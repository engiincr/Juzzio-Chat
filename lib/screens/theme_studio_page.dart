// =============================================================================
// JUZZIO v0.8.2 — Tema Stüdyosu
//  • Özel temalar: oluştur, düzenle, uygula, yeniden adlandır, çoğalt, sil
//  • JSON dışa aktar (panoya) / içe aktar (güvenli doğrulama)
//  • Varsayılana dön (hazır cam temasına geri)
//  • Düzenleyicide canlı önizleme: taslak tüm uygulamaya geçici uygulanır,
//    kaydetmeden çıkılırsa eski görünüm geri gelir.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_custom_theme.dart';
import '../core/theme/juzzio_glass.dart';
import '../core/widgets/glass_components.dart';
import '../widgets/glass/juzzio_color_picker.dart';
import 'theme_preview_page.dart';

String _tr(String tr, String en, [String? de]) => JuzzioAppController.instance.trEn(tr, en, de);

class JuzzioThemeStudioPage extends StatelessWidget {
  const JuzzioThemeStudioPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioThemeStudioPage()));

  Future<void> _create(BuildContext context) async {
    final app = JuzzioAppController.instance;
    if (app.customThemes.length >= JuzzioAppController.maxCustomThemes) {
      showGlassToast(context, _tr('En fazla ${JuzzioAppController.maxCustomThemes} tema saklanabilir.',
          'At most ${JuzzioAppController.maxCustomThemes} themes.'), icon: Icons.warning_amber_rounded);
      return;
    }
    final choice = await showGlassBottomSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.auto_fix_high_rounded),
            title: Text(_tr('Mevcut görünümden başla', 'Start from current look')),
            onTap: () => Navigator.of(ctx).pop('current'),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded),
            title: Text(_tr('Sıfırdan — koyu', 'From scratch — dark')),
            onTap: () => Navigator.of(ctx).pop('dark'),
          ),
          ListTile(
            leading: const Icon(Icons.light_mode_rounded),
            title: Text(_tr('Sıfırdan — açık', 'From scratch — light')),
            onTap: () => Navigator.of(ctx).pop('light'),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    final draft = choice == 'current'
        ? app.draftFromCurrent()
        : JuzzioCustomTheme.blank(id: app.newCustomThemeId(), name: _tr('Yeni tema', 'New theme'), dark: choice == 'dark');
    await JuzzioThemeEditorPage.open(context, draft, isNew: true);
  }

  Future<void> _import(BuildContext context) async {
    final app = JuzzioAppController.instance;
    final ctrl = TextEditingController();
    final raw = await showGlassDialog<String>(
      context: context,
      title: _tr('JSON ile tema içe aktar', 'Import theme from JSON'),
      icon: Icons.file_download_rounded,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: ctrl,
          maxLines: 8,
          minLines: 4,
          style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 12.5, fontFamily: 'monospace'),
          decoration: InputDecoration(hintText: '{ "schema": "juzzio-theme", ... }'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final d = await Clipboard.getData(Clipboard.kTextPlain);
              if (d?.text != null) ctrl.text = d!.text!;
            },
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: Text(_tr('Panodan yapıştır', 'Paste')),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(_tr('İptal', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: Text(_tr('İçe aktar', 'Import'))),
      ],
    );
    ctrl.dispose();
    if (raw == null || raw.trim().isEmpty || !context.mounted) return;
    final res = app.importCustomThemeJson(raw);
    if (!res.ok) {
      await showGlassDialog<void>(
        context: context,
        title: _tr('Tema içe aktarılamadı', 'Import failed'),
        icon: Icons.error_outline_rounded,
        message: res.errors.take(8).map((e) => '• $e').join('\n'),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(_tr('Tamam', 'OK')))],
      );
      return;
    }
    showGlassToast(
      context,
      res.warnings.isEmpty
          ? _tr('"${res.theme!.name}" içe aktarıldı', 'Imported "${res.theme!.name}"')
          : _tr('"${res.theme!.name}" içe aktarıldı (${res.warnings.length} düzeltme)', 'Imported with ${res.warnings.length} fixes'),
      icon: Icons.check_circle_rounded,
    );
  }

  Future<void> _rename(BuildContext context, JuzzioCustomTheme t) async {
    final ctrl = TextEditingController(text: t.name);
    final name = await showGlassDialog<String>(
      context: context,
      title: _tr('Yeniden adlandır', 'Rename'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: JuzzioCustomTheme.maxNameLength,
        style: TextStyle(color: JuzzioGlassTokens.textPrimary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(_tr('İptal', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: Text(_tr('Kaydet', 'Save'))),
      ],
    );
    ctrl.dispose();
    if (name != null) JuzzioAppController.instance.renameCustomTheme(t.id, name);
  }

  Future<void> _delete(BuildContext context, JuzzioCustomTheme t) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      title: _tr('Tema silinsin mi?', 'Delete theme?'),
      icon: Icons.delete_outline_rounded,
      message: _tr('"${t.name}" kalıcı olarak silinecek. Dışa aktardıysanız JSON ile geri yükleyebilirsiniz.',
          '"${t.name}" will be deleted permanently.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(_tr('Vazgeç', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF647B), foregroundColor: Colors.white),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_tr('Sil', 'Delete')),
        ),
      ],
    );
    if (ok == true) JuzzioAppController.instance.deleteCustomTheme(t.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final themes = app.customThemes;
        final t = JuzzioGlassTokens.textPrimary;
        final t2 = JuzzioGlassTokens.textSecondary;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(_tr('Tema Stüdyosu', 'Theme Studio', 'Design-Studio'),
                style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
            actions: [
              IconButton(
                tooltip: _tr('JSON içe aktar', 'Import JSON'),
                icon: const Icon(Icons.file_download_rounded),
                onPressed: () => _import(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: JuzzioGlassTokens.accentFill,
            foregroundColor: JuzzioGlassTokens.onAccent,
            onPressed: () => _create(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(_tr('Yeni tema', 'New theme'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              if (app.activeCustomTheme != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassContainer(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Row(children: [
                      Icon(Icons.palette_outlined, color: JuzzioGlassTokens.icon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_tr('Etkin: ${app.activeCustomTheme!.name}', 'Active: ${app.activeCustomTheme!.name}'),
                            style: TextStyle(color: t, fontWeight: FontWeight.w800)),
                      ),
                      TextButton.icon(
                        onPressed: app.clearCustomTheme,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: Text(_tr('Varsayılana dön', 'Reset to default')),
                      ),
                    ]),
                  ),
                ),
              if (themes.isEmpty)
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(Icons.brush_rounded, size: 40, color: JuzzioGlassTokens.icon),
                    const SizedBox(height: 10),
                    Text(_tr('Henüz özel temanız yok', 'No custom themes yet'),
                        style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      _tr('Arka plan, metin, başlık, buton, kart, sohbet balonu, ikon, kenarlık ve cam efektlerini tek tek ayarlayarak kendi temanızı oluşturun.',
                          'Build your own theme by adjusting every color role and the glass effect.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t2, height: 1.4),
                    ),
                  ]),
                ),
              for (final th in themes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ThemeCard(
                    theme: th,
                    active: app.activeCustomThemeId == th.id,
                    onApply: () {
                      app.applyCustomTheme(th.id);
                      showGlassToast(context, _tr('Tema uygulandı: ${th.name}', 'Theme applied: ${th.name}'),
                          icon: Icons.check_circle_rounded);
                    },
                    onEdit: () => JuzzioThemeEditorPage.open(context, th),
                    onMenu: (v) async {
                      switch (v) {
                        case 'rename':
                          await _rename(context, th);
                        case 'duplicate':
                          final c = app.duplicateCustomTheme(th.id);
                          if (c == null && context.mounted) {
                            showGlassToast(context, _tr('Tema sınırına ulaşıldı.', 'Theme limit reached.'),
                                icon: Icons.warning_amber_rounded);
                          }
                        case 'export':
                          await Clipboard.setData(ClipboardData(text: app.exportCustomThemeJson(th.id)));
                          if (context.mounted) {
                            showGlassToast(context, _tr('Tema JSON olarak panoya kopyalandı', 'Theme JSON copied'),
                                icon: Icons.content_copy_rounded);
                          }
                        case 'delete':
                          await _delete(context, th);
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final JuzzioCustomTheme theme;
  final bool active;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final ValueChanged<String> onMenu;
  const _ThemeCard({required this.theme, required this.active, required this.onApply, required this.onEdit, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final t = JuzzioGlassTokens.textPrimary;
    return GlassContainer(
      enableBlur: false,
      iridescentBorder: active,
      padding: const EdgeInsets.all(12),
      onTap: onEdit,
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: theme.gradient
                  ? [theme.c('gradientA'), theme.background, theme.c('gradientB')]
                  : [theme.background, theme.background],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Center(
            child: Container(
              width: 22,
              height: 14,
              decoration: BoxDecoration(color: theme.bubbleOut, borderRadius: BorderRadius.circular(7)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(theme.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              '${theme.dark ? _tr('Koyu', 'Dark') : _tr('Açık', 'Light')} · blur ${theme.blur.round()} · ${(theme.opacity * 100).round()}%'
              '${theme.textReadable ? '' : ' · ⚠ ${_tr('düşük kontrast', 'low contrast')}'}',
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12),
            ),
          ]),
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.check_circle_rounded, color: JuzzioGlassTokens.icon),
          )
        else
          TextButton(onPressed: onApply, child: Text(_tr('Uygula', 'Apply'))),
        PopupMenuButton<String>(
          tooltip: _tr('Diğer', 'More'),
          onSelected: onMenu,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text(_tr('Yeniden adlandır', 'Rename'))),
            PopupMenuItem(value: 'duplicate', child: Text(_tr('Çoğalt', 'Duplicate'))),
            PopupMenuItem(value: 'export', child: Text(_tr('JSON dışa aktar', 'Export JSON'))),
            PopupMenuItem(value: 'delete', child: Text(_tr('Sil', 'Delete'))),
          ],
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// DÜZENLEYİCİ
// -----------------------------------------------------------------------------
class JuzzioThemeEditorPage extends StatefulWidget {
  final JuzzioCustomTheme initial;
  final bool isNew;
  /// v0.8.3: verilirse tema yerel olarak değil bu geri çağırımla kaydedilir
  /// (Yönetici Tema Stüdyosu → sunucuya taslak). true dönerse kaydedildi.
  final Future<bool> Function(JuzzioCustomTheme theme)? onSubmit;
  final String? submitLabel;
  const JuzzioThemeEditorPage({super.key, required this.initial, this.isNew = false, this.onSubmit, this.submitLabel});

  static Future<void> open(BuildContext context, JuzzioCustomTheme t,
          {bool isNew = false, Future<bool> Function(JuzzioCustomTheme theme)? onSubmit, String? submitLabel}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => JuzzioThemeEditorPage(initial: t, isNew: isNew, onSubmit: onSubmit, submitLabel: submitLabel)));

  @override
  State<JuzzioThemeEditorPage> createState() => _JuzzioThemeEditorPageState();
}

class _JuzzioThemeEditorPageState extends State<JuzzioThemeEditorPage> {
  final _app = JuzzioAppController.instance;
  late JuzzioCustomTheme _draft = widget.initial;
  late final TextEditingController _name = TextEditingController(text: widget.initial.name);
  bool _dirty = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    // canlı önizleme: taslak tüm uygulamaya geçici uygulanır
    WidgetsBinding.instance.addPostFrameCallback((_) => _app.previewCustomTheme(_draft));
  }

  @override
  void dispose() {
    _name.dispose();
    // kaydedilmeden çıkıldıysa önceki görünüm geri gelir
    _app.previewCustomTheme(null);
    super.dispose();
  }

  void _update(JuzzioCustomTheme t) {
    setState(() {
      _draft = t;
      _dirty = true;
    });
    _app.previewCustomTheme(t);
  }

  Future<void> _pick(String role, {bool alpha = false, Color? against}) async {
    final c = await showJuzzioColorPicker(
      context,
      initial: _draft.c(role),
      title: JuzzioCustomTheme.colorRoles[role] ?? role,
      allowAlpha: alpha,
      contrastAgainst: against,
    );
    if (c != null) _update(_draft.withColor(role, c));
  }

  bool _save({bool apply = false}) {
    final t = _draft.copyWith(name: JuzzioCustomTheme.sanitizeName(_name.text));
    final ok = _app.saveCustomTheme(t);
    if (!ok) {
      showGlassToast(context, _tr('Tema sınırına ulaşıldı.', 'Theme limit reached.'), icon: Icons.warning_amber_rounded);
      return false;
    }
    if (apply) _app.applyCustomTheme(t.id);
    _saved = true;
    _dirty = false;
    return true;
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _saved) return true;
    final r = await showGlassDialog<String>(
      context: context,
      title: _tr('Değişiklikler kaydedilsin mi?', 'Save changes?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop('discard'), child: Text(_tr('Kaydetme', 'Discard'))),
        FilledButton(onPressed: () => Navigator.of(context).pop('save'), child: Text(_tr('Kaydet', 'Save'))),
      ],
    );
    if (r == 'save') {
      if (widget.onSubmit != null) return widget.onSubmit!(_draft.copyWith(name: JuzzioCustomTheme.sanitizeName(_name.text)));
      return _save();
    }
    return r == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    final ratio = JuzzioCustomTheme.contrastRatio(_draft.text, _draft.background);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: GlassContainer(
            enableBlur: false,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: TextStyle(color: JuzzioGlassTokens.heading, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 6),
              ...children,
            ]),
          ),
        );

    Widget colorRow(String role, {bool alpha = false, Color? against}) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          onTap: () => _pick(role, alpha: alpha, against: against),
          title: Text(JuzzioCustomTheme.colorRoles[role] ?? role, style: TextStyle(color: t, fontWeight: FontWeight.w700)),
          subtitle: Text(JuzzioCustomTheme.toHex(_draft.c(role)), style: TextStyle(color: t2, fontSize: 12)),
          trailing: Container(
            width: 40,
            height: 28,
            decoration: BoxDecoration(
              color: _draft.c(role),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JuzzioGlassTokens.borderStrong),
            ),
          ),
        );

    Widget slider(String label, double value, double min, double max, String shown, ValueChanged<double> onChanged) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: t, fontWeight: FontWeight.w700))),
            Text(shown, style: TextStyle(color: t2, fontWeight: FontWeight.w800)),
          ]),
          Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
        ]);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.isNew ? _tr('Yeni tema', 'New theme') : _tr('Temayı düzenle', 'Edit theme'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
          actions: [
            if (widget.onSubmit == null)
              TextButton(
                onPressed: () {
                  if (_save()) {
                    showGlassToast(context, _tr('Kaydedildi', 'Saved'), icon: Icons.check_circle_rounded);
                  }
                },
                child: Text(_tr('Kaydet', 'Save'), style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            // Canlı önizleme (etkin tokenlarla çizilir → taslak anında görünür)
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: const SizedBox(
                height: 330,
                child: IgnorePointer(child: JuzzioThemeMockPreview()),
              ),
            ),
            if (ratio < 4.5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠ ${_tr('Metin/arka plan kontrastı', 'Text/background contrast')} ${ratio.toStringAsFixed(1)}:1 — '
                  '${_tr('okunabilirlik için en az 4.5:1 önerilir.', 'at least 4.5:1 is recommended.')}',
                  style: const TextStyle(color: Color(0xFFFF647B), fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
            section(_tr('Genel', 'General'), [
              TextField(
                controller: _name,
                maxLength: JuzzioCustomTheme.maxNameLength,
                style: TextStyle(color: t),
                decoration: InputDecoration(labelText: _tr('Tema adı', 'Theme name')),
                onChanged: (_) => _dirty = true,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.dark,
                onChanged: (v) => _update(_draft.copyWith(dark: v)),
                title: Text(_tr('Koyu tema', 'Dark theme'), style: TextStyle(color: t, fontWeight: FontWeight.w700)),
                subtitle: Text(_tr('Durum çubuğu ve sistem bileşenleri buna göre ayarlanır', 'System UI follows this'),
                    style: TextStyle(color: t2, fontSize: 12)),
              ),
            ]),
            section(_tr('Arka plan ve gradyan', 'Background & gradient'), [
              colorRow('background'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.gradient,
                onChanged: (v) => _update(_draft.copyWith(gradient: v)),
                title: Text(_tr('Aurora gradyanı', 'Aurora gradient'), style: TextStyle(color: t, fontWeight: FontWeight.w700)),
              ),
              if (_draft.gradient) ...[colorRow('gradientA'), colorRow('gradientB'), colorRow('gradientC')],
            ]),
            section(_tr('Metin', 'Text'), [
              colorRow('text', against: _draft.background),
              colorRow('heading', against: _draft.background),
            ]),
            section(_tr('Bileşenler', 'Components'), [
              colorRow('button'),
              colorRow('buttonText', against: _draft.button),
              colorRow('card'),
              colorRow('icon', against: _draft.background),
              colorRow('border', alpha: true),
            ]),
            section(_tr('Sohbet balonları', 'Chat bubbles'), [
              colorRow('bubbleOut'),
              colorRow('bubbleIn'),
            ]),
            section(_tr('Cam efekti', 'Glass effect'), [
              slider(_tr('Bulanıklık (blur)', 'Blur'), _draft.blur, JuzzioCustomTheme.blurMin, JuzzioCustomTheme.blurMax,
                  _draft.blur.round().toString(), (v) => _update(_draft.copyWith(blur: v))),
              slider(_tr('Opaklık', 'Opacity'), _draft.opacity, JuzzioCustomTheme.opacityMin, JuzzioCustomTheme.opacityMax,
                  '${(_draft.opacity * 100).round()}%', (v) => _update(_draft.copyWith(opacity: v))),
              slider(_tr('Cam yoğunluğu', 'Glass intensity'), _draft.intensity, JuzzioCustomTheme.intensityMin,
                  JuzzioCustomTheme.intensityMax, '${(_draft.intensity * 100).round()}%', (v) => _update(_draft.copyWith(intensity: v))),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
              onPressed: () async {
                if (widget.onSubmit != null) {
                  final nav = Navigator.of(context);
                  final ok = await widget.onSubmit!(_draft.copyWith(name: JuzzioCustomTheme.sanitizeName(_name.text)));
                  if (ok) {
                    _saved = true;
                    _dirty = false;
                    nav.pop();
                  }
                  return;
                }
                if (_save(apply: true)) {
                  showGlassToast(context, _tr('Kaydedildi ve uygulandı', 'Saved and applied'), icon: Icons.check_circle_rounded);
                  Navigator.of(context).pop();
                }
              },
              icon: Icon(widget.onSubmit != null ? Icons.cloud_upload_rounded : Icons.format_color_fill_rounded),
              label: Text(widget.submitLabel ?? _tr('Kaydet ve uygula', 'Save & apply'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              onPressed: () => _update(JuzzioCustomTheme.blank(id: _draft.id, name: _name.text, dark: _draft.dark)),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(_tr('Renkleri varsayılana sıfırla', 'Reset colors to default')),
            ),
          ],
        ),
      ),
    );
  }
}
