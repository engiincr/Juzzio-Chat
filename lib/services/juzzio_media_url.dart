// =============================================================================
// JUZZIO v0.9.0 — Özel medya erişimi (denetim bulgusu C, P0/P1)
//
// chat-media, voice-notes, stories, posts ve reels bucket'ları artık ÖZELDİR. Veritabanında
// saklanan "…/storage/v1/object/public/<bucket>/<yol>" adresi yalnızca bir KİMLİKTİR;
// görüntülerken kısa ömürlü imzalı URL'ye çevrilir (createSignedUrl). İmza isteği Storage
// RLS'inden geçer: oda üyeliği, hikâye/gönderi görünürlüğü, engel ve süre dolumu sunucuda
// denetlenir. İmzalı URL'ler bellekte, süresi dolmadan 5 dk öncesine kadar önbelleklenir ve
// ASLA günlüğe/kalıcı depoya yazılmaz.
//
// avatars bucket'ı ürün gereği herkese açık kaldığından avatar adresleri olduğu gibi kullanılır.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Depolama URL'sinin ayrıştırılmış hâli.
class JuzzioStorageRef {
  const JuzzioStorageRef(this.bucket, this.path);
  final String bucket;
  final String path;
}

class JuzzioMediaUrl {
  JuzzioMediaUrl._();

  /// Özel (imza gerektiren) bucket'lar.
  static const Set<String> privateBuckets = {'chat-media', 'voice-notes', 'stories', 'posts', 'reels'};

  /// İmzalı URL ömrü. Kısa tutulur; önbellek süresi dolmadan yeniler.
  static const Duration signedTtl = Duration(hours: 1);
  static const Duration _refreshMargin = Duration(minutes: 5);

  static final RegExp _storageRe =
      RegExp(r'/storage/v1/object/(public|sign|authenticated)/([a-z0-9-]+)/([^?#]+)');
  static final Map<String, _SignedEntry> _cache = <String, _SignedEntry>{};
  static final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  /// Test ve önizleme ortamında imzalayıcı değiştirilebilir (varsayılan: Supabase Storage).
  static Future<String> Function(String bucket, String path, int expiresInSeconds)? signerOverride;

  /// URL bir Juzzio Storage nesnesine mi işaret ediyor? Değilse null.
  static JuzzioStorageRef? parse(String? url) {
    if (url == null || url.isEmpty) return null;
    final m = _storageRe.firstMatch(url);
    if (m == null) return null;
    String path;
    try {
      path = Uri.decodeComponent(m.group(3)!);
    } catch (_) {
      return null;
    }
    if (path.isEmpty || path.contains('..') || path.startsWith('/')) return null;
    return JuzzioStorageRef(m.group(2)!, path);
  }

  /// Bu adres imzalanmadan görüntülenemez mi?
  static bool needsSigning(String? url) {
    final ref = parse(url);
    return ref != null && privateBuckets.contains(ref.bucket);
  }

  /// Önbellekte geçerli imzalı adres varsa hemen döner (yoksa null).
  static String? cachedSigned(String url) {
    final e = _cache[url];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiresAt.subtract(_refreshMargin))) {
      _cache.remove(url);
      return null;
    }
    return e.signedUrl;
  }

  /// Görüntülenebilir adres: özel nesne için imzalı URL, diğerleri için aynı adres.
  /// İmzalama başarısızsa istisna fırlatır (yetki yok, nesne silinmiş, ağ hatası).
  static Future<String> resolve(String url) {
    final ref = parse(url);
    if (ref == null || !privateBuckets.contains(ref.bucket)) return Future<String>.value(url);
    final cached = cachedSigned(url);
    if (cached != null) return Future<String>.value(cached);
    final pending = _inFlight[url];
    if (pending != null) return pending;
    final future = _sign(ref).then((signed) {
      _cache[url] = _SignedEntry(signed, DateTime.now().add(signedTtl));
      if (_cache.length > 600) _cache.remove(_cache.keys.first);
      return signed;
    }).whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  /// Hata durumunda özgün adresi döndüren güvenli sürüm (eski/herkese açık nesneler için).
  static Future<String> resolveOrOriginal(String url) async {
    try {
      return await resolve(url);
    } catch (_) {
      return url;
    }
  }

  static Future<String> _sign(JuzzioStorageRef ref) {
    final override = signerOverride;
    if (override != null) return override(ref.bucket, ref.path, signedTtl.inSeconds);
    return Supabase.instance.client.storage.from(ref.bucket).createSignedUrl(ref.path, signedTtl.inSeconds);
  }

  /// Oturum kapanınca / hesap değişince imzalı adresler unutulur.
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}

class _SignedEntry {
  _SignedEntry(this.signedUrl, this.expiresAt);
  final String signedUrl;
  final DateTime expiresAt;
}

/// `Image.network` yerine geçen, özel Storage nesnelerini otomatik imzalayan görsel.
/// İmza gerekmeyen adreslerde doğrudan `Image.network` ile birebir aynı davranır.
class JuzzioStorageImage extends StatefulWidget {
  const JuzzioStorageImage(
    this.src, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.loadingBuilder,
    this.errorBuilder,
    this.cacheWidth,
    this.cacheHeight,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
  });

  final String src;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final int? cacheWidth;
  final int? cacheHeight;
  final bool gaplessPlayback;
  final FilterQuality filterQuality;
  final String? semanticLabel;

  @override
  State<JuzzioStorageImage> createState() => _JuzzioStorageImageState();
}

class _JuzzioStorageImageState extends State<JuzzioStorageImage> {
  String? _resolved;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant JuzzioStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) _start();
  }

  void _start() {
    final gen = ++_generation;
    _error = null;
    if (!JuzzioMediaUrl.needsSigning(widget.src)) {
      _resolved = widget.src;
      return;
    }
    _resolved = JuzzioMediaUrl.cachedSigned(widget.src);
    if (_resolved != null) return;
    JuzzioMediaUrl.resolve(widget.src).then((signed) {
      if (!mounted || gen != _generation) return;
      setState(() => _resolved = signed);
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (_error != null) {
      final eb = widget.errorBuilder;
      if (eb != null) return eb(context, _error!, null);
      return SizedBox(width: widget.width, height: widget.height);
    }
    if (resolved == null) {
      final lb = widget.loadingBuilder;
      final placeholder = SizedBox(width: widget.width, height: widget.height);
      if (lb != null) {
        return lb(context, placeholder, const ImageChunkEvent(cumulativeBytesLoaded: 0, expectedTotalBytes: null));
      }
      return placeholder;
    }
    return Image.network(
      resolved,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      gaplessPlayback: widget.gaplessPlayback,
      filterQuality: widget.filterQuality,
      semanticLabel: widget.semanticLabel,
    );
  }
}
