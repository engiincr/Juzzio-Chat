// =============================================================================
// JUZZIO v1.2.4 — Yapımcı Tanıtım İçeriği (Portfolyo videosu)
//  "Hello" ile başlayan, Engin ÇIRPAN'ı ve Juzzio'yu anlatan 26 sn'lik tanıtım videosu.
//  Video uygulamaya gömülüdür (assets/creator/juzzio_creator_reel.mp4) → internet gerekmez.
//  Dokun: duraklat/oynat · alttaki çubuk: ilerleme · bitince "Tekrar izle".
//  Kaynak: tools/creator_reel/reel.py (kareler kodla çizilir, ffmpeg ile kodlanır).
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme_and_locale.dart';

const String kJuzzioCreatorReelAsset = 'assets/creator/juzzio_creator_reel.mp4';

class JuzzioCreatorReelPage extends StatefulWidget {
  const JuzzioCreatorReelPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, __, ___) => const JuzzioCreatorReelPage(),
          transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
            child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
          ),
        ),
      );

  @override
  State<JuzzioCreatorReelPage> createState() => _JuzzioCreatorReelPageState();
}

class _JuzzioCreatorReelPageState extends State<JuzzioCreatorReelPage> {
  late final VideoPlayerController _c = VideoPlayerController.asset(kJuzzioCreatorReelAsset);
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  bool get _ended => _ready && _c.value.position >= _c.value.duration - const Duration(milliseconds: 120) && !_c.value.isPlaying;

  void _toggle() {
    if (!_ready) return;
    HapticFeedback.selectionClick();
    if (_ended) {
      _c.seekTo(Duration.zero);
      _c.play();
    } else if (_c.value.isPlaying) {
      _c.pause();
    } else {
      _c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final pad = MediaQuery.of(context).padding;
    final dur = _c.value.duration.inMilliseconds;
    final pos = _c.value.position.inMilliseconds;
    final progress = dur <= 0 ? 0.0 : (pos / dur).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Stack(fit: StackFit.expand, children: [
          if (_ready)
            Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)))
          else if (_failed)
            Center(
              child: Text(app.trEn('Video oynatılamadı.', 'The video could not be played.', 'Video konnte nicht abgespielt werden.'),
                  style: const TextStyle(color: Colors.white70)),
            )
          else
            const Center(child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white70))),
          // üst: kapat + başlık (cam)
          Positioned(
            top: pad.top + 10,
            left: 14,
            right: 14,
            child: Row(children: [
              _GlassPill(
                child: IconButton(
                  tooltip: app.trEn('Kapat', 'Close', 'Schließen'),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassPill(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(app.trEn('Yapımcı Tanıtım İçeriği', 'Creator Showreel', 'Creator-Showreel'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ]),
          ),
          // orta: duraklatıldı / bitti
          if (_ready && (!_c.value.isPlaying))
            Center(
              child: _GlassPill(
                padding: const EdgeInsets.all(18),
                child: Icon(_ended ? Icons.replay_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 44),
              ),
            ),
          // alt: ilerleme
          Positioned(
            left: 18,
            right: 18,
            bottom: pad.bottom + 18,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD4FF4F)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Yapımcı sayfasındaki "Portfolyo · Yapımcı Tanıtımı" cam düğmesi (glassmorphism).
class JuzzioCreatorReelButton extends StatelessWidget {
  const JuzzioCreatorReelButton({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return Semantics(
      button: true,
      label: app.trEn('Yapımcı tanıtım videosunu oynat', 'Play creator showreel', 'Creator-Showreel abspielen'),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          JuzzioCreatorReelPage.open(context);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF7B5CFF).withValues(alpha: 0.38), const Color(0xFF1E144E).withValues(alpha: 0.52)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
                boxShadow: [BoxShadow(color: const Color(0xFF7B5CFF).withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFD4FF4F)),
                  child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF140C30), size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.trEn('Portfolyo · Yapımcı Tanıtımı', 'Portfolio · Creator Showreel', 'Portfolio · Creator-Showreel'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(app.trEn('26 sn · internetsiz izlenir', '26 s · plays offline', '26 s · offline abspielbar'),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600, fontSize: 12.5)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.8)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
