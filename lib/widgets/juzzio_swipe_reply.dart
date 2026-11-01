// =============================================================================
// JUZZIO v0.7.0 — Yaylı "kaydır → yanıtla" (alıntı) hareketi
//  • Sağa sürüklerken artan direnç (lastik bant eğrisi): ne kadar çekersen o kadar zorlaşır.
//  • Eşik geçilince tek seferlik dokunsal geri bildirim ve yanıt simgesi "pop" eder.
//  • Bırakınca balon fizik tabanlı yay (SpringSimulation) ile kavisli şekilde yerine oturur.
//  • Sola kaydırma ayrı geri çağrı ile iletilir (mevcut eylem menüsü davranışı).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class JuzzioSwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReply;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRightSmall;
  final Color iconColor;
  final Color iconBackground;
  final bool enabled;

  const JuzzioSwipeToReply({
    super.key,
    required this.child,
    this.onReply,
    this.onSwipeLeft,
    this.onSwipeRightSmall,
    this.iconColor = Colors.white,
    this.iconBackground = const Color(0x33FFFFFF),
    this.enabled = true,
  });

  @override
  State<JuzzioSwipeToReply> createState() => _JuzzioSwipeToReplyState();
}

class _JuzzioSwipeToReplyState extends State<JuzzioSwipeToReply> with SingleTickerProviderStateMixin {
  static const double _maxPull = 96;
  static const double _threshold = 58;

  late final AnimationController _ctrl = AnimationController.unbounded(vsync: this);
  double _raw = 0;
  bool _armed = false;

  // Kritik sönümlemeye yakın, hafif kavisli (bir kez yaylanan) dönüş
  static const SpringDescription _spring = SpringDescription(mass: 1, stiffness: 420, damping: 24);

  double _resist(double dx) {
    if (dx <= 0) return 0;
    return _maxPull * (1 - math.exp(-dx / (_maxPull * 1.15)));
  }

  void _onStart(DragStartDetails d) {
    _ctrl.stop();
    _raw = _ctrl.value <= 0 ? 0 : _ctrl.value;
    _armed = false;
  }

  void _onUpdate(DragUpdateDetails d) {
    final delta = d.primaryDelta ?? 0;
    if (_raw <= 0 && delta < -6) {
      widget.onSwipeLeft?.call();
      return;
    }
    _raw = math.max(0, _raw + delta);
    final v = _resist(_raw);
    _ctrl.value = v;
    if (!_armed && v >= _threshold) {
      _armed = true;
      HapticFeedback.mediumImpact();
    } else if (_armed && v < _threshold - 8) {
      _armed = false;
      HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (_armed) widget.onReply?.call();
    if (!_armed && _ctrl.value > 8) widget.onSwipeRightSmall?.call();
    _armed = false;
    _raw = 0;
    final velocity = (d.primaryVelocity ?? 0) / 4;
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, 0, -velocity.abs()));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => _onEnd(DragEndDetails(primaryVelocity: 0)),
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          final v = _ctrl.value;
          final progress = (v / _threshold).clamp(0.0, 1.0);
          // Hafif kavis: sürükledikçe balon çok az döner ve yükselir
          final angle = -0.035 * progress;
          final lift = -3.0 * math.sin(progress * math.pi / 2);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 6,
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.55 + 0.45 * Curves.easeOutBack.transform(progress) + (_armed ? 0.08 : 0),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: widget.iconBackground, shape: BoxShape.circle),
                      child: Icon(Icons.reply_rounded, size: 19, color: widget.iconColor),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(v, lift),
                child: Transform.rotate(angle: angle, alignment: Alignment.centerLeft, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}
