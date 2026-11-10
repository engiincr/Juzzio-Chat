// =============================================================================
// JUZZIO v1.2.4 — Sohbet medyasını galeriye otomatik kaydet (varsayılan açık)
//  • Gelen fotoğraf → Resimler/Juzzio, video → Filmler/Juzzio, belge → İndirilenler/Juzzio.
//  • Kaydedilirken dosya aynı zamanda uygulamanın çevrimdışı önbelleğine iner: sohbetteki
//    medya internet yokken de açılır/oynatılır.
//  • Tek görüntülemelik (view-once) medya ASLA kaydedilmez. Uçtan uca şifreli medya cihazda
//    çözülür; çözülmüş geçici dosya kayıttan hemen sonra silinir.
//  • Aynı mesaj iki kez kaydedilmez (kaydedilen kimlikler hesaba özel önbellekte tutulur).
//  • Ayar: Ayarlar → Sohbetler → "Medyayı galeriye kaydet".
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/app_theme_and_locale.dart';
import '../core/native_bridge.dart';
import '../widgets/juzzio_encrypted_image.dart' show JuzzioEncryptedMedia;
import 'juzzio_media_cache.dart';
import 'supabase_service.dart';

/// Mesajdaki kaydedilebilir medya (saf; test edilir). Kaydedilecek bir şey yoksa null.
({String url, String kind, String mime, String name})? juzzioGalleryTarget(JuzzioMessage m) {
  if (m.isViewOnce || m.isDeleted) return null;
  String ext(String url, String fallback) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final e = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(e) ? e : fallback;
  }

  final img = m.imageUrl;
  if (img != null && img.isNotEmpty) {
    final e = ext(img, 'jpg');
    final mime = e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : (e == 'gif' ? 'image/gif' : 'image/jpeg'));
    return (url: img, kind: 'image', mime: mime, name: 'Juzzio_${m.id.length > 8 ? m.id.substring(0, 8) : m.id}.$e');
  }
  final vid = m.videoUrl;
  if (vid != null && vid.isNotEmpty) {
    final e = ext(vid, 'mp4');
    return (url: vid, kind: 'video', mime: e == 'webm' ? 'video/webm' : (e == 'mov' ? 'video/quicktime' : 'video/mp4'),
        name: 'Juzzio_${m.id.length > 8 ? m.id.substring(0, 8) : m.id}.$e');
  }
  final doc = m.documentUrl;
  if (doc != null && doc.isNotEmpty) {
    final raw = (m.documentName ?? '').trim();
    final name = raw.isEmpty ? 'Juzzio_${m.id.length > 8 ? m.id.substring(0, 8) : m.id}.${ext(doc, 'bin')}' : raw;
    final e = ext(name, 'bin');
    const mimes = {
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'zip': 'application/zip',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    };
    return (url: doc, kind: 'document', mime: mimes[e] ?? 'application/octet-stream', name: name);
  }
  return null;
}

class JuzzioGallerySaver {
  JuzzioGallerySaver._();
  static final JuzzioGallerySaver instance = JuzzioGallerySaver._();

  static const String _cacheName = 'gallery_saved_ids';
  Set<String>? _saved;
  final Set<String> _inFlight = <String>{};
  Future<void> _chain = Future<void>.value();

  Future<Set<String>> _load() async {
    if (_saved != null) return _saved!;
    try {
      final raw = await SupabaseService.instance.readLocalCache(_cacheName);
      _saved = raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
    } catch (_) {
      _saved = <String>{};
    }
    return _saved!;
  }

  /// Gelen mesajı (ayar açıksa) arka planda galeriye kaydeder. Sıralı çalışır (aynı anda tek dosya).
  void handleIncoming(JuzzioMessage m) {
    if (!JuzzioAppController.instance.autoSaveMedia) return;
    if (m.senderId == SupabaseService.instance.currentUserId) return;
    final t = juzzioGalleryTarget(m);
    if (t == null || !_inFlight.add(m.id)) return;
    _chain = _chain.then((_) => _save(m, t)).then((_) {}, onError: (_) {}).whenComplete(() {
      _inFlight.remove(m.id);
    });
  }

  Future<bool> _save(JuzzioMessage m, ({String url, String kind, String mime, String name}) t) async {
    final saved = await _load();
    if (saved.contains(m.id)) return true;
    File? tmp;
    try {
      String? path;
      if (JuzzioEncryptedMedia.isEncrypted(m.metadata)) {
        final bytes = await JuzzioEncryptedMedia.load(m.id, t.url, keepInMemory: false);
        if (bytes == null) return false;
        final dir = await getTemporaryDirectory();
        tmp = File('${dir.path}/jgs_${m.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}');
        await tmp.writeAsBytes(bytes, flush: true);
        path = tmp.path;
      } else {
        final f = await JuzzioMediaDiskCache.instance.loadFile(t.url);
        path = f?.path;
      }
      if (path == null) return false;
      final ok = await JuzzioNative.saveToGallery(path: path, mime: t.mime, name: t.name, kind: t.kind);
      if (ok) {
        saved.add(m.id);
        final list = saved.toList();
        await SupabaseService.instance.writeLocalCache(_cacheName, list.length > 3000 ? list.sublist(list.length - 3000) : list);
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      if (tmp != null) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }
}
