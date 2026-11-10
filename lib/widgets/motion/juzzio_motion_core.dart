// =============================================================================
// JUZZIO v1.1.0 — Hareket çekirdeği (referans videolar: iOS Feedback Patterns +
// 10 Page Transitions). Tüm bileşenler tema belirteçlerinden (JuzzioGlassTokens)
// renk alır; yalnız transform/opacity animasyonu (GPU dostu); "Hareketi azalt"
// açıksa animasyonlar anında biter.
//
//  • kJuzzioSpring / JuzzioSpringCurve — doğal yaylanma eğrileri
//  • JuzzioHaptics — gönderim, anahtar, eşik, uzun basma titreşimleri
//  • JuzzioFlashHighlight — alıntıdan gidilen mesajı kısa süre parlatır
//  • JuzzioHud — ekranı kaplamayan cam bildirim (kopyalandı, mikrofon kapalı…)
//  • showJuzzioSheet — arkası bulanıklaşan, yaylanan alt sayfa (#08 Bottom Sheet)
//  • showJuzzioActionSheet — kritik işlemler için alttan açılan eylem sayfası
//  • JuzzioZoomRoute — ızgaradan tam ekrana yakınlaşma geçişi (#03 Zoom)
//  • JuzzioSymbolSwap — ikon durum değişiminde ölçeklenip zıplama (Symbol Effect)
//  • JuzzioIsland / JuzzioLiveIsland — Dynamic Island tarzı canlı durum kapsülü
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';

/// Şartname eğrisi: cubic-bezier(0.22, 1, 0.36, 1)
const Curve kJuzzioSpring = Cubic(0.22, 1, 0.36, 1);

/// Hafif aşmalı sönümlü yay (zıplayan rozetler, ikon değişimleri)
class JuzzioSpringCurve extends Curve {
  const JuzzioSpringCurve({this.damping = 6.5, this.frequency = 2.4});
  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) {
    final w = frequency * 2 * math.pi;
    return 1 - math.exp(-damping * t) * math.cos(w * t * 0.5);
  }
}

bool juzzioReduceMotion(BuildContext? context) {
  if (JuzzioAppController.instance.reduceMotion) return true;
  // v1.2.0: Performans modu süs animasyonlarını da kapatır (konfeti, parçacık, yaylı girişler)
  if (JuzzioGlassTokens.reducedEffects) return true;
  if (context == null) return false;
  return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Titreşim kalıpları (light / medium / selection)
class JuzzioHaptics {
  JuzzioHaptics._();
  static void send() => HapticFeedback.lightImpact();
  static void toggle() => HapticFeedback.selectionClick();
  static void threshold() => HapticFeedback.mediumImpact();
  static void longPress() => HapticFeedback.mediumImpact();
  static void success() => HapticFeedback.lightImpact();
  static void warning() => HapticFeedback.heavyImpact();
}

/// Alıntıdan gidilen mesajı kısa süre vurgular
class JuzzioFlashHighlight extends StatelessWidget {
  const JuzzioFlashHighlight({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1.0 : 0.0),
      duration: Duration(milliseconds: active ? 260 : 700),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, child) {
        if (v <= 0.001) return child!;
        final c = JuzzioGlassTokens.glow;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16 * v),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.28 * v), blurRadius: 22 * v)],
          ),
          child: child,
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// HUD — üstten yumuşakça beliren yarı saydam cam bildirim
// -----------------------------------------------------------------------------
class JuzzioHud {
  JuzzioHud._();
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, {required IconData icon, required String text, Duration duration = const Duration(milliseconds: 1500)}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _timer?.cancel();
    _entry?.remove();
    final key = GlobalKey<_HudViewState>();
    final entry = OverlayEntry(builder: (_) => _HudView(key: key, icon: icon, text: text));
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () async {
      await key.currentState?.dismiss();
      if (identical(_entry, entry)) {
        entry.remove();
        _entry = null;
      }
    });
  }
}

class _HudView extends StatefulWidget {
  const _HudView({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  State<_HudView> createState() => _HudViewState();
}

class _HudViewState extends State<_HudView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();

  Future<void> dismiss() async {
    if (!mounted) return;
    await _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 10;
    final anim = CurvedAnimation(parent: _c, curve: const JuzzioSpringCurve(), reverseCurve: Curves.easeIn);
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: anim,
            builder: (context, child) => Opacity(
              opacity: _c.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -16 * (1 - anim.value)),
                child: Transform.scale(scale: 0.86 + 0.14 * anim.value, child: child),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: JuzzioGlassTokens.sheet.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: JuzzioGlassTokens.border),
                      boxShadow: JuzzioGlassTokens.glowShadow(0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 18, color: JuzzioGlassTokens.glowText),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Bulanık arka planlı, yaylanan alt sayfa (#08 Bottom Sheet)
// -----------------------------------------------------------------------------
class JuzzioBlurSheetRoute<T> extends ModalBottomSheetRoute<T> {
  JuzzioBlurSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.backgroundColor,
    super.shape,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    super.settings,
    this.barrierBlur = 10,
  });

  /// v1.2.0: arka plan bulanıklığı (sigma); seçim sayfaları daha güçlü bulanıklık kullanır
  final double barrierBlur;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    final a = animation;
    if (a == null || JuzzioGlassTokens.reducedEffects || JuzzioAppController.instance.reduceMotion) return barrier;
    return AnimatedBuilder(
      animation: a,
      child: barrier,
      builder: (context, child) {
        final t = a.value.clamp(0.0, 1.0);
        if (t <= 0.01) return child!;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: barrierBlur * t, sigmaY: barrierBlur * t),
          child: child,
        );
      },
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // ModalBottomSheet kendi kaydırmasını yapar; üstüne hafif yay ölçeği eklenir
    if (JuzzioAppController.instance.reduceMotion) return child;
    final curved = CurvedAnimation(parent: animation, curve: kJuzzioSpring, reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => Transform.scale(
        alignment: Alignment.bottomCenter,
        scale: 0.96 + 0.04 * curved.value,
        child: child,
      ),
    );
  }
}

/// showModalBottomSheet ile aynı imza (kullanılan parametreler) + bulanık arka plan
Future<T?> showJuzzioSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  Color? barrierColor,
  bool? showDragHandle,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
  double barrierBlur = 10,
}) {
  final nav = Navigator.of(context, rootNavigator: useRootNavigator);
  final loc = MaterialLocalizations.of(context);
  JuzzioHaptics.toggle();
  return nav.push(JuzzioBlurSheetRoute<T>(
    builder: builder,
    capturedThemes: InheritedTheme.capture(from: context, to: nav.context),
    isScrollControlled: isScrollControlled,
    barrierLabel: loc.scrimLabel,
    backgroundColor: backgroundColor,
    shape: shape,
    modalBarrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.34),
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    settings: routeSettings,
    barrierBlur: barrierBlur,
  ));
}

// -----------------------------------------------------------------------------
// Eylem sayfası (çıkış, sohbeti temizle, mesaj sil)
// -----------------------------------------------------------------------------
class JuzzioSheetAction {
  const JuzzioSheetAction(this.label, {this.icon, this.destructive = false});
  final String label;
  final IconData? icon;
  final bool destructive;
}

/// Seçilen eylemin sırasını döndürür (vazgeçilirse null)
Future<int?> showJuzzioActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  required List<JuzzioSheetAction> actions,
  String? cancelLabel,
}) {
  final app = JuzzioAppController.instance;
  return showJuzzioSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      Widget group(List<Widget> children) => ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: JuzzioGlassTokens.sheet,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: JuzzioGlassTokens.border),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          );
      final danger = Theme.of(ctx).colorScheme.error;
      final rows = <Widget>[];
      if (title != null || message != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Column(
            children: [
              if (title != null)
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
              if (message != null) ...[
                const SizedBox(height: 4),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13)),
              ],
            ],
          ),
        ));
      }
      for (var i = 0; i < actions.length; i++) {
        final a = actions[i];
        if (rows.isNotEmpty) rows.add(Divider(height: 1, color: JuzzioGlassTokens.border));
        rows.add(InkWell(
          onTap: () {
            if (a.destructive) JuzzioHaptics.warning();
            Navigator.of(ctx).pop(i);
          },
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (a.icon != null) ...[
                  Icon(a.icon, size: 20, color: a.destructive ? danger : JuzzioGlassTokens.glowText),
                  const SizedBox(width: 10),
                ],
                Text(a.label,
                    style: TextStyle(
                      color: a.destructive ? danger : JuzzioGlassTokens.textPrimary,
                      fontWeight: a.destructive ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                    )),
              ],
            ),
          ),
        ));
      }
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              group(rows),
              const SizedBox(height: 8),
              group([
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: SizedBox(
                    height: 54,
                    child: Center(
                      child: Text(cancelLabel ?? app.trEn('Vazgeç', 'Cancel', 'Abbrechen'),
                          style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      );
    },
  );
}

// -----------------------------------------------------------------------------
// Yakınlaşma geçişi (#03 Zoom) — medya ızgarasından tam ekran önizlemeye
// -----------------------------------------------------------------------------
class JuzzioZoomRoute<T> extends PageRouteBuilder<T> {
  JuzzioZoomRoute({required WidgetBuilder builder, this.origin})
      : super(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, _, __) => builder(context),
        );

  /// Dokunulan öğenin ekran üzerindeki kutusu (varsa yakınlaşma oradan başlar)
  final Rect? origin;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (JuzzioAppController.instance.reduceMotion) return FadeTransition(opacity: animation, child: child);
    final curved = CurvedAnimation(parent: animation, curve: kJuzzioSpring, reverseCurve: Curves.easeInCubic);
    final size = MediaQuery.sizeOf(context);
    Alignment align = Alignment.center;
    final o = origin;
    if (o != null && size.width > 0 && size.height > 0) {
      align = Alignment((o.center.dx / size.width) * 2 - 1, (o.center.dy / size.height) * 2 - 1);
    }
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.scale(alignment: align, scale: 0.72 + 0.28 * curved.value, child: child),
      ),
    );
  }
}

/// Bir widget'ın ekran kutusu (yakınlaşma başlangıcı için)
Rect? juzzioGlobalRect(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final o = box.localToGlobal(Offset.zero);
  return o & box.size;
}

// -----------------------------------------------------------------------------
// Symbol Effect — ikon değişiminde ölçeklenip zıplama
// -----------------------------------------------------------------------------
class JuzzioSymbolSwap extends StatelessWidget {
  const JuzzioSymbolSwap({super.key, required this.child, this.duration = const Duration(milliseconds: 380)});
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: juzzioReduceMotion(context) ? Duration.zero : duration,
      switchInCurve: const JuzzioSpringCurve(),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween<double>(begin: 0.4, end: 1).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: child,
    );
  }
}

/// Değer her değiştiğinde çocuğu bir kez zıplatır (bildirim çanı, sabitleme ikonu…)
class JuzzioBounceOnChange extends StatefulWidget {
  const JuzzioBounceOnChange({super.key, required this.value, required this.child});
  final Object? value;
  final Widget child;
  @override
  State<JuzzioBounceOnChange> createState() => _JuzzioBounceOnChangeState();
}

class _JuzzioBounceOnChangeState extends State<JuzzioBounceOnChange> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(covariant JuzzioBounceOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !JuzzioAppController.instance.reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final s = t == 0 || t == 1 ? 1.0 : 1 + 0.28 * math.sin(math.pi * t) * math.exp(-2.4 * t);
        final r = t == 0 || t == 1 ? 0.0 : 0.22 * math.sin(3 * math.pi * t) * (1 - t);
        return Transform.rotate(angle: r, child: Transform.scale(scale: s, child: child));
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Dynamic Island / Live Activity — üstte genişleyip daralan canlı durum kapsülü
// -----------------------------------------------------------------------------
class JuzzioIslandActivity {
  JuzzioIslandActivity({
    required this.id,
    required this.icon,
    required this.label,
    this.detail,
    this.color,
    this.progress,
    this.startedAt,
    this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? detail;
  final Color? color;

  /// 0..1 ilerleme (yükleme); null = belirsiz
  final double? progress;

  /// süre sayacı (arama / kayıt)
  final DateTime? startedAt;
  final VoidCallback? onTap;
}

class JuzzioIsland extends ChangeNotifier {
  JuzzioIsland._();
  static final JuzzioIsland instance = JuzzioIsland._();

  final Map<String, JuzzioIslandActivity> _items = {};
  int _suppress = 0;

  JuzzioIslandActivity? get current => _items.isEmpty || _suppress > 0 ? null : _items.values.last;
  int get count => _items.length;

  void set(JuzzioIslandActivity a) {
    _items.remove(a.id);
    _items[a.id] = a;
    notifyListeners();
  }

  void clear(String id) {
    if (_items.remove(id) != null) notifyListeners();
  }

  /// Etkinliğin kendi ekranı açıkken (ör. arama ekranı) kapsül gizlenir
  void suppress() {
    _suppress++;
    notifyListeners();
  }

  void unsuppress() {
    if (_suppress > 0) _suppress--;
    notifyListeners();
  }
}

String juzzioFormatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class JuzzioLiveIsland extends StatefulWidget {
  const JuzzioLiveIsland({super.key});
  @override
  State<JuzzioLiveIsland> createState() => _JuzzioLiveIslandState();
}

class _JuzzioLiveIslandState extends State<JuzzioLiveIsland> {
  bool _expanded = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    JuzzioIsland.instance.addListener(_onChange);
    _onChange();
  }

  void _onChange() {
    final cur = JuzzioIsland.instance.current;
    if (cur?.startedAt != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
    if (cur == null) _expanded = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    JuzzioIsland.instance.removeListener(_onChange);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = JuzzioIsland.instance.current;
    // v1.2.0: kapsül artık başlığın (profil fotoğrafı + ad) ALTINDA durur; başlığı örtmez
    final top = MediaQuery.paddingOf(context).top + 66;
    final accent = a?.color ?? JuzzioGlassTokens.glow;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : const Color(0xFF15151A);
    final inkSoft = dark ? Colors.white70 : const Color(0xB315151A);
    final radius = BorderRadius.circular(_expanded ? 26 : 999);
    final elapsed = a?.startedAt == null ? null : juzzioFormatElapsed(DateTime.now().difference(a!.startedAt!));
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: const JuzzioSpringCurve(),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
          child: a == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : GestureDetector(
                  key: const ValueKey('island'),
                  onTap: () {
                    JuzzioHaptics.toggle();
                    if (_expanded && a.onTap != null) {
                      a.onTap!();
                    } else {
                      setState(() => _expanded = !_expanded);
                    }
                  },
                  // v1.2.0: şeffaf cam (glassmorphism) — karanlık ve aydınlık modda okunur
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.30 : 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: ClipRRect(
                    borderRadius: radius,
                    child: BackdropFilter(
                    // v1.2.0: performans modunda bulanıklık yok (yalnız yarı saydam zemin)
                    filter: JuzzioGlassTokens.reducedEffects ? ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0) : ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    curve: kJuzzioSpring,
                    constraints: BoxConstraints(minWidth: _expanded ? 280 : 128, maxWidth: _expanded ? 340 : 260),
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: _expanded ? 14 : 8),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0x52141418) : const Color(0x8CFFFFFF),
                      borderRadius: radius,
                      border: Border.all(color: dark ? const Color(0x33FFFFFF) : const Color(0x1F000000)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent.withValues(alpha: dark ? 0.16 : 0.10), Colors.transparent],
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 360),
                        curve: kJuzzioSpring,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _IslandPulse(color: accent, child: Icon(a.icon, size: 16, color: accent)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(a.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700)),
                                ),
                                if (elapsed != null) ...[
                                  const SizedBox(width: 10),
                                  Text(elapsed,
                                      style: TextStyle(
                                          color: accent, fontSize: 13, fontWeight: FontWeight.w800, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                                ],
                                if (a.progress != null && elapsed == null) ...[
                                  const SizedBox(width: 10),
                                  Text('${(a.progress!.clamp(0.0, 1.0) * 100).round()}%',
                                      style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
                                ],
                              ],
                            ),
                            if (_expanded) ...[
                              if ((a.detail ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(a.detail!, style: TextStyle(color: inkSoft, fontSize: 12.5)),
                              ],
                              if (a.progress != null) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: a.progress!.clamp(0.0, 1.0),
                                    minHeight: 4,
                                    color: accent,
                                    backgroundColor: ink.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                              if (a.onTap != null) ...[
                                const SizedBox(height: 8),
                                Text(JuzzioAppController.instance.trEn('Açmak için dokun', 'Tap to open', 'Zum Öffnen tippen'),
                                    style: TextStyle(color: accent.withValues(alpha: 0.85), fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                  ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _IslandPulse extends StatefulWidget {
  const _IslandPulse({required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  State<_IslandPulse> createState() => _IslandPulseState();
}

class _IslandPulseState extends State<_IslandPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (!JuzzioAppController.instance.reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.10 + 0.14 * (1 - _c.value)),
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)), blurRadius: 2 + 8 * _c.value, spreadRadius: 3 * _c.value)],
        ),
        child: child,
      ),
    );
  }
}
