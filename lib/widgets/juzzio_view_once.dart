// =============================================================================
// JUZZIO v0.9.5 — Tek seferlik fotoğraf / video
//  • Alıcı bir kez açar; kapattığı an adres silinir ve dosya buluttan kalıcı temizlenir
//    (finish_view_once + depolama temizlik kuyruğu). Açılıp kapatılmazsa 5 dk sonra sunucu siler.
//  • Görüntülerken ekran görüntüsü/kayıt engellenir (Android FLAG_SECURE).
//  • Gönderen kendi tek seferlik medyasını açamaz; yalnız "açıldı / açılmadı" görür.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_media_cache.dart';
import '../services/juzzio_media_url.dart';
import '../services/supabase_service.dart';
import 'juzzio_encrypted_image.dart';
import 'juzzio_motion.dart';

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
    final isVideo = (widget.message.videoUrl ?? '').isNotEmpty || widget.message.messageType == 'video';
    // v1.2.0: açıldıktan sonra soluk, kompakt "Açıldı" durumu — bir daha açılamaz
    if (_opened) return _openedPill(app, isVideo);
    final hint = widget.isMe
        ? app.trEn('Henüz açılmadı', 'Not opened yet', 'Noch nicht geöffnet')
        : app.trEn('Görmek için dokun', 'Tap to view', 'Zum Ansehen tippen');
    // v1.2.0: bulanık önizleme + cam "Tek görüntülemelik" etiketi + cam bomba simgesi.
    // Gerçek medya açılmadan İNDİRİLMEZ; önizleme mesaj kimliğinden üretilen soyut bir bulanık desendir.
    return GestureDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 230,
          height: 172,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.decal),
                child: CustomPaint(painter: _BlurBlobsPainter(seed: widget.message.id.hashCode)),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x14000000), Color(0x66000000)],
                  ),
                ),
              ),
              Center(
                child: _busy
                    ? const SizedBox(width: 46, height: 46, child: JuzzioOrbitLoader(strokeWidth: 2.4, color: Colors.white))
                    : _glass(
                        radius: 99,
                        padding: const EdgeInsets.all(12),
                        child: const SizedBox(width: 34, height: 34, child: CustomPaint(painter: _BombPainter())),
                      ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _glass(
                  radius: 99,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isVideo ? Icons.videocam_rounded : Icons.photo_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(app.trEn('Tek görüntülemelik', 'View once', 'Einmal ansehen'),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Text(hint,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, shadows: [Shadow(color: Color(0x88000000), blurRadius: 6)])),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glass({required Widget child, required double radius, required EdgeInsets padding}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0x59FFFFFF)),
            ),
            child: child,
          ),
        ),
      );

  Widget _openedPill(JuzzioAppController app, bool isVideo) {
    final p = JuzzioPalette(app.isDark);
    final fg = widget.isMe ? Colors.white70 : p.textSecondary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: (widget.isMe ? Colors.white : p.textPrimary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: 0.6), width: 1.4)),
          child: Icon(Icons.visibility_off_rounded, size: 15, color: fg),
        ),
        const SizedBox(width: 9),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(app.trEn('Açıldı', 'Opened', 'Geöffnet'), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13.5)),
          Text(
            isVideo ? app.trEn('Tek görüntülemelik video', 'View-once video', 'Einmal-Video') : app.trEn('Tek görüntülemelik fotoğraf', 'View-once photo', 'Einmal-Foto'),
            style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11.5),
          ),
        ]),
      ]),
    );
  }
}

/// Mesaj kimliğinden üretilen soyut renk lekeleri (bulanıklaştırılınca "fotoğraf" hissi verir)
class _BlurBlobsPainter extends CustomPainter {
  const _BlurBlobsPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    canvas.drawRect(Offset.zero & size, Paint()..color = HSLColor.fromAHSL(1, rnd.nextDouble() * 360, 0.45, 0.30).toColor());
    for (var i = 0; i < 7; i++) {
      final c = HSLColor.fromAHSL(1, rnd.nextDouble() * 360, 0.55 + rnd.nextDouble() * 0.3, 0.45 + rnd.nextDouble() * 0.25).toColor();
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        size.shortestSide * (0.18 + rnd.nextDouble() * 0.32),
        Paint()..color = c.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlurBlobsPainter old) => old.seed != seed;
}

/// Cam bomba simgesi (gövde + fitil + kıvılcım)
class _BombPainter extends CustomPainter {
  const _BombPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final body = Offset(s * 0.44, s * 0.58);
    final r = s * 0.34;
    canvas.drawCircle(body, r, Paint()..color = const Color(0xF2FFFFFF));
    canvas.drawCircle(body + Offset(-r * 0.35, -r * 0.35), r * 0.22, Paint()..color = const Color(0x40000000));
    final cap = Rect.fromCenter(center: body + Offset(r * 0.62, -r * 0.62), width: s * 0.2, height: s * 0.14);
    canvas.save();
    canvas.translate(cap.center.dx, cap.center.dy);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: cap.width, height: cap.height), const Radius.circular(2)),
        Paint()..color = const Color(0xF2FFFFFF));
    canvas.restore();
    final fuse = Path()
      ..moveTo(cap.center.dx + s * 0.05, cap.center.dy - s * 0.05)
      ..quadraticBezierTo(s * 0.86, s * 0.06, s * 0.94, s * 0.16);
    canvas.drawPath(
      fuse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xE6FFFFFF),
    );
    final spark = Offset(s * 0.94, s * 0.14);
    canvas.drawCircle(spark, s * 0.09, Paint()..color = const Color(0xFFFFD45C)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawCircle(spark, s * 0.045, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _BombPainter old) => false;
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
          builder: (_, s) => s.hasData ? Image.network(s.data!, fit: BoxFit.contain) : const JuzzioOrbitLoader(),
        ),
      );
    } else {
      final vc = _vc;
      body = vc != null && vc.value.isInitialized
          ? AspectRatio(aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc))
          : const JuzzioOrbitLoader();
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
            ? const JuzzioOrbitLoader(color: Colors.white)
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
              : const JuzzioOrbitLoader(),
        ),
      );
}
