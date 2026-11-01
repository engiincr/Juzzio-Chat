// =============================================================================
// JUZZIO v0.8.1 — Tema önizleme + Uygula
// Seçilen cam teması gerçek bileşenlerle (sohbet listesi, balonlar, arama, çipler,
// butonlar) önizlenir; yalnızca "Uygula" ile kullanıcının kendi seçimi olur.
// Yönetici varsayılanı bu seçimi asla değiştirmez.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_aurora.dart';
import '../core/theme/juzzio_glass.dart';
import '../core/widgets/glass_components.dart';

/// Temanın gerçek renkleriyle küçük rozet (boya ikonu yerine)
class JuzzioThemeSwatch extends StatelessWidget {
  final JuzzioAuroraPalette palette;
  final double size;
  final bool selected;
  const JuzzioThemeSwatch({super.key, required this.palette, this.size = 28, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.swatchA, palette.swatchB],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.95 : 0.55), width: selected ? 2 : 1.2),
        boxShadow: [BoxShadow(color: palette.swatchA.withValues(alpha: 0.45), blurRadius: size * 0.5)],
      ),
      child: selected ? Icon(Icons.check_rounded, size: size * 0.6, color: Colors.white) : null,
    );
  }
}

class JuzzioThemePreviewPage extends StatefulWidget {
  final String initialId;
  const JuzzioThemePreviewPage({super.key, required this.initialId});

  static Future<void> open(BuildContext context, String id) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => JuzzioThemePreviewPage(initialId: id)));

  @override
  State<JuzzioThemePreviewPage> createState() => _JuzzioThemePreviewPageState();
}

class _JuzzioThemePreviewPageState extends State<JuzzioThemePreviewPage> {
  late String _id = widget.initialId;
  late final PageController _pc = PageController(
    initialPage: kJuzzioAuroraPalettes.indexWhere((p) => p.id == widget.initialId).clamp(0, kJuzzioAuroraPalettes.length - 1),
    viewportFraction: 1,
  );

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final dark = app.isDark;
        final t = JuzzioGlassTokens.textPrimary;
        final applied = app.glassPaletteId == _id;
        final pal = juzzioAuroraPaletteById(_id);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: kJuzzioAuroraPalettes.length,
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _id = kJuzzioAuroraPalettes[i].id);
                  },
                  itemBuilder: (_, i) => JuzzioAuroraBackground(palette: kJuzzioAuroraPalettes[i], dark: dark),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(children: [
                        JuzzioGlassIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
                        const SizedBox(width: 10),
                        JuzzioThemeSwatch(palette: pal, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(pal.label(app.uiLang),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: t, fontSize: 20, fontWeight: FontWeight.w900)),
                              Text(app.translateUiDynamic(pal.character.tr, enText: pal.character.en, deText: pal.character.de),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(app.trEn('Kaydır →', 'Swipe →', 'Wischen →'),
                            style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                      ]),
                    ),
                    const Expanded(child: IgnorePointer(child: JuzzioThemeMockPreview())),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < kJuzzioAuroraPalettes.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: GestureDetector(
                                  onTap: () => _pc.animateToPage(i,
                                      duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                                  child: JuzzioThemeSwatch(
                                      palette: kJuzzioAuroraPalettes[i], size: 40, selected: kJuzzioAuroraPalettes[i].id == _id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: applied ? JuzzioGlassTokens.surfaceStrong : JuzzioGlassTokens.accentFill,
                          foregroundColor: applied ? t : JuzzioGlassTokens.onAccent,
                          minimumSize: const Size.fromHeight(54),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: applied
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                app.setGlassPalette(_id);
                                showGlassToast(context, app.trEn('Tema uygulandı: ${pal.label('tr')}',
                                    'Theme applied: ${pal.label('en')}', 'Design angewendet: ${pal.label('de')}'),
                                    icon: Icons.check_circle_rounded);
                              },
                        icon: Icon(applied ? Icons.check_circle_rounded : Icons.format_color_fill_rounded),
                        label: Text(
                          applied
                              ? app.trEn('Bu tema kullanılıyor', 'Theme in use', 'Design aktiv')
                              : app.trEn('Uygula', 'Apply', 'Anwenden'),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

/// Gerçek bileşenlerle mini uygulama önizlemesi (tema önizleme ve Tema Stüdyosu ortak).
/// Etkin tema tokenlarıyla çizildiği için düzenlenen tema anında yansır.
class JuzzioThemeMockPreview extends StatelessWidget {
  final bool shrinkWrap;
  const JuzzioThemeMockPreview({super.key, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    final p = JuzzioPalette(app.isDark);
    Widget tile(String name, String msg, int unread) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassContainer(
            enableBlur: false,
            iridescentBorder: unread > 0,
            borderRadius: 20,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              JuzzioGlassAvatar(imageUrl: null, name: name, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(color: t, fontWeight: FontWeight.w800)),
                  Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t2, fontSize: 12.5)),
                ]),
              ),
              if (unread > 0) JuzzioGlassBadge(count: unread),
            ]),
          ),
        );
    Widget bubble(String text, bool me) => Align(
          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: const BoxConstraints(maxWidth: 230),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: me ? p.outgoingBubble : p.incomingBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(me ? 20 : 6),
                bottomRight: Radius.circular(me ? 6 : 20),
              ),
              border: Border.all(color: me ? Colors.white.withValues(alpha: 0.18) : JuzzioGlassTokens.border),
            ),
            child: Text(text, style: TextStyle(color: me ? Colors.white : t, fontSize: 13.5)),
          ),
        );
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        GlassTextField(hintText: app.trEn('Kişi, grup veya mesaj ara...', 'Search...', 'Suchen...'), prefixIcon: Icons.search_rounded),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          GlassPill(label: app.trEn('Tümü', 'All', 'Alle'), selected: true),
          GlassPill(label: app.trEn('Kişiler', 'People', 'Personen')),
          GlassPill(label: app.trEn('Gruplar', 'Groups', 'Gruppen')),
        ]),
        const SizedBox(height: 14),
        tile('Elif', app.trEn('Akşam görüşelim mi? 🌙', 'See you tonight? 🌙', 'Heute Abend? 🌙'), 2),
        tile('Can', app.trEn('Dosyayı gönderdim', 'Sent the file', 'Datei gesendet'), 0),
        const SizedBox(height: 6),
        GlassContainer(
          borderRadius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            bubble(app.trEn('Selam! Yeni tema nasıl? ✨', 'Hi! How is the new theme? ✨', 'Hi! Wie ist das neue Design? ✨'), false),
            bubble(app.trEn('Çok yumuşak ve net görünüyor 💙', 'Looks soft and crisp 💙', 'Weich und klar 💙'), true),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: GlassTextField(hintText: app.trEn('Mesaj yaz', 'Message', 'Nachricht'))),
              const SizedBox(width: 8),
              const JuzzioGlassIconButton(icon: Icons.send_rounded, active: true),
            ]),
          ]),
        ),
      ],
    );
  }
}
