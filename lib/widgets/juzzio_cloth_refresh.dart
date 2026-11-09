// =============================================================================
// JUZZIO v1.1.1 — Tombul el ile "aşağı çek-yenile" (VEKTÖR yeniden çizim)
//
//  Neden yeniden: v0.9.9'daki önceden render edilmiş 3D sprite'lar poz kareleri arasında
//  çapraz geçişte hayalet/"ayak gibi" görünüyor, koyu temadaki kumaş tonları (#07080B)
//  içeriğin üstünde siyah leke gibi duruyordu. Artık el ve kumaş tamamen vektörle çizilir:
//   • El: tek siluet (dış çizgi + dünya-koordinatlı ten gradyanı), 4 tombul parmak, tırnaklar,
//     başparmak. Sarkaç = tek şeklin kök etrafında dönmesi; yumruk = parmakların bükülmesi
//     (kare geçişi yok → hayalet yok, her çözünürlükte keskin).
//   • Kol, temanın parlayan renginde bir manşetle çentikten çıkar (kesik görünmez).
//   • Kumaş: yumruğun kavradığı sayfa kenarı; rengi temanın zemininden açık bir yüzey,
//     kıvrımlar yumuşak vadi/sırt çizgileri. Hiçbir temada siyah leke oluşmaz.
//   • Dynamic Island: tam siyah kapsül, en üst katman; el yalnız çentiğin altında görünür.
//
//  Fazlar (değişmedi): 1) çekme (parmak uçları belirir) · 2) sarkaç (yenileme sürerken) ·
//  3) yumruk (kumaşı kavrar) · 4) yukarı çekme (içerik yumrukla aynı hızda kalkar) ·
//  5) ütüleme (kumaş çentiğe doğru toplanıp kaybolur).
//  Performans: içerik yalnız Transform ile kayar; çizim kök Overlay'de RepaintBoundary içinde
//  tek CustomPainter; görüntü bulanıklığı yok. "Hareketi azalt" açıksa el/kumaş çizilmez.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

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

const Color kJuzzioIslandColor = Color(0xFF000000);

/// v1.1.1 vektör el renkleri (sıcak, mat şeftali ten; koyu/siyah ton yok)
class JuzzioHandColors {
  JuzzioHandColors._();
  static const Color skin = Color(0xFFF8CBB6);
  static const Color shade = Color(0xFFE3A089);
  static const Color highlight = Color(0xFFFFE7DC);
  static const Color outline = Color(0xFFC7826B);
  static const Color nail = Color(0xFFFFF1EC);
}

/// Kumaş (yakalanan sayfa kenarı) renkleri: koyuda zeminden AÇIK yüzey, aydınlıkta beyaz.
/// Hiçbir temada siyaha yakın dolgu kullanılmaz (v0.9.9'daki siyah leke hatası).
({Color fill, Color valley, Color ridge}) juzzioSheetColors({required bool dark, required Color depth}) {
  if (dark) {
    return (
      fill: Color.lerp(depth, Colors.white, 0.12)!,
      valley: Colors.black.withValues(alpha: 0.14),
      ridge: Colors.white.withValues(alpha: 0.12),
    );
  }
  return (
    fill: Colors.white,
    valley: const Color(0xFF8A93A6).withValues(alpha: 0.16),
    ridge: Colors.white.withValues(alpha: 0.9),
  );
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

  /// Vektör el 115 px'lik çentik için tasarlandı (tasarım birimi × [scale] = mantıksal px).
  double get scale => islandWidth / 115.0;
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
  /// v1.1.1: kumaş rengi temanın derinlik renginden türetilir (koyuda AÇIK yüzey, siyah değil).
  ({Color fill, Color valley, Color ridge}) _sheetColors() {
    final dark = JuzzioAppController.instance.isDark;
    final c = juzzioSheetColors(dark: dark, depth: JuzzioGlassTokens.space.depth.first);
    final custom = widget.clothColor;
    return custom == null ? c : (fill: custom.withValues(alpha: 1), valley: c.valley, ridge: c.ridge);
  }

  void _insertOverlay() {
    if (_overlay != null || _reduceMotion) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final sheet = _sheetColors();
    final sleeve = JuzzioGlassTokens.glow;
    _overlay = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ClothScenePainter(scene: _scene, content: _content, geo: _geo, sheet: sheet, sleeve: sleeve),
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
// Sahne çizimi (v1.1.1: tamamen vektör)
// ---------------------------------------------------------------------------

/// Vektör elin parçaları (tasarım birimi; kök (0,0) = çentik merkezi, +y aşağı).
/// [curl] 0 açık el … 1 yumruk. Saf; testlerde doğrulanır.
class JuzzioHandShape {
  JuzzioHandShape(double curl) : c = curl.clamp(0.0, 1.0) {
    double l(double a, double b) => a + (b - a) * c;
    caps = <(Offset, Offset, double)>[
      (const Offset(0, -4), const Offset(0, 64), 20.0), // önkol
    ];
    const xs = [-19.0, -6.5, 6.5, 19.0];
    const lens = [19.0, 23.0, 22.0, 16.0];
    tips = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final end = Offset(xs[i], 112 + l(lens[i], 3.5));
      caps.add((Offset(xs[i], 112), end, 7.6));
      tips.add(end);
    }
    thumbBase = Offset(l(-25, -24), l(98, 104));
    thumbTip = Offset(l(-36, 4), l(120, 110));
    caps.add((thumbBase, thumbTip, 8.4));
    palm = Rect.fromCenter(center: Offset(0, l(96, 98)), width: 66, height: l(50, 46));
  }

  final double c;
  late final List<(Offset, Offset, double)> caps;
  late final List<Offset> tips;
  late final Offset thumbBase;
  late final Offset thumbTip;
  late final Rect palm;

  /// Elin en alt noktası (gölge ve kumaş bağlantısı için)
  double get lowestY => tips.map((t) => t.dy).fold<double>(thumbTip.dy, math.max) + 7.6;
}

class _ClothScenePainter extends CustomPainter {
  _ClothScenePainter({
    required this.scene,
    required this.content,
    required this.geo,
    required this.sheet,
    required this.sleeve,
  }) : super(repaint: Listenable.merge([scene, content]));

  final ValueNotifier<JuzzioClothScene> scene;
  final ValueNotifier<double> content;
  final JuzzioClothGeometry geo;
  final ({Color fill, Color valley, Color ridge}) sheet;
  final Color sleeve;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scene.value;
    final g = geo;
    final cx = size.width / 2;
    final k = g.scale;
    final root = Offset(cx, g.rootY(s.reveal));

    // El ve kumaş yalnız çentiğin alt kenarının altında görünür (maske)
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, g.islandBottomY - 0.5, size.width, size.height));

    // ---- Kumaş: yumruğun kavradığı sayfa kenarı ----
    final amount = math.max(s.tension, s.drape).clamp(0.0, 1.0);
    if (amount > 0.01) {
      final topY = math.max(root.dy + 108 * k, g.islandBottomY);
      final edge = g.contentTop + content.value;
      final shrink = (-s.drapeStretch).clamp(0.0, 1.0); // ütüleme: alt kenar yukarı toplanır
      final bottomY = edge + (topY - edge) * shrink;
      _drawSheet(canvas, size, cx, topY, bottomY, 24 * k, amount);
    }

    // ---- El ----
    if (s.reveal > -2) {
      final shape = JuzzioHandShape(s.curl);
      final rad = s.angleDeg * math.pi / 180;
      // yumuşak zemin gölgesi (radyal gradyan; görüntü bulanıklığı YOK → GPU artefaktı yok)
      final len = shape.lowestY * k;
      final tip = root + Offset(math.sin(rad) * len, math.cos(rad) * len);
      final c = tip + Offset(10 + 16 * s.lift, 2 + 14 * s.lift) * k;
      final w = 88 * k * (1 + 0.4 * s.lift);
      final strength = (s.dark ? 0.30 : 0.18) * (1 - 0.85 * s.lift);
      if (strength > 0.01) {
        final base = s.dark ? Colors.black : const Color(0xFF7D8597);
        final oval = Rect.fromCenter(center: c, width: w, height: w * 0.26);
        canvas.drawOval(
          oval,
          Paint()
            ..shader = RadialGradient(colors: [base.withValues(alpha: strength), base.withValues(alpha: 0)]).createShader(oval),
        );
      }
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(-rad); // pozitif açı = parmak ucu sağa
      canvas.scale(k);
      _drawHand(canvas, shape);
      canvas.restore();
    }
    canvas.restore();

    // ---- Dynamic Island: tam siyah, EN ÜST katman (el asla üstünü boyamaz) ----
    if (s.island > 0.01) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, g.islandCenterY), width: g.islandWidth, height: g.islandHeight),
        Radius.circular(g.islandHeight / 2),
      );
      canvas.drawRRect(r, Paint()..color = kJuzzioIslandColor);
    }
  }

  void _drawSheet(Canvas canvas, Size size, double cx, double topY, double bottomY, double hw, double amount) {
    final h = bottomY - topY;
    if (h < 4) return;
    // kısa kumaş dar kalır (ütüleme sonunda ekran boyu ince çizgi oluşmaz)
    final w = math.min(size.width / 2 + 6, hw + h * 2.4);
    final path = Path()
      ..moveTo(cx - hw, topY)
      ..cubicTo(cx - hw * 1.7, topY + h * 0.42, cx - w, bottomY - h * 0.42, cx - w, bottomY)
      ..quadraticBezierTo(cx, bottomY + math.min(10.0, h * 0.08), cx + w, bottomY)
      ..cubicTo(cx + w, bottomY - h * 0.42, cx + hw * 1.7, topY + h * 0.42, cx + hw, topY)
      ..close();
    final bounds = Rect.fromLTRB(cx - w, topY, cx + w, bottomY);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(sheet.fill, Colors.black, 0.05)!.withValues(alpha: 0.96 * amount),
            sheet.fill.withValues(alpha: 0.92 * amount),
          ],
        ).createShader(bounds),
    );
    // yumuşak kıvrımlar: yumruktan yelpaze gibi açılan vadi + ince sırt çizgileri
    if (h < 24) return;
    canvas.save();
    canvas.clipPath(path);
    final valley = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(3.0, hw * 0.22)
      ..color = sheet.valley.withValues(alpha: sheet.valley.a * amount);
    final ridge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, hw * 0.08)
      ..color = sheet.ridge.withValues(alpha: sheet.ridge.a * amount);
    for (final f in const [-0.72, -0.36, 0.0, 0.36, 0.72]) {
      final ex = f * w * 0.78;
      final start = Offset(cx + f * hw * 0.8, topY + 3);
      final ctrl = Offset(cx + ex * 0.5, topY + h * 0.45);
      final end = Offset(cx + ex, bottomY);
      canvas.drawPath(Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy), valley);
      final o = Offset(hw * 0.12, 0);
      canvas.drawPath(
          Path()
            ..moveTo(start.dx + o.dx, start.dy)
            ..quadraticBezierTo(ctrl.dx + o.dx, ctrl.dy, end.dx + o.dx * 1.4, end.dy),
          ridge);
    }
    canvas.restore();
  }

  void _drawHand(Canvas canvas, JuzzioHandShape shape) {
    final skin = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [JuzzioHandColors.highlight, JuzzioHandColors.skin, JuzzioHandColors.shade],
        stops: [0.0, 0.42, 1.0],
      ).createShader(const Rect.fromLTRB(-34, 0, 34, 30));
    Paint capPaint(Paint base, double width) => Paint()
      ..shader = base.shader
      ..color = base.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    final outline = Paint()..color = JuzzioHandColors.outline;
    final palm = RRect.fromRectAndRadius(shape.palm, const Radius.circular(20));

    // 1) dış çizgi (tüm parçalar), 2) dolgu (tüm parçalar) → tek, temiz siluet
    for (final (a, b, r) in shape.caps) {
      canvas.drawLine(a, b, capPaint(outline, 2 * r + 3));
    }
    canvas.drawRRect(palm.inflate(1.5), outline);
    for (final (a, b, r) in shape.caps) {
      canvas.drawLine(a, b, capPaint(skin, 2 * r));
    }
    canvas.drawRRect(palm, skin);

    final c = shape.c;
    final crease = Paint()
      ..color = JuzzioHandColors.shade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8;
    // parmak araları
    for (final x in const [-12.75, 0.0, 12.75]) {
      canvas.drawLine(Offset(x, 116), Offset(x, 128 - 10 * c), crease);
    }
    // yumrukta boğum çizgisi
    if (c > 0.3) {
      final a = ((c - 0.3) / 0.4).clamp(0.0, 1.0);
      canvas.drawPath(
        Path()
          ..moveTo(-26, 112)
          ..quadraticBezierTo(0, 118, 26, 112),
        Paint()
          ..color = JuzzioHandColors.shade.withValues(alpha: a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
    // tırnaklar (yumrukta parmak uçları içe kıvrılır → söner)
    final nail = Paint()..color = JuzzioHandColors.nail.withValues(alpha: 1 - c);
    if (c < 0.98) {
      for (final t in shape.tips) {
        canvas.drawOval(Rect.fromCenter(center: t.translate(0, 1), width: 8.4, height: 9.2 - 4.4 * c), nail);
      }
    }
    canvas.drawCircle(shape.thumbTip, 4.4, Paint()..color = JuzzioHandColors.nail);
    // parlama
    final hi = Paint()..color = JuzzioHandColors.highlight.withValues(alpha: 0.55);
    canvas.drawLine(const Offset(-9, 40), const Offset(-9, 62), capPaint(hi, 6));
    canvas.drawOval(Rect.fromCenter(center: Offset(-12, shape.palm.top + 8), width: 18, height: 10), hi);

    // kol manşeti: temanın parlayan rengi (kol çentikten "kesik" görünmez)
    final cuff = RRect.fromRectAndRadius(const Rect.fromLTWH(-25, -10, 50, 44), const Radius.circular(13));
    canvas.drawRRect(
      cuff,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(sleeve, Colors.white, 0.55)!, sleeve],
        ).createShader(cuff.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-25, 26, 50, 8), const Radius.circular(4)),
      Paint()..color = Color.lerp(sleeve, Colors.black, 0.22)!,
    );
  }

  @override
  bool shouldRepaint(_ClothScenePainter old) =>
      old.scene != scene || old.content != content || old.geo != geo || old.sheet != sheet || old.sleeve != sleeve;
}
