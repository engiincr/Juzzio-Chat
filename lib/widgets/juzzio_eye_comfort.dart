// =============================================================================
// JUZZIO v0.9.6 — Göz Konforu Modu (mavi ışık filtresi)
//  • Modlar: kapalı · her zaman açık · zamanlanmış (ör. 20:00–07:00) · gün batımı→gün doğumu
//  • Gün batımı/doğumu cihazda NOAA güneş denklemiyle hesaplanır (konum yalnız cihazda
//    tutulur, sunucuya gönderilmez).
//  • Tüm uygulamanın üstüne dokunmayı engellemeyen amber bir katman çizilir; yoğunluk
//    kaydırıcısıyla ayarlanır. Cam (glassmorphism) ve özel temalarla birlikte çalışır:
//    renkleri değiştirmez, yalnızca sıcak bir ton ekler.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';

/// Belirli bir gün için yerel gün doğumu / gün batımı. Kutup gecesi/gündüzünde null.
({DateTime sunrise, DateTime sunset})? juzzioSunTimes(DateTime day, double lat, double lng) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;
  final start = DateTime.utc(day.year, 1, 1);
  final n = DateTime.utc(day.year, day.month, day.day).difference(start).inDays + 1;
  // Kesirli yıl (radyan), öğlen için
  final g = 2 * math.pi / 365 * (n - 1);
  final eqTime = 229.18 *
      (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g));
  final decl = 0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);
  final cosHa = (math.cos(rad(90.833)) / (math.cos(rad(lat)) * math.cos(decl))) - math.tan(rad(lat)) * math.tan(decl);
  if (cosHa < -1 || cosHa > 1) return null;
  final ha = deg(math.acos(cosHa));
  final sunriseUtcMin = 720 - 4 * (lng + ha) - eqTime;
  final sunsetUtcMin = 720 - 4 * (lng - ha) - eqTime;
  final base = DateTime.utc(day.year, day.month, day.day);
  return (
    sunrise: base.add(Duration(seconds: (sunriseUtcMin * 60).round())).toLocal(),
    sunset: base.add(Duration(seconds: (sunsetUtcMin * 60).round())).toLocal(),
  );
}

/// [now] anında filtre açık mı? (saf fonksiyon — testlerde kullanılır)
bool juzzioEyeComfortActive({
  required String mode,
  required DateTime now,
  int startMin = 20 * 60,
  int endMin = 7 * 60,
  double? lat,
  double? lng,
}) {
  switch (mode) {
    case 'on':
      return true;
    case 'schedule':
      final m = now.hour * 60 + now.minute;
      if (startMin == endMin) return false;
      return startMin < endMin ? (m >= startMin && m < endMin) : (m >= startMin || m < endMin);
    case 'sun':
      if (lat == null || lng == null) {
        // Konum yoksa makul varsayılan: 19:00–07:00
        return juzzioEyeComfortActive(mode: 'schedule', now: now, startMin: 19 * 60, endMin: 7 * 60);
      }
      final t = juzzioSunTimes(now, lat, lng);
      if (t == null) {
        // Kutup: yaz gündüzü filtre yok, kış gecesi filtre var
        final summerNorth = now.month >= 4 && now.month <= 9;
        return lat > 0 ? !summerNorth : summerNorth;
      }
      return now.isBefore(t.sunrise) || !now.isBefore(t.sunset);
    default:
      return false;
  }
}

/// Amber katman rengi (yoğunluk 5..90 → alfa ~0.02..0.36)
Color juzzioEyeComfortColor(int intensity) {
  final a = (intensity.clamp(5, 90) / 100.0) * 0.40;
  return const Color(0xFFFF9A3C).withValues(alpha: a);
}

class JuzzioEyeComfortOverlay extends StatefulWidget {
  const JuzzioEyeComfortOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<JuzzioEyeComfortOverlay> createState() => _JuzzioEyeComfortOverlayState();
}

class _JuzzioEyeComfortOverlayState extends State<JuzzioEyeComfortOverlay> {
  final _app = JuzzioAppController.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _app.addListener(_onChange);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _app.eyeComfortMode != 'off' && _app.eyeComfortMode != 'on') setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _app.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = juzzioEyeComfortActive(
      mode: _app.eyeComfortMode,
      now: DateTime.now(),
      startMin: _app.eyeComfortStartMin,
      endMin: _app.eyeComfortEndMin,
      lat: _app.eyeComfortLat,
      lng: _app.eyeComfortLng,
    );
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              child: ColoredBox(color: juzzioEyeComfortColor(_app.eyeComfortIntensity)),
            ),
          ),
        ),
      ],
    );
  }
}
