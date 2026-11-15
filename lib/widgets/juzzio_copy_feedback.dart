// =============================================================================
// JUZZIO v1.2.9 — "Panoya kopyalandı" animasyonları (Copy to Clipboard videosundan)
//  • juzzioCopy()      : panoya yazar, hafif titreşim ve "Pill Stretch" bildirimi — küçük
//                        bir daire ekranın altında "✓ Kopyalandı" hapına uzar, sonra geri büzülür.
//  • JuzzioCopyButton  : "Outline Echo" — simge kopyala → onay işaretine döner, çevresinde iki
//                        halka dalga gibi dışa yayılır; 1,6 sn sonra eski hâline döner.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';

const Color _kMint = Color(0xFF34D399);

/// Panoya kopyalar ve "Pill Stretch" bildirimini gösterir.
Future<void> juzzioCopy(BuildContext context, String text, {String? label}) async {
  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.lightImpact();
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final app = JuzzioAppController.instance;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CopyPill(
      text: label ?? app.trEn('Kopyalandı', 'Copied', 'Kopiert'),
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _CopyPill extends StatefulWidget {
  const _CopyPill({required this.text, required this.onDone});
  final String text;
  final VoidCallback onDone;

  @override
  State<_CopyPill> createState() => _CopyPillState();
}

class _CopyPillState extends State<_CopyPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 96;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value;
              // 0–0,22 uzama · 0,22–0,8 bekleme · 0,8–1 büzülüp kaybolma
              final grow = Curves.easeOutBack.transform((t / 0.22).clamp(0, 1));
              final shrink = Curves.easeIn.transform(((t - 0.8) / 0.2).clamp(0, 1));
              final w = 44 + 150 * grow * (1 - shrink);
              final opacity = (1 - shrink).clamp(0.0, 1.0);
              final textOpacity = ((grow - 0.6) / 0.4).clamp(0.0, 1.0) * (1 - shrink);
              return Opacity(
                opacity: opacity,
                child: Container(
                  width: w,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kMint,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: _kMint.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 6))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.check_rounded, color: Color(0xFF052E1C), size: 20),
                    if (textOpacity > 0.01) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Opacity(
                          opacity: textOpacity,
                          child: Text(widget.text,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: const TextStyle(color: Color(0xFF052E1C), fontWeight: FontWeight.w900, fontSize: 14, decoration: TextDecoration.none)),
                        ),
                      ),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "Outline Echo" kopyala düğmesi
class JuzzioCopyButton extends StatefulWidget {
  const JuzzioCopyButton({super.key, required this.text, this.color, this.size = 22, this.label});
  final String text;
  final Color? color;
  final double size;
  final String? label;

  @override
  State<JuzzioCopyButton> createState() => _JuzzioCopyButtonState();
}

class _JuzzioCopyButtonState extends State<JuzzioCopyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _echo = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    _echo.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    await juzzioCopy(context, widget.text, label: widget.label);
    if (!mounted) return;
    setState(() => _copied = true);
    _echo.forward(from: 0);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? (JuzzioAppController.instance.isDark ? Colors.white : Colors.black87);
    final box = widget.size * 1.9;
    return Semantics(
      button: true,
      label: JuzzioAppController.instance.trEn('Kopyala', 'Copy', 'Kopieren'),
      child: GestureDetector(
        onTap: _go,
        child: SizedBox(
          width: box,
          height: box,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _echo,
              builder: (_, __) => Stack(alignment: Alignment.center, children: [
                for (final delay in const [0.0, 0.25])
                  if (_echo.isAnimating)
                    Builder(builder: (_) {
                      final v = ((_echo.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                      return Container(
                        width: box * (0.6 + 0.6 * v),
                        height: box * (0.6 + 0.6 * v),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _kMint.withValues(alpha: (1 - v) * 0.8), width: 1.6),
                        ),
                      );
                    }),
              ]),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: RotationTransition(turns: Tween(begin: 0.75, end: 1.0).animate(a), child: w)),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                key: ValueKey(_copied),
                size: widget.size,
                color: _copied ? _kMint : c,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
