// =============================================================================
// JUZZIO v1.2.1 — Hava durumuna göre tema (varsayılan AÇIK; Görünüm'den kapatılır)
//
//  • Konum: yalnız izin VERİLMİŞSE okunur (yaklaşık doğruluk); ilk kez izin bir kez istenir.
//    Koordinatlar ~10 km'ye yuvarlanır (1 ondalık) ve yalnız Open-Meteo'ya gider —
//    Juzzio sunucusuna konum gönderilmez, saklanmaz.
//  • Open-Meteo: anahtarsız, ücretsiz; yalnız "current=weather_code,is_day,temperature_2m".
//  • 45 dakikada bir yenilenir; başarısızlıkta son durum korunur (çevrimdışı sorun değil).
// =============================================================================

import 'dart:async';
import 'dart:convert';

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
      'current': 'weather_code,is_day,temperature_2m',
    });

class JuzzioWeatherState {
  const JuzzioWeatherState({required this.kind, required this.isDay, this.temperature, required this.fetchedAt});
  final JuzzioWeatherKind kind;
  final bool isDay;
  final double? temperature;
  final DateTime fetchedAt;
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
      final pos = await _position(askPermission: askPermission);
      if (pos == null) return;
      final res = await http.get(juzzioWeatherUri(pos.latitude, pos.longitude)).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      final cur = body is Map ? body['current'] : null;
      if (cur is! Map) return;
      final code = (cur['weather_code'] as num?)?.toInt();
      if (code == null) return;
      _state = JuzzioWeatherState(
        kind: juzzioWeatherKindFromWmo(code),
        isDay: (cur['is_day'] as num?)?.toInt() != 0,
        temperature: (cur['temperature_2m'] as num?)?.toDouble(),
        fetchedAt: DateTime.now(),
      );
      notifyListeners();
    } catch (_) {
      // çevrimdışı / izin yok: son durum korunur
    } finally {
      _busy = false;
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
