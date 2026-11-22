// =============================================================================
// JUZZIO Design System v1.3 — tek kaynak tasarım tokenları (K1)
//  Kaynak: claude.ai Juzzio projesi kurallar/juzzio_design_tokens.json + JUZZIO_VISUAL_SPEC.md
//  Ekranlarda sabit renk/radius/boyut yazılmaz; buradan okunur. Yeni varyant önce buraya eklenir.
//  GM-002 (21.11.2026): giriş/kayıt yenilemesi için oluşturuldu.
// =============================================================================

import 'package:flutter/material.dart';

/// Renk tokenları (semantik). Lime hero yalnız giriş/kayıtta kullanılır (K1).
class JuzzioColorTokens {
  JuzzioColorTokens._();

  static const Color accent = Color(0xFFC5F63F);
  static const Color accentSoft = Color(0xFFD7FF63);
  static const Color onAccent = Color(0xFF101310);

  // Giriş/kayıt lime hero (referanstan örneklendi)
  static const Color heroLight = Color(0xFFB6E045);
  static const Color heroMid = Color(0xFFA1D13C);
  static const Color heroDeep = Color(0xFF86B02C);

  static const Color appBackgroundDark = Color(0xFF101114);
  static const Color formDark = Color(0xFF141618);
  static const Color surface = Color(0xFF202326);
  static const Color elevated = Color(0xFF2C2F30);
  static const Color input = Color(0xFF25292B);
  static const Color social = Color(0xFF242524);

  static const Color textPrimary = Color(0xFFF7F8F8);
  static const Color textSecondary = Color(0xFFB7B9B9);
  static const Color textSubtle = Color(0xFFCDD0CF);
  static const Color textMuted = Color(0xFF858A8D);
  static const Color chipBackground = Color(0xFFFAFAFA);
  static const Color chipForeground = Color(0xFF161719);

  static const Color borderDark = Color(0x33FFFFFF);
  static const Color borderFine = Color(0x22FFFFFF);

  static const Color error = Color(0xFFF4434E);
  static const Color errorOnDark = Color(
    0xFFFF7A82,
  ); // koyu cam üstünde okunur hata metni
  static const Color footerText = Color(0xFFE4E5E5);
  static const Color dividerText = Color(0xFFC8C8C8);
  static const Color heroBackFill = Color(
    0x8C3F5A12,
  ); // lime hero üstündeki geri dairesi

  /// Koyu cam panel dikey geçişi (üstte saydam → altta formDark)
  static const List<Color> glassPanel = [
    Color(0x701C211F),
    Color(0xB81B1E1D),
    Color(0xEB181A1B),
    Color(0xFA151718),
    formDark,
  ];
  static const List<double> glassPanelStops = [0.0, 0.07, 0.20, 0.42, 1.0];
  static const Color success = Color(0xFF79DE83);
  static const Color info = Color(0xFF59BDFF);
}

/// Boşluk (4/8 dp grid)
class JuzzioSpace {
  JuzzioSpace._();
  static const double s4 = 4,
      s8 = 8,
      s12 = 12,
      s16 = 16,
      s20 = 20,
      s24 = 24,
      s28 = 28,
      s32 = 32,
      s40 = 40,
      s48 = 48;
  static const double screenInset =
      28; // form yatay iç boşluğu (referans ≈27dp)
}

/// Köşe yarıçapları
class JuzzioRadius {
  JuzzioRadius._();
  static const double xs = 8, sm = 12, md = 16, lg = 22, xl = 28;
  static const double authGlassTop = 54;
  static const double input = 26;
  static const double pill = 999;
  static const double checkbox = 6;
}

/// Standart bileşen boyutları (K1 varyant tablosu)
class JuzzioSizes {
  JuzzioSizes._();
  static const double minTouch = 48;
  static const double primaryHeight = 56;
  static const double secondaryHeight = 48;
  static const double compactHeight = 36;
  static const double authInputHeight = 54;
  static const double appInputHeight = 48;
  static const double iconCircleBack = 46;
  static const double iconCircleSocial = 54;
  static const double iconCircleSmall = 40;
  static const double socialLogo = 25;
  static const double inputLeadingIcon = 22;
  static const double ctaArrow = 23;
  static const double checkbox = 24;
}

/// Tipografi (sp). Font: Inter (SIL OFL 1.1, assets/fonts/inter) — auth ekranlarında.
class JuzzioType {
  JuzzioType._();
  static const String family = 'JuzzioInter';
  static const double heroTitle = 31;
  static const double subtitle = 15;
  static const double field = 15;
  static const double cta = 19;
  static const double chip = 14;
  static const double secondaryAction = 14.5;
  static const double footer = 15;
  static const double divider = 14;
}

/// Cam (glass) değerleri
class JuzzioGlassValues {
  JuzzioGlassValues._();
  static const double panelSigma = 22;
  static const double lowPowerSigma = 10;
  static const double borderTopAlpha = 0.24;
  static const double focusGlowAlpha = 0.28;
}

/// Hareket süreleri
class JuzzioMotion {
  JuzzioMotion._();
  static const Duration focus = Duration(milliseconds: 180);
  static const Duration pressDown = Duration(milliseconds: 90);
  static const Duration pressUp = Duration(milliseconds: 150);
  static const Duration modal = Duration(milliseconds: 250);
  static const Duration fadeIn = Duration(milliseconds: 220);
}
