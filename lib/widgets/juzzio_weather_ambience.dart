// =============================================================================
// JUZZIO v1.2.1 — Hava durumu ambiyansı (tema içi değişim)
//  Tüm sayfaların üstünde, dokunmayı ENGELLEMEYEN çok hafif bir katman:
//   • Açık: gündüz sıcak güneş ışıltısı (sağ üst), gece soğuk ay hâlesi + birkaç yıldız
//   • Bulutlu: üstte yavaş süzülen yumuşak bulutlar
//   • Sis: altta pus
//   • Çisenti / yağmur: ince eğik damlalar (yoğunluk türe göre)
//   • Kar: yavaş düşen kar taneleri
//   • Fırtına: yağmur + seyrek şimşek parlaması
//  Okunabilirlik için saydamlık düşük tutulur. "Hareketi azalt" ve Performans modunda yalnız
//  durağan renk tonu çizilir (animasyon/ticker yok). Ayar: Görünüm → Hava durumu teması.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_weather_service.dart';

class JuzzioWeatherAmbience extends StatefulWidget {
  const JuzzioWeatherAmbience({super.key});

  @override
  State<JuzzioWeatherAmbience> createState() => _JuzzioWeatherAmbienceState();
}

class _JuzzioWeatherAmbienceState extends State<JuzzioWeatherAmbience> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  final _svc = JuzzioWeatherService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.addListener(_sync);
    JuzzioAppController.instance.addListener(_sync);
    _updateLoop();
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
    final need = _animate && st != null && st.kind != JuzzioWeatherKind.clear && JuzzioAppController.instance.weatherThemeEnabled;
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
          ),
        ),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter({required this.t, required this.kind, required this.isDay, required this.dark, required this.still}) : super(repaint: t);

  final Animation<double> t;
  final JuzzioWeatherKind kind;
  final bool isDay;
  final bool dark;
  final bool still;

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
      old.kind != kind || old.isDay != isDay || old.dark != dark || old.still != still;
}
