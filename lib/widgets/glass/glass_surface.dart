// v0.8.1 — Şartname §8 GlassSurface: mevcut JuzzioGlass sistemini genişletir
// (ayrı ikinci bir cam sistemi oluşturmaz). Değerler JuzzioGlassTokens'tan gelir.
import 'package:flutter/material.dart';

import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final double opacity;
  final bool showShadow;
  final Color glowColor;
  final bool premiumBorder;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = JuzzioGlassTokens.blurNavigation,
    this.radius = JuzzioGlassTokens.radiusLarge,
    this.padding = const EdgeInsets.all(16),
    this.tint = JuzzioColors.surface,
    this.opacity = JuzzioGlassTokens.opacityStandard,
    this.showShadow = true,
    this.glowColor = JuzzioColors.cyan,
    this.premiumBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final o = opacity.clamp(0.0, 1.0).toDouble();
    return JuzzioGlass(
      radius: radius,
      blurSigma: blur,
      padding: padding,
      strongBorder: premiumBorder,
      color: tint.withValues(alpha: o),
      shadow: showShadow
          ? [
              BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 28, offset: const Offset(0, 10)),
              BoxShadow(color: glowColor.withValues(alpha: 0.07), blurRadius: 30, spreadRadius: -8),
            ]
          : null,
      child: child,
    );
  }
}
