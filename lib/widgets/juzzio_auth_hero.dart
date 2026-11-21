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
