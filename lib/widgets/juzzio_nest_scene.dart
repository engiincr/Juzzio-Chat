// =============================================================================
// JUZZIO v0.7.0 — Civciv oyunu: saman kuş yuvası sahnesi
//  • Sıcak ahır ışığı zemin, katman katman saman çöpleriyle örülmüş yuva.
//  • Yumurta evresinde: benekli krem yumurta; beslendikçe titrer ve deneyim
//    puanı arttıkça kabuktaki çatlaklar adım adım büyür.
//  • Sonraki evrelerde civciv yuvanın içinde oturur.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

class JuzzioNestScene extends StatelessWidget {
  /// 0 = yumurta, 1+ = civciv evreleri
  final int stage;
  /// 0..1 — yumurtanın çatlama ilerlemesi
  final double crack;
  /// Besleme titreşimi (0..1, AnimationController değeri)
  final Animation<double> wobble;
  /// Hafif nefes/zıplama
  final Animation<double> idle;
  final String chickEmoji;
  final bool dark;

  const JuzzioNestScene({
    super.key,
    required this.stage,
    required this.crack,
    required this.wobble,
    required this.idle,
    required this.chickEmoji,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.25,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: Listenable.merge([wobble, idle]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _BarnBackdropPainter(dark: dark)),
                CustomPaint(painter: _NestPainter(back: true)),
                if (stage <= 0)
                  CustomPaint(painter: _EggPainter(crack: crack, wobble: wobble.value, breathe: idle.value))
                else
                  Align(
                    alignment: const Alignment(0, 0.05),
                    child: Transform.translate(
                      offset: Offset(0, -8 * idle.value),
                      child: Transform.rotate(
                        angle: math.sin(wobble.value * math.pi * 6) * 0.12 * (1 - wobble.value),
                        child: Text(chickEmoji, style: const TextStyle(fontSize: 92)),
                      ),
                    ),
                  ),
                CustomPaint(painter: _NestPainter(back: false)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BarnBackdropPainter extends CustomPainter {
  final bool dark;
  _BarnBackdropPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF2A1E12), Color(0xFF3B2A17), Color(0xFF1C140C)]
              : const [Color(0xFFFFF1D6), Color(0xFFF6D9A8), Color(0xFFE6B877)],
        ).createShader(rect),
    );
    // Sıcak ışık huzmesi
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.05),
      size.width * 0.7,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: dark ? 0.10 : 0.45), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(size.width * 0.22, size.height * 0.05), radius: size.width * 0.7)),
    );
    // Yerdeki dağınık saman çöpleri
    final rnd = math.Random(7);
    final straw = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 70; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = size.height * (0.78 + rnd.nextDouble() * 0.22);
      final a = (rnd.nextDouble() - 0.5) * 1.2;
      final l = 10 + rnd.nextDouble() * 18;
      straw.color = Color.lerp(const Color(0xFFC8962E), const Color(0xFFF0CF7A), rnd.nextDouble())!
          .withValues(alpha: dark ? 0.55 : 0.85);
      canvas.drawLine(Offset(x, y), Offset(x + math.cos(a) * l, y + math.sin(a) * l), straw);
    }
  }

  @override
  bool shouldRepaint(covariant _BarnBackdropPainter old) => old.dark != dark;
}

class _NestPainter extends CustomPainter {
  /// true → yuvanın arka kenarı (yumurtanın arkasında), false → ön kenar (önünde)
  final bool back;
  _NestPainter({required this.back});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.70;
    final rx = size.width * 0.36;
    final ry = size.height * 0.16;
    final bowl = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
    if (back) {
      canvas.drawOval(
        bowl.inflate(6),
        Paint()..color = const Color(0xFF6B4A22),
      );
      canvas.drawOval(
        bowl.deflate(8),
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xFF3E2A12), Color(0xFF5C3F1C)]).createShader(bowl),
      );
    }
    final rnd = math.Random(back ? 11 : 23);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final count = back ? 90 : 140;
    for (var i = 0; i < count; i++) {
      final t = rnd.nextDouble() * math.pi * (back ? 1 : 1) + (back ? math.pi : 0);
      final rr = 1 + (rnd.nextDouble() - 0.5) * 0.18;
      final x = cx + math.cos(t) * rx * rr;
      final y = cy + math.sin(t) * ry * rr * (back ? 1 : 1.35) + (back ? 0 : 4);
      final len = 18 + rnd.nextDouble() * 26;
      final ang = t + math.pi / 2 + (rnd.nextDouble() - 0.5) * 0.9;
      p
        ..strokeWidth = 2.0 + rnd.nextDouble() * 2.2
        ..color = Color.lerp(const Color(0xFFB07A2A), const Color(0xFFF2D27C), rnd.nextDouble())!;
      final path = Path()
        ..moveTo(x - math.cos(ang) * len / 2, y - math.sin(ang) * len / 2)
        ..quadraticBezierTo(
          x + (rnd.nextDouble() - 0.5) * 8,
          y + (rnd.nextDouble() - 0.5) * 6,
          x + math.cos(ang) * len / 2,
          y + math.sin(ang) * len / 2,
        );
      canvas.drawPath(path, p);
    }
    if (!back) {
      // Ön kenara yumuşak gölge
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + ry * 1.25), width: rx * 2.2, height: ry * 0.7),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NestPainter old) => false;
}

class _EggPainter extends CustomPainter {
  final double crack;
  final double wobble;
  final double breathe;
  _EggPainter({required this.crack, required this.wobble, required this.breathe});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final base = size.height * 0.70;
    final w = size.width * 0.24;
    final h = w * 1.32;
    // Titreme: hızlı sönümlenen salınım (besleme anında)
    final angle = math.sin(wobble * math.pi * 8) * 0.16 * (1 - wobble);
    canvas.save();
    canvas.translate(cx, base);
    canvas.rotate(angle);
    canvas.translate(0, -2 * breathe);
    final egg = Path()
      ..moveTo(0, -h)
      ..cubicTo(w * 0.62, -h, w * 0.58, -h * 0.05, 0, 0)
      ..cubicTo(-w * 0.58, -h * 0.05, -w * 0.62, -h, 0, -h)
      ..close();
    final bounds = egg.getBounds();
    canvas.drawShadow(egg, Colors.black, 6, false);
    canvas.drawPath(
      egg,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [Color(0xFFFFFCF4), Color(0xFFF3E3C6), Color(0xFFD9BE90)],
          stops: [0.0, 0.6, 1.0],
        ).createShader(bounds),
    );
    // Benekler
    final rnd = math.Random(3);
    final speck = Paint()..color = const Color(0xFFB08B57).withValues(alpha: 0.35);
    canvas.save();
    canvas.clipPath(egg);
    for (var i = 0; i < 26; i++) {
      final x = (rnd.nextDouble() - 0.5) * w * 1.1;
      final y = -rnd.nextDouble() * h;
      canvas.drawCircle(Offset(x, y), 1.0 + rnd.nextDouble() * 2.2, speck);
    }
    // Çatlaklar: ilerleme arttıkça daha fazla ve uzun çizgi
    final c = crack.clamp(0.0, 1.0);
    if (c > 0.05) {
      final cp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF5B4426);
      final segs = (2 + c * 10).round();
      final path = Path()..moveTo(-w * 0.42, -h * 0.55);
      final zr = math.Random(9);
      for (var i = 1; i <= segs; i++) {
        final x = -w * 0.42 + (w * 0.84) * (i / segs);
        final y = -h * 0.55 + (i.isEven ? -1 : 1) * (6 + zr.nextDouble() * 6);
        path.lineTo(x, y);
      }
      final metric = path.computeMetrics().toList();
      for (final m in metric) {
        canvas.drawPath(m.extractPath(0, m.length * math.min(1.0, c * 1.4)), cp);
      }
      if (c > 0.55) {
        final br = Path()
          ..moveTo(w * 0.05, -h * 0.55)
          ..lineTo(w * 0.12, -h * 0.68)
          ..lineTo(w * 0.04, -h * 0.78);
        canvas.drawPath(br, cp);
      }
      if (c > 0.8) {
        final br2 = Path()
          ..moveTo(-w * 0.2, -h * 0.53)
          ..lineTo(-w * 0.26, -h * 0.40)
          ..lineTo(-w * 0.18, -h * 0.30);
        canvas.drawPath(br2, cp);
      }
    }
    canvas.restore();
    // Parlama
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-w * 0.18, -h * 0.72), width: w * 0.22, height: h * 0.16),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EggPainter old) =>
      old.crack != crack || old.wobble != wobble || old.breathe != breathe;
}
