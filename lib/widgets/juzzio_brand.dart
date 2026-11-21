// =============================================================================
// JUZZIO 2.1 — Marka: yeşil şerit "J" logosu, kelime markası ve ortak ekran başlığı
//  • Logo tamamen kodla çizilir (dış görsel yok); geometri tools/brand_icon.py ile aynıdır,
//    böylece uygulama içi logo ve başlatıcı ikonu birebir aynı görünür.
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

/// Birim kare içindeki şerit yolları (tools/brand_icon.py ile birebir)
class JuzzioLogoGeometry {
  JuzzioLogoGeometry._();
  static const double width = 0.19;

  static Path stem(double s) => Path()
    ..moveTo(0.64 * s, 0.17 * s)
    ..lineTo(0.64 * s, 0.56 * s)
    ..cubicTo(0.64 * s, 0.86 * s, 0.36 * s, 0.90 * s, 0.24 * s, 0.70 * s);

  static Path leaf(double s) => Path()
    ..moveTo(0.24 * s, 0.40 * s)
    ..cubicTo(0.34 * s, 0.30 * s, 0.50 * s, 0.20 * s, 0.64 * s, 0.17 * s);
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({this.mono});
  final Color? mono;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size(s, s);
    Paint stroke(Shader? shader) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = JuzzioLogoGeometry.width * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..shader = mono == null ? shader : null
      ..color = mono ?? Colors.white;
    canvas.drawPath(
      JuzzioLogoGeometry.leaf(s),
      stroke(const LinearGradient(
        begin: Alignment(-0.6, 0.3),
        end: Alignment(0.4, -0.7),
        colors: [JuzzioBrandColors.deep, JuzzioBrandColors.lime],
      ).createShader(rect)),
    );
    canvas.drawPath(
      JuzzioLogoGeometry.stem(s),
      stroke(LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          JuzzioBrandColors.limeHighlight,
          JuzzioBrandColors.lime,
          Color.lerp(JuzzioBrandColors.lime, JuzzioBrandColors.deep, 0.5)!,
          JuzzioBrandColors.lime,
        ],
        stops: const [0.1, 0.5, 0.82, 1.0],
      ).createShader(rect)),
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.mono != mono;
}

/// Yalnız şerit "J" (saydam zemin)
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
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: JuzzioBrandColors.ink,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: JuzzioBrandColors.lime.withValues(alpha: 0.22)),
        boxShadow: glow
            ? [BoxShadow(color: JuzzioBrandColors.lime.withValues(alpha: 0.28), blurRadius: size * 0.5, spreadRadius: -size * 0.08)]
            : null,
      ),
      child: JuzzioLogoGlyph(size: size * 0.76),
    );
  }
}

/// Kelime markası: şerit J + "Juzzio" (tasarımdaki başlık logosu)
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
