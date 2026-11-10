// =============================================================================
// JUZZIO v1.2.1 — Kompakt 3B "Cloth-Pinch" aşağı çekip yenileme
//
//  Referans: "JUZZIO – COMPACT 3D PULL-TO-REFRESH SPECIFICATION" (5 aşama)
//   01 START   (0–20%)  : çentiğin (Dynamic Island) altından tombul kil elin parmak uçları görünür
//   02 EXTEND  (20–60%) : el aşağı uzanır; içerik aynı miktarda aşağı kayar → el başlığa DOKUNMAZ
//   03 PINCH   (100%)   : el yumruk yapar, ekran yüzeyi yumruğun altında kumaş gibi büzülür
//                         (yumuşak 3B gölge + hafif içe çekilme; yelpaze/radyal çizgi YOK)
//   04 RELEASE & SNAP   : parmak bırakılınca el beklemeden ~200 ms elastik yayla çentiğe çekilir
//   05 LOADING          : çentik ile başlık arasındaki boşlukta yalnız sade bir yükleme halkası döner;
//                         iş bitince liste sıfır konumuna oturur
//
//  Kurallar
//   • Elin dikey hareketi en fazla 80 dp:  travel = math.min(pull × 0.55, 80)
//   • Başlangıç noktası MediaQuery.padding.top (çentik) — ya da gömülü listelerde listenin üst kenarı
//   • onRefresh eşik aşıldığında TAM BİR KEZ çağrılır; yenileme sürerken yeni çekiş kilitlidir
//   • Eşik aşılmadan bırakılırsa hiçbir şey tetiklenmez, el süzülerek çekilir, durum sıfırlanır
//   • dispose: tüm AnimationController / Ticker kaynakları kapatılır
//   • disableAnimations (ve "Hareketi azalt") → 3B sekans atlanır, yalnız standart halka
//
//  v1.2.7 düzeltmesi ("ilk çekişte el sayfayı tutmuyor, ancak ikinci çekişte tutuyor"):
//   • Kök neden: eşik için ~145 dp aşağı çekmek gerekiyordu (travel = pull × 0.55) ve el yumruk
//     yaptıktan sonra parmak birkaç piksel geri gelince eşik kayboluyordu; ayrıca listenin tam
//     tepesinde BAŞLAMAYAN çekişler (tepeye varıp taşan) hiç kurulmuyordu.
//   • Artık: travel = pull × 0.8 (≈100 dp'de tutar), el bir kez yumruk yapınca KİLİTLENİR
//     (parmak %60'ın altına çekilmedikçe bırakınca yenileme kesin başlar) ve tepeye sonradan
//     varan çekişler de kurulur. El ~%20 büyütüldü.
//  Biçim: Rive/Lottie yerine vektör CustomPainter. Gerekçe: ek paket ve ağ yok, APK büyümez,
//  tema rengine göre anında boyanır, 60 FPS (tek RepaintBoundary, önbellekli Paint/gölge),
//  çentik ölçüsüne göre her ekranda keskin; varlık yüklemesi olmadığı için ilk karede takılma yok.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import 'juzzio_motion.dart';

/// Elin en fazla aşağı inebileceği mesafe (dp) — talimat: 75–80 dp
const double kJuzzioRefreshMaxTravel = 80.0;

/// Yenileme sırasında içeriğin bıraktığı boşluk (halka bu boşlukta döner)
const double kJuzzioRefreshSpinnerGap = 56.0;

/// Geri çekilme süresi (talimat: ~200 ms)
const Duration kJuzzioSnapBackDuration = Duration(milliseconds: 200);

/// Elastik geri çekilmenin sönümleme oranı (spesifikasyon diyagramı: 0.85)
const double kJuzzioSnapDamping = 0.85;

/// Çentik kapsülü rengi (çentiksiz ekranlarda çizilen sahte çentik)
const Color kJuzzioIslandColor = Color(0xFF000000);

/// Çekme mesafesi → elin dikey yolu (dp). Saf; test edilir.
double juzzioRefreshTravel(double pull) => math.min(math.max(pull, 0.0) * kJuzzioRefreshPullRatio, kJuzzioRefreshMaxTravel);

/// Parmak yolu → el yolu oranı (v1.2.7: 0.55 → 0.8; eşik ≈100 dp çekişte)
const double kJuzzioRefreshPullRatio = 0.8;

/// El yumruk yaptıktan sonra kilit bu oranın altına düşmedikçe korunur (v1.2.7)
const double kJuzzioRefreshLatchKeep = 0.6;

/// Bırakınca yenileme başlamalı mı: eşik şimdi aşılmışsa ya da el kilitliyse ve parmak
/// %60'ın altına geri çekilmemişse. Saf; test edilir.
bool juzzioRefreshShouldFire(double travel, {required bool latched}) =>
    juzzioRefreshArmed(travel) || (latched && juzzioRefreshProgress(travel) >= kJuzzioRefreshLatchKeep);

/// Elin boyut çarpanı (v1.2.7: ~%20 daha tombul/büyük)
const double kJuzzioHandScaleBoost = 1.2;

/// 0..1 ilerleme (eşik = 1)
double juzzioRefreshProgress(double travel) => (travel / kJuzzioRefreshMaxTravel).clamp(0.0, 1.0);

/// Eşik (100%) aşıldı mı
bool juzzioRefreshArmed(double travel) => travel >= kJuzzioRefreshMaxTravel - 0.5;

/// Yumruk miktarı: 0 açık el … 1 yumruk; son %30'luk dilimde kapanır (03 PINCH)
double juzzioRefreshCurl(double travel) {
  final t = ((juzzioRefreshProgress(travel) - 0.70) / 0.30).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Sönümlü yay (ζ = 0.85): 0 → 1, t ∈ [0,1] (200 ms'ye ölçeklenir). Saf; test edilir.
double juzzioSnapBack(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const z = kJuzzioSnapDamping;
  const w = 8.0;
  final wd = w * math.sqrt(1 - z * z);
  final e = math.exp(-z * w * t);
  return 1 - e * (math.cos(wd * t) + z / math.sqrt(1 - z * z) * math.sin(wd * t));
}

/// Ekran / çentik ölçüleri (mantıksal px)
class JuzzioRefreshGeometry {
  JuzzioRefreshGeometry({required this.screenWidth, required this.topInset, double? contentTop})
      : contentTop = contentTop ?? 0;

  final double screenWidth;
  final double topInset;

  /// Yenilenebilir alanın ekrandaki üst kenarı
  final double contentTop;

  double get islandWidth => (screenWidth * 0.30).clamp(96.0, 126.0);
  double get islandHeight => (topInset * 0.68).clamp(26.0, 36.0);
  double get islandCenterY => math.max(topInset > 0 ? topInset * 0.5 : 16.0, islandHeight / 2 + 4);
  double get islandBottomY => islandCenterY + islandHeight / 2;

  /// Gömülü mod: alan ekranın tepesinde değil (başlığın altındaki liste) → el listenin üst
  /// kenarından çıkar, çentik çizilmez.
  bool get embedded => contentTop - islandBottomY > 24;

  /// Elin çıktığı çizgi (yerel koordinat)
  double get originY => embedded ? 0 : islandBottomY - contentTop;

  /// Elin ölçeği (çentik genişliğine oranlı; tasarım: 112 px'lik çentik)
  double get scale => (islandWidth / 112.0 * kJuzzioHandScaleBoost).clamp(1.0, 1.4);

  /// Yükleme halkasının merkezi (yerel koordinat): çentik ile başlık arasındaki boşluk
  double get spinnerCenterY => (embedded ? 0 : math.max(topInset - contentTop, 0.0)) + kJuzzioRefreshSpinnerGap / 2;
}

enum JuzzioRefreshPhase { idle, pulling, snapping, refreshing, settling }

class JuzzioClothRefresh extends StatefulWidget {
  const JuzzioClothRefresh({super.key, required this.onRefresh, required this.child, this.clothColor});

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Geriye uyumluluk (v1.1.1 kumaş rengi) — kompakt sürümde yalnız büzülme gölgesinin tonu
  final Color? clothColor;

  @override
  State<JuzzioClothRefresh> createState() => _JuzzioClothRefreshState();
}

class _JuzzioClothRefreshState extends State<JuzzioClothRefresh> with TickerProviderStateMixin {
  /// İçeriğin aşağı kayması (dp)
  final ValueNotifier<double> _content = ValueNotifier<double>(0);

  /// Elin yolu (dp, 0..80) ve yumruk (0..1)
  final ValueNotifier<double> _travel = ValueNotifier<double>(0);
  final ValueNotifier<double> _curl = ValueNotifier<double>(0);
  final ValueNotifier<bool> _spinning = ValueNotifier<bool>(false);

  late final AnimationController _snap = AnimationController(vsync: this, duration: kJuzzioSnapBackDuration);
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  JuzzioRefreshPhase _phase = JuzzioRefreshPhase.idle;
  JuzzioRefreshGeometry _geo = JuzzioRefreshGeometry(screenWidth: 360, topInset: 47);
  double _pull = 0;
  bool _armedDrag = false;
  bool _hapticDone = false;
  bool _latched = false; // v1.2.7: el bir kez yumruk yaptı → bırakınca yenile
  bool _inFlight = false; // tekil tetikleme kilidi
  double _snapFromTravel = 0;
  double _snapFromCurl = 0;
  double _settleFrom = 0;
  double _settleTo = 0;

  bool get _reduceMotion =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) || JuzzioAppController.instance.reduceMotion;

  @override
  void initState() {
    super.initState();
    _snap.addListener(_onSnapTick);
    _settle.addListener(() {
      final e = Curves.easeOutCubic.transform(_settle.value);
      _content.value = _settleFrom + (_settleTo - _settleFrom) * e;
    });
    // 60 FPS: el yolları ve gölgeler ilk karede hazır olsun (vektör → varlık yüklemesi yok)
    _JuzzioClayHandPainter.warmUp();
  }

  @override
  void dispose() {
    _snap.dispose();
    _settle.dispose();
    _content.dispose();
    _travel.dispose();
    _curl.dispose();
    _spinning.dispose();
    super.dispose();
  }

  void _measure() {
    final mq = MediaQuery.maybeOf(context);
    final box = context.findRenderObject();
    double top = 0;
    if (box is RenderBox && box.attached) top = box.localToGlobal(Offset.zero).dy;
    _geo = JuzzioRefreshGeometry(screenWidth: mq?.size.width ?? 360, topInset: mq?.padding.top ?? 0, contentTop: top);
  }

  // ---------------------------------------------------------------------------
  // Kaydırma bildirimleri (Android clamping + iOS bouncing)
  // ---------------------------------------------------------------------------
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_phase != JuzzioRefreshPhase.idle && _phase != JuzzioRefreshPhase.pulling) return false;
    if (n is ScrollStartNotification) {
      _armedDrag = n.dragDetails != null && n.metrics.extentBefore <= 0.5;
    } else if (n is OverscrollNotification) {
      // v1.2.7: tepede başlamayan ama tepeye varıp taşan çekiş de kurulur
      if (!_armedDrag && n.dragDetails != null && n.overscroll < 0 && n.metrics.extentBefore <= 0.5) _armedDrag = true;
      if (_armedDrag && n.dragDetails != null && n.overscroll < 0) _setPull(_pull - n.overscroll);
    } else if (n is ScrollUpdateNotification) {
      final d = n.dragDetails;
      if (d != null && n.metrics.pixels < 0) {
        _armedDrag = true;
        _setPull(-n.metrics.pixels * 1.4);
      } else if (d != null && _pull > 0 && (n.scrollDelta ?? 0) > 0) {
        _setPull(_pull - (n.scrollDelta ?? 0));
      }
    } else if (n is ScrollEndNotification) {
      _release();
    } else if (n is UserScrollNotification && n.direction == ScrollDirection.idle) {
      _release();
    }
    return false;
  }

  void _setPull(double v) {
    if (_inFlight) return;
    if (_phase == JuzzioRefreshPhase.idle) _measure();
    _pull = v.clamp(0.0, 600.0);
    final travel = juzzioRefreshTravel(_pull);
    _settle.stop();
    _snap.stop();
    _content.value = travel; // içerik elin indiği kadar kayar → el başlığa değmez
    if (_reduceMotion) {
      _travel.value = 0;
      _curl.value = 0;
    } else {
      _travel.value = travel;
      _curl.value = juzzioRefreshCurl(travel);
    }
    _phase = _pull > 0 ? JuzzioRefreshPhase.pulling : JuzzioRefreshPhase.idle;
    final armed = juzzioRefreshArmed(travel);
    if (armed) _latched = true;
    if (_latched && juzzioRefreshProgress(travel) < kJuzzioRefreshLatchKeep) _latched = false;
    if (armed && !_hapticDone) {
      _hapticDone = true;
      HapticFeedback.mediumImpact(); // 03 PINCH
    } else if (!armed) {
      _hapticDone = false;
    }
  }

  void _release() {
    _armedDrag = false;
    if (_phase != JuzzioRefreshPhase.pulling) return;
    final travel = juzzioRefreshTravel(_pull);
    final fire = juzzioRefreshShouldFire(travel, latched: _latched) && !_inFlight;
    _latched = false;
    _pull = 0;
    _hapticDone = false;
    // 04 RELEASE & SNAP: el hiç beklemeden çentiğe çekilir
    _snapFromTravel = _travel.value;
    _snapFromCurl = _curl.value;
    _phase = JuzzioRefreshPhase.snapping;
    if (_reduceMotion) {
      _travel.value = 0;
      _curl.value = 0;
    } else {
      _snap.forward(from: 0);
    }
    if (fire) {
      _startRefresh();
    } else {
      // Temiz iptal: tetikleme yok, içerik yerine oturur
      _animateContent(0, then: () => _phase = JuzzioRefreshPhase.idle);
    }
  }

  void _onSnapTick() {
    final k = juzzioSnapBack(_snap.value);
    _travel.value = (_snapFromTravel * (1 - k)).clamp(-6.0, kJuzzioRefreshMaxTravel);
    _curl.value = _snapFromCurl * (1 - _snap.value);
  }

  Future<void> _startRefresh() async {
    _inFlight = true;
    _phase = JuzzioRefreshPhase.refreshing;
    _animateContent(kJuzzioRefreshSpinnerGap);
    _spinning.value = true;
    try {
      await widget.onRefresh();
    } catch (_) {
      // hata ekranı çağıranın işidir; yenileme halkası yine kapanır
    } finally {
      if (mounted) {
        _spinning.value = false;
        _phase = JuzzioRefreshPhase.settling;
        _animateContent(0, then: () {
          _phase = JuzzioRefreshPhase.idle;
          _inFlight = false;
        });
      } else {
        _inFlight = false;
      }
    }
  }

  void _animateContent(double to, {VoidCallback? then}) {
    _settleFrom = _content.value;
    _settleTo = to;
    if (_reduceMotion) {
      _content.value = to;
      then?.call();
      return;
    }
    _settle.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted && _settle.value >= 1) then?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioAppController.instance.isDark;
    return ScrollConfiguration(
      behavior: const _JuzzioClothScrollBehavior(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 03 PINCH: içerik yumruğa doğru çok hafif içe çekilir (kumaş büzülmesi)
            ValueListenableBuilder<double>(
              valueListenable: _content,
              child: widget.child,
              builder: (context, dy, child) => ValueListenableBuilder<double>(
                valueListenable: _curl,
                child: child,
                builder: (context, curl, child) => Transform.translate(
                  offset: Offset(0, dy),
                  child: curl <= 0.001
                      ? child
                      : Transform.scale(
                          scale: 1 - 0.012 * curl,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                ),
              ),
            ),
            // 05 LOADING: çentik ile başlık arasındaki boşlukta sade halka
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _spinning,
                  builder: (context, on, _) => AnimatedOpacity(
                    opacity: on ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: on
                        ? Padding(
                            padding: EdgeInsets.only(top: math.max(0.0, _geo.spinnerCenterY - 11)),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: JuzzioOrbitLoader(strokeWidth: 2.2, color: dark ? Colors.white : const Color(0xFF2A2A33)),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            // 01–04: kil el (yalnız çentik/üst kenar ile başlık arasındaki boşlukta)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _JuzzioClayHandPainter(
                      travel: _travel,
                      curl: _curl,
                      geo: () => _geo,
                      shadowTint: widget.clothColor,
                      dark: dark,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JuzzioClothScrollBehavior extends MaterialScrollBehavior {
  const _JuzzioClothScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ---------------------------------------------------------------------------
// Kil (claymorphism) bebek eli — vektör
// ---------------------------------------------------------------------------

/// Kil el renkleri (açık pembe-şeftali; tırnak dairesi YOK)
class JuzzioHandColors {
  JuzzioHandColors._();
  static const Color skin = Color(0xFFF8C3BC);
  static const Color light = Color(0xFFFFE1DB);
  static const Color shade = Color(0xFFE29A93);
  static const Color deep = Color(0xFFC97B76);
}

/// Elin parçaları (tasarım birimi; (0,0) = bilek üst ortası, +y aşağı). [curl] 0 açık … 1 yumruk.
/// Referans görseldeki gibi: geniş tombul avuç, hafif açılmış dört uzun parmak, yanda başparmak.
/// Saf; testlerde doğrulanır.
class JuzzioHandShape {
  JuzzioHandShape(double curl) : c = curl.clamp(0.0, 1.0);
  final double c;

  static const double wristHalf = 22;
  static const double palmTop = 28;
  double get palmBottom => 58 + 2 * c;
  double get palmHalf => 31 + 1 * c;

  /// Dört parmak: (kök x, uzunluk, açılma açısı°) — yumrukta kısalır ve kapanır
  List<({double x, double len, double deg})> get fingers {
    double l(double open) => open - (open - 13) * c;
    double d(double open) => open * (1 - c);
    return [
      (x: -21.0, len: l(37), deg: d(8)),
      (x: -7.0, len: l(45), deg: d(2.5)),
      (x: 7.0, len: l(43), deg: d(-2.5)),
      (x: 21.0, len: l(33), deg: d(-8)),
    ];
  }

  double get fingerWidth => 15.5 + 0.5 * c;
  double get fingerBaseY => palmBottom - 8;

  /// Parmak uçları (ekran yönünde; açı +° → sola açılır)
  List<Offset> get tips => [
        for (final f in fingers)
          Offset(f.x - math.sin(f.deg * math.pi / 180) * f.len, fingerBaseY + math.cos(f.deg * math.pi / 180) * f.len),
      ];

  /// Başparmak ucu: açıkta sola-aşağı açık, yumrukta avucun önüne kıvrılır
  Offset get thumbTip => Offset.lerp(const Offset(-52, 66), const Offset(-4, 56), c)!;

  double get lowestY => tips.map((t) => t.dy).reduce(math.max);
}

class _JuzzioClayHandPainter extends CustomPainter {
  _JuzzioClayHandPainter({required this.travel, required this.curl, required this.geo, required this.dark, this.shadowTint})
      : super(repaint: Listenable.merge([travel, curl]));

  final ValueNotifier<double> travel;
  final ValueNotifier<double> curl;
  final JuzzioRefreshGeometry Function() geo;
  final bool dark;
  final Color? shadowTint;

  static final Paint _castShadow = Paint()
    ..color = const Color(0x55000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
  static final Paint _island = Paint()..color = kJuzzioIslandColor;
  static bool _warm = false;

  /// İlk karede gölge/maskeler hazır (shader derleme takılmasını önler)
  static void warmUp() {
    if (_warm) return;
    _warm = true;
    final r = ui.PictureRecorder();
    final c = Canvas(r);
    _paintHand(c, JuzzioHandShape(0));
    _paintHand(c, JuzzioHandShape(1));
    r.endRecording().dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = travel.value;
    if (t <= 0.5) return;
    final g = geo();
    final shape = JuzzioHandShape(curl.value);
    final s = g.scale;
    final origin = g.originY;
    final cx = size.width / 2;
    // el ucu = başlangıç çizgisi + yol (en fazla 80 dp); üst kısmı çizginin üstünde gizli
    final tipY = origin + t;
    final topY = tipY - shape.lowestY * s;

    // 03 PINCH: yumruğun altında yüzey büzülmesi (yumuşak 3B gölge, çizgi yok)
    final c = curl.value;
    if (c > 0.02) {
      final pinchCenter = Offset(cx, tipY + 6);
      final base = shadowTint ?? Colors.black;
      final pinch = Paint()
        ..shader = RadialGradient(
          colors: [base.withValues(alpha: (dark ? 0.42 : 0.22) * c), base.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: pinchCenter, radius: 90 * s));
      canvas.drawOval(Rect.fromCenter(center: pinchCenter, width: 210 * s, height: 70 * s), pinch);
      // kumaşın kabaran kenarı: yumuşak açık vurgu
      final hl = Paint()
        ..color = Colors.white.withValues(alpha: (dark ? 0.07 : 0.16) * c)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawOval(Rect.fromCenter(center: pinchCenter.translate(0, 18 * s), width: 170 * s, height: 22 * s), hl);
    }

    canvas.save();
    // yalnız çentiğin / üst kenarın altında görünür
    canvas.clipRect(Rect.fromLTRB(0, origin - 0.5, size.width, size.height));
    canvas.translate(cx, topY);
    canvas.scale(s);
    // 3B yumuşak düşen gölge
    canvas.save();
    canvas.translate(4, 7);
    canvas.drawPath(_silhouette(shape), _castShadow);
    canvas.restore();
    _paintHand(canvas, shape);
    canvas.restore();

    // çentiksiz ekranlarda el çentikten çıkıyormuş gibi görünsün
    if (!g.embedded) {
      final w = g.islandWidth, h = g.islandHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, g.islandCenterY - g.contentTop), width: w, height: h), Radius.circular(h / 2)),
        _island,
      );
    }
  }

  static Path _silhouette(JuzzioHandShape h) {
    final p = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-JuzzioHandShape.wristHalf, -6, JuzzioHandShape.wristHalf, JuzzioHandShape.palmTop + 6), const Radius.circular(12)))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(-h.palmHalf, JuzzioHandShape.palmTop - 6, h.palmHalf, h.palmBottom + 4), Radius.circular(h.palmHalf * 0.8)));
    for (final f in h.fingers) {
      p.addPath(_finger(h, f), Offset.zero);
    }
    p.addPath(_thumb(h), Offset.zero);
    return p;
  }

  static Path _finger(JuzzioHandShape h, ({double x, double len, double deg}) f) {
    final m = Matrix4.identity()
      ..translate(f.x, h.fingerBaseY)
      ..rotateZ(f.deg * math.pi / 180);
    final r = Rect.fromLTWH(-h.fingerWidth / 2, -8, h.fingerWidth, f.len + 8);
    return (Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(h.fingerWidth / 2)))).transform(m.storage);
  }

  static Path _thumb(JuzzioHandShape h) {
    final root = Offset(-h.palmHalf + 8, JuzzioHandShape.palmTop + 10);
    final tip = h.thumbTip;
    final dir = tip - root;
    final len = dir.distance;
    final ang = math.atan2(dir.dy, dir.dx);
    final m = Matrix4.identity()
      ..translate(root.dx, root.dy)
      ..rotateZ(ang);
    return (Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-4, -8, len + 4, 16), const Radius.circular(8)))).transform(m.storage);
  }

  /// Kil dokusu: her parça kendi yumuşak radyal gölgesiyle (ışık sol üstten)
  static void _paintHand(Canvas canvas, JuzzioHandShape h) {
    Paint clay(Rect r, {double lightX = -0.45, double lightY = -0.55}) => Paint()
      ..shader = RadialGradient(
        center: Alignment(lightX, lightY),
        radius: 1.05,
        colors: const [JuzzioHandColors.light, JuzzioHandColors.skin, JuzzioHandColors.shade],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(r);

    // bilek / kol (çentikten gelir)
    final wrist = Rect.fromLTRB(-JuzzioHandShape.wristHalf, -40, JuzzioHandShape.wristHalf, JuzzioHandShape.palmTop + 6);
    canvas.drawRRect(RRect.fromRectAndRadius(wrist, const Radius.circular(14)),
        Paint()
          ..shader = const LinearGradient(colors: [JuzzioHandColors.shade, JuzzioHandColors.light, JuzzioHandColors.skin, JuzzioHandColors.shade], stops: [0, 0.35, 0.7, 1])
              .createShader(wrist));

    // başparmak arkada (açık elde avucun yanında)
    final thumb = _thumb(h);
    if (h.c < 0.5) canvas.drawPath(thumb, clay(thumb.getBounds()));

    // parmaklar (avucun arkasından çıkar)
    for (final f in h.fingers) {
      final path = _finger(h, f);
      canvas.drawPath(path, clay(path.getBounds(), lightX: -0.3, lightY: -0.2));
      // eklem kıvrımı (yumrukta boğum gölgesi) — tırnak dairesi YOK
      final crease = Paint()
        ..color = JuzzioHandColors.deep.withValues(alpha: 0.16 + 0.22 * h.c)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.save();
      canvas.translate(f.x, h.fingerBaseY);
      canvas.rotate(f.deg * math.pi / 180);
      canvas.drawArc(Rect.fromCenter(center: Offset(0, f.len * 0.55), width: h.fingerWidth * 0.55, height: 4), 0.2, math.pi - 0.4, false, crease);
      canvas.restore();
    }

    // avuç (tombul, yumuşak)
    final palm = Rect.fromLTRB(-h.palmHalf, JuzzioHandShape.palmTop - 6, h.palmHalf, h.palmBottom + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(palm, Radius.circular(h.palmHalf * 0.8)), clay(palm));
    // avuç parlaklığı (kil hissi)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-h.palmHalf * 0.35, JuzzioHandShape.palmTop + 6), width: h.palmHalf * 0.8, height: 12),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // yumrukta başparmak avucun önüne kıvrılır
    if (h.c >= 0.5) canvas.drawPath(thumb, clay(thumb.getBounds(), lightX: -0.2, lightY: -0.7));
  }

  @override
  bool shouldRepaint(covariant _JuzzioClayHandPainter old) => old.dark != dark || old.shadowTint != shadowTint;
}
