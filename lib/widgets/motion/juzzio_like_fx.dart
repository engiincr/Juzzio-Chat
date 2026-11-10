// =============================================================================
// JUZZIO v1.1.0 — Beğeni, tepki ve kaydetme animasyonları (referans: "10 like")
//  • JuzzioDoubleTapHeart (#03 Double-tap): fotoğraf/videoya çift dokununca
//    ortada büyüyüp kaybolan kalp
//  • JuzzioReactionBurst  (#02 Burst ring + #06 Draw-on): tepki seçilince kalp
//    çizilerek dolar, etrafında ince halka ve parçacık patlaması
//  • JuzzioFloatingReactions (#04 Floating hearts): aramada alttan süzülen tepkiler
//  • JuzzioStarSave       (#10 Star save): yıldızlı mesaja eklerken dönen,
//    ışıltı saçan yıldız
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import 'juzzio_motion_core.dart';

/// Kalp yolu (birim kare içinde, merkez 0,0, genişlik ~2)
Path juzzioHeartPath(double size) {
  final s = size / 2;
  return Path()
    ..moveTo(0, s * 0.78)
    ..cubicTo(-s * 1.05, s * 0.05, -s * 0.95, -s * 0.85, -s * 0.48, -s * 0.85)
    ..cubicTo(-s * 0.18, -s * 0.85, 0, -s * 0.62, 0, -s * 0.42)
    ..cubicTo(0, -s * 0.62, s * 0.18, -s * 0.85, s * 0.48, -s * 0.85)
    ..cubicTo(s * 0.95, -s * 0.85, s * 1.05, s * 0.05, 0, s * 0.78)
    ..close();
}

const Color kJuzzioHeartRed = Color(0xFFFF3B6B);

// -----------------------------------------------------------------------------
class JuzzioDoubleTapHeart extends StatefulWidget {
  const JuzzioDoubleTapHeart({super.key, required this.child, this.onDoubleTap, this.onTap});
  final Widget child;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTap;
  @override
  State<JuzzioDoubleTapHeart> createState() => _JuzzioDoubleTapHeartState();
}

class _JuzzioDoubleTapHeartState extends State<JuzzioDoubleTapHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 820));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap == null
          ? null
          : () {
              JuzzioHaptics.send();
              if (!juzzioReduceMotion(context)) _c.forward(from: 0);
              widget.onDoubleTap!();
            },
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                if (t == 0 || t == 1) return const SizedBox.shrink();
                final k = const JuzzioSpringCurve(damping: 5, frequency: 2.6).transform((t / 0.55).clamp(0.0, 1.0));
                final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, t > 0.7 ? -30 * (t - 0.7) / 0.3 : 0),
                    child: Transform.scale(
                      scale: 0.2 + 0.9 * k,
                      child: CustomPaint(size: const Size(84, 84), painter: _HeartPainter(fill: 1, color: Colors.white, glow: kJuzzioHeartRed)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  _HeartPainter({required this.fill, required this.color, this.glow, this.draw = 1, this.strokeColor});
  final double fill;
  final double draw;
  final Color color;
  final Color? glow;
  final Color? strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final path = juzzioHeartPath(size.shortestSide * 0.9);
    if (glow != null && fill > 0) {
      canvas.drawPath(path, Paint()..color = glow!.withValues(alpha: 0.55 * fill)..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.12));
    }
    if (draw > 0 && draw < 1) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.07
        ..strokeCap = StrokeCap.round
        ..color = strokeColor ?? color;
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * draw), p);
      }
    }
    if (fill > 0) {
      canvas.save();
      canvas.scale(fill, fill);
      canvas.drawPath(path, Paint()..color = color);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeartPainter o) => o.fill != fill || o.draw != draw || o.color != color || o.glow != glow;
}

// -----------------------------------------------------------------------------
// Tepki patlaması: ❤️ ise çizilerek dolan kalp; diğer emojiler zıplar. Halka + parçacıklar
// -----------------------------------------------------------------------------
class JuzzioReactionBurst extends StatefulWidget {
  const JuzzioReactionBurst({super.key, required this.emoji, this.size = 64, this.emojiStyle});
  final String emoji;
  final double size;
  final TextStyle? emojiStyle;
  @override
  State<JuzzioReactionBurst> createState() => _JuzzioReactionBurstState();
}

class _JuzzioReactionBurstState extends State<JuzzioReactionBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // v1.2.0: yalnız düz kalp çizilir; ❤️‍🔥, ❤️‍🩹 gibi birleşik emojiler kendi görünümüyle patlar
  bool get _isHeart => juzzioIsPlainHeart(widget.emoji);

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final glow = JuzzioGlassTokens.glow;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
        final ring = (t / 0.6).clamp(0.0, 1.0);
        final ringColor = _isHeart ? kJuzzioHeartRed : glow;
        return Opacity(
          opacity: fade,
          child: SizedBox(
            width: s * 2,
            height: s * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ince halka patlaması
                if (ring > 0 && ring < 1)
                  Container(
                    width: s * (0.6 + 1.1 * ring),
                    height: s * (0.6 + 1.1 * ring),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor.withValues(alpha: 1 - ring), width: 3 * (1 - ring) + 0.6),
                    ),
                  ),
                // parçacıklar
                CustomPaint(size: Size.square(s * 2), painter: _BurstDotsPainter(t: ring, color: ringColor)),
                if (_isHeart)
                  CustomPaint(
                    size: Size.square(s),
                    painter: _HeartPainter(
                      draw: (t / 0.35).clamp(0.0, 1.0),
                      fill: const JuzzioSpringCurve(damping: 5, frequency: 2.6).transform(((t - 0.3) / 0.45).clamp(0.0, 1.0)),
                      color: kJuzzioHeartRed,
                      glow: kJuzzioHeartRed,
                    ),
                  )
                else
                  Transform.scale(
                    scale: 0.35 + 0.75 * const JuzzioSpringCurve(damping: 5, frequency: 2.6).transform((t / 0.5).clamp(0.0, 1.0)),
                    child: Text(widget.emoji, style: widget.emojiStyle ?? TextStyle(fontSize: s * 0.8)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BurstDotsPainter extends CustomPainter {
  _BurstDotsPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide * (0.22 + 0.26 * Curves.easeOutCubic.transform(t));
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.2;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(p, 3.2 * (1 - t) + 0.4, Paint()..color = (i.isEven ? color : Colors.white).withValues(alpha: 1 - t));
    }
  }

  @override
  bool shouldRepaint(covariant _BurstDotsPainter o) => o.t != t || o.color != color;
}

// -----------------------------------------------------------------------------
// Arama içi süzülen tepkiler
// -----------------------------------------------------------------------------
class JuzzioFloatingReactionsController extends ChangeNotifier {
  final List<_Floater> _items = [];
  final math.Random _rnd = math.Random();

  void add(String emoji) {
    if (JuzzioGlassTokens.reducedEffects && _items.length >= 3) return; // v1.2.0: performans modu — en fazla 3 uçan tepki
    if (_items.length > 40) _items.removeAt(0);
    _items.add(_Floater(emoji, DateTime.now(), 0.15 + _rnd.nextDouble() * 0.7, _rnd.nextDouble() * math.pi * 2, 0.9 + _rnd.nextDouble() * 0.5));
    notifyListeners();
  }
}

class _Floater {
  _Floater(this.emoji, this.born, this.x, this.phase, this.scale);
  final String emoji;
  final DateTime born;
  final double x;
  final double phase;
  final double scale;
}

class JuzzioFloatingReactions extends StatefulWidget {
  const JuzzioFloatingReactions({super.key, required this.controller});
  final JuzzioFloatingReactionsController controller;
  @override
  State<JuzzioFloatingReactions> createState() => _JuzzioFloatingReactionsState();
}

class _JuzzioFloatingReactionsState extends State<JuzzioFloatingReactions> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  static const double _lifeS = 2.8;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _frame());
    widget.controller.addListener(_wake);
  }

  void _wake() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _frame() {
    final now = DateTime.now();
    widget.controller._items.removeWhere((f) => now.difference(f.born).inMilliseconds > _lifeS * 1000);
    if (widget.controller._items.isEmpty) _ticker.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_wake);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final f in widget.controller._items)
              Builder(builder: (context) {
                final t = (now.difference(f.born).inMilliseconds / (_lifeS * 1000)).clamp(0.0, 1.0);
                final y = box.maxHeight * (1 - t * 0.85) - 40;
                final x = box.maxWidth * f.x + math.sin(f.phase + t * 7) * 18;
                final op = t < 0.1 ? t / 0.1 : (t > 0.7 ? (1 - (t - 0.7) / 0.3) : 1.0);
                final sc = f.scale * (t < 0.12 ? 0.4 + 0.6 * (t / 0.12) : 1.0);
                return Positioned(
                  left: x - 18,
                  top: y,
                  child: Opacity(
                    opacity: op.clamp(0.0, 1.0),
                    child: Transform.scale(scale: sc, child: Text(f.emoji, style: const TextStyle(fontSize: 32))),
                  ),
                );
              }),
          ],
        );
      }),
    );
  }
}

// -----------------------------------------------------------------------------
// Yıldız kaydet
// -----------------------------------------------------------------------------
class JuzzioStarSave extends StatefulWidget {
  const JuzzioStarSave({super.key, required this.saved, this.size = 22, this.color, this.idleColor, this.playOnMount = false});
  final bool saved;

  /// ilk çizimde de dönüp ışıltı saçar (az önce kaydedildi)
  final bool playOnMount;
  final double size;
  final Color? color;
  final Color? idleColor;
  @override
  State<JuzzioStarSave> createState() => _JuzzioStarSaveState();
}

class _JuzzioStarSaveState extends State<JuzzioStarSave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 760), value: 1);

  @override
  void initState() {
    super.initState();
    if (widget.playOnMount && widget.saved && !JuzzioAppController.instance.reduceMotion) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant JuzzioStarSave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.saved && widget.saved && !JuzzioAppController.instance.reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = widget.color ?? const Color(0xFFFFC83D);
    final idle = widget.idleColor ?? JuzzioGlassTokens.textSecondary;
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final spin = t < 1 ? Curves.easeOutCubic.transform(t) * 2 * math.pi * 0.4 : 0.0;
        final pop = t < 1 ? 1 + 0.35 * math.sin(math.pi * t) : 1.0;
        return SizedBox(
          width: s * 1.15,
          height: s * 1.15,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.saved && t > 0 && t < 1)
                OverflowBox(
                  maxWidth: s * 2.4,
                  maxHeight: s * 2.4,
                  child: CustomPaint(size: Size.square(s * 2.4), painter: _SparklePainter(t: t, color: gold)),
                ),
              Transform.rotate(
                angle: spin,
                child: Transform.scale(
                  scale: pop,
                  child: Icon(widget.saved ? Icons.star_rounded : Icons.star_outline_rounded, size: s, color: widget.saved ? gold : idle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * (0.25 + 0.3 * Curves.easeOutCubic.transform(t));
    final p = Paint()
      ..color = color.withValues(alpha: 1 - t)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r, c + dir * (r + 4 * (1 - t) + 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter o) => o.t != t;
}

/// Düz kırmızı kalp mi? (❤️‍🔥 / ❤️‍🩹 gibi ZWJ birleşimleri hariç) — saf, test edilir
bool juzzioIsPlainHeart(String emoji) {
  final e = emoji.trim();
  return e == '❤️' || e == '❤' || e == '♥️' || e == '♥';
}

