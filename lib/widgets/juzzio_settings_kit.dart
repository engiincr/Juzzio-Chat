// =============================================================================
// v2.2.0 — Ayarlar, Engin'in gönderdiği referans görselle birebir:
//  • Sol üstte ince çerçeveli yuvarlak geri düğmesi + büyük "Ayarlar", sağda QR simgesi
//  • Başlığın altında üst köşeleri çok yuvarlak TEK büyük cam panel; bölümler bunun içinde
//  • Harf aralıklı BÜYÜK HARF bölüm etiketleri (SOHBETLER VE BİLDİRİMLER, GÖRÜNÜM VE DİL…)
//  • Satırlar kartsız: yuvarlak ikon dairesi · kalın başlık · altında açıklama/değer · sağda ok
//  • Arkada hava katmanı (bulut/güneş/yağmur/ay) — sayfa JuzzioAuroraPage ile gelir
// Önceki GM-015 kiti ("Juzzio Ayarlar" tuvali, GM-011 Ana çizim tahtası)
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

/// Başlık satırı (referans: ince çerçeveli geri dairesi + büyük başlık + sağda sade QR simgesi)
class JuzzioSettingsTitleBar extends StatelessWidget {
  const JuzzioSettingsTitleBar({super.key, required this.title, this.showBack = true, this.trailing});
  final String title;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 18),
      child: Row(
        children: [
          if (showBack && nav.canPop()) ...[
            _OutlineCircle(icon: Icons.chevron_left_rounded, semantic: 'Geri', onTap: () => nav.maybePop()),
            const SizedBox(width: 16),
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
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
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

/// Sağ üstteki sade simge düğmesi (referanstaki QR)
class JuzzioSettingsPlainIconButton extends StatelessWidget {
  const JuzzioSettingsPlainIconButton({super.key, required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          radius: 26,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 30, color: JuzzioGlassTokens.heading),
          ),
        ),
      ),
    );
  }
}

class _OutlineCircle extends StatelessWidget {
  const _OutlineCircle({required this.icon, required this.onTap, required this.semantic});
  final IconData icon;
  final VoidCallback onTap;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: InkResponse(
        radius: 28,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: JuzzioGlassTokens.textSecondary.withValues(alpha: 0.55), width: 1.4),
          ),
          child: Icon(icon, size: 30, color: JuzzioGlassTokens.heading),
        ),
      ),
    );
  }
}

/// Başlığın altındaki TEK büyük cam panel (üst köşeler çok yuvarlak, alta kadar uzanır)
class JuzzioSettingsPanel extends StatelessWidget {
  const JuzzioSettingsPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioGlassTokens.isDarkResolver();
    return JuzzioLiquidGlass(
      radius: 44,
      blur: 18,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: JuzzioGlassTokens.textPrimary.withValues(alpha: dark ? 0.035 : 0.02),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(44)),
        ),
        child: child,
      ),
    );
  }
}

/// Profil satırı (panelin en üstü): yuvarlak avatar · ad + onay · "@kullanıcı · …" · ok
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
    return Semantics(
      button: true,
      label: '$name, $handleLine',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: glow, width: 2)),
                  child: ClipOval(child: avatar),
                ),
                const SizedBox(width: 16),
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
                            style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (verified != null) ...[const SizedBox(width: 6), verified!],
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        handleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textMuted, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ayarlarda ara" kutusu (panelin içinde, sade)
class JuzzioSettingsSearchField extends StatelessWidget {
  const JuzzioSettingsSearchField({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioGlassTokens.isDarkResolver();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: JuzzioGlassTokens.textPrimary.withValues(alpha: dark ? 0.06 : 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JuzzioGlassTokens.border.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          Icon(Icons.search_rounded, size: 20, color: JuzzioGlassTokens.textSecondary),
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
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
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

/// Bölüm: harf aralıklı BÜYÜK HARF etiket + kartsız satırlar
class JuzzioSettingsSectionView extends StatelessWidget {
  const JuzzioSettingsSectionView({super.key, required this.section});
  final JuzzioSettingsSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 10, 22, 4),
              child: Text(
                juzzioSettingsUpper(section.label, turkish: JuzzioAppController.instance.uiLang == 'tr'),
                style: TextStyle(
                  color: JuzzioGlassTokens.textSecondary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          for (final it in section.items) JuzzioSettingsRow(item: it),
        ],
      ),
    );
  }
}

/// Tek satır (referans): yuvarlak ikon dairesi · kalın başlık · açıklama ya da değer · ok
class JuzzioSettingsRow extends StatelessWidget {
  const JuzzioSettingsRow({super.key, required this.item});
  final JuzzioSettingsItem item;

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioGlassTokens.isDarkResolver();
    final danger = item.danger;
    final dangerColor = dark ? const Color(0xFFFF7A82) : const Color(0xFFC62835);
    final circleBg = danger
        ? dangerColor.withValues(alpha: 0.14)
        : item.primary
            ? JuzzioGlassTokens.glow
            : JuzzioGlassTokens.textPrimary.withValues(alpha: dark ? 0.08 : 0.06);
    final iconColor = danger ? dangerColor : (item.primary ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.heading);
    final titleColor = danger ? dangerColor : JuzzioGlassTokens.heading;
    // değer (ör. "Türkçe") açıklama satırında gösterilir — referanstaki "Dil / Türkçe"
    final sub = [
      if ((item.subtitle ?? '').isNotEmpty) item.subtitle!,
      if ((item.subtitle ?? '').isEmpty && (item.value ?? '').isNotEmpty) item.value!,
    ].join();
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
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
                  child: Icon(item.icon, size: 24, color: iconColor),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: titleColor, fontSize: 18.5, fontWeight: FontWeight.w800),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                      ],
                    ],
                  ),
                ),
                if ((item.subtitle ?? '').isNotEmpty && (item.value ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      item.value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: JuzzioGlassTokens.glowText, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (item.showChevron && !danger) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, size: 26, color: JuzzioGlassTokens.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
