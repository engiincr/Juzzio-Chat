// =============================================================================
// JUZZIO v1.2.9 — Hava teması ve Ay evresi için gerçekçi görseller
//  Görseller tools/weather_sprites.py ile KODLA üretilir (stok fotoğraf yok; Juzzio'ya ait):
//   assets/weather/moon.png (kraterli, denizli Ay), cloud_a/b.png (kümülüs), sun.png
//  Bir kez çözülüp bellekte tutulur; çizerler (CustomPainter) doğrudan kullanır. Yüklenemezse
//  çizerler vektör çizime düşer (uygulama asla boş kalmaz).
// =============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class JuzzioWeatherSprites {
  JuzzioWeatherSprites._();

  static ui.Image? moon;
  static ui.Image? sun;
  static ui.Image? cloudA;
  static ui.Image? cloudB;

  /// Yükleme bitince artar (çizerler yeniden çizilsin)
  static final ValueNotifier<int> ready = ValueNotifier<int>(0);
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<ui.Image?> _one(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _load() async {
    final r = await Future.wait([
      _one('assets/weather/moon.png'),
      _one('assets/weather/sun.png'),
      _one('assets/weather/cloud_a.png'),
      _one('assets/weather/cloud_b.png'),
    ]);
    moon = r[0];
    sun = r[1];
    cloudA = r[2];
    cloudB = r[3];
    ready.value++;
  }
}
