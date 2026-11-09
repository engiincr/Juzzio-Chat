// =============================================================================
// JUZZIO v0.9.9 — 3D kil el ile kumaş "aşağı çek-yenile" (referans videoya birebir revizyon)
//
//  Görsel yapı
//   • 3D kil el/kol: tools/cloth_render/hand.py (SDF raymarch) ile önceden render edilmiş
//     sprite'lar — tombul kısa kol (bilek ≈ çentik genişliğinin %55'i), sıcak mat şeftali
//     (#F2C2B3 gövde, #DF9F8E boğum gölgesi), başparmak dahil her parmakta parlak 3D tırnak
//     (#F9DCD3), boğum çizgileri.
//       hand_s0..s8 : sarkaç pozları (−15°…+25°, 5° adım). Kök çentik merkezinde SABİT; kol
//                     esnek bir kemik gibi bükülür, sağ zirvede parmaklar yelpaze gibi açılır.
//       hand_c0..c7 : açık el → yumruk (4 kıvrık parmak yan yana, aralarında dikey oyuklar,
//                     başparmak altta sıkılı).
//   • Dynamic Island: her iki temada tam siyah (#000000) kapsül, EN ÜST katmanda çizilir. El
//     yalnız çentiğin alt kenarının (islandBottomY) altında görünür (maske); çentikten çıkar,
//     çentiğe girerek kaybolur.
//   • Kumaş: tools/cloth_render/folds.py — kavisli, asimetrik, keskin sırtlı pli katları:
//       fold_tension_* : yumruğun SOL/SAĞ yanında çentiğe doğru kıvrılan kelebek kanadı
//                        kıstırma döngüleri (alt taraf pürüzsüz)
//       fold_drape_*   : 6 ana perde katı (sol-alt / orta / sağ-alt), üst barı örter,
//                        "Popular Food" hizasına iner. *_cov = yarı saydam çarşaf örtüsü.
//     Renkler: aydınlık → vadiler #DFE2E8–#C8CDD6, sırtlar #FFFFFF (asla siyah/koyu gri yok);
//              koyu → vadiler #07080B, sırtlar #222630 (asla beyaz parlama yok).
//
//  Fazlar
//   1) Çekme    : overscroll 0–35 px'te çentiğin altından yalnız 4 tombul parmak ucu ve
//                 tırnaklar görünür; çekme sürdükçe el ve bilek iner. İçerik 140–155 px kayar.
//   2) Sarkaç   : kök sabit, poz kareleri arasında geçiş (−15° → +25° → −8° → 0°); içerik
//                 tam çekilmiş konumda KİLİTLİ (el temiz boşlukta sallanır).
//   3) Yumruk   : sarkaç merkezden geçerken el ~0,3 sn'de yumruk olur, kumaşı kavrar; yanlarda
//                 kelebek kanadı kıstırma katları belirir. İçerik hâlâ kilitli.
//   4) Yukarı   : ~0,5 sn — yumruk çentiğe çekilir; içerik yumruğun alt sınırına bağlı gibi
//                 elle AYNI hızda yukarı çıkar (yay yok, aşma yok). Perde katları açılır.
//   5) Ütüleme  : son 250 ms'de katlar çentiğe doğru yukarı gerilip düzleşir; içerik 0'da
//                 sabit — titreme olmaz.
//
//  Performans: içerik yalnız Transform ile kayar; el/kumaş kök Overlay'de, RepaintBoundary
//  içinde tek CustomPainter (60/120 fps). "Hareketi azalt" açıksa el/kumaş çizilmez.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';

// ---------------------------------------------------------------------------
// Saf yardımcılar (birim testlerde doğrulanır)
// ---------------------------------------------------------------------------

/// Faz 1: çekilen piksel → içeriğin aşağı kayması (azalan getiri, en fazla 156 px).
double juzzioClothExtent(double pull, {double maxExtent = 156}) {
  if (pull <= 0) return 0;
  return maxExtent * (1 - math.exp(-pull / 167));
}

/// Faz 2: sarkaç açısı (derece). 0→0,3 sn −15°, 0,75 sn +25°, 1,1 sn −8°, 1,4 sn 0°;
/// yenileme sürüyorsa ardından ±9°'lik sönümlü salınım devam eder.
double juzzioPendulumDegrees(double t) {
  if (t <= 0) return 0;
  const keys = <(double, double)>[(0.0, 0), (0.30, -15), (0.75, 25), (1.10, -8), (1.40, 0)];
  if (t < 1.40) {
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i], b = keys[i + 1];
      if (t >= a.$1 && t <= b.$1) {
        final u = (t - a.$1) / (b.$1 - a.$1);
        final e = u * u * (3 - 2 * u); // sarkaçta tepe noktalarında yavaşlama
        return a.$2 + (b.$2 - a.$2) * e;
      }
    }
  }
  final s = t - 1.40;
  return 9 * math.sin(s * 2 * math.pi / 1.25) * math.exp(-s * 0.15).clamp(0.55, 1.0);
}

/// Faz 3-5 zaman çizelgesi (saniye, yenileme bittikten sonra).
const double kJuzzioClenchDur = 0.30;
const double kJuzzioYankDur = 0.50;
const double kJuzzioSmoothDur = 0.25;

/// Kıvrım katmanlarının görsel gücü.
const double kJuzzioTensionStrength = 1.6;
const double kJuzzioDrapeStrength = 1.5;

/// Sarkaç poz karelerinin açıları (hand_s0..s8).
const List<double> kJuzzioSwingAngles = [-15, -10, -5, 0, 5, 10, 15, 20, 25];

/// Kumaş renkleri (spesifikasyon): aydınlıkta siyah/koyu gri YOK, koyuda beyaz parlama YOK.
const Color kJuzzioFoldLightRidge = Color(0xFFFFFFFF);
const Color kJuzzioFoldLightValley = Color(0xFFC8CDD6); // yarı saydam → #DFE2E8…#C8CDD6
const Color kJuzzioFoldDarkRidge = Color(0xFF222630);
const Color kJuzzioFoldDarkValley = Color(0xFF07080B);
const Color kJuzzioIslandColor = Color(0xFF000000);

/// El gölgesi tonları (aydınlıkta soğuk gümüş gri; koyu/siyah leke yok)
class JuzzioClothShadowTone {
  JuzzioClothShadowTone._();
  static const Color light = Color(0xFF8C93A3);
}

/// İki komşu poz karesi ve geçiş oranı: (i0, i1, f).
(int, int, double) juzzioSwingFrame(double angleDeg) {
  final x = ((angleDeg - kJuzzioSwingAngles.first) / 5).clamp(0.0, (kJuzzioSwingAngles.length - 1).toDouble());
  final i0 = math.min(math.max(x.floor(), 0), kJuzzioSwingAngles.length - 1);
  final i1 = math.min(i0 + 1, kJuzzioSwingAngles.length - 1);
  return (i0, i1, x - i0);
}

/// Faz 1 "parmak ucu görünmesi": içerik kaymasına göre çentiğin altında görünen el uzunluğu.
/// Üs > 1 olduğundan ilk ~35 px'lik çekişte yalnız parmak uçları ve tırnaklar çıkar.
double juzzioPeekReveal(double content, double rest, double maxVisible) {
  if (content <= 0 || rest <= 0) return 0;
  final u = (content / rest).clamp(0.0, 1.0);
  return maxVisible * math.pow(u, 1.3).toDouble();
}

/// Faz 4: içerik yumruğun alt sınırına bağlıdır — yumruk çentiğe yaklaştıkça aynı oranda kalkar.
double juzzioYankContent({required double fistLowY, required double fistLowFromY, required double islandBottomY, required double rest}) {
  final span = fistLowFromY - islandBottomY;
  if (span <= 0) return 0;
  return rest * ((fistLowY - islandBottomY) / span).clamp(0.0, 1.0);
}

enum JuzzioClothPhase { idle, pulling, swinging, clenching, yanking, smoothing, retracting }

/// Ekran ölçülerinden türetilen sabit geometri (mantıksal px).
class JuzzioClothGeometry {
  JuzzioClothGeometry({required this.screenWidth, required this.topInset, double? contentTop})
      : contentTop = contentTop ?? topInset;

  final double screenWidth;
  final double topInset;
  final double contentTop;

  /// Referans: çentik genişliği ≈ ekranın %32'si.
  double get islandWidth => (screenWidth * 0.32).clamp(100.0, 130.0);
  double get islandHeight => (topInset * 0.68).clamp(26.0, 37.0);
  double get islandCenterY => math.max(topInset > 0 ? topInset * 0.5 : 16.0, islandHeight / 2 + 4);
  double get islandBottomY => islandCenterY + islandHeight / 2;

  /// Sprite'lar 115 px'lik çentiğe göre render edildi (bilek ≈ %55).
  double get scale => islandWidth / 115.0;
  Size get spriteSize => Size(300 * scale, 200 * scale);
  Offset get rootInSprite => Offset(150 * scale, 12 * scale);
  double get openTip => 150.3 * scale;
  double get fistCenterY => 120 * scale;
  double get fistLow => 145.7 * scale;

  /// Kök çentik merkezindeyken çentiğin altında görünen en uzun kol.
  double get maxVisible => islandCenterY + openTip - islandBottomY;

  /// İçeriğin beklediği kayma: elin ucu ile içerik arasında temiz boşluk, 140–155 px.
  double get restContent => (islandCenterY + openTip + 24 - contentTop).clamp(140.0, 155.0);
  double get threshold => restContent * 0.80;

  /// [reveal] (çentik altında görünen uzunluk) → kökün ekran y'si.
  double rootY(double reveal) => islandBottomY + reveal - openTip;

  double get foldScale => screenWidth / 360.0;
}

// ---------------------------------------------------------------------------
// Varlıklar (bir kez yüklenir, tüm sayfalarda paylaşılır)
// ---------------------------------------------------------------------------
class JuzzioClothAssets {
  JuzzioClothAssets._();
  static final JuzzioClothAssets instance = JuzzioClothAssets._();

  /// Sprite render: 900×600 px = mantıksal 300×200 (×3); kök (150, 12).
  static const Size spriteLogical = Size(300, 200);
  static const Offset rootLogical = Offset(150, 12);
  static const Size tensionSize = Size(360, 230);
  static const Offset tensionAnchor = Offset(180, 150); // yumruk merkezi
  static const Size drapeSize = Size(360, 340);
  static const Offset drapeAnchor = Offset(180, 22); // kavrama noktası

  static final List<String> assetNames = List.unmodifiable(<String>[
    for (var i = 0; i < 9; i++) 'hand_s$i',
    for (var i = 0; i < 8; i++) 'hand_c$i',
    'fold_tension_hi',
    'fold_tension_sh',
    'fold_tension_cov',
    'fold_drape_hi',
    'fold_drape_sh',
    'fold_drape_cov',
  ]);

  final List<ui.Image> swing = [];
  final List<ui.Image> curl = [];
  ui.Image? tensionHi, tensionSh, tensionCov, drapeHi, drapeSh, drapeCov;
  Future<void>? _loading;
  bool get ready => swing.length == 9 && curl.length == 8 && drapeCov != null && tensionCov != null;

  Future<void> ensure() => _loading ??= _load();

  Future<ui.Image> _img(String name) async {
    final data = await rootBundle.load('assets/cloth/$name.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  Future<void> _load() async {
    try {
      final s = await Future.wait([for (var i = 0; i < 9; i++) _img('hand_s$i')]);
      final c = await Future.wait([for (var i = 0; i < 8; i++) _img('hand_c$i')]);
      swing
        ..clear()
        ..addAll(s);
      curl
        ..clear()
        ..addAll(c);
      tensionHi = await _img('fold_tension_hi');
      tensionSh = await _img('fold_tension_sh');
      tensionCov = await _img('fold_tension_cov');
      drapeHi = await _img('fold_drape_hi');
      drapeSh = await _img('fold_drape_sh');
      drapeCov = await _img('fold_drape_cov');
    } catch (_) {
      _loading = null; // bir sonraki çekişte yeniden denenir; bu sırada yalnız içerik kayar
    }
  }
}

/// Bir karede çizilecek sahne (painter'a giden değişmez durum).
class JuzzioClothScene {
  const JuzzioClothScene({
    required this.reveal,
    required this.angleDeg,
    required this.curl,
    required this.lift,
    required this.tension,
    required this.drape,
    required this.drapeStretch,
    required this.grabY,
    required this.island,
    required this.dark,
  });

  /// Elin çentik alt kenarının altında görünen uzunluğu (px).
  final double reveal;
  final double angleDeg;

  /// 0 açık el … 1 sıkı yumruk.
  final double curl;

  /// Elin zeminden yükselmesi (gölge büyür/söner) 0..1.
  final double lift;
  final double tension;
  final double drape;
  final double drapeStretch;

  /// Perde kavrama noktasının ekran y'si.
  final double grabY;

  /// Siyah çentik kapsülü çizilsin mi (>0) — çizildiğinde her zaman tam opak siyahtır.
  final double island;
  final bool dark;

  static const JuzzioClothScene hidden = JuzzioClothScene(
      reveal: 0, angleDeg: 0, curl: 0, lift: 0, tension: 0, drape: 0, drapeStretch: 0, grabY: 0, island: 0, dark: false);
}

class JuzzioClothRefresh extends StatefulWidget {
  const JuzzioClothRefresh({super.key, required this.onRefresh, required this.child, this.clothColor});

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Çarşaf örtüsünün rengi (verilmezse temanın zemin rengi).
  final Color? clothColor;

  @override
  State<JuzzioClothRefresh> createState() => _JuzzioClothRefreshState();
}

class _JuzzioClothRefreshState extends State<JuzzioClothRefresh> with TickerProviderStateMixin {
  final ValueNotifier<double> _content = ValueNotifier<double>(0);
  final ValueNotifier<JuzzioClothScene> _scene = ValueNotifier<JuzzioClothScene>(JuzzioClothScene.hidden);

  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _contentSpring = AnimationController.unbounded(vsync: this)
    ..addListener(() => _content.value = _contentSpring.value.clamp(-6.0, 160.0));

  JuzzioClothPhase _phase = JuzzioClothPhase.idle;
  JuzzioClothGeometry _geo = JuzzioClothGeometry(screenWidth: 360, topInset: 47);
  double _pull = 0;
  bool _armed = false;
  bool _passedThreshold = false;
  bool _refreshDone = false;
  Duration _phaseStart = Duration.zero;
  Duration _now = Duration.zero;
  double _prevAngle = 0;
  double _yankFromReveal = 0;
  double _yankFromFistLow = 0;
  double _retractFrom = 0;
  double _retractIsland = 1;
  OverlayEntry? _overlay;

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(JuzzioClothAssets.instance.ensure());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _contentSpring.dispose();
    _removeOverlay();
    _content.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _measure() {
    final mq = MediaQuery.maybeOf(context);
    final box = context.findRenderObject();
    double? top;
    if (box is RenderBox && box.attached) top = box.localToGlobal(Offset.zero).dy;
    _geo = JuzzioClothGeometry(
      screenWidth: mq?.size.width ?? 360,
      topInset: mq?.viewPadding.top ?? 0,
      contentTop: top,
    );
  }

  // ---------------------------------------------------------------------------
  // Kaydırma bildirimleri (Android clamping + iOS bouncing)
  // ---------------------------------------------------------------------------
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_phase != JuzzioClothPhase.idle && _phase != JuzzioClothPhase.pulling) return false;
    if (n is ScrollStartNotification) {
      _armed = n.dragDetails != null && n.metrics.extentBefore <= 0.5;
    } else if (n is OverscrollNotification) {
      if (_armed && n.dragDetails != null && n.overscroll < 0) _setPull(_pull - n.overscroll);
    } else if (n is ScrollUpdateNotification) {
      final d = n.dragDetails;
      if (d != null && n.metrics.pixels < 0) {
        _armed = true;
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
    if (_phase == JuzzioClothPhase.idle) _measure();
    _pull = v.clamp(0.0, 1200.0);
    final c = juzzioClothExtent(_pull);
    _contentSpring.stop();
    _content.value = c;
    if (_pull > 0 && _phase == JuzzioClothPhase.idle) {
      _phase = JuzzioClothPhase.pulling;
      _insertOverlay();
    }
    if (_pull <= 0 && _phase == JuzzioClothPhase.pulling) {
      _phase = JuzzioClothPhase.idle;
      _removeOverlay();
    }
    final over = c >= _geo.threshold;
    if (over != _passedThreshold) {
      _passedThreshold = over;
      if (over) HapticFeedback.lightImpact();
    }
    _scene.value = _openScene(c, island: c > 0 ? 1.0 : 0.0);
  }

  /// Açık el, kök sabit; görünen uzunluk içerik kaymasından (parmak ucu görünmesi).
  JuzzioClothScene _openScene(double content, {double angle = 0, double island = 1}) => JuzzioClothScene(
        reveal: juzzioPeekReveal(content, _geo.restContent, _geo.maxVisible),
        angleDeg: angle,
        curl: 0,
        lift: 0,
        tension: 0,
        drape: 0,
        drapeStretch: 0,
        grabY: 0,
        island: island,
        dark: JuzzioAppController.instance.isDark,
      );

  void _release() {
    _armed = false;
    if (_phase != JuzzioClothPhase.pulling) return;
    final c = _content.value;
    _pull = 0;
    _passedThreshold = false;
    if (c < _geo.threshold) {
      // Eşiğe ulaşmadı: el çentiğe geri girer, içerik yaylanarak oturur
      _retractFrom = _scene.value.reveal;
      _retractIsland = _scene.value.island;
      _startPhase(JuzzioClothPhase.retracting);
      _springContent(c, 0);
      return;
    }
    _refreshDone = false;
    _prevAngle = 0;
    _startPhase(JuzzioClothPhase.swinging);
    // tam çekilmiş konuma (140–155 px) oturur ve sarkaç/yumruk boyunca orada kilitli kalır
    _springContent(c, _geo.restContent, stiffness: 300, damping: 36); // kritik sönüm: aşma yok
    unawaited(() async {
      try {
        await widget.onRefresh();
      } catch (_) {
      } finally {
        _refreshDone = true;
      }
    }());
  }

  void _springContent(double from, double to, {double stiffness = 260, double damping = 22, double velocity = 0}) {
    _contentSpring.value = from;
    _contentSpring.animateWith(SpringSimulation(SpringDescription(mass: 1, stiffness: stiffness, damping: damping), from, to, velocity));
  }

  void _lockContent(double v) {
    _contentSpring.stop();
    _content.value = v;
  }

  void _startPhase(JuzzioClothPhase p) {
    _phase = p;
    _phaseStart = _now;
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _phaseStart = Duration.zero;
      _ticker.start();
    }
  }

  // ---------------------------------------------------------------------------
  // Kare kare faz motoru
  // ---------------------------------------------------------------------------
  void _onTick(Duration elapsed) {
    _now = elapsed;
    final t = (elapsed - _phaseStart).inMicroseconds / 1e6;
    final dark = JuzzioAppController.instance.isDark;
    final g = _geo;
    switch (_phase) {
      case JuzzioClothPhase.retracting: {
        final u = (t / 0.32).clamp(0.0, 1.0);
        final e = Curves.easeInCubic.transform(u);
        _scene.value = JuzzioClothScene(
          reveal: _retractFrom * (1 - e) - 4 * e,
          angleDeg: 0,
          curl: 0,
          lift: 0,
          tension: 0,
          drape: 0,
          drapeStretch: 0,
          grabY: 0,
          island: u < 1 ? _retractIsland : 0.0,
          dark: dark,
        );
        if (u >= 1) _finish();
      }
      case JuzzioClothPhase.swinging: {
        final ang = juzzioPendulumDegrees(t);
        _scene.value = _openScene(_content.value, angle: ang);
        // En az bir tam sarkaç turu; yenileme bitince el MERKEZDEN geçerken yumruk yapar
        final crossed = ang.abs() < 1.5 || (_prevAngle != 0 && ang.sign != _prevAngle.sign);
        _prevAngle = ang;
        if (_refreshDone && t >= 1.40 && crossed) {
          _lockContent(g.restContent);
          _startPhase(JuzzioClothPhase.clenching);
        }
      }
      case JuzzioClothPhase.clenching: {
        final u = (t / kJuzzioClenchDur).clamp(0.0, 1.0);
        _lockContent(g.restContent); // kavrayana kadar sayfa kilitli
        _scene.value = JuzzioClothScene(
          reveal: g.maxVisible + 8 * Curves.easeOut.transform(u), // kumaşa bastırır
          angleDeg: 0,
          curl: Curves.easeInCubic.transform(u),
          lift: 0,
          tension: Curves.easeOut.transform(u),
          drape: 0,
          drapeStretch: 0,
          grabY: 0,
          island: 1,
          dark: dark,
        );
        if (u >= 1) {
          _yankFromReveal = g.maxVisible + 8;
          _yankFromFistLow = g.rootY(_yankFromReveal) + g.fistLow;
          _startPhase(JuzzioClothPhase.yanking);
          HapticFeedback.mediumImpact();
        }
      }
      case JuzzioClothPhase.yanking: {
        final u = (t / kJuzzioYankDur).clamp(0.0, 1.0);
        final e = Curves.easeInOutCubic.transform(u);
        // yumruk tamamen çentiğe girene kadar (alt sınırı çentik altına ulaşır)
        final hidden = g.openTip - g.fistLow - 2;
        final reveal = _yankFromReveal + (hidden - _yankFromReveal) * e;
        final root = g.rootY(reveal);
        // içerik yumruğun alt sınırına bağlı: aynı hızda kalkar, yumruk kaybolurken 0'a varır
        _lockContent(juzzioYankContent(
          fistLowY: root + g.fistLow,
          fistLowFromY: _yankFromFistLow,
          islandBottomY: g.islandBottomY,
          rest: g.restContent,
        ));
        _scene.value = JuzzioClothScene(
          reveal: reveal,
          angleDeg: 0,
          curl: 1,
          lift: e,
          tension: 1 - (u / 0.35).clamp(0.0, 1.0),
          drape: Curves.easeOut.transform((u / 0.30).clamp(0.0, 1.0)),
          drapeStretch: 0.25 * e,
          grabY: math.max(root + g.fistCenterY, g.islandBottomY),
          island: 1,
          dark: dark,
        );
        if (u >= 1) {
          _lockContent(0);
          _startPhase(JuzzioClothPhase.smoothing);
        }
      }
      case JuzzioClothPhase.smoothing: {
        final u = (t / kJuzzioSmoothDur).clamp(0.0, 1.0);
        final e = Curves.easeOutCubic.transform(u);
        _lockContent(0); // titreme yok: içerik yerinde
        _scene.value = JuzzioClothScene(
          reveal: 0,
          angleDeg: 0,
          curl: 1,
          lift: 1,
          tension: 0,
          drape: 1 - e,
          drapeStretch: 0.25 - 0.75 * e, // kumaş çentiğe doğru yukarı gerilerek ütülenir
          grabY: g.islandBottomY,
          island: u < 1 ? 1.0 : 0.0,
          dark: dark,
        );
        if (u >= 1) _finish();
      }
      case JuzzioClothPhase.idle:
      case JuzzioClothPhase.pulling:
        break;
    }
  }

  void _finish() {
    _ticker.stop();
    _phase = JuzzioClothPhase.idle;
    _scene.value = JuzzioClothScene.hidden;
    _removeOverlay();
  }

  // ---------------------------------------------------------------------------
  // Overlay: el, kumaş ve çentik ekranın en üstünde çizilir
  // ---------------------------------------------------------------------------
  Color _clothColor(BuildContext ctx) {
    if (widget.clothColor != null) return widget.clothColor!.withValues(alpha: 1);
    final dark = JuzzioAppController.instance.isDark;
    final bg = Theme.of(ctx).scaffoldBackgroundColor;
    if (bg.a > 0.9) return bg;
    return dark ? const Color(0xFF0E1016) : const Color(0xFFF6F7FA);
  }

  void _insertOverlay() {
    if (_overlay != null || _reduceMotion) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final cloth = _clothColor(context);
    _overlay = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ClothScenePainter(scene: _scene, geo: _geo, cloth: cloth),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    // v1.0.0 mobil düzeltme: alt kaydırılabilirler her platformda aynı davranır —
    //  • her zaman kaydırılabilir (içerik kısa olsa da çekilebilir),
    //  • sıkıştırmalı (clamping) fizik: iOS esneme + bizim kaydırmamız iki kat hareket yapmaz,
    //  • Android 12+ "stretch" taşma efekti kapalı: içerik hem esneyip hem kaymıyordu (görüntü bozulması).
    return ScrollConfiguration(
      behavior: const _JuzzioClothScrollBehavior(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ValueListenableBuilder<double>(
          valueListenable: _content,
          child: widget.child,
          builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
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
// Sahne çizimi
// ---------------------------------------------------------------------------
class _ClothScenePainter extends CustomPainter {
  _ClothScenePainter({required this.scene, required this.geo, required this.cloth}) : super(repaint: scene);

  final ValueNotifier<JuzzioClothScene> scene;
  final JuzzioClothGeometry geo;
  final Color cloth;

  @override
  void paint(Canvas canvas, Size size) {
    final a = JuzzioClothAssets.instance;
    final s = scene.value;
    final g = geo;
    final cx = size.width / 2;

    if (a.ready) {
      final ridge = s.dark ? kJuzzioFoldDarkRidge : kJuzzioFoldLightRidge;
      final valley = s.dark ? kJuzzioFoldDarkValley : kJuzzioFoldLightValley;
      final root = Offset(cx, g.rootY(s.reveal));

      // El ve kumaş yalnız çentiğin alt kenarının altında görünür (maske)
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, g.islandBottomY - 0.5, size.width, size.height));

      // ---- Kumaş: önce yarı saydam çarşaf örtüsü, sonra gölge vadileri ve sırtlar ----
      final fk = g.foldScale;
      if (s.drape > 0.01) {
        final at = Offset(cx, s.grabY);
        final sy = fk * (1 + s.drapeStretch);
        _drawFold(canvas, a.drapeCov!, a.drapeSh!, a.drapeHi!, JuzzioClothAssets.drapeAnchor, JuzzioClothAssets.drapeSize, at, fk, sy,
            s.drape, kJuzzioDrapeStrength, 0.50, valley, ridge);
      }
      if (s.tension > 0.01) {
        final at = Offset(cx, root.dy + g.fistCenterY);
        final k = fk * (0.80 + 0.20 * s.tension);
        _drawFold(canvas, a.tensionCov!, a.tensionSh!, a.tensionHi!, JuzzioClothAssets.tensionAnchor, JuzzioClothAssets.tensionSize, at, k,
            k, s.tension, kJuzzioTensionStrength, 0.40, valley, ridge);
      }

      // ---- El / kol ----
      if (s.reveal > -2) {
        final layers = _frames(a, s);
        // v1.0.0: zemin gölgesi artık görüntü bulanıklığı (ImageFilter.blur) DEĞİL — bazı
        // Android GPU'larında (Impeller/Vulkan) bulanık sprite dikdörtgen leke/titreme
        // bırakıyordu. Yerine elin altına yumuşak radyal elips çizilir: sabit maliyet, artefakt yok.
        final rad = s.angleDeg * math.pi / 180;
        final handLen = s.curl > 0.5 ? g.fistCenterY : g.openTip * 0.72;
        final tip = root + Offset(math.sin(rad) * handLen, math.cos(rad) * handLen);
        final shadowCenter = tip + Offset(10 + 18 * s.lift, 16 + 22 * s.lift) * g.scale;
        final sw = (g.islandWidth * 0.62) * (1 + 0.5 * s.lift);
        final sh = sw * 0.42;
        final base = s.dark ? const Color(0xFF000000) : JuzzioClothShadowTone.light;
        final strength = (s.dark ? 0.34 : 0.16) * (1 - 0.85 * s.lift);
        if (strength > 0.01) {
          final oval = Rect.fromCenter(center: shadowCenter, width: sw, height: sh);
          canvas.drawOval(
            oval,
            Paint()
              ..shader = RadialGradient(
                colors: [base.withValues(alpha: strength), base.withValues(alpha: strength * 0.45), base.withValues(alpha: 0)],
                stops: const [0.0, 0.55, 1.0],
              ).createShader(oval),
          );
        }
        for (final (img, rot, alpha) in layers) {
          _drawSprite(canvas, img, root, rot, Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Colors.white.withValues(alpha: alpha));
        }
      }
      canvas.restore();
    }

    // ---- Dynamic Island: tam siyah, EN ÜST katman (el asla üstünü boyamaz) ----
    if (s.island > 0.01) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, g.islandCenterY), width: g.islandWidth, height: g.islandHeight),
        Radius.circular(g.islandHeight / 2),
      );
      // asla yarı saydam (gri) çizilmez: görünürken her zaman tam opak #000000
      canvas.drawRRect(r, Paint()..color = kJuzzioIslandColor);
    }
  }

  /// Çizilecek kare(ler): (görüntü, kök etrafında ek dönüş (rad), opaklık).
  /// Sarkaç: komşu iki poz karesi, aradaki açı farkı kökte küçük bir dönüşle kapatılır
  /// (kök sabit kalır, hayalet oluşmaz). Yumruk: kıvrılma kareleri arasında geçiş.
  List<(ui.Image, double, double)> _frames(JuzzioClothAssets a, JuzzioClothScene s) {
    if (s.curl > 0.001) {
      final x = s.curl.clamp(0.0, 1.0) * 7;
      final i0 = math.min(math.max(x.floor(), 0), 7);
      final i1 = math.min(i0 + 1, 7);
      final f = x - i0;
      return [(a.curl[i0], 0.0, 1.0), if (f > 0.02 && i1 != i0) (a.curl[i1], 0.0, f)];
    }
    final (i0, i1, f) = juzzioSwingFrame(s.angleDeg);
    double corr(int i) => (s.angleDeg - kJuzzioSwingAngles[i]) * 0.85 * math.pi / 180;
    return [(a.swing[i0], corr(i0), 1.0), if (f > 0.02 && i1 != i0) (a.swing[i1], corr(i1), f)];
  }

  void _drawSprite(Canvas canvas, ui.Image img, Offset root, double rot, Paint paint) {
    final sz = geo.spriteSize;
    final r0 = geo.rootInSprite;
    canvas.save();
    canvas.translate(root.dx, root.dy);
    if (rot != 0) canvas.rotate(-rot); // pozitif açı = uç sağa → saat yönünün tersi düzeltme
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(-r0.dx, -r0.dy, sz.width, sz.height), paint);
    canvas.restore();
  }

  /// Kıvrım haritası: [anchor] (haritadaki kavrama noktası) ekrandaki [at] noktasına oturur.
  /// Faz 4'te [sy] > [sx] (kumaş aşağı sarkar), Faz 5'te [sy] < [sx] (kumaş çentiğe doğru
  /// yukarı gerilerek düzleşir).
  void _drawFold(Canvas canvas, ui.Image cov, ui.Image sh, ui.Image hi, Offset anchor, Size mapSize, Offset at, double sx, double sy,
      double amount, double strength, double coverAlpha, Color valley, Color ridge) {
    final dst = Rect.fromLTWH(at.dx - anchor.dx * sx, at.dy - anchor.dy * sy, mapSize.width * sx, mapSize.height * sy);
    void draw(ui.Image img, Color c, double alpha) {
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = ColorFilter.mode(c.withValues(alpha: alpha.clamp(0.0, 1.0)), BlendMode.srcIn));
    }

    draw(cov, cloth, amount * coverAlpha);
    final op = amount * strength;
    // Güç > 1 iken vadi haritası iki kez çizilir; renk hiçbir zaman [valley]'den koyu olamaz
    if (op > 1) draw(sh, valley, op - 1);
    draw(sh, valley, op);
    draw(hi, ridge, op);
  }

  @override
  bool shouldRepaint(_ClothScenePainter old) => old.scene != scene || old.geo != geo || old.cloth != cloth;
}
