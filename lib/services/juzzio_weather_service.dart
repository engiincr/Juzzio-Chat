// =============================================================================
// JUZZIO v1.2.1 — Hava durumuna göre tema (varsayılan AÇIK; Görünüm'den kapatılır)
//
//  • Konum: yalnız izin VERİLMİŞSE okunur (yaklaşık doğruluk); ilk kez izin bir kez istenir.
//    Koordinatlar ~10 km'ye yuvarlanır (1 ondalık) ve yalnız Open-Meteo'ya gider —
//    Juzzio sunucusuna konum gönderilmez, saklanmaz.
//  • Open-Meteo: anahtarsız, ücretsiz; yalnız "current=weather_code,is_day,temperature_2m".
//  • 45 dakikada bir yenilenir; başarısızlıkta son durum korunur (çevrimdışı sorun değil).
//  v2.1 (Gökyüzü 2.1): aynı istekle konumun gün doğumu/batımı, saat dilimi farkı (ülke saati),
//    bulutluluk, yağış miktarı ve rüzgâr da alınır — ambiyans gerçek güneş/ay konumuna göre çizilir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/app_theme_and_locale.dart';

enum JuzzioWeatherKind { clear, clouds, fog, drizzle, rain, snow, thunder }

/// WMO hava kodu → tür (saf; test edilir) — https://open-meteo.com/en/docs (WMO Weather interpretation codes)
JuzzioWeatherKind juzzioWeatherKindFromWmo(int code) {
  if (code == 0 || code == 1) return JuzzioWeatherKind.clear;
  if (code == 2 || code == 3) return JuzzioWeatherKind.clouds;
  if (code == 45 || code == 48) return JuzzioWeatherKind.fog;
  if (code >= 51 && code <= 57) return JuzzioWeatherKind.drizzle;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return JuzzioWeatherKind.rain;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return JuzzioWeatherKind.snow;
  if (code >= 95) return JuzzioWeatherKind.thunder;
  return JuzzioWeatherKind.clouds;
}

/// Gizlilik: koordinatlar ~10 km'ye yuvarlanır (saf; test edilir)
double juzzioRoundCoord(double v) => (v * 10).roundToDouble() / 10;

/// Open-Meteo isteği (saf; test edilir)
Uri juzzioWeatherUri(double lat, double lng) => Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': juzzioRoundCoord(lat).toStringAsFixed(1),
      'longitude': juzzioRoundCoord(lng).toStringAsFixed(1),
      'current': 'weather_code,is_day,temperature_2m,cloud_cover,precipitation,wind_speed_10m',
      'daily': 'sunrise,sunset',
      'timezone': 'auto',
      'forecast_days': '2',
    });

/// Open-Meteo'nun konum saatindeki ("2026-11-21T07:12") zamanı UTC'ye çevirir (saf; test edilir)
DateTime? juzzioParseLocalIso(Object? raw, int utcOffsetSeconds) {
  if (raw is! String || raw.isEmpty) return null;
  final naive = DateTime.tryParse(raw.endsWith('Z') ? raw.substring(0, raw.length - 1) : raw);
  if (naive == null) return null;
  final asUtc = DateTime.utc(naive.year, naive.month, naive.day, naive.hour, naive.minute, naive.second);
  return asUtc.subtract(Duration(seconds: utcOffsetSeconds));
}

/// Konumun (ülkenin) şu anki duvar saati (saf; test edilir)
DateTime juzzioLocationNow(DateTime nowUtc, int utcOffsetSeconds) =>
    nowUtc.toUtc().add(Duration(seconds: utcOffsetSeconds));

class JuzzioWeatherState {
  const JuzzioWeatherState({
    required this.kind,
    required this.isDay,
    this.temperature,
    required this.fetchedAt,
    this.sunrises = const <DateTime>[],
    this.sunsets = const <DateTime>[],
    this.utcOffsetSeconds,
    this.cloudCover,
    this.precipitation,
    this.windSpeed,
  });
  final JuzzioWeatherKind kind;
  final bool isDay;
  final double? temperature;
  final DateTime fetchedAt;

  /// v2.1: konumun gün doğumu / batımı (UTC; bugün ve yarın)
  final List<DateTime> sunrises;
  final List<DateTime> sunsets;

  /// v2.1: konumun UTC farkı (saniye) — "ülke saati"
  final int? utcOffsetSeconds;

  /// v2.1: bulutluluk %, yağış mm, rüzgâr km/sa
  final double? cloudCover;
  final double? precipitation;
  final double? windSpeed;
}

class JuzzioWeatherService extends ChangeNotifier {
  JuzzioWeatherService._();
  static final JuzzioWeatherService instance = JuzzioWeatherService._();

  static const Duration refreshEvery = Duration(minutes: 45);

  JuzzioWeatherState? _state;
  JuzzioWeatherState? get state => _state;
  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  /// Uygulama açılınca (giriş sonrası) çağrılır; ayar kapalıysa hiçbir şey yapmaz.
  void start() {
    final app = JuzzioAppController.instance;
    if (_started) return;
    _started = true;
    app.addListener(_onSettings);
    _onSettings();
  }

  void _onSettings() {
    final on = JuzzioAppController.instance.weatherThemeEnabled;
    if (!on) {
      _timer?.cancel();
      _timer = null;
      if (_state != null) {
        _state = null;
        notifyListeners();
      }
      return;
    }
    if (_timer == null) {
      _timer = Timer.periodic(refreshEvery, (_) => refresh());
      refresh();
    }
  }

  Future<void> refresh({bool askPermission = true}) async {
    if (_busy || !JuzzioAppController.instance.weatherThemeEnabled) return;
    _busy = true;
    try {
      Position? pos;
      try {
        pos = await _position(askPermission: askPermission);
      } catch (_) {
        pos = null; // masaüstünde konum servisi yok / zaman aşımı
      }
      // GM-014: konum yoksa (Windows/macOS, izin verilmedi) kişinin ülkesinin başkenti kullanılır;
      // hava durumu, ay evresi ve gece/gündüz yine o ülkenin saatine göre çalışır.
      final approx = pos == null ? juzzioApproxCoordsForLocale(_localeName(), DateTime.now().timeZoneOffset) : null;
      final lat = pos?.latitude ?? approx!.$1;
      final lon = pos?.longitude ?? approx!.$2;
      final res = await http.get(juzzioWeatherUri(lat, lon)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      final cur = body is Map ? body['current'] : null;
      if (cur is! Map) return;
      final code = (cur['weather_code'] as num?)?.toInt();
      if (code == null) return;
      final offset = (body['utc_offset_seconds'] as num?)?.toInt() ?? DateTime.now().timeZoneOffset.inSeconds;
      final daily = body['daily'];
      List<DateTime> times(String key) {
        final list = daily is Map ? daily[key] : null;
        if (list is! List) return const <DateTime>[];
        return [for (final e in list) juzzioParseLocalIso(e, offset)].whereType<DateTime>().toList(growable: false);
      }
      _state = JuzzioWeatherState(
        kind: juzzioWeatherKindFromWmo(code),
        isDay: (cur['is_day'] as num?)?.toInt() != 0,
        temperature: (cur['temperature_2m'] as num?)?.toDouble(),
        fetchedAt: DateTime.now(),
        sunrises: times('sunrise'),
        sunsets: times('sunset'),
        utcOffsetSeconds: offset,
        cloudCover: (cur['cloud_cover'] as num?)?.toDouble(),
        precipitation: (cur['precipitation'] as num?)?.toDouble(),
        windSpeed: (cur['wind_speed_10m'] as num?)?.toDouble(),
      );
      notifyListeners();
    } catch (_) {
      // çevrimdışı / izin yok: son durum korunur
    } finally {
      _busy = false;
    }
  }

  static String _localeName() {
    try {
      return Platform.localeName;
    } catch (_) {
      return '';
    }
  }

  Future<Position?> _position({required bool askPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && askPermission) {
      // izin yalnız BİR KEZ istenir (her açılışta rahatsız edilmez)
      final app = JuzzioAppController.instance;
      if (!app.weatherPermAsked) {
        app.markWeatherPermAsked();
        perm = await Geolocator.requestPermission();
      }
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
    );
  }
}

/// Görünüm sayfasında gösterilen ad
String juzzioWeatherLabel(JuzzioWeatherKind k) {
  final a = JuzzioAppController.instance;
  return switch (k) {
    JuzzioWeatherKind.clear => a.trEn('Açık', 'Clear', 'Klar'),
    JuzzioWeatherKind.clouds => a.trEn('Bulutlu', 'Cloudy', 'Bewölkt'),
    JuzzioWeatherKind.fog => a.trEn('Sisli', 'Foggy', 'Neblig'),
    JuzzioWeatherKind.drizzle => a.trEn('Çisenti', 'Drizzle', 'Nieselregen'),
    JuzzioWeatherKind.rain => a.trEn('Yağmurlu', 'Rain', 'Regen'),
    JuzzioWeatherKind.snow => a.trEn('Karlı', 'Snow', 'Schnee'),
    JuzzioWeatherKind.thunder => a.trEn('Fırtına', 'Thunderstorm', 'Gewitter'),
  };
}

/// GM-014: konum alınamayınca yaklaşık konum — cihaz dilinin ülkesinin başkenti (ör. tr_TR → Ankara);
/// ülke bilinmiyorsa saat diliminden boylam (UTC+3 → 45°D). Saf; test edilir.
const Map<String, (double, double)> kJuzzioCountryCapitals = {
  'TR': (39.93, 32.86), 'US': (38.90, -77.04), 'GB': (51.51, -0.13), 'DE': (52.52, 13.40), 'FR': (48.86, 2.35),
  'NL': (52.37, 4.90), 'BE': (50.85, 4.35), 'AT': (48.21, 16.37), 'CH': (46.95, 7.45), 'IT': (41.90, 12.50),
  'ES': (40.42, -3.70), 'PT': (38.72, -9.14), 'GR': (37.98, 23.73), 'BG': (42.70, 23.32), 'RO': (44.43, 26.10),
  'RU': (55.76, 37.62), 'UA': (50.45, 30.52), 'PL': (52.23, 21.01), 'SE': (59.33, 18.07), 'NO': (59.91, 10.75),
  'DK': (55.68, 12.57), 'FI': (60.17, 24.94), 'AZ': (40.41, 49.87), 'GE': (41.72, 44.79), 'IR': (35.69, 51.39),
  'IQ': (33.31, 44.36), 'SA': (24.71, 46.68), 'AE': (24.45, 54.38), 'EG': (30.04, 31.24), 'IN': (28.61, 77.21),
  'PK': (33.68, 73.05), 'CN': (39.90, 116.40), 'JP': (35.68, 139.69), 'KR': (37.57, 126.98), 'ID': (-6.21, 106.85),
  'BR': (-15.79, -47.88), 'MX': (19.43, -99.13), 'CA': (45.42, -75.70), 'AU': (-35.28, 149.13), 'KZ': (51.17, 71.43),
  'UZ': (41.30, 69.24), 'TM': (37.95, 58.38), 'KG': (42.87, 74.59), 'CY': (35.17, 33.37), 'AL': (41.33, 19.82),
  'BA': (43.86, 18.41), 'MK': (41.99, 21.43), 'RS': (44.79, 20.45),
};

(double, double) juzzioApproxCoordsForLocale(String localeName, Duration utcOffset) {
  final m = RegExp(r'[_-]([A-Za-z]{2})\b').firstMatch(localeName);
  final cc = m?.group(1)?.toUpperCase();
  final hit = cc == null ? null : kJuzzioCountryCapitals[cc];
  if (hit != null) return hit;
  final lon = (utcOffset.inMinutes / 60.0 * 15.0).clamp(-180.0, 180.0);
  return (40.0, lon);
}
