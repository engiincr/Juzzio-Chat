// =============================================================================
// JUZZIO v0.9.6 — Göz Konforu ayarları
//  Elle aç/kapat · zamanlanmış (başlangıç/bitiş saati) · gün batımından gün doğumuna
//  (konuma göre, yalnız cihazda hesaplanır) · yoğunluk kaydırıcısı · canlı önizleme.
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../widgets/juzzio_eye_comfort.dart';

class JuzzioEyeComfortPage extends StatefulWidget {
  const JuzzioEyeComfortPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioEyeComfortPage()));

  @override
  State<JuzzioEyeComfortPage> createState() => _JuzzioEyeComfortPageState();
}

class _JuzzioEyeComfortPageState extends State<JuzzioEyeComfortPage> {
  final _app = JuzzioAppController.instance;
  bool _locating = false;
  String? _error;

  String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String _t(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool start) async {
    final cur = start ? _app.eyeComfortStartMin : _app.eyeComfortEndMin;
    final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (r == null) return;
    final v = r.hour * 60 + r.minute;
    start ? _app.setEyeComfort(startMin: v) : _app.setEyeComfort(endMin: v);
  }

  Future<void> _useSun() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('permission');
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low))
          .timeout(const Duration(seconds: 15));
      // Gün doğumu hesabı için şehir düzeyi yeterli: konum 2 ondalığa yuvarlanır (~1 km)
      _app.setEyeComfort(
        mode: 'sun',
        lat: double.parse(pos.latitude.toStringAsFixed(2)),
        lng: double.parse(pos.longitude.toStringAsFixed(2)),
      );
    } catch (_) {
      _app.setEyeComfort(mode: 'sun');
      if (mounted) {
        setState(() => _error = _app.trEn('Konum alınamadı; varsayılan 19:00–07:00 kullanılacak.',
            'Location unavailable; using the default 19:00–07:00.', 'Standort nicht verfügbar; Standard 19:00–07:00.'));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _app,
      builder: (context, _) {
        final p = JuzzioPalette(_app.isDark);
        final mode = _app.eyeComfortMode;
        final active = juzzioEyeComfortActive(
          mode: mode,
          now: DateTime.now(),
          startMin: _app.eyeComfortStartMin,
          endMin: _app.eyeComfortEndMin,
          lat: _app.eyeComfortLat,
          lng: _app.eyeComfortLng,
        );
        final sun = (_app.eyeComfortLat != null && _app.eyeComfortLng != null)
            ? juzzioSunTimes(DateTime.now(), _app.eyeComfortLat!, _app.eyeComfortLng!)
            : null;
        Widget modeTile(String id, IconData icon, String title, String sub, {VoidCallback? onTap}) => RadioListTile<String>(
              value: id,
              groupValue: mode,
              onChanged: (_) => onTap != null ? onTap() : _app.setEyeComfort(mode: id),
              secondary: Icon(icon, color: p.amberGlow),
              title: Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
              subtitle: Text(sub, style: TextStyle(color: p.textSecondary, fontSize: 12)),
            );
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(title: Text(_app.trEn('Göz Konforu', 'Eye Comfort', 'Augenkomfort'))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            // Canlı önizleme kartı
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [JuzzioGlassTokens.accentFill, p.amberGlow.withValues(alpha: 0.7)]),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(active ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: Colors.white, size: 34),
                        const SizedBox(width: 12),
                        Text(
                          active
                              ? _app.trEn('Filtre şu an açık', 'Filter is on now', 'Filter ist an')
                              : _app.trEn('Filtre şu an kapalı', 'Filter is off now', 'Filter ist aus'),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ]),
                    ),
                    IgnorePointer(child: ColoredBox(color: juzzioEyeComfortColor(_app.eyeComfortIntensity))),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _app.trEn('Ekrana sıcak (amber) bir ton ekleyerek mavi ışığı azaltır; akşamları göz yorgunluğunu hafifletir. Temanın ve cam efektinin renkleri korunur.',
                  'Adds a warm amber tint to reduce blue light and ease evening eye strain. Your theme and glass colours stay intact.',
                  'Fügt einen warmen Bernsteinton hinzu, um blaues Licht zu reduzieren.'),
              style: TextStyle(color: p.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            modeTile('off', Icons.visibility_rounded, _app.trEn('Kapalı', 'Off', 'Aus'), _app.trEn('Filtre uygulanmaz', 'No filter', 'Kein Filter')),
            modeTile('on', Icons.remove_red_eye_rounded, _app.trEn('Her zaman açık', 'Always on', 'Immer an'),
                _app.trEn('Elle açıldı; kapatana kadar sürer', 'Manually on until you turn it off', 'Manuell an')),
            modeTile('schedule', Icons.schedule_rounded, _app.trEn('Zamanlanmış', 'Scheduled', 'Geplant'),
                '${_hm(_app.eyeComfortStartMin)} – ${_hm(_app.eyeComfortEndMin)}'),
            if (mode == 'schedule')
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 6),
                child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.nights_stay_rounded, size: 18),
                    label: Text('${_app.trEn('Başlangıç', 'Start', 'Beginn')} ${_hm(_app.eyeComfortStartMin)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.wb_twilight_rounded, size: 18),
                    label: Text('${_app.trEn('Bitiş', 'End', 'Ende')} ${_hm(_app.eyeComfortEndMin)}'),
                  ),
                ]),
              ),
            modeTile(
              'sun',
              Icons.wb_twilight_rounded,
              _app.trEn('Gün batımından gün doğumuna', 'Sunset to sunrise', 'Sonnenuntergang bis -aufgang'),
              sun != null
                  ? '${_t(sun.sunset)} – ${_t(sun.sunrise)} · ${_app.trEn('konuma göre', 'by location', 'nach Standort')}'
                  : _app.trEn('Konumuna göre otomatik (konum yalnız cihazında kalır)', 'Automatic by location (stays on your device)', 'Automatisch nach Standort'),
              onTap: _useSun,
            ),
            if (_locating) const LinearProgressIndicator(),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: p.amberGlow, fontSize: 12))),
            const SizedBox(height: 12),
            Text('${_app.trEn('Yoğunluk', 'Intensity', 'Intensität')} · %${_app.eyeComfortIntensity}',
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
            Slider(
              value: _app.eyeComfortIntensity.toDouble(),
              min: 5,
              max: 90,
              divisions: 17,
              activeColor: p.amberGlow,
              label: '%${_app.eyeComfortIntensity}',
              onChanged: (v) => _app.setEyeComfort(intensity: v.round()),
            ),
          ]),
        );
      },
    );
  }
}
