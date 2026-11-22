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

/// GM-033 (v2.2.0): önizlemedeki tek bir tema (uygulama teması ya da sohbet teması)
class JuzzioThemePreviewItem {
  const JuzzioThemePreviewItem({
    required this.key,
    required this.palette,
    required this.isApplied,
    required this.apply,
    this.subtitle,
  });
  final String key;
  final JuzzioAuroraPalette palette;
  final String? subtitle;
  final bool Function(JuzzioAppController app) isApplied;
  final void Function(JuzzioAppController app) apply;
}

/// Uygulama temaları (tüm cam aileleri)
List<JuzzioThemePreviewItem> juzzioAppThemePreviewItems() => [
      for (final p in kJuzzioAuroraPalettes)
        JuzzioThemePreviewItem(
          key: p.id,
          palette: p,
          isApplied: (app) => app.activeCustomTheme == null && app.glassPaletteId == p.id,
          apply: (app) => app.setGlassPalette(p.id),
        ),
    ];

/// GM-033: tema adı + ayar etiketi → "Gece Mavisi | Parlaklık"
String juzzioThemeSettingLabel(String themeName, String setting) => '$themeName | $setting';

/// GM-033 (v2.2.0): tema önizleme — dokun → önizleme, sağa kaydır → sonraki tema.
/// Aynı ekranda parlaklık ve cam yoğunluğu ayarlanır; "Uygula" hepsini birlikte uygular.
/// Uygulama temaları ve sohbet temaları aynı sayfayı kullanır ([chat] = true → sohbet teması).
class JuzzioThemePreviewPage extends StatefulWidget {
  final String initialId;
  final bool chat;
  final List<JuzzioThemePreviewItem>? items;
  const JuzzioThemePreviewPage({super.key, required this.initialId, this.chat = false, this.items});

  static Future<void> open(BuildContext context, String id, {bool chat = false, List<JuzzioThemePreviewItem>? items}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioThemePreviewPage(initialId: id, chat: chat, items: items)));

  @override
  State<JuzzioThemePreviewPage> createState() => _JuzzioThemePreviewPageState();
}

class _JuzzioThemePreviewPageState extends State<JuzzioThemePreviewPage> {
  final JuzzioAppController _app = JuzzioAppController.instance;
  late final List<JuzzioThemePreviewItem> _items = widget.items ?? juzzioAppThemePreviewItems();
  late int _index = _items.indexWhere((e) => e.key == widget.initialId).clamp(0, _items.length - 1);
  late final PageController _pc = PageController(initialPage: _index);
  late double _brightness = _app.chatThemeIntensity.clamp(0.6, 1.4).toDouble();
  late double _glass = _app.glassIntensity;
  late final double _origGlass = _app.glassIntensity;
  bool _applied = false;

  @override
  void dispose() {
    // uygulanmadan çıkılırsa canlı önizlemedeki cam yoğunluğu eski hâline döner
    if (!_applied) JuzzioGlassTokens.intensity = _origGlass;
    _pc.dispose();
    super.dispose();
  }

  JuzzioThemePreviewItem get _item => _items[_index];

  bool get _dirty =>
      !_item.isApplied(_app) || (_brightness - _app.chatThemeIntensity).abs() > 0.001 || (_glass - _app.glassIntensity).abs() > 0.001;

  void _apply() {
    HapticFeedback.mediumImpact();
    _item.apply(_app);
    _app.setChatThemeIntensity(_brightness);
    _app.setGlassIntensity(_glass);
    _applied = true;
    final n = _item.palette;
    showGlassToast(
        context,
        widget.chat
            ? _app.trEn('Sohbet teması uygulandı: ${n.label('tr')}', 'Chat theme applied: ${n.label('en')}', 'Chatdesign angewendet: ${n.label('de')}')
            : _app.trEn('Tema uygulandı: ${n.label('tr')}', 'Theme applied: ${n.label('en')}', 'Design angewendet: ${n.label('de')}'),
        icon: Icons.check_circle_rounded);
    setState(() {});
  }

  Widget _slider({required IconData icon, required String label, required double value, required ValueChanged<double> onChanged, required Key key}) {
    final t = JuzzioGlassTokens.textPrimary;
    return Row(children: [
      Icon(icon, size: 18, color: JuzzioGlassTokens.glowText),
      const SizedBox(width: 8),
      SizedBox(
        width: 150,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t, fontWeight: FontWeight.w800, fontSize: 12.5)),
      ),
      Expanded(
        child: Slider(
          key: key,
          value: value,
          min: 0.6,
          max: 1.4,
          divisions: 16,
          activeColor: JuzzioGlassTokens.glow,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 42,
        child: Text('${(value * 100).round()}%',
            textAlign: TextAlign.end, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (context, _) {
        final dark = _app.isDark;
        final t = JuzzioGlassTokens.textPrimary;
        final pal = _item.palette;
        final name = pal.label(_app.uiLang);
        final dirty = _dirty;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  key: const ValueKey('gm033-theme-pager'),
                  controller: _pc,
                  itemCount: _items.length,
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = i);
                  },
                  itemBuilder: (_, i) => Opacity(
                    opacity: ((_brightness - 0.6) / 0.8 * 0.45 + 0.55).clamp(0.55, 1.0),
                    child: JuzzioAuroraBackground(palette: _items[i].palette, dark: dark),
                  ),
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
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t, fontSize: 20, fontWeight: FontWeight.w900)),
                              Text(
                                  _item.subtitle ??
                                      _app.translateUiDynamic(pal.character.tr, enText: pal.character.en, deText: pal.character.de),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('${_index + 1}/${_items.length}  ${_app.trEn('Kaydır →', 'Swipe →', 'Wischen →')}',
                            style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                      ]),
                    ),
                    const Expanded(child: IgnorePointer(child: JuzzioThemeMockPreview())),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < _items.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: GestureDetector(
                                  onTap: () => _pc.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                                  child: JuzzioThemeSwatch(palette: _items[i].palette, size: 40, selected: i == _index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: JuzzioLiquidGlass(
                        radius: 18,
                        padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          _slider(
                            key: const ValueKey('gm033-brightness'),
                            icon: Icons.brightness_6_rounded,
                            label: juzzioThemeSettingLabel(name, _app.trEn('Parlaklık', 'Brightness', 'Helligkeit')),
                            value: _brightness,
                            onChanged: (v) => setState(() => _brightness = v),
                          ),
                          _slider(
                            key: const ValueKey('gm033-glass'),
                            icon: Icons.blur_on_rounded,
                            label: juzzioThemeSettingLabel(name, _app.trEn('Cam yoğunluğu', 'Glass intensity', 'Glasintensität')),
                            value: _glass,
                            onChanged: (v) => setState(() {
                              _glass = v;
                              JuzzioGlassTokens.intensity = v; // canlı önizleme (Uygula'ya kadar kaydedilmez)
                            }),
                          ),
                        ]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FilledButton.icon(
                        key: const ValueKey('gm033-apply'),
                        style: FilledButton.styleFrom(
                          backgroundColor: dirty ? JuzzioGlassTokens.accentFill : JuzzioGlassTokens.surfaceStrong,
                          foregroundColor: dirty ? JuzzioGlassTokens.onAccent : t,
                          minimumSize: const Size.fromHeight(54),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: dirty ? _apply : null,
                        icon: Icon(dirty ? Icons.format_color_fill_rounded : Icons.check_circle_rounded),
                        label: Text(
                          dirty ? _app.trEn('Uygula', 'Apply', 'Anwenden') : _app.trEn('Bu tema kullanılıyor', 'Theme in use', 'Design aktiv'),
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
