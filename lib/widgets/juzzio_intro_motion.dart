// =============================================================================
// JUZZIO v1.2.9 — Karşılama / giriş / kayıt sayfaları için akıcı hareket
//  • juzzioIntroTransition: paylaşılan eksen geçişi (yeni sayfa sağdan süzülür ve %96 → %100
//    büyür; eski sayfa sola kayarak söner). Sıçrama/aşma yok.
//  • JuzzioStaggerIn: sayfa içeriği yukarı doğru yumuşakça belirir (tek seferlik).
//  • JuzzioIntroBlobs: arkada adıma göre yer ve renk değiştiren üç yumuşak ışık lekesi.
//  Hepsi kodla çizilir (görsel/telif yok). "Hareketi azalt" açıkken çağıran taraf kapatır.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/juzzio_glass.dart';

Widget juzzioIntroTransition(Widget child, Animation<double> a) {
  // AnimatedSwitcher giden çocuğu ters yönde oynatır: a 1→0
  final incoming = a.status == AnimationStatus.forward || a.status == AnimationStatus.completed;
  final slide = Tween<Offset>(begin: Offset(incoming ? 0.16 : -0.12, 0), end: Offset.zero).animate(a);
  final scale = Tween<double>(begin: 0.96, end: 1).animate(a);
  return FadeTransition(
    opacity: a,
    child: SlideTransition(position: slide, child: ScaleTransition(scale: scale, child: child)),
  );
}

class JuzzioStaggerIn extends StatefulWidget {
  const JuzzioStaggerIn({super.key, required this.child, this.delay = const Duration(milliseconds: 90)});
  final Widget child;
  final Duration delay;

  @override
  State<JuzzioStaggerIn> createState() => _JuzzioStaggerInState();
}

class _JuzzioStaggerInState extends State<JuzzioStaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: 0.35 + 0.65 * t,
          child: Transform.translate(offset: Offset(0, 22 * (1 - t)), child: child),
        );
      },
    );
  }
}

/// Arkadaki yumuşak ışık lekeleri: her adımda yeni konuma 900 ms'de süzülür
class JuzzioIntroBlobs extends StatelessWidget {
  const JuzzioIntroBlobs({super.key, required this.step});
  final int step;

  static const _spots = <List<Alignment>>[
    [Alignment(-0.9, -0.8), Alignment(0.95, -0.2), Alignment(-0.3, 0.95)],
    [Alignment(0.85, -0.85), Alignment(-0.9, 0.1), Alignment(0.4, 0.9)],
    [Alignment(-0.2, -1.0), Alignment(1.0, 0.55), Alignment(-1.0, 0.75)],
  ];

  @override
  Widget build(BuildContext context) {
    final spots = _spots[step.clamp(0, 2)];
    final glow = JuzzioGlassTokens.glow;
    final colors = <Color>[
      glow,
      HSLColor.fromColor(glow).withHue((HSLColor.fromColor(glow).hue + 55) % 360).toColor(),
      HSLColor.fromColor(glow).withHue((HSLColor.fromColor(glow).hue + 200) % 360).toColor(),
    ];
    return LayoutBuilder(builder: (context, c) {
      final d = math.max(c.maxWidth, c.maxHeight) * 0.62;
      return Stack(children: [
        for (var i = 0; i < 3; i++)
          AnimatedAlign(
            alignment: spots[i],
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOutCubic,
            child: Container(
              width: d * (i == 0 ? 1 : 0.8),
              height: d * (i == 0 ? 1 : 0.8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [colors[i].withValues(alpha: 0.22), colors[i].withValues(alpha: 0)]),
              ),
            ),
          ),
      ]);
    });
  }
}
