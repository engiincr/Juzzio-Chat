// =============================================================================
// JUZZIO — Merkezi renk paleti (tek kaynak).
// Uygulamadaki tüm sabit renkler buradan gelir; yeni renk eklerken önce burada
// mevcut bir tonu kullanmayı deneyin. JuzzioPalette (tema) bu tokenleri kullanır.
// =============================================================================

import 'dart:ui' show Color;

class JuzzioColors {
  JuzzioColors._();

  // v0.8.1 Premium Liquid Glass tasarım sistemi (brief §2 / §6)
  static const Color background = Color(0xFF050A12);
  static const Color backgroundAlt = Color(0xFF081522);
  static const Color surface = Color(0xFF101B2A);
  static const Color surfaceLight = Color(0xFF172536);
  static const Color cyan = Color(0xFF20D9F2);
  static const Color cyanSoft = Color(0xFF6BDDF0);
  static const Color blue = Color(0xFF397BFF);
  static const Color purple = Color(0xFF925CFF);
  static const Color emerald = Color(0xFF20D6A0);
  static const Color error = Color(0xFFFF647B);
  static const Color warning = Color(0xFFFFBF69);
  static const Color textPrimary = Color(0xFFF5F9FF);
  static const Color textSecondary = Color(0xFFA8B5C7);
  static const Color textMuted = Color(0xFF718198);
  static const Color borderSubtle = Color(0x26FFFFFF);

  // v0.5.0 "Nötr Cam" kimliği: grafit zemin + gri-beyaz cam vurgu (iOS/HyperOS).
  // Eski mavi/mor/kehribar tonlar nötr grilerle eşlendi (isimler geriye dönük
  // uyumluluk için korunur). Mavi doğrulama tiki için sky500 kullanılır.
  static const Color accent = Color(0xFFF2F2F7);
  static const Color accentLight = Color(0xFFFFFFFF);
  static const Color accentDeep = Color(0xFFD1D1D6);
  static const Color obsidian = Color(0xFF0B0B0D);
  static const Color obsidianRaised = Color(0xFF151517);
  static const Color obsidianElevated = Color(0xFF1E1E21);
  static const Color verifiedBlue = Color(0xFF1D9BF0);

  static const Color amber100 = Color(0xFFFFF6CC);
  static const Color amber500 = Color(0xFFFFD60A);
  static const Color amber600 = Color(0xFFE6C200);
  static const Color amber700 = Color(0xFF3A3A3C);
  static const Color amber800 = Color(0xFF2C2C2E);
  static const Color blue400 = Color(0xFFC7C7CC);
  static const Color blue500 = Color(0xFF8E8E93);
  static const Color blue600 = Color(0xFF636366);
  static const Color blue900 = Color(0xFF2C2C2E);
  static const Color blueDeep = Color(0xFF48484A);
  static const Color blueFlat = Color(0xFF8E8E93);
  static const Color blueVivid = Color(0xFF8E8E93);
  static const Color brandIndigo = Color(0xFF636366);
  static const Color darkBackground = Color(0xFF0B0B0D);
  static const Color deepForest = Color(0xFF0B0B0D);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald400 = Color(0xFF34D399);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald700 = Color(0xFF047857);
  static const Color emerald800 = Color(0xFF065F46);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray600 = Color(0xFF636366);
  static const Color gray800 = Color(0xFF2C2C2E);
  static const Color greenDark = Color(0xFF1E824C);
  static const Color greenFlat = Color(0xFF2ECC71);
  static const Color indigo50 = Color(0xFFF2F2F7);
  static const Color indigo500 = Color(0xFF8E8E93);
  static const Color indigo600 = Color(0xFF636366);
  static const Color indigoDeep = Color(0xFF3A3A3C);
  static const Color indigoSoft = Color(0xFFC7C7CC);
  static const Color ink = Color(0xFF111113);
  static const Color midnight = Color(0xFF0B0B0D);
  static const Color pink400 = Color(0xFFAEAEB2);
  static const Color pink50 = Color(0xFFF2F2F7);
  static const Color pink500 = Color(0xFFD1D1D6);
  static const Color purple400 = Color(0xFFC7C7CC);
  static const Color purple50 = Color(0xFFF2F2F7);
  static const Color purpleDeep = Color(0xFF3A3A3C);
  static const Color purpleFlat = Color(0xFF8E8E93);
  static const Color red500 = Color(0xFFEF4444);
  static const Color redAlert = Color(0xFFFF3B30);
  static const Color redBrick = Color(0xFFB0303C);
  static const Color redDark = Color(0xFF922B21);
  static const Color redFlat = Color(0xFFE74C3C);
  static const Color redSoft = Color(0xFFE5A0A6);
  static const Color royalNavy = Color(0xFF2C2C2E);
  static const Color sky300 = Color(0xFFFFFFFF);
  static const Color sky400 = Color(0xFFC7C7CC);
  static const Color sky500 = Color(0xFF0EA5E9);
  static const Color slate100 = Color(0xFFF2F2F7);
  static const Color slate200 = Color(0xFFE5E5EA);
  static const Color slate300 = Color(0xFFD1D1D6);
  static const Color slate400 = Color(0xFFAEAEB2);
  static const Color slate50 = Color(0xFFF9F9FB);
  static const Color slate500 = Color(0xFF8E8E93);
  static const Color slate600 = Color(0xFF636366);
  static const Color slate700 = Color(0xFF48484A);
  static const Color slate800 = Color(0xFF2C2C2E);
  static const Color slate900 = Color(0xFF1C1C1E);
  static const Color surface05056B = Color(0xFF05056B);
  static const Color surface060D09 = Color(0xFF0A0A0A);
  static const Color surface0B0C10 = Color(0xFF0D0D0D);
  static const Color surface0B0F17 = Color(0xFF0F0F0F);
  static const Color surface0B1017 = Color(0xFF0F0F0F);
  static const Color surface0D221E = Color(0xFF1B1B1B);
  static const Color surface0E0F12 = Color(0xFF101010);
  static const Color surface0E6251 = Color(0xFF0E6251);
  static const Color surface101F2B = Color(0xFF101F2B);
  static const Color surface102419 = Color(0xFF1D1D1D);
  static const Color surface12151C = Color(0xFF161616);
  static const Color surface121529 = Color(0xFF121529);
  static const Color surface13111A = Color(0xFF151515);
  static const Color surface131B26 = Color(0xFF1B1B1B);
  static const Color surface141416 = Color(0xFF141414);
  static const Color surface141519 = Color(0xFF161616);
  static const Color surface14161C = Color(0xFF171717);
  static const Color surface141B26 = Color(0xFF1C1C1C);
  static const Color surface15171E = Color(0xFF191919);
  static const Color surface16181F = Color(0xFF1A1A1A);
  static const Color surface161820 = Color(0xFF1B1B1B);
  static const Color surface171B2E = Color(0xFF222222);
  static const Color surface181A22 = Color(0xFF1D1D1D);
  static const Color surface191D26 = Color(0xFF1F1F1F);
  static const Color surface1A1C23 = Color(0xFF1E1E1E);
  static const Color surface1A1E29 = Color(0xFF212121);
  static const Color surface1A2433 = Color(0xFF262626);
  static const Color surface1C1E26 = Color(0xFF212121);
  static const Color surface1E2028 = Color(0xFF222222);
  static const Color surface1E2029 = Color(0xFF232323);
  static const Color surface1E2430 = Color(0xFF262626);
  static const Color surface1F1226 = Color(0xFF1F1226);
  static const Color surface1F2128 = Color(0xFF232323);
  static const Color surface1F222A = Color(0xFF242424);
  static const Color surface1F2430 = Color(0xFF272727);
  static const Color surface22252E = Color(0xFF272727);
  static const Color surface231F2E = Color(0xFF262626);
  static const Color surface23252C = Color(0xFF272727);
  static const Color surface24100E = Color(0xFF1A1218);
  static const Color surface24786D = Color(0xFF24786D);
  static const Color surface280D1D = Color(0xFF280D1D);
  static const Color surface281313 = Color(0xFF1C1218);
  static const Color surface282B34 = Color(0xFF2D2D2D);
  static const Color surface282B36 = Color(0xFF2E2E2E);
  static const Color surface2B1E2E = Color(0xFF252525);
  static const Color surface3A1D2E = Color(0xFF3A1D2E);
  static const Color surface4A2E40 = Color(0xFF4A2E40);
  static const Color surface686D78 = Color(0xFF6D6D6D);
  static const Color surface6B4C62 = Color(0xFF6B4C62);
  static const Color surface9AA0AC = Color(0xFFA0A0A0);
  static const Color surfaceE7E9F0 = Color(0xFFE9E9E9);
  static const Color surfaceE8ECF4 = Color(0xFFECECEC);
  static const Color surfaceECEFF5 = Color(0xFFEFEFEF);
  static const Color surfaceF1F3F7 = Color(0xFFF3F3F3);
  static const Color surfaceF3F4F8 = Color(0xFFF4F4F4);
  static const Color surfaceF3F5F9 = Color(0xFFF5F5F5);
  static const Color surfaceF5F6FA = Color(0xFFF6F6F6);
  static const Color surfaceF6F7FA = Color(0xFFF7F7F7);
  static const Color surfaceF9FAFC = Color(0xFFFAFAFA);
  static const Color teal500 = Color(0xFF9A9AA0);
  static const Color tint3B82F6A22 = Color(0x22FFFFFF);
  static const Color tint6366F1A18 = Color(0x18FFFFFF);
  static const Color tintF59E0BA22 = Color(0x22FFD60A);
  static const Color turquoise = Color(0xFF1ABC9C);
  static const Color violet500 = Color(0xFF8E8E93);
  static const Color white = Color(0xFFFFFFFF);
  static const Color yellow400 = Color(0xFFFFD60A);
}
