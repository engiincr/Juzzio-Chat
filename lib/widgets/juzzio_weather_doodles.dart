// =============================================================================
// JUZZIO v2.2.0 — "Gökyüzü doodle" hava katmanı (Engin'in gönderdiği referans görseller esas alındı)
//  Referans 1 (Ayarlar, gündüz bulutlu): ekrana dağılmış küçük düz bulut simgeleri + ince ışınlı
//  güneşler. Referans 2 (Mesajlar, gece yağmurlu): ince eğik yağmur çizgileri, mavi damlalar,
//  hilal ay. Hepsi kodla çizilir (görsel dosyası yok), içeriğin ARKASINDA durur, dokunmayı
//  engellemez, her temada aynı biçimde görünür (renkler gece/gündüze göre ayarlanır).
//  • JuzzioDoodleSkyPainter : sahneyi çizer (saf yerleşim yardımcıları test edilir)
//  • JuzzioWeatherDoodleLayer: ana ekran dışındaki sayfalar (Ayarlar vb.) için bağımsız katman
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_weather_service.dart';
import 'juzzio_moon_phase.dart';

/// Katmanda çizilen simge türleri
enum JuzzioDoodleKind { cloud, sun, moon, star, drop, snowflake, bolt }

/// Ekrandaki bir simge: göreli konum (0..1), boyut (px) ve tür
class JuzzioDoodleSlot {
  const JuzzioDoodleSlot(this.kind, this.x, this.y, this.size);
  final JuzzioDoodleKind kind;
  final double x;
  final double y;
  final double size;
}

/// Hava ve gece/gündüze göre simge dizisi (saf; test edilir).
/// Gece hilal ay tek ve üstte; gündüz güneşler; yağmurda damlalar; karda kar taneleri.
List<JuzzioDoodleKind> juzzioDoodleKinds(JuzzioWeatherKind kind, {required bool night}) {
  const c = JuzzioDoodleKind.cloud;
  final sky = night ? JuzzioDoodleKind.star : JuzzioDoodleKind.sun;
  switch (kind) {
    case JuzzioWeatherKind.clear:
      return night ? [c, sky, sky, c, sky, sky, c, sky, sky, c] : [c, sky, c, c, sky, c, c, sky, c, c];
    case JuzzioWeatherKind.clouds:
      return night ? [c, c, sky, c, c, c, sky, c, c, c] : [c, sky, c, c, c, sky, c, c, sky, c];
    case JuzzioWeatherKind.fog:
      return const [c, c, c, c, c, c, c, c];
    case JuzzioWeatherKind.drizzle:
    case JuzzioWeatherKind.rain:
      const d = JuzzioDoodleKind.drop;
      return [c, d, c, d, c, d, c, d, c, d];
    case JuzzioWeatherKind.snow:
      const f = JuzzioDoodleKind.snowflake;
      return [f, c, f, f, c, f, f, c, f, f];
    case JuzzioWeatherKind.thunder:
      const d = JuzzioDoodleKind.drop, b = JuzzioDoodleKind.bolt;
      return [c, d, b, c, d, c, b, d, c, d];
  }
}

/// Yağmur çizgisi sayısı (0 = yağmur yok; saf, test edilir)
int juzzioRainStreaks(JuzzioWeatherKind kind) {
  switch (kind) {
    case JuzzioWeatherKind.drizzle:
      return 26;
    case JuzzioWeatherKind.rain:
      return 44;
    case JuzzioWeatherKind.thunder:
      return 56;
    default:
      return 0;
  }
}

/// Simgelerin ekrana dağılımı (saf; test edilir). Başlık ve alt gezinme şeridi bölgesine simge
/// konmaz ([top] ve [bottom] göreli sınırlar). Konumlar sabittir: aynı havada hep aynı yerler.
List<JuzzioDoodleSlot> juzzioDoodleLayout(List<JuzzioDoodleKind> kinds, {double top = 0.14, double bottom = 0.88}) {
  final out = <JuzzioDoodleSlot>[];
  final n = kinds.length;
  if (n == 0) return out;
  const cols = 3;
  final rows = (n / cols).ceil();
  for (var i = 0; i < n; i++) {
    final r = math.Random(i * 7349 + 113);
    final row = i ~/ cols, col = i % cols;
    // satırlar arası kaydırma: ızgara hissi vermez
    final shift = row.isOdd ? 0.16 : 0.0;
    final x = ((col + 0.5) / cols + shift + (r.nextDouble() - 0.5) * 0.18) % 1.0;
    final y = top + (bottom - top) * ((row + 0.5 + (r.nextDouble() - 0.5) * 0.5) / rows);
    final k = kinds[i];
    final size = switch (k) {
      JuzzioDoodleKind.cloud => 30 + r.nextDouble() * 26,
      JuzzioDoodleKind.sun => 30 + r.nextDouble() * 10,
      JuzzioDoodleKind.moon => 34,
      JuzzioDoodleKind.star => 8 + r.nextDouble() * 6,
      JuzzioDoodleKind.drop => 16 + r.nextDouble() * 8,
      JuzzioDoodleKind.snowflake => 14 + r.nextDouble() * 8,
      JuzzioDoodleKind.bolt => 18 + r.nextDouble() * 6,
    };
    out.add(JuzzioDoodleSlot(k, x.clamp(0.06, 0.94), y.clamp(top, bottom), size));
  }
  return out;
}

class JuzzioDoodleSkyPainter extends CustomPainter {
  JuzzioDoodleSkyPainter({
    required this.t,
    required this.kind,
    required this.night,
    required this.dark,
    required this.still,
    required this.moonPhase,
    this.topInset = 0,
  }) : super(repaint: t);

  final Animation<double> t;
  final JuzzioWeatherKind kind;
  final bool night;
  final bool dark;
  final bool still;
  final double moonPhase;
  final double topInset;

  static final List<Offset> _seeds = List<Offset>.generate(64, (i) {
    final r = math.Random(i * 911 + 7);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final v = still ? 0.0 : t.value;
    final topRel = ((topInset + 92) / size.height).clamp(0.08, 0.3);
    final streaks = juzzioRainStreaks(kind);
    if (streaks > 0) _rain(canvas, size, v, streaks);
    if (kind == JuzzioWeatherKind.snow) _snow(canvas, size, v);
    if (kind == JuzzioWeatherKind.fog) _fog(canvas, size);
    // gece hilal ay: üst bandın sağında, başlığın hemen altında (referanstaki gibi)
    if (night) {
      final mc = Offset(size.width * 0.72, size.height * topRel + 6);
      _moon(canvas, mc, 17);
    }
    final slots = juzzioDoodleLayout(juzzioDoodleKinds(kind, night: night), top: topRel + 0.06);
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final drift = still ? 0.0 : math.sin((v + i * 0.13) * 2 * math.pi) * 6;
      final bob = still ? 0.0 : math.cos((v * 2 + i * 0.29) * 2 * math.pi) * 3;
      final c = Offset(s.x * size.width + drift, s.y * size.height + bob);
      switch (s.kind) {
        case JuzzioDoodleKind.cloud:
          _cloud(canvas, c, s.size);
        case JuzzioDoodleKind.sun:
          _sun(canvas, c, s.size / 2, still ? 0.0 : v * 2 * math.pi * 0.25);
        case JuzzioDoodleKind.moon:
          _moon(canvas, c, s.size / 2);
        case JuzzioDoodleKind.star:
          _star(canvas, c, s.size / 2, still ? 1.0 : 0.6 + 0.4 * math.sin((v * 6 + i) * math.pi).abs());
        case JuzzioDoodleKind.drop:
          _drop(canvas, c, s.size / 2);
        case JuzzioDoodleKind.snowflake:
          _flake(canvas, c, s.size / 2);
        case JuzzioDoodleKind.bolt:
          _bolt(canvas, c, s.size / 2);
      }
    }
  }

  // Düz, yumuşak köşeli bulut simgesi (referanstaki gri-mavi bulutlar)
  void _cloud(Canvas canvas, Offset c, double w) {
    final h = w * 0.62;
    final col = dark ? const Color(0xFF8DA4C6) : const Color(0xFF7E95BA);
    final a = dark ? 0.42 : 0.38;
    final l = c.dx - w / 2, b = c.dy + h / 2;
    final p = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(l, b - h * 0.46, l + w, b), Radius.circular(h * 0.23)))
      ..addOval(Rect.fromCircle(center: Offset(l + w * 0.32, b - h * 0.46), radius: h * 0.30))
      ..addOval(Rect.fromCircle(center: Offset(l + w * 0.60, b - h * 0.56), radius: h * 0.40));
    canvas.drawPath(p, Paint()..color = col.withValues(alpha: a));
  }

  // İnce ışınlı güneş (referanstaki küçük güneşler)
  void _sun(Canvas canvas, Offset c, double r, double spin) {
    final ray = Paint()
      ..color = const Color(0xFFF2B84B).withValues(alpha: dark ? 0.55 : 0.7)
      ..strokeWidth = math.max(1.2, r * 0.09)
      ..strokeCap = StrokeCap.round;
    for (var j = 0; j < 8; j++) {
      final ang = spin + j * math.pi / 4;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c + d * r * 0.62, c + d * r * 0.95, ray);
    }
    canvas.drawCircle(c, r * 0.42, Paint()..color = const Color(0xFFF6C453).withValues(alpha: dark ? 0.6 : 0.75));
  }

  // Düz hilal / evreli ay (gri-bej; gerçek Ay evresine göre aydınlık kısım)
  void _moon(Canvas canvas, Offset c, double r) {
    final lit = const Color(0xFFD8CFB8).withValues(alpha: dark ? 0.72 : 0.8);
    canvas.drawPath(juzzioFlatMoonPath(c, r, moonPhase), Paint()..color = lit);
  }

  void _star(Canvas canvas, Offset c, double r, double tw) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.15, c.dy - r * 0.15, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.15, c.dy + r * 0.15, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.15, c.dy + r * 0.15, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.15, c.dy - r * 0.15, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = (dark ? Colors.white : const Color(0xFF8A9CC4)).withValues(alpha: 0.5 * tw));
  }

  // Mavi damla (referanstaki gibi)
  void _drop(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..cubicTo(c.dx + r * 0.35, c.dy - r * 0.4, c.dx + r * 0.7, c.dy, c.dx + r * 0.58, c.dy + r * 0.38)
      ..arcToPoint(Offset(c.dx - r * 0.58, c.dy + r * 0.38), radius: Radius.circular(r * 0.6), clockwise: true)
      ..cubicTo(c.dx - r * 0.7, c.dy, c.dx - r * 0.35, c.dy - r * 0.4, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF4F7FD9).withValues(alpha: dark ? 0.6 : 0.55));
  }

  void _flake(Canvas canvas, Offset c, double r) {
    final line = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF8FB4E8)).withValues(alpha: 0.55)
      ..strokeWidth = math.max(1.0, r * 0.12)
      ..strokeCap = StrokeCap.round;
    for (var j = 0; j < 6; j++) {
      final ang = j * math.pi / 3;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c, c + d * r, line);
      final base = c + d * r * 0.55;
      for (final side in const [-1, 1]) {
        canvas.drawLine(base, base + Offset(math.cos(ang + side * 0.8), math.sin(ang + side * 0.8)) * r * 0.3, line);
      }
    }
  }

  void _bolt(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx + r * 0.15, c.dy - r)
      ..lineTo(c.dx - r * 0.55, c.dy + r * 0.12)
      ..lineTo(c.dx - r * 0.02, c.dy + r * 0.12)
      ..lineTo(c.dx - r * 0.22, c.dy + r)
      ..lineTo(c.dx + r * 0.58, c.dy - r * 0.18)
      ..lineTo(c.dx + r * 0.06, c.dy - r * 0.18)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFFFD54A).withValues(alpha: 0.6));
  }

  // İnce, hafif eğik yağmur çizgileri (referanstaki gibi)
  void _rain(Canvas canvas, Size size, double v, int n) {
    final p = Paint()
      ..color = (dark ? const Color(0xFFCFDCF5) : const Color(0xFF6E86B8)).withValues(alpha: dark ? 0.22 : 0.28)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    const slant = 0.12;
    for (var i = 0; i < n; i++) {
      final s = _seeds[i % _seeds.length];
      final len = 14.0 + (i % 4) * 5;
      final speed = 3.0 + (i % 5);
      final y = ((s.dy + v * speed) % 1.0) * (size.height + 60) - 30;
      final x = (s.dx * size.width + y * slant) % size.width;
      canvas.drawLine(Offset(x, y), Offset(x - len * slant, y - len), p);
    }
  }

  void _snow(Canvas canvas, Size size, double v) {
    final p = Paint()..color = Colors.white.withValues(alpha: dark ? 0.5 : 0.7);
    for (var i = 0; i < 36; i++) {
      final s = _seeds[i];
      final y = ((s.dy + v * (1.2 + (i % 4) * 0.35)) % 1.0) * (size.height + 20) - 10;
      final x = s.dx * size.width + math.sin((v * 8 + i) * math.pi) * 10;
      canvas.drawCircle(Offset(x, y), 1.2 + (i % 3) * 0.7, p);
    }
  }

  void _fog(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(0, size.height * 0.5, size.width, size.height * 0.5);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: dark ? 0.07 : 0.12)],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant JuzzioDoodleSkyPainter old) =>
      old.kind != kind || old.night != night || old.dark != dark || old.still != still || old.topInset != topInset;
}

/// Düz (gölgesiz) ay şekli: [phase] 0 = yeni ay, 0.5 = dolunay, 1 = yeni ay (saf; test edilir).
/// Yeni aya çok yakınken bile ince bir hilal görünür (referanstaki hilal).
Path juzzioFlatMoonPath(Offset c, double r, double phase) {
  final ph = phase.isFinite ? phase % 1.0 : 0.25;
  // aydınlık oran 0..1 (yeni ayda en az %18'lik hilal)
  final illum = math.max(0.18, (1 - math.cos(ph * 2 * math.pi)) / 2);
  final waxing = ph < 0.5;
  final rect = Rect.fromCircle(center: c, radius: r);
  // aydınlık kenar yarım dairesi
  final outer = Path()..addArc(rect, waxing ? -math.pi / 2 : math.pi / 2, math.pi);
  // sınır elipsi: genişlik |1 - 2*illum| * r
  final k = (1 - 2 * illum);
  final ew = (k.abs() * r).clamp(0.0, r);
  final ellipse = Rect.fromCenter(center: c, width: ew * 2, height: r * 2);
  final p = Path()..addPath(outer, Offset.zero);
  // elips yarısı: hilalde içe, şişkin ayda dışa doğru
  final inward = k > 0;
  final start = waxing ? math.pi / 2 : -math.pi / 2;
  final sweep = inward ? -math.pi : math.pi;
  p.arcTo(ellipse, start, sweep, false);
  p.close();
  return p;
}

/// Ana ekran dışındaki sayfalarda (Ayarlar, Arkadaşlar…) aynı hava katmanı. Ayarda kapalıysa,
/// hava bilgisi yoksa ya da "Hareketi azalt" açıksa durağan çizilir/çizilmez.
class JuzzioWeatherDoodleLayer extends StatefulWidget {
  const JuzzioWeatherDoodleLayer({super.key});

  @override
  State<JuzzioWeatherDoodleLayer> createState() => _JuzzioWeatherDoodleLayerState();
}

class _JuzzioWeatherDoodleLayerState extends State<JuzzioWeatherDoodleLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 30));
  final _svc = JuzzioWeatherService.instance;
  final _app = JuzzioAppController.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_sync);
    _app.addListener(_sync);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
  }

  bool get _animate => !_app.reduceMotion && !JuzzioGlassTokens.reducedEffects;

  void _sync() {
    if (!mounted) return;
    final need = _animate && _app.weatherThemeEnabled && _svc.state != null && TickerMode.of(context);
    if (need && !_loop.isAnimating) _loop.repeat();
    if (!need && _loop.isAnimating) _loop.stop();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _svc.removeListener(_sync);
    _app.removeListener(_sync);
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _svc.state;
    if (st == null || !_app.weatherThemeEnabled) return const SizedBox.shrink();
    final fresh = DateTime.now().difference(st.fetchedAt) <= const Duration(hours: 3);
    final night = juzzioIsNightNowForDoodles(DateTime.now(), isDay: fresh ? st.isDay : null);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: JuzzioDoodleSkyPainter(
            t: _loop,
            kind: st.kind,
            night: night,
            dark: _app.isDark,
            still: !_animate,
            moonPhase: juzzioMoonPhase(DateTime.now()),
            topInset: MediaQuery.maybeOf(context)?.padding.top ?? 0,
          ),
        ),
      ),
    );
  }
}

/// Gece mi (saf): hava bilgisi tazeyse onun gündüz/gece bilgisi, değilse yerel saat 19:00–06:00.
bool juzzioIsNightNowForDoodles(DateTime local, {bool? isDay}) {
  if (isDay != null) return !isDay;
  final h = local.hour;
  return h >= 19 || h < 6;
}
