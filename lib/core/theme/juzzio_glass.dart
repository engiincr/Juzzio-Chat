// =============================================================================
// JUZZIO v0.6.0 — Glassmorphism tasarım sistemi
//  Aurora zemin (juzzio_aurora.dart) üzerinde buzlu, yarı saydam cam yüzeyler:
//  ince kristal kenar, sol üstten vuran ışık, yumuşak gölge. Turuncu ton yoktur.
//  Yeniden kullanılabilir cam bileşenleri:
//   • JuzzioGlass            : bulanık, ince kristal kenarlı yüzey (tek blur katmanı)
//   • JuzzioGlassCard        : kart (liste içinde blur kullanmayan hafif sürüm dahil)
//   • JuzzioGlassIconButton  : yuvarlak cam ikon butonu
//   • JuzzioGlassButton      : birincil / ikincil hap buton
//   • JuzzioGlassTextField   : cam metin alanı
//   • JuzzioGlassBadge       : sayı rozeti
//   • JuzzioGlassAvatar      : profil fotoğrafı (yoksa baş harf) + isteğe bağlı halka
//   • showJuzzioGlassSheet   : cam alt pencere
//   • showJuzzioGlassDialog  : cam diyalog
//  Performans: liste öğelerinde blur kullanılmaz (`blur: false`), blur yalnızca
//  üst katman yüzeylerde ve tek bir BackdropFilter ile uygulanır.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'juzzio_aurora.dart';
import 'juzzio_colors.dart';
import 'juzzio_custom_theme.dart';

/// Uygulama genelinde emoji yazı tipi (Noto Color Emoji, OFL 1.1 — pubspec'te
/// `JuzzioEmoji` ailesi). Tüm metinlerde yedek yazı tipi olarak kullanılır;
/// böylece emojiler her cihazda aynı görünür.
const List<String> kJuzzioEmojiFallback = <String>['JuzzioEmoji'];

/// Ağırlıklı olarak emoji gösteren metinler (tepkiler, seçici, çıkartmalar) için stil.
TextStyle juzzioEmojiStyle(double size) => TextStyle(
      fontSize: size,
      fontFamily: 'JuzzioEmoji',
      fontFamilyFallback: kJuzzioEmojiFallback,
      height: 1.15,
    );

class JuzzioGlassTokens {
  JuzzioGlassTokens._();

  /// v0.7.0: Cam belirteçleri artık TEMA DUYARLIDIR (önceden koyu temaya kilitli sabitlerdi).
  /// Uygulama açılışında JuzzioAppController ile bağlanır; aydınlık modda koyu metin,
  /// beyaz buzlu cam ve ince grafit kenar; karanlık modda berrak beyaz kristal kenar ve
  /// derin grafit cam korunur.
  static bool Function() isDarkResolver = () => true;
  static bool get _d => isDarkResolver();

  /// v0.8.0: yumuşak cam — arka plan seçilebilir kalır, blur sert değil
  static const double blurSigma = 18;

  // v0.8.1 brief §3/§7: bileşene göre blur, opaklık ve köşe değerleri
  static const double blurSmall = 10;
  static const double blurHeader = 12;
  static const double blurComposer = 14;
  static const double blurNavigation = 18;
  static const double blurCallControls = 20;
  static const double blurModal = 24;
  static const double blurSpecial = 30;
  static const double opacityStandard = 0.34;
  static const double opacityStrong = 0.40;
  static const double borderOpacity = 0.20;
  static const double glowOpacity = 0.08;
  static const double radiusSmall = 14;
  static const double radiusCard = 20;
  static const double radiusLarge = 26;
  static const double radiusModal = 30;

  /// Performans modu (brief §16): true iken cam yüzeyler blur yerine statik yarı saydam
  /// renk kullanır. Ayarlardan değiştirilir.
  static bool reducedEffects = false;

  /// v0.8.1 Cam yoğunluğu (Ayarlar → Görünüm): 0.6 sade … 1.4 belirgin. Yüzey/kenar
  /// opaklığını ve blur miktarını güvenli sınırlar içinde ölçekler.
  static double intensity = 1.0;
  /// Yüksek Kontrast teması: kenarlar ve ikincil metinler belirginleşir (erişilebilirlik)
  static bool Function() highContrastResolver = () => false;
  static bool get _hc => highContrastResolver();
  /// v0.8.4: etkin temanın cam karakteri (blur, opaklık, ışık, derinlik, kenar rengi)
  static JuzzioGlassCharacter Function() characterResolver = () => JuzzioGlassCharacter.standard;
  static JuzzioGlassCharacter get character => custom != null ? JuzzioGlassCharacter.standard : characterResolver();
  static Color _scaled(Color c) =>
      c.withValues(alpha: (c.a * intensity * character.opacity * (_hc ? 2.2 : 1.0)).clamp(0.0, 1.0));
  static double get effectiveBlur => (blurSigma * intensity).clamp(6.0, 30.0);
  /// v0.8.2 Tema Stüdyosu: etkin (veya düzenlenmekte olan) özel tema. null → hazır tema.
  static JuzzioCustomTheme? custom;
  static JuzzioCustomTheme? get _ct => custom;
  static double get _ci => _ct?.intensity ?? 1.0;
  static Color _scaledC(Color c) =>
      c.withValues(alpha: (c.a * intensity * _ci * (_hc ? 2.2 : 1.0)).clamp(0.0, 1.0));

  /// Bileşen için etkin temel blur (özel temada kullanıcının değeri)
  static double get baseBlur => _ct?.blur ?? blurSigma * character.blur;

  static Color get surface {
    final t = _ct;
    if (t != null) return _scaledC(t.card.withValues(alpha: t.opacity));
    return _scaled(_d ? const Color(0x0DFFFFFF) : const Color(0x3DFFFFFF));
  }

  static Color get surfaceStrong {
    final t = _ct;
    if (t != null) return _scaledC(t.card.withValues(alpha: (t.opacity * 1.6).clamp(0.0, 0.92)));
    return _scaled(_d ? const Color(0x1AFFFFFF) : const Color(0x66FFFFFF));
  }

  static Color get surfaceSolid {
    final t = _ct;
    if (t != null) return t.card.withValues(alpha: math.max(t.opacity * 2.4, 0.62).clamp(0.0, 0.96));
    return _scaled(_d ? const Color(0x5C12141C) : const Color(0x99FFFFFF));
  }

  static Color get sheet {
    final t = _ct;
    if (t != null) return Color.alphaBlend(t.card.withValues(alpha: 0.35), t.background.withValues(alpha: 0.88));
    return _d ? const Color(0xB80E1018) : const Color(0xD9F7F8FB);
  }

  static Color get border {
    final t = _ct;
    if (t != null) return _scaledC(t.border);
    return _scaled(_d ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF));
  }

  static Color get borderStrong {
    final t = _ct;
    if (t != null) return _scaledC(t.border.withValues(alpha: (t.border.a * 1.5).clamp(0.0, 1.0)));
    return _scaled(_d ? const Color(0x3DFFFFFF) : const Color(0xB3FFFFFF));
  }

  static Color get highlight => _d ? const Color(0x14FFFFFF) : const Color(0x0A000000);
  static Color get textPrimary => _ct?.text ?? (_d ? const Color(0xFFF5F5F7) : const Color(0xFF111113));
  static Color get textSecondary {
    final t = _ct;
    if (t != null) return t.text.withValues(alpha: _hc ? 0.92 : 0.74);
    return _hc ? (_d ? const Color(0xFFE5E5EA) : const Color(0xFF1C1C1E)) : (_d ? const Color(0xFFAEAEB2) : const Color(0xFF4A4A52));
  }

  static Color get textMuted {
    final t = _ct;
    if (t != null) return t.text.withValues(alpha: _hc ? 0.8 : 0.56);
    return _hc ? (_d ? const Color(0xFFC7C7CC) : const Color(0xFF3A3A3C)) : (_d ? const Color(0xFF7C7C82) : const Color(0xFF6E6E76));
  }

  /// Başlık ve ikon rolleri (özel temada ayrı ayrı seçilebilir)
  static Color get heading => _ct?.heading ?? textPrimary;
  static Color get icon => _ct?.icon ?? textPrimary;
  static const Color accent = JuzzioColors.accent;
  /// Birincil buton dolgusu: koyu modda beyaz, aydınlık modda grafit (her temada okunur)
  static Color get accentFill => _ct?.button ?? (_d ? JuzzioColors.accent : const Color(0xFF111113));
  static Color get onAccent => _ct?.buttonText ?? (_d ? const Color(0xFF111113) : const Color(0xFFFFFFFF));
  static const double radius = 22;

  static List<BoxShadow> get shadow {
    final k = character.depth;
    return _d
        ? [BoxShadow(color: Color.fromRGBO(0, 0, 0, (0.30 * k).clamp(0.0, 0.6)), blurRadius: 40 * k, offset: Offset(0, 20 * k))]
        : [BoxShadow(color: const Color(0xFF1B1F3B).withValues(alpha: (0.10 * k).clamp(0.0, 0.3)), blurRadius: 40 * k, offset: Offset(0, 20 * k))];
  }

  /// Sayfa zemini artık saydamdır: her sayfanın arkasında seçili aurora cam
  /// teması çizilir (JuzzioAuroraPageTransitionsBuilder).
  static const BoxDecoration backdrop = BoxDecoration();

  /// Camın sol üstten vuran ışığı
  static LinearGradient get sheen {
    final k = character.sheen;
    Color w(double a) => Colors.white.withValues(alpha: (a * k).clamp(0.0, 1.0));
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _d ? [w(0.20), w(0.06), w(0.04)] : [w(0.45), w(0.15), w(0.06)],
      stops: const [0.0, 0.45, 1.0],
    );
  }
}

/// Bulanık cam yüzey. [blur] false olduğunda (liste öğeleri gibi) blur yerine
/// yarı opak sıcak zemin kullanılır; görünüm tutarlı kalır, kaydırma akıcı olur.
class JuzzioGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool blur;
  final Color? color;
  final bool strongBorder;
  final List<BoxShadow>? shadow;
  /// Bileşene özel blur (null → varsayılan)
  final double? blurSigma;

  const JuzzioGlass({
    super.key,
    required this.child,
    this.radius = JuzzioGlassTokens.radius,
    this.padding,
    this.blur = true,
    this.color,
    this.strongBorder = false,
    this.shadow,
    this.blurSigma,
  });

  @override
  Widget build(BuildContext context) {
    // v0.8.1: 3D buzlu cam (apply.txt "Key Settings"): dolgu ve ışık ayrı katmanlarda
    // (önceden BoxDecoration'da color + gradient birlikteydi; Flutter yalnızca gradyanı
    // çizdiği için cam tonu kayboluyor, renkler çamurlaşıyordu).
    final br = BorderRadius.circular(radius);
    final d = JuzzioGlassTokens._d;
    final tint = color ?? (blur && !JuzzioGlassTokens.reducedEffects ? JuzzioGlassTokens.surface : JuzzioGlassTokens.surfaceSolid);
    final body = CustomPaint(
      foregroundPainter: JuzzioGlassBorderPainter(
        radius: radius,
        strong: strongBorder,
        dark: d,
        rim: JuzzioGlassTokens.character.rim,
        glow: JuzzioGlassTokens.character.glow,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: br, color: tint),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: br, gradient: JuzzioGlassTokens.sheen),
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: br, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: br,
        child: blur && !JuzzioGlassTokens.reducedEffects
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(
                    sigmaX: ((blurSigma ?? JuzzioGlassTokens.baseBlur) * JuzzioGlassTokens.intensity).clamp(6.0, 30.0),
                    sigmaY: ((blurSigma ?? JuzzioGlassTokens.baseBlur) * JuzzioGlassTokens.intensity).clamp(6.0, 30.0)),
                child: body,
              )
            : body,
      ),
    );
  }
}

/// 3D speküler + hafif yanardöner (iridescent) kenar ve içe sızan ışık (inner glow).
/// Sol üst köşe parlak, sağ alt köşe hafif renkli; kenarın ortaları neredeyse görünmez.
class JuzzioGlassBorderPainter extends CustomPainter {
  final double radius;
  final bool strong;
  final bool dark;
  final bool iridescent;
  /// v0.8.4: temanın kenar ışığı rengi ve neon parıltısı
  final Color? rim;
  final double glow;
  const JuzzioGlassBorderPainter(
      {required this.radius, this.strong = false, this.dark = true, this.iridescent = true, this.rim, this.glow = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(radius));
    final a = strong ? 1.0 : 0.75;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strong ? 1.4 : 1.1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: (dark ? 0.55 : 0.95) * a),
          Colors.white.withValues(alpha: (dark ? 0.10 : 0.45) * a),
          Colors.white.withValues(alpha: (dark ? 0.04 : 0.30) * a),
          if (iridescent) (rim ?? const Color(0xFF9AD7FF)).withValues(alpha: (dark ? 0.30 : 0.45) * a),
          if (iridescent) (rim ?? const Color(0xFFD7B4FF)).withValues(alpha: (dark ? 0.38 : 0.55) * a),
        ],
        stops: iridescent ? const [0.0, 0.32, 0.6, 0.85, 1.0] : const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rr, edge);
    // Neon temalarda kenar parıltısı
    if (glow > 0 && rim != null) {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6)
          ..color = rim!.withValues(alpha: glow.clamp(0.0, 1.0)),
      );
    }
    // İçe sızan ışık: yalnızca üst kenarda yumuşak bir parlama
    final innerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [Colors.white.withValues(alpha: dark ? 0.10 : 0.22), Colors.transparent],
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRRect(rr.deflate(2), innerGlow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JuzzioGlassBorderPainter old) =>
      old.radius != radius || old.strong != strong || old.dark != dark || old.iridescent != iridescent || old.rim != rim || old.glow != glow;
}

class JuzzioGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool blur;
  final double radius;

  const JuzzioGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.blur = false,
    this.radius = JuzzioGlassTokens.radius,
  });

  @override
  Widget build(BuildContext context) {
    final card = JuzzioGlass(
      blur: blur,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          splashColor: JuzzioColors.accent.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.03),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return Padding(padding: margin, child: card);
  }
}

class JuzzioGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final bool active;
  final int badgeCount;
  final Color? iconColor;

  const JuzzioGlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.tooltip,
    this.active = false,
    this.badgeCount = 0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? JuzzioGlassTokens.accent : JuzzioGlassTokens.surface,
            border: Border.all(color: active ? Colors.transparent : JuzzioGlassTokens.border),
          ),
          child: Icon(
            icon,
            size: size * 0.48,
            color: iconColor ?? (active ? JuzzioGlassTokens.onAccent : JuzzioGlassTokens.textPrimary),
          ),
        ),
      ),
    );
    if (badgeCount > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(top: -2, right: -2, child: JuzzioGlassBadge(count: badgeCount)),
        ],
      );
    }
    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class JuzzioGlassBadge extends StatelessWidget {
  final int count;
  final Color color;
  const JuzzioGlassBadge({super.key, required this.count, this.color = const Color(0xFFFF3B30)});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
    );
  }
}

class JuzzioGlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;
  final bool expand;
  final double height;

  const JuzzioGlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = true,
    this.loading = false,
    this.expand = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? JuzzioGlassTokens.onAccent : JuzzioGlassTokens.textPrimary;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else if (icon != null)
          Icon(icon, size: 19, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.1),
          ),
        ),
      ],
    );
    final disabled = onTap == null || loading;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: disabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        child: primary
            ? Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: JuzzioGlassTokens.accentFill,
                  border: Border.all(color: JuzzioGlassTokens.borderStrong),
                ),
                child: content,
              )
            : JuzzioGlass(
                radius: 999,
                blur: false,
                color: JuzzioGlassTokens.surface,
                child: SizedBox(
                  height: height - 2,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: content),
                ),
              ),
      ),
    );
  }
}

class JuzzioGlassTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscure;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? maxLength;
  final bool autofocus;
  final TextInputAction? textInputAction;

  const JuzzioGlassTextField({
    super.key,
    this.controller,
    required this.hint,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.autocorrect = true,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return JuzzioGlass(
      blur: false,
      radius: 18,
      color: JuzzioGlassTokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: JuzzioGlassTokens.textSecondary, size: 20),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              autocorrect: autocorrect && !obscure,
              enableSuggestions: autocorrect && !obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              maxLines: obscure ? 1 : maxLines,
              maxLength: maxLength,
              autofocus: autofocus,
              textInputAction: textInputAction,
              cursorColor: JuzzioColors.accent,
              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted),
                border: InputBorder.none,
                filled: false,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

/// Profil fotoğrafı; fotoğraf yoksa ya da yüklenemezse baş harf gösterilir.
/// [ringColor] verilirse (ör. aktif hikâye veya konuşma) çevresinde halka çizilir.
class JuzzioGlassAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? ringColor;
  final Gradient? ringGradient;
  final double ringWidth;

  const JuzzioGlassAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 22,
    this.ringColor,
    this.ringGradient,
    this.ringWidth = 2.5,
  });

  static String initialOf(String name) {
    final t = name.trim().replaceAll('@', '');
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    final fallback = Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF48484A), Color(0xFF242427)],
        ),
      ),
      child: Text(
        initialOf(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.85,
        ),
      ),
    );
    Widget avatar = ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: url.startsWith('http')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: (radius * 2 * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (ctx, child, progress) => progress == null ? child : fallback,
              )
            : fallback,
      ),
    );
    if (ringColor != null || ringGradient != null) {
      avatar = Container(
        padding: EdgeInsets.all(ringWidth + 1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ringGradient == null ? ringColor : null,
          gradient: ringGradient,
        ),
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: JuzzioGlassTokens._d ? JuzzioColors.obsidian : Colors.white),
          child: avatar,
        ),
      );
    }
    return avatar;
  }
}

/// Aktif hikâyesi olan kullanıcı halkası — v0.7.0: tema duyarlı canlı cam halka
/// (gök mavisi → çivit → mor → pembe; turuncu yok). Aydınlık temada da net görünür.
Gradient get kJuzzioStoryRing => JuzzioGlassTokens._d
    ? const SweepGradient(colors: [JuzzioColors.cyan, JuzzioColors.blue, JuzzioColors.purple, JuzzioColors.cyanSoft, JuzzioColors.cyan])
    : const SweepGradient(colors: [Color(0xFF0891B2), JuzzioColors.blue, Color(0xFF7C3AED), Color(0xFF0891B2)]);

/// v0.8.1: izlenmiş hikâye — aynı halka, belirgin biçimde soluk
Gradient get kJuzzioStorySeenRing => SweepGradient(colors: [
      JuzzioGlassTokens.textMuted.withValues(alpha: 0.55),
      JuzzioGlassTokens.textMuted.withValues(alpha: 0.30),
      JuzzioGlassTokens.textMuted.withValues(alpha: 0.55),
    ]);

/// Yakın arkadaşlara özel hikâye halkası (yeşil)
const Gradient kJuzzioCloseFriendsRing = SweepGradient(
  colors: [Color(0xFF34C759), Color(0xFF30D158), Color(0xFF00C7BE), Color(0xFF34C759)],
);

Future<T?> showJuzzioGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: JuzzioGlass(
            radius: 30,
            color: JuzzioGlassTokens.sheet,
            strongBorder: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: JuzzioGlassTokens.textMuted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<T?> showJuzzioGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<Widget> actions,
  IconData? icon,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: JuzzioGlass(
            radius: 28,
            color: JuzzioGlassTokens.sheet,
            strongBorder: true,
            shadow: JuzzioGlassTokens.shadow,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: JuzzioColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: JuzzioColors.accent),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  title,
                  style: TextStyle(
                    color: JuzzioGlassTokens.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message, style: TextStyle(color: JuzzioGlassTokens.textSecondary, height: 1.4)),
                ],
                if (content != null) ...[const SizedBox(height: 14), content],
                const SizedBox(height: 18),
                Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(c), child: child),
      );
    },
  );
}

/// Merkezî koyu tema: Material bileşenleri (dialog, sheet, input, buton, switch...)
/// otomatik olarak cam paletiyle çizilir.
ThemeData buildJuzzioDarkTheme({required String fontFamily, required PageTransitionsTheme transitions, bool dark = true}) {
  // v0.8.1: aynı cam bileşen temaları aydınlık modda da (dark:false) uygulanır
  final acc = dark ? JuzzioColors.accent : const Color(0xFF111113);
  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: acc,
    onPrimary: JuzzioGlassTokens.onAccent,
    primaryContainer: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
    onPrimaryContainer: dark ? JuzzioColors.accentLight : const Color(0xFF111113),
    secondary: dark ? JuzzioColors.accentLight : const Color(0xFF2563EB),
    onSecondary: JuzzioGlassTokens.onAccent,
    tertiary: dark ? const Color(0xFFC7C7CC) : const Color(0xFF3A3A3C),
    onTertiary: dark ? const Color(0xFF111113) : Colors.white,
    error: const Color(0xFFFF453A),
    onError: Colors.white,
    surface: dark ? JuzzioColors.obsidianRaised : const Color(0xFFF7F8FB),
    onSurface: JuzzioGlassTokens.textPrimary,
    surfaceContainerHighest: dark ? JuzzioColors.obsidianElevated : const Color(0xFFE9EBF1),
    onSurfaceVariant: JuzzioGlassTokens.textSecondary,
    outline: dark ? const Color(0x33FFFFFF) : const Color(0x33000000),
    outlineVariant: dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: fontFamily,
    fontFamilyFallback: kJuzzioEmojiFallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: dark ? const Color(0xFF0C0D12) : const Color(0xFFF7F8FB),
    pageTransitionsTheme: transitions,
  );
  final roundedInput = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: JuzzioGlassTokens.border),
  );
  return base.copyWith(
    // v0.8.2: ikon ve başlık rolleri (Tema Stüdyosu'nda ayrı seçilebilir)
    iconTheme: IconThemeData(color: JuzzioGlassTokens.icon),
    textTheme: base.textTheme.apply(bodyColor: JuzzioGlassTokens.textPrimary, displayColor: JuzzioGlassTokens.heading),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: JuzzioGlassTokens.heading,
      iconTheme: IconThemeData(color: JuzzioGlassTokens.icon),
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: JuzzioGlassTokens.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: JuzzioGlassTokens.borderStrong),
      ),
      titleTextStyle: TextStyle(
        color: JuzzioGlassTokens.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w900,
      ),
      contentTextStyle: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14.5, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: JuzzioGlassTokens.sheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: JuzzioGlassTokens.sheet,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        side: BorderSide(color: JuzzioGlassTokens.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: JuzzioGlassTokens.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: JuzzioGlassTokens.border),
      ),
      textStyle: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JuzzioGlassTokens.sheet,
      contentTextStyle: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: JuzzioGlassTokens.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JuzzioGlassTokens.surface,
      hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted),
      labelStyle: TextStyle(color: JuzzioGlassTokens.textSecondary),
      floatingLabelStyle: TextStyle(color: JuzzioGlassTokens.textPrimary),
      prefixIconColor: JuzzioGlassTokens.textSecondary,
      suffixIconColor: JuzzioGlassTokens.textSecondary,
      border: roundedInput,
      enabledBorder: roundedInput,
      focusedBorder: roundedInput.copyWith(borderSide: BorderSide(color: JuzzioGlassTokens.borderStrong, width: 1.3)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: JuzzioGlassTokens.accentFill,
        foregroundColor: JuzzioGlassTokens.onAccent,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JuzzioGlassTokens.textPrimary,
        side: BorderSide(color: JuzzioGlassTokens.borderStrong),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: JuzzioGlassTokens.textPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: JuzzioGlassTokens.surface,
      selectedColor: JuzzioGlassTokens.surfaceStrong,
      labelStyle: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800),
      side: BorderSide(color: JuzzioGlassTokens.border),
      shape: const StadiumBorder(),
      checkmarkColor: JuzzioGlassTokens.textPrimary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : JuzzioGlassTokens.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Color(0xFF34C759) : JuzzioGlassTokens.surfaceStrong,
      ),
      trackOutlineColor: WidgetStateProperty.all(JuzzioGlassTokens.border),
    ),
    dividerTheme: DividerThemeData(color: JuzzioGlassTokens.border, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: JuzzioGlassTokens.custom?.icon ?? JuzzioGlassTokens.textSecondary,
      textColor: JuzzioGlassTokens.textPrimary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: acc),
    tabBarTheme: TabBarThemeData(
      labelColor: JuzzioGlassTokens.textPrimary,
      unselectedLabelColor: JuzzioGlassTokens.textSecondary,
      indicatorColor: acc,
      dividerColor: JuzzioGlassTokens.border,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: acc,
      selectionColor: dark ? const Color(0x55FFFFFF) : const Color(0x332563EB),
      selectionHandleColor: acc,
    ),
  );
}
