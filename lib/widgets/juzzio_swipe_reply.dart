// =============================================================================
// JUZZIO v0.7.0 — Yaylı "kaydır → yanıtla" (alıntı) hareketi
//  • Sağa sürüklerken artan direnç (lastik bant eğrisi): ne kadar çekersen o kadar zorlaşır.
//  • Eşik geçilince tek seferlik dokunsal geri bildirim ve yanıt simgesi "pop" eder.
//  • Bırakınca balon fizik tabanlı yay (SpringSimulation) ile kavisli şekilde yerine oturur.
//  • v0.9.3: sola kaydırma da yaylı — balon dirençle sola kayar, arkadaki eylemler (sil,
//    sessize al) ölçeklenip belirir; bırakınca eşiği geçtiyse açık konuma, geçmediyse
//    yerine YAY fiziğiyle oturur. Açıkken balona dokununca kapanır.
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

  /// v0.9.3: sola kaydırınca ortaya çıkan eylemler (yoksa sola kaydırma yalnız [onSwipeLeft]).
  final Widget? trailing;
  final double trailingWidth;
  final bool open;
  final ValueChanged<bool>? onOpenChanged;

  const JuzzioSwipeToReply({
    super.key,
    required this.child,
    this.onReply,
    this.onSwipeLeft,
    this.onSwipeRightSmall,
    this.iconColor = Colors.white,
    this.iconBackground = const Color(0x33FFFFFF),
    this.enabled = true,
    this.trailing,
    this.trailingWidth = 96,
    this.open = false,
    this.onOpenChanged,
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

  static double resistLeft(double dx, double width) => juzzioSwipeResistLeft(dx, width);
  static bool shouldOpen(double value, double width, double velocity) => juzzioSwipeShouldOpen(value, width, velocity);

  bool get _hasTrailing => widget.trailing != null;

  void _settle(double target, double velocity) {
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  @override
  void didUpdateWidget(covariant JuzzioSwipeToReply old) {
    super.didUpdateWidget(old);
    // Dışarıdan kapatıldıysa (başka mesaj açıldı / eylem seçildi) yay ile yerine dön
    if (_hasTrailing && !widget.open && _ctrl.value < -1 && !_dragging) _settle(0, 0);
  }

  bool _dragging = false;

  void _onStart(DragStartDetails d) {
    _ctrl.stop();
    _dragging = true;
    _raw = _ctrl.value;
    if (_raw < 0 && !_hasTrailing) _raw = 0;
    _armed = false;
  }

  void _onUpdate(DragUpdateDetails d) {
    final delta = d.primaryDelta ?? 0;
    if (_hasTrailing && (_raw < 0 || (_raw <= 0 && delta < 0))) {
      // Sola: yaylı açılma
      _raw = math.min(0, _raw + delta);
      if (_raw > 0) _raw = 0;
      _ctrl.value = resistLeft(_raw, widget.trailingWidth);
      return;
    }
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
    _dragging = false;
    if (_hasTrailing && _ctrl.value < 0) {
      final vel = d.primaryVelocity ?? 0;
      final open = shouldOpen(_ctrl.value, widget.trailingWidth, vel);
      if (open) HapticFeedback.selectionClick();
      _settle(open ? -widget.trailingWidth : 0, vel / 1000);
      _raw = 0;
      widget.onOpenChanged?.call(open);
      return;
    }
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
          // Tek ağaç yapısı: sağa/sola geçişte balonun durumu (çeviri vb.) yeniden kurulmaz
          final progress = (v / _threshold).clamp(0.0, 1.0);
          final reveal = _hasTrailing ? (-v / widget.trailingWidth).clamp(0.0, 1.0) : 0.0;
          // Hafif kavis: sağa sürükledikçe balon çok az döner ve yükselir
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
              if (_hasTrailing)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: Curves.easeOut.transform(reveal),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * Curves.easeOutBack.transform(reveal),
                      alignment: Alignment.centerRight,
                      child: Center(child: IgnorePointer(ignoring: reveal < 0.6, child: widget.trailing)),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(v, v > 0 ? lift : 0),
                child: Transform.rotate(
                  angle: v > 0 ? angle : 0,
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    // Açıkken balona dokunmak kapatır
                    onTap: (widget.open && v < 0)
                        ? () {
                            _settle(0, 0);
                            widget.onOpenChanged?.call(false);
                          }
                        : null,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// v0.9.3: sola: eylem genişliğine kadar doğrusal, sonrası lastik direnç (saf, test edilebilir).
double juzzioSwipeResistLeft(double dx, double width) {
  if (dx >= 0) return 0;
  final pull = -dx;
  if (pull <= width) return -pull;
  final extra = pull - width;
  const over = 36.0;
  return -(width + over * (1 - math.exp(-extra / (over * 1.6))));
}

/// Bırakınca açık mı kalsın? (genişliğin %45'i ya da hızlı fırlatma)
bool juzzioSwipeShouldOpen(double value, double width, double velocity) => value < -width * 0.45 || velocity < -650;
