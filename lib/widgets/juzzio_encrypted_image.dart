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
import '../services/juzzio_media_crypto.dart';
import '../services/juzzio_media_cache.dart';
import '../services/supabase_service.dart';

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
}

class JuzzioEncryptedImage extends StatelessWidget {
  const JuzzioEncryptedImage({super.key, required this.messageId, required this.url, this.height, this.fit = BoxFit.cover});
  final String messageId;
  final String url;
  final double? height;
  final BoxFit fit;

  static Future<void> openFullScreen(BuildContext context, {required String messageId, required String url}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(child: InteractiveViewer(child: JuzzioEncryptedImage(messageId: messageId, url: url, fit: BoxFit.contain))),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return FutureBuilder<Uint8List?>(
      future: JuzzioEncryptedMedia.load(messageId, url),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return SizedBox(
            height: height ?? 120,
            child: Center(
              child: Semantics(
                label: app.trEn('Şifreli fotoğraf açılamadı', 'Encrypted photo could not be opened', 'Verschlüsseltes Foto nicht lesbar'),
                child: const Icon(Icons.lock_rounded, size: 36, color: Colors.grey),
              ),
            ),
          );
        }
        return Image.memory(bytes, height: height, width: double.infinity, fit: fit, gaplessPlayback: true,
            semanticLabel: app.trEn('Uçtan uca şifreli fotoğraf', 'End-to-end encrypted photo', 'Ende-zu-Ende-verschlüsseltes Foto'));
      },
    );
  }
}
