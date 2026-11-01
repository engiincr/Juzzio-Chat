// =============================================================================
// JUZZIO v0.8.2 — Tema Stüdyosu veri modeli
// Kullanıcının oluşturduğu temalar: sürümlü şema, 12 renk rolü, cam ayarları,
// güvenli JSON içe/dışa aktarma. Veritabanı gerektirmez; kullanıcının tercih
// dosyasında (ve şifreli Drive yedeğinde) saklanır.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show Alignment;

import 'juzzio_aurora.dart';

class JuzzioCustomTheme {
  static const String schema = 'juzzio-theme';
  static const int version = 1;
  static const int maxJsonBytes = 16 * 1024;
  static const int maxNameLength = 40;

  static const double blurMin = 6, blurMax = 30;
  static const double opacityMin = 0.04, opacityMax = 0.7;
  static const double intensityMin = 0.6, intensityMax = 1.4;

  /// Renk rolleri (JSON anahtarı → Türkçe etiket)
  static const Map<String, String> colorRoles = {
    'background': 'Arka plan',
    'gradientA': 'Gradyan 1',
    'gradientB': 'Gradyan 2',
    'gradientC': 'Gradyan 3',
    'text': 'Metin',
    'heading': 'Başlık',
    'button': 'Buton',
    'buttonText': 'Buton yazısı',
    'card': 'Kart / cam tonu',
    'bubbleOut': 'Giden balon',
    'bubbleIn': 'Gelen balon',
    'icon': 'İkon',
    'border': 'Kenarlık',
  };

  final String id;
  final String name;
  final bool dark;
  final bool gradient;
  final Map<String, Color> colors;
  final double blur;
  final double opacity;
  final double intensity;

  const JuzzioCustomTheme({
    required this.id,
    required this.name,
    required this.dark,
    required this.gradient,
    required this.colors,
    required this.blur,
    required this.opacity,
    required this.intensity,
  });

  Color c(String role) => colors[role] ?? _defaults(dark)[role]!;
  Color get background => c('background');
  Color get text => c('text');
  Color get heading => c('heading');
  Color get button => c('button');
  Color get buttonText => c('buttonText');
  Color get card => c('card');
  Color get bubbleOut => c('bubbleOut');
  Color get bubbleIn => c('bubbleIn');
  Color get icon => c('icon');
  Color get border => c('border');

  static Map<String, Color> _defaults(bool dark) => dark
      ? const {
          'background': Color(0xFF050A12),
          'gradientA': Color(0xFF20D9F2),
          'gradientB': Color(0xFF397BFF),
          'gradientC': Color(0xFF925CFF),
          'text': Color(0xFFF5F9FF),
          'heading': Color(0xFFFFFFFF),
          'button': Color(0xFF20D9F2),
          'buttonText': Color(0xFF041018),
          'card': Color(0xFF101B2A),
          'bubbleOut': Color(0xFF1E6FD9),
          'bubbleIn': Color(0xFF172536),
          'icon': Color(0xFFDDE7F5),
          'border': Color(0x40FFFFFF),
        }
      : const {
          'background': Color(0xFFEEF4FA),
          'gradientA': Color(0xFF6BDDF0),
          'gradientB': Color(0xFF93B4FF),
          'gradientC': Color(0xFFC9B2FF),
          'text': Color(0xFF111827),
          'heading': Color(0xFF0B1220),
          'button': Color(0xFF1F5FD6),
          'buttonText': Color(0xFFFFFFFF),
          'card': Color(0xFFFFFFFF),
          'bubbleOut': Color(0xFF2563EB),
          'bubbleIn': Color(0xFFFFFFFF),
          'icon': Color(0xFF1F2937),
          'border': Color(0x99FFFFFF),
        };

  /// Sıfırdan yeni tema (güvenli varsayılanlarla)
  factory JuzzioCustomTheme.blank({required String id, String name = 'Yeni tema', bool dark = true}) =>
      JuzzioCustomTheme(
        id: id,
        name: name,
        dark: dark,
        gradient: true,
        colors: Map<String, Color>.from(_defaults(dark)),
        blur: 18,
        opacity: 0.30,
        intensity: 1.0,
      );

  /// Mevcut hazır cam temasından başlangıç
  factory JuzzioCustomTheme.fromPalette({required String id, required String name, required JuzzioAuroraPalette palette, required bool dark}) {
    final base = Map<String, Color>.from(_defaults(dark));
    base['background'] = dark ? palette.base : palette.baseLight;
    base['gradientA'] = palette.swatchA;
    base['gradientB'] = palette.swatchB;
    final orbs = dark ? palette.orbs : palette.orbsLight;
    if (orbs.length > 2) base['gradientC'] = orbs[2].color.withValues(alpha: 1);
    base['bubbleOut'] = palette.swatchA;
    return JuzzioCustomTheme(id: id, name: name, dark: dark, gradient: orbs.isNotEmpty, colors: base, blur: 18, opacity: 0.30, intensity: 1.0);
  }

  JuzzioCustomTheme copyWith({
    String? id,
    String? name,
    bool? dark,
    bool? gradient,
    Map<String, Color>? colors,
    double? blur,
    double? opacity,
    double? intensity,
  }) =>
      JuzzioCustomTheme(
        id: id ?? this.id,
        name: name ?? this.name,
        dark: dark ?? this.dark,
        gradient: gradient ?? this.gradient,
        colors: colors ?? this.colors,
        blur: (blur ?? this.blur).clamp(blurMin, blurMax).toDouble(),
        opacity: (opacity ?? this.opacity).clamp(opacityMin, opacityMax).toDouble(),
        intensity: (intensity ?? this.intensity).clamp(intensityMin, intensityMax).toDouble(),
      );

  JuzzioCustomTheme withColor(String role, Color color) =>
      copyWith(colors: Map<String, Color>.from(colors)..[role] = color);

  /// Aurora arka planı. Kimlik değerlerden türetilir; düzenlerken anında yeniden çizilir.
  JuzzioAuroraPalette toPalette() {
    final a = c('gradientA'), b = c('gradientB'), cc = c('gradientC');
    final orbs = gradient
        ? [
            JuzzioAuroraOrb(const Alignment(-0.95, -0.8), 0.9, a.withValues(alpha: dark ? 0.42 : 0.40)),
            JuzzioAuroraOrb(const Alignment(1.0, -0.05), 0.8, b.withValues(alpha: dark ? 0.40 : 0.36)),
            JuzzioAuroraOrb(const Alignment(-0.4, 1.0), 0.85, cc.withValues(alpha: dark ? 0.36 : 0.32)),
          ]
        : const <JuzzioAuroraOrb>[];
    return JuzzioAuroraPalette(
      id: 'custom:$id:$fingerprint',
      nameTr: name,
      nameEn: name,
      nameDe: name,
      base: background,
      baseLight: background,
      orbs: orbs,
      orbsLight: orbs,
      swatchA: a,
      swatchB: b,
    );
  }

  int get fingerprint => Object.hash(
        dark,
        gradient,
        blur,
        opacity,
        intensity,
        Object.hashAll(colorRoles.keys.map((k) => c(k).toARGB32())),
      );

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------
  Map<String, dynamic> toJson() => {
        'schema': schema,
        'version': version,
        'id': id,
        'name': name,
        'mode': dark ? 'dark' : 'light',
        'gradient': gradient,
        'colors': {for (final k in colorRoles.keys) k: toHex(c(k))},
        'glass': {'blur': blur, 'opacity': opacity, 'intensity': intensity},
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static String toHex(Color c) {
    final v = c.toARGB32();
    final a = (v >> 24) & 0xFF;
    final rgb = (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    return a == 0xFF ? '#$rgb' : '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb';
  }

  static final RegExp _hexRe = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

  /// "#RRGGBB" veya "#AARRGGBB" → Color; geçersizse null
  static Color? parseHex(String? s) {
    if (s == null) return null;
    final m = _hexRe.firstMatch(s.trim());
    if (m == null) return null;
    final h = m.group(1)!;
    final v = int.parse(h, radix: 16);
    return Color(h.length == 6 ? (0xFF000000 | v) : v);
  }

  static String sanitizeName(String? raw) {
    final cleaned = (raw ?? '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F<>{}\\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Özel tema';
    return cleaned.length > maxNameLength ? cleaned.substring(0, maxNameLength).trim() : cleaned;
  }

  /// Güvenli içe aktarma. Hatalar varsa tema null döner; uyarılar (eksik renk
  /// tamamlandı, sınır dışı değer sınırlandı) bilgilendirme amaçlıdır.
  static JuzzioThemeParseResult parse(String raw, {required String newId}) {
    final errors = <String>[];
    final warnings = <String>[];
    if (utf8.encode(raw).length > maxJsonBytes) {
      return JuzzioThemeParseResult(null, ['Dosya çok büyük (en fazla 16 KB).'], warnings);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      return JuzzioThemeParseResult(null, ['Geçersiz JSON biçimi.'], warnings);
    }
    if (decoded is! Map) return JuzzioThemeParseResult(null, ['JSON bir nesne olmalı.'], warnings);
    final map = Map<String, dynamic>.from(decoded);
    return fromMap(map, newId: newId, errors: errors, warnings: warnings);
  }

  static JuzzioThemeParseResult fromMap(Map<String, dynamic> map,
      {required String newId, List<String>? errors, List<String>? warnings}) {
    final err = errors ?? <String>[];
    final warn = warnings ?? <String>[];
    if (map['schema'] != schema) err.add('Bu bir Juzzio teması değil (schema).');
    final ver = map['version'];
    if (ver is! int || ver < 1) {
      err.add('Geçersiz sürüm.');
    } else if (ver > version) {
      err.add('Bu tema daha yeni bir Juzzio sürümüyle oluşturulmuş (v$ver).');
    }
    final mode = map['mode'];
    final dark = mode != 'light';
    if (mode != null && mode != 'light' && mode != 'dark') warn.add('Bilinmeyen mod; koyu kabul edildi.');
    final defaults = _defaults(dark);
    final colorsRaw = map['colors'];
    final colors = <String, Color>{};
    if (colorsRaw is! Map) {
      err.add('"colors" alanı eksik veya geçersiz.');
    } else {
      for (final role in colorRoles.keys) {
        final v = colorsRaw[role];
        if (v == null) {
          colors[role] = defaults[role]!;
          warn.add('Eksik renk tamamlandı: ${colorRoles[role]}');
          continue;
        }
        final parsed = v is String ? parseHex(v) : null;
        if (parsed == null) {
          err.add('Geçersiz HEX: ${colorRoles[role]} ("$v")');
        } else {
          colors[role] = parsed;
        }
      }
    }
    double glassNum(String key, double def, double lo, double hi) {
      final glass = map['glass'];
      final v = glass is Map ? glass[key] : null;
      if (v == null) return def;
      if (v is! num || !v.isFinite) {
        err.add('Geçersiz sayı: $key');
        return def;
      }
      final d = v.toDouble();
      if (d < lo || d > hi) {
        warn.add('$key sınır dışı (${d.toStringAsFixed(2)}); ${lo.toStringAsFixed(2)}–${hi.toStringAsFixed(2)} aralığına alındı.');
      }
      return d.clamp(lo, hi).toDouble();
    }

    final blur = glassNum('blur', 18, blurMin, blurMax);
    final opacity = glassNum('opacity', 0.30, opacityMin, opacityMax);
    final intensity = glassNum('intensity', 1.0, intensityMin, intensityMax);
    final gradient = map['gradient'] is bool ? map['gradient'] as bool : true;
    if (err.isNotEmpty) return JuzzioThemeParseResult(null, err, warn);
    return JuzzioThemeParseResult(
      JuzzioCustomTheme(
        id: newId,
        name: sanitizeName(map['name']?.toString()),
        dark: dark,
        gradient: gradient,
        colors: colors,
        blur: blur,
        opacity: opacity,
        intensity: intensity,
      ),
      err,
      warn,
    );
  }

  /// Kayıtlı veriyi okurken (kendi kaydımız): kimlik korunur
  static JuzzioCustomTheme? fromStored(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id']?.toString() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{4,40}$').hasMatch(id)) return null;
    return fromMap(m, newId: id).theme;
  }

  // ---------------------------------------------------------------------------
  // Erişilebilirlik: WCAG 2.x kontrast oranı
  // ---------------------------------------------------------------------------
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Metin rengi ile arka plan arasında en az 4.5:1 (WCAG AA) var mı?
  bool get textReadable => contrastRatio(text, background) >= 4.5;
}

class JuzzioThemeParseResult {
  final JuzzioCustomTheme? theme;
  final List<String> errors;
  final List<String> warnings;
  const JuzzioThemeParseResult(this.theme, this.errors, this.warnings);
  bool get ok => theme != null && errors.isEmpty;
}
