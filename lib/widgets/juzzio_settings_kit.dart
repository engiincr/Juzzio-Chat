// =============================================================================
// GM-015 — Ayarlar tasarım kiti ("Juzzio Ayarlar" tuvali, GM-011 Ana çizim tahtası)
//  • Sola hizalı büyük başlık + cam geri / QR düğmeleri
//  • Güçlü cam profil kartı: tema vurgulu halkalı avatar, ad + onay, "@kullanıcı · Profili ve hesabı düzenle"
//  • "Ayarlarda ara" cam arama kutusu (satır başlığı ve açıklamasında arar)
//  • BÜYÜK HARF bölüm etiketleri, cam gruplar, ikon karoları (vurgu tonu zemin + vurgu ikon),
//    başlık / açıklama / değer / ok; vurgulu satırda dolgu karo (onGlow ikon)
//  Tüm renkler tema belirteçlerinden (KR-010): 18 tema + özel tema, gece/gündüz, yüksek kontrast.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';

/// Ayarlar satırı tanımı (arama ve çizim aynı veriden)
class JuzzioSettingsItem {
  const JuzzioSettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.primary = false,
    this.danger = false,
    this.showChevron = true,
    this.keywords = '',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool showChevron;
  final String keywords;
}

class JuzzioSettingsSection {
  const JuzzioSettingsSection(this.label, this.items);
  final String label;
  final List<JuzzioSettingsItem> items;
}

/// Türkçe büyük/küçük harf duyarsız normalleştirme (saf; test edilir)
String juzzioSettingsNorm(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .trim();

/// Bölüm etiketi büyük harf (Türkçede i → İ). Saf; test edilir.
String juzzioSettingsUpper(String s, {required bool turkish}) =>
    turkish ? s.replaceAll('i', 'İ').toUpperCase() : s.toUpperCase();

/// Aramaya uyan bölümler (boş bölümler atılır). Saf; test edilir.
List<JuzzioSettingsSection> juzzioFilterSettings(List<JuzzioSettingsSection> sections, String query) {
  final q = juzzioSettingsNorm(query);
  if (q.isEmpty) return sections;
  final out = <JuzzioSettingsSection>[];
  for (final s in sections) {
    final items = s.items
        .where((i) => juzzioSettingsNorm('${i.title} ${i.subtitle ?? ''} ${i.value ?? ''} ${i.keywords} ${s.label}').contains(q))
        .toList();
    if (items.isNotEmpty) out.add(JuzzioSettingsSection(s.label, items));
  }
  return out;
}

/// Sola hizalı başlık satırı
class JuzzioSettingsTitleBar extends StatelessWidget {
  const JuzzioSettingsTitleBar({super.key, required this.title, this.showBack = true, this.trailing});
  final String title;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
      child: Row(
        children: [
          if (showBack && nav.canPop()) ...[
            _GlassCircle(icon: Icons.arrow_back_ios_new_rounded, semantic: 'Geri', onTap: () => nav.maybePop()),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: JuzzioGlassTokens.heading,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.icon, required this.onTap, required this.semantic});
  final IconData icon;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: JuzzioLiquidGlass(
          shape: BoxShape.circle,
          blur: 14,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 18, color: JuzzioGlassTokens.heading),
          ),
        ),
      ),
    );
  }
}

/// Güçlü cam profil kartı
class JuzzioSettingsProfileCard extends StatelessWidget {
  const JuzzioSettingsProfileCard({
    super.key,
    required this.name,
    required this.handleLine,
    required this.avatar,
    this.verified,
    this.onTap,
  });

  final String name;
  final String handleLine;
  final Widget avatar;
  final Widget? verified;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final pair = JuzzioGlassTokens.accentPair;
    return Semantics(
      button: true,
      label: '$name, $handleLine',
      child: GestureDetector(
        onTap: onTap,
        child: JuzzioLiquidGlass(
          strong: true,
          radius: 26,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [glow, pair.length > 1 ? pair[1] : glow, glow]),
                ),
                child: ClipOval(child: avatar),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (verified != null) ...[const SizedBox(width: 6), verified!],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      handleLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Ayarlarda ara" cam kutusu
class JuzzioSettingsSearchField extends StatelessWidget {
  const JuzzioSettingsSearchField({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return JuzzioLiquidGlass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 46,
        child: Row(children: [
          Icon(Icons.search_rounded, size: 19, color: JuzzioGlassTokens.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 15),
              cursorColor: JuzzioGlassTokens.glowText,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 15),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(Icons.close_rounded, size: 18, color: JuzzioGlassTokens.textMuted),
            ),
        ]),
      ),
    );
  }
}

/// Bölüm: BÜYÜK HARF etiket + cam grup
class JuzzioSettingsSectionView extends StatelessWidget {
  const JuzzioSettingsSectionView({super.key, required this.section});
  final JuzzioSettingsSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
              child: Text(
                juzzioSettingsUpper(section.label, turkish: JuzzioAppController.instance.uiLang == 'tr'),
                style: TextStyle(
                  color: JuzzioGlassTokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          JuzzioLiquidGlass(
            radius: 24,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < section.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 63, color: JuzzioGlassTokens.border.withValues(alpha: 0.5)),
                  JuzzioSettingsRow(item: section.items[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek satır: ikon karosu · başlık/açıklama · değer · ok
class JuzzioSettingsRow extends StatelessWidget {
  const JuzzioSettingsRow({super.key, required this.item});
  final JuzzioSettingsItem item;

  @override
  Widget build(BuildContext context) {
    final glowText = JuzzioGlassTokens.glowText;
    final danger = item.danger;
    final dangerColor = JuzzioGlassTokens.isDarkResolver() ? const Color(0xFFFF7A82) : const Color(0xFFC62835);
    final tileBg = danger
        ? dangerColor.withValues(alpha: 0.12)
        : item.primary
            ? JuzzioGlassTokens.glow
            : glowText.withValues(alpha: JuzzioGlassTokens.isDarkResolver() ? 0.14 : 0.12);
    final tileFg = danger ? dangerColor : (item.primary ? JuzzioGlassTokens.onGlow : glowText);
    final titleColor = danger ? dangerColor : JuzzioGlassTokens.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                item.onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(item.icon, size: 19, color: tileFg),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if ((item.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if ((item.value ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      item.value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: glowText, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (item.showChevron && !danger) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 20, color: JuzzioGlassTokens.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
