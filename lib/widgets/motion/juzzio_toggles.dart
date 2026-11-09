// =============================================================================
// JUZZIO v1.1.0 — Anahtarlar (referans: "10 toggle switches")
//  • gooey   (#07 Gooey + #06 Neon): genel ayarlar — topuz geçişte akışkan biçimde
//            uzar/basılır; açıkken karanlık temada neon parlama
//  • check   (#10 X → ✓): gizlilik, uçtan uca şifreleme, okundu bilgisi, izinler
//  • dayNight(#02 Day / Night): görünüm — güneş aya dönüşür, yıldızlar belirir
//  • power   (#09 Power Button): canlı çeviri, rahatsız etme, bağlantı
//  Sürükleme ve dokunma desteklenir; her değişimde seçim titreşimi.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import 'juzzio_motion_core.dart';

enum JuzzioToggleStyle { gooey, check, dayNight, power }

class JuzzioSwitch extends StatefulWidget {
  const JuzzioSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.style = JuzzioToggleStyle.gooey,
    this.activeColor,
    this.activeThumbColor,
    this.semanticLabel,
    this.icon,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final JuzzioToggleStyle style;
  final Color? activeColor;
  final Color? activeThumbColor;
  final String? semanticLabel;

  /// power stilinde güç simgesi yerine çizilecek ikon (ör. çeviri)
  final IconData? icon;

  @override
  State<JuzzioSwitch> createState() => _JuzzioSwitchState();
}

class _JuzzioSwitchState extends State<JuzzioSwitch> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: widget.value ? 1 : 0,
  );
  double _from = 0;
  double _to = 0;
  bool _dragging = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(covariant JuzzioSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dragging) _animateTo(widget.value ? 1 : 0);
  }

  void _animateTo(double target) {
    _from = _c.value;
    _to = target;
    if (JuzzioAppController.instance.reduceMotion) {
      _c.value = target;
    } else {
      _c.animateTo(target, curve: kJuzzioSpring);
    }
  }

  void _toggle() {
    if (!_enabled) return;
    JuzzioHaptics.toggle();
    widget.onChanged!(!widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Size get _size => switch (widget.style) {
        JuzzioToggleStyle.power => const Size(44, 44),
        JuzzioToggleStyle.dayNight => const Size(58, 32),
        _ => const Size(52, 30),
      };

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioAppController.instance.isDark;
    final size = _size;
    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onHorizontalDragStart: widget.style == JuzzioToggleStyle.power || !_enabled
            ? null
            : (_) {
                _dragging = true;
                _from = _c.value;
              },
        onHorizontalDragUpdate: widget.style == JuzzioToggleStyle.power || !_enabled
            ? null
            : (d) {
                _c.value = (_c.value + d.primaryDelta! / (size.width - size.height)).clamp(0.0, 1.0);
                _to = _c.value;
              },
        onHorizontalDragEnd: widget.style == JuzzioToggleStyle.power || !_enabled
            ? null
            : (_) {
                _dragging = false;
                final next = _c.value >= 0.5;
                if (next != widget.value) {
                  JuzzioHaptics.toggle();
                  widget.onChanged!(next);
                } else {
                  _animateTo(widget.value ? 1 : 0);
                }
              },
        child: Opacity(
          opacity: _enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final span = (_to - _from).abs();
                final f = span < 0.001 ? 1.0 : ((t - _from) / (_to - _from)).clamp(0.0, 1.0);
                final stretch = _dragging ? 0.35 : math.sin(math.pi * f);
                return CustomPaint(
                  size: size,
                  painter: _TogglePainter(
                    style: widget.style,
                    t: t,
                    stretch: stretch,
                    dark: dark,
                    active: widget.activeColor ?? JuzzioGlassTokens.glow,
                    thumbOn: widget.activeThumbColor ?? JuzzioGlassTokens.onGlow,
                    offTrack: JuzzioGlassTokens.textPrimary.withValues(alpha: dark ? 0.14 : 0.12),
                    offThumb: dark ? const Color(0xFFE9ECEF) : Colors.white,
                    muted: JuzzioGlassTokens.textMuted,
                    danger: Theme.of(context).colorScheme.error,
                    icon: widget.icon,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  _TogglePainter({
    required this.style,
    required this.t,
    required this.stretch,
    required this.dark,
    required this.active,
    required this.thumbOn,
    required this.offTrack,
    required this.offThumb,
    required this.muted,
    required this.danger,
    this.icon,
  });

  final JuzzioToggleStyle style;
  final double t;
  final double stretch;
  final bool dark;
  final Color active;
  final Color thumbOn;
  final Color offTrack;
  final Color offThumb;
  final Color muted;
  final Color danger;
  final IconData? icon;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case JuzzioToggleStyle.gooey:
        _gooey(canvas, size);
      case JuzzioToggleStyle.check:
        _check(canvas, size);
      case JuzzioToggleStyle.dayNight:
        _dayNight(canvas, size);
      case JuzzioToggleStyle.power:
        _power(canvas, size);
    }
  }

  RRect _track(Size s) => RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height / 2));

  void _neon(Canvas canvas, RRect r, Color c, double strength) {
    if (strength <= 0.01) return;
    canvas.drawRRect(
      r.inflate(1),
      Paint()
        ..color = c.withValues(alpha: (dark ? 0.55 : 0.28) * strength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * strength),
    );
  }

  void _gooey(Canvas canvas, Size s) {
    final r = _track(s);
    final track = Color.lerp(offTrack, active, t)!;
    _neon(canvas, r, active, t);
    canvas.drawRRect(r, Paint()..color = track);
    // ince parlak kenar (sıvı cam)
    canvas.drawRRect(
      r.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10 + 0.10 * t),
    );
    final pad = 3.0;
    final d = s.height - pad * 2;
    final travel = s.width - pad * 2 - d;
    final cx = pad + d / 2 + travel * t;
    // akışkan uzama: hareket yönünde uzar, dikeyde hafif basılır
    final w = d + 14 * stretch;
    final h = d - 3 * stretch;
    final dir = t >= 0.5 ? -1.0 : 1.0;
    final center = Offset(cx + dir * 3 * stretch, s.height / 2);
    final thumb = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: w, height: h), Radius.circular(h / 2));
    canvas.drawRRect(
      thumb.shift(const Offset(0, 1.2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawRRect(thumb, Paint()..color = Color.lerp(offThumb, thumbOn, t)!);
    // damla izi (gooey kopuş)
    if (stretch > 0.15) {
      final tail = Offset(center.dx + dir * (w / 2 + 2 + 3 * stretch), s.height / 2);
      canvas.drawCircle(tail, 2.6 * stretch, Paint()..color = Color.lerp(offThumb, thumbOn, t)!.withValues(alpha: 0.85));
    }
  }

  void _check(Canvas canvas, Size s) {
    final r = _track(s);
    final track = Color.lerp(danger.withValues(alpha: 0.85), active, t)!;
    _neon(canvas, r, Color.lerp(danger, active, t)!, 0.6);
    canvas.drawRRect(r, Paint()..color = track);
    final pad = 3.0;
    final d = s.height - pad * 2;
    final cx = pad + d / 2 + (s.width - pad * 2 - d) * t;
    final c = Offset(cx, s.height / 2);
    canvas.drawCircle(c.translate(0, 1.2), d / 2, Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawCircle(c, d / 2 + stretch * 1.5, Paint()..color = Colors.white);
    // X → ✓ biçim dönüşümü
    final k = d * 0.26;
    Offset lerp(Offset a, Offset b) => Offset.lerp(a, b, t)!;
    final a1 = lerp(Offset(-k, -k), Offset(-k * 1.05, 0.05 * k));
    final a2 = lerp(Offset(k, k), Offset(-k * 0.25, k * 0.85));
    final b1 = lerp(Offset(-k, k), Offset(-k * 0.25, k * 0.85));
    final b2 = lerp(Offset(k, -k), Offset(k * 1.15, -k * 0.85));
    final p = Paint()
      ..color = Color.lerp(danger, active.computeLuminance() > 0.6 ? Color.lerp(active, Colors.black, 0.45)! : active, t)!
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((1 - t) * 0.0 + stretch * 0.35);
    canvas.drawLine(a1, a2, p);
    canvas.drawLine(b1, b2, p);
    canvas.restore();
  }

  void _dayNight(Canvas canvas, Size s) {
    final r = _track(s);
    final sky = LinearGradient(colors: [
      Color.lerp(const Color(0xFF6EC3FF), const Color(0xFF1C2556), t)!,
      Color.lerp(const Color(0xFFA9DEFF), const Color(0xFF0B1030), t)!,
    ]).createShader(Offset.zero & s);
    _neon(canvas, r, Color.lerp(const Color(0xFFFFD54A), const Color(0xFF8EA2FF), t)!, 0.55);
    canvas.drawRRect(r, Paint()..shader = sky);
    canvas.save();
    canvas.clipRRect(r);
    // bulutlar (gündüz)
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85 * (1 - t));
    canvas.drawCircle(Offset(s.width * 0.70 + 6 * t, s.height * 0.62), 5, cloud);
    canvas.drawCircle(Offset(s.width * 0.80 + 6 * t, s.height * 0.58), 6.5, cloud);
    canvas.drawCircle(Offset(s.width * 0.90 + 6 * t, s.height * 0.66), 4.5, cloud);
    // yıldızlar (gece)
    final star = Paint()..color = Colors.white.withValues(alpha: t);
    for (final p in const [Offset(0.18, 0.30), Offset(0.32, 0.62), Offset(0.12, 0.70), Offset(0.42, 0.26), Offset(0.26, 0.45)]) {
      canvas.drawCircle(Offset(s.width * p.dx, s.height * p.dy), 0.9 + 0.5 * t, star);
    }
    canvas.restore();
    final pad = 3.0;
    final d = s.height - pad * 2;
    final cx = pad + d / 2 + (s.width - pad * 2 - d) * t;
    final c = Offset(cx, s.height / 2);
    final body = Color.lerp(const Color(0xFFFFD54A), const Color(0xFFE8ECF5), t)!;
    // güneş ışıması → ay hâlesi
    canvas.drawCircle(c, d / 2 + 3, Paint()..color = body.withValues(alpha: 0.28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(c, d / 2, Paint()..color = body);
    // ay kraterleri
    final crater = Paint()..color = const Color(0xFFB7BFD1).withValues(alpha: t);
    canvas.drawCircle(c.translate(-d * 0.16, -d * 0.12), d * 0.11, crater);
    canvas.drawCircle(c.translate(d * 0.14, d * 0.10), d * 0.08, crater);
    canvas.drawCircle(c.translate(d * 0.05, -d * 0.24), d * 0.05, crater);
  }

  void _power(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final rad = s.shortestSide / 2 - 2;
    final on = Color.lerp(muted, active, t)!;
    if (t > 0.01) {
      canvas.drawCircle(c, rad + 1, Paint()..color = active.withValues(alpha: (dark ? 0.55 : 0.30) * t)..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * t));
    }
    canvas.drawCircle(c, rad, Paint()..color = Color.lerp(JuzzioGlassTokens.spaceButton, active.withValues(alpha: 0.16), t)!);
    canvas.drawCircle(
      c,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = on,
    );
    if (icon != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon!.codePoint),
          style: TextStyle(fontSize: rad * 0.95, fontFamily: icon!.fontFamily, package: icon!.fontPackage, color: on),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = on;
    final ir = rad * 0.46;
    canvas.drawArc(Rect.fromCircle(center: c, radius: ir), -math.pi / 2 + 0.55, 2 * math.pi - 1.1, false, p);
    canvas.drawLine(c.translate(0, -ir - 2), c.translate(0, -ir * 0.15), p);
  }

  @override
  bool shouldRepaint(covariant _TogglePainter o) =>
      o.t != t || o.stretch != stretch || o.dark != dark || o.active != active || o.style != style || o.thumbOn != thumbOn || o.icon != icon;
}

/// SwitchListTile ile aynı kullanım; sağda Juzzio anahtarı.
class JuzzioSwitchListTile extends StatelessWidget {
  const JuzzioSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.activeColor,
    this.activeThumbColor,
    this.contentPadding,
    this.style = JuzzioToggleStyle.gooey,
    this.dense,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final Color? activeColor;
  final Color? activeThumbColor;
  final EdgeInsetsGeometry? contentPadding;
  final JuzzioToggleStyle style;
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        dense: dense,
        leading: secondary,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        trailing: JuzzioSwitch(
          value: value,
          onChanged: onChanged,
          style: style,
          // eski ayarlardaki sabit turuncu/mavi yerine etkin temanın parlayan rengi
          activeColor: activeColor == null ? null : JuzzioGlassTokens.glow,
          activeThumbColor: activeThumbColor == null ? null : JuzzioGlassTokens.onGlow,
        ),
        onTap: onChanged == null
            ? null
            : () {
                JuzzioHaptics.toggle();
                onChanged!(!value);
              },
      ),
    );
  }
}

/// Dairesel neon parlamalı güç düğmesi (canlı çeviri, rahatsız etme…) + etiket
class JuzzioPowerButton extends StatelessWidget {
  const JuzzioPowerButton({super.key, required this.value, required this.onChanged, this.label, this.icon});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final sw = JuzzioSwitch(value: value, onChanged: onChanged, style: JuzzioToggleStyle.power, icon: icon, semanticLabel: label);
    if (label == null) return sw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        sw,
        Text(label!,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: value ? JuzzioGlassTokens.glowText : JuzzioGlassTokens.textSecondary,
            )),
      ],
    );
  }
}
