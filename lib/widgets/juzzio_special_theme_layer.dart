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
import 'juzzio_weather_hd.dart' show juzzioHdBandHeight, juzzioHdSceneWidth, kJuzzioHdSearchTop;

const String kHalloweenCastle = 'assets/special/halloween/castle_scene.webp';
const String kHalloweenTree = 'assets/special/halloween/pumpkin_tree.webp';
const String kHalloweenMoonClouds = 'assets/special/halloween/moon_clouds.webp';
const List<String> kJuzzioHalloweenAssets = [kHalloweenCastle, kHalloweenTree, kHalloweenMoonClouds];

/// GM-037: paketteki karışık Halloween görsellerinden temiz kırpılıp referansın mor-turuncu
/// renklerine göre renklendirilmiş parçalar (en/boy oranları)
const double kHwCastleAspect = 1200 / 600;

/// GM-029: HD dalgalanan Türk bayrağı (resmî geometri; gece saten + gümüş amblem)
const String kTurkFlagDay = 'assets/special/turkey/flag_day.webp';
const String kTurkFlagNight = 'assets/special/turkey/flag_night.webp';
const double kTurkFlagAspect = 1300 / 660;
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
        return ValueListenableBuilder<double?>(
          valueListenable: kJuzzioHdSearchTop,
          builder: (context, top, _) {
            // GM-037: konumlar Sohbetler arama kutusunun üst kenarına göre (referans ölçüleri, birim = genişlik)
            // Sohbetler sekmesi görünmüyorsa (başka sekme) dekor çizilmez; düğmelere binmez
            if (top == null) return const SizedBox.shrink();
            final a = top;
            if (theme == JuzzioSpecialTheme.halloween) {
              // Referans (Engin'in Halloween ekranı): mor-turuncu gök, sağda dolunaylı şato + yarasalar
              // (alt kısmı arama kutusunun ardında), solda kabaklı ağaç, arama altında çıplak ağaçlar şeridi.
              final o = dark ? 1.0 : 0.95;
              final bottom = a + sw * 0.44;
              return Stack(clipBehavior: Clip.hardEdge, children: [
                // mor gök: üstte koyu mor, ortada canlı mor, arama hizasında turuncu ufuk, altta sayfaya erir
                Positioned(
                  left: 0,
                  top: 0,
                  width: sw,
                  height: bottom,
                  child: DecoratedBox(
                    key: const ValueKey('gm031-sky'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF1E0F2C).withValues(alpha: 0.92 * o),
                          const Color(0xFF4A2468).withValues(alpha: 0.88 * o),
                          const Color(0xFF7A3A63).withValues(alpha: 0.80 * o),
                          const Color(0xFFB0522F).withValues(alpha: 0.55 * o),
                          const Color(0xFF241229).withValues(alpha: 0.70 * o),
                          const Color(0xFF140A18).withValues(alpha: 0.0),
                        ],
                        stops: [0.0, (a - sw * 0.30) / bottom, (a - sw * 0.08) / bottom, a / bottom, (a + sw * 0.22) / bottom, 1.0]
                            .map((e) => e.clamp(0.0, 1.0))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                // ayın ve şatonun ardındaki turuncu hâle
                Positioned(
                  left: sw * 0.69 - sw * 0.42,
                  top: a - sw * 0.10 - sw * 0.30,
                  width: sw * 0.84,
                  height: sw * 0.60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        const Color(0xFFFF8A2A).withValues(alpha: 0.45 * o),
                        const Color(0xFFFF8A2A).withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
                Positioned(left: -sw * 0.04, top: a + sw * 0.06, child: _img(kHalloweenMoonClouds, sw * 0.58, kHwBandAspect, 0.95 * o)),
                Positioned(
                    left: sw * 0.46,
                    top: a + sw * 0.05,
                    child: Transform.flip(flipX: true, child: _img(kHalloweenMoonClouds, sw * 0.60, kHwBandAspect, 0.95 * o))),
                Positioned(left: sw * 0.40, top: a - sw * 0.27, child: _img(kHalloweenCastle, sw * 0.60, kHwCastleAspect, o)),
                Positioned(left: -sw * 0.06, top: a - sw * 0.30, child: _img(kHalloweenTree, sw * 0.46, kHwTreeAspect, o)),
                // uçan yarasalar (referans: gökte dağınık)
                Positioned.fill(child: AnimatedBuilder(animation: loop, builder: (context, _) => CustomPaint(painter: JuzzioBatsPainter(t: loop.value, width: sw, anchor: a)))),
              ]);
            }
            // Referans (Engin'in Türk bayraklı ekranı): dalgalanan Türk bayrağı başlık düğmelerinin altında,
            // ay-yıldız ≈ (0.66W, arama üstü − 0.07W), bayrak sağ kenara uzanır; gece koyu saten kırmızı +
            // gümüş ay-yıldız, gündüz resmî kırmızı + beyaz ay-yıldız; soldan limon ışık yayı.
            final fw = sw * 0.60;
            return AnimatedBuilder(
              animation: loop,
              builder: (context, _) {
                final sway = math.sin(loop.value * 2 * math.pi * 3) * sw * 0.006;
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: JuzzioTurkFlagPainter(
                          t: loop.value, dark: dark, accent: accent, band: band, width: sw, anchor: a, swooshOnly: true),
                    ),
                  ),
                  Positioned(
                    key: const ValueKey('gm029-flag'),
                    left: sw * 0.4385 + sway,
                    top: a - sw * 0.222,
                    child: _img(dark ? kTurkFlagNight : kTurkFlagDay, fw, kTurkFlagAspect, dark ? 0.95 : 1.0),
                  ),
                ]);
              },
            );
          },
        );
      }),
    );
  }
}

/// Dalgalanan Türk bayrağı (gündüz) / gümüş ay-yıldız (gece) + vurgu renginde ışık yayı
/// GM-031: referanstaki gibi gökte süzülen küçük yarasa siluetleri
class JuzzioBatsPainter extends CustomPainter {
  JuzzioBatsPainter({required this.t, required this.width, required this.anchor});
  final double t;
  final double width;
  final double anchor;

  static const List<(double, double, double)> _bats = [
    (0.56, -0.36, 1.0), (0.64, -0.40, 0.7), (0.86, -0.33, 0.85), (0.92, -0.20, 0.6), (0.36, -0.28, 0.55), (0.48, -0.20, 0.5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF140A18);
    for (var i = 0; i < _bats.length; i++) {
      final (bx, by, sc) = _bats[i];
      final flap = math.sin((t * 24 + i * 0.7) * 2 * math.pi);
      final c = Offset(width * bx + math.sin((t * 2 + i) * 2 * math.pi) * width * 0.01, anchor + width * by);
      final w = width * 0.035 * sc, h = w * (0.35 + 0.15 * flap);
      final p = Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(c.dx - w * 0.35, c.dy - h, c.dx - w, c.dy - h * 0.3)
        ..quadraticBezierTo(c.dx - w * 0.7, c.dy + h * 0.1, c.dx - w * 0.55, c.dy + h * 0.25)
        ..quadraticBezierTo(c.dx - w * 0.3, c.dy + h * 0.05, c.dx, c.dy + h * 0.3)
        ..quadraticBezierTo(c.dx + w * 0.3, c.dy + h * 0.05, c.dx + w * 0.55, c.dy + h * 0.25)
        ..quadraticBezierTo(c.dx + w * 0.7, c.dy + h * 0.1, c.dx + w, c.dy - h * 0.3)
        ..quadraticBezierTo(c.dx + w * 0.35, c.dy - h, c.dx, c.dy)
        ..close();
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(JuzzioBatsPainter o) => o.t != t || o.width != width || o.anchor != anchor;
}

class JuzzioTurkFlagPainter extends CustomPainter {
  JuzzioTurkFlagPainter(
      {required this.t, required this.dark, required this.accent, required this.band, required this.width, double? anchor, this.swooshOnly = false})
      : anchor = anchor ?? band * 0.34;

  /// GM-029: bayrak artık HD dalgalanan bayrak görseliyle çizilir; ressam yalnız ışık yayını çizer
  final bool swooshOnly;
  final double t;
  final bool dark;
  final Color accent;
  final double band;

  /// GM-037: arama kutusunun üst kenarı (global y); amblem ve ışık yayı buna göre yerleşir
  final double anchor;
  final double width;

  static const Color red = Color(0xFFE30A17); // resmî bayrak kırmızısı

  void _swoosh(Canvas canvas) {
    final path = Path()
      ..moveTo(-width * 0.02, anchor - width * 0.05)
      ..cubicTo(width * 0.30, anchor - width * 0.01, width * 0.55, anchor - width * 0.20, width * 0.92, anchor - width * 0.40);
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
    if (swooshOnly) return;
    // Referans (Engin'in görseli): ay-yıldız başlık düğmelerinin altında, ekranın ortasının biraz sağında
    // ölçü: hilal çapı ≈ 0.125W, merkez ≈ (0.60W, arama üstü − 0.07W)
    final g = (width * 0.25).clamp(60.0, 140.0);
    final geo = JuzzioTurkFlagGeometry(g);
    final emblemOrigin = Offset(width * 0.60 - g * 0.5, anchor - width * 0.07 - g * 0.5);
    if (!dark) {
      // gündüz: emblemin arkasında yumuşak kenarlı, dalgalanan kırmızı bayrak kumaşı
      final fw = width * 0.62, fh = g * 1.05;
      final fo = Offset(emblemOrigin.dx - width * 0.03, emblemOrigin.dy - g * 0.05);
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
  bool shouldRepaint(JuzzioTurkFlagPainter o) => o.t != t || o.dark != dark || o.accent != accent || o.band != band || o.width != width || o.anchor != anchor;
}
