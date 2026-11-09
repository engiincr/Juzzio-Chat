// =============================================================================
// JUZZIO v1.0.0 — "Juzzio Space" bileşen kiti (Figma tasarımı)
//
//  Derin tema gradyanı üzerinde buzlu cam yüzeyler, parlayan vurgu (temaya göre lime,
//  cyan, ametist …) ve yuvarlatılmış kare (squircle) dili. Tüm renkler
//  JuzzioGlassTokens / JuzzioSpaceSpec üzerinden gelir: 16 temanın hepsinde ve
//  aydınlık/karanlık modda aynı bileşen, sabit hex YOK.
//
//   JuzzioSpaceEyebrow · JuzzioSpaceBrand · JuzzioSpaceHeader
//   JuzzioSpaceIconButton · JuzzioSpaceComposeButton
//   JuzzioSpaceSearchBar (⌘K kısayol çipi)
//   JuzzioSpaceStoryAvatar (hikâye halkası, kesikli "durumum" halkası, çevrimiçi nokta)
//   JuzzioSpaceSectionHeader (INBOX / Messages / ⋯)
//   JuzzioSpaceFilterPill (sayaç rozetli)
//   JuzzioSpaceCard · JuzzioSpaceSquircleAvatar · JuzzioSpaceCountBadge
//   JuzzioSpaceBottomNav (yüzen cam alt menü)
//   JuzzioSpacePageHeader (alt sayfalar için geri + başlık)
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_media_url.dart';
import 'juzzio_motion.dart';

/// Ölçüler (Figma, 393 dp genişlik referansı)
class JuzzioSpaceMetrics {
  JuzzioSpaceMetrics._();
  static const double gutter = 20;
  static const double iconButton = 44;
  static const double iconRadius = 15;
  static const double searchHeight = 54;
  static const double searchRadius = 22;
  static const double storyAvatar = 62;
  static const double cardRadius = 26;
  static const double cardAvatar = 54;
  static const double cardAvatarRadius = 17;
  static const double pillHeight = 40;
  static const double navHeight = 76;
  static const double navRadius = 28;
}

bool get _dark => JuzzioAppController.instance.isDark;
bool get _calm => JuzzioAppController.instance.reduceMotion || JuzzioGlassTokens.reducedEffects;

/// Bulanık cam katmanı (performans modunda blur yerine düz yarı saydam dolgu)
class _Frost extends StatelessWidget {
  const _Frost({required this.radius, required this.child, this.sigma = 18});
  final BorderRadius radius;
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    if (_calm) return ClipRRect(borderRadius: radius, child: child);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Başlık
// ---------------------------------------------------------------------------

/// "YOUR SPACE" / "INBOX" gibi harf aralıklı küçük üst başlık
class JuzzioSpaceEyebrow extends StatelessWidget {
  const JuzzioSpaceEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: JuzzioConfig.fontRegularBold,
        color: JuzzioGlassTokens.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 3.0,
        height: 1.1,
      ),
    );
  }
}

/// "Juzzio." — vurgu renkli nokta ile marka yazısı
class JuzzioSpaceBrand extends StatelessWidget {
  const JuzzioSpaceBrand({super.key, this.text = 'Juzzio', this.size = 36, this.dot = true});
  final String text;
  final double size;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text),
        if (dot) TextSpan(text: '.', style: TextStyle(color: JuzzioGlassTokens.glowText)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: TextStyle(
        fontFamily: JuzzioConfig.fontRegularBold,
        color: JuzzioGlassTokens.heading,
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: -size * 0.045,
        height: 1.05,
      ),
    );
  }
}

/// Yuvarlatılmış kare cam ikon düğmesi; [dotColor] verilirse sağ üstte durum noktası
class JuzzioSpaceIconButton extends StatelessWidget {
  const JuzzioSpaceIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.dotColor,
    this.badgeCount = 0,
    this.size = JuzzioSpaceMetrics.iconButton,
    this.iconColor,
    this.iconWidget,
  });

  final IconData icon;

  /// v1.1.0: dönüşen ikon (JuzzioMorphIcon) gibi özel çizim; verilirse [icon] yerine çizilir
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? dotColor;
  final int badgeCount;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.34);
    final dot = badgeCount > 0 ? const Color(0xFFFF6B5E) : dotColor;
    Widget b = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: JuzzioGlassTokens.spaceButton,
        borderRadius: r,
        border: Border.all(color: JuzzioGlassTokens.spaceCardBorder, width: 1),
      ),
      child: Stack(
        children: [
          // v1.1.0 Symbol Effect: rozet sayısı değişince ikon zıplar
          Center(
            child: JuzzioBounceOnChange(
              value: badgeCount,
              child: iconWidget ?? Icon(icon, size: size * 0.46, color: iconColor ?? JuzzioGlassTokens.icon),
            ),
          ),
          if (dot != null)
            Positioned(
              top: size * 0.17,
              right: size * 0.2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle, boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.6), blurRadius: 6)]),
              ),
            ),
        ],
      ),
    );
    b = Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: b,
      ),
    );
    final label = badgeCount > 0 ? '${tooltip ?? ''} ($badgeCount)' : tooltip;
    return Semantics(button: true, label: label, child: label == null ? b : Tooltip(message: label, child: b));
  }
}

/// Parlayan vurgu dolgulu "yeni sohbet / oluştur" düğmesi
class JuzzioSpaceComposeButton extends StatelessWidget {
  const JuzzioSpaceComposeButton({super.key, required this.onTap, this.icon = Icons.edit_outlined, this.tooltip, this.size = JuzzioSpaceMetrics.iconButton});
  final VoidCallback? onTap;
  final IconData icon;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.34);
    final b = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: JuzzioGlassTokens.glow, borderRadius: r, boxShadow: JuzzioGlassTokens.glowShadow(0.9)),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Center(child: Icon(icon, size: size * 0.48, color: JuzzioGlassTokens.onGlow)),
        ),
      ),
    );
    return Semantics(button: true, label: tooltip, child: tooltip == null ? b : Tooltip(message: tooltip!, child: b));
  }
}

/// Üst başlık: eyebrow + büyük başlık solda, eylemler sağda
class JuzzioSpaceHeader extends StatelessWidget {
  const JuzzioSpaceHeader({super.key, required this.eyebrow, required this.title, this.actions = const [], this.onTitleTap, this.padding});
  final String eyebrow;
  final Widget title;
  final List<Widget> actions;
  final VoidCallback? onTitleTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(JuzzioSpaceMetrics.gutter, 14, JuzzioSpaceMetrics.gutter, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTitleTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [JuzzioSpaceEyebrow(eyebrow), const SizedBox(height: 6), title],
              ),
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
        ],
      ),
    );
  }
}

/// Alt sayfalar için başlık: geri düğmesi + eyebrow + başlık + eylemler
class JuzzioSpacePageHeader extends StatelessWidget {
  const JuzzioSpacePageHeader({super.key, required this.title, this.eyebrow, this.actions = const [], this.onBack});
  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (canPop || onBack != null) ...[
            JuzzioSpaceIconButton(
              icon: Icons.arrow_back_rounded,
              size: 42,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[JuzzioSpaceEyebrow(eyebrow!), const SizedBox(height: 3)],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioGlassTokens.heading,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[const SizedBox(width: 8), actions[i]],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Arama
// ---------------------------------------------------------------------------
class JuzzioSpaceSearchBar extends StatelessWidget {
  const JuzzioSpaceSearchBar({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.onShortcutTap,
    this.shortcutLabel = '⌘K',
    this.readOnly = false,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onShortcutTap;
  final String? shortcutLabel;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(JuzzioSpaceMetrics.searchRadius);
    return Container(
      height: JuzzioSpaceMetrics.searchHeight,
      decoration: BoxDecoration(
        color: JuzzioGlassTokens.spaceInset,
        borderRadius: r,
        border: Border.all(color: JuzzioGlassTokens.spaceCardBorder, width: 1),
      ),
      padding: const EdgeInsets.only(left: 16, right: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: JuzzioGlassTokens.textSecondary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTap: onTap,
              readOnly: readOnly,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
              cursorColor: JuzzioGlassTokens.glowText,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                hintText: hint,
                hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 16, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (shortcutLabel != null)
            Semantics(
              button: onShortcutTap != null,
              child: GestureDetector(
                onTap: onShortcutTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: JuzzioGlassTokens.spaceCard,
                    border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
                  ),
                  child: Text(
                    shortcutLabel!,
                    style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hikâyeler
// ---------------------------------------------------------------------------
enum JuzzioSpaceRing { none, story, seen, mine }

class JuzzioSpaceStoryAvatar extends StatelessWidget {
  const JuzzioSpaceStoryAvatar({
    super.key,
    required this.label,
    required this.avatar,
    this.ring = JuzzioSpaceRing.none,
    this.online = false,
    this.plus = false,
    this.onTap,
    this.onPlusTap,
    this.onLongPress,
    this.size = JuzzioSpaceMetrics.storyAvatar,
    this.badge,
  });

  final String label;

  /// Halka içindeki görsel (dairesel avatar)
  final Widget avatar;
  final JuzzioSpaceRing ring;
  final bool online;
  final bool plus;
  final VoidCallback? onTap;
  final VoidCallback? onPlusTap;
  final VoidCallback? onLongPress;
  final double size;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final ringW = 2.6;
    Widget core = Padding(padding: EdgeInsets.all(ringW + 3.5), child: ClipOval(child: avatar));
    core = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          ring: ring,
          color: ring == JuzzioSpaceRing.seen ? JuzzioGlassTokens.textMuted.withValues(alpha: 0.55) : glow.withValues(alpha: _dark ? 0.62 : 0.9),
          dashed: ring == JuzzioSpaceRing.mine,
          dashColor: JuzzioGlassTokens.textMuted.withValues(alpha: 0.75),
          width: ringW,
        ),
        child: core,
      ),
    );
    final dotBorder = JuzzioGlassTokens.space.depth[1];
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: size + 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  core,
                  if (online)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: glow,
                          shape: BoxShape.circle,
                          border: Border.all(color: _dark ? dotBorder : Colors.white, width: 2.4),
                          boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 8)],
                        ),
                      ),
                    ),
                  if (plus)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: GestureDetector(
                        onTap: onPlusTap ?? onTap,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: glow,
                            shape: BoxShape.circle,
                            border: Border.all(color: _dark ? dotBorder : Colors.white, width: 2.2),
                          ),
                          child: Icon(Icons.add_rounded, size: 15, color: JuzzioGlassTokens.onGlow),
                        ),
                      ),
                    ),
                  if (badge != null) Positioned(right: -2, bottom: -2, child: badge!),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.ring, required this.color, required this.dashed, required this.dashColor, required this.width});
  final JuzzioSpaceRing ring;
  final Color color;
  final bool dashed;
  final Color dashColor;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (ring == JuzzioSpaceRing.none) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - width / 2;
    if (dashed) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.8
        ..strokeCap = StrokeCap.round
        ..color = dashColor;
      const n = 26;
      const sweep = 2 * math.pi / n;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * sweep, sweep * 0.5, false, p);
      }
      return;
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.ring != ring || o.color != color || o.dashed != dashed;
}

// ---------------------------------------------------------------------------
// Bölüm başlığı ve filtreler
// ---------------------------------------------------------------------------
class JuzzioSpaceSectionHeader extends StatelessWidget {
  const JuzzioSpaceSectionHeader({super.key, required this.eyebrow, required this.title, this.onMore, this.moreTooltip, this.trailing, this.moreOpen = false});

  /// v1.1.0 (#10 Ring + X): menü açıkken çizgiler halka içinde × olur
  final bool moreOpen;
  final String eyebrow;
  final String title;
  final VoidCallback? onMore;
  final String? moreTooltip;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(JuzzioSpaceMetrics.gutter, 6, JuzzioSpaceMetrics.gutter, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JuzzioSpaceEyebrow(eyebrow),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioGlassTokens.heading,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (onMore != null)
            JuzzioSpaceIconButton(
              icon: Icons.more_horiz_rounded,
              size: 40,
              tooltip: moreTooltip,
              onTap: onMore,
              iconWidget: JuzzioMorphIcon(kind: JuzzioMorph.ringX, open: moreOpen, size: 20, color: JuzzioGlassTokens.icon),
            ),
        ],
      ),
    );
  }
}

class JuzzioSpaceFilterPill extends StatelessWidget {
  const JuzzioSpaceFilterPill({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.count = 0});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final fg = selected ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label ($count)' : label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: _calm ? 0 : 200),
          curve: Curves.easeOutCubic,
          height: JuzzioSpaceMetrics.pillHeight,
          padding: EdgeInsets.only(left: 18, right: count > 0 ? 8 : 18),
          decoration: BoxDecoration(
            color: selected ? Color.lerp(glow, Colors.white, _dark ? 0.32 : 0.0) : JuzzioGlassTokens.spaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Colors.transparent : JuzzioGlassTokens.spaceCardBorder),
            boxShadow: selected ? JuzzioGlassTokens.glowShadow(0.55) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
              Text(
                label,
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: fg, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (count > 0) ...[
                const SizedBox(width: 9),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? JuzzioGlassTokens.onGlow.withValues(alpha: 0.78) : glow,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: selected ? Color.lerp(glow, Colors.white, 0.35) : JuzzioGlassTokens.onGlow,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kart, avatar, rozet
// ---------------------------------------------------------------------------
class JuzzioSpaceCard extends StatelessWidget {
  const JuzzioSpaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 16, 14),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.radius = JuzzioSpaceMetrics.cardRadius,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.blur = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;
  final bool blur;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        color: color ?? (highlighted ? JuzzioGlassTokens.glow.withValues(alpha: 0.10) : JuzzioGlassTokens.spaceCard),
        border: Border.all(
          color: highlighted ? JuzzioGlassTokens.glow.withValues(alpha: 0.35) : JuzzioGlassTokens.spaceCardBorder,
          width: 1.2,
        ),
      ),
      // Sol üstten hafif cam ışığı (dolgu rengini EZMEMESİ için ayrı katmanda)
      foregroundDecoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: _dark ? 0.035 : 0.18), Colors.white.withValues(alpha: 0)],
        ),
      ),
      child: child,
    );
    if (onTap != null || onLongPress != null) {
      body = Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(borderRadius: r, onTap: onTap, onLongPress: onLongPress, child: body),
      );
    }
    if (blur) body = _Frost(radius: r, sigma: 16, child: body);
    return Padding(padding: margin, child: body);
  }
}

/// Yuvarlatılmış kare avatar; [online] parlayan nokta, [badgeIcon] sağ altta (ör. grup)
class JuzzioSpaceSquircleAvatar extends StatelessWidget {
  const JuzzioSpaceSquircleAvatar({
    super.key,
    required this.child,
    this.size = JuzzioSpaceMetrics.cardAvatar,
    this.online = false,
    this.badgeIcon,
  });

  final Widget child;
  final double size;
  final bool online;
  final IconData? badgeIcon;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final ring = _dark ? JuzzioGlassTokens.space.depth[1] : Colors.white;
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.32),
              border: Border.all(color: Colors.white.withValues(alpha: _dark ? 0.10 : 0.6), width: 1),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(size * 0.32), child: SizedBox(width: size, height: size, child: child)),
          ),
          if (online && badgeIcon == null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: glow,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2.4),
                  boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.5), blurRadius: 6)],
                ),
              ),
            ),
          if (badgeIcon != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: glow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ring, width: 2),
                ),
                child: Icon(badgeIcon, size: 14, color: JuzzioGlassTokens.onGlow),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kare kırpılmış profil fotoğrafı; yoksa temanın vurgu ailesinde baş harf zemini
class JuzzioSpacePhoto extends StatelessWidget {
  const JuzzioSpacePhoto({super.key, required this.url, required this.name, this.size = JuzzioSpaceMetrics.cardAvatar});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    final pair = juzzioAvatarGradient(name, JuzzioGlassTokens.accentPair, dark: _dark);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair)),
      child: Text(
        JuzzioGlassAvatar.initialOf(name),
        style: TextStyle(color: juzzioReadableOn(pair.first), fontWeight: FontWeight.w900, fontSize: size * 0.42),
      ),
    );
    if (!u.startsWith('http')) return fallback;
    return JuzzioStorageImage(
      u,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (ctx, child, progress) => progress == null ? child : fallback,
    );
  }
}

/// Parlayan okunmamış sayacı (daire; iki hane ve üstü hap)
class JuzzioSpaceCountBadge extends StatelessWidget {
  const JuzzioSpaceCountBadge({super.key, required this.count, this.muted = false, this.size = 24});
  final int count;
  final bool muted;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return SizedBox(width: size, height: size);
    final bg = muted ? JuzzioGlassTokens.textMuted.withValues(alpha: 0.45) : JuzzioGlassTokens.glow;
    final fg = muted ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.onGlow;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: _calm ? 0 : 320),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Container(
        key: ValueKey(count),
        constraints: BoxConstraints(minWidth: size),
        height: size,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: muted ? null : JuzzioGlassTokens.glowShadow(0.45),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(color: fg, fontSize: size * 0.5, fontWeight: FontWeight.w800, height: 1.0),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yüzen cam alt menü
// ---------------------------------------------------------------------------
class JuzzioSpaceNavItem {
  const JuzzioSpaceNavItem({required this.icon, required this.activeIcon, required this.label, this.badge = 0});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
}

class JuzzioSpaceBottomNav extends StatelessWidget {
  const JuzzioSpaceBottomNav({super.key, required this.items, required this.selected, required this.onTap});
  final List<JuzzioSpaceNavItem> items;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final r = BorderRadius.circular(JuzzioSpaceMetrics.navRadius);
    final glow = JuzzioGlassTokens.glow;
    final fill = _dark
        ? Color.alphaBlend(const Color(0x0AFFFFFF), JuzzioGlassTokens.space.depth[2]).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.82);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? bottom : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: r, boxShadow: JuzzioGlassTokens.shadow),
        child: _Frost(
          radius: r,
          sigma: 20,
          child: Container(
            height: JuzzioSpaceMetrics.navHeight,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: r,
              border: Border.all(color: JuzzioGlassTokens.spaceCardBorder, width: 1.2),
            ),
            child: Row(
              children: List.generate(items.length, (i) {
                final it = items[i];
                final active = i == selected;
                final fg = active ? JuzzioGlassTokens.glowText : JuzzioGlassTokens.textSecondary;
                Widget icon = Icon(active ? it.activeIcon : it.icon, color: fg, size: 25);
                if (it.badge > 0) {
                  icon = Stack(
                    clipBehavior: Clip.none,
                    children: [
                      icon,
                      Positioned(
                        top: -9,
                        right: -14,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 19),
                          height: 19,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: glow,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: fill.withValues(alpha: 1), width: 1.6),
                          ),
                          child: Text(
                            it.badge > 99 ? '99+' : '${it.badge}',
                            style: TextStyle(color: JuzzioGlassTokens.onGlow, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: active,
                    label: it.badge > 0 ? '${it.label} (${it.badge})' : it.label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onTap(i);
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: _calm ? 0 : 240),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: active ? glow.withValues(alpha: _dark ? 0.09 : 0.16) : Colors.transparent,
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            icon,
                            const SizedBox(height: 5),
                            Text(
                              it.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: fg,
                                fontSize: 11.5,
                                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Liste içindeki ince ayırıcı çizgi (başlık altı)
class JuzzioSpaceDivider extends StatelessWidget {
  const JuzzioSpaceDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 1, color: JuzzioGlassTokens.spaceCardBorder);
}
