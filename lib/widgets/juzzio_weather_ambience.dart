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
//  v2.1 — "Gökyüzü 2.1": sahne baştan tasarlandı (juzzio_sky21.dart). Konumun gerçek gün
//   doğumu/batımı ve ülke saatine göre gök rengi, yayda ilerleyen güneş/ay, göz kırpan yıldızlar,
//   parallaks bulutlar, rüzgârlı yağmur, sıçramalar ve bulut içi şimşek.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_weather_service.dart';
import '../services/juzzio_special_themes.dart';
import 'juzzio_moon_phase.dart' show juzzioMoonPhaseIndex;
import 'juzzio_sky21.dart';
import 'juzzio_special_theme_layer.dart';
import 'juzzio_weather_hd.dart';

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
/// v1.2.9: gökyüzü dilimi (saf; test edilir) — 0 gece, 1 gündüz, 2 akşam.
/// [isDay] cihazın konumundaki GERÇEK gündüz/gece bilgisidir (hava servisi, güneşin doğuşu/batışı);
/// biliniyorsa saatten önce gelir. Böylece ay yalnız o kişinin yerel gecesinde görünür.
int juzzioSkyBand(int hour, {bool? isDay}) {
  final h = hour % 24;
  final byHour = (h >= 21 || h < 6) ? 0 : (h >= 17 ? 2 : 1);
  if (isDay == false) return 0;
  if (isDay == true && byHour == 0) return 2;
  return byHour;
}

/// v1.2.9: şu an gece mi? (saf) — hava bilgisi taze değilse yerel saate göre 19:00–06:00.
bool juzzioIsNightNow(DateTime local, {bool? isDay}) {
  if (isDay != null) return !isDay;
  final h = local.hour;
  return h >= 19 || h < 6;
}

List<JuzzioWeatherDoodle> juzzioWeatherDoodles(int hour, JuzzioWeatherKind kind, {bool? isDay}) {
  final band = juzzioSkyBand(hour, isDay: isDay);
  final List<JuzzioWeatherDoodle> base;
  if (band == 0) {
    base = const [JuzzioWeatherDoodle.moon, JuzzioWeatherDoodle.star, JuzzioWeatherDoodle.star, JuzzioWeatherDoodle.cloud];
  } else if (band == 2) {
    // gün ışığı sürüyorsa akşam diliminde ay/yıldız çizilmez
    base = isDay == true
        ? const [JuzzioWeatherDoodle.sunset, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.sun]
        : const [JuzzioWeatherDoodle.sunset, JuzzioWeatherDoodle.cloud, JuzzioWeatherDoodle.moon, JuzzioWeatherDoodle.star];
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

class _JuzzioWeatherAmbienceState extends State<JuzzioWeatherAmbience> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 24));
  // v1.2.8: sahneler arası çok yavaş çapraz geçiş (ilk açılışta 0'dan belirir)
  late final AnimationController _fade = AnimationController(vsync: this, duration: kJuzzioWeatherCrossfade);
  // v1.2.8: yağmurda ara sıra çakan şimşek
  late final AnimationController _bolt = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  final _svc = JuzzioWeatherService.instance;
  final _route = JuzzioAmbienceRouteObserver.instance;
  Timer? _hourTick; // saat dilimi değişince (gece → sabah) simgeler yenilenir
  Timer? _boltTimer;
  final math.Random _rnd = math.Random();
  JuzzioSkyScene? _cur;
  JuzzioSkyScene? _prev;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.addListener(_sync);
    JuzzioAppController.instance.addListener(_sync);
    _route.onHome.addListener(_sync);
    JuzzioSpecialThemes.instance.addListener(_sync);
    _trackScene();
    _updateLoop();
    // v2.1: güneş/ay yayda ilerlesin diye her dakika yeniden hesaplanır
    _hourTick = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
  }

  JuzzioSpecialTheme get _special => JuzzioSpecialThemes.instance.active;

  bool get _visible =>
      _route.onHome.value &&
      (_special != JuzzioSpecialTheme.none || (JuzzioAppController.instance.weatherThemeEnabled && _svc.state != null));

  /// Yeni sahne geldiyse eskiyi tutup yavaşça yenisine geçer
  void _trackScene() {
    final st = _svc.state;
    if (st == null) return;
    final next = JuzzioSkyScene.from(st, DateTime.now().toUtc());
    final cur = _cur;
    if (cur == null) {
      _cur = next;
      _prev = null;
      _fade.duration = const Duration(seconds: 3); // ilk belirme
      _fade.forward(from: 0);
      return;
    }
    if (cur.same(next)) {
      _cur = next; // aynı sahne: güneş/ay konumu güncellenir, geçiş yok
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
    // GM-030: HD şimşek flaşı yalnız fırtınada (referans); özel temada hava yok
    if (st == null || !_visible || !_animate || st.kind != JuzzioWeatherKind.thunder || _special != JuzzioSpecialTheme.none) return;
    final secs = 8 + _rnd.nextInt(14);
    _boltTimer = Timer(Duration(seconds: secs), () {
      if (!mounted || !_visible) return;
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
      !JuzzioAppController.instance.reduceMotion &&
      !JuzzioGlassTokens.reducedEffects &&
      (_svc.state != null || _special != JuzzioSpecialTheme.none);

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
    JuzzioSpecialThemes.instance.removeListener(_sync);
    _loop.dispose();
    _fade.dispose();
    _bolt.dispose();
    super.dispose();
  }

  // v2.2.0: Engin'in referans görsellerindeki "doodle" gökyüzü — küçük düz bulutlar, ince ışınlı
  // güneşler, hilal ay, mavi damlalar ve ince yağmur çizgileri (JuzzioDoodleSkyPainter).
  // Gökyüzü 2.1'in büyük bulanık bulutları ve fotoğraf ay kaldırıldı.
  // GM-030 (v2.2.0): Sohbetler ekranında Engin'in HD şeffaf hava görselleri (referans yerleşim).
  // Eski "doodle" gökyüzü (JuzzioDoodleSkyPainter) diğer sayfalardaki küçük katmanda kalır.
  Widget _scenePaint(JuzzioSkyScene sc) => JuzzioHdWeatherScene(
        kind: sc.kind,
        night: sc.showMoon,
        dark: JuzzioAppController.instance.isDark,
        moonIndex: juzzioMoonPhaseIndex(sc.moonPhase),
        loop: _loop,
        bolt: _bolt,
        still: !_animate,
      );

  @override
  Widget build(BuildContext context) {
    // GM-029/031: özel gün teması etkinse hava katmanı ÇİZİLMEZ (dekoru örtmesin)
    final special = _special;
    if (special != JuzzioSpecialTheme.none) {
      return IgnorePointer(
        child: AnimatedOpacity(
          opacity: _route.onHome.value ? 1 : 0,
          duration: const Duration(milliseconds: 450),
          child: RepaintBoundary(
            child: JuzzioSpecialThemeLayer(
              key: ValueKey(special),
              theme: special,
              dark: JuzzioAppController.instance.isDark,
              loop: _animate ? _loop : const AlwaysStoppedAnimation<double>(0),
              accent: JuzzioGlassTokens.glow,
            ),
          ),
        ),
      );
    }
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
              // GM-030: şimşek flaşı HD sahnenin içinde (juzzioBoltFlash)
              // v2.2.0: katman içeriğin ARKASINDA; simgeler başlık ve alt şerit bölgesine konmaz
              // (juzzioDoodleLayout), yağmur çizgileri referanstaki gibi tüm ekranda.
              return Stack(fit: StackFit.expand, children: children);
            },
          ),
        ),
      ),
    );
  }
}

/// GM-014: hava katmanının "düğmesiz" bölgeleri (saf; test edilir).
/// Başlık bandı (güvenli alan + [kJuzzioAmbienceHeaderClear]) ve alt şerit
/// ([kJuzzioAmbienceDockClear]) tamamen temiz; aradaki içerik bölgesinde efektler %55 görünür.
const double kJuzzioAmbienceHeaderClear = 96;
const double kJuzzioAmbienceDockClear = 112;
const double kJuzzioAmbienceContentAlpha = 0.55;

List<double> juzzioAmbienceMaskStops(double height, {double topInset = 0, double bottomInset = 0}) {
  if (height <= 0) return const [0, 0, 1, 1];
  final top = ((topInset + kJuzzioAmbienceHeaderClear) / height).clamp(0.0, 0.45);
  final fadeIn = (top + 48 / height).clamp(top, 0.5);
  final bottom = (1 - (bottomInset + kJuzzioAmbienceDockClear) / height).clamp(0.55, 1.0);
  final fadeOut = (bottom - 48 / height).clamp(0.5, bottom);
  return [top, fadeIn, fadeOut, bottom];
}

Shader juzzioAmbienceSafeMask(Rect r, {double topInset = 0, double bottomInset = 0}) {
  final st = juzzioAmbienceMaskStops(r.height, topInset: topInset, bottomInset: bottomInset);
  final on = Colors.white.withValues(alpha: kJuzzioAmbienceContentAlpha);
  const off = Color(0x00FFFFFF);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [off, off, on, on, off, off],
    stops: [0, st[0], st[1], st[2], st[3], 1],
  ).createShader(r);
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
