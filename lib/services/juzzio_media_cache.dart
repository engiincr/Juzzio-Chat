// =============================================================================
// JUZZIO v0.9.2 — Çevrimdışı medya önbelleği (WhatsApp benzeri)
//  * Görüntülenen fotoğraf, profil resmi ve sesli mesajlar cihazda saklanır; internet
//    yokken aynı dosyadan gösterilir/oynatılır.
//  * Konum: <uygulama destek klasörü>/juzzio_cache/<kullanıcı>/media — hesaba özeldir,
//    oturum kapatılınca (clearLocalCacheForCurrentUser) birlikte silinir.
//  * Anahtar: Storage nesnesinin KİMLİĞİ (bucket/yol) — imzalı adresin değişen token'ı
//    aynı dosyaya düşer. Dış adreslerde tam adres.
//  * Uçtan uca şifreli fotoğraflar diske ŞİFRELİ hâliyle yazılır (çözme bellekte).
//  * Sınır: 300 MB; aşılınca en eski kullanılanlar silinerek 240 MB'a inilir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import 'juzzio_media_url.dart';

class JuzzioMediaDiskCache {
  JuzzioMediaDiskCache._();
  static final JuzzioMediaDiskCache instance = JuzzioMediaDiskCache._();

  static const int maxBytes = 300 * 1024 * 1024;
  static const int pruneTarget = 240 * 1024 * 1024;
  static const int maxItemBytes = 30 * 1024 * 1024;

  Directory? _dir;
  String _owner = '';
  int _writesSincePrune = 0;
  final Map<String, Future<File?>> _inFlight = {};

  /// Önbellek anahtarı (test edilebilir, saf).
  static String keyFor(String url) {
    final ref = JuzzioMediaUrl.parse(url);
    final canonical = ref != null ? '${ref.bucket}/${ref.path}' : url.split('#').first;
    return sha256Hex(canonical);
  }

  static String sha256Hex(String s) =>
      const DartSha256().hashSync(utf8.encode(s)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Oturum açan kullanıcının klasörünü hazırlar. Kullanıcı değişince klasör de değişir.
  Future<void> init(String? userId) async {
    final uid = (userId ?? '').trim();
    if (uid.isEmpty) {
      _dir = null;
      _owner = '';
      return;
    }
    if (uid == _owner && _dir != null) return;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/juzzio_cache/$uid/media');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
      _owner = uid;
    } catch (_) {
      _dir = null;
      _owner = '';
    }
  }

  /// Önbellekte varsa dosyayı HEMEN döndürür (ağ yok); yoksa null.
  File? cachedFile(String url) {
    final d = _dir;
    if (d == null || url.isEmpty) return null;
    final f = File('${d.path}/${keyFor(url)}');
    try {
      return f.existsSync() && f.lengthSync() > 0 ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Önbellekten ya da ağdan (indirip saklayarak) dosya. Ulaşılamazsa null.
  /// [resolvedUrl] verilirse o adresten indirilir (önceden imzalanmış adres).
  Future<File?> loadFile(String url, {String? resolvedUrl}) {
    final hit = cachedFile(url);
    if (hit != null) {
      _touch(hit);
      return Future.value(hit);
    }
    final k = keyFor(url);
    return _inFlight[k] ??= _download(url, k, resolvedUrl).whenComplete(() {
      _inFlight.remove(k);
    });
  }

  Future<Uint8List?> loadBytes(String url, {String? resolvedUrl}) async {
    final f = await loadFile(url, resolvedUrl: resolvedUrl);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<File?> _download(String url, String key, String? resolvedUrl) async {
    try {
      final target = resolvedUrl ?? await JuzzioMediaUrl.resolve(url);
      // Zaman aşımı dart:io bağlantı düzeyinde (test ortamında bekleyen Timer bırakmaz)
      final client = IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 20));
      final http.Response res;
      try {
        res = await client.get(Uri.parse(target));
      } finally {
        client.close();
      }
      if (res.statusCode != 200 || res.bodyBytes.isEmpty || res.bodyBytes.length > maxItemBytes) return null;
      final d = _dir;
      if (d == null) {
        // Klasör yoksa (oturum yok / test) yalnız geçici dosya: yine de gösterilebilsin
        final tmp = File('${Directory.systemTemp.path}/juzzio_media_$key');
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        return tmp;
      }
      final f = File('${d.path}/$key');
      final part = File('${f.path}.part');
      await part.writeAsBytes(res.bodyBytes, flush: true);
      await part.rename(f.path);
      if (++_writesSincePrune >= 20) {
        _writesSincePrune = 0;
        unawaited(prune());
      }
      return f;
    } catch (_) {
      return null;
    }
  }

  void _touch(File f) {
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  Future<int> sizeBytes() async {
    final d = _dir;
    if (d == null || !d.existsSync()) return 0;
    var sum = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is File) {
        try {
          sum += e.lengthSync();
        } catch (_) {}
      }
    }
    return sum;
  }

  /// En eski kullanılan dosyalardan başlayarak sınırın altına iner.
  Future<void> prune({int limit = maxBytes, int target = pruneTarget}) async {
    final d = _dir;
    if (d == null || !d.existsSync()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is! File) continue;
      try {
        final len = e.lengthSync();
        total += len;
        files.add((e, len, e.lastModifiedSync()));
      } catch (_) {}
    }
    if (total <= limit) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final f in files) {
      if (total <= target) break;
      try {
        f.$1.deleteSync();
        total -= f.$2;
      } catch (_) {}
    }
  }

  /// Yalnız medya önbelleğini siler (mesajlar, anahtarlar, hesap verisi silinmez).
  Future<int> clear() async {
    final d = _dir;
    if (d == null || !d.existsSync()) return 0;
    final freed = await sizeBytes();
    try {
      for (final e in d.listSync(followLinks: false)) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }
}

/// Çevrimdışı çalışan görsel sağlayıcı: önce disk önbelleği, yoksa indirip saklar.
@immutable
class JuzzioCachedImageProvider extends ImageProvider<JuzzioCachedImageProvider> {
  const JuzzioCachedImageProvider(this.url, {this.resolvedUrl, this.scale = 1.0});

  final String url;
  final String? resolvedUrl;
  final double scale;

  @override
  Future<JuzzioCachedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<JuzzioCachedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(JuzzioCachedImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: key.scale);

  static Future<ui.Codec> _load(JuzzioCachedImageProvider key, ImageDecoderCallback decode) async {
    final bytes = await JuzzioMediaDiskCache.instance.loadBytes(key.url, resolvedUrl: key.resolvedUrl);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('juzzio_image_unavailable');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  // Aynı nesne kimliği → aynı görsel (imzalı adres token'ı farklı olsa bile)
  @override
  bool operator ==(Object other) =>
      other is JuzzioCachedImageProvider && JuzzioMediaDiskCache.keyFor(other.url) == JuzzioMediaDiskCache.keyFor(url) && other.scale == scale;

  @override
  int get hashCode => Object.hash(JuzzioMediaDiskCache.keyFor(url), scale);
}
