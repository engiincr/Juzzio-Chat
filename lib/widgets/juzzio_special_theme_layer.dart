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
          final o = dark ? 1.0 : 0.92;
          return Stack(clipBehavior: Clip.hardEdge, children: [
            // ikinci şerit: hikâyelerin arkasında çıplak ağaçlar + turuncu gök
            Positioned(left: -sw * 0.10, top: band * 0.50, child: _img(kHalloweenMoonClouds, sw * 1.2, 2048 / 1536, 0.75 * o)),
            // şato + dolunay (sağ üst)
            Positioned(left: sw * 0.22, top: band * 0.12, child: _img(kHalloweenCastle, sw * 0.86, 2048 / 1152, o)),
            // kabaklı ağaç (sol üst)
            Positioned(left: -sw * 0.10, top: band * 0.16, child: _img(kHalloweenTree, sw * 0.56, 1.0, o)),
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
      ..moveTo(-width * 0.05, band * 0.52)
      ..quadraticBezierTo(width * 0.45, band * 0.05, width * 1.05, band * 0.02);
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

  @override
  void paint(Canvas canvas, Size size) {
    _swoosh(canvas);
    final g = (band * 0.36).clamp(70.0, 170.0);
    final geo = JuzzioTurkFlagGeometry(g);
    final origin = Offset(width - geo.length - width * 0.02, band * 0.30);
    if (dark) {
      // gece: gümüş ay-yıldız, hafif parıltı (referanstaki gibi kırmızı zemin yok)
      canvas.save();
      canvas.translate(origin.dx + g * 0.1, origin.dy);
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      _emblem(canvas, geo, glow);
      final silver = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFC9CED6), Color(0xFF8E959F)],
        ).createShader(Rect.fromLTWH(0, 0, geo.length, g));
      _emblem(canvas, geo, silver);
      canvas.restore();
      return;
    }
    // gündüz: dalgalanan kırmızı bayrak (şeritler halinde sinüs dalgası + kıvrım gölgesi)
    const strips = 36;
    final sw = geo.length / strips;
    final amp = g * 0.06;
    for (var i = 0; i < strips; i++) {
      final x = i * sw;
      final phase = (x / geo.length) * 2 * math.pi * 1.3 - t * 2 * math.pi * 4;
      final dy = math.sin(phase) * amp * (x / geo.length);
      final shade = math.cos(phase);
      canvas.save();
      canvas.translate(origin.dx, origin.dy + dy);
      canvas.clipRect(Rect.fromLTWH(x, -amp, sw + 0.8, g + amp * 2));
      // hafif saydam kenar: soldaki uç yumuşakça kaybolur (referanstaki gibi)
      final edge = (x / (geo.length * 0.18)).clamp(0.0, 1.0);
      canvas.drawRect(Rect.fromLTWH(0, 0, geo.length, g), Paint()..color = red.withValues(alpha: 0.92 * edge));
      _emblem(canvas, geo, Paint()..color = Colors.white.withValues(alpha: edge));
      canvas.drawRect(
          Rect.fromLTWH(x, 0, sw + 0.8, g),
          Paint()
            ..color = (shade > 0 ? Colors.white : Colors.black).withValues(alpha: (shade.abs() * 0.14) * edge));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(JuzzioTurkFlagPainter o) => o.t != t || o.dark != dark || o.accent != accent || o.band != band || o.width != width;
}
