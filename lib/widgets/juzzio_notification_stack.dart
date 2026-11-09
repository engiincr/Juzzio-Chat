// =============================================================================
// JUZZIO v0.9.7 — Uygulama içi bildirim yığını (Stacked Notifications)
//  Uygulama açıkken gelen bildirimler ekranın üstünde cam kartlar olarak üst üste
//  kayarak gelir: en yeni kart önde; arkadakiler hafifçe küçülür, aşağı kayar ve
//  solar (en fazla 3 kart görünür). Kart yukarı kaydırılınca kapanır, dokununca
//  ilgili sohbet/gönderi açılır, 5 sn sonra kendiliğinden kaybolur.
//  Sistem bildirim çekmecesinde ise bildirimler Android grubunda yığılır (MainActivity).
// =============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

class JuzzioStackItem {
  JuzzioStackItem({required this.title, required this.body, this.icon = Icons.chat_bubble_rounded, this.onTap})
      : id = DateTime.now().microsecondsSinceEpoch,
        createdAt = DateTime.now();
  final int id;
  final String title;
  final String body;
  final IconData icon;
  final VoidCallback? onTap;
  final DateTime createdAt;
}

/// Görünür kartların yığın dönüşümü (saf fonksiyon, testlerde doğrulanır):
/// derinlik 0 = en öndeki kart.
({double scale, double dy, double opacity}) juzzioStackTransform(int depth) {
  final d = depth.clamp(0, 3);
  return (scale: 1 - 0.06 * d, dy: 10.0 * d, opacity: d == 0 ? 1.0 : (d == 1 ? 0.72 : (d == 2 ? 0.42 : 0.0)));
}

class JuzzioNotificationStack {
  JuzzioNotificationStack._();
  static final JuzzioNotificationStack instance = JuzzioNotificationStack._();

  static const int maxVisible = 3;
  static const Duration lifetime = Duration(seconds: 5);

  final ValueNotifier<List<JuzzioStackItem>> items = ValueNotifier(const []);
  OverlayEntry? _entry;
  final Map<int, Timer> _timers = {};

  void show(BuildContext context, JuzzioStackItem item) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _StackHost(stack: this));
      overlay.insert(_entry!);
    }
    final next = [item, ...items.value];
    // Görünür sınırın dışında kalanlar yığından düşer
    for (final old in next.skip(maxVisible + 1)) {
      _timers.remove(old.id)?.cancel();
    }
    items.value = next.take(maxVisible + 1).toList();
    _timers[item.id] = Timer(lifetime, () => dismiss(item.id));
    HapticFeedback.selectionClick();
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    items.value = items.value.where((e) => e.id != id).toList();
    if (items.value.isEmpty) {
      // Çıkış animasyonu bittikten sonra katman kaldırılır
      Timer(const Duration(milliseconds: 420), () {
        if (items.value.isEmpty) {
          _entry?.remove();
          _entry = null;
        }
      });
    }
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    items.value = const [];
  }
}

class _StackHost extends StatelessWidget {
  const _StackHost({required this.stack});
  final JuzzioNotificationStack stack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return ValueListenableBuilder<List<JuzzioStackItem>>(
      valueListenable: stack.items,
      builder: (context, list, _) {
        final visible = list.take(JuzzioNotificationStack.maxVisible).toList();
        return Positioned(
          top: top,
          left: 12,
          right: 12,
          child: SizedBox(
            height: 112,
            child: Stack(clipBehavior: Clip.none, children: [
              // Arkadakiler önce çizilir (en öndeki en üstte)
              for (var i = visible.length - 1; i >= 0; i--)
                _StackCard(key: ValueKey(visible[i].id), item: visible[i], depth: i, onDismiss: () => stack.dismiss(visible[i].id)),
            ]),
          ),
        );
      },
    );
  }
}

class _StackCard extends StatefulWidget {
  const _StackCard({super.key, required this.item, required this.depth, required this.onDismiss});
  final JuzzioStackItem item;
  final int depth;
  final VoidCallback onDismiss;

  @override
  State<_StackCard> createState() => _StackCardState();
}

class _StackCardState extends State<_StackCard> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 460))..forward();
  double _drag = 0;

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = JuzzioAppController.instance.reduceMotion;
    final tf = juzzioStackTransform(widget.depth);
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: enter,
      builder: (context, child) {
        final slide = reduce ? 0.0 : (1 - enter.value) * -90;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, tf.dy + slide + _drag, 0)..multiply(Matrix4.diagonal3Values(tf.scale, tf.scale, 1)),
          transformAlignment: Alignment.topCenter,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: (tf.opacity * (reduce ? 1 : enter.value.clamp(0.0, 1.0))).clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: IgnorePointer(
        ignoring: widget.depth > 0,
        child: GestureDetector(
          onTap: () {
            widget.onDismiss();
            widget.item.onTap?.call();
          },
          onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-140.0, 24.0)),
          onVerticalDragEnd: (d) {
            if (_drag < -36 || (d.primaryVelocity ?? 0) < -500) {
              widget.onDismiss();
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: JuzzioGlass(
                  radius: 24,
                  blur: false,
                  color: JuzzioGlassTokens.sheet,
                  strongBorder: true,
                  shadow: JuzzioGlassTokens.shadow,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: JuzzioGlassTokens.accentPair),
                      ),
                      child: Icon(widget.item.icon, color: juzzioReadableOn(JuzzioGlassTokens.accentPair.first), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(widget.item.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13, height: 1.25)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
