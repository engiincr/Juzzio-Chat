// =============================================================================
// JUZZIO 2.1 — "Gökyüzü 2.1" hava ambiyansı (baştan tasarım)
//
//  Ana ekranın arkasında, dokunmayı engellemeyen hafif bir gökyüzü katmanı.
//  Konumun GERÇEK gün doğumu/batımı ve ülke saatine (Open-Meteo, timezone=auto) göre:
//   • Gök rengi: gece (lacivert) · şafak (pembe-şeftali) · gündüz (açık mavi) ·
//     altın saat (kehribar) · alacakaranlık (mor-magenta). Geçişler dakikalarca sürer.
//   • Güneş gün boyu gökte yay çizerek ilerler (doğuda doğar, batıda batar);
//     altın saatte büyür ve turuncuya döner.
//   • Ay yalnız konumun gecesinde, gerçek Ay evresiyle yay boyunca ilerler.
//   • Yıldızlar ayrı ayrı göz kırpar; açık gecelerde ara sıra kayan yıldız geçer.
//     Bulutluluk arttıkça yıldızlar azalır.
//   • Bulutlar iki derinlikte (parallaks) süzülür; sayısı bulutluluk yüzdesine,
//     rengi günün saatine göre (altın saatte turuncu kenar, fırtınada koyu gri).
//   • Yağmur iki katmanlı; yoğunluk yağış miktarına, eğim rüzgâra göre; zeminde
//     küçük sıçrama halkaları. Kar iki katmanlı, rüzgârla salınır. Sis kayan bantlar.
//   • Şimşek: bulut içinde parlama + dallanan çakım + ardıl ışıma (ayrı ressam).
//  Hepsi kodla çizilir (görsel/fotoğraf yok). "Hareketi azalt"ta durağan çizilir.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/juzzio_weather_service.dart';
import 'juzzio_moon_phase.dart';

/// Gökyüzü evresi
enum JuzzioSkyPhase { night, dawn, day, golden, dusk }

/// Konumun gün doğumu/batımına göre evre (saf; test edilir).
/// Gün doğumu/batımı bilinmiyorsa [localHour] (konumun saati) kullanılır.
JuzzioSkyPhase juzzioSkyPhase(
  DateTime nowUtc, {
  List<DateTime> sunrises = const [],
  List<DateTime> sunsets = const [],
  bool? isDay,
  int? localHour,
}) {
  final now = nowUtc.toUtc();
  if (sunrises.isNotEmpty && sunsets.isNotEmpty) {
    for (final rise in sunrises) {
      final d = now.difference(rise).inMinutes;
      if (d >= -40 && d < 30) return JuzzioSkyPhase.dawn;
    }
    for (final sset in sunsets) {
      final d = now.difference(sset).inMinutes;
      if (d >= -60 && d < 0) return JuzzioSkyPhase.golden;
      if (d >= 0 && d < 40) return JuzzioSkyPhase.dusk;
    }
    final p = juzzioSunProgress(now, sunrises, sunsets);
    if (p != null) return JuzzioSkyPhase.day;
    return JuzzioSkyPhase.night;
  }
  final h = (localHour ?? now.hour) % 24;
  if (isDay == false) return (h >= 17 && h < 20) ? JuzzioSkyPhase.dusk : JuzzioSkyPhase.night;
  if (h >= 5 && h < 7) return JuzzioSkyPhase.dawn;
  if (h >= 7 && h < 16) return JuzzioSkyPhase.day;
  if (h >= 16 && h < 18) return isDay == true ? JuzzioSkyPhase.golden : JuzzioSkyPhase.dusk;
  if (h >= 18 && h < 20) return isDay == true ? JuzzioSkyPhase.golden : JuzzioSkyPhase.dusk;
  return isDay == true ? JuzzioSkyPhase.day : JuzzioSkyPhase.night;
}

/// Güneşin gökteki ilerleyişi 0 (doğuş) … 1 (batış); gündüz değilse null (saf).
double? juzzioSunProgress(DateTime nowUtc, List<DateTime> sunrises, List<DateTime> sunsets) {
  final now = nowUtc.toUtc();
  for (final rise in sunrises) {
    DateTime? sset;
    for (final s in sunsets) {
      if (s.isAfter(rise) && (sset == null || s.isBefore(sset))) sset = s;
    }
    if (sset == null) continue;
    if (!now.isBefore(rise) && now.isBefore(sset)) {
      return now.difference(rise).inSeconds / sset.difference(rise).inSeconds;
    }
  }
  return null;
}

/// Gecenin ilerleyişi 0 (batış) … 1 (doğuş); bilinmiyorsa saate göre (saf).
double juzzioNightProgress(DateTime nowUtc, List<DateTime> sunrises, List<DateTime> sunsets, {int? localHour}) {
  final now = nowUtc.toUtc();
  DateTime? lastSet;
  for (final s in sunsets) {
    if (!s.isAfter(now) && (lastSet == null || s.isAfter(lastSet))) lastSet = s;
  }
  DateTime? nextRise;
  for (final r in sunrises) {
    if (r.isAfter(now) && (nextRise == null || r.isBefore(nextRise))) nextRise = r;
  }
  lastSet ??= nextRise?.subtract(const Duration(hours: 12));
  if (lastSet != null && nextRise != null && nextRise.isAfter(lastSet)) {
    return (now.difference(lastSet).inSeconds / nextRise.difference(lastSet).inSeconds).clamp(0.0, 1.0);
  }
  final h = ((localHour ?? now.hour) + 24 - 19) % 24; // 19:00 → 0, 06:00 → 11
  return (h / 11).clamp(0.0, 1.0);
}

/// Bulut sayısı: hava türü + bulutluluk yüzdesi (saf)
int juzzioCloudCount(JuzzioWeatherKind k, double? cloudCover) {
  final byKind = switch (k) {
    JuzzioWeatherKind.clear => 1,
    JuzzioWeatherKind.clouds => 5,
    JuzzioWeatherKind.fog => 3,
    JuzzioWeatherKind.drizzle => 5,
    JuzzioWeatherKind.rain => 6,
    JuzzioWeatherKind.snow => 5,
    JuzzioWeatherKind.thunder => 7,
  };
  if (cloudCover == null) return byKind;
  final byCover = (cloudCover.clamp(0, 100) / 100 * 7).round();
  return math.max(k == JuzzioWeatherKind.clear ? 0 : 2, math.min(7, math.max(byCover, byKind - 2)));
}

/// Yağmur damlası sayısı: yağış miktarına göre (saf)
int juzzioRainDrops(JuzzioWeatherKind k, double? precipitationMm) {
  final base = switch (k) {
    JuzzioWeatherKind.drizzle => 34,
    JuzzioWeatherKind.rain => 70,
    JuzzioWeatherKind.thunder => 90,
    _ => 0,
  };
  if (base == 0 || precipitationMm == null) return base;
  return (base * (0.7 + (precipitationMm.clamp(0, 8) / 8) * 0.6)).round().clamp(20, 110);
}

/// Rüzgâra göre yağmur/kar eğimi (saf): 0 dik … 0.55 yatık
double juzzioWindSlant(double? windKmh) => ((windKmh ?? 10) / 60).clamp(0.08, 0.55);

/// Yıldızlar ne kadar görünür (0..1) (saf)
double juzzioStarVisibility(JuzzioSkyPhase p, double? cloudCover) {
  final byPhase = switch (p) {
    JuzzioSkyPhase.night => 1.0,
    JuzzioSkyPhase.dusk => 0.45,
    JuzzioSkyPhase.dawn => 0.25,
    _ => 0.0,
  };
  final clear = 1 - ((cloudCover ?? 20).clamp(0, 100) / 100) * 0.85;
  return byPhase * clear;
}

/// Gök renkleri (üst, orta) — evreye ve havaya göre
List<Color> juzzioSkyColors(JuzzioSkyPhase p, JuzzioWeatherKind k) {
  final stormy = k == JuzzioWeatherKind.thunder || k == JuzzioWeatherKind.rain;
  final grey = k == JuzzioWeatherKind.clouds || k == JuzzioWeatherKind.fog || k == JuzzioWeatherKind.drizzle;
  List<Color> c = switch (p) {
    JuzzioSkyPhase.night => const [Color(0xFF0B1240), Color(0xFF1B1F5E)],
    JuzzioSkyPhase.dawn => const [Color(0xFF5B4B9A), Color(0xFFFF9E8A)],
    JuzzioSkyPhase.day => const [Color(0xFF3D8BFF), Color(0xFF9FD3FF)],
    JuzzioSkyPhase.golden => const [Color(0xFFFF8A3D), Color(0xFFFFC46B)],
    JuzzioSkyPhase.dusk => const [Color(0xFF5A2A86), Color(0xFFE0568A)],
  };
  if (stormy) c = [Color.lerp(c[0], const Color(0xFF1C2230), 0.65)!, Color.lerp(c[1], const Color(0xFF39404F), 0.65)!];
  if (grey) c = [Color.lerp(c[0], const Color(0xFF6B7487), 0.45)!, Color.lerp(c[1], const Color(0xFF9AA3B4), 0.45)!];
  return c;
}

/// Tek sahnenin bütün bilgisi (ressama verilir)
class JuzzioSkyScene {
  const JuzzioSkyScene({
    required this.kind,
    required this.phase,
    this.sunProgress,
    required this.nightProgress,
    required this.moonPhase,
    this.cloudCover,
    this.precipitation,
    this.windSpeed,
  });

  factory JuzzioSkyScene.from(JuzzioWeatherState st, DateTime nowUtc) {
    final off = st.utcOffsetSeconds;
    final localHour = off == null ? DateTime.now().hour : juzzioLocationNow(nowUtc, off).hour;
    return JuzzioSkyScene(
      kind: st.kind,
      phase: juzzioSkyPhase(nowUtc, sunrises: st.sunrises, sunsets: st.sunsets, isDay: st.isDay, localHour: localHour),
      sunProgress: juzzioSunProgress(nowUtc, st.sunrises, st.sunsets) ??
          (st.isDay && st.sunrises.isEmpty ? ((localHour - 6).clamp(0, 12) / 12) : null),
      nightProgress: juzzioNightProgress(nowUtc, st.sunrises, st.sunsets, localHour: localHour),
      moonPhase: juzzioMoonPhase(nowUtc),
      cloudCover: st.cloudCover,
      precipitation: st.precipitation,
      windSpeed: st.windSpeed,
    );
  }

  final JuzzioWeatherKind kind;
  final JuzzioSkyPhase phase;
  final double? sunProgress;
  final double nightProgress;
  final double moonPhase;
  final double? cloudCover;
  final double? precipitation;
  final double? windSpeed;

  bool get showSun => sunProgress != null && phase != JuzzioSkyPhase.night;
  bool get showMoon => phase == JuzzioSkyPhase.night || phase == JuzzioSkyPhase.dusk;

  /// Görsel olarak aynı sahne mi (çapraz geçiş gerekmez)
  bool same(JuzzioSkyScene o) => o.kind == kind && o.phase == phase;
}

class JuzzioSky21Painter extends CustomPainter {
  JuzzioSky21Painter({required this.t, required this.scene, required this.dark, required this.still}) : super(repaint: t);

  final Animation<double> t;
  final JuzzioSkyScene scene;
  final bool dark;
  final bool still;

  static final List<Offset> _seeds = List<Offset>.generate(140, (i) {
    final r = math.Random(i * 92821 + 7);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final v = still ? 0.0 : t.value;
    final a = dark ? 1.0 : 0.7; // açık temada daha hafif
    _sky(canvas, size, a);
    _stars(canvas, size, v, a);
    if (scene.showSun) _sun(canvas, size, v, a);
    if (scene.showMoon) _moon(canvas, size, a);
    final clouds = juzzioCloudCount(scene.kind, scene.cloudCover);
    _clouds(canvas, size, v, a, clouds, far: true);
    switch (scene.kind) {
      case JuzzioWeatherKind.drizzle:
      case JuzzioWeatherKind.rain:
      case JuzzioWeatherKind.thunder:
        _rain(canvas, size, v, a);
      case JuzzioWeatherKind.snow:
        _snow(canvas, size, v, a);
      case JuzzioWeatherKind.fog:
        _fog(canvas, size, v, a);
      case JuzzioWeatherKind.clear:
      case JuzzioWeatherKind.clouds:
        break;
    }
    _clouds(canvas, size, v, a, clouds, far: false);
  }

  // 1) Gök rengi: üstte hafif, aşağı doğru tamamen saydam (içerik okunur kalır)
  void _sky(Canvas canvas, Size size, double a) {
    final c = juzzioSkyColors(scene.phase, scene.kind);
    final r = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c[0].withValues(alpha: 0.26 * a), c[1].withValues(alpha: 0.12 * a), c[1].withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(r),
    );
  }

  // 2) Göz kırpan yıldızlar + ara sıra kayan yıldız
  void _stars(Canvas canvas, Size size, double v, double a) {
    final vis = juzzioStarVisibility(scene.phase, scene.cloudCover);
    if (vis <= 0.01) return;
    final n = (60 * vis).round().clamp(8, 60);
    for (var i = 0; i < n; i++) {
      final s = _seeds[i];
      final tw = still ? 0.7 : 0.45 + 0.55 * (0.5 + 0.5 * math.sin((v * 6 + s.dx * 9 + i * 0.7) * 2 * math.pi));
      final r = 0.6 + (i % 4) * 0.35;
      final o = Offset(s.dx * size.width, s.dy * size.height * 0.34);
      canvas.drawCircle(o, r, Paint()..color = Colors.white.withValues(alpha: 0.75 * tw * vis * a));
      if (i % 9 == 0) {
        canvas.drawCircle(o, r * 3.2, Paint()..color = const Color(0xFFBFD0FF).withValues(alpha: 0.10 * tw * vis * a));
      }
    }
    // kayan yıldız: açık gecede, her turda bir kez (~1 sn)
    if (!still && scene.phase == JuzzioSkyPhase.night && (scene.cloudCover ?? 0) < 40) {
      const at = 0.62, len = 0.035;
      final d = v - at;
      if (d >= 0 && d < len) {
        final k = d / len;
        final start = Offset(size.width * 0.18, size.height * 0.05);
        final dir = Offset(size.width * 0.42, size.height * 0.11);
        final head = start + dir * k;
        final tail = head - dir * 0.22;
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.85 * (1 - k) * a)])
                .createShader(Rect.fromPoints(tail, head)),
        );
      }
    }
  }

  /// Yay üzerindeki konum: p 0 (sol/doğu) … 1 (sağ/batı)
  Offset _arc(Size size, double p) {
    final x = size.width * (0.08 + 0.84 * p);
    final y = size.height * (0.20 - 0.14 * math.sin(math.pi * p));
    return Offset(x, y);
  }

  // 3) Güneş: gerçek ilerleyişe göre yayda; altın saatte büyük ve turuncu
  void _sun(Canvas canvas, Size size, double v, double a) {
    final p = scene.sunProgress!.clamp(0.0, 1.0);
    final c = _arc(size, p);
    final golden = scene.phase == JuzzioSkyPhase.golden || scene.phase == JuzzioSkyPhase.dawn;
    final cover = ((scene.cloudCover ?? 15).clamp(0, 100) / 100);
    final dim = (1 - cover * 0.75) * a;
    final core = golden ? const Color(0xFFFFB067) : const Color(0xFFFFF1B8);
    final edge = golden ? const Color(0xFFFF6A3D) : const Color(0xFFFFC233);
    final r = size.shortestSide * (golden ? 0.06 : 0.045);
    // geniş hâle
    final halo = r * (golden ? 9 : 7);
    canvas.drawCircle(
      c,
      halo,
      Paint()
        ..shader = RadialGradient(colors: [edge.withValues(alpha: 0.30 * dim), edge.withValues(alpha: 0.08 * dim), edge.withValues(alpha: 0)], stops: const [0, 0.35, 1])
            .createShader(Rect.fromCircle(center: c, radius: halo)),
    );
    // yavaş dönen ince ışınlar
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(still ? 0 : v * 2 * math.pi * 0.25);
    final ray = Paint()..color = core.withValues(alpha: 0.16 * dim);
    for (var j = 0; j < 12; j++) {
      final ang = j * math.pi / 6;
      final len = r * (j.isEven ? 3.2 : 2.4);
      final path = Path()
        ..moveTo(math.cos(ang - 0.05) * r * 1.2, math.sin(ang - 0.05) * r * 1.2)
        ..lineTo(math.cos(ang) * len, math.sin(ang) * len)
        ..lineTo(math.cos(ang + 0.05) * r * 1.2, math.sin(ang + 0.05) * r * 1.2)
        ..close();
      canvas.drawPath(path, ray);
    }
    canvas.restore();
    // disk
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.3, -0.3), colors: [Colors.white.withValues(alpha: 0.95 * dim), core.withValues(alpha: 0.9 * dim), edge.withValues(alpha: 0.85 * dim)], stops: const [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  // 4) Ay: gece boyunca yayda, gerçek evre ve kraterlerle
  void _moon(Canvas canvas, Size size, double a) {
    final p = scene.phase == JuzzioSkyPhase.dusk ? 0.04 : scene.nightProgress;
    final c = _arc(size, p);
    final r = size.shortestSide * 0.04;
    final cover = ((scene.cloudCover ?? 15).clamp(0, 100) / 100);
    final alpha = ((1 - cover * 0.7) * (scene.phase == JuzzioSkyPhase.dusk ? 0.55 : 0.9) * a).clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      r * 5,
      Paint()
        ..shader = RadialGradient(colors: [const Color(0xFFCAD6FF).withValues(alpha: 0.22 * alpha), const Color(0xFFCAD6FF).withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r * 5)),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    juzzioPaintMoon(canvas, scene.moonPhase, r, alpha: alpha, glow: false);
    canvas.restore();
  }

  Color get _cloudTop {
    if (scene.kind == JuzzioWeatherKind.thunder) return const Color(0xFF5A6273);
    if (scene.kind == JuzzioWeatherKind.rain) return const Color(0xFF7D879A);
    return switch (scene.phase) {
      JuzzioSkyPhase.night => const Color(0xFF8D97B8),
      JuzzioSkyPhase.dawn => const Color(0xFFFFD2C4),
      JuzzioSkyPhase.golden => const Color(0xFFFFD9A8),
      JuzzioSkyPhase.dusk => const Color(0xFFE7B5D6),
      JuzzioSkyPhase.day => const Color(0xFFFFFFFF),
    };
  }

  Color get _cloudBottom {
    if (scene.kind == JuzzioWeatherKind.thunder) return const Color(0xFF2E3442);
    return switch (scene.phase) {
      JuzzioSkyPhase.night => const Color(0xFF3B4366),
      JuzzioSkyPhase.dawn => const Color(0xFF9C7FB8),
      JuzzioSkyPhase.golden => const Color(0xFFE08A5A),
      JuzzioSkyPhase.dusk => const Color(0xFF7A4C8E),
      JuzzioSkyPhase.day => const Color(0xFFB8C7DE),
    };
  }

  // 5) Katmanlı bulutlar: uzak (küçük, yavaş, soluk) ve yakın (büyük, hızlı)
  void _clouds(Canvas canvas, Size size, double v, double a, int count, {required bool far}) {
    if (count <= 0) return;
    final farN = (count / 2).ceil();
    final n = far ? farN : count - farN;
    final top = _cloudTop, bottom = _cloudBottom;
    final baseAlpha = (far ? 0.18 : 0.30) * a * (dark ? 1 : 1.25);
    for (var i = 0; i < n; i++) {
      final s = _seeds[far ? 80 + i : 100 + i];
      final speed = far ? 0.06 + 0.03 * (i % 3) : 0.12 + 0.05 * (i % 3);
      final w = size.width * (far ? 0.30 + 0.12 * s.dy : 0.46 + 0.18 * s.dy);
      final x = ((s.dx + (still ? 0 : v * speed)) % 1.0) * (size.width + w) - w / 2;
      final y = size.height * (far ? 0.05 + 0.08 * s.dy : 0.10 + 0.12 * s.dy);
      _cloud(canvas, Offset(x, y), w, top, bottom, baseAlpha.clamp(0.0, 1.0), i);
    }
  }

  void _cloud(Canvas canvas, Offset c, double w, Color top, Color bottom, double alpha, int seed) {
    final h = w * 0.34;
    final r = math.Random(seed * 31 + 5);
    final puffs = <Rect>[];
    for (var k = 0; k < 5; k++) {
      final px = c.dx - w * 0.38 + w * 0.19 * k + (r.nextDouble() - 0.5) * w * 0.06;
      final pr = h * (0.42 + r.nextDouble() * 0.34) * (k == 0 || k == 4 ? 0.75 : 1);
      puffs.add(Rect.fromCircle(center: Offset(px, c.dy - pr * 0.25), radius: pr));
    }
    final bounds = Rect.fromLTRB(c.dx - w / 2, c.dy - h, c.dx + w / 2, c.dy + h * 0.5);
    final paint = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top.withValues(alpha: alpha), bottom.withValues(alpha: alpha * 0.85)])
          .createShader(bounds);
    final path = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(c.dx - w * 0.45, c.dy - h * 0.1, c.dx + w * 0.45, c.dy + h * 0.32), Radius.circular(h * 0.3)));
    for (final p in puffs) {
      path.addOval(p);
    }
    canvas.drawPath(path, paint);
  }

  // 6) Yağmur: uzak + yakın katman, rüzgâr eğimi, zeminde sıçrama halkaları
  void _rain(Canvas canvas, Size size, double v, double a) {
    final drops = juzzioRainDrops(scene.kind, scene.precipitation);
    final slant = juzzioWindSlant(scene.windSpeed);
    final col = dark ? const Color(0xFFC7D8FF) : const Color(0xFF5C76AA);
    for (var layer = 0; layer < 2; layer++) {
      final near = layer == 1;
      final n = near ? drops ~/ 2 : drops - drops ~/ 2;
      final len = near ? 20.0 : 10.0;
      final p = Paint()
        ..color = col.withValues(alpha: (near ? 0.30 : 0.16) * a)
        ..strokeWidth = near ? 1.4 : 0.9
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < n; i++) {
        final s = _seeds[(i + layer * 60) % _seeds.length];
        final speed = (near ? 9.0 : 6.0) + (i % 4);
        final y = ((s.dy + v * speed) % 1.0) * (size.height + 40) - 20;
        final x = (s.dx * size.width + y * slant) % size.width;
        canvas.drawLine(Offset(x, y), Offset(x - len * slant, y - len), p);
      }
    }
    if (still) return;
    // sıçramalar
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var i = 0; i < 10; i++) {
      final s = _seeds[120 + i];
      final ph = (v * 7 + s.dy) % 1.0;
      final c = Offset(s.dx * size.width, size.height * (0.90 + 0.08 * s.dy));
      ring.color = col.withValues(alpha: 0.22 * (1 - ph) * a);
      canvas.drawOval(Rect.fromCenter(center: c, width: 4 + 16 * ph, height: 1.5 + 5 * ph), ring);
    }
  }

  // 7) Kar: iki katman, rüzgârla salınım
  void _snow(Canvas canvas, Size size, double v, double a) {
    final slant = juzzioWindSlant(scene.windSpeed);
    for (var layer = 0; layer < 2; layer++) {
      final near = layer == 1;
      final p = Paint()..color = Colors.white.withValues(alpha: (near ? 0.65 : 0.38) * a);
      for (var i = 0; i < (near ? 26 : 34); i++) {
        final s = _seeds[(i + layer * 40) % _seeds.length];
        final speed = (near ? 1.6 : 1.0) + (i % 4) * 0.3;
        final y = ((s.dy + v * speed) % 1.0) * (size.height + 20) - 10;
        final x = (s.dx * size.width + y * slant * 0.5 + math.sin((v * 8 + i) * math.pi) * (near ? 14 : 8)) % size.width;
        canvas.drawCircle(Offset(x, y), near ? 1.8 + (i % 3) * 0.8 : 1.0 + (i % 3) * 0.4, p);
      }
    }
  }

  // 8) Sis: yavaş kayan yumuşak bantlar
  void _fog(Canvas canvas, Size size, double v, double a) {
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.45 + 0.17 * i);
      final dx = (still ? 0 : math.sin((v + i * 0.3) * 2 * math.pi)) * size.width * 0.06;
      final r = Rect.fromLTWH(-size.width * 0.1 + dx, y, size.width * 1.2, size.height * 0.16);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.09 * a), Colors.white.withValues(alpha: 0)],
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(covariant JuzzioSky21Painter old) =>
      !identical(old.scene, scene) || old.dark != dark || old.still != still;
}

/// 2.1 şimşek: bulut içi parlama + dallanan çakım + ardıl ışıma.
/// [seed] her çakımda değişir; bazı çakımlar yalnız "bulut içi" parlamadır.
class JuzzioLightning21Painter extends CustomPainter {
  JuzzioLightning21Painter({required this.t, required this.seed}) : super(repaint: t);
  final Animation<double> t;
  final int seed;

  /// İki-üç darbeli parlaklık eğrisi (0..1) (saf; test edilir)
  static double intensity(double v) {
    if (v <= 0 || v >= 1) return 0;
    double pulse(double c, double w) => math.max(0, 1 - ((v - c) / w).abs());
    return math.min(1, pulse(0.06, 0.06) + pulse(0.22, 0.08) * 0.9 + pulse(0.40, 0.10) * 0.5 + pulse(0.65, 0.30) * 0.25);
  }

  List<Offset> _bolt(math.Random r, Offset from, Offset to, int segs, double jag) {
    final pts = <Offset>[from];
    for (var i = 1; i < segs; i++) {
      final k = i / segs;
      final base = Offset.lerp(from, to, k)!;
      final n = Offset(-(to.dy - from.dy), to.dx - from.dx);
      final len = n.distance == 0 ? 1.0 : n.distance;
      pts.add(base + n / len * ((r.nextDouble() - 0.5) * 2 * jag));
    }
    pts.add(to);
    return pts;
  }

  void _stroke(Canvas canvas, List<Offset> pts, double width, double alpha) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFA9C8FF).withValues(alpha: 0.35 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = intensity(t.value);
    if (a <= 0.001) return;
    final w = size.width, h = size.height;
    final r = math.Random(seed);
    final cx = w * (0.15 + r.nextDouble() * 0.7);
    final cloudSpot = Offset(cx, h * (0.06 + r.nextDouble() * 0.06));
    // bulut içi parlama (her çakımda)
    canvas.drawCircle(
      cloudSpot,
      w * 0.55,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.30 * a), const Color(0xFFBFD4FF).withValues(alpha: 0.10 * a), Colors.white.withValues(alpha: 0)], stops: const [0, 0.4, 1])
            .createShader(Rect.fromCircle(center: cloudSpot, radius: w * 0.55)),
    );
    // tüm ekranda çok hafif aydınlanma
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: 0.06 * a));
    if (seed % 3 == 0) return; // yalnız bulut içi şimşek
    final to = Offset(cx + (r.nextDouble() - 0.5) * w * 0.3, h * (0.40 + r.nextDouble() * 0.15));
    final main = _bolt(r, cloudSpot, to, 13, w * 0.04);
    _stroke(canvas, main, 2.4, a);
    for (var b = 0; b < 2 + r.nextInt(3); b++) {
      final at = main[3 + r.nextInt(main.length - 5)];
      final side = r.nextBool() ? 1 : -1;
      final end = at + Offset(side * w * (0.05 + r.nextDouble() * 0.12), h * (0.04 + r.nextDouble() * 0.09));
      _stroke(canvas, _bolt(r, at, end, 6, w * 0.022), 1.2, a * 0.75);
    }
  }

  @override
  bool shouldRepaint(covariant JuzzioLightning21Painter old) => old.seed != seed;
}
