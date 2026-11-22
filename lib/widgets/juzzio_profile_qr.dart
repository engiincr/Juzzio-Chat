// =============================================================================
// JUZZIO v2.2.0 — Tek profil karekodu tasarımı
//  Profil fotoğrafındaki çevirmeli kart ile sağ üstteki "Profil Karekodum" sayfası artık AYNI
//  karekodu üretir: aynı veri, aynı hata düzeltme düzeyi (M), yuvarlak noktalar ve kartın
//  renginde yuvarlak köşe gözleri (Engin'in yeşil kart görseli esas alındı).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Profil kartı rengi (profiles.card_bg_color, "#RRGGBB") → renk; geçersizse [fallback].
Color juzzioProfileCardColor(String hex, Color fallback) {
  final h = hex.trim().replaceFirst('#', '').toUpperCase();
  final v = int.tryParse(h, radix: 16);
  if (h.length != 6 || v == null) return fallback;
  // eski turuncu / amber kart renkleri cam mavisine (profil kartıyla aynı kural)
  if (h == 'EA580C' || h == 'F59E0B' || h == 'F97316') return const Color(0xFF0891B2);
  return Color(0xFF000000 | v);
}

/// Göz rengi beyaz zeminde okunur kalsın diye çok açık renkler koyulaştırılır (saf; test edilir).
Color juzzioQrEyeColor(Color c) {
  var out = c.withValues(alpha: 1);
  var guard = 0;
  while (out.computeLuminance() > 0.35 && guard < 10) {
    out = Color.lerp(out, const Color(0xFF000000), 0.15)!;
    guard++;
  }
  return out;
}

/// Hata düzeltme düzeyi: iki ekranda da aynı (aynı veri → birebir aynı desen)
const int kJuzzioProfileQrLevel = QrErrorCorrectLevel.M;

class JuzzioProfileQr extends StatelessWidget {
  const JuzzioProfileQr({super.key, required this.data, required this.color, this.size = 200});
  final String data;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      padding: EdgeInsets.zero,
      errorCorrectionLevel: kJuzzioProfileQrLevel,
      backgroundColor: Colors.white,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: juzzioQrEyeColor(color)),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF0E0F12)),
    );
  }
}
