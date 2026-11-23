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

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';

import '../core/theme/juzzio_glass.dart' show JuzzioGlassTokens;
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

/// GM-037: iki yanı ve altı yumuşatılmış, kesiksiz bulut (paketteki cloud_white'tan üretildi)
const String kHdCloudPuff = 'assets/weather_hd/cloud_puff.webp';

/// GM-037: açık tema için gündoğumu (bulut gövdeleri beyaz/mavi-gri, ışınlar sarı — Engin'in gündüz görseli)
const String kHdSunRiseLight = 'assets/weather_hd/sun_rise_clouds_light.webp';
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
  kHdCloudWhite, kHdCloudStorm, kHdCloudPuff, kHdSunRise, kHdSunRiseLight, kHdSunRays, kHdSnowFlakes, kHdSnowLight,
  kHdBolt, kHdBoltCloud, kHdFogBank, kHdFogLow, kHdRainCloud, kHdRainHeavy,
];

/// Görselin özgün en/boy oranı (yükseklik = genişlik / oran)
const Map<String, double> kJuzzioHdAspect = {
  kHdCloudWhite: 2048 / 1250,
  kHdCloudStorm: 2048 / 1250,
  kHdCloudPuff: 1212 / 526,
  kHdSunRiseLight: 2048 / 1536,
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
      {required this.left,
      required this.top,
      required this.width,
      this.opacity = 1,
      this.drift = 0,
      this.fall = false,
      this.flip = false,
      this.tint,
      this.anchored = false});
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

  /// GM-037: true ise [top], Sohbetler arama kutusunun üst kenarına göre ve sahne GENİŞLİĞİ
  /// biriminde ölçülür (referanslarda ay/güneş başlık düğmeleri ile arama kutusu arasında durur;
  /// ekran yüksekliği değişse de yeri kaymaz).
  final bool anchored;
}

/// GM-037: Sohbetler başlığındaki arama kutusunun üst kenarı (global y). [JuzzioHdAnchor] yazar.
final ValueNotifier<double?> kJuzzioHdSearchTop = ValueNotifier<double?>(null);

/// Arama kutusu yokken (ör. ilk kare) kullanılan tahmini üst kenar: güvenli alan + başlık
double juzzioHdFallbackAnchor(double safeTop) => safeTop + 96;

/// Arama kutusunu sarar; yerleşimden sonra üst kenarının global y'sini [kJuzzioHdSearchTop]'a yazar.
class JuzzioHdAnchor extends StatefulWidget {
  const JuzzioHdAnchor({super.key, required this.child});
  final Widget child;
  @override
  State<JuzzioHdAnchor> createState() => _JuzzioHdAnchorState();
}

class _JuzzioHdAnchorState extends State<JuzzioHdAnchor> {
  static _JuzzioHdAnchorState? _owner;
  static bool enabled = true;
  bool _active = true;

  static void clear() {
    _owner = null;
    if (kJuzzioHdSearchTop.value != null) kJuzzioHdSearchTop.value = null;
  }

  void _report(Duration _) {
    if (!mounted) return;
    if (!_active || !enabled) {
      // Sohbetler sekmesi gizliyken (başka sekme) gök cisimleri çizilmez: düğmelere binmesinler
      if (_owner == this || !enabled) clear();
      return;
    }
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      final y = box.localToGlobal(Offset.zero).dy;
      _owner = this;
      if (kJuzzioHdSearchTop.value == null || (kJuzzioHdSearchTop.value! - y).abs() > 0.5) kJuzzioHdSearchTop.value = y;
    }
  }

  @override
  void dispose() {
    if (_owner == this) {
      _owner = null;
      // bildirim çerçeve dışında (dispose sırasında dinleyici yeniden kurulmasın)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_owner == null) kJuzzioHdSearchTop.value = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _active = TickerMode.of(context);
    WidgetsBinding.instance.addPostFrameCallback(_report);
    return widget.child;
  }
}

/// Sohbetler listesi görünür mü (ekran her çizimde bildirir). Kapalıyken gök cisimleri gizlenir;
/// açılınca arama kutusu konumunu yeniden yazar.
void juzzioHdAnchorEnabled(bool on) {
  if (_JuzzioHdAnchorState.enabled == on) return;
  _JuzzioHdAnchorState.enabled = on;
  if (!on) WidgetsBinding.instance.addPostFrameCallback((_) => _JuzzioHdAnchorState.clear());
}

/// Gök cismi (ay/güneş) katmanı mı — arama kutusu görünmüyorsa çizilmez
bool juzzioHdIsCelestial(String asset) => asset == kHdSunRise || asset == kHdSunRiseLight || kJuzzioHdMoonAssets.contains(asset);

/// Hava türüne göre referans ekranlardaki yerleşim (saf; test edilir)
List<JuzzioHdLayer> juzzioHdWeatherLayers(JuzzioWeatherKind kind, {required bool night, required bool dark, required int moonIndex}) {
  final storm = dark ? 1.0 : 0.80; // açık temada koyu bulutlar biraz hafifler
  final moon = kJuzzioHdMoonAssets[moonIndex.clamp(0, 7)];
  // Kural (GM-037): düz kesik kenarlı bulutların o kenarı ekran dışında kalır (left < 0 veya
  // left + width > 1); her iki kenarı kesik olan fırtına bulutu ekranı taşacak genişlikte çizilir.
  switch (kind) {
    case JuzzioWeatherKind.clear:
      if (night) {
        // referans: ay başlık düğmelerinin solunda, arama kutusunun hemen üstünde (yarısı camın ardında)
        return [
          JuzzioHdLayer(moon, left: 0.53, top: -0.135, width: 0.13, anchored: true),
          JuzzioHdLayer(kHdCloudPuff, left: -0.32, top: 0.62, width: 0.66, opacity: 0.14, drift: 0.02, flip: true),
        ];
      }
      // referans (Engin'in güneşli gece/gündüz görselleri): yalnız arama kutusunun üstünde, bulut
      // kümesinin ardından doğan güneş (merkez ≈ 0.77W); açık temada bulutlar beyaz, ışınlar sarı
      // GM-064: açık tema referansında (eebd3257) güneş ve beyaz bulut kümesi daha büyük; bulutların
      // alt kenarı aramanın üst kenarında, güneş merkezi ≈ (0.76W, −0.06W)
      return [
        dark
            ? JuzzioHdLayer(kHdSunRise, left: 0.43, top: -0.27, width: 0.59, anchored: true)
            : JuzzioHdLayer(kHdSunRiseLight, left: 0.34, top: -0.34, width: 0.72, anchored: true),
      ];
    case JuzzioWeatherKind.clouds:
      // GM-064 (Engin 23.11 videosu): bulutlar referanstaki gibi KÜÇÜK ve KOYU bir bant —
      // marka satırının altından aramanın ardına; hikâyelerin sağında küçük küme. "Gelen kutusu"
      // satırına (≈ +0.50W) ve logoya binmez; arama kutusu koyu camla okunur kalır.
      final cTint = night ? const Color(0xFF5E6B7C) : (dark ? const Color(0xFF7D879A) : const Color(0xFFC3CEDE)); // açık temada beyaz zeminde görünür gri-mavi gölge
      return [
        if (night) JuzzioHdLayer(moon, left: 0.56, top: -0.15, width: 0.11, opacity: 0.85, anchored: true),
        ...juzzioHdCloudBand(tint: cTint, opacity: night ? 0.78 : (dark ? 0.85 : 0.92)),
      ];
    case JuzzioWeatherKind.fog:
      return [
        // sis: başlığın ardında ince, yazıları örtmeyen pus (hikâyelerin altına inmez)
        JuzzioHdLayer(kHdFogBank, left: -0.12, top: -0.30, width: 1.24, opacity: dark ? 0.30 : 0.40, drift: 0.04, anchored: true),
        JuzzioHdLayer(kHdFogLow, left: -0.14, top: 0.06, width: 1.28, opacity: dark ? 0.20 : 0.26, drift: 0.05, anchored: true),
      ];
    case JuzzioWeatherKind.drizzle:
    case JuzzioWeatherKind.rain:
      final heavy = kind == JuzzioWeatherKind.rain;
      // referans (Engin'in yağmurlu görseli): arduvaz-mavi gök, koyu küçük bulut bandı; yağmur yalnız
      // başlık bandında yağar (sohbet kartlarının üstüne yağmaz) ve bulutlarla birlikte KAYMAZ
      final rTint = dark ? const Color(0xFF55637A) : const Color(0xFF9AA8BA);
      return [
        ...juzzioHdCloudBand(tint: rTint, opacity: 0.86 * storm),
        JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 0.5, opacity: heavy ? 0.30 : 0.18, fall: true),
      ];
    case JuzzioWeatherKind.snow:
      // kar: açık bulut bandı + ressamla çizilen kar taneleri (yalnız başlık bandında)
      final sTint = dark ? const Color(0xFFA9B4C4) : const Color(0xFFCAD3E0);
      return juzzioHdCloudBand(tint: sTint, opacity: dark ? 0.70 : 0.90);
    case JuzzioWeatherKind.thunder:
      // fırtına: en koyu bulut bandı + yağmur; şimşek yalnız kısa flaşlarda bulutların ardından çakar
      final tTint = dark ? const Color(0xFF465264) : const Color(0xFF8592A4);
      return [
        ...juzzioHdCloudBand(tint: tTint, opacity: 0.92 * storm),
        const JuzzioHdLayer(kHdRainHeavy, left: 0, top: 0, width: 0.5, opacity: 0.32, fall: true),
      ];
  }
}

/// Referans bulut bandı (84356993 / a2de70a2): arama kutusuna göre W cinsinden; en alt kenar +0.40W
/// (Gelen kutusu satırı ≈ +0.50W). Saf; test edilir.
List<JuzzioHdLayer> juzzioHdCloudBand({Color? tint, double opacity = 0.85}) => [
      JuzzioHdLayer(kHdCloudPuff, left: -0.12, top: -0.15, width: 0.54, opacity: opacity * 0.92, drift: 0.010, flip: true, tint: tint, anchored: true),
      JuzzioHdLayer(kHdCloudPuff, left: 0.44, top: -0.19, width: 0.62, opacity: opacity, drift: 0.012, tint: tint, anchored: true),
      JuzzioHdLayer(kHdCloudPuff, left: 0.46, top: 0.16, width: 0.52, opacity: opacity * 0.85, drift: 0.014, tint: tint, anchored: true),
      JuzzioHdLayer(kHdCloudPuff, left: 0.26, top: 0.22, width: 0.24, opacity: opacity * 0.60, drift: 0.008, flip: true, tint: tint, anchored: true),
    ];

/// Yağmur/kar yalnız bu yüksekliğe kadar (arama kutusu + 0.42W) iner
double juzzioHdPrecipBottom(double anchor, double sw) => anchor + sw * 0.42;

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
          animation: Listenable.merge([loop, bolt, kJuzzioHdSearchTop]),
          builder: (context, _) {
            final t = still ? 0.0 : loop.value;
            final anchorKnown = kJuzzioHdSearchTop.value != null;
            // GM-064: hava sahnesi YALNIZ Sohbetler listesinin başlığında; Profil/Keşfet/Ayarlar vb.
            // sayfalarda (arama kutusu yokken) hiçbir katman (yağmur, kar, şimşek, renk) çizilmez
            if (!anchorKnown) return const SizedBox.shrink();
            final anchor = kJuzzioHdSearchTop.value ?? juzzioHdFallbackAnchor(MediaQuery.paddingOf(context).top);
            final children = <Widget>[];
            final rainy = kind == JuzzioWeatherKind.rain || kind == JuzzioWeatherKind.drizzle || kind == JuzzioWeatherKind.thunder;
            if (rainy) {
              // referans: yağmurda başlık arduvaz-mavi bir göğe bürünür
              children.add(Positioned(
                left: 0,
                top: 0,
                width: sw,
                height: anchor + sw * 0.50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: dark
                          ? const [Color(0x8C2A3846), Color(0x732C3B4A), Color(0x00222C36)]
                          : const [Color(0x598FA2B6), Color(0x408FA2B6), Color(0x008FA2B6)],
                    ),
                  ),
                ),
              ));
            }
            if (anchorKnown && !dark && !night && kind == JuzzioWeatherKind.clear) {
              // açık tema referansı: güneşin ardında yumuşak açık mavi gök lekesi
              children.add(Positioned(
                left: sw * 0.30,
                top: anchor - sw * 0.40,
                width: sw * 0.90,
                height: sw * 0.50,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [Color(0x66BFD6EE), Color(0x00BFD6EE)]),
                  ),
                ),
              ));
            }
            if (anchorKnown && (kind == JuzzioWeatherKind.clear || kind == JuzzioWeatherKind.clouds)) {
              // referans: logonun altından düğmelerin ardına yükselen limon ışık yayı
              children.add(Positioned.fill(child: CustomPaint(painter: JuzzioHdSwooshPainter(width: sw, anchor: anchor, color: JuzzioGlassTokens.glow))));
            }
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
              if (!anchorKnown && juzzioHdIsCelestial(l.asset)) continue;
              final w = sw * l.width;
              if (l.fall) {
                // GM-064: yağmur görseli içinde bulut taşıdığı için döşenince dikiş/bulut parçası oluşuyordu;
                // artık ekrana sabit, yalnız başlık bandında yağan ince damla çizgileri (bulutla KAYMAZ)
                children.add(Positioned(
                  left: 0,
                  top: 0,
                  width: sw,
                  height: juzzioHdPrecipBottom(anchor, sw),
                  child: CustomPaint(painter: JuzzioHdRainPainter(t: t, dark: dark, intensity: l.opacity)),
                ));
                continue;
              }
              final dx = l.drift == 0 ? 0.0 : math.sin(t * 2 * math.pi) * l.drift * sw;
              final y = l.anchored ? anchor + l.top * sw : band * l.top;
              children.add(Positioned(left: sw * l.left + dx, top: y, child: _img(l.asset, w, l.opacity, flip: l.flip, tint: l.tint)));
            }
            if (kind == JuzzioWeatherKind.snow) {
              children.add(Positioned(
                  left: 0,
                  top: 0,
                  width: sw,
                  height: juzzioHdPrecipBottom(anchor, sw),
                  child: CustomPaint(painter: JuzzioHdSnowPainter(t: t, dark: dark))));
            }
            if (kind == JuzzioWeatherKind.thunder) {
              final f = still ? 0.0 : juzzioBoltFlash(bolt.value);
              if (f > 0) {
                // şimşek bulutların arasından aramaya doğru iner
                // küçük şimşek: sağ üst bulutun ardından aramaya doğru (yazıların üstüne inmez)
                children.add(Positioned(left: sw * 0.46, top: anchor - sw * 0.27, child: _img(kHdBolt, sw * 0.44, f * 0.9)));
                children.add(Positioned(
                    left: 0, top: 0, width: sw, height: juzzioHdPrecipBottom(anchor, sw),
                    child: ColoredBox(color: Colors.white.withValues(alpha: 0.05 * f))));
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

/// GM-037: referanslardaki limon ışık yayı (Türk bayrağı temasındakiyle aynı eğri)
class JuzzioHdSwooshPainter extends CustomPainter {
  JuzzioHdSwooshPainter({required this.width, required this.anchor, required this.color});
  final double width;
  final double anchor;
  final Color color;

  static Path path(double width, double anchor) => Path()
    ..moveTo(-width * 0.02, anchor - width * 0.05)
    ..cubicTo(width * 0.30, anchor - width * 0.01, width * 0.55, anchor - width * 0.20, width * 0.92, anchor - width * 0.40);

  @override
  void paint(Canvas canvas, Size size) {
    final p = path(width, anchor);
    for (final (w, a) in [(18.0, 0.08), (8.0, 0.18), (2.0, 0.80)]) {
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: a)
            ..maskFilter = w > 3 ? MaskFilter.blur(BlurStyle.normal, w / 2) : null);
    }
  }

  @override
  bool shouldRepaint(JuzzioHdSwooshPainter o) => o.width != width || o.anchor != anchor || o.color != color;
}

/// GM-037: kar — farklı boyda, yumuşak kenarlı, salınarak düşen taneler (ikon ızgarası yok)
class JuzzioHdSnowPainter extends CustomPainter {
  JuzzioHdSnowPainter({required this.t, required this.dark});
  final double t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(11);
    final h = size.height; // alan zaten başlık bandıyla sınırlı (juzzioHdPrecipBottom)
    for (var i = 0; i < 90; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final y0 = rnd.nextDouble();
      final r = 0.9 + rnd.nextDouble() * 2.4;
      final speed = 0.6 + r / 3.3; // büyük tane daha hızlı (yakın)
      final ph = rnd.nextDouble() * math.pi * 2;
      final y = ((y0 + t * speed * 2) % 1.0) * h;
      final x = x0 + math.sin(t * 2 * math.pi * 3 + ph) * (6 + r * 2);
      final fade = (1 - (y / h)).clamp(0.0, 1.0);
      final a = (0.45 + 0.45 * (r / 3.3)) * (0.35 + 0.65 * fade);
      final c = (dark ? Colors.white : const Color(0xFFFFFFFF)).withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = c..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45));
      if (!dark) {
        canvas.drawCircle(Offset(x, y), r + 0.6, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = const Color(0xFF9DB0C8).withValues(alpha: a * 0.6));
      }
    }
  }

  @override
  bool shouldRepaint(JuzzioHdSnowPainter o) => o.t != t || o.dark != dark;
}

/// GM-064: ince, hafif eğik yağmur çizgileri; üstte ve altta yumuşakça kaybolur (saf çizim)
class JuzzioHdRainPainter extends CustomPainter {
  JuzzioHdRainPainter({required this.t, required this.dark, required this.intensity});
  final double t;
  final bool dark;
  final double intensity; // 0.18 çisenti … 0.32 sağanak

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final n = (60 + intensity * 260).round();
    final h = size.height;
    final base = dark ? const Color(0xFFCFD8E6) : const Color(0xFF6F8299);
    for (var i = 0; i < n; i++) {
      final x0 = rnd.nextDouble() * (size.width + 40) - 20;
      final y0 = rnd.nextDouble();
      final len = 10 + rnd.nextDouble() * 16;
      final speed = 2.2 + rnd.nextDouble() * 1.6;
      final y = ((y0 + t * speed * 6) % 1.0) * (h + len) - len;
      final x = x0 - y * 0.12;
      final edge = (math.min(y / (h * 0.18), (h - y) / (h * 0.30))).clamp(0.0, 1.0);
      final a = (0.20 + rnd.nextDouble() * 0.35) * (intensity / 0.30).clamp(0.5, 1.2) * edge;
      if (a <= 0.01) continue;
      canvas.drawLine(
          Offset(x, y),
          Offset(x - len * 0.12, y + len),
          Paint()
            ..color = base.withValues(alpha: a.clamp(0.0, 0.6))
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(JuzzioHdRainPainter o) => o.t != t || o.dark != dark || o.intensity != intensity;
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

/// GM-037: Görünüm sayfasındaki önizleme seçicisi KALDIRILDI (Engin: hava ve özel gün temaları yalnız
/// otomatik gelir; kullanıcıya seçenek gösterilmez). Geliştirici denetimi için YALNIZ hata ayıklama
/// derlemesinde, depo DIŞINDAKİ `..\juzzio_logs\juzzio_debug_preview.txt` dosyası okunur
/// (ör. `rain:night`, `clear:day`, `turkey`, `halloween`; boş = gerçek hava). Kullanıcı arayüzünde iz yok.
class JuzzioWeatherDebugFile {
  static Timer? _t;
  static String _last = '';

  static String? _path() {
    try {
      if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return null;
      var d = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 8; i++) {
        if (File('${d.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
          return '${d.parent.path}${Platform.pathSeparator}juzzio_logs${Platform.pathSeparator}juzzio_debug_preview.txt';
        }
        d = d.parent;
      }
    } catch (_) {}
    return null;
  }

  static void start() {
    if (!kDebugMode || _t != null) return;
    final path = _path();
    if (path == null) return;
    _t = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      String v = '';
      try {
        final f = File(path);
        if (f.existsSync()) v = f.readAsStringSync().trim().toLowerCase();
      } catch (_) {}
      if (v == _last) return;
      _last = v;
      apply(v);
    });
  }

  @visibleForTesting
  static void apply(String v) {
    if (v == 'turkey' || v == 'halloween') {
      JuzzioWeatherService.debugPreview.value = null;
      JuzzioSpecialThemes.instance.debugForce(v == 'turkey' ? JuzzioSpecialTheme.turkey : JuzzioSpecialTheme.halloween);
      return;
    }
    JuzzioSpecialThemes.instance.debugForce(null);
    final parts = v.split(':');
    final kind = JuzzioWeatherKind.values.where((k) => k.name == parts.first).firstOrNull;
    JuzzioWeatherService.debugPreview.value = kind == null ? null : (kind, parts.length > 1 && parts[1] == 'night');
  }
}
