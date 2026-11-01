// v0.8.1 — Şartname §10 GlassButton (ink efekti cam yüzeyin dışında, ClipRRect ile sınırlı)
import 'package:flutter/material.dart';

import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';
import 'glass_surface.dart';

class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  const GlassButton({super.key, required this.label, required this.onPressed, this.icon, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null;
    final fg = JuzzioGlassTokens.textPrimary;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      child: Opacity(
        opacity: active ? 1 : 0.42,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              GlassSurface(
                blur: JuzzioGlassTokens.blurSmall,
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                tint: primary ? JuzzioColors.cyan : JuzzioColors.surface,
                opacity: primary ? 0.28 : JuzzioGlassTokens.opacityStandard,
                premiumBorder: primary,
                glowColor: primary ? JuzzioColors.cyan : JuzzioColors.blue,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[Icon(icon, color: fg, size: 18), const SizedBox(width: 8)],
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
