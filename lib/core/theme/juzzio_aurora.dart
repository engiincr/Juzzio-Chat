// =============================================================================
// JUZZIO v0.6.0 — Glassmorphism "Aurora" zemin sistemi
//  Buzlu cam yüzeylerin arkasında yumuşak, bulanık renk küreleri: derin koyu
//  zemin + 3-4 ışıma (mavi, ametist, zümrüt, lagün, krom). Turuncu / amber ton
//  hiçbir palette YOKTUR.
//  • JuzzioAuroraBackground       : tam ekran zemin (CustomPainter, tek katman)
//  • JuzzioAuroraPageTransitions  : her sayfanın arkasına aurora zemini koyar,
//                                   iOS tarzı kaydırmalı geçiş korunur
//  • kJuzzioAuroraPalettes        : kullanıcının seçebildiği cam temaları
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// Bir aurora ışıması: konum (Alignment), yarıçap (kısa kenara oran) ve renk.
class JuzzioAuroraOrb {
  final Alignment center;
  final double radius;
  final Color color;
  const JuzzioAuroraOrb(this.center, this.radius, this.color);
}

class JuzzioAuroraPalette {
  final String id;
  final String nameTr;
  final String nameEn;
  final String nameDe;
  final Color base;
  final Color baseLight;
  final List<JuzzioAuroraOrb> orbs;
  final List<JuzzioAuroraOrb> orbsLight;

  /// Seçim kartında ve widget'ta kullanılan iki tonlu önizleme
  final Color swatchA;
  final Color swatchB;

  const JuzzioAuroraPalette({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.nameDe,
    required this.base,
    required this.baseLight,
    required this.orbs,
    required this.orbsLight,
    required this.swatchA,
    required this.swatchB,
  });

  String label(String lang) {
    switch (lang.toLowerCase()) {
      case 'tr':
        return nameTr;
      case 'de':
        return nameDe;
      default:
        return nameEn;
    }
  }
}

/// v0.8.4 Tasarım ailesi: 12 temanın hepsi aynı Liquid Glass bileşenlerini kullanır;
/// yalnızca camın rengi, ışığı, derinliği ve atmosferi (bu "karakter") değişir.
class JuzzioGlassCharacter {
  final String tr;
  final String en;
  final String de;
  /// blur çarpanı (bileşenin temel blur değeri × bu)
  final double blur;
  /// cam dolgu opaklığı çarpanı
  final double opacity;
  /// sol üstten vuran ışık (sheen) yoğunluğu çarpanı
  final double sheen;
  /// gölge/derinlik çarpanı
  final double depth;
  /// kenar ışığının rengi (null → nötr beyaz/yanardöner)
  final Color? rim;
  /// kenarda neon parıltı (0 = yok)
  final double glow;

  const JuzzioGlassCharacter({
    required this.tr,
    required this.en,
    this.de = '',
    this.blur = 1.0,
    this.opacity = 1.0,
    this.sheen = 1.0,
    this.depth = 1.0,
    this.rim,
    this.glow = 0.0,
  });

  static const JuzzioGlassCharacter standard = JuzzioGlassCharacter(tr: 'Liquid Glass', en: 'Liquid Glass');

  String label(String lang) {
    final l = lang.toLowerCase();
    if (l == 'tr') return tr;
    if (l == 'de' && de.isNotEmpty) return de;
    return en;
  }
}

const Map<String, JuzzioGlassCharacter> kJuzzioGlassCharacters = {
  'juzzio_liquid': JuzzioGlassCharacter(tr: 'Yoğun Liquid Glass', en: 'Dense Liquid Glass', de: 'Dichtes Liquid Glass',
      blur: 1.25, opacity: 1.15, sheen: 1.25, depth: 1.1, rim: Color(0xFF20D9F2)),
  'ocean': JuzzioGlassCharacter(tr: 'Koyu mavi Glassmorphism', en: 'Deep blue Glassmorphism', de: 'Tiefblaues Glassmorphism', rim: Color(0xFF60A5FA)),
  'glass_white': JuzzioGlassCharacter(tr: 'Şeffaf, açık renkli Glassmorphism', en: 'Clear, light Glassmorphism', de: 'Klares, helles Glassmorphism',
      blur: 1.1, opacity: 0.75, sheen: 1.4, depth: 0.8, rim: Color(0xFFFFFFFF)),
  'amethyst': JuzzioGlassCharacter(tr: 'Mor tonlu Liquid Glass', en: 'Violet Liquid Glass', de: 'Violettes Liquid Glass',
      blur: 1.2, opacity: 1.1, sheen: 1.2, rim: Color(0xFFC084FC)),
  'emerald': JuzzioGlassCharacter(tr: 'Yeşil tonlu Glassmorphism', en: 'Emerald Glassmorphism', de: 'Smaragdgrünes Glassmorphism', rim: Color(0xFF34D399)),
  'lagoon': JuzzioGlassCharacter(tr: 'Turkuaz cam efekti', en: 'Turquoise glass', de: 'Türkisglas',
      blur: 1.05, opacity: 0.95, sheen: 1.1, rim: Color(0xFF2DD4BF)),
  'chrome': JuzzioGlassCharacter(tr: 'Metalik yansımalı Liquid Glass', en: 'Metallic Liquid Glass', de: 'Metallisch spiegelndes Liquid Glass',
      blur: 1.1, opacity: 1.1, sheen: 1.8, depth: 1.2, rim: Color(0xFFE5E7EB)),
  'obsidian_oled': JuzzioGlassCharacter(tr: 'Siyah, OLED odaklı cam katmanları', en: 'Black OLED glass layers', de: 'Schwarze OLED-Glasschichten',
      blur: 0.8, opacity: 0.7, sheen: 0.6, depth: 1.4, rim: Color(0xFF6B7280)),
  'lavender_mist': JuzzioGlassCharacter(tr: 'Yumuşak, pastel Glassmorphism', en: 'Soft pastel Glassmorphism', de: 'Sanftes Pastell-Glassmorphism',
      blur: 1.3, opacity: 0.9, sheen: 1.1, depth: 0.8, rim: Color(0xFFDDD6FE)),
  'rose_quartz': JuzzioGlassCharacter(tr: 'Pembe, yarı saydam cam', en: 'Pink translucent glass', de: 'Rosa, durchscheinendes Glas',
      blur: 1.15, opacity: 0.95, sheen: 1.15, rim: Color(0xFFF9A8D4)),
  'cyber_neon': JuzzioGlassCharacter(tr: 'Neon ışıklı Liquid Glass', en: 'Neon Liquid Glass', de: 'Neon-Liquid-Glass',
      blur: 1.2, sheen: 1.0, rim: Color(0xFF22D3EE), glow: 0.35),
  'high_contrast': JuzzioGlassCharacter(tr: 'Erişilebilirlik odaklı, belirgin yüzeyler', en: 'Accessible, distinct surfaces', de: 'Barrierefreie, klare Flächen',
      blur: 0.6, opacity: 1.8, sheen: 0.5),
};

extension JuzzioAuroraPaletteCharacter on JuzzioAuroraPalette {
  JuzzioGlassCharacter get character => kJuzzioGlassCharacters[id] ?? JuzzioGlassCharacter.standard;
}

/// Cam temaları. İlk öğe varsayılandır.
const List<JuzzioAuroraPalette> kJuzzioAuroraPalettes = [
  // v0.8.1 Premium Dark Liquid Glass (tasarım şartnamesi §2/§9): #050A12 zemin,
  // sol üstte cyan, sağda electric blue, altta derin turkuaz, hafif aurora moru.
  JuzzioAuroraPalette(
    id: 'juzzio_liquid',
    nameTr: 'Juzzio Sıvı Cam',
    nameEn: 'Juzzio Liquid Glass',
    nameDe: 'Juzzio Liquid Glass',
    base: Color(0xFF050A12),
    baseLight: Color(0xFFEAF6FB),
    swatchA: Color(0xFF20D9F2),
    swatchB: Color(0xFF397BFF),
    orbs: [
      JuzzioAuroraOrb(Alignment(-1.0, -0.85), 0.85, Color(0x5220D9F2)),
      JuzzioAuroraOrb(Alignment(1.05, -0.05), 0.80, Color(0x52397BFF)),
      JuzzioAuroraOrb(Alignment(-0.6, 1.05), 0.85, Color(0x66075B76)),
      JuzzioAuroraOrb(Alignment(0.85, 0.95), 0.45, Color(0x2E925CFF)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-1.0, -0.85), 0.90, Color(0x5520D9F2)),
      JuzzioAuroraOrb(Alignment(1.05, -0.05), 0.80, Color(0x40397BFF)),
      JuzzioAuroraOrb(Alignment(-0.6, 1.05), 0.85, Color(0x406BDDF0)),
      JuzzioAuroraOrb(Alignment(0.85, 0.95), 0.45, Color(0x26925CFF)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'ocean',
    nameTr: 'Gece Mavisi',
    nameEn: 'Midnight Blue',
    nameDe: 'Nachtblau',
    base: Color(0xFF03060F),
    baseLight: Color(0xFFEAF0FA),
    swatchA: Color(0xFF1D4ED8),
    swatchB: Color(0xFF0EA5E9),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.75), 0.95, Color(0xB31D4ED8)),
      JuzzioAuroraOrb(Alignment(1.0, -0.1), 0.80, Color(0x800EA5E9)),
      JuzzioAuroraOrb(Alignment(-0.4, 0.95), 0.90, Color(0x993730A3)),
      JuzzioAuroraOrb(Alignment(0.7, 0.85), 0.55, Color(0x661E40AF)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.75), 0.95, Color(0x6693C5FD)),
      JuzzioAuroraOrb(Alignment(1.0, -0.1), 0.80, Color(0x5567E8F9)),
      JuzzioAuroraOrb(Alignment(-0.4, 0.95), 0.90, Color(0x55A5B4FC)),
    ],
  ),
  // v0.7.0: Glass White — ultra modern, saydam beyaz buzlu cam (iOS/visionOS esintili).
  // Aydınlık modda inci beyazı zemin + pastel yanardöner ışık; karanlık modda derin
  // grafit üstünde süt beyazı cam ışıltısı.
  JuzzioAuroraPalette(
    id: 'glass_white',
    nameTr: 'Cam Beyaz',
    nameEn: 'Glass White',
    nameDe: 'Glasweiß',
    base: Color(0xFF0B0C10),
    baseLight: Color(0xFFF7F8FC),
    swatchA: Color(0xFFFFFFFF),
    swatchB: Color(0xFFDDE3F0),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.85), 0.95, Color(0x40FFFFFF)),
      JuzzioAuroraOrb(Alignment(0.95, -0.2), 0.80, Color(0x33C7D2FE)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.90, Color(0x2EF5D0FE)),
      JuzzioAuroraOrb(Alignment(0.75, 0.9), 0.55, Color(0x29BAE6FD)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.85), 0.95, Color(0x66BAE6FD)),
      JuzzioAuroraOrb(Alignment(0.95, -0.2), 0.80, Color(0x55E9D5FF)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.90, Color(0x55FBCFE8)),
      JuzzioAuroraOrb(Alignment(0.7, 0.85), 0.60, Color(0x66FFFFFF)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'amethyst',
    nameTr: 'Ametist',
    nameEn: 'Amethyst',
    nameDe: 'Amethyst',
    base: Color(0xFF07040F),
    baseLight: Color(0xFFF1EDFA),
    swatchA: Color(0xFF6D28D9),
    swatchB: Color(0xFF4338CA),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.85, -0.8), 0.95, Color(0xA66D28D9)),
      JuzzioAuroraOrb(Alignment(0.95, 0.0), 0.80, Color(0x804338CA)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.85, Color(0x807C3AED)),
      JuzzioAuroraOrb(Alignment(0.8, -0.9), 0.45, Color(0x552563EB)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.85, -0.8), 0.95, Color(0x55C4B5FD)),
      JuzzioAuroraOrb(Alignment(0.95, 0.0), 0.80, Color(0x55A5B4FC)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.85, Color(0x44DDD6FE)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'emerald',
    nameTr: 'Zümrüt',
    nameEn: 'Emerald',
    nameDe: 'Smaragd',
    base: Color(0xFF020805),
    baseLight: Color(0xFFEAF6EF),
    swatchA: Color(0xFF16A34A),
    swatchB: Color(0xFF065F46),
    orbs: [
      JuzzioAuroraOrb(Alignment(0.9, -0.85), 0.90, Color(0x9916A34A)),
      JuzzioAuroraOrb(Alignment(-1.0, 0.1), 0.85, Color(0x80065F46)),
      JuzzioAuroraOrb(Alignment(0.3, 1.0), 0.80, Color(0x7722C55E)),
      JuzzioAuroraOrb(Alignment(-0.6, -1.0), 0.45, Color(0x55047857)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(0.9, -0.85), 0.90, Color(0x5586EFAC)),
      JuzzioAuroraOrb(Alignment(-1.0, 0.1), 0.85, Color(0x446EE7B7)),
      JuzzioAuroraOrb(Alignment(0.3, 1.0), 0.80, Color(0x44BBF7D0)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'lagoon',
    nameTr: 'Lagün',
    nameEn: 'Lagoon',
    nameDe: 'Lagune',
    base: Color(0xFF02080B),
    baseLight: Color(0xFFE8F4F6),
    swatchA: Color(0xFF0E7490),
    swatchB: Color(0xFF14B8A6),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.7), 0.90, Color(0x990E7490)),
      JuzzioAuroraOrb(Alignment(0.95, 0.15), 0.80, Color(0x7714B8A6)),
      JuzzioAuroraOrb(Alignment(-0.2, 1.0), 0.85, Color(0x771E3A8A)),
      JuzzioAuroraOrb(Alignment(0.6, -1.0), 0.45, Color(0x5506B6D4)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.7), 0.90, Color(0x5567E8F9)),
      JuzzioAuroraOrb(Alignment(0.95, 0.15), 0.80, Color(0x4499F6E4)),
      JuzzioAuroraOrb(Alignment(-0.2, 1.0), 0.85, Color(0x44BFDBFE)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'chrome',
    nameTr: 'Krom',
    nameEn: 'Chrome',
    nameDe: 'Chrom',
    base: Color(0xFF09090B),
    baseLight: Color(0xFFF2F2F5),
    swatchA: Color(0xFF8E8E93),
    swatchB: Color(0xFF3A3A3C),
    orbs: [
      JuzzioAuroraOrb(Alignment(0.85, -0.8), 0.80, Color(0x55D1D1D6)),
      JuzzioAuroraOrb(Alignment(-1.0, 0.2), 0.85, Color(0x4D8E8E93)),
      JuzzioAuroraOrb(Alignment(0.2, 1.0), 0.80, Color(0x40AEAEB2)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(0.85, -0.8), 0.80, Color(0x55FFFFFF)),
      JuzzioAuroraOrb(Alignment(-1.0, 0.2), 0.85, Color(0x33C7C7CC)),
      JuzzioAuroraOrb(Alignment(0.2, 1.0), 0.80, Color(0x33D1D1D6)),
    ],
  ),
  // v0.8.1 tema kataloğu genişletmesi (turuncu ton yok)
  JuzzioAuroraPalette(
    id: 'obsidian_oled',
    nameTr: 'Obsidyen OLED',
    nameEn: 'Obsidian OLED',
    nameDe: 'Obsidian OLED',
    base: Color(0xFF000000),
    baseLight: Color(0xFFF4F5F7),
    swatchA: Color(0xFF0A0A0A),
    swatchB: Color(0xFF3A3A40),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.9), 0.6, Color(0x1A3A3A40)),
      JuzzioAuroraOrb(Alignment(0.9, 0.9), 0.5, Color(0x14303036)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.9), 0.8, Color(0x33C7CBD4)),
      JuzzioAuroraOrb(Alignment(0.9, 0.9), 0.7, Color(0x26DDE1E8)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'lavender_mist',
    nameTr: 'Lavanta Sisi',
    nameEn: 'Lavender Mist',
    nameDe: 'Lavendelnebel',
    base: Color(0xFF0B0814),
    baseLight: Color(0xFFF3F0FB),
    swatchA: Color(0xFFA78BFA),
    swatchB: Color(0xFFC4B5FD),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.7), 0.9, Color(0x66A78BFA)),
      JuzzioAuroraOrb(Alignment(1.0, 0.0), 0.75, Color(0x52C4B5FD)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.8, Color(0x4D6D28D9)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.7), 0.95, Color(0x66DDD6FE)),
      JuzzioAuroraOrb(Alignment(1.0, 0.0), 0.8, Color(0x55C4B5FD)),
      JuzzioAuroraOrb(Alignment(-0.3, 1.0), 0.8, Color(0x40E9D5FF)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'rose_quartz',
    nameTr: 'Gül Kuvars',
    nameEn: 'Rose Quartz',
    nameDe: 'Rosenquarz',
    base: Color(0xFF120810),
    baseLight: Color(0xFFFBF0F5),
    swatchA: Color(0xFFF472B6),
    swatchB: Color(0xFFF9A8D4),
    orbs: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.8), 0.9, Color(0x5CF472B6)),
      JuzzioAuroraOrb(Alignment(1.0, -0.1), 0.75, Color(0x47F9A8D4)),
      JuzzioAuroraOrb(Alignment(-0.4, 1.0), 0.85, Color(0x47A21CAF)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-0.9, -0.8), 0.95, Color(0x66FBCFE8)),
      JuzzioAuroraOrb(Alignment(1.0, -0.1), 0.8, Color(0x55F9A8D4)),
      JuzzioAuroraOrb(Alignment(-0.4, 1.0), 0.85, Color(0x40F5D0FE)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'cyber_neon',
    nameTr: 'Siber Neon',
    nameEn: 'Cyber Neon',
    nameDe: 'Cyber-Neon',
    base: Color(0xFF03040A),
    baseLight: Color(0xFFEEF6FF),
    swatchA: Color(0xFF22D3EE),
    swatchB: Color(0xFFD946EF),
    orbs: [
      JuzzioAuroraOrb(Alignment(-1.0, -0.8), 0.8, Color(0x5922D3EE)),
      JuzzioAuroraOrb(Alignment(1.0, 0.2), 0.75, Color(0x52D946EF)),
      JuzzioAuroraOrb(Alignment(-0.2, 1.05), 0.7, Color(0x473B82F6)),
    ],
    orbsLight: [
      JuzzioAuroraOrb(Alignment(-1.0, -0.8), 0.85, Color(0x4D67E8F9)),
      JuzzioAuroraOrb(Alignment(1.0, 0.2), 0.8, Color(0x40F0ABFC)),
      JuzzioAuroraOrb(Alignment(-0.2, 1.05), 0.75, Color(0x4093C5FD)),
    ],
  ),
  JuzzioAuroraPalette(
    id: 'high_contrast',
    nameTr: 'Yüksek Kontrast',
    nameEn: 'High Contrast',
    nameDe: 'Hoher Kontrast',
    base: Color(0xFF000000),
    baseLight: Color(0xFFFFFFFF),
    swatchA: Color(0xFF000000),
    swatchB: Color(0xFFFFFFFF),
    orbs: [

    ],
    orbsLight: [

    ],
  ),
];

JuzzioAuroraPalette juzzioAuroraPaletteById(String? id) {
  for (final p in kJuzzioAuroraPalettes) {
    if (p.id == id) return p;
  }
  return kJuzzioAuroraPalettes.first;
}

/// Aurora zemini. [palette] ve [dark] dışarıdan verilir (tema denetleyicisine
/// bağımlılık yoktur; çağıran taraf seçimi geçirir).
class JuzzioAuroraBackground extends StatelessWidget {
  final JuzzioAuroraPalette palette;
  final bool dark;
  final Widget? child;

  const JuzzioAuroraBackground({super.key, required this.palette, required this.dark, this.child});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _JuzzioAuroraPainter(palette: palette, dark: dark),
        isComplex: true,
        willChange: false,
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _JuzzioAuroraPainter extends CustomPainter {
  final JuzzioAuroraPalette palette;
  final bool dark;

  _JuzzioAuroraPainter({required this.palette, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = dark ? palette.base : palette.baseLight);
    final shortest = math.min(size.width, size.height);
    final longest = math.max(size.width, size.height);
    for (final orb in dark ? palette.orbs : palette.orbsLight) {
      final c = orb.center.alongSize(size);
      final r = orb.radius * (shortest * 0.55 + longest * 0.30);
      final transparent = orb.color.withValues(alpha: 0);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [orb.color, orb.color.withValues(alpha: orb.color.a * 0.45), transparent],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }
    // Camın üstüne vuran ince ışık süzmesi (sol üst → sağ alt)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0x0FFFFFFF), Color(0x00FFFFFF), Color(0x24000000)]
              : const [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x0A000000)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _JuzzioAuroraPainter oldDelegate) =>
      oldDelegate.palette.id != palette.id || oldDelegate.dark != dark;
}

/// Seçili paleti ve gece/gündüz modunu veren kaynak (tema denetleyicisi atar).
class JuzzioAuroraScope {
  JuzzioAuroraScope._();
  static JuzzioAuroraPalette Function() palette = () => kJuzzioAuroraPalettes.first;
  static bool Function() isDark = () => true;
  static Listenable? listenable;
  /// v0.8.2: hareket azaltılmışsa tema arka planı anında değişir
  static bool Function() reduceMotion = () => false;
}

/// Sayfanın arkasına aurora zemini çizen sarmalayıcı (ayar değişince yenilenir).
class JuzzioAuroraPage extends StatelessWidget {
  final Widget child;
  const JuzzioAuroraPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget bg() => JuzzioAuroraBackground(
          palette: JuzzioAuroraScope.palette(),
          dark: JuzzioAuroraScope.isDark(),
        );
    final l = JuzzioAuroraScope.listenable;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          // v0.8.2: tema değişiminde arka plan yumuşak geçer (ani renk sıçraması yok)
          child: l == null
              ? bg()
              : ListenableBuilder(
                  listenable: l,
                  builder: (_, __) {
                    final pal = JuzzioAuroraScope.palette();
                    final dark = JuzzioAuroraScope.isDark();
                    return AnimatedSwitcher(
                      duration: JuzzioAuroraScope.reduceMotion() ? Duration.zero : const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
                      // özel temada düzenleme sırasında her değişiklikte çapraz geçiş yapılmaz
                      child: KeyedSubtree(
                          key: ValueKey('${pal.id.startsWith('custom:') ? pal.id.split(':').take(2).join(':') : pal.id}|$dark'),
                          child: bg()),
                    );
                  },
                ),
        ),
        child,
      ],
    );
  }
}

/// iOS tarzı kaydırmalı geçişi korur; her sayfa kendi aurora zeminiyle opak
/// çizildiği için saydam sayfalar geçiş sırasında üst üste binmez.
class JuzzioAuroraPageTransitionsBuilder extends PageTransitionsBuilder {
  const JuzzioAuroraPageTransitionsBuilder();

  static const CupertinoPageTransitionsBuilder _inner = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _inner.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final wrapped = route.opaque ? JuzzioAuroraPage(child: child) : child;
    return _inner.buildTransitions<T>(route, context, animation, secondaryAnimation, wrapped);
  }
}
