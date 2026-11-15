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
//  v1.2.8:
//   • Simgeler hikâye, video, arama ve diğer tam ekran sayfaların ÜSTÜNE binmez: katman yalnız
//     ana ekranda görünür (JuzzioAmbienceRouteObserver), başka sayfa açılınca yumuşakça söner.
//   • Hava/saat değişimi fark edilmeyecek kadar yumuşak: eski ve yeni sahne 12 sn boyunca
//     çapraz geçişle karışır; ilk görünüş de 3 sn'de belirir (ani "tema kayması" yok).
//   • Yağmurlu/fırtınalı havada ara sıra (20–55 sn'de bir) sol üstteki "Juzzio — senin alanın"
//     köşesinden gelen kutusu/mesajlar alanına kadar parlak bir şimşek çakar.
//  Okunabilirlik için saydamlık düşük tutulur. "Hareketi azalt" ve Performans modunda yalnız
//  durağan renk tonu çizilir (animasyon/ticker yok). Ayar: Görünüm → Hava durumu teması.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_weather_service.dart';
import 'juzzio_moon_phase.dart';
import 'juzzio_weather_sprites.dart';

/// v1.2.8: hava katmanının hangi sayfada görüneceğini izler. Yalnız ana ekranda (yığında tek
/// tam sayfa varken) görünür; hikâye, video, arama, profil vb. tam sayfalar açılınca söner.
/// Alt sayfalar/diyaloglar (PopupRoute) sayılmaz.
class JuzzioAmbienceRouteObserver extends NavigatorObserver {
  JuzzioAmbienceRouteObserver._();
  static final JuzzioAmbienceRouteObserver instance = JuzzioAmbienceRouteObserver._();

  /// Katman görünebilir mi (ana ekran en üstte mi)
  final ValueNotifier<bool> onHome = ValueNotifier<bool>(true);
  final List<Route<dynamic>> _pages = <Route<dynamic>>[];

  /// v1.2.9: rota yığınından bağımsız gizleme sahipleri (hikâye, video, sohbet içi medya,
  /// sohbet penceresi, keşfet/reels sekmeleri). Biri bile varsa katman görünmez.
  final Set<Object> _holds = <Object>{};

  void _recount() => onHome.value = juzzioAmbienceVisibleForPages(_pages.length) && _holds.isEmpty;

  /// [key] için katmanı gizle (on=true) ya da gizlemeyi bırak. Kare sonunda uygulanır
  /// (derleme sırasında başka widget'ı yeniden çizdirmez).
  void hold(Object key, bool on) {
    final changed = on ? _holds.add(key) : _holds.remove(key);
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recount());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PopupRoute) _pages.add(route);
    _recount();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _recount();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _recount();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i >= 0) _pages.removeAt(i);
    if (newRoute != null && newRoute is! PopupRoute) {
      if (i >= 0) {
        _pages.insert(i, newRoute);
      } else {
        _pages.add(newRoute);
      }
    }
    _recount();
  }
}

/// Yığındaki tam sayfa sayısına göre katman görünür mü (saf; test edilir).
bool juzzioAmbienceVisibleForPages(int pages) => pages <= 1;

/// Şimşek çakacak hava mı (saf; test edilir)
bool juzzioWeatherHasLightning(JuzzioWeatherKind k) =>
    k == JuzzioWeatherKind.rain || k == JuzzioWeatherKind.drizzle || k == JuzzioWeatherKind.thunder;

/// Çapraz geçiş süresi (fark edilmeyecek kadar yavaş)
const Duration kJuzzioWeatherCrossfade = Duration(seconds: 12);

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

/// Sahne kimliği: hava türü + gündüz/gece + saat dilimi (simge seti)
class _Scene {
  const _Scene(this.kind, this.isDay, this.hour);
  final JuzzioWeatherKind kind;
  final bool isDay;
  final int hour;
  int get band => (hour >= 21 || hour < 6) ? 0 : (hour >= 17 ? 2 : 1);
  bool same(_Scene o) => o.kind == kind && o.isDay == isDay && o.band == band;
}

class _JuzzioWeatherAmbienceState extends State<JuzzioWeatherAmbience> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  // v1.2.8: sahneler arası çok yavaş çapraz geçiş (ilk açılışta 0'dan belirir)
  late final AnimationController _fade = AnimationController(vsync: this, duration: kJuzzioWeatherCrossfade);
  // v1.2.8: yağmurda ara sıra çakan şimşek
  late final AnimationController _bolt = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _svc = JuzzioWeatherService.instance;
  final _route = JuzzioAmbienceRouteObserver.instance;
  Timer? _hourTick; // saat dilimi değişince (gece → sabah) simgeler yenilenir
  Timer? _boltTimer;
  final math.Random _rnd = math.Random();
  int _boltSeed = 1;
  _Scene? _cur;
  _Scene? _prev;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(JuzzioWeatherSprites.load());
    _svc.addListener(_sync);
    JuzzioAppController.instance.addListener(_sync);
    _route.onHome.addListener(_sync);
    _trackScene();
    _updateLoop();
    _hourTick = Timer.periodic(const Duration(minutes: 5), (_) => _sync());
  }

  bool get _visible => _route.onHome.value && JuzzioAppController.instance.weatherThemeEnabled && _svc.state != null;

  /// Yeni sahne geldiyse eskiyi tutup yavaşça yenisine geçer
  void _trackScene() {
    final st = _svc.state;
    if (st == null) return;
    final next = _Scene(st.kind, st.isDay, DateTime.now().hour);
    final cur = _cur;
    if (cur == null) {
      _cur = next;
      _prev = null;
      _fade.duration = const Duration(seconds: 3); // ilk belirme
      _fade.forward(from: 0);
      return;
    }
    if (cur.same(next)) {
      _cur = next; // aynı sahne: saat güncellenir, geçiş yok
      return;
    }
    // geçiş yarıdaysa o anki görüntü "önceki" kabul edilir (sıçrama olmaz)
    _prev = _fade.value < 0.5 && _prev != null ? _prev : cur;
    _cur = next;
    _fade.duration = kJuzzioWeatherCrossfade;
    _fade.forward(from: 0);
  }

  void _scheduleBolt() {
    _boltTimer?.cancel();
    final st = _svc.state;
    if (st == null || !_visible || !_animate || !juzzioWeatherHasLightning(st.kind)) return;
    final secs = st.kind == JuzzioWeatherKind.thunder ? 14 + _rnd.nextInt(22) : 22 + _rnd.nextInt(34);
    _boltTimer = Timer(Duration(seconds: secs), () {
      if (!mounted || !_visible) return;
      _boltSeed = _rnd.nextInt(1 << 30);
      _bolt.forward(from: 0);
      _scheduleBolt();
    });
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
    // v1.2.7: açık havada da simgeler süzülür; v1.2.8: katman görünmüyorsa (tam ekran
    // sayfa açık) döngü durur — pil ve kare harcanmaz
    final need = _animate && _visible;
    if (need && !_loop.isAnimating) _loop.repeat();
    if (!need && _loop.isAnimating) _loop.stop();
    if (need) {
      if (_boltTimer == null || !_boltTimer!.isActive) _scheduleBolt();
    } else {
      _boltTimer?.cancel();
    }
  }

  void _sync() {
    if (!mounted) return;
    final before = _svc.state?.kind;
    _trackScene();
    _updateLoop();
    if (before != null && !juzzioWeatherHasLightning(before)) _boltTimer?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hourTick?.cancel();
    _boltTimer?.cancel();
    _svc.removeListener(_sync);
    JuzzioAppController.instance.removeListener(_sync);
    _route.onHome.removeListener(_sync);
    _loop.dispose();
    _fade.dispose();
    _bolt.dispose();
    super.dispose();
  }

  Widget _scenePaint(_Scene sc) => CustomPaint(
        size: Size.infinite,
        painter: _WeatherPainter(
          t: _loop,
          kind: sc.kind,
          isDay: sc.isDay,
          dark: JuzzioAppController.instance.isDark,
          still: !_animate,
          hour: sc.hour,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = _svc.state;
    if (st == null || !JuzzioAppController.instance.weatherThemeEnabled) return const SizedBox.shrink();
    if (_cur == null) _trackScene(); // ilk sahne: 3 sn'de belirir
    final cur = _cur!;
    final prev = _prev;
    return IgnorePointer(
      // v1.2.8: tam ekran sayfa açılınca yumuşakça söner, ana ekrana dönünce belirir
      child: AnimatedOpacity(
        opacity: _route.onHome.value ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _fade,
            builder: (context, _) {
              final k = Curves.easeInOut.transform(_fade.value);
              final children = <Widget>[];
              if (prev != null && k < 1) children.add(Opacity(opacity: 1 - k, child: _scenePaint(prev)));
              children.add(k >= 1 ? _scenePaint(cur) : Opacity(opacity: k, child: _scenePaint(cur)));
              if (juzzioWeatherHasLightning(cur.kind) && _animate) {
                children.add(CustomPaint(size: Size.infinite, painter: _LightningPainter(t: _bolt, seed: _boltSeed)));
              }
              return Stack(fit: StackFit.expand, children: children);
            },
          ),
        ),
      ),
    );
  }
}

/// v1.2.8 — parlak şimşek: sol üst köşeden (Juzzio — senin alanın / gelen kutusu başlığı)
/// zikzakla mesajlar alanına kadar iner, dallanır, iki kez parlar; ekran kısa süre aydınlanır.
class _LightningPainter extends CustomPainter {
  _LightningPainter({required this.t, required this.seed}) : super(repaint: t);
  final Animation<double> t;
  final int seed;

  /// İki darbeli parlaklık eğrisi (0..1)
  static double _intensity(double v) {
    if (v <= 0 || v >= 1) return 0;
    double pulse(double c, double w) => math.max(0, 1 - ((v - c) / w).abs());
    return math.min(1, pulse(0.08, 0.08) + pulse(0.30, 0.10) * 0.85 + pulse(0.55, 0.25) * 0.35);
  }

  List<Offset> _bolt(math.Random r, Offset from, Offset to, int segs, double jag) {
    final pts = <Offset>[from];
    for (var i = 1; i < segs; i++) {
      final k = i / segs;
      final base = Offset.lerp(from, to, k)!;
      final n = Offset(-(to.dy - from.dy), to.dx - from.dx);
      final len = n.distance == 0 ? 1.0 : n.distance;
      pts.add(base + n / len * ((r.nextDouble() - 0.5) * 2 * jag));
    }
    pts.add(to);
    return pts;
  }

  void _stroke(Canvas canvas, List<Offset> pts, double width, double alpha) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF9EC9FF).withValues(alpha: 0.45 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = _intensity(t.value);
    if (a <= 0.001) return;
    final w = size.width, h = size.height;
    // ekran kısa süre aydınlanır (sol üstten yayılan ışık)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.85, -0.85),
          radius: 1.4,
          colors: [Colors.white.withValues(alpha: 0.22 * a), Colors.white.withValues(alpha: 0.05 * a)],
        ).createShader(Offset.zero & size),
    );
    final r = math.Random(seed);
    final from = Offset(w * (0.05 + r.nextDouble() * 0.06), h * 0.06);
    final to = Offset(w * (0.38 + r.nextDouble() * 0.2), h * (0.38 + r.nextDouble() * 0.1));
    final main = _bolt(r, from, to, 11, w * 0.045);
    _stroke(canvas, main, 2.6, a);
    // 2–3 dal
    for (var b = 0; b < 2 + r.nextInt(2); b++) {
      final at = main[3 + r.nextInt(main.length - 5)];
      final end = at + Offset(w * (0.06 + r.nextDouble() * 0.12), h * (0.05 + r.nextDouble() * 0.08));
      _stroke(canvas, _bolt(r, at, end, 5, w * 0.025), 1.4, a * 0.8);
    }
  }

  @override
  bool shouldRepaint(covariant _LightningPainter old) => old.seed != seed;
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

  // v1.2.9: daha gerçekçi vektörler — radyal gölgeli güneş/ay, gerçek Ay evresi + kraterler,
  // alt tarafı gölgeli katmanlı bulut, parlama noktalı damla, dallı kar tanesi, parıldayan yıldız
  void _doodle(Canvas canvas, JuzzioWeatherDoodle k, double r, double alpha) {
    Paint fill(Color c) => Paint()..color = c.withValues(alpha: alpha);
    final box = Rect.fromCircle(center: Offset.zero, radius: r * 1.2);
    switch (k) {
      case JuzzioWeatherDoodle.moon:
        juzzioPaintMoon(canvas, _moonPhase, r, alpha: math.min(1.0, alpha * 2.2), glow: false);
      case JuzzioWeatherDoodle.star:
        // 4 köşeli parıltı + yumuşak hâle
        canvas.drawCircle(Offset.zero, r * 0.9, Paint()
          ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: alpha * 0.8), Colors.white.withValues(alpha: 0)]).createShader(box));
        final p = Path()
          ..moveTo(0, -r)
          ..quadraticBezierTo(r * 0.12, -r * 0.12, r, 0)
          ..quadraticBezierTo(r * 0.12, r * 0.12, 0, r)
          ..quadraticBezierTo(-r * 0.12, r * 0.12, -r, 0)
          ..quadraticBezierTo(-r * 0.12, -r * 0.12, 0, -r)
          ..close();
        canvas.drawPath(p, fill(dark ? Colors.white : const Color(0xFFB9C3E6)));
      case JuzzioWeatherDoodle.sun:
      case JuzzioWeatherDoodle.sunset:
        final ss = JuzzioWeatherSprites.sun;
        if (ss != null) {
          canvas.drawImageRect(
            ss,
            Rect.fromLTWH(0, 0, ss.width.toDouble(), ss.height.toDouble()),
            Rect.fromCircle(center: Offset.zero, radius: r * 2.4),
            Paint()
              ..filterQuality = FilterQuality.low
              ..color = Colors.white.withValues(alpha: math.min(1.0, alpha * 1.8))
              ..colorFilter = k == JuzzioWeatherDoodle.sunset ? const ColorFilter.mode(Color(0xFFFF9A6B), BlendMode.modulate) : null,
          );
          break;
        }
        final core = k == JuzzioWeatherDoodle.sun ? const Color(0xFFFFE27A) : const Color(0xFFFFB067);
        final edge = k == JuzzioWeatherDoodle.sun ? const Color(0xFFFFA81F) : const Color(0xFFFF6A3D);
        canvas.drawCircle(Offset.zero, r * 1.25, Paint()
          ..shader = RadialGradient(colors: [edge.withValues(alpha: alpha * 0.55), edge.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 1.25)));
        // incelen ışınlar
        for (var j = 0; j < 12; j++) {
          final ang = j * math.pi / 6;
          final len = j.isEven ? 1.15 : 0.98;
          final p = Path()
            ..moveTo(math.cos(ang - 0.09) * r * 0.66, math.sin(ang - 0.09) * r * 0.66)
            ..lineTo(math.cos(ang) * r * len, math.sin(ang) * r * len)
            ..lineTo(math.cos(ang + 0.09) * r * 0.66, math.sin(ang + 0.09) * r * 0.66)
            ..close();
          canvas.drawPath(p, fill(edge));
        }
        canvas.drawCircle(Offset.zero, r * 0.58, Paint()
          ..shader = RadialGradient(center: const Alignment(-0.3, -0.3), colors: [core.withValues(alpha: math.min(1.0, alpha * 1.6)), edge.withValues(alpha: alpha)]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.58)));
      case JuzzioWeatherDoodle.cloud:
        // v1.2.9: gerçekçi kümülüs görseli (kodla üretilmiş); yüklenemezse aşağıdaki vektör çizim
        final cs = r > 14 ? JuzzioWeatherSprites.cloudA : JuzzioWeatherSprites.cloudB;
        if (cs != null) {
          final w = r * 2.6, h = w * cs.height / cs.width;
          canvas.drawImageRect(
            cs,
            Rect.fromLTWH(0, 0, cs.width.toDouble(), cs.height.toDouble()),
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Paint()
              ..filterQuality = FilterQuality.low
              ..color = Colors.white.withValues(alpha: math.min(1.0, alpha * (dark ? 1.5 : 2.0)))
              ..colorFilter = dark ? null : const ColorFilter.mode(Color(0xFF8FA3C8), BlendMode.modulate),
          );
          break;
        }
        final top = dark ? const Color(0xFFF2F6FF) : const Color(0xFFB4C3DE);
        final bottom = dark ? const Color(0xFF9AA8C4) : const Color(0xFF7F92B6);
        final p = Path()
          ..addOval(Rect.fromCircle(center: Offset(-r * 0.62, r * 0.18), radius: r * 0.44))
          ..addOval(Rect.fromCircle(center: Offset(-r * 0.15, -r * 0.18), radius: r * 0.58))
          ..addOval(Rect.fromCircle(center: Offset(r * 0.38, -r * 0.05), radius: r * 0.5))
          ..addOval(Rect.fromCircle(center: Offset(r * 0.78, r * 0.22), radius: r * 0.36))
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-r * 1.0, r * 0.05, r * 1.08, r * 0.6), Radius.circular(r * 0.28)));
        // yumuşak gölge
        canvas.save();
        canvas.translate(0, r * 0.12);
        canvas.drawPath(p, Paint()
          ..color = Colors.black.withValues(alpha: alpha * 0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
        canvas.restore();
        canvas.drawPath(p, Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top.withValues(alpha: math.min(1.0, alpha * 1.4)), bottom.withValues(alpha: alpha)])
              .createShader(Rect.fromLTRB(-r, -r * 0.8, r, r * 0.6)));
      case JuzzioWeatherDoodle.drop:
        final p = Path()
          ..moveTo(0, -r)
          ..cubicTo(r * 0.35, -r * 0.45, r * 0.72, -r * 0.05, r * 0.6, r * 0.35)
          ..arcToPoint(Offset(-r * 0.6, r * 0.35), radius: Radius.circular(r * 0.62), clockwise: true)
          ..cubicTo(-r * 0.72, -r * 0.05, -r * 0.35, -r * 0.45, 0, -r)
          ..close();
        canvas.drawPath(p, Paint()
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [const Color(0xFFB8DAFF).withValues(alpha: math.min(1.0, alpha * 1.3)), const Color(0xFF3D7EEA).withValues(alpha: alpha)])
              .createShader(box));
        canvas.drawOval(Rect.fromCenter(center: Offset(-r * 0.22, r * 0.12), width: r * 0.2, height: r * 0.36), Paint()..color = Colors.white.withValues(alpha: math.min(1.0, alpha * 1.2)));
      case JuzzioWeatherDoodle.snowflake:
        final line = Paint()
          ..color = (dark ? Colors.white : const Color(0xFF8FB4E8)).withValues(alpha: math.min(1.0, alpha * 1.3))
          ..strokeWidth = math.max(0.9, r * 0.11)
          ..strokeCap = StrokeCap.round;
        for (var j = 0; j < 6; j++) {
          final ang = j * math.pi / 3;
          final d = Offset(math.cos(ang), math.sin(ang));
          canvas.drawLine(Offset.zero, d * r, line);
          // her kolda iki dal
          for (final at in const [0.45, 0.72]) {
            final base = d * r * at;
            for (final side in const [-1, 1]) {
              final b = Offset(math.cos(ang + side * 0.75), math.sin(ang + side * 0.75)) * r * 0.26;
              canvas.drawLine(base, base + b, line);
            }
          }
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
        canvas.drawPath(p, Paint()
          ..color = const Color(0xFFFFE066).withValues(alpha: alpha * 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3));
        canvas.drawPath(p, Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [const Color(0xFFFFF3B0).withValues(alpha: math.min(1.0, alpha * 1.5)), const Color(0xFFFFB800).withValues(alpha: alpha)])
              .createShader(box));
    }
  }

  static double get _moonPhase => juzzioMoonPhase(DateTime.now());

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


/// v1.2.9: içindeyken hava katmanını gizler (hikâye görüntüleyici, video oynatıcılar, tam ekran medya)
class JuzzioAmbienceHide extends StatefulWidget {
  const JuzzioAmbienceHide({super.key, required this.child});
  final Widget child;

  @override
  State<JuzzioAmbienceHide> createState() => _JuzzioAmbienceHideState();
}

class _JuzzioAmbienceHideState extends State<JuzzioAmbienceHide> {
  final Object _key = Object();

  @override
  void initState() {
    super.initState();
    JuzzioAmbienceRouteObserver.instance.hold(_key, true);
  }

  @override
  void dispose() {
    JuzzioAmbienceRouteObserver.instance.hold(_key, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
