// =============================================================================
// JUZZIO v2.2.0 — GM-029 / GM-031: Özel gün dekorları (Sohbetler ekranı başlığı)
//  • Türk bayrağı: gündüz dalgalanan kırmızı bayrak, gece gümüş ay-yıldız + parıltı
//    (bayrak resmî oranlarla KODLA çizilir; harici görsel yok) ve temanın vurgu renginde ışık yayı.
//  • Halloween: paketin şeffaf görselleri (şato + dolunay, kabaklı ağaç, ay ve bulut şeridi).
//  Dekorlar dokunmayı engellemez; hava katmanı yerine çizilir (hava dekoru örtmez).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/juzzio_special_themes.dart';
import 'juzzio_weather_hd.dart' show juzzioHdBandHeight, juzzioHdSceneWidth;

const String kHalloweenCastle = 'assets/special/halloween/castle_scene.webp';
const String kHalloweenTree = 'assets/special/halloween/pumpkin_tree.webp';
const String kHalloweenMoonClouds = 'assets/special/halloween/moon_clouds.webp';
const List<String> kJuzzioHalloweenAssets = [kHalloweenCastle, kHalloweenTree, kHalloweenMoonClouds];

/// GM-037: paketteki karışık Halloween görsellerinden temiz kırpılıp referansın mor-turuncu
/// renklerine göre renklendirilmiş parçalar (en/boy oranları)
const double kHwCastleAspect = 1157 / 622;
const double kHwTreeAspect = 1229 / 1152;
const double kHwBandAspect = 532 / 323;

/// Türk bayrağı resmî oranları (TS 2/1983 — G: bayrak eni; boy 1.5 G) (saf; test edilir)
class JuzzioTurkFlagGeometry {
  const JuzzioTurkFlagGeometry(this.g);
  final double g;
  double get length => 1.5 * g;
  Offset get outerCenter => Offset(0.5 * g, 0.5 * g);
  double get outerRadius => 0.25 * g;
  Offset get innerCenter => Offset(0.5625 * g, 0.5 * g);
  double get innerRadius => 0.2 * g;
  Offset get starCenter => Offset(0.7925 * g, 0.5 * g);
  double get starRadius => 0.125 * g;
}

Path juzzioStarPath(Offset c, double r, {double rotation = -math.pi}) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * 0.382;
    final a = rotation + i * math.pi / 5;
    final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

class JuzzioSpecialThemeLayer extends StatelessWidget {
  const JuzzioSpecialThemeLayer({super.key, required this.theme, required this.dark, required this.loop, required this.accent});
  final JuzzioSpecialTheme theme;
  final bool dark;
  final Animation<double> loop;
  final Color accent;

  Widget _img(String asset, double w, double aspect, double opacity) => Opacity(
        opacity: opacity,
        child: Image.asset(asset,
            width: w,
            height: w / aspect,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      );

  @override
  Widget build(BuildContext context) {
    if (theme == JuzzioSpecialTheme.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        final sw = juzzioHdSceneWidth(c.maxWidth);
        final band = juzzioHdBandHeight(c.maxHeight);
        if (theme == JuzzioSpecialTheme.halloween) {
          // Referans (Engin'in Halloween ekranı): mor-turuncu gökyüzü bandı, sağda dolunaylı şato +
          // yarasalar, solda kabaklı ağaç, hikâyelerin arkasında çıplak ağaçlı ikinci şerit.
          final o = dark ? 1.0 : 0.92;
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              left: 0,
              top: 0,
              width: sw,
              height: band * 1.02,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF1A0F24).withValues(alpha: 0.0),
                      const Color(0xFF3B1E4F).withValues(alpha: 0.55 * o),
                      const Color(0xFF5A2A3A).withValues(alpha: 0.45 * o),
                      const Color(0xFF1A0F24).withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              ),
            ),
            // ikinci şerit: hikâyelerin arkasında çıplak ağaçlar (karartılmış, iki kopya aynalı)
            Positioned(left: -sw * 0.06, top: band * 0.62, child: _img(kHalloweenMoonClouds, sw * 0.60, kHwBandAspect, 0.9 * o)),
            Positioned(
                left: sw * 0.46,
                top: band * 0.60,
                child: Transform.flip(flipX: true, child: _img(kHalloweenMoonClouds, sw * 0.62, kHwBandAspect, 0.9 * o))),
            // sağda dolunaylı şato + yarasalar
            Positioned(left: sw * 0.30, top: band * 0.20, child: _img(kHalloweenCastle, sw * 0.76, kHwCastleAspect, o)),
            // solda kabaklı ağaç
            Positioned(left: -sw * 0.08, top: band * 0.22, child: _img(kHalloweenTree, sw * 0.50, kHwTreeAspect, o)),
          ]);
        }
        return AnimatedBuilder(
          animation: loop,
          builder: (context, _) => CustomPaint(
            size: Size(sw, band),
            painter: JuzzioTurkFlagPainter(t: loop.value, dark: dark, accent: accent, band: band, width: sw),
          ),
        );
      }),
    );
  }
}

/// Dalgalanan Türk bayrağı (gündüz) / gümüş ay-yıldız (gece) + vurgu renginde ışık yayı
class JuzzioTurkFlagPainter extends CustomPainter {
  JuzzioTurkFlagPainter({required this.t, required this.dark, required this.accent, required this.band, required this.width});
  final double t;
  final bool dark;
  final Color accent;
  final double band;
  final double width;

  static const Color red = Color(0xFFE30A17); // resmî bayrak kırmızısı

  void _swoosh(Canvas canvas) {
    final path = Path()
      ..moveTo(-width * 0.02, band * 0.36)
      ..cubicTo(width * 0.30, band * 0.40, width * 0.55, band * 0.22, width * 0.92, band * 0.02);
    for (final (w, a) in [(18.0, 0.10), (8.0, 0.20), (2.2, 0.85)]) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: a)
            ..maskFilter = w > 3 ? MaskFilter.blur(BlurStyle.normal, w / 2) : null);
    }
  }

  void _emblem(Canvas canvas, JuzzioTurkFlagGeometry geo, Paint paint) {
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: geo.outerCenter, radius: geo.outerRadius)),
      Path()..addOval(Rect.fromCircle(center: geo.innerCenter, radius: geo.innerRadius)),
    );
    canvas.drawPath(crescent, paint);
    canvas.drawPath(juzzioStarPath(geo.starCenter, geo.starRadius), paint);
  }

  /// Metalik (3B görünümlü) ay-yıldız: gümüş gradyan + üst kenarda ışık, altta gölge
  void _metalEmblem(Canvas canvas, JuzzioTurkFlagGeometry geo, {required bool onRed}) {
    final bounds = Rect.fromLTWH(geo.outerCenter.dx - geo.outerRadius, 0, geo.length, geo.g);
    canvas.save();
    canvas.translate(2, 3);
    _emblem(canvas, geo, Paint()
      ..color = Colors.black.withValues(alpha: onRed ? 0.25 : 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.restore();
    _emblem(
        canvas,
        geo,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: onRed
                ? const [Color(0xFFFFFFFF), Color(0xFFF2F2F2), Color(0xFFCFD2D6)]
                : const [Color(0xFFFFFFFF), Color(0xFFD9DCE0), Color(0xFF8A9098), Color(0xFFC9CDD2)],
          ).createShader(bounds));
    // ince parlak kenar
    _emblem(
        canvas,
        geo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _swoosh(canvas);
    // Referans (Engin'in görseli): ay-yıldız başlık düğmelerinin altında, ekranın ortasının biraz sağında
    final g = (width * 0.20).clamp(54.0, 120.0);
    final geo = JuzzioTurkFlagGeometry(g);
    final emblemOrigin = Offset(width * 0.47, band * 0.27);
    if (!dark) {
      // gündüz: emblemin arkasında yumuşak kenarlı, dalgalanan kırmızı bayrak kumaşı
      final fw = width * 0.62, fh = g * 1.05;
      final fo = Offset(width * 0.44, band * 0.27 - g * 0.05);
      const strips = 40;
      final sw = fw / strips;
      for (var i = 0; i < strips; i++) {
        final x = i * sw;
        final ph = (x / fw) * 2 * math.pi * 1.2 - t * 2 * math.pi * 4;
        final dy = math.sin(ph) * fh * 0.06;
        final shade = math.cos(ph);
        // kenarlar (özellikle sol) kumaş gibi yumuşakça kaybolur
        final edge = ((x / (fw * 0.35)).clamp(0.0, 1.0)) * (((fw - x) / (fw * 0.12)).clamp(0.0, 1.0));
        final r = Rect.fromLTWH(fo.dx + x, fo.dy + dy, sw + 0.8, fh);
        canvas.drawRect(
            r,
            Paint()
              ..color = Color.lerp(red, shade > 0 ? const Color(0xFFFF4A52) : const Color(0xFFA0050F), shade.abs() * 0.45)!
                  .withValues(alpha: 0.88 * edge)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      }
    } else {
      // gece: emblemin çevresinde soğuk, hafif hale
      canvas.drawCircle(
          emblemOrigin + geo.outerCenter,
          geo.outerRadius * 1.9,
          Paint()
            ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: emblemOrigin + geo.outerCenter, radius: geo.outerRadius * 1.9)));
    }
    canvas.save();
    canvas.translate(emblemOrigin.dx, emblemOrigin.dy);
    _metalEmblem(canvas, geo, onRed: !dark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(JuzzioTurkFlagPainter o) => o.t != t || o.dark != dark || o.accent != accent || o.band != band || o.width != width;
}
