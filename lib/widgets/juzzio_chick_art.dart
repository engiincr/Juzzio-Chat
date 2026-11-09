// =============================================================================
// JUZZIO v0.9.3 — Civciv oyunu: HD vektör civciv + likit cam butonlar + parçacıklar
//  • Emoji yerine her çözünürlükte keskin, gradyanlı vektör çizim (CustomPainter).
//  • Evreye göre görünüm: 1 kabuktan yeni çıkmış · 2 genç · 3 tavuk (ibik, gerdan, kuyruk).
//  • Ruh hâline göre yüz: mutlu (parlak göz, yanak), aç (düşük kaş, açık gaga),
//    ölüyor (kapalı göz, gözyaşı, soluk renk). Göz kırpma ve kanat çırpma animasyonu.
//  • JuzzioLiquidGlassButton: bulanık cam + ışık kenarı + basınca yaylanan buton.
//  • JuzzioChickParticles: beslemede yem taneleri, sevince kalpler.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ruh hâli → çizim parametreleri (test edilebilir saf fonksiyon).
class JuzzioChickLook {
  final double eyeOpen; // 0 kapalı · 1 tam açık
  final double browTilt; // + üzgün
  final double beakOpen; // 0..1
  final double saturation; // 1 normal · <1 soluk
  final bool tears;
  final bool blush;

  const JuzzioChickLook({
    required this.eyeOpen,
    required this.browTilt,
    required this.beakOpen,
    required this.saturation,
    required this.tears,
    required this.blush,
  });

  static JuzzioChickLook forMood(String mood) {
    switch (mood) {
      case 'dying':
        return const JuzzioChickLook(eyeOpen: 0.0, browTilt: 1.0, beakOpen: 0.15, saturation: 0.45, tears: true, blush: false);
      case 'hungry':
        return const JuzzioChickLook(eyeOpen: 0.7, browTilt: 0.7, beakOpen: 1.0, saturation: 0.85, tears: false, blush: false);
      default:
        return const JuzzioChickLook(eyeOpen: 1.0, browTilt: 0.0, beakOpen: 0.0, saturation: 1.0, tears: false, blush: true);
    }
  }
}

/// Açlık göstergesi: 0 tok · 1 ölüm eşiği (7 gün). 12 saat → aç, 72 saat → ölüyor.
double juzzioChickHungerLevel(double hoursSinceFed) => (hoursSinceFed / 168.0).clamp(0.0, 1.0);

/// Sohbetteki yumurta yalnızca civciv bu arkadaşla ortaksa ve AÇSA (veya ondan bekleyen bir davet varsa) görünür.
bool juzzioChickEggVisible({
  required bool hasChick,
  required String mood,
  required String chickPartnerId,
  required String chatPartnerId,
  required bool hasIncomingInviteFromPartner,
}) {
  if (hasIncomingInviteFromPartner) return true;
  if (!hasChick || chickPartnerId.isEmpty || chickPartnerId != chatPartnerId) return false;
  return mood == 'hungry' || mood == 'dying';
}

Color _desat(Color c, double s) {
  if (s >= 1) return c;
  final g = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
  return Color.from(
    alpha: c.a,
    red: g + (c.r - g) * s,
    green: g + (c.g - g) * s,
    blue: g + (c.b - g) * s,
  );
}

class JuzzioChickPainter extends CustomPainter {
  final int stage; // 1..3
  final String mood;
  final double blink; // 0..1 (1 = göz kapalı anı)
  final double breathe; // 0..1
  final double flap; // 0..1 kanat çırpma
  final double wobble; // 0..1 besleme titreşimi
  /// v0.9.4: gardırop — {'hat','glasses','outfit','shoes','color'}
  final Map<String, String> style;

  JuzzioChickPainter({
    required this.stage,
    required this.mood,
    this.blink = 0,
    this.breathe = 0,
    this.flap = 0,
    this.wobble = 0,
    this.style = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    final look = JuzzioChickLook.forMood(mood);
    final s = math.min(size.width, size.height);
    final st = stage.clamp(1, 3);
    final hen = st == 3;
    final scale = st == 1 ? 0.78 : (st == 2 ? 0.92 : 1.0);
    final r = s * 0.30 * scale; // gövde yarıçapı
    final cx = size.width / 2;
    final baseY = size.height * 0.80;
    final angle = math.sin(wobble * math.pi * 6) * 0.12 * (1 - wobble);

    final custom = juzzioParseHexColor(style['color']);
    final bodyLight = _desat(custom != null ? Color.lerp(custom, Colors.white, 0.55)! : (hen ? const Color(0xFFFFF8EC) : const Color(0xFFFFF3A0)), look.saturation);
    final bodyMid = _desat(custom ?? (hen ? const Color(0xFFF1D9B5) : const Color(0xFFFFD43B)), look.saturation);
    final bodyDark = _desat(custom != null ? Color.lerp(custom, Colors.black, 0.3)! : (hen ? const Color(0xFFC79A66) : const Color(0xFFF2A516)), look.saturation);
    final beakC = _desat(const Color(0xFFFF8A1F), look.saturation);
    final beakD = _desat(const Color(0xFFD9620A), look.saturation);

    canvas.save();
    canvas.translate(cx, baseY);
    canvas.rotate(angle);
    final squash = 1 + 0.025 * math.sin(breathe * math.pi);
    canvas.scale(1 / squash, squash);

    // Zemin gölgesi
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 2), width: r * 1.9, height: r * 0.32),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Ayaklar (genç ve tavuk)
    if (st >= 2) {
      final leg = Paint()
        ..color = beakD
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (final dx in [-r * 0.32, r * 0.32]) {
        canvas.drawLine(Offset(dx, -r * 0.25), Offset(dx, 0), leg);
        canvas.drawLine(Offset(dx, 0), Offset(dx - r * 0.14, r * 0.05), leg);
        canvas.drawLine(Offset(dx, 0), Offset(dx + r * 0.14, r * 0.05), leg);
      }
    }

    final bodyCenter = Offset(0, -r * (st == 1 ? 0.95 : 1.15));
    final bodyRect = Rect.fromCenter(center: bodyCenter, width: r * 2.0, height: r * (hen ? 2.05 : 1.9));

    // Kuyruk (tavuk)
    if (hen) {
      final tail = Path()
        ..moveTo(r * 0.7, bodyCenter.dy - r * 0.1)
        ..quadraticBezierTo(r * 1.45, bodyCenter.dy - r * 1.2, r * 1.25, bodyCenter.dy - r * 0.05)
        ..quadraticBezierTo(r * 1.55, bodyCenter.dy - r * 0.75, r * 1.05, bodyCenter.dy + r * 0.35)
        ..close();
      canvas.drawPath(
        tail,
        Paint()
          ..shader = LinearGradient(colors: [bodyMid, bodyDark]).createShader(tail.getBounds()),
      );
    }

    // Gövde
    final body = Path()..addOval(bodyRect);
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [bodyLight, bodyMid, bodyDark],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(bodyRect),
    );
    // Kenar ışığı (rim light)
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.65), Colors.white.withValues(alpha: 0.0)],
        ).createShader(bodyRect),
    );
    // Tüy dokusu: yumuşak kısa çizgiler
    final fluff = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = rnd.nextDouble() * r * 0.85;
      final p = bodyCenter + Offset(math.cos(a) * d, math.sin(a) * d * 0.95);
      canvas.drawLine(p, p + Offset(math.cos(a) * 3, math.sin(a) * 3), fluff);
    }
    // Tepe tüyü (civciv / genç)
    if (!hen) {
      final tuft = Paint()
        ..color = bodyMid
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final top = Offset(0, bodyRect.top + r * 0.04);
      canvas.drawPath(Path()..moveTo(top.dx, top.dy)..quadraticBezierTo(-r * 0.05, top.dy - r * 0.32, -r * 0.2, top.dy - r * 0.3), tuft);
      canvas.drawPath(Path()..moveTo(top.dx, top.dy)..quadraticBezierTo(r * 0.1, top.dy - r * 0.35, r * 0.18, top.dy - r * 0.22), tuft);
    } else {
      // İbik
      final combC = _desat(const Color(0xFFE53935), look.saturation);
      final top = bodyRect.top + r * 0.12;
      final comb = Path()..moveTo(-r * 0.32, top);
      for (var i = 0; i < 3; i++) {
        final x0 = -r * 0.32 + i * r * 0.22;
        comb.quadraticBezierTo(x0 + r * 0.11, top - r * (0.42 + (i == 1 ? 0.1 : 0)), x0 + r * 0.22, top);
      }
      comb.close();
      canvas.drawPath(comb, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [combC, _desat(const Color(0xFFB71C1C), look.saturation)]).createShader(comb.getBounds()));
    }

    // Kanatlar (çırpma)
    final wingAngle = -0.35 * math.sin(flap * math.pi);
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(side * r * 0.82, bodyCenter.dy + r * 0.12);
      canvas.rotate(side * wingAngle);
      final wing = Path()
        ..moveTo(0, -r * 0.3)
        ..quadraticBezierTo(side * r * 0.42, -r * 0.05, side * r * 0.12, r * 0.42)
        ..quadraticBezierTo(-side * r * 0.08, r * 0.1, 0, -r * 0.3)
        ..close();
      canvas.drawPath(wing, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bodyMid, bodyDark]).createShader(wing.getBounds()));
      canvas.restore();
    }

    // Kabuk (yalnız 1. evre): alt yarıda çatlak kenarlı yumurta kabuğu
    if (st == 1) {
      final shellTop = bodyCenter.dy + r * 0.25;
      final shellRect = Rect.fromLTRB(-r * 1.12, shellTop - r * 0.2, r * 1.12, r * 0.15);
      final shell = Path()..moveTo(-r * 1.08, shellTop);
      const zig = 8;
      for (var i = 1; i <= zig; i++) {
        final x = -r * 1.08 + (r * 2.16) * (i / zig);
        shell.lineTo(x, shellTop + (i.isEven ? 0 : -r * 0.2));
      }
      shell
        ..quadraticBezierTo(r * 1.1, r * 0.1, 0, r * 0.12)
        ..quadraticBezierTo(-r * 1.1, r * 0.1, -r * 1.08, shellTop)
        ..close();
      canvas.drawPath(
        shell,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF4), Color(0xFFE6CFA6)],
          ).createShader(shellRect),
      );
      canvas.drawPath(shell, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFB08B57).withValues(alpha: 0.6));
    }

    // Yüz
    final eyeY = bodyCenter.dy - r * 0.22;
    final eyeDx = r * 0.36;
    final eyeR = r * 0.13;
    final open = (look.eyeOpen * (1 - blink)).clamp(0.0, 1.0);
    for (final side in [-1.0, 1.0]) {
      final c = Offset(side * eyeDx, eyeY);
      if (open < 0.08) {
        // Kapalı göz: yay
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: eyeR * 0.9),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.045
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF2B1B0E),
        );
      } else {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(1, open);
        canvas.drawCircle(Offset.zero, eyeR, Paint()..color = const Color(0xFF1C120A));
        canvas.drawCircle(Offset(-eyeR * 0.32, -eyeR * 0.35), eyeR * 0.38, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(eyeR * 0.35, eyeR * 0.3), eyeR * 0.15, Paint()..color = Colors.white.withValues(alpha: 0.8));
        canvas.restore();
      }
      // Kaş (üzgünken eğik)
      if (look.browTilt > 0) {
        final bp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.035
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF6B4A1E);
        final inner = Offset(side * (eyeDx - eyeR * 0.9), eyeY - eyeR * (1.5 - 0.3 * look.browTilt));
        final outer = Offset(side * (eyeDx + eyeR * 0.9), eyeY - eyeR * (1.5 + 0.35 * look.browTilt) + eyeR * 0.9 * look.browTilt);
        canvas.drawLine(inner, outer, bp);
      }
      if (look.blush) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(side * (eyeDx + r * 0.1), eyeY + r * 0.24), width: r * 0.26, height: r * 0.14),
          Paint()
            ..color = const Color(0xFFFF7A9A).withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );
      }
      if (look.tears) {
        final t = Path()
          ..moveTo(side * eyeDx, eyeY + eyeR * 0.6)
          ..quadraticBezierTo(side * (eyeDx + eyeR * 0.6), eyeY + eyeR * 2.2, side * eyeDx, eyeY + eyeR * 2.6)
          ..quadraticBezierTo(side * (eyeDx - eyeR * 0.6), eyeY + eyeR * 2.2, side * eyeDx, eyeY + eyeR * 0.6);
        canvas.drawPath(t, Paint()..color = const Color(0xFF6EC6FF).withValues(alpha: 0.85));
      }
    }

    // Gaga (açlıkta açık)
    final beakY = eyeY + r * 0.2;
    final bw = r * 0.2;
    final bo = r * 0.12 * look.beakOpen;
    final upper = Path()
      ..moveTo(-bw, beakY)
      ..quadraticBezierTo(0, beakY - r * 0.14, bw, beakY)
      ..lineTo(0, beakY + r * 0.16)
      ..close();
    final lower = Path()
      ..moveTo(-bw * 0.8, beakY + bo)
      ..lineTo(bw * 0.8, beakY + bo)
      ..lineTo(0, beakY + r * 0.12 + bo * 1.4)
      ..close();
    if (bo > 0) {
      canvas.drawOval(Rect.fromCenter(center: Offset(0, beakY + bo * 0.8), width: bw * 1.2, height: bo * 1.8), Paint()..color = const Color(0xFF7A1F12));
    }
    canvas.drawPath(lower, Paint()..color = beakD);
    canvas.drawPath(upper, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [beakC, beakD]).createShader(upper.getBounds()));
    if (hen) {
      // Gerdan
      final wattleC = _desat(const Color(0xFFE53935), look.saturation);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, beakY + r * 0.3), width: r * 0.16, height: r * 0.24), Paint()..color = wattleC);
    }

    juzzioPaintChickAccessories(canvas, style: style, r: r, bodyRect: bodyRect, eyeY: eyeY, eyeDx: eyeDx, eyeR: eyeR, beakY: beakY);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JuzzioChickPainter old) =>
      old.stage != stage ||
      old.mood != mood ||
      old.blink != blink ||
      old.breathe != breathe ||
      old.flap != flap ||
      old.wobble != wobble ||
      !_sameStyle(old.style, style);
}

bool _sameStyle(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// '#RRGGBB' → Color (geçersizse null).
Color? juzzioParseHexColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// Gardırop aksesuarlarını gövdeye göre çizer (tümü vektör, her çözünürlükte keskin).
void juzzioPaintChickAccessories(Canvas canvas,
    {required Map<String, String> style,
    required double r,
    required Rect bodyRect,
    required double eyeY,
    required double eyeDx,
    required double eyeR,
    required double beakY}) {
  final top = bodyRect.top;
  // Kıyafet (boyunda)
  switch (style['outfit']) {
    case 'bow_tie':
      final y = beakY + r * 0.42;
      final c = Paint()..color = const Color(0xFFE53935);
      final left = Path()..moveTo(0, y)..lineTo(-r * 0.3, y - r * 0.15)..lineTo(-r * 0.3, y + r * 0.15)..close();
      final right = Path()..moveTo(0, y)..lineTo(r * 0.3, y - r * 0.15)..lineTo(r * 0.3, y + r * 0.15)..close();
      canvas.drawPath(left, c);
      canvas.drawPath(right, c);
      canvas.drawCircle(Offset(0, y), r * 0.07, Paint()..color = const Color(0xFFB71C1C));
    case 'scarf':
      final y = beakY + r * 0.4;
      final band = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y), width: r * 1.5, height: r * 0.22), Radius.circular(r * 0.11));
      canvas.drawRRect(band, Paint()..color = const Color(0xFF1E88E5));
      final tail = RRect.fromRectAndRadius(Rect.fromLTWH(r * 0.25, y, r * 0.2, r * 0.55), Radius.circular(r * 0.08));
      canvas.drawRRect(tail, Paint()..color = const Color(0xFF1565C0));
      final stripe = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = r * 0.03;
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(Offset(i * r * 0.25, y - r * 0.1), Offset(i * r * 0.25, y + r * 0.1), stripe);
      }
    case 'cape':
      final y = beakY + r * 0.35;
      final cape = Path()
        ..moveTo(-r * 0.75, y)
        ..quadraticBezierTo(0, y + r * 0.12, r * 0.75, y)
        ..lineTo(r * 1.05, bodyRect.bottom - r * 0.1)
        ..quadraticBezierTo(0, bodyRect.bottom + r * 0.12, -r * 1.05, bodyRect.bottom - r * 0.1)
        ..close();
      canvas.drawPath(cape, Paint()..color = const Color(0xFF8E24AA).withValues(alpha: 0.88));
      canvas.drawCircle(Offset(0, y + r * 0.04), r * 0.08, Paint()..color = const Color(0xFFFFD54F));
  }
  // Gözlük
  switch (style['glasses']) {
    case 'round_glasses':
      final g = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045
        ..color = const Color(0xFF263238);
      for (final side in [-1.0, 1.0]) {
        canvas.drawCircle(Offset(side * eyeDx, eyeY), eyeR * 1.7, g);
      }
      canvas.drawLine(Offset(-eyeDx + eyeR * 1.7, eyeY), Offset(eyeDx - eyeR * 1.7, eyeY), g);
    case 'sunglasses':
      final lens = Paint()..color = const Color(0xE6101418);
      for (final side in [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(side * eyeDx, eyeY + eyeR * 0.1), width: eyeR * 3.6, height: eyeR * 2.4), Radius.circular(eyeR * 0.9)),
            lens);
        canvas.drawLine(Offset(side * eyeDx - eyeR, eyeY - eyeR * 0.5), Offset(side * eyeDx - eyeR * 0.2, eyeY - eyeR * 0.8),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.5)
              ..strokeWidth = r * 0.025);
      }
      canvas.drawLine(Offset(-eyeDx + eyeR * 1.8, eyeY), Offset(eyeDx - eyeR * 1.8, eyeY), Paint()
        ..color = const Color(0xFF101418)
        ..strokeWidth = r * 0.045);
    case 'heart_glasses':
      final hp = Paint()..color = const Color(0xE6FF4F7B);
      for (final side in [-1.0, 1.0]) {
        final c = Offset(side * eyeDx, eyeY);
        final s2 = eyeR * 1.8;
        final h = Path()
          ..moveTo(c.dx, c.dy + s2 * 0.6)
          ..cubicTo(c.dx - s2 * 1.2, c.dy - s2 * 0.2, c.dx - s2 * 0.5, c.dy - s2 * 1.0, c.dx, c.dy - s2 * 0.4)
          ..cubicTo(c.dx + s2 * 0.5, c.dy - s2 * 1.0, c.dx + s2 * 1.2, c.dy - s2 * 0.2, c.dx, c.dy + s2 * 0.6);
        canvas.drawPath(h, hp);
      }
  }
  // Şapka
  switch (style['hat']) {
    case 'party_hat':
      final hat = Path()..moveTo(-r * 0.32, top + r * 0.12)..lineTo(r * 0.05, top - r * 0.7)..lineTo(r * 0.36, top + r * 0.1)..close();
      canvas.drawPath(hat, Paint()..shader = const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFFF4081)]).createShader(hat.getBounds()));
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(Offset(-r * 0.05, top - r * 0.15), r * 0.05, dot);
      canvas.drawCircle(Offset(r * 0.12, top - r * 0.35), r * 0.04, dot);
      canvas.drawCircle(Offset(r * 0.05, top - r * 0.72), r * 0.09, Paint()..color = const Color(0xFFFFEB3B));
    case 'crown':
      final y = top + r * 0.1;
      final crown = Path()
        ..moveTo(-r * 0.42, y)
        ..lineTo(-r * 0.46, y - r * 0.42)
        ..lineTo(-r * 0.22, y - r * 0.2)
        ..lineTo(0, y - r * 0.55)
        ..lineTo(r * 0.22, y - r * 0.2)
        ..lineTo(r * 0.46, y - r * 0.42)
        ..lineTo(r * 0.42, y)
        ..close();
      canvas.drawPath(crown, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE082), Color(0xFFFFA000)]).createShader(crown.getBounds()));
      canvas.drawCircle(Offset(0, y - r * 0.18), r * 0.07, Paint()..color = const Color(0xFFE53935));
    case 'beanie':
      final rect = Rect.fromCenter(center: Offset(0, top + r * 0.08), width: r * 1.3, height: r * 0.9);
      canvas.drawArc(rect, math.pi, math.pi, true, Paint()..color = const Color(0xFF43A047));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, top + r * 0.1), width: r * 1.36, height: r * 0.2), Radius.circular(r * 0.1)),
          Paint()..color = const Color(0xFF2E7D32));
      canvas.drawCircle(Offset(0, top - r * 0.42), r * 0.13, Paint()..color = Colors.white);
    case 'cowboy_hat':
      final y = top + r * 0.05;
      canvas.drawOval(Rect.fromCenter(center: Offset(0, y), width: r * 1.9, height: r * 0.32), Paint()..color = const Color(0xFF8D6E63));
      final crownRect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y - r * 0.25), width: r * 0.9, height: r * 0.5), Radius.circular(r * 0.2));
      canvas.drawRRect(crownRect, Paint()..color = const Color(0xFF6D4C41));
      canvas.drawRect(Rect.fromCenter(center: Offset(0, y - r * 0.08), width: r * 0.92, height: r * 0.08), Paint()..color = const Color(0xFF3E2723));
  }
  // Ayakkabı (ayakların altında)
  final shoe = style['shoes'];
  if (shoe != null) {
    final c = shoe == 'boots' ? const Color(0xFF5D4037) : const Color(0xFFE53935);
    for (final dx in [-r * 0.32, r * 0.32]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(dx, r * 0.03), width: r * 0.42, height: shoe == 'boots' ? r * 0.24 : r * 0.16), Radius.circular(r * 0.08)),
          Paint()..color = c);
      if (shoe == 'sneakers') {
        canvas.drawLine(Offset(dx - r * 0.18, r * 0.07), Offset(dx + r * 0.18, r * 0.07), Paint()
          ..color = Colors.white
          ..strokeWidth = r * 0.03);
      }
    }
  }
}

/// Tema → sahne arka plan gradyanı.
List<Color> juzzioChickThemeColors(String? theme, bool dark) {
  switch (theme) {
    case 'theme_night':
      return const [Color(0xFF0B1033), Color(0xFF2B1B5A)];
    case 'theme_beach':
      return const [Color(0xFF4FC3F7), Color(0xFFFFE0B2)];
    case 'theme_snow':
      return const [Color(0xFFB3E5FC), Color(0xFFF5F9FF)];
    case 'theme_meadow':
      return const [Color(0xFF9CCC65), Color(0xFFE6F4D7)];
    default:
      return dark ? const [Color(0xFF1B2433), Color(0xFF0F141C)] : const [Color(0xFFFFF4D6), Color(0xFFFFE6B3)];
  }
}

/// Likit cam buton: arka planı bulanıklaştırır, üstten ışık kenarı, basınca yaylanır.
class JuzzioLiquidGlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color tint;
  final double height;
  final bool loading;

  const JuzzioLiquidGlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.tint = const Color(0xFFFFB300),
    this.height = 56,
    this.loading = false,
  });

  @override
  State<JuzzioLiquidGlassButton> createState() => _JuzzioLiquidGlassButtonState();
}

class _JuzzioLiquidGlassButtonState extends State<JuzzioLiquidGlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final radius = BorderRadius.circular(widget.height / 2);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: widget.onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 260),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: widget.height,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.tint.withValues(alpha: 0.62),
                      widget.tint.withValues(alpha: 0.34),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
                  boxShadow: [
                    BoxShadow(color: widget.tint.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Üst parıltı (sıvı cam yansıması)
                    Positioned(
                      top: 3,
                      left: 14,
                      right: 14,
                      height: widget.height * 0.38,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.height),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0.0)],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.loading)
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        else if (widget.icon != null)
                          Icon(widget.icon, color: Colors.white, size: 21),
                        if (widget.loading || widget.icon != null) const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Küçük cam bilgi kartı (evre, açlık, besleme).
class JuzzioGlassStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? meter; // 0..1 (opsiyonel çubuk)

  const JuzzioGlassStatChip({super.key, required this.icon, required this.label, required this.value, required this.color, this.meter});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withValues(alpha: 0.13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color))),
              ]),
              const SizedBox(height: 4),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              if (meter != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: meter!.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.18)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Uçuşan parçacıklar (kalp / yem tanesi). [progress] 0→1 bir patlama.
class JuzzioChickParticlesPainter extends CustomPainter {
  final double progress;
  final bool hearts;
  final int seed;

  JuzzioChickParticlesPainter({required this.progress, required this.hearts, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final rnd = math.Random(seed);
    final origin = Offset(size.width / 2, size.height * 0.55);
    final n = hearts ? 9 : 16;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.1;
      final speed = size.height * (0.25 + rnd.nextDouble() * 0.35);
      final t = Curves.easeOutCubic.transform(progress);
      final gravity = hearts ? -0.15 : 0.55;
      final p = origin + Offset(math.cos(a) * speed * t, math.sin(a) * speed * t + gravity * speed * progress * progress);
      final alpha = (1 - progress).clamp(0.0, 1.0);
      if (hearts) {
        final s = 7 + rnd.nextDouble() * 7;
        final path = Path()
          ..moveTo(p.dx, p.dy + s * 0.35)
          ..cubicTo(p.dx - s, p.dy - s * 0.4, p.dx - s * 0.35, p.dy - s * 1.0, p.dx, p.dy - s * 0.45)
          ..cubicTo(p.dx + s * 0.35, p.dy - s * 1.0, p.dx + s, p.dy - s * 0.4, p.dx, p.dy + s * 0.35);
        canvas.drawPath(path, Paint()..color = const Color(0xFFFF4F7B).withValues(alpha: alpha));
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: p, width: 5, height: 3.6),
          Paint()..color = (i.isEven ? const Color(0xFFE0B04A) : const Color(0xFFC98E2B)).withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant JuzzioChickParticlesPainter old) => old.progress != progress || old.hearts != hearts || old.seed != seed;
}
