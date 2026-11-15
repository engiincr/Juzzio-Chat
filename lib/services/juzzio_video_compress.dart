// =============================================================================
// JUZZIO v1.2.8 — Gönderilen videoları sıkıştır (en çok 720p, 30 kare/sn)
//  • Kısa kenarı 720 pikselden büyük ya da 6 MB'tan büyük videolar gönderilmeden önce
//    720p / 30 fps'e dönüştürülür. Daha küçükse dokunulmaz (kalite kaybı yok).
//  • Dönüştürme başarısız olursa özgün dosya gönderilir (gönderme asla takılmaz).
//  • Daha küçük dosya = daha hızlı gönderme + daha az depolama/veri trafiği (Supabase egress).
// =============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:video_compress/video_compress.dart';

/// Sıkıştırma gerekli mi (saf; test edilir)
bool juzzioVideoNeedsCompression({required int width, required int height, required int bytes}) {
  final shortSide = (width <= 0 || height <= 0) ? 0 : math.min(width, height);
  return shortSide > 720 || bytes > 6 * 1024 * 1024;
}

/// Gönderilecek videoyu hazırlar: gerekirse 720p/30fps'e sıkıştırılmış dosyayı döndürür.
Future<File> juzzioPrepareVideoForSend(File original) async {
  try {
    final size = original.lengthSync();
    final info = await VideoCompress.getMediaInfo(original.path);
    final w = info.width ?? 0;
    final h = info.height ?? 0;
    if (!juzzioVideoNeedsCompression(width: w, height: h, bytes: size)) return original;
    final out = await VideoCompress.compressVideo(
      original.path,
      quality: VideoQuality.Res1280x720Quality,
      deleteOrigin: false,
      includeAudio: true,
      frameRate: 30,
    );
    final f = out?.file;
    if (f != null && f.existsSync()) {
      final len = f.lengthSync();
      if (len > 0 && len < size) return f;
    }
  } catch (_) {}
  return original;
}
