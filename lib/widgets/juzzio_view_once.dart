// =============================================================================
// JUZZIO v0.9.5 — Tek seferlik fotoğraf / video
//  • Alıcı bir kez açar; kapattığı an adres silinir ve dosya buluttan kalıcı temizlenir
//    (finish_view_once + depolama temizlik kuyruğu). Açılıp kapatılmazsa 5 dk sonra sunucu siler.
//  • Görüntülerken ekran görüntüsü/kayıt engellenir (Android FLAG_SECURE).
//  • Gönderen kendi tek seferlik medyasını açamaz; yalnız "açıldı / açılmadı" görür.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_media_cache.dart';
import '../services/juzzio_media_url.dart';
import '../services/supabase_service.dart';
import 'juzzio_encrypted_image.dart';

const MethodChannel _kSecureChannel = MethodChannel('juzzio/notifications');

Future<void> _setSecure(bool on) async {
  try {
    await _kSecureChannel.invokeMethod('setSecureScreen', {'secure': on});
  } catch (_) {}
}

class JuzzioViewOnceBubble extends StatefulWidget {
  const JuzzioViewOnceBubble({super.key, required this.message, required this.isMe});
  final JuzzioMessage message;
  final bool isMe;

  @override
  State<JuzzioViewOnceBubble> createState() => _JuzzioViewOnceBubbleState();
}

class _JuzzioViewOnceBubbleState extends State<JuzzioViewOnceBubble> {
  bool _busy = false;
  bool _openedLocally = false;

  bool get _opened =>
      _openedLocally || widget.message.viewOnceOpenedAt != null || ((widget.message.imageUrl ?? '').isEmpty && (widget.message.videoUrl ?? '').isEmpty);

  Future<void> _open() async {
    if (_busy || widget.isMe || _opened) return;
    final app = JuzzioAppController.instance;
    setState(() => _busy = true);
    try {
      final r = await SupabaseService.instance.client.rpc('open_view_once', params: {'p_message': widget.message.id});
      final m = Map<String, dynamic>.from(r as Map);
      final img = (m['image_url'] ?? '').toString();
      final vid = (m['video_url'] ?? '').toString();
      Uint8List? bytes;
      if (img.isNotEmpty && JuzzioEncryptedMedia.isEncrypted(widget.message.metadata)) {
        bytes = await JuzzioEncryptedMedia.load(widget.message.id, img, keepInMemory: false);
      }
      if (!mounted) return;
      setState(() => _openedLocally = true);
      await _setSecure(true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ViewOncePage(imageUrl: img, videoUrl: vid, bytes: bytes),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(e.toString().contains('view_once_already_opened')
              ? app.trEn('Bu medya zaten açıldı.', 'This media was already opened.', 'Bereits geöffnet.')
              : SupabaseService.instance.friendlyError(e)),
        ));
      }
    } finally {
      await _setSecure(false);
      try {
        await SupabaseService.instance.client.rpc('finish_view_once', params: {'p_message': widget.message.id});
      } catch (_) {}
      final u = widget.message.imageUrl ?? widget.message.videoUrl;
      if (u != null) {
        try {
          JuzzioMediaDiskCache.instance.cachedFile(u)?.deleteSync();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    final fg = widget.isMe ? Colors.white : p.textPrimary;
    final isVideo = (widget.message.videoUrl ?? '').isNotEmpty || widget.message.messageType == 'video';
    final label = widget.isMe
        ? (_opened ? app.trEn('Açıldı', 'Opened', 'Geöffnet') : app.trEn('Tek seferlik · henüz açılmadı', 'View once · not opened yet', 'Einmalig · ungeöffnet'))
        : (_opened
            ? app.trEn('Açıldı', 'Opened', 'Geöffnet')
            : (isVideo ? app.trEn('Tek seferlik video · aç', 'View-once video · open', 'Einmal-Video öffnen') : app.trEn('Tek seferlik fotoğraf · aç', 'View-once photo · open', 'Einmal-Foto öffnen')));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _busy
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : Icon(_opened ? Icons.radio_button_unchecked_rounded : Icons.looks_one_rounded, color: fg),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _ViewOncePage extends StatefulWidget {
  const _ViewOncePage({required this.imageUrl, required this.videoUrl, required this.bytes});
  final String imageUrl;
  final String videoUrl;
  final Uint8List? bytes;

  @override
  State<_ViewOncePage> createState() => _ViewOncePageState();
}

class _ViewOncePageState extends State<_ViewOncePage> {
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl.isNotEmpty) _initVideo();
  }

  Future<void> _initVideo() async {
    final url = await JuzzioMediaUrl.resolve(widget.videoUrl);
    final vc = VideoPlayerController.networkUrl(Uri.parse(url));
    _vc = vc;
    try {
      await vc.initialize();
      await vc.play();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (widget.bytes != null) {
      body = InteractiveViewer(child: Image.memory(widget.bytes!, fit: BoxFit.contain, gaplessPlayback: true));
    } else if (widget.imageUrl.isNotEmpty) {
      body = InteractiveViewer(
        child: FutureBuilder<String>(
          future: JuzzioMediaUrl.resolve(widget.imageUrl),
          builder: (_, s) => s.hasData ? Image.network(s.data!, fit: BoxFit.contain) : const CircularProgressIndicator(),
        ),
      );
    } else {
      final vc = _vc;
      body = vc != null && vc.value.isInitialized
          ? AspectRatio(aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc))
          : const CircularProgressIndicator();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(JuzzioAppController.instance.trEn('Tek seferlik', 'View once', 'Einmalig')),
      ),
      body: Center(child: body),
    );
  }
}

/// v0.9.6: uçtan uca şifreli video — dokununca cihazda çözülür, geçici dosyadan oynatılır.
class JuzzioEncryptedVideoTile extends StatefulWidget {
  const JuzzioEncryptedVideoTile({super.key, required this.messageId, required this.url, required this.isMe});
  final String messageId;
  final String url;
  final bool isMe;

  @override
  State<JuzzioEncryptedVideoTile> createState() => _JuzzioEncryptedVideoTileState();
}

class _JuzzioEncryptedVideoTileState extends State<JuzzioEncryptedVideoTile> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await JuzzioEncryptedMedia.load(widget.messageId, widget.url, keepInMemory: false);
      if (bytes == null) throw Exception('decrypt_failed');
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/jv_${widget.messageId}.mp4');
      if (!f.existsSync()) await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _LocalVideoPage(file: f)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(JuzzioAppController.instance.trEn('Video çözülemedi.', 'The video could not be decrypted.', 'Video konnte nicht entschlüsselt werden.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      child: Container(
        height: 150,
        width: 220,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: _busy
            ? const CircularProgressIndicator(color: Colors.white)
            : const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 54),
                SizedBox(height: 4),
                Text('🔒', style: TextStyle(color: Colors.white70)),
              ]),
      ),
    );
  }
}

class _LocalVideoPage extends StatefulWidget {
  const _LocalVideoPage({required this.file});
  final File file;

  @override
  State<_LocalVideoPage> createState() => _LocalVideoPageState();
}

class _LocalVideoPageState extends State<_LocalVideoPage> {
  late final VideoPlayerController _vc = VideoPlayerController.file(widget.file);

  @override
  void initState() {
    super.initState();
    _vc.initialize().then((_) {
      if (mounted) setState(() {});
      _vc.play();
    });
  }

  @override
  void dispose() {
    _vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: _vc.value.isInitialized
              ? GestureDetector(
                  onTap: () => setState(() => _vc.value.isPlaying ? _vc.pause() : _vc.play()),
                  child: AspectRatio(aspectRatio: _vc.value.aspectRatio, child: VideoPlayer(_vc)),
                )
              : const CircularProgressIndicator(),
        ),
      );
}
