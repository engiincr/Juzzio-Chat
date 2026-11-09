// =============================================================================
// JUZZIO v0.9.3 — Ayarlanabilir güzelleştirme (hikâye fotoğrafları + görüntülü arama)
//  • Yoğunluk 0..100 (0 = kapalı). Görüntülü aramadaki yerel işlemciyle (JuzzioBeautyProcessor.kt)
//    AYNI parametre eşlemesi kullanılır; böylece kullanıcı her iki yerde aynı sonucu görür.
//  • Kenar korumalı yumuşatma: yalnızca küçük parlaklık farkları (cilt dokusu) yumuşatılır,
//    gözler/kaşlar/saç keskin kalır; gölgeler hafif aydınlanır, ten hafif ısınır.
//  • Fotoğraf işleme ayrı isolate'te (compute) yapılır; arayüz donmaz.
// =============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Yoğunluk → işlem parametreleri (Kotlin tarafıyla birebir aynı formül).
class JuzzioBeautyParams {
  final int radius;
  final int alpha; // 0..256 yumuşatma gücü
  final int threshold; // bu farkın üstü (kenar) hiç değişmez
  final int lift; // gölge aydınlatma
  final int warm; // sıcak ton kayması

  const JuzzioBeautyParams(this.radius, this.alpha, this.threshold, this.lift, this.warm);

  static JuzzioBeautyParams forLevel(int level) {
    final l = level.clamp(0, 100);
    return JuzzioBeautyParams(
      l > 65 ? 3 : 2,
      (40 + l * 2).clamp(0, 240),
      6 + (l * 16) ~/ 100,
      (l * 12) ~/ 100,
      l >= 30 ? 1 : 0,
    );
  }
}

/// RGBA piksel dizisine güzelleştirme uygular (yerinde değil, yeni dizi döner).
Uint8List juzzioBeautifyRgba(Uint8List rgba, int w, int h, int level) {
  if (level <= 0 || w < 8 || h < 8) return rgba;
  final p = JuzzioBeautyParams.forLevel(level);
  final n = w * h;
  final luma = Int32List(n);
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    luma[i] = (rgba[j] * 77 + rgba[j + 1] * 150 + rgba[j + 2] * 29) >> 8;
  }
  // Ayrılabilir kutu bulanıklığı (kayan pencere)
  final r = p.radius;
  final tmp = Int32List(n);
  for (var y = 0; y < h; y++) {
    final base = y * w;
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += luma[base + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[base + x] = sum;
      sum += luma[base + (x + r + 1).clamp(0, w - 1)] - luma[base + (x - r).clamp(0, w - 1)];
    }
  }
  final area = (2 * r + 1) * (2 * r + 1);
  final blur = Int32List(n);
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      blur[y * w + x] = sum ~/ area;
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] - tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  final out = Uint8List.fromList(rgba);
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    final y = luma[i];
    final d = blur[i] - y;
    final ad = d.abs();
    var delta = 0;
    if (ad < p.threshold) {
      final w8 = p.alpha * (p.threshold - ad) ~/ p.threshold;
      delta = (d * w8) >> 8;
    }
    final boost = p.lift * (255 - y) ~/ 255;
    final add = delta + boost;
    out[j] = (rgba[j] + add + p.warm).clamp(0, 255);
    out[j + 1] = (rgba[j + 1] + add).clamp(0, 255);
    out[j + 2] = (rgba[j + 2] + add - p.warm).clamp(0, 255);
  }
  return out;
}

Uint8List? _beautifyJpegIsolate(Map<String, Object> args) {
  final bytes = args['bytes'] as Uint8List;
  final level = args['level'] as int;
  final maxSide = args['maxSide'] as int;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  final longest = im.width > im.height ? im.width : im.height;
  if (longest > maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
  }
  final rgba = im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  final processed = juzzioBeautifyRgba(Uint8List.fromList(rgba), im.width, im.height, level);
  final outImg = img.Image.fromBytes(width: im.width, height: im.height, bytes: processed.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return Uint8List.fromList(img.encodeJpg(outImg, quality: 92));
}

/// Fotoğraf dosyasına güzelleştirme uygular; yeni geçici JPEG döner. Başarısızsa orijinal dosya.
Future<File> juzzioBeautifyImageFile(File source, int level, {int maxSide = 2160}) async {
  if (level <= 0) return source;
  try {
    final bytes = await source.readAsBytes();
    final out = await compute(_beautifyJpegIsolate, <String, Object>{'bytes': bytes, 'level': level, 'maxSide': maxSide});
    if (out == null) return source;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/juzzio_beauty_${DateTime.now().microsecondsSinceEpoch}_$level.jpg');
    await f.writeAsBytes(out, flush: true);
    return f;
  } catch (_) {
    return source;
  }
}

Uint8List? _compressJpegIsolate(Map<String, Object> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  final maxSide = args['maxSide'] as int;
  if ((im.width > im.height ? im.width : im.height) > maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: args['quality'] as int));
}

/// v0.9.4: profil/kapak görselini yüklemeden önce ≤[maxSide] px JPEG'e sıkıştırır (avatars kovası 5 MB).
/// Çözülemeyen dosyada orijinal döner.
Future<File> juzzioCompressImageForUpload(File source, {int maxSide = 1600, int quality = 85}) async {
  try {
    final bytes = await source.readAsBytes();
    final out = await compute(_compressJpegIsolate, <String, Object>{'bytes': bytes, 'maxSide': maxSide, 'quality': quality});
    if (out == null) return source;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/juzzio_up_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(out, flush: true);
    return f;
  } catch (_) {
    return source;
  }
}
