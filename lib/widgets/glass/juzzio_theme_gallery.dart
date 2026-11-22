// v0.8.4 — Ayarlar › Görünüm: tüm uygulama ve sohbet temaları tek galeride.
// 12 Liquid Glass ailesi hem uygulama arayüzü hem sohbet teması olarak
// seçilebilir; 16 klasik sohbet ön ayarı da aynı yerde listelenir.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/theme/juzzio_aurora.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../screens/theme_preview_page.dart';

String _gl(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

/// Tema karakter açıklaması, arayüz diline göre (tr/en yerleşik, diğerleri dil paketinden).
String juzzioCharacterText(JuzzioAuroraPalette pal) {
  final c = pal.character;
  return JuzzioAppController.instance.translateUiDynamic(c.tr, enText: c.en, deText: c.de);
}

class _GalleryCard extends StatelessWidget {
  final JuzzioAuroraPalette palette;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool chatMock;
  const _GalleryCard({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.chatMock = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final dark = app.isDark;
    final ink = dark ? Colors.white : const Color(0xFF111827);
    final c = palette.character;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 132,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? (c.rim ?? palette.swatchA) : Colors.white.withValues(alpha: 0.18),
              width: selected ? 2.2 : 1,
            ),
            boxShadow: [
              if (selected) BoxShadow(color: (c.rim ?? palette.swatchA).withValues(alpha: 0.45), blurRadius: 16),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: Stack(
              fit: StackFit.expand,
              children: [
                JuzzioAuroraBackground(palette: palette, dark: dark),
                if (chatMock)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _bubble(Color.alphaBlend(palette.swatchB.withValues(alpha: 0.16),
                              dark ? const Color(0x8C1B1D24) : const Color(0xB3FFFFFF)), 58),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _bubble(Color.alphaBlend(palette.swatchA.withValues(alpha: 0.6), const Color(0x8C2C2C2E)), 70),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: JuzzioThemeSwatch(palette: palette, size: 22, selected: selected),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: JuzzioGlass(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: ink, fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: ink.withValues(alpha: 0.78), fontSize: 10.5, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(Color color, double width) => Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      );
}

JuzzioAuroraPalette _presetPalette(JuzzioChatThemePreset preset) {
  final a = preset.primaryColor;
  final b = preset.secondaryColor;
  final orbs = [
    JuzzioAuroraOrb(const Alignment(-0.8, -0.7), 0.9, a.withValues(alpha: 0.55)),
    JuzzioAuroraOrb(const Alignment(0.9, 0.2), 0.8, b.withValues(alpha: 0.5)),
    JuzzioAuroraOrb(const Alignment(-0.3, 0.95), 0.7, preset.incomingDarkColor.withValues(alpha: 0.5)),
  ];
  return JuzzioAuroraPalette(
    id: 'chat_${preset.id}',
    nameTr: preset.nameTr,
    nameEn: preset.nameEn,
    nameDe: preset.nameEn,
    base: const Color(0xFF0B0D12),
    baseLight: const Color(0xFFF3F4F8),
    orbs: orbs,
    orbsLight: [for (final o in orbs) JuzzioAuroraOrb(o.center, o.radius, o.color.withValues(alpha: o.color.a * 0.6))],
    swatchA: a,
    swatchB: b,
  );
}

/// Uygulama arayüz teması: 12 Liquid Glass ailesi. Dokun → önizleme ("Uygula").
class JuzzioAppThemeGallery extends StatelessWidget {
  final bool previewFirst;
  const JuzzioAppThemeGallery({super.key, this.previewFirst = true});

  @override
  Widget build(BuildContext context) {
    // GM-014: sayfada `const` kullanıldığı için tema/gece-gündüz değişince yeniden çizilmiyordu
    // (koyu modda açık önizlemeler, eski seçim işareti). Artık denetleyiciyi dinler.
    final app = JuzzioAppController.instance;
    return ListenableBuilder(listenable: app, builder: (context, _) => _build(context, app));
  }

  Widget _build(BuildContext context, JuzzioAppController app) {
    return SizedBox(
      height: 168,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: kJuzzioAuroraPalettes.length,
        itemBuilder: (context, i) {
          final pal = kJuzzioAuroraPalettes[i];
          return _GalleryCard(
            palette: pal,
            title: pal.label(app.uiLang),
            subtitle: juzzioCharacterText(pal),
            selected: app.activeCustomTheme == null && app.glassPaletteId == pal.id,
            onTap: () => previewFirst ? JuzzioThemePreviewPage.open(context, pal.id) : app.setGlassPalette(pal.id),
          );
        },
      ),
    );
  }
}

/// Sohbet teması: 12 Liquid Glass ailesi + 16 sohbet ön ayarı. Dokununca hemen uygulanır.
class JuzzioChatThemeGallery extends StatelessWidget {
  const JuzzioChatThemeGallery({super.key});

  @override
  Widget build(BuildContext context) {
    // GM-014: tema/gece-gündüz değişince yeniden çizilir (const kullanımda donuyordu)
    final app = JuzzioAppController.instance;
    return ListenableBuilder(listenable: app, builder: (context, _) => _build(context, app));
  }

  Widget _build(BuildContext context, JuzzioAppController app) {
    final items = juzzioChatThemePreviewItems(app);
    return SizedBox(
      height: 168,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          final pal = it.palette;
          return _GalleryCard(
            palette: pal,
            title: pal.label(app.uiLang),
            subtitle: it.subtitle ?? juzzioCharacterText(pal),
            chatMock: true,
            selected: it.isApplied(app),
            // GM-033: dokun → önizleme (kaydır → sonraki tema, parlaklık/cam + Uygula)
            onTap: () => JuzzioThemePreviewPage.open(context, it.key, chat: true, items: items),
          );
        },
      ),
    );
  }
}

/// GM-032 (v2.2.0): uygulama temalarıyla ya da birbirleriyle AYNI renkteki klasik sohbet
/// ön ayarları galeride gösterilmez (dizin sırası korunur; seçili olan gizlenmez).
const Set<String> kJuzzioHiddenDuplicateChatPresets = {
  'rose_quartz', // = Gül Kuvars cam teması
  'nordic_slate', // = Cam (varsayılan) ile aynı gri
  'liquid_aqua', // = Siber Camgöbeği
  'liquid_violet', // = Lavanta Sisi cam teması
  'liquid_rose', // = Gül Kuvars
};

/// GM-033: sohbet teması önizleme listesi (cam aileleri + benzersiz klasik ön ayarlar)
List<JuzzioThemePreviewItem> juzzioChatThemePreviewItems(JuzzioAppController app) {
  final out = <JuzzioThemePreviewItem>[
    for (final p in kJuzzioAuroraPalettes)
      JuzzioThemePreviewItem(
        key: p.id,
        palette: p,
        isApplied: (a) => a.chatPaletteId == p.id,
        apply: (a) => a.setChatPalette(p.id),
      ),
  ];
  for (var idx = 0; idx < kJuzzioChatThemes.length; idx++) {
    final preset = kJuzzioChatThemes[idx];
    final selected = app.chatPaletteId.isEmpty && app.selectedChatThemeIndex == idx;
    if (kJuzzioHiddenDuplicateChatPresets.contains(preset.id) && !selected) continue;
    out.add(JuzzioThemePreviewItem(
      key: 'chat_${preset.id}',
      palette: _presetPalette(preset),
      subtitle: _gl('Klasik sohbet teması', 'Classic chat theme', 'Klassisches Chatdesign'),
      isApplied: (a) => a.chatPaletteId.isEmpty && a.selectedChatThemeIndex == idx,
      apply: (a) => a.setChatTheme(idx),
    ));
  }
  return out;
}
