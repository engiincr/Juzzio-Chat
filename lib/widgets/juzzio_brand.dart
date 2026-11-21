// =============================================================================
// JUZZIO 2.1 — Marka: resmî limon "J" logosu, kelime markası ve ortak ekran başlığı
//  • Logo vektör yol olarak çizilir (her boyutta keskin); kaynak assets/brand/juzzio_logo_source.png,
//    platform ikonları tools/brand_logo.py ile aynı kaynaktan üretilir.
//  • JuzzioScreenHeader: tasarımdaki "geri · J Juzzio · Başlık · menü" düzeni (tüm alt sayfalar)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';

/// Marka renkleri (tasarım dosyalarından ölçüldü)
class JuzzioBrandColors {
  JuzzioBrandColors._();
  static const Color lime = Color(0xFFC6F135);
  static const Color limeHighlight = Color(0xFFE2FF78);
  static const Color deep = Color(0xFF2E4A08);
  static const Color ink = Color(0xFF0E0F12);
}

/// v2.1: resmî logo — limon "J" (assets/brand/juzzio_logo_source.png'den vektöre çevrildi,
/// tools/brand_logo.py ile aynı kaynak). Birim kare içinde, ortalanmış.
class JuzzioLogoGeometry {
  JuzzioLogoGeometry._();

  /// Logodaki limon rengi (kaynak görselden ölçüldü)
  static const Color logoLime = Color(0xFFBAFA08);

  static Path glyph(double s) => Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(0.50348 * s, 0.99943 * s)
    ..cubicTo(0.57636 * s, 0.99290 * s, 0.64258 * s, 0.96952 * s, 0.70795 * s, 0.92723 * s)
    ..cubicTo(0.78255 * s, 0.87898 * s, 0.84768 * s, 0.80025 * s, 0.89628 * s, 0.69959 * s)
    ..cubicTo(0.92775 * s, 0.63440 * s, 0.94330 * s, 0.57476 * s, 0.94727 * s, 0.50406 * s)
    ..cubicTo(0.94886 * s, 0.47559 * s, 0.94879 * s, 0.14703 * s, 0.94719 * s, 0.12978 * s)
    ..cubicTo(0.94491 * s, 0.10535 * s, 0.93952 * s, 0.08652 * s, 0.92969 * s, 0.06871 * s)
    ..cubicTo(0.91048 * s, 0.03392 * s, 0.87904 * s, 0.01114 * s, 0.83778 * s, 0.00210 * s)
    ..cubicTo(0.83221 * s, 0.00088 * s, 0.79677 * s, 0.00058 * s, 0.65991 * s, 0.00058 * s)
    ..lineTo(0.48899 * s, 0.00058 * s)
    ..lineTo(0.47598 * s, 0.00322 * s)
    ..cubicTo(0.42336 * s, 0.01388 * s, 0.38348 * s, 0.04326 * s, 0.36104 * s, 0.08788 * s)
    ..cubicTo(0.32781 * s, 0.15398 * s, 0.34812 * s, 0.23665 * s, 0.40707 * s, 0.27518 * s)
    ..cubicTo(0.42587 * s, 0.28747 * s, 0.44424 * s, 0.29405 * s, 0.46682 * s, 0.29656 * s)
    ..cubicTo(0.47363 * s, 0.29732 * s, 0.50997 * s, 0.29780 * s, 0.56130 * s, 0.29780 * s)
    ..lineTo(0.64471 * s, 0.29780 * s)
    ..lineTo(0.64797 * s, 0.30059 * s)
    ..lineTo(0.65122 * s, 0.30339 * s)
    ..lineTo(0.65158 * s, 0.38373 * s)
    ..cubicTo(0.65196 * s, 0.46903 * s, 0.65103 * s, 0.49940 * s, 0.64709 * s, 0.53017 * s)
    ..cubicTo(0.63815 * s, 0.60012 * s, 0.61232 * s, 0.64767 * s, 0.56483 * s, 0.68164 * s)
    ..cubicTo(0.55179 * s, 0.69097 * s, 0.52575 * s, 0.70419 * s, 0.51043 * s, 0.70925 * s)
    ..cubicTo(0.49726 * s, 0.71361 * s, 0.49366 * s, 0.71567 * s, 0.48747 * s, 0.72238 * s)
    ..cubicTo(0.48152 * s, 0.72883 * s, 0.47915 * s, 0.73657 * s, 0.47912 * s, 0.74963 * s)
    ..cubicTo(0.47906 * s, 0.77877 * s, 0.46880 * s, 0.81656 * s, 0.45192 * s, 0.84980 * s)
    ..cubicTo(0.43044 * s, 0.89210 * s, 0.39534 * s, 0.93501 * s, 0.35731 * s, 0.96548 * s)
    ..cubicTo(0.34553 * s, 0.97493 * s, 0.34353 * s, 0.97810 * s, 0.34585 * s, 0.98370 * s)
    ..cubicTo(0.34655 * s, 0.98537 * s, 0.34809 * s, 0.98735 * s, 0.34927 * s, 0.98809 * s)
    ..cubicTo(0.35460 * s, 0.99141 * s, 0.39932 * s, 0.99800 * s, 0.43279 * s, 1.00038 * s)
    ..cubicTo(0.44791 * s, 1.00146 * s, 0.48667 * s, 1.00094 * s, 0.50348 * s, 0.99943 * s)
    ..close()
    ..moveTo(0.29507 * s, 0.96412 * s)
    ..cubicTo(0.30909 * s, 0.95979 * s, 0.31869 * s, 0.95178 * s, 0.34099 * s, 0.92586 * s)
    ..cubicTo(0.39746 * s, 0.86020 * s, 0.43279 * s, 0.79096 * s, 0.43279 * s, 0.74599 * s)
    ..cubicTo(0.43279 * s, 0.73660 * s, 0.43238 * s, 0.73427 * s, 0.42979 * s, 0.72908 * s)
    ..cubicTo(0.42622 * s, 0.72192 * s, 0.41938 * s, 0.71574 * s, 0.41205 * s, 0.71306 * s)
    ..cubicTo(0.39367 * s, 0.70633 * s, 0.38835 * s, 0.70397 * s, 0.37998 * s, 0.69882 * s)
    ..cubicTo(0.36127 * s, 0.68730 * s, 0.34904 * s, 0.67236 * s, 0.33393 * s, 0.64253 * s)
    ..cubicTo(0.32523 * s, 0.62536 * s, 0.31840 * s, 0.61628 * s, 0.30763 * s, 0.60755 * s)
    ..cubicTo(0.29812 * s, 0.59984 * s, 0.28899 * s, 0.59532 * s, 0.27514 * s, 0.59146 * s)
    ..cubicTo(0.26525 * s, 0.58871 * s, 0.26166 * s, 0.58836 * s, 0.23786 * s, 0.58780 * s)
    ..cubicTo(0.20807 * s, 0.58711 * s, 0.19640 * s, 0.58816 * s, 0.17678 * s, 0.59331 * s)
    ..cubicTo(0.16184 * s, 0.59723 * s, 0.14829 * s, 0.60283 * s, 0.13413 * s, 0.61095 * s)
    ..cubicTo(0.09057 * s, 0.63593 * s, 0.05938 * s, 0.68106 * s, 0.05389 * s, 0.72708 * s)
    ..cubicTo(0.04906 * s, 0.76749 * s, 0.06657 * s, 0.81467 * s, 0.10337 * s, 0.86039 * s)
    ..cubicTo(0.11385 * s, 0.87342 * s, 0.13650 * s, 0.89579 * s, 0.15128 * s, 0.90772 * s)
    ..cubicTo(0.16689 * s, 0.92032 * s, 0.19363 * s, 0.93756 * s, 0.21044 * s, 0.94586 * s)
    ..cubicTo(0.24794 * s, 0.96438 * s, 0.27521 * s, 0.97026 * s, 0.29507 * s, 0.96412 * s)
    ..close();
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({this.mono});
  final Color? mono;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawPath(
      JuzzioLogoGeometry.glyph(s),
      Paint()
        ..isAntiAlias = true
        ..color = mono ?? JuzzioLogoGeometry.logoLime,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.mono != mono;
}

/// Yalnız logo "J" (saydam zemin)
class JuzzioLogoGlyph extends StatelessWidget {
  const JuzzioLogoGlyph({super.key, this.size = 28, this.mono});
  final double size;
  final Color? mono;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Juzzio',
      child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(mono: mono))),
    );
  }
}

/// Koyu yuvarlak kare içinde logo (uygulama ikonu görünümü)
class JuzzioLogoTile extends StatelessWidget {
  const JuzzioLogoTile({super.key, this.size = 40, this.glow = true});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.19),
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: JuzzioBrandColors.lime.withValues(alpha: 0.22)),
        boxShadow: glow
            ? [BoxShadow(color: JuzzioBrandColors.lime.withValues(alpha: 0.28), blurRadius: size * 0.5, spreadRadius: -size * 0.08)]
            : null,
      ),
      child: JuzzioLogoGlyph(size: size * 0.62),
    );
  }
}

/// Kelime markası: logo J + "Juzzio" (tasarımdaki başlık logosu)
class JuzzioWordmark extends StatelessWidget {
  const JuzzioWordmark({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        JuzzioLogoGlyph(size: size * 1.15),
        SizedBox(width: size * 0.12),
        Text(
          'Juzzio',
          maxLines: 1,
          style: TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: color ?? JuzzioGlassTokens.heading,
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -size * 0.03,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

/// Yuvarlak cam başlık düğmesi (geri / menü)
class JuzzioHeaderCircleButton extends StatelessWidget {
  const JuzzioHeaderCircleButton({super.key, required this.icon, required this.onTap, this.tooltip, this.size = 40});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: JuzzioGlassTokens.spaceCard,
      shape: CircleBorder(side: BorderSide(color: JuzzioGlassTokens.spaceCardBorder)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: size * 0.5, color: JuzzioGlassTokens.textPrimary)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Tasarımdaki alt sayfa başlığı: solda geri, ortada "J Juzzio" + büyük başlık (+ alt açıklama),
/// sağda isteğe bağlı eylem. Kaydırılabilir sayfaların en üstüne konur.
class JuzzioScreenHeader extends StatelessWidget {
  const JuzzioScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.onBack,
    this.trailing,
    this.showBack = true,
    this.showWordmark = true,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool showBack;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: showBack && (canPop || onBack != null)
                    ? JuzzioHeaderCircleButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: app.trEn('Geri', 'Back', 'Zurück'),
                        onTap: onBack ?? () => Navigator.of(context).maybePop(),
                      )
                    : null,
              ),
              Expanded(child: Center(child: showWordmark ? const JuzzioWordmark(size: 20) : const SizedBox.shrink())),
              SizedBox(width: 40, child: trailing),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, color: JuzzioGlassTokens.textPrimary, size: 24),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioGlassTokens.heading,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
