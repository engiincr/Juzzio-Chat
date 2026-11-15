// =============================================================================
// JUZZIO v0.9.0 — G23/G24 şifreli fotoğraf görüntüleyici
//  Şifreli bayt imzalı URL ile indirilir, cihazda SHA-256 + AES-GCM doğrulanarak açılır.
//  Anahtar yoksa / doğrulama tutmazsa kilit simgesi gösterilir (ham veri asla gösterilmez).
//  Diskte yalnız ŞİFRELİ bayt saklanır (çevrimdışı); açılmış görsel yalnız bellekte (en fazla 40).
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_e2ee.dart';
import '../services/juzzio_gallery_saver.dart' show JuzzioDownloadAction;
import '../services/juzzio_media_crypto.dart';
import '../services/juzzio_media_cache.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

class JuzzioEncryptedMedia {
  JuzzioEncryptedMedia._();
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static bool isEncrypted(Map<String, dynamic> metadata) => metadata['media_e2ee'] != null && metadata['e2ee'] is Map;

  static Future<Uint8List?> load(String messageId, String url, {bool keepInMemory = true}) {
    // Önbellek anahtarı hesaba bağlıdır: hesap değişince başka hesabın görselleri dönmez
    final ck = '${SupabaseService.instance.currentUserId ?? ''}|$messageId';
    // v0.9.4: büyük belgeler bellekte tutulmaz (25 MB × 40 bellek taşmasını önler)
    if (!keepInMemory) return _load(ck, messageId, url, keep: false);
    final hit = _cache[ck];
    if (hit != null) return Future.value(hit);
    return _inFlight[ck] ??= _load(ck, messageId, url).whenComplete(() {
      _inFlight.remove(ck);
    });
  }

  static Future<Uint8List?> _load(String ck, String messageId, String url, {bool keep = true}) async {
    final key = JuzzioE2ee.instance.mediaKeyFor(messageId);
    if (key == null) return null;
    try {
      // v0.9.2: şifreli bayt diskte saklanır (çevrimdışı görüntüleme); çözme yalnız bellekte
      final cipher = await JuzzioMediaDiskCache.instance.loadBytes(url);
      if (cipher == null) return null;
      final out = await JuzzioMediaCrypto.open(cipher, key);
      if (out == null) return null;
      if (!keep) return out;
      if (_cache.length >= 40) _cache.remove(_cache.keys.first);
      _cache[ck] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  static void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  /// v1.2.8: bellekte açılmış hâli varsa HEMEN döndürür (çizimde yükleme karesi olmaz)
  static Uint8List? peek(String messageId) => _cache['${SupabaseService.instance.currentUserId ?? ''}|$messageId'];

  /// v1.2.8: gönderen kendi gönderdiği medyanın açık hâlini zaten bilir → yeniden indirip
  /// çözmeden gösterilir (titreme yok, gereksiz veri trafiği yok)
  static void seed(String messageId, Uint8List bytes) {
    final ck = '${SupabaseService.instance.currentUserId ?? ''}|$messageId';
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[ck] = bytes;
  }
}

class JuzzioEncryptedImage extends StatefulWidget {
  const JuzzioEncryptedImage({super.key, required this.messageId, required this.url, this.height, this.fit = BoxFit.cover});
  final String messageId;
  final String url;
  final double? height;
  final BoxFit fit;

  /// v1.1.0: yakınlaşma geçişi (#03 Zoom) + paylaşılan öğe (#09 Hero)
  static Future<void> openFullScreen(BuildContext context, {required String messageId, required String url, String? heroTag, Rect? origin}) =>
      Navigator.of(context).push(JuzzioZoomRoute<void>(
        origin: origin,
        builder: (_) {
          final img = JuzzioEncryptedImage(messageId: messageId, url: url, fit: BoxFit.contain);
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, actions: [
              // v1.2.8: sağ üstte indir
              JuzzioDownloadAction(url: url, isVideo: false, messageId: messageId, encrypted: true),
            ]),
            body: Center(child: InteractiveViewer(child: heroTag == null ? img : Hero(tag: heroTag, child: img))),
          );
        },
      ));

  @override
  State<JuzzioEncryptedImage> createState() => _JuzzioEncryptedImageState();
}

/// v1.2.8: durum bilgili — yükleme işi bir kez başlar; önbellekteyse ilk karede görünür.
/// (Önceden her yeniden çizimde yeni bir Future oluşuyor, sohbet her güncellendiğinde
/// fotoğraf bir an "yükleniyor"a dönüp titriyordu.)
class _JuzzioEncryptedImageState extends State<JuzzioEncryptedImage> {
  Uint8List? _bytes;
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void didUpdateWidget(covariant JuzzioEncryptedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId || oldWidget.url != widget.url) _prime();
  }

  void _prime() {
    _bytes = JuzzioEncryptedMedia.peek(widget.messageId);
    _future = _bytes == null ? JuzzioEncryptedMedia.load(widget.messageId, widget.url) : null;
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final ready = _bytes;
    if (ready != null) return _image(app, ready);
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: widget.height ?? 190, width: widget.height == null ? 220 : null, child: const Center(child: JuzzioOrbitLoader()));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return SizedBox(
            height: widget.height ?? 120,
            child: Center(
              child: Semantics(
                label: app.trEn('Şifreli fotoğraf açılamadı', 'Encrypted photo could not be opened', 'Verschlüsseltes Foto nicht lesbar'),
                child: const Icon(Icons.lock_rounded, size: 36, color: Colors.grey),
              ),
            ),
          );
        }
        _bytes = bytes;
        return _image(app, bytes);
      },
    );
  }

  // yükseklik verilmezse görsel kendi oranında (kırpılmadan) yerleşir
  Widget _image(JuzzioAppController app, Uint8List bytes) => Image.memory(bytes,
      height: widget.height, width: widget.height == null ? null : double.infinity, fit: widget.fit, gaplessPlayback: true,
      semanticLabel: app.trEn('Uçtan uca şifreli fotoğraf', 'End-to-end encrypted photo', 'Ende-zu-Ende-verschlüsseltes Foto'));
}
