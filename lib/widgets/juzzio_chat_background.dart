// =============================================================================
// JUZZIO v2.2.0 — GM-019: sohbete özel arka plan
//  Kişi bilgisi → "Sohbet arka planı". Yalnız O sohbete uygulanır (cihazda saklanır):
//  • Varsayılan (tema zemini)
//  • Galeriden görsel: önce kırpma/konumlandırma ekranı (yakınlaştır, sağa-sola kaydır, döndür),
//    sonra önizleme; "Kaydet ve uygula" deyince sohbete uygulanır. Karartma ayarlanabilir.
//  • Hazır renk ve degrade temaları (tema vurgusuyla uyumlu "Tema ışıltısı" dahil)
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_aurora.dart';
import '../core/theme/juzzio_glass.dart';

/// Arka plan türleri
enum JuzzioChatBgKind { none, image, preset }

/// Bir sohbetin arka plan ayarı (saf; JSON ile saklanır, test edilir)
@immutable
class JuzzioChatBackground {
  const JuzzioChatBackground({this.kind = JuzzioChatBgKind.none, this.imagePath = '', this.presetId = '', this.dim = 0.35, this.alignX = 0});
  final JuzzioChatBgKind kind;
  final String imagePath;
  final String presetId;

  /// Görselin üstüne konan karartma (0 = yok, 0.8 = çok koyu); yazılar okunur kalsın diye
  final double dim;

  /// GM-019: görselin yatay konumu (-1 = sol, 0 = orta, 1 = sağ) — geniş ekranlarda (Windows) kırpılan alanı seçer
  final double alignX;

  static const none = JuzzioChatBackground();

  Map<String, dynamic> toJson() => {'k': kind.name, 'p': imagePath, 's': presetId, 'd': dim, 'x': alignX};

  factory JuzzioChatBackground.fromJson(Object? raw) {
    if (raw is! Map) return none;
    final k = JuzzioChatBgKind.values.firstWhere((e) => e.name == raw['k'], orElse: () => JuzzioChatBgKind.none);
    final d = (raw['d'] as num?)?.toDouble() ?? 0.35;
    return JuzzioChatBackground(
      kind: k,
      imagePath: (raw['p'] ?? '').toString(),
      presetId: (raw['s'] ?? '').toString(),
      dim: d.clamp(0.0, 0.8).toDouble(),
      alignX: ((raw['x'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0).toDouble(),
    );
  }

  JuzzioChatBackground copyWith({JuzzioChatBgKind? kind, String? imagePath, String? presetId, double? dim, double? alignX}) => JuzzioChatBackground(
        kind: kind ?? this.kind,
        imagePath: imagePath ?? this.imagePath,
        presetId: presetId ?? this.presetId,
        dim: dim ?? this.dim,
        alignX: alignX ?? this.alignX,
      );

  @override
  bool operator ==(Object other) =>
      other is JuzzioChatBackground && other.kind == kind && other.imagePath == imagePath && other.presetId == presetId && other.dim == dim && other.alignX == alignX;

  @override
  int get hashCode => Object.hash(kind, imagePath, presetId, dim, alignX);
}

/// Hazır arka plan (renk ya da degrade)
class JuzzioChatBgPreset {
  const JuzzioChatBgPreset(this.id, this.tr, this.en, this.de, this.colors);
  final String id;
  final String tr;
  final String en;
  final String de;

  /// Boşsa tema vurgusundan üretilir ("Tema ışıltısı")
  final List<Color> colors;
}

const List<JuzzioChatBgPreset> kJuzzioChatBgPresets = [
  JuzzioChatBgPreset('theme_glow', 'Tema ışıltısı', 'Theme glow', 'Design-Glanz', []),
  JuzzioChatBgPreset('night', 'Gece', 'Night', 'Nacht', [Color(0xFF0B1426), Color(0xFF1B2D4F)]),
  JuzzioChatBgPreset('ocean', 'Okyanus', 'Ocean', 'Ozean', [Color(0xFF06283D), Color(0xFF1363DF)]),
  JuzzioChatBgPreset('sunset', 'Gün batımı', 'Sunset', 'Sonnenuntergang', [Color(0xFF2B1B3D), Color(0xFFB4505A), Color(0xFFF2A65A)]),
  JuzzioChatBgPreset('lavender', 'Lavanta', 'Lavender', 'Lavendel', [Color(0xFF2A2141), Color(0xFF6D5BB8)]),
  JuzzioChatBgPreset('forest', 'Orman', 'Forest', 'Wald', [Color(0xFF0E1F17), Color(0xFF2F6B4A)]),
  JuzzioChatBgPreset('rose', 'Gül', 'Rose', 'Rose', [Color(0xFF2B1620), Color(0xFFB5536F)]),
  JuzzioChatBgPreset('graphite', 'Grafit', 'Graphite', 'Graphit', [Color(0xFF16181C), Color(0xFF2A2D33)]),
  JuzzioChatBgPreset('pearl', 'İnci', 'Pearl', 'Perle', [Color(0xFFF4F1EA), Color(0xFFDCE3EE)]),
];

JuzzioChatBgPreset? juzzioChatBgPresetById(String id) {
  for (final p in kJuzzioChatBgPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Hazır temanın renkleri (tema ışıltısı → mevcut tema zemini + vurgu; saf)
List<Color> juzzioChatBgPresetColors(JuzzioChatBgPreset p, {required Color glow, required Color base}) {
  if (p.colors.isNotEmpty) return p.colors;
  return [base, Color.lerp(base, glow, 0.28)!, base];
}

/// Sohbet arka planlarını cihazda saklar (JSON dosyası + kopyalanmış görseller)
class JuzzioChatBackgrounds extends ChangeNotifier {
  JuzzioChatBackgrounds._();
  static final JuzzioChatBackgrounds instance = JuzzioChatBackgrounds._();

  final Map<String, JuzzioChatBackground> _map = {};
  bool _loaded = false;

  JuzzioChatBackground of(String roomId) => _map[roomId] ?? JuzzioChatBackground.none;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}chat_backgrounds');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file() async => File('${(await _dir()).path}${Platform.pathSeparator}backgrounds.json');

  Future<void> load() async {
    if (_loaded || kIsWeb) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          raw.forEach((k, v) => _map[k.toString()] = JuzzioChatBackground.fromJson(v));
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_map.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
  }

  /// Seçilen görseli sohbete özel kalıcı yere kopyalar ve uygular
  Future<void> setImage(String roomId, File source, {double dim = 0.35, double alignX = 0}) async {
    final d = await _dir();
    final safe = roomId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final target = File('${d.path}${Platform.pathSeparator}$safe-${DateTime.now().millisecondsSinceEpoch}.png');
    await source.copy(target.path);
    final old = _map[roomId];
    _map[roomId] = JuzzioChatBackground(kind: JuzzioChatBgKind.image, imagePath: target.path, dim: dim, alignX: alignX);
    await _deleteOldImage(old, keep: target.path);
    await _save();
    notifyListeners();
  }

  Future<void> set(String roomId, JuzzioChatBackground bg) async {
    final old = _map[roomId];
    if (bg.kind == JuzzioChatBgKind.none) {
      _map.remove(roomId);
    } else {
      _map[roomId] = bg;
    }
    await _deleteOldImage(old, keep: bg.imagePath);
    await _save();
    notifyListeners();
  }

  Future<void> _deleteOldImage(JuzzioChatBackground? old, {required String keep}) async {
    if (old == null || old.kind != JuzzioChatBgKind.image || old.imagePath.isEmpty || old.imagePath == keep) return;
    try {
      final f = File(old.imagePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Sohbet gövdesinin arkasına konan katman (ayar yoksa hiçbir şey çizmez)
class JuzzioChatBackgroundLayer extends StatefulWidget {
  const JuzzioChatBackgroundLayer({super.key, required this.roomId, this.preview});
  final String roomId;

  /// Önizlemede kaydedilmemiş ayarı göstermek için
  final JuzzioChatBackground? preview;

  @override
  State<JuzzioChatBackgroundLayer> createState() => _JuzzioChatBackgroundLayerState();
}

class _JuzzioChatBackgroundLayerState extends State<JuzzioChatBackgroundLayer> {
  @override
  void initState() {
    super.initState();
    JuzzioChatBackgrounds.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([JuzzioChatBackgrounds.instance, JuzzioAppController.instance]),
      builder: (context, _) {
        final bg = widget.preview ?? JuzzioChatBackgrounds.instance.of(widget.roomId);
        return IgnorePointer(child: juzzioChatBackgroundPaint(bg));
      },
    );
  }
}

/// Ayara göre arka planı çizer (önizleme ve sohbet aynı kodu kullanır)
Widget juzzioChatBackgroundPaint(JuzzioChatBackground bg) {
  switch (bg.kind) {
    case JuzzioChatBgKind.none:
      return const SizedBox.shrink();
    case JuzzioChatBgKind.image:
      if (bg.imagePath.isEmpty || kIsWeb) return const SizedBox.shrink();
      return Stack(fit: StackFit.expand, children: [
        Image.file(File(bg.imagePath),
            fit: BoxFit.cover,
            alignment: Alignment(bg.alignX, 0),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        if (bg.dim > 0) ColoredBox(color: Colors.black.withValues(alpha: bg.dim)),
      ]);
    case JuzzioChatBgKind.preset:
      final p = juzzioChatBgPresetById(bg.presetId);
      if (p == null) return const SizedBox.shrink();
      final depth = JuzzioGlassTokens.space.depth;
      final colors = juzzioChatBgPresetColors(p, glow: JuzzioGlassTokens.glow, base: depth.isEmpty ? Colors.black : depth.first);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.length == 1
              ? null
              : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          color: colors.length == 1 ? colors.first : null,
        ),
      );
  }
}

/// Kişi bilgisi → Sohbet arka planı düzenleyicisi
class JuzzioChatBackgroundPage extends StatefulWidget {
  const JuzzioChatBackgroundPage({super.key, required this.roomId, required this.title});
  final String roomId;
  final String title;

  static Future<void> open(BuildContext context, {required String roomId, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioChatBackgroundPage(roomId: roomId, title: title)));

  @override
  State<JuzzioChatBackgroundPage> createState() => _JuzzioChatBackgroundPageState();
}

class _JuzzioChatBackgroundPageState extends State<JuzzioChatBackgroundPage> {
  final _app = JuzzioAppController.instance;
  late JuzzioChatBackground _draft = JuzzioChatBackgrounds.instance.of(widget.roomId);
  File? _pendingImage;
  bool _saving = false;

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 2000);
      if (picked == null || !mounted) return;
      // kırp + konumlandır (yakınlaştır, sağa/sola kaydır, döndür) — hemen uygulanmaz
      final cropped = await JuzzioImageCropperModal.show(
        context,
        sourceFile: File(picked.path),
        isCircular: false,
        aspectRatio: 9 / 16,
        title: _app.trEn('Arka planı kırp ve konumlandır', 'Crop and position background', 'Hintergrund zuschneiden'),
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _pendingImage = cropped;
        _draft = JuzzioChatBackground(kind: JuzzioChatBgKind.image, imagePath: cropped.path, dim: _draft.dim, alignX: _draft.alignX);
      });
    } catch (_) {}
  }

  Future<void> _apply() async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = JuzzioChatBackgrounds.instance;
    if (_draft.kind == JuzzioChatBgKind.image && _pendingImage != null) {
      await store.setImage(widget.roomId, _pendingImage!, dim: _draft.dim, alignX: _draft.alignX);
    } else {
      await store.set(widget.roomId, _draft);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(_app.trEn('Sohbet arka planı uygulandı.', 'Chat background applied.', 'Chat-Hintergrund angewendet.')),
    ));
  }

  Widget _bubble(String text, {required bool mine}) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 190),
        decoration: BoxDecoration(
          color: mine ? JuzzioGlassTokens.glow.withValues(alpha: 0.85) : JuzzioGlassTokens.sheet.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
        ),
        child: Text(text,
            style: TextStyle(
                color: mine ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _swatch({required Widget child, required bool selected, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? JuzzioGlassTokens.glow : JuzzioGlassTokens.spaceCardBorder, width: selected ? 2.4 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (context, _) {
        final lang = _app.uiLang;
        String name(JuzzioChatBgPreset p) => lang == 'tr' ? p.tr : (lang == 'de' ? p.de : p.en);
        final depth = JuzzioGlassTokens.space.depth;
        return JuzzioAuroraPage(
          weather: false, // GM-019: önizlemenin üstünde hava doodle'ı görünmesin
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: JuzzioGlassTokens.heading,
              elevation: 0,
              title: Text(_app.trEn('Sohbet arka planı', 'Chat background', 'Chat-Hintergrund'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            body: SafeArea(
              top: false,
              child: Column(children: [
                // Önizleme (yalnız bu sohbet)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(fit: StackFit.expand, children: [
                            DecoratedBox(decoration: JuzzioGlassTokens.backdrop),
                            juzzioChatBackgroundPaint(_draft),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                _bubble(_app.trEn('Selam! Yeni arka plan nasıl?', 'Hi! How is the new background?', 'Hallo! Wie ist der neue Hintergrund?'),
                                    mine: false),
                                _bubble(_app.trEn('Çok güzel oldu 😍', 'Looks great 😍', 'Sieht toll aus 😍'), mine: true),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_draft.kind == JuzzioChatBgKind.image)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      Icon(Icons.brightness_6_rounded, color: JuzzioGlassTokens.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Text(_app.trEn('Karartma', 'Dim', 'Abdunkeln'),
                          style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Slider(
                          value: _draft.dim,
                          min: 0,
                          max: 0.8,
                          activeColor: JuzzioGlassTokens.glow,
                          onChanged: (v) => setState(() => _draft = _draft.copyWith(dim: v)),
                        ),
                      ),
                    ]),
                  ),
                if (_draft.kind == JuzzioChatBgKind.image)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      Icon(Icons.swap_horiz_rounded, color: JuzzioGlassTokens.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Text(_app.trEn('Konum', 'Position', 'Position'),
                          style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('gm019-align-x'),
                          value: _draft.alignX,
                          min: -1,
                          max: 1,
                          divisions: 20,
                          activeColor: JuzzioGlassTokens.glow,
                          onChanged: (v) => setState(() => _draft = _draft.copyWith(alignX: v)),
                        ),
                      ),
                    ]),
                  ),
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      _swatch(
                        selected: _draft.kind == JuzzioChatBgKind.none,
                        label: _app.trEn('Varsayılan', 'Default', 'Standard'),
                        onTap: () => setState(() => _draft = JuzzioChatBackground.none),
                        child: DecoratedBox(decoration: JuzzioGlassTokens.backdrop, child: const SizedBox.expand()),
                      ),
                      _swatch(
                        selected: _draft.kind == JuzzioChatBgKind.image,
                        label: _app.trEn('Galeriden', 'Gallery', 'Galerie'),
                        onTap: _pickImage,
                        child: _draft.kind == JuzzioChatBgKind.image
                            ? Image.file(File(_draft.imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                            : ColoredBox(
                                color: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.06),
                                child: Icon(Icons.add_photo_alternate_outlined, color: JuzzioGlassTokens.glowText),
                              ),
                      ),
                      for (final p in kJuzzioChatBgPresets)
                        _swatch(
                          selected: _draft.kind == JuzzioChatBgKind.preset && _draft.presetId == p.id,
                          label: name(p),
                          onTap: () => setState(() => _draft = JuzzioChatBackground(kind: JuzzioChatBgKind.preset, presetId: p.id)),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: juzzioChatBgPresetColors(p,
                                    glow: JuzzioGlassTokens.glow, base: depth.isEmpty ? Colors.black : depth.first),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: JuzzioGlassTokens.glow,
                        foregroundColor: JuzzioGlassTokens.onGlow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: _saving ? null : _apply,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(_app.trEn('Kaydet ve uygula', 'Save and apply', 'Speichern und anwenden'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
