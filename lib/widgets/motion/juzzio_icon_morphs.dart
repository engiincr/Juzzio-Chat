// =============================================================================
// JUZZIO v1.1.0 — İkon dönüşümleri (referans: "10 hamburger menu morphs")
//  Statik ikon değişimi yerine kesintisiz Canvas biçim dönüşümü:
//  • plusX      (#04 Plus): eklenti (+) döner ve kapatma (×) olur
//  • menuBack   (#02 Back arrow): menü çizgileri geri okuna (←) dönüşür
//  • kebab      (#05 Kebab): üç çizgi dikey üç noktaya (⋮) / × dönüşür
//  • unevenX    (#09 Uneven bars): asimetrik çizgiler × olur
//  • ringX      (#10 Ring + X): çizgiler halka içinde × olur, halka çizilir
//  progress 0 → kapalı, 1 → açık; yay eğrisiyle canlandırılır.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import 'juzzio_motion_core.dart';

enum JuzzioMorph { plusX, menuBack, kebab, unevenX, ringX }

class JuzzioMorphIcon extends StatelessWidget {
  const JuzzioMorphIcon({
    super.key,
    required this.kind,
    required this.open,
    this.size = 24,
    this.color,
    this.duration = const Duration(milliseconds: 420),
    this.animateIn = false,
  });
  final JuzzioMorph kind;

  /// İlk çizimde de karşı durumdan dönüşerek gelir (ör. menü → geri oku sayfaya girerken)
  final bool animateIn;
  final bool open;
  final double size;
  final Color? color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animateIn ? (open ? 0.0 : 1.0) : null, end: open ? 1.0 : 0.0),
      duration: JuzzioAppController.instance.reduceMotion ? Duration.zero : duration,
      curve: kJuzzioSpring,
      builder: (context, t, _) => CustomPaint(size: Size.square(size), painter: JuzzioMorphPainter(kind: kind, t: t, color: c)),
    );
  }
}

class JuzzioMorphPainter extends CustomPainter {
  JuzzioMorphPainter({required this.kind, required this.t, required this.color});
  final JuzzioMorph kind;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final p = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final h = s * 0.32;
    Offset l(Offset a, Offset b) => Offset.lerp(a, b, t)!;
    switch (kind) {
      case JuzzioMorph.plusX:
        canvas.rotate(t * math.pi * 0.75);
        canvas.drawLine(Offset(-h, 0), Offset(h, 0), p);
        canvas.drawLine(Offset(0, -h), Offset(0, h), p);
      case JuzzioMorph.menuBack:
        canvas.rotate(t * math.pi);
        // üst ve alt çizgiler okun kanatlarına, orta çizgi gövdeye
        canvas.drawLine(l(Offset(-h, -h * 0.66), Offset(h * 0.05, -h * 0.62)), l(Offset(h, -h * 0.66), Offset(h, 0)), p);
        canvas.drawLine(l(Offset(-h, 0), Offset(-h, 0)), l(Offset(h, 0), Offset(h, 0)), p);
        canvas.drawLine(l(Offset(-h, h * 0.66), Offset(h * 0.05, h * 0.62)), l(Offset(h, h * 0.66), Offset(h, 0)), p);
      case JuzzioMorph.kebab:
        // kapalı: dikey üç nokta; açık: ×
        if (t < 0.5) {
          final k = t / 0.5;
          final dot = Paint()..color = color;
          for (final y in [-h * 0.8, 0.0, h * 0.8]) {
            canvas.drawCircle(Offset(0, y * (1 - k)), s * 0.07 * (1 - k * 0.3), dot);
          }
          if (k > 0) {
            canvas.drawLine(Offset(-h * k, 0), Offset(h * k, 0), p..color = color.withValues(alpha: k));
          }
        } else {
          final k = (t - 0.5) / 0.5;
          canvas.rotate(k * math.pi / 4);
          canvas.drawLine(Offset(-h, 0), Offset(h, 0), p);
          canvas.drawLine(Offset(0, -h * k), Offset(0, h * k), p);
        }
      case JuzzioMorph.unevenX:
        // asimetrik çizgiler (uzun / kısa / orta) → ×
        canvas.drawLine(l(Offset(-h, -h * 0.66), Offset(-h * 0.8, -h * 0.8)), l(Offset(h, -h * 0.66), Offset(h * 0.8, h * 0.8)), p);
        canvas.drawLine(Offset(-h * (1 - t), 0), Offset(h * 0.25 * (1 - t), 0), p..color = color.withValues(alpha: 1 - t));
        p.color = color;
        canvas.drawLine(l(Offset(-h, h * 0.66), Offset(-h * 0.8, h * 0.8)), l(Offset(h * 0.55, h * 0.66), Offset(h * 0.8, -h * 0.8)), p);
      case JuzzioMorph.ringX:
        final k = t;
        final rr = s * 0.46;
        if (k > 0) {
          final ring = Paint()
            ..color = color
            ..strokeWidth = s * 0.06
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: rr), -math.pi / 2, 2 * math.pi * k, false, ring);
        }
        final hh = h * (1 - 0.22 * k);
        canvas.drawLine(l(Offset(-hh, -hh * 0.6), Offset(-hh * 0.7, -hh * 0.7)), l(Offset(hh, -hh * 0.6), Offset(hh * 0.7, hh * 0.7)), p);
        canvas.drawLine(Offset(-hh * (1 - k), 0), Offset(hh * (1 - k), 0), p..color = color.withValues(alpha: 1 - k));
        p.color = color;
        canvas.drawLine(l(Offset(-hh, hh * 0.6), Offset(-hh * 0.7, hh * 0.7)), l(Offset(hh, hh * 0.6), Offset(hh * 0.7, -hh * 0.7)), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JuzzioMorphPainter o) => o.t != t || o.kind != kind || o.color != color;
}

/// Dönüşen ikonlu yuvarlak düğme (IconButton yerine)
class JuzzioMorphButton extends StatelessWidget {
  const JuzzioMorphButton({
    super.key,
    required this.kind,
    required this.open,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 24,
  });
  final JuzzioMorph kind;
  final bool open;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed == null
          ? null
          : () {
              JuzzioHaptics.toggle();
              onPressed!();
            },
      icon: JuzzioMorphIcon(kind: kind, open: open, size: size, color: color),
    );
  }
}
