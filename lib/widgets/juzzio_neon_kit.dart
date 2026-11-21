// =============================================================================
// JUZZIO 2.1 — Neon Lime bileşen kiti (tasarım dosyalarındaki ortak parçalar)
//  • JuzzioNeonCard       : koyu cam kart, ince kenar, isteğe bağlı limon parıltı
//  • JuzzioLimeButton     : limon dolgu / çerçeve / tehlike (kırmızı) düğme
//  • JuzzioNeonTabs       : "Gelen İstekler 12 | Gönderilen 4" türü hap sekmeler
//  • JuzzioNeonChips      : "Tümü · Cevapsız · Gelen · Giden" filtre çipleri
//  • JuzzioNeonGroup/Row  : ikonlu ayar satırları (başlık, açıklama, değer, ok, anahtar)
// Tüm renkler etkin temadan gelir (açık/koyu/özel tema uyumlu).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';

class JuzzioNeonCard extends StatelessWidget {
  const JuzzioNeonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 22,
    this.highlighted = false,
    this.onTap,
    this.opaque,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool highlighted;
  final VoidCallback? onTap;
  /// v2.1: opak zemin. Boşsa otomatik: iletişim kutusu / açılır pencere (PopupRoute) içindeyse opak.
  /// (Saydam kart diyalogda alttaki sayfanın yazılarıyla üst üste biniyordu.)
  final bool? opaque;

  /// Diyalog/alt sayfa gibi açılır pencereler için okunur, tamamen opak kart rengi
  static Color solidColor() {
    final dark = JuzzioGlassTokens.isDarkResolver();
    final sp = JuzzioGlassTokens.space;
    final base = dark ? sp.depth[sp.depth.length > 1 ? 1 : 0] : sp.depthLight.last;
    return Color.alphaBlend(JuzzioGlassTokens.spaceCard, base.withValues(alpha: 1));
  }

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final r = BorderRadius.circular(radius);
    final solid = opaque ?? (ModalRoute.of(context) is PopupRoute);
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: solid ? solidColor() : JuzzioGlassTokens.spaceCard,
        borderRadius: r,
        border: Border.all(
          color: highlighted ? glow.withValues(alpha: 0.75) : JuzzioGlassTokens.spaceCardBorder,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: glow.withValues(alpha: 0.22), blurRadius: 18, spreadRadius: -4)]
            : (solid ? [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 12))] : null),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return box;
  }
}

enum JuzzioLimeButtonStyle { filled, outline, danger, ghost }

class JuzzioLimeButton extends StatelessWidget {
  const JuzzioLimeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = JuzzioLimeButtonStyle.filled,
    this.expand = true,
    this.height = 50,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final JuzzioLimeButtonStyle style;
  final bool expand;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    const danger = Color(0xFFFF5A6A);
    final enabled = onPressed != null && !busy;
    late final Color bg;
    late final Color fg;
    late final Color border;
    switch (style) {
      case JuzzioLimeButtonStyle.filled:
        bg = glow;
        fg = JuzzioGlassTokens.onGlow;
        border = glow;
      case JuzzioLimeButtonStyle.outline:
        bg = glow.withValues(alpha: 0.06);
        fg = JuzzioGlassTokens.glowText;
        border = glow.withValues(alpha: 0.8);
      case JuzzioLimeButtonStyle.danger:
        bg = danger.withValues(alpha: 0.08);
        fg = danger;
        border = danger.withValues(alpha: 0.7);
      case JuzzioLimeButtonStyle.ghost:
        bg = JuzzioGlassTokens.spaceCard;
        fg = JuzzioGlassTokens.textPrimary;
        border = JuzzioGlassTokens.spaceCardBorder;
    }
    final r = BorderRadius.circular(height / 2);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: fg, fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: r,
          border: Border.all(color: border, width: 1.3),
          boxShadow: style == JuzzioLimeButtonStyle.filled && enabled
              ? [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  }
                : null,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: content),
          ),
        ),
      ),
    );
  }
}

class JuzzioNeonTab {
  const JuzzioNeonTab(this.label, {this.icon, this.count});
  final String label;
  final IconData? icon;
  final int? count;
}

/// İki-üç seçenekli hap sekme (seçili olan limon çerçeveli)
class JuzzioNeonTabs extends StatelessWidget {
  const JuzzioNeonTabs({super.key, required this.tabs, required this.selected, required this.onChanged});
  final List<JuzzioNeonTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: JuzzioGlassTokens.spaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                  decoration: BoxDecoration(
                    color: i == selected ? glow.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: i == selected ? glow.withValues(alpha: 0.85) : Colors.transparent, width: 1.3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (tabs[i].icon != null) ...[
                        Icon(tabs[i].icon, size: 17, color: i == selected ? JuzzioGlassTokens.glowText : JuzzioGlassTokens.textSecondary),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          tabs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == selected ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary,
                            fontSize: 13,
                            fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if ((tabs[i].count ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        JuzzioNeonCountBadge(count: tabs[i].count!, muted: i != selected),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class JuzzioNeonCountBadge extends StatelessWidget {
  const JuzzioNeonCountBadge({super.key, required this.count, this.muted = false});
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? JuzzioGlassTokens.surfaceStrong : glow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: muted ? JuzzioGlassTokens.textSecondary : JuzzioGlassTokens.onGlow,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Yatay kaydırılabilir filtre çipleri (seçili olan limon dolgulu)
class JuzzioNeonChips extends StatelessWidget {
  const JuzzioNeonChips({super.key, required this.labels, required this.selected, required this.onChanged, this.padding});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: Material(
                color: i == selected ? glow : JuzzioGlassTokens.spaceCard,
                shape: StadiumBorder(
                  side: BorderSide(color: i == selected ? glow : JuzzioGlassTokens.spaceCardBorder),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == selected ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bölüm başlığı (ör. "Genel", "Çeviri Ayarları")
class JuzzioNeonSectionLabel extends StatelessWidget {
  const JuzzioNeonSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Text(
        text,
        style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.1),
      ),
    );
  }
}

/// Satırları tek kartta toplar, aralarına ince çizgi koyar
class JuzzioNeonGroup extends StatelessWidget {
  const JuzzioNeonGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(height: 1, thickness: 1, indent: 52, color: JuzzioGlassTokens.spaceCardBorder));
      items.add(children[i]);
    }
    return JuzzioNeonCard(padding: EdgeInsets.zero, radius: 18, child: Column(children: items));
  }
}

/// İkonlu ayar satırı: ikon · başlık (+açıklama) · değer · ok / anahtar
class JuzzioNeonRow extends StatelessWidget {
  const JuzzioNeonRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.showChevron = true,
  });

  /// Anahtarlı satır kısayolu
  factory JuzzioNeonRow.toggle({
    Key? key,
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return JuzzioNeonRow(
      key: key,
      icon: icon,
      title: title,
      subtitle: subtitle,
      showChevron: false,
      onTap: onChanged == null ? null : () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF5A6A);
    final fg = danger ? red : JuzzioGlassTokens.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: danger ? red : JuzzioGlassTokens.textPrimary.withValues(alpha: 0.9)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5, height: 1.3)),
                  ],
                ],
              ),
            ),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (trailing == null && showChevron && onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textSecondary, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sosyal giriş düğmesi (Google · Apple · GitHub) — yuvarlak cam düğme
class JuzzioOAuthButton extends StatelessWidget {
  const JuzzioOAuthButton({super.key, required this.provider, required this.onTap});
  final String provider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (provider) {
      'google' => const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
      'apple' => Icon(Icons.apple, size: 26, color: JuzzioGlassTokens.textPrimary),
      _ => Icon(Icons.code_rounded, size: 24, color: JuzzioGlassTokens.textPrimary),
    };
    final label = switch (provider) { 'google' => 'Google', 'apple' => 'Apple', _ => 'GitHub' };
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: JuzzioGlassTokens.spaceCard,
        shape: CircleBorder(side: BorderSide(color: JuzzioGlassTokens.spaceCardBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Center(child: mark)),
        ),
      ),
    );
  }
}

/// v2.1 — Ayar alt sayfalarının üst çubuğu için yuvarlak neon geri düğmesi (tasarımdaki gibi).
/// Geri gidilemeyen sayfada hiçbir şey çizmez.
class JuzzioNeonBackButton extends StatelessWidget {
  const JuzzioNeonBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    if (!nav.canPop()) return const SizedBox.shrink();
    return Center(
      child: Material(
        color: JuzzioGlassTokens.spaceCard,
        shape: CircleBorder(side: BorderSide(color: JuzzioGlassTokens.spaceCardBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => nav.maybePop(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: JuzzioGlassTokens.heading),
          ),
        ),
      ),
    );
  }
}
