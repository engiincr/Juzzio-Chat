// =============================================================================
// JUZZIO v1.1.0 — Yükleyiciler (referans: "10 loaders"; yalnız hareket mekaniği
// alındı, tematik görseller kullanılmadı — renkler etkin Juzzio temasından gelir)
//  • JuzzioOrbitLoader  (#07 Orbit): arkasında ışıklı iz bırakan yörünge halkası.
//    value verilirse #09 yüzde halkasına dönüşür (büyük boyutta ortada % sayacı).
//    CircularProgressIndicator ile aynı parametreler → tüm uygulamada yerini aldı.
//  • JuzzioSparklerBar  (#03 Sparkler): ucunda ışık parçacıkları saçan ince çubuk.
//    LinearProgressIndicator ile aynı parametreler.
//  • JuzzioTypingBubble (#06 3 nokta zıplama): "yazıyor…" balonu.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';

class JuzzioOrbitLoader extends StatefulWidget {
  const JuzzioOrbitLoader({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 3.4,
    this.showPercent,
    this.semanticsLabel,
  });

  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double strokeWidth;

  /// null: boyut ≥ 44 ise ve value varsa ortada yüzde gösterilir
  final bool? showPercent;
  final String? semanticsLabel;

  @override
  State<JuzzioOrbitLoader> createState() => _JuzzioOrbitLoaderState();
}

class _JuzzioOrbitLoaderState extends State<JuzzioOrbitLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant JuzzioOrbitLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final spin = widget.value == null && !JuzzioAppController.instance.reduceMotion;
    if (spin && !_c.isAnimating) {
      _c.repeat();
    } else if (!spin && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? JuzzioGlassTokens.glow;
    final v = widget.value;
    return Semantics(
      label: widget.semanticsLabel,
      value: v == null ? null : '${(v.clamp(0.0, 1.0) * 100).round()}%',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        child: LayoutBuilder(builder: (context, box) {
          // CircularProgressIndicator gibi: sıkı kısıtta onu doldurur, serbestte 36 px
          final w = box.hasTightWidth ? box.maxWidth : math.min(math.max(36.0, box.minWidth), box.maxWidth);
          final h = box.hasTightHeight ? box.maxHeight : math.min(math.max(36.0, box.minHeight), box.maxHeight);
          final side = math.min(w, h);
          final percent = v != null && (widget.showPercent ?? side >= 44);
          return SizedBox(
            width: side,
            height: side,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _OrbitPainter(
                  t: _c.value,
                  value: v,
                  color: color,
                  track: widget.backgroundColor ?? color.withValues(alpha: 0.16),
                  stroke: widget.strokeWidth,
                ),
                child: percent
                    ? Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: (v ?? 0.0).clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, x, _) => Text(
                            '${(x * 100).round()}%',
                            style: TextStyle(
                              color: JuzzioGlassTokens.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: (side * 0.24).clamp(10.0, 22.0),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.t, required this.value, required this.color, required this.track, required this.stroke});
  final double t;
  final double? value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke - 1;
    if (r <= 1) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    final v = value;
    if (v != null) {
      // #09 yüzde halkası
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track);
      final sweep = 2 * math.pi * v.clamp(0.0, 1.0);
      if (sweep <= 0) return;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: const GradientRotation(-math.pi / 2),
            colors: [color.withValues(alpha: 0.55), color],
            stops: [0, v.clamp(0.01, 1.0)],
          ).createShader(rect),
      );
      final head = c + Offset(math.cos(-math.pi / 2 + sweep), math.sin(-math.pi / 2 + sweep)) * r;
      canvas.drawCircle(head, stroke * 1.3, Paint()..color = color.withValues(alpha: 0.6)..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.4));
      canvas.drawCircle(head, stroke * 0.7, Paint()..color = Colors.white.withValues(alpha: 0.9));
      return;
    }
    // #07 yörünge: soluk yörünge + kuyruklu kuyruklu yıldız
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke * 0.5..color = track);
    final angle = 2 * math.pi * t - math.pi / 2;
    const trail = math.pi * 1.25;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle - trail);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(
      rect,
      0,
      trail,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: trail,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.95)],
        ).createShader(rect),
    );
    canvas.restore();
    final head = c + Offset(math.cos(angle), math.sin(angle)) * r;
    canvas.drawCircle(head, stroke * 1.8, Paint()..color = color.withValues(alpha: 0.55)..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 2));
    canvas.drawCircle(head, stroke * 0.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter o) => o.t != t || o.value != value || o.color != color || o.track != track || o.stroke != stroke;
}

/// Ortasında yüzde sayacı olan büyük halka (büyük medya / ses aktarımı)
class JuzzioPercentRing extends StatelessWidget {
  const JuzzioPercentRing({super.key, required this.value, this.size = 64, this.color});
  final double value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: JuzzioOrbitLoader(value: value, color: color, strokeWidth: math.max(3.0, size / 16), showPercent: true),
      );
}

// -----------------------------------------------------------------------------
// #03 Sparkler — ucunda ışık parçacıkları saçan ilerleme çubuğu
// -----------------------------------------------------------------------------
class JuzzioSparklerBar extends StatefulWidget {
  const JuzzioSparklerBar({
    super.key,
    this.value,
    this.minHeight = 4,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.semanticsLabel,
  });

  final double? value;
  final double minHeight;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;

  @override
  State<JuzzioSparklerBar> createState() => _JuzzioSparklerBarState();
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.life);
  double x, y, vx, vy, life;
}

class _JuzzioSparklerBarState extends State<JuzzioSparklerBar> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Spark> _sparks = [];
  final math.Random _rnd = math.Random();
  Duration _last = Duration.zero;
  double _phase = 0;
  double _shown = 0;

  bool get _animate => !JuzzioAppController.instance.reduceMotion;

  @override
  void initState() {
    super.initState();
    _shown = widget.value?.clamp(0.0, 1.0) ?? 0;
    _ticker = createTicker(_onTick);
    if (_animate) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant JuzzioSparklerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _settledFor = 0;
      if (_animate && !_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    }
  }

  double _settledFor = 0;

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    final v = widget.value;
    var moving = v == null;
    if (v == null) {
      _phase = (_phase + dt * 0.75) % 1.0;
    } else {
      final target = v.clamp(0.0, 1.0);
      moving = (target - _shown).abs() > 0.002;
      _shown += (target - _shown) * math.min(1.0, dt * 9);
    }
    // ilerleme durunca (ör. sabit seviye çubuğu) parçacıklar söner, tikleyici durur
    _settledFor = moving ? 0 : _settledFor + dt;
    if (_settledFor > 0.9 && _sparks.isEmpty) {
      _ticker.stop();
      if (mounted) setState(() {});
      return;
    }
    // parçacıklar: ucun etrafında doğup geriye ve yukarı/aşağı saçılır
    final active = v == null || (v > 0 && v < 1 && _settledFor < 0.6);
    if (active) {
      for (var i = 0; i < 2; i++) {
        _sparks.add(_Spark(0, 0, -(20 + _rnd.nextDouble() * 60), (_rnd.nextDouble() - 0.5) * 70, 0.35 + _rnd.nextDouble() * 0.35));
      }
    }
    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 60 * dt;
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    if (_sparks.length > 60) _sparks.removeRange(0, _sparks.length - 60);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.valueColor?.value ?? widget.color ?? JuzzioGlassTokens.glow;
    final track = widget.backgroundColor ?? color.withValues(alpha: 0.16);
    final v = widget.value;
    return Semantics(
      label: widget.semanticsLabel,
      value: v == null ? null : '${(v.clamp(0.0, 1.0) * 100).round()}%',
      child: SizedBox(
        height: widget.minHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklerPainter(
            value: v == null ? null : (_animate ? _shown : v.clamp(0.0, 1.0)),
            phase: _phase,
            color: color,
            track: track,
            sparks: _animate ? _sparks : const <_Spark>[],
          ),
        ),
      ),
    );
  }
}

class _SparklerPainter extends CustomPainter {
  _SparklerPainter({required this.value, required this.phase, required this.color, required this.track, required this.sparks});
  final double? value;
  final double phase;
  final Color color;
  final Color track;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final r = Radius.circular(h / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    double start;
    double end;
    final v = value;
    if (v == null) {
      final w = size.width * 0.32;
      end = (size.width + w) * phase;
      start = end - w;
    } else {
      start = 0;
      end = size.width * v;
    }
    start = start.clamp(0.0, size.width);
    end = end.clamp(0.0, size.width);
    if (end - start < 0.5) return;
    final fill = Rect.fromLTRB(start, 0, end, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, r),
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0.35), color]).createShader(fill),
    );
    final head = Offset(end, h / 2);
    canvas.drawCircle(head, h * 1.6, Paint()..color = color.withValues(alpha: 0.55)..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 1.6));
    canvas.drawCircle(head, h * 0.75, Paint()..color = Colors.white);
    for (final s in sparks) {
      final a = (s.life / 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(head + Offset(s.x, s.y), 0.6 + 1.1 * a, Paint()..color = Color.lerp(Colors.white, color, 1 - a)!.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(covariant _SparklerPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// #06 3 nokta zıplama — karşı taraf yazarken sohbet balonu
// -----------------------------------------------------------------------------
class JuzzioTypingBubble extends StatefulWidget {
  const JuzzioTypingBubble({super.key, this.label});
  final String? label;

  @override
  State<JuzzioTypingBubble> createState() => _JuzzioTypingBubbleState();
}

class _JuzzioTypingBubbleState extends State<JuzzioTypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

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
    final glow = JuzzioGlassTokens.glow;
    return Semantics(
      liveRegion: true,
      label: widget.label ?? JuzzioAppController.instance.trEn('Yazıyor', 'Typing', 'Schreibt'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JuzzioGlassTokens.spaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Builder(builder: (context) {
                  // her nokta 0,15 gecikmeyle; yumuşak zıplama (sinüs yayı)
                  final p = ((_c.value - i * 0.15) % 1.0 + 1.0) % 1.0;
                  final up = p < 0.5 ? math.sin(p * 2 * math.pi / 2 * 2) : 0.0;
                  final lift = math.max(0.0, up) * 6;
                  final a = 0.45 + 0.55 * math.max(0.0, up);
                  return Transform.translate(
                    offset: Offset(0, -lift),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: glow.withValues(alpha: a),
                        boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.5 * a), blurRadius: 6)],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
