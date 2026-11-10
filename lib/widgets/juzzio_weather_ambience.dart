// =============================================================================
// JUZZIO v1.2.1 — Hava durumu ambiyansı (tema içi değişim)
//  Tüm sayfaların üstünde, dokunmayı ENGELLEMEYEN çok hafif bir katman:
//   • Açık: gündüz sıcak güneş ışıltısı (sağ üst), gece soğuk ay hâlesi + birkaç yıldız
//   • Bulutlu: üstte yavaş süzülen yumuşak bulutlar
//   • Sis: altta pus
//   • Çisenti / yağmur: ince eğik damlalar (yoğunluk türe göre)
//   • Kar: yavaş düşen kar taneleri
//   • Fırtına: yağmur + seyrek şimşek parlaması
//  v1.2.7: saate (ve havaya) göre arka planda minik VEKTÖR simgeler yavaşça süzülür:
//   gece 🌙 hilal + ✦ yıldız, sabah/öğle ☀️ güneş + ☁️ bulut, akşam 🌇 turuncu güneş + hilal,
//   yağmurda 💧 damla, karda ❄️ kar tanesi, fırtınada ⚡ şimşek. Hepsi kod ile çizilir (görsel yok).
//  Okunabilirlik için saydamlık düşük tutulur. "Hareketi azalt" ve Performans modunda yalnız
//  durağan renk tonu çizilir (animasyon/ticker yok). Ayar: Görünüm → Hava durumu teması.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_weather_service.dart';

/// Arka planda süzülen minik simge türleri
enum JuzzioWeatherDoodle { moon, star, sun, sunset, cloud, drop, snowflake, bolt }

/// Saat dilimi (yerel saat) ve havaya göre çizilecek minik simgeler (saf; test edilir).
/// Sıra önemlidir: her simge listedeki konumuna göre sabit bir yere yerleşir.
List<JuzzioWeatherDoodle> juzzioWeatherDoodles(int hour, JuzzioWeatherKind kind) {
  final h = hour % 24;
  final List<JuzzioWeatherDoodle> base;
  if (h >= 21 || h < 6) {
    base = const [JuzzioWeatherDoodle.moon, JuzzioWeatherDoodle.star, JuzzioWeatherDoodle.star, JuzzioWeatherDoodle.cloud];
  } else if (h >= 17) {
    base = const [JuzzioWeatherDoodle.sunset, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.moon, JuzzioWeatherDoodle.star];
  } else {
    base = const [JuzzioWeatherDoodle.sun, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.sun];
  }
  switch (kind) {
    case JuzzioWeatherKind.drizzle:
    case JuzzioWeatherKind.rain:
      return [JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.drop, base.first, JuzzioWeatherDoodle.drop];
    case JuzzioWeatherKind.snow:
      return [JuzzioWeatherDoodle.snowflake, JuzzioWeatherDoodle.cloud, base.first, JuzzioWeatherDoodle.snowflake];
    case JuzzioWeatherKind.thunder:
      return [JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.bolt, JuzzioWeatherDoodle.drop, JuzzioWeatherDoodle.cloud];
    case JuzzioWeatherKind.clouds:
    case JuzzioWeatherKind.fog:
      return [JuzzioWeatherDoodle.cloud, base.first, JuzzioWeatherDoodle.cloud, base[1]];
    case JuzzioWeatherKind.clear:
      return base;
  }
}

class JuzzioWeatherAmbience extends StatefulWidget {
  const JuzzioWeatherAmbience({super.key});

  @override
  State<JuzzioWeatherAmbience> createState() => _JuzzioWeatherAmbienceState();
}

class _JuzzioWeatherAmbienceState extends State<JuzzioWeatherAmbience> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  final _svc = JuzzioWeatherService.instance;
  Timer? _hourTick; // saat dilimi değişince (gece → sabah) simgeler yenilenir

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.addListener(_sync);
    JuzzioAppController.instance.addListener(_sync);
    _updateLoop();
    _hourTick = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // arka planda pil harcanmaz
    if (s == AppLifecycleState.resumed) {
      _sync();
    } else {
      _loop.stop();
    }
  }

  bool get _animate =>
      !JuzzioAppController.instance.reduceMotion && !JuzzioGlassTokens.reducedEffects && _svc.state != null;

  void _updateLoop() {
    final st = _svc.state;
    // v1.2.7: açık havada da minik simgeler süzüldüğü için döngü her havada çalışır
    final need = _animate && st != null && JuzzioAppController.instance.weatherThemeEnabled;
    if (need && !_loop.isAnimating) _loop.repeat();
    if (!need && _loop.isAnimating) _loop.stop();
  }

  void _sync() {
    if (!mounted) return;
    _updateLoop();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hourTick?.cancel();
    _svc.removeListener(_sync);
    JuzzioAppController.instance.removeListener(_sync);
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _svc.state;
    if (st == null || !JuzzioAppController.instance.weatherThemeEnabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _WeatherPainter(
            t: _loop,
            kind: st.kind,
            isDay: st.isDay,
            dark: JuzzioAppController.instance.isDark,
            still: !_animate,
            hour: DateTime.now().hour,
          ),
        ),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter({
    required this.t,
    required this.kind,
    required this.isDay,
    required this.dark,
    required this.still,
    required this.hour,
  }) : super(repaint: t);

  final Animation<double> t;
  final JuzzioWeatherKind kind;
  final bool isDay;
  final bool dark;
  final bool still;
  final int hour;

  static final List<Offset> _seeds = List<Offset>.generate(70, (i) {
    final r = math.Random(i * 7349 + 11);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final v = still ? 0.0 : t.value;
    final a = dark ? 1.0 : 0.75; // aydınlık temada daha da hafif

    switch (kind) {
      case JuzzioWeatherKind.clear:
        _sunOrMoon(canvas, size, a);
      case JuzzioWeatherKind.clouds:
        _sunOrMoon(canvas, size, a * 0.5);
        _clouds(canvas, size, v, a, count: 4);
      case JuzzioWeatherKind.fog:
        final r = Rect.fromLTWH(0, h * 0.55, w, h * 0.45);
        canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.10 * a)],
            ).createShader(r),
        );
        _clouds(canvas, size, v, a * 0.7, count: 3);
      case JuzzioWeatherKind.drizzle:
        _clouds(canvas, size, v, a, count: 3);
        _rain(canvas, size, v, a, drops: 28, len: 9, alpha: 0.16);
      case JuzzioWeatherKind.rain:
        _clouds(canvas, size, v, a, count: 4);
        _rain(canvas, size, v, a, drops: 55, len: 16, alpha: 0.20);
      case JuzzioWeatherKind.thunder:
        _clouds(canvas, size, v, a, count: 5);
        _rain(canvas, size, v, a, drops: 60, len: 18, alpha: 0.22);
        // her 24 sn'lik turda iki kısa şimşek
        for (final at in const [0.31, 0.74]) {
          final d = (v - at).abs();
          if (d < 0.012) {
            canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.10 * (1 - d / 0.012) * a));
          }
        }
      case JuzzioWeatherKind.snow:
        _clouds(canvas, size, v, a * 0.6, count: 3);
        _snow(canvas, size, v, a);
    }
    _doodles(canvas, size, v, a);
  }

  // ---------------------------------------------------------------------------
  // v1.2.7 — minik vektör simgeler (🌙 ✦ ☀️ ☁️ 💧 ❄️ ⚡): 12 adet, ekrana dağılmış,
  // çok yavaş süzülür ve hafifçe sallanır. Boyut 11–19 px, saydamlık düşük.
  // ---------------------------------------------------------------------------
  void _doodles(Canvas canvas, Size size, double v, double a) {
    final kinds = juzzioWeatherDoodles(hour, kind);
    const count = 12;
    for (var i = 0; i < count; i++) {
      final s = _seeds[40 + i];
      final k = kinds[i % kinds.length];
      final drift = still ? 0.0 : v * (0.06 + 0.02 * (i % 3)); // 24 sn'de ekranın ~%6-10'u
      final x = ((s.dx + drift) % 1.0) * size.width;
      final y = (0.08 + 0.84 * ((s.dy + i * 0.083) % 1.0)) * size.height +
          (still ? 0.0 : math.sin((v * 2 + i * 0.37) * 2 * math.pi) * 6);
      final r = 5.5 + (i % 4) * 1.4;
      final alpha = (dark ? 0.30 : 0.36) * a;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(still ? 0 : math.sin((v + i * 0.21) * 2 * math.pi) * 0.12);
      _doodle(canvas, k, r, alpha);
      canvas.restore();
    }
  }

  void _doodle(Canvas canvas, JuzzioWeatherDoodle k, double r, double alpha) {
    Paint fill(Color c) => Paint()..color = c.withValues(alpha: alpha);
    switch (k) {
      case JuzzioWeatherDoodle.moon:
        // hilal: daire − kaydırılmış daire
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)),
          Path()..addOval(Rect.fromCircle(center: Offset(r * 0.48, -r * 0.30), radius: r * 0.86)),
        );
        canvas.drawPath(moon, fill(const Color(0xFFFFE08A)));
      case JuzzioWeatherDoodle.star:
        final p = Path();
        for (var j = 0; j < 8; j++) {
          final ang = j * math.pi / 4 - math.pi / 2;
          final rr = j.isEven ? r * 0.85 : r * 0.28;
          final pt = Offset(math.cos(ang) * rr, math.sin(ang) * rr);
          if (j == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        p.close();
        canvas.drawPath(p, fill(dark ? Colors.white : const Color(0xFFB9C3E6)));
      case JuzzioWeatherDoodle.sun:
      case JuzzioWeatherDoodle.sunset:
        final col = k == JuzzioWeatherDoodle.sun ? const Color(0xFFFFC23D) : const Color(0xFFFF8A4C);
        final rays = Paint()
          ..color = col.withValues(alpha: alpha)
          ..strokeWidth = math.max(1.2, r * 0.18)
          ..strokeCap = StrokeCap.round;
        for (var j = 0; j < 8; j++) {
          final ang = j * math.pi / 4;
          canvas.drawLine(Offset(math.cos(ang) * r * 0.78, math.sin(ang) * r * 0.78),
              Offset(math.cos(ang) * r * 1.12, math.sin(ang) * r * 1.12), rays);
        }
        canvas.drawCircle(Offset.zero, r * 0.55, fill(col));
      case JuzzioWeatherDoodle.cloud:
        final c = dark ? const Color(0xFFDDE5F5) : const Color(0xFF9FB0CF);
        final p = Path()
          ..addOval(Rect.fromCircle(center: Offset(-r * 0.55, r * 0.15), radius: r * 0.48))
          ..addOval(Rect.fromCircle(center: Offset(0, -r * 0.12), radius: r * 0.66))
          ..addOval(Rect.fromCircle(center: Offset(r * 0.60, r * 0.18), radius: r * 0.44))
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-r * 1.0, r * 0.05, r * 1.0, r * 0.62), Radius.circular(r * 0.3)));
        canvas.drawPath(p, fill(c));
      case JuzzioWeatherDoodle.drop:
        final p = Path()
          ..moveTo(0, -r)
          ..quadraticBezierTo(r * 0.75, 0, r * 0.55, r * 0.35)
          ..arcToPoint(Offset(-r * 0.55, r * 0.35), radius: Radius.circular(r * 0.58), clockwise: true)
          ..quadraticBezierTo(-r * 0.75, 0, 0, -r)
          ..close();
        canvas.drawPath(p, fill(const Color(0xFF6FA8FF)));
      case JuzzioWeatherDoodle.snowflake:
        final line = Paint()
          ..color = (dark ? Colors.white : const Color(0xFF8FB4E8)).withValues(alpha: alpha)
          ..strokeWidth = math.max(1.0, r * 0.14)
          ..strokeCap = StrokeCap.round;
        for (var j = 0; j < 3; j++) {
          final ang = j * math.pi / 3;
          final d = Offset(math.cos(ang) * r, math.sin(ang) * r);
          canvas.drawLine(-d, d, line);
        }
      case JuzzioWeatherDoodle.bolt:
        final p = Path()
          ..moveTo(r * 0.15, -r)
          ..lineTo(-r * 0.55, r * 0.12)
          ..lineTo(-r * 0.02, r * 0.12)
          ..lineTo(-r * 0.22, r)
          ..lineTo(r * 0.58, -r * 0.18)
          ..lineTo(r * 0.06, -r * 0.18)
          ..close();
        canvas.drawPath(p, fill(const Color(0xFFFFD43B)));
    }
  }

  void _sunOrMoon(Canvas canvas, Size size, double a) {
    final c = Offset(size.width * 0.86, size.height * 0.06);
    final col = isDay ? const Color(0xFFFFC46B) : const Color(0xFFB9C8FF);
    final r = size.shortestSide * 0.55;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [col.withValues(alpha: (isDay ? 0.20 : 0.14) * a), col.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    if (!isDay) {
      final p = Paint()..color = Colors.white.withValues(alpha: 0.35 * a);
      for (var i = 0; i < 14; i++) {
        final s = _seeds[i];
        canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height * 0.28), 0.8 + (i % 3) * 0.4, p);
      }
    }
  }

  void _clouds(Canvas canvas, Size size, double v, double a, {required int count}) {
    final p = Paint()
      ..color = (dark ? const Color(0xFFDDE3F0) : Colors.white).withValues(alpha: 0.07 * a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    for (var i = 0; i < count; i++) {
      final s = _seeds[20 + i];
      final x = ((s.dx + v * (0.25 + 0.1 * i)) % 1.3 - 0.15) * size.width;
      final y = size.height * (0.03 + 0.07 * s.dy);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: size.width * 0.55, height: 70), p);
    }
  }

  void _rain(Canvas canvas, Size size, double v, double a, {required int drops, required double len, required double alpha}) {
    final p = Paint()
      ..color = (dark ? const Color(0xFFBFD4FF) : const Color(0xFF6E86B8)).withValues(alpha: alpha * a)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    const slant = 0.22;
    for (var i = 0; i < drops; i++) {
      final s = _seeds[i % _seeds.length];
      final speed = 6.0 + (i % 5);
      final y = ((s.dy + v * speed) % 1.0) * (size.height + 40) - 20;
      final x = (s.dx * size.width + y * slant) % size.width;
      canvas.drawLine(Offset(x, y), Offset(x - len * slant, y - len), p);
    }
  }

  void _snow(Canvas canvas, Size size, double v, double a) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.45 * a);
    for (var i = 0; i < 40; i++) {
      final s = _seeds[i];
      final speed = 1.2 + (i % 4) * 0.35;
      final y = ((s.dy + v * speed) % 1.0) * (size.height + 20) - 10;
      final x = s.dx * size.width + math.sin((v * 8 + i) * math.pi) * 10;
      canvas.drawCircle(Offset(x, y), 1.2 + (i % 3) * 0.7, p);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter old) =>
      old.kind != kind || old.isDay != isDay || old.dark != dark || old.still != still || old.hour != hour;
}
