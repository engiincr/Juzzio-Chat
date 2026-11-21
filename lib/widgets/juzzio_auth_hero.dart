// =============================================================================
// JUZZIO 2.1 — Giriş/Kayıt üst görseli (tasarım: "Neon Yeşil Kayıt/Giriş Ekranı")
//  Tasarımdaki fotoğraf yerine (telif/kişilik hakkı) tamamen kodla çizilen sahne:
//  limon degrade cam pano, ortada parlayan yeşil şerit J logosu, etrafında süzülen
//  emoji balonları ve sol altta "sesli mesaj" dalga rozeti.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import 'juzzio_brand.dart';

class JuzzioAuthHero extends StatefulWidget {
  const JuzzioAuthHero({super.key, this.height = 250});
  final double height;

  @override
  State<JuzzioAuthHero> createState() => _JuzzioAuthHeroState();
}

class _JuzzioAuthHeroState extends State<JuzzioAuthHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (!JuzzioAppController.instance.reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return SizedBox(
      height: h,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34), top: Radius.circular(28)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFB9E62E), Color(0xFF6E9A12), Color(0xFF1A2208)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value * 2 * math.pi;
              Widget bubble(String e, double x, double y, double size, double phase) {
                return Align(
                  alignment: Alignment(x, y + math.sin(t + phase) * 0.04),
                  child: Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Text(e, style: TextStyle(fontSize: size * 0.52)),
                  ),
                );
              }

              return Stack(
                children: [
                  // yumuşak ışık halkası
                  Align(
                    alignment: const Alignment(0, -0.05),
                    child: Container(
                      width: h * 0.82,
                      height: h * 0.82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.0)]),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(0, -0.08 + math.sin(t) * 0.02),
                    child: JuzzioLogoTile(size: h * 0.42),
                  ),
                  bubble('😎', -0.62, -0.62, 44, 0),
                  bubble('😄', -0.78, 0.18, 34, 1.4),
                  bubble('😁', 0.74, -0.05, 42, 2.6),
                  // sesli mesaj rozeti
                  Align(
                    alignment: const Alignment(-0.82, 0.62),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: JuzzioBrandColors.ink.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: JuzzioGlassTokens.glowText, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, size: 18, color: JuzzioBrandColors.ink),
                          ),
                          const SizedBox(width: 8),
                          for (var i = 0; i < 9; i++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.3),
                              width: 3,
                              height: 6 + 10 * (0.5 + 0.5 * math.sin(t * 2 + i * 0.9)).abs(),
                              decoration: BoxDecoration(color: JuzzioGlassTokens.glowText, borderRadius: BorderRadius.circular(2)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// v2.1 (tasarım: Giriş/Kayıt) — başlık altındaki limon el çizimi vurgu (kodla çizilir)
class JuzzioTitleScribble extends StatelessWidget {
  const JuzzioTitleScribble({super.key, this.width = 96});
  final double width;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size(width, 10), painter: _ScribblePainter(JuzzioGlassTokens.glow)),
      );
}

class _ScribblePainter extends CustomPainter {
  _ScribblePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.70)
      ..quadraticBezierTo(w * 0.35, h * 0.30, w * 0.70, h * 0.50)
      ..quadraticBezierTo(w * 0.85, h * 0.60, w, h * 0.25);
    canvas.drawPath(path, paint);
    final path2 = Path()
      ..moveTo(w * 0.10, h * 0.95)
      ..quadraticBezierTo(w * 0.45, h * 0.62, w * 0.82, h * 0.78);
    canvas.drawPath(path2, paint..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(covariant _ScribblePainter old) => old.color != color;
}

/// Google "G" işareti (dört renk, kodla çizilir — "Google ile giriş" düğmesi için)
class JuzzioGoogleMark extends StatelessWidget {
  const JuzzioGoogleMark({super.key, this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2 - stroke / 2);
    Paint pen(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = math.pi / 180;
    canvas.drawArc(rect, -150 * deg, 105 * deg, false, pen(const Color(0xFFEA4335))); // kırmızı (üst)
    canvas.drawArc(rect, 150 * deg, 60 * deg, false, pen(const Color(0xFFFBBC05))); // sarı (sol)
    canvas.drawArc(rect, 45 * deg, 105 * deg, false, pen(const Color(0xFF34A853))); // yeşil (alt)
    canvas.drawArc(rect, 0, 45 * deg, false, pen(const Color(0xFF4285F4))); // mavi (sağ)
    // mavi yatay çubuk
    canvas.drawRect(Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke * 0.05, stroke), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// GitHub işareti (sade kedi silueti, kodla çizilir — "GitHub ile giriş" düğmesi için)
class JuzzioGithubMark extends StatelessWidget {
  const JuzzioGithubMark({super.key, this.size = 28, this.color = Colors.white});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GithubPainter(color));
}

class _GithubPainter extends CustomPainter {
  _GithubPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()..color = color;
    // dış daire
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, fill);
    final hole = Paint()..color = const Color(0xFF1B1D20);
    // kedi başı (koyu)
    final head = Path()
      ..moveTo(s * 0.30, s * 0.30)
      ..lineTo(s * 0.33, s * 0.18)
      ..lineTo(s * 0.42, s * 0.26)
      ..quadraticBezierTo(s * 0.50, s * 0.24, s * 0.58, s * 0.26)
      ..lineTo(s * 0.67, s * 0.18)
      ..lineTo(s * 0.70, s * 0.30)
      ..quadraticBezierTo(s * 0.80, s * 0.42, s * 0.74, s * 0.56)
      ..quadraticBezierTo(s * 0.68, s * 0.66, s * 0.58, s * 0.68)
      ..lineTo(s * 0.58, s * 0.92)
      ..lineTo(s * 0.42, s * 0.92)
      ..lineTo(s * 0.42, s * 0.80)
      ..quadraticBezierTo(s * 0.30, s * 0.82, s * 0.26, s * 0.72)
      ..lineTo(s * 0.32, s * 0.72)
      ..quadraticBezierTo(s * 0.36, s * 0.76, s * 0.42, s * 0.74)
      ..lineTo(s * 0.42, s * 0.68)
      ..quadraticBezierTo(s * 0.32, s * 0.66, s * 0.26, s * 0.56)
      ..quadraticBezierTo(s * 0.20, s * 0.42, s * 0.30, s * 0.30)
      ..close();
    canvas.drawPath(head, hole);
  }

  @override
  bool shouldRepaint(covariant _GithubPainter old) => old.color != color;
}
