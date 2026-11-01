// =============================================================================
// JUZZIO v0.8.1 — 3D Frosted Glassmorphism bileşenleri (apply.txt mimarisi)
// Tüm renkler JuzzioGlassTokens ve seçili aurora temasından gelir; tema/mod
// değişince otomatik uyum sağlar. Liste öğelerinde enableBlur:false kullanın.
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/juzzio_glass.dart';

/// 3D buzlu cam kap: blur + %20→%4 beyaz dolgu + speküler/yanardöner kenar + gölge
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool enableBlur;
  final bool iridescentBorder;
  final Color? tintColor;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding,
    this.margin,
    this.enableBlur = true,
    this.iridescentBorder = false,
    this.tintColor,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget w = JuzzioGlass(
      radius: borderRadius,
      blur: enableBlur,
      padding: padding,
      strongBorder: iridescentBorder,
      color: tintColor == null
          ? null
          : Color.alphaBlend(tintColor!.withValues(alpha: 0.16), JuzzioGlassTokens.surface),
      shadow: enableBlur ? JuzzioGlassTokens.shadow : null,
      child: child,
    );
    if (width != null || height != null) w = SizedBox(width: width, height: height, child: w);
    if (onTap != null) {
      w = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(borderRadius: BorderRadius.circular(borderRadius), onTap: onTap, child: w),
      );
    }
    if (margin != null) w = Padding(padding: margin!, child: w);
    return w;
  }
}

/// Görsellerdeki "UI Background" hap etiketi / filtre çipi
class GlassPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? accent;

  const GlassPill({super.key, required this.label, this.icon, this.selected = false, this.onTap, this.accent});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? Color.alphaBlend((accent ?? Colors.white).withValues(alpha: 0.14), JuzzioGlassTokens.surfaceStrong)
              : JuzzioGlassTokens.surface,
          border: Border.all(
            color: selected ? JuzzioGlassTokens.borderStrong : JuzzioGlassTokens.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
          Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Buzlu cam metin kutusu (arama, form, sohbet)
class GlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final int? maxLines;

  const GlassTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return JuzzioGlass(
      radius: 999,
      blur: false,
      color: JuzzioGlassTokens.surface,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 14.5),
        cursorColor: JuzzioGlassTokens.textPrimary,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 14),
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, color: JuzzioGlassTokens.textSecondary, size: 20),
          suffixIcon: suffix,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

/// Cam diyalog (başlık + mesaj + eylemler)
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const [],
  IconData? icon,
}) =>
    showJuzzioGlassDialog<T>(context: context, title: title, message: message, content: content, actions: actions, icon: icon);

/// Cam alt çekmece
Future<T?> showGlassBottomSheet<T>({required BuildContext context, required WidgetBuilder builder}) =>
    showJuzzioGlassSheet<T>(context: context, builder: builder);

/// Üstten inen cam bildirim kapsülü
void showGlassToast(BuildContext context, String message, {IconData icon = Icons.info_outline_rounded}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _GlassToast(message: message, icon: icon, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _GlassToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final VoidCallback onDone;
  const _GlassToast({required this.message, required this.icon, required this.onDone});

  @override
  State<_GlassToast> createState() => _GlassToastState();
}

class _GlassToastState extends State<_GlassToast> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 10;
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(anim),
        child: FadeTransition(
          opacity: anim,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: JuzzioGlass(
                  radius: 22,
                  blur: false,
                  color: JuzzioGlassTokens.sheet,
                  strongBorder: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(widget.icon, color: JuzzioGlassTokens.textPrimary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.message,
                          style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
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
