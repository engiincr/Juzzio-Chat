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

import 'package:flutter/material.dart';

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
const String kHdSnowCloud = 'assets/weather_hd/snow_cloud.webp';
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
  kHdCloudWhite, kHdCloudStorm, kHdSunRise, kHdSunRays, kHdSnowCloud, kHdSnowFlakes, kHdSnowLight,
  kHdBolt, kHdBoltCloud, kHdFogBank, kHdFogLow, kHdRainCloud, kHdRainHeavy,
];

/// Görselin özgün en/boy oranı (yükseklik = genişlik / oran)
const Map<String, double> kJuzzioHdAspect = {
  kHdCloudWhite: 2048 / 1250,
  kHdCloudStorm: 2048 / 1250,
  kHdSunRise: 2048 / 1536,
  kHdSunRays: 2048 / 1536,
  kHdSnowCloud: 1536 / 2048,
  kHdSnowFlakes: 1.0,
  kHdSnowLight: 1.0,
  kHdBolt: 2048 / 1536,
  kHdBoltCloud: 1536 / 2048,
  kHdFogBank: 2048 / 1200,
  kHdFogLow: 2048 / 900,
  kHdRainCloud: 1536 / 2048,
  kHdRainHeavy: 1536 / 2048,
};

/// Sahnedeki bir görsel katmanı. Konum ve genişlik, sahne bandına (genişlik W, yükseklik B) göre oran.
class JuzzioHdLayer {
  const JuzzioHdLayer(this.asset, {required this.left, required this.top, required this.width, this.opacity = 1, this.drift = 0, this.fall = false});
  final String asset;
  final double left;
  final double top;
  final double width;
  final double opacity;

  /// Yatay süzülme genliği (genişliğin oranı); 0 = durağan
  final double drift;

  /// Yukarıdan aşağı sürekli düşen katman (yağmur, kar)
  final bool fall;
}

/// Hava türüne göre referans ekranlardaki yerleşim (saf; test edilir)
List<JuzzioHdLayer> juzzioHdWeatherLayers(JuzzioWeatherKind kind, {required bool night, required bool dark, required int moonIndex}) {
  final storm = dark ? 1.0 : 0.78; // açık temada koyu bulutlar biraz hafifler
  final moon = kJuzzioHdMoonAssets[moonIndex.clamp(0, 7)];
  switch (kind) {
    case JuzzioWeatherKind.clear:
      if (night) {
        return [
          JuzzioHdLayer(moon, left: 0.60, top: 0.04, width: 0.30),
          JuzzioHdLayer(kHdCloudStorm, left: -0.28, top: 0.56, width: 0.72, opacity: 0.30 * storm, drift: 0.03),
        ];
      }
      return const [
        JuzzioHdLayer(kHdSunRise, left: 0.18, top: 0.06, width: 0.98),
        JuzzioHdLayer(kHdCloudWhite, left: -0.26, top: 0.40, width: 0.62, opacity: 0.55, drift: 0.035),
        JuzzioHdLayer(kHdCloudWhite, left: 0.46, top: 0.66, width: 0.70, opacity: 0.50, drift: 0.03),
      ];
    case JuzzioWeatherKind.clouds:
      final c = night ? kHdCloudStorm : kHdCloudWhite;
      return [
        if (night) JuzzioHdLayer(moon, left: 0.64, top: 0.03, width: 0.24, opacity: 0.85),
        JuzzioHdLayer(c, left: -0.20, top: 0.12, width: 0.82, opacity: (night ? 0.80 : 0.85) * (night ? storm : 1), drift: 0.04),
        JuzzioHdLayer(c, left: 0.40, top: 0.46, width: 0.86, opacity: (night ? 0.70 : 0.78) * (night ? storm : 1), drift: 0.035),
      ];
    case JuzzioWeatherKind.fog:
      return [
        JuzzioHdLayer(kHdFogBank, left: -0.12, top: 0.04, width: 1.24, opacity: dark ? 0.85 : 0.70, drift: 0.05),
        JuzzioHdLayer(kHdFogLow, left: -0.14, top: 0.58, width: 1.28, opacity: dark ? 0.75 : 0.60, drift: 0.06),
      ];
    case JuzzioWeatherKind.drizzle:
    case JuzzioWeatherKind.rain:
      final heavy = kind == JuzzioWeatherKind.rain;
      return [
        JuzzioHdLayer(kHdRainCloud, left: -0.24, top: -0.06, width: 0.70, opacity: 0.90 * storm, drift: 0.025),
        JuzzioHdLayer(kHdRainCloud, left: 0.46, top: 0.20, width: 0.66, opacity: 0.85 * storm, drift: 0.02),
        JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 1.0, opacity: heavy ? 0.42 : 0.24, fall: true),
      ];
    case JuzzioWeatherKind.snow:
      return [
        JuzzioHdLayer(kHdSnowCloud, left: -0.18, top: -0.10, width: 0.62, opacity: 0.95, drift: 0.02),
        JuzzioHdLayer(kHdSnowCloud, left: 0.50, top: 0.04, width: 0.58, opacity: 0.90, drift: 0.02),
        const JuzzioHdLayer(kHdSnowFlakes, left: 0, top: 0, width: 1.0, opacity: 0.85, fall: true),
      ];
    case JuzzioWeatherKind.thunder:
      return [
        JuzzioHdLayer(kHdBoltCloud, left: 0.34, top: -0.10, width: 0.70, opacity: 0.95 * storm),
        JuzzioHdLayer(kHdRainCloud, left: -0.26, top: -0.04, width: 0.66, opacity: 0.85 * storm, drift: 0.02),
        const JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 1.0, opacity: 0.40, fall: true),
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

  Widget _img(String asset, double w, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Image.asset(
          asset,
          width: w,
          height: w / (kJuzzioHdAspect[asset] ?? 1),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );

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
                        Positioned(left: sw * l.left, top: k * h + dy, child: _img(l.asset, w, l.opacity)),
                    ]),
                  ),
                ));
                continue;
              }
              final dx = l.drift == 0 ? 0.0 : math.sin(t * 2 * math.pi) * l.drift * sw;
              children.add(Positioned(left: sw * l.left + dx, top: band * l.top, child: _img(l.asset, w, l.opacity)));
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
