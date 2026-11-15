// =============================================================================
// JUZZIO v1.2.9 — Ay evresi (internet gerektirmez, saf astronomik hesap)
//  • "Senin alanın — Juzzio" başlığında Juzzio yazısının yanında bugünkü Ay evresi
//  • Hava katmanındaki ay simgesi de gerçek evreyi çizer (hep aynı hilal değil)
//  Hesap: sinodik ay 29,530588853 gün; referans yeni ay 2000-01-06 18:14 UTC.
//  Doğruluk ±0,5 gün — simge için fazlasıyla yeterli.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import 'juzzio_weather_sprites.dart';

const double kJuzzioSynodicMonth = 29.530588853;
final DateTime _kRefNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

/// 0 = yeni ay, 0.25 = ilk dördün, 0.5 = dolunay, 0.75 = son dördün (saf; test edilir)
double juzzioMoonPhase(DateTime when) {
  final days = when.toUtc().difference(_kRefNewMoon).inSeconds / 86400.0;
  final p = (days / kJuzzioSynodicMonth) % 1.0;
  return p < 0 ? p + 1 : p;
}

/// Aydınlanan oran 0..1 (saf)
double juzzioMoonIllumination(double phase) => (1 - math.cos(2 * math.pi * phase)) / 2;

/// 8 evre indeksi: 0 yeni, 1 büyüyen hilal, 2 ilk dördün, 3 büyüyen şişkin, 4 dolunay,
/// 5 küçülen şişkin, 6 son dördün, 7 küçülen hilal (saf)
int juzzioMoonPhaseIndex(double phase) => ((phase * 8) + 0.5).floor() % 8;

String juzzioMoonPhaseName(double phase) {
  final app = JuzzioAppController.instance;
  switch (juzzioMoonPhaseIndex(phase)) {
    case 0:
      return app.trEn('Yeni Ay', 'New Moon');
    case 1:
      return app.trEn('Büyüyen Hilal', 'Waxing Crescent');
    case 2:
      return app.trEn('İlk Dördün', 'First Quarter');
    case 3:
      return app.trEn('Büyüyen Şişkin Ay', 'Waxing Gibbous');
    case 4:
      return app.trEn('Dolunay', 'Full Moon');
    case 5:
      return app.trEn('Küçülen Şişkin Ay', 'Waning Gibbous');
    case 6:
      return app.trEn('Son Dördün', 'Last Quarter');
    default:
      return app.trEn('Küçülen Hilal', 'Waning Crescent');
  }
}

/// Ayın aydınlık kısmının yolu (merkez 0,0; yarıçap r). Kuzey yarımküre görünümü.
Path juzzioMoonLitPath(double phase, double r) {
  final p = phase % 1.0;
  final waxing = p < 0.5;
  final half = Path()
    ..addArc(Rect.fromCircle(center: Offset.zero, radius: r), waxing ? -math.pi / 2 : math.pi / 2, math.pi)
    ..close();
  final ex = (r * math.cos(2 * math.pi * p)).abs();
  final ellipse = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: math.max(0.01, ex * 2), height: r * 2));
  final gibbous = (p > 0.25 && p < 0.75);
  return Path.combine(gibbous ? PathOperation.union : PathOperation.difference, half, ellipse);
}

/// Gerçekçi ay çizimi. v1.2.9: görsel yüklüyse (assets/weather/moon.png — kraterli, denizli, kodla
/// üretilmiş Ay) o kullanılır ve karanlık kısım evreye göre gölgelenir; yüklü değilse vektör çizim.
void juzzioPaintMoon(Canvas canvas, double phase, double r, {double alpha = 1, bool glow = true}) {
  final disk = Rect.fromCircle(center: Offset.zero, radius: r);
  if (glow) {
    canvas.drawCircle(Offset.zero, r * 1.7,
        Paint()..shader = RadialGradient(colors: [const Color(0xFFFFF4D6).withValues(alpha: 0.26 * alpha), const Color(0x00FFF4D6)]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.7)));
  }
  final lit = juzzioMoonLitPath(phase, r);
  final sprite = JuzzioWeatherSprites.moon;
  if (sprite != null) {
    canvas.drawImageRect(
      sprite,
      Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
      disk,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: alpha),
    );
    // karanlık yüz: tam siyah değil — "dünya ışığı" ile yüzey hafifçe seçilir
    final dark = Path.combine(PathOperation.difference, Path()..addOval(disk.inflate(0.6)), lit);
    canvas.drawPath(dark, Paint()..color = const Color(0xFF070B18).withValues(alpha: 0.88 * alpha));
    return;
  }
  // dünya ışığı (karanlık kısım hafifçe seçilir)
  canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFF3A4256).withValues(alpha: 0.55 * alpha));
  canvas.save();
  canvas.clipPath(lit);
  canvas.drawCircle(
    Offset.zero,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        radius: 1.05,
        colors: [const Color(0xFFFFFBEA).withValues(alpha: alpha), const Color(0xFFE9DFC2).withValues(alpha: alpha), const Color(0xFFBFB494).withValues(alpha: alpha)],
        stops: const [0, 0.6, 1],
      ).createShader(disk),
  );
  final crater = Paint()..color = const Color(0xFF9E9478).withValues(alpha: 0.42 * alpha);
  for (final c in const [Offset(-0.32, -0.18), Offset(0.22, 0.3), Offset(0.38, -0.32), Offset(-0.12, 0.45), Offset(0.05, -0.02)]) {
    final rr = r * (0.09 + (c.dx.abs() * 0.12));
    canvas.drawCircle(Offset(c.dx * r, c.dy * r), rr, crater);
  }
  canvas.restore();
}

/// Başlıkta küçük ay simgesi (dokununca evre adı ve aydınlanma yüzdesi)
class JuzzioMoonPhaseIcon extends StatelessWidget {
  const JuzzioMoonPhaseIcon({super.key, this.size = 22, this.when});
  final double size;
  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    unawaited(JuzzioWeatherSprites.load());
    final phase = juzzioMoonPhase(when ?? DateTime.now());
    final name = juzzioMoonPhaseName(phase);
    final pct = (juzzioMoonIllumination(phase) * 100).round();
    return Tooltip(
      message: '$name · %$pct',
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: name,
        child: SizedBox(
          width: size,
          height: size,
          child: ValueListenableBuilder<int>(
            valueListenable: JuzzioWeatherSprites.ready,
            builder: (_, v, __) => CustomPaint(painter: _MoonIconPainter(phase, v)),
          ),
        ),
      ),
    );
  }
}

class _MoonIconPainter extends CustomPainter {
  _MoonIconPainter(this.phase, this.spriteVersion);
  final double phase;
  final int spriteVersion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    juzzioPaintMoon(canvas, phase, size.shortestSide * 0.42);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MoonIconPainter old) => old.phase != phase || old.spriteVersion != spriteVersion;
}
