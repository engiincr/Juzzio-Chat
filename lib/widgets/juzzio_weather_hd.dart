// =============================================================================
// JUZZIO v2.2.0 — GM-030: HD şeffaf hava görselleri (Sohbetler ekranı)
//  Engin'in paketindeki gerçek RGBA görseller (assets/weather_hd/*.webp, kalite 92, özgün
//  çözünürlük — kalite düşürülmedi) referans ekranlardaki yerleşimle çizilir:
//   • Açık/gündüz: başlığın sağında bulutların arkasından doğan güneş + iki yumuşak bulut
//   • Açık/gece: konumun gerçek ay evresi (8 evre görseli) + göz kırpan yıldızlar
//   • Bulutlu: beyaz (gündüz) / koyu fırtına (gece) bulutları yavaşça süzülür
//   • Sis: sis bankası + alçak sis, çok yavaş yatay kayma
//   • Çisenti/yağmur: yağmur bulutları + düşen yağmur katmanı (tüm ekranda hafif)
//   • Kar: kar bulutları + düşen kar taneleri
//   • Fırtına: şimşek bulutu + yağmur + 100–160 ms'lik kısa şimşek flaşları
//  "Hareketi azalt" açıkken her şey durağan çizilir. Katman dokunmayı engellemez (IgnorePointer).
//
//  GM-029 / GM-031: Özel gün temaları (Türk bayrağı, Halloween) etkinken hava katmanı ÇİZİLMEZ;
//  yerine özel tema dekoru gelir (JuzzioSpecialThemeLayer). Yalnız yönetici panelinden açılır.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/juzzio_special_themes.dart';
import '../services/juzzio_weather_service.dart';

/// Ay evresi görseli (0 = yeni ay … 4 = dolunay … 7 = küçülen hilal) — juzzioMoonPhaseIndex ile aynı sıra
const List<String> kJuzzioHdMoonAssets = [
  'assets/weather_hd/moon_0_new.webp',
  'assets/weather_hd/moon_1_waxing_crescent.webp',
  'assets/weather_hd/moon_2_first_quarter.webp',
  'assets/weather_hd/moon_3_waxing_gibbous.webp',
  'assets/weather_hd/moon_4_full.webp',
  'assets/weather_hd/moon_5_waning_gibbous.webp',
  'assets/weather_hd/moon_6_last_quarter.webp',
  'assets/weather_hd/moon_7_waning_crescent.webp',
];

const String kHdCloudWhite = 'assets/weather_hd/cloud_white.webp';
const String kHdCloudStorm = 'assets/weather_hd/cloud_storm.webp';
const String kHdSunRise = 'assets/weather_hd/sun_rise_clouds.webp';
const String kHdSunRays = 'assets/weather_hd/sun_rays.webp';
const String kHdSnowFlakes = 'assets/weather_hd/snow_flakes.webp';
const String kHdSnowLight = 'assets/weather_hd/snow_light.webp';
const String kHdBolt = 'assets/weather_hd/lightning_bolt.webp';
const String kHdBoltCloud = 'assets/weather_hd/lightning_cloud.webp';
const String kHdFogBank = 'assets/weather_hd/fog_bank.webp';
const String kHdFogLow = 'assets/weather_hd/fog_low.webp';
const String kHdRainCloud = 'assets/weather_hd/rain_cloud.webp';
const String kHdRainHeavy = 'assets/weather_hd/rain_heavy.webp';

/// Tüm HD görseller (pubspec ve testler için)
const List<String> kJuzzioHdWeatherAssets = [
  ...kJuzzioHdMoonAssets,
  kHdCloudWhite, kHdCloudStorm, kHdSunRise, kHdSunRays, kHdSnowFlakes, kHdSnowLight,
  kHdBolt, kHdBoltCloud, kHdFogBank, kHdFogLow, kHdRainCloud, kHdRainHeavy,
];

/// Görselin özgün en/boy oranı (yükseklik = genişlik / oran)
const Map<String, double> kJuzzioHdAspect = {
  kHdCloudWhite: 2048 / 1250,
  kHdCloudStorm: 2048 / 1250,
  kHdSunRise: 2048 / 1536,
  kHdSunRays: 2048 / 1536,
  kHdSnowFlakes: 1.0,
  kHdSnowLight: 1.0,
  kHdBolt: 2048 / 1536,
  kHdBoltCloud: 1536 / 2048, // pakette "Kar_Bulutu" adıyla gelen şimşekli bulut (GM-037)
  kHdFogBank: 2048 / 1200,
  kHdFogLow: 2048 / 900,
  kHdRainCloud: 1536 / 2048,
  kHdRainHeavy: 1536 / 2048,
};

/// Sahnedeki bir görsel katmanı. Konum ve genişlik, sahne bandına (genişlik W, yükseklik B) göre oran.
class JuzzioHdLayer {
  const JuzzioHdLayer(this.asset,
      {required this.left, required this.top, required this.width, this.opacity = 1, this.drift = 0, this.fall = false, this.flip = false, this.tint});
  final String asset;
  final double left;
  final double top;
  final double width;
  final double opacity;

  /// Yatay süzülme genliği (genişliğin oranı); 0 = durağan
  final double drift;

  /// Yukarıdan aşağı sürekli düşen katman (yağmur, kar) — yatayda da döşenir
  final bool fall;

  /// GM-037: yatay aynalama. Paketteki bulutların bir kenarı düz kesik; o kenar her zaman
  /// ekranın DIŞINDA kalacak şekilde aynalanıp konumlanır (ekranda kesik görünmez).
  final bool flip;

  /// İsteğe bağlı renk çarpanı (karanlık temada gündüz bulutları referanstaki gibi gri-mavi)
  final Color? tint;
}

/// Hava türüne göre referans ekranlardaki yerleşim (saf; test edilir)
List<JuzzioHdLayer> juzzioHdWeatherLayers(JuzzioWeatherKind kind, {required bool night, required bool dark, required int moonIndex}) {
  final storm = dark ? 1.0 : 0.80; // açık temada koyu bulutlar biraz hafifler
  final moon = kJuzzioHdMoonAssets[moonIndex.clamp(0, 7)];
  // Kural (GM-037): düz kesik kenarlı bulutların o kenarı ekran dışında kalır (left < 0 veya
  // left + width > 1); her iki kenarı kesik olan fırtına bulutu ekranı taşacak genişlikte çizilir.
  switch (kind) {
    case JuzzioWeatherKind.clear:
      if (night) {
        return [
          JuzzioHdLayer(moon, left: 0.62, top: 0.05, width: 0.28),
          JuzzioHdLayer(kHdCloudWhite, left: -0.32, top: 0.58, width: 0.66, opacity: 0.16, drift: 0.02, flip: true),
        ];
      }
      final dayTint = dark ? const Color(0xFF8E98AC) : null; // referans: koyu temada gri-mavi bulut
      return [
        const JuzzioHdLayer(kHdSunRise, left: 0.20, top: 0.06, width: 0.98),
        JuzzioHdLayer(kHdCloudWhite, left: -0.30, top: 0.40, width: 0.62, opacity: 0.70, drift: 0.02, flip: true, tint: dayTint),
        JuzzioHdLayer(kHdCloudWhite, left: 0.46, top: 0.66, width: 0.72, opacity: 0.65, drift: 0.02, tint: dayTint),
      ];
    case JuzzioWeatherKind.clouds:
      if (night) {
        return [
          JuzzioHdLayer(moon, left: 0.64, top: 0.03, width: 0.22, opacity: 0.85),
          JuzzioHdLayer(kHdCloudStorm, left: -0.22, top: 0.10, width: 1.44, opacity: 0.70 * storm, drift: 0.02),
          JuzzioHdLayer(kHdCloudStorm, left: -0.30, top: 0.48, width: 1.56, opacity: 0.50 * storm, drift: 0.015, flip: true),
        ];
      }
      final cTint = dark ? const Color(0xFF8E98AC) : null;
      return [
        JuzzioHdLayer(kHdCloudWhite, left: -0.30, top: 0.12, width: 0.84, opacity: 0.85, drift: 0.02, flip: true, tint: cTint),
        JuzzioHdLayer(kHdCloudWhite, left: 0.40, top: 0.46, width: 0.88, opacity: 0.78, drift: 0.02, tint: cTint),
      ];
    case JuzzioWeatherKind.fog:
      return [
        JuzzioHdLayer(kHdFogBank, left: -0.12, top: 0.04, width: 1.24, opacity: dark ? 0.85 : 0.70, drift: 0.04),
        JuzzioHdLayer(kHdFogLow, left: -0.14, top: 0.58, width: 1.28, opacity: dark ? 0.75 : 0.60, drift: 0.05),
      ];
    case JuzzioWeatherKind.drizzle:
    case JuzzioWeatherKind.rain:
      final heavy = kind == JuzzioWeatherKind.rain;
      return [
        JuzzioHdLayer(kHdRainCloud, left: -0.26, top: -0.06, width: 0.70, opacity: 0.90 * storm, drift: 0.015, flip: true),
        JuzzioHdLayer(kHdRainCloud, left: 0.46, top: 0.20, width: 0.66, opacity: 0.85 * storm, drift: 0.015),
        JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 0.5, opacity: heavy ? 0.40 : 0.22, fall: true),
      ];
    case JuzzioWeatherKind.snow:
      return [
        JuzzioHdLayer(kHdCloudWhite, left: -0.30, top: -0.02, width: 0.80, opacity: 0.90, drift: 0.015, flip: true),
        JuzzioHdLayer(kHdCloudWhite, left: 0.44, top: 0.10, width: 0.80, opacity: 0.85, drift: 0.015),
        const JuzzioHdLayer(kHdSnowLight, left: 0, top: 0, width: 0.34, opacity: 0.80, fall: true),
      ];
    case JuzzioWeatherKind.thunder:
      return [
        JuzzioHdLayer(kHdBoltCloud, left: -0.08, top: -0.08, width: 0.74, opacity: 0.95 * storm),
        JuzzioHdLayer(kHdRainCloud, left: 0.46, top: -0.02, width: 0.66, opacity: 0.85 * storm, drift: 0.015),
        const JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 0.5, opacity: 0.38, fall: true),
      ];
  }
}

/// Şimşek flaşının görünürlüğü: [t] 0..1 → iki kısa flaş (yaklaşık 140 ms + 110 ms) (saf; test edilir)
double juzzioBoltFlash(double t) {
  if (t <= 0 || t >= 1) return 0;
  if (t < 0.13) return 1; // ilk flaş
  if (t < 0.22) return 0.15;
  if (t < 0.32) return 0.9; // ikinci kısa flaş
  return (1 - (t - 0.32) / 0.68).clamp(0.0, 1.0) * 0.25; // sönüş
}

/// Sahne bandı yüksekliği: ekranın üst kısmı (başlık + arama + hikâyeler)
double juzzioHdBandHeight(double screenH) => (screenH * 0.46).clamp(260.0, 520.0);

/// Geniş ekranda (Windows) sahne sohbet listesi sütununa sığar
double juzzioHdSceneWidth(double screenW) => screenW <= 720 ? screenW : 460;

class JuzzioHdWeatherScene extends StatelessWidget {
  const JuzzioHdWeatherScene({
    super.key,
    required this.kind,
    required this.night,
    required this.dark,
    required this.moonIndex,
    required this.loop,
    required this.bolt,
    this.still = false,
  });
  final JuzzioWeatherKind kind;
  final bool night;
  final bool dark;
  final int moonIndex;
  final Animation<double> loop;
  final Animation<double> bolt;
  final bool still;

  Widget _img(String asset, double w, double opacity, {bool flip = false, Color? tint}) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: _tinted(tint, Image.asset(
          asset,
          width: w,
          height: w / (kJuzzioHdAspect[asset] ?? 1),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        )).flipped(flip),
      );

  static Widget _tinted(Color? c, Widget w) =>
      c == null ? w : ColorFiltered(colorFilter: ColorFilter.mode(c, BlendMode.modulate), child: w);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        // GM-028: geniş pencerede (Windows) sağ panelin kendi gece/gündüz sahnesi var; HD hava
        // katmanı yalnız telefon düzeninde (Sohbetler ekranının üst kısmı) çizilir.
        if (c.maxWidth > 720) return const SizedBox.shrink();
        final sw = juzzioHdSceneWidth(c.maxWidth);
        final band = juzzioHdBandHeight(c.maxHeight);
        final layers = juzzioHdWeatherLayers(kind, night: night, dark: dark, moonIndex: moonIndex);
        return AnimatedBuilder(
          animation: Listenable.merge([loop, bolt]),
          builder: (context, _) {
            final t = still ? 0.0 : loop.value;
            final children = <Widget>[];
            if (night && (kind == JuzzioWeatherKind.clear || kind == JuzzioWeatherKind.clouds)) {
              children.add(Positioned(
                left: 0,
                top: 0,
                width: sw,
                height: band,
                child: CustomPaint(painter: _HdStarsPainter(t: t, dark: dark)),
              ));
            }
            for (final l in layers) {
              final w = sw * l.width;
              if (l.fall) {
                // aynı görselin iki kopyası alt alta → kesintisiz düşüş (tüm ekran, hafif)
                final h = w / (kJuzzioHdAspect[l.asset] ?? 1);
                final dy = (t * 6 % 1) * h;
                children.add(Positioned(
                  left: 0,
                  top: 0,
                  width: sw,
                  bottom: 0,
                  child: ClipRect(
                    child: Stack(clipBehavior: Clip.hardEdge, children: [
                      for (var k = -1; k < (c.maxHeight / h).ceil() + 1; k++)
                        for (var j = 0; j * w < sw; j++)
                          Positioned(left: sw * l.left + j * w, top: k * h + dy, child: _img(l.asset, w, l.opacity, flip: j.isOdd)),
                    ]),
                  ),
                ));
                continue;
              }
              final dx = l.drift == 0 ? 0.0 : math.sin(t * 2 * math.pi) * l.drift * sw;
              children.add(Positioned(left: sw * l.left + dx, top: band * l.top, child: _img(l.asset, w, l.opacity, flip: l.flip, tint: l.tint)));
            }
            if (kind == JuzzioWeatherKind.thunder) {
              final f = still ? 0.0 : juzzioBoltFlash(bolt.value);
              if (f > 0) {
                children.add(Positioned(left: sw * 0.02, top: band * 0.02, child: _img(kHdBolt, sw * 0.98, f)));
                children.add(Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.06 * f))));
              }
            }
            // bandın altı içerikle yumuşakça birleşir (keskin kesik yok)
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.white, Colors.white, Color(0x55FFFFFF)],
                stops: [0, (band / r.height).clamp(0.2, 0.95), 1],
              ).createShader(r),
              child: Stack(clipBehavior: Clip.hardEdge, children: children),
            );
          },
        );
      }),
    );
  }
}

class _HdStarsPainter extends CustomPainter {
  _HdStarsPainter({required this.t, required this.dark});
  final double t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 34; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height * 0.85;
      final r = 0.6 + rnd.nextDouble() * 1.3;
      final tw = 0.45 + 0.55 * (0.5 + 0.5 * math.sin((t * 2 * math.pi * 3) + i));
      p.color = (dark ? Colors.white : const Color(0xFF8FA3C8)).withValues(alpha: (dark ? 0.75 : 0.45) * tw);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(_HdStarsPainter o) => o.t != t || o.dark != dark;
}

extension on Widget {
  /// Yatay aynalama (GM-037)
  Widget flipped(bool on) => on ? Transform.flip(flipX: true, child: this) : this;
}

/// GM-037: YALNIZ hata ayıklama derlemesinde Görünüm sayfasında görünen önizleme seçicisi —
/// her hava türünü gece/gündüz ve özel gün temalarını Sohbetler ekranında denemek için.
class JuzzioWeatherDebugPreview extends StatelessWidget {
  const JuzzioWeatherDebugPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([JuzzioWeatherService.debugPreview, JuzzioSpecialThemes.instance]),
      builder: (context, _) {
        final cur = JuzzioWeatherService.debugPreview.value;
        final sp = JuzzioSpecialThemes.instance.debugForced;
        Widget chip(String label, bool on, VoidCallback tap) => Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 6),
              child: ChoiceChip(label: Text(label), selected: on, onSelected: (_) => tap()),
            );
        return Padding(
          key: const ValueKey('gm037-debug-preview'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(children: [
            chip('Gerçek', cur == null && sp == null, () {
              JuzzioWeatherService.debugPreview.value = null;
              JuzzioSpecialThemes.instance.debugForce(null);
            }),
            for (final k in JuzzioWeatherKind.values)
              for (final n in [false, true])
                chip('${k.name}${n ? ' gece' : ' gündüz'}', cur?.$1 == k && cur?.$2 == n, () {
                  JuzzioSpecialThemes.instance.debugForce(null);
                  JuzzioWeatherService.debugPreview.value = (k, n);
                }),
            chip('Türk bayrağı', sp == JuzzioSpecialTheme.turkey, () => JuzzioSpecialThemes.instance.debugForce(JuzzioSpecialTheme.turkey)),
            chip('Halloween', sp == JuzzioSpecialTheme.halloween,
                () => JuzzioSpecialThemes.instance.debugForce(JuzzioSpecialTheme.halloween)),
          ]),
        );
      },
    );
  }
}
