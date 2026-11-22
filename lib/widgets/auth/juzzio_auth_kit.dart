// =============================================================================
// JUZZIO GM-002 — Giriş / Kayıt ortak bileşenleri (Design System v1.3)
//  Referans: Engin'in "Trawave Giriş Ekranı" ve "Trawave Kayıt Ekranı" görselleri.
//  Katman haritası (K4, arkadan öne):
//   L1 lime hero zemin (kod)  → JuzzioAuthBackdrop
//   L2 portre (ayrı PNG)      → JuzzioAuthHeroScene
//   L3 geri düğmesi + J logo  → JuzzioAuthHeroScene
//   L4 emoji balonları        → JuzzioEmojiBubble (Fluent Emoji 3D, MIT)
//   L5 ses çıkartması         → JuzzioAudioSticker (CustomPainter)
//   L6 koyu cam panel         → JuzzioAuthGlassPanel
//   L7 chip + başlık + açıklama, L8 form, sosyal giriş, alt bağlantı
//  Hero konumları "sahne birimi" ile verilir: sahne genişliği 1192 birim = ekran genişliği
//  (referans görselin telefon çerçevesi ve durum çubuğu hariç alanı). Sabit piksel yok.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/juzzio_design_tokens.dart';
import '../juzzio_auth_hero.dart'
    show JuzzioGoogleMark, JuzzioGithubMark, JuzzioTitleScribble;
import '../juzzio_brand.dart' show JuzzioLogoGlyph;

/// Varlık yolları (K5). Portre GEÇİCİDİR: mevcut assets/images/auth_hero.jpg'den
/// renk anahtarıyla ayrıldı; Engin'den orijinal fotoğraf bekleniyor.
class JuzzioAuthAssets {
  JuzzioAuthAssets._();
  static const String portrait = 'assets/auth/portrait_temp.png';
  static const String emojiSunglasses =
      'assets/auth/emoji/smiling_face_with_sunglasses.png';
  static const String emojiGrin =
      'assets/auth/emoji/grinning_face_with_smiling_eyes.png';
  static const String emojiBeaming =
      'assets/auth/emoji/beaming_face_with_smiling_eyes.png';
  static const String emojiWave = 'assets/auth/emoji/waving_hand.png';
}

/// Sahne ölçüleri (birim: sahne genişliği 1192)
class _Scene {
  static const double width = 1192;
  static const double panelTop = 842; // referans: cam panelin üst kenarı
  static const double panelTopMin = 650; // yüz/çene her zaman görünür kalsın
  static const Rect portrait = Rect.fromLTWH(154, 148, 861, 688);
  static const Offset back = Offset(119, 77);
  static const double backDiameter = 106;
  static const double logoTop = 40;
  static const double logoGlyph = 110;
  static const double logoGap = 28;
  static const double logoText = 81;
  static const Rect sticker = Rect.fromLTWH(72, 690, 228, 88);
}

// ─────────────────────────────────────────────────────────────────────────────
// L1 — Lime hero zemin
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthBackdrop extends StatelessWidget {
  const JuzzioAuthBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.1, -0.55),
          radius: 1.15,
          colors: [
            JuzzioColorTokens.heroLight,
            JuzzioColorTokens.heroMid,
            JuzzioColorTokens.heroDeep
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// L2–L5 — Hero sahnesi
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthHeroScene extends StatelessWidget {
  const JuzzioAuthHeroScene(
      {super.key,
      required this.width,
      this.onBack,
      this.backLabel = 'Geri',
      this.panelTop});

  final double width;

  /// Cam panelin üst kenarı (dp). Panel referanstan yukarıda başlarsa alt dekorlar (ses kapsülü,
  /// orta emojiler) panelin altında kalmasın diye birlikte yukarı kaydırılır.
  final double? panelTop;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final u = width / _Scene.width;
    Rect r(Rect s) =>
        Rect.fromLTWH(s.left * u, s.top * u, s.width * u, s.height * u);
    final p = r(_Scene.portrait);
    // Alt dekorların panelle çakışmaması için ortak yukarı kayma (referans düzeninde 0)
    final lift = panelTop == null
        ? 0.0
        : math.max(0.0, (_Scene.sticker.bottom + 10) * u - panelTop!);
    final st = r(_Scene.sticker).shift(Offset(0, -lift));
    final backD =
        (_Scene.backDiameter * u).clamp(36.0, JuzzioSizes.iconCircleBack);
    final logoGlyph = _Scene.logoGlyph * u;

    return SizedBox(
      width: width,
      height: _Scene.panelTop * u,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // L2 portre
          Positioned.fromRect(
            rect: p,
            child: const ExcludeSemantics(
              child: Image(
                image: AssetImage(JuzzioAuthAssets.portrait),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          // L3 logo (J amblemi + Juzzio)
          Positioned(
            left: 0,
            right: 0,
            top: _Scene.logoTop * u,
            child: Center(
              child: Semantics(
                header: true,
                label: 'Trawave',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _shadowed(JuzzioLogoGlyph(size: logoGlyph), u),
                      SizedBox(width: _Scene.logoGap * u),
                      Text(
                        'Trawave',
                        maxLines: 1,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontFamily: JuzzioType.family,
                          fontWeight: FontWeight.w800,
                          fontSize: _Scene.logoText * u,
                          height: 1.0,
                          letterSpacing: -_Scene.logoText * u * 0.03,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 14 * u,
                                offset: Offset(0, 4 * u))
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // L3 geri düğmesi (yalnız gerçek bir geri işlemi varsa)
          if (onBack != null)
            Positioned(
              left: _Scene.back.dx * u - JuzzioSizes.minTouch / 2,
              top: _Scene.back.dy * u - JuzzioSizes.minTouch / 2,
              child: JuzzioHeroBackButton(
                  diameter: backD, onTap: onBack!, label: backLabel),
            ),
          // L4 emoji balonları
          JuzzioEmojiBubble.positioned(
              u: u,
              center: const Offset(320, 280),
              bubble: 190,
              glyph: 110,
              asset: JuzzioAuthAssets.emojiSunglasses),
          JuzzioEmojiBubble.positioned(
              u: u,
              center: Offset(185, 575 - lift / u * 0.6),
              bubble: 160,
              glyph: 84,
              asset: JuzzioAuthAssets.emojiGrin),
          JuzzioEmojiBubble.positioned(
              u: u,
              center: Offset(1032, 640 - lift / u),
              bubble: 182,
              glyph: 112,
              asset: JuzzioAuthAssets.emojiBeaming),
          // L5 ses çıkartması (dekoratif; oynatılabilir görünmez)
          Positioned.fromRect(rect: st, child: const JuzzioAudioSticker()),
        ],
      ),
    );
  }

  static Widget _shadowed(Widget child, double u) => DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18 * u,
                spreadRadius: -6 * u)
          ],
        ),
        child: child,
      );
}

class JuzzioHeroBackButton extends StatelessWidget {
  const JuzzioHeroBackButton(
      {super.key,
      required this.diameter,
      required this.onTap,
      required this.label});
  final double diameter;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: JuzzioSizes.minTouch,
        height: JuzzioSizes.minTouch,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            radius: JuzzioSizes.minTouch / 2,
            child: Center(
              child: Container(
                width: diameter,
                height: diameter,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: JuzzioColorTokens.heroBackFill),
                child: Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: diameter * 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JuzzioEmojiBubble extends StatelessWidget {
  const JuzzioEmojiBubble(
      {super.key,
      required this.diameter,
      required this.glyph,
      required this.asset});
  final double diameter;
  final double glyph;
  final String asset;

  static Widget positioned(
      {required double u,
      required Offset center,
      required double bubble,
      required double glyph,
      required String asset}) {
    final d = bubble * u;
    return Positioned(
      left: center.dx * u - d / 2,
      top: center.dy * u - d / 2,
      child: JuzzioEmojiBubble(diameter: d, glyph: glyph * u, asset: asset),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.04),
          ], stops: const [
            0.0,
            0.7,
            1.0
          ]),
        ),
        alignment: Alignment.center,
        child: Image.asset(asset,
            width: glyph, height: glyph, filterQuality: FilterQuality.high),
      ),
    );
  }
}

/// Lime ses mesajı kapsülü: siyah oynat dairesi + 8 dalga çubuğu (tamamen kodla çizilir)
class JuzzioAudioSticker extends StatelessWidget {
  const JuzzioAudioSticker({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(JuzzioRadius.pill),
          gradient: const LinearGradient(
              colors: [JuzzioColorTokens.accentSoft, JuzzioColorTokens.accent]),
          boxShadow: [
            BoxShadow(
                color: JuzzioColorTokens.accent.withValues(alpha: 0.45),
                blurRadius: 14,
                spreadRadius: -2)
          ],
        ),
        child: const CustomPaint(
            painter: _AudioStickerPainter(), child: SizedBox.expand()),
      ),
    );
  }
}

class _AudioStickerPainter extends CustomPainter {
  const _AudioStickerPainter();
  static const _bars = [0.42, 0.86, 0.50, 1.0, 0.38, 0.72, 0.95, 0.55];

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final ink = Paint()..color = JuzzioColorTokens.onAccent;
    // oynat dairesi
    final cR = h * 0.30;
    final c = Offset(h * 0.48, h / 2);
    canvas.drawCircle(c, cR, ink);
    final tri = Path()
      ..moveTo(c.dx - cR * 0.32, c.dy - cR * 0.45)
      ..lineTo(c.dx + cR * 0.50, c.dy)
      ..lineTo(c.dx - cR * 0.32, c.dy + cR * 0.45)
      ..close();
    canvas.drawPath(tri, Paint()..color = JuzzioColorTokens.accent);
    // dalga çubukları
    final barW = size.width * 0.026;
    final gap = size.width * 0.040;
    var x = c.dx + cR + size.width * 0.075;
    final bar = Paint()
      ..color = JuzzioColorTokens.onAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    for (final f in _bars) {
      final bh = h * 0.62 * f;
      canvas.drawLine(
          Offset(x, h / 2 - bh / 2), Offset(x, h / 2 + bh / 2), bar);
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _AudioStickerPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// L6 — Koyu cam panel
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthGlassPanel extends StatelessWidget {
  const JuzzioAuthGlassPanel(
      {super.key,
      required this.child,
      this.minHeight = 0,
      this.lowPower = false});
  final Widget child;
  final double minHeight;
  final bool lowPower;

  @override
  Widget build(BuildContext context) {
    const radius =
        BorderRadius.vertical(top: Radius.circular(JuzzioRadius.authGlassTop));
    final sigma = lowPower
        ? JuzzioGlassValues.lowPowerSigma
        : JuzzioGlassValues.panelSigma;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          foregroundDecoration: const _GlassRim(),
          decoration: const BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: JuzzioColorTokens.glassPanel,
              stops: JuzzioColorTokens.glassPanelStops,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Panelin üst kıvrımında ince beyaz/lime ışık; yanlara doğru söner (kalın yan hale yok).
class _GlassRim extends Decoration {
  const _GlassRim();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GlassRimPainter();
}

class _GlassRimPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null) return;
    const r = JuzzioRadius.authGlassTop;
    const inset = 0.75;
    final rect = offset & size;
    final l = rect.left + inset, t = rect.top + inset, rr = rect.right - inset;
    final fadeLen = math.min(size.height, r * 2.6);
    final path = Path()
      ..moveTo(l, t + fadeLen)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
      ..lineTo(rr - r, t)
      ..arcToPoint(Offset(rr, t + r), radius: const Radius.circular(r))
      ..lineTo(rr, t + fadeLen);
    // 1) lime kenar ışığı: köşelerde güçlü, aşağı doğru söner
    final lime = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          JuzzioColorTokens.accent.withValues(alpha: 0.70),
          JuzzioColorTokens.accent.withValues(alpha: 0.0)
        ],
      ).createShader(Rect.fromLTWH(rect.left, rect.top, rect.width, fadeLen));
    canvas.drawPath(path, lime);
    // 2) üst kenarda beyaz parıltı (ortada)
    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: JuzzioGlassValues.borderTopAlpha + 0.16),
        Colors.white.withValues(alpha: JuzzioGlassValues.borderTopAlpha + 0.16),
        Colors.white.withValues(alpha: 0.0),
      ], stops: const [
        0.08,
        0.3,
        0.7,
        0.92
      ]).createShader(Rect.fromLTWH(rect.left, rect.top, rect.width, r));
    canvas.drawLine(Offset(l + r, t), Offset(rr - r, t), sheen);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// L7 — Chip ve başlık
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthChip extends StatelessWidget {
  const JuzzioAuthChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
          color: JuzzioColorTokens.chipBackground,
          borderRadius: BorderRadius.circular(JuzzioRadius.pill)),
      child: Text(label,
          style: const TextStyle(
              fontFamily: JuzzioType.family,
              color: JuzzioColorTokens.chipForeground,
              fontWeight: FontWeight.w700,
              fontSize: JuzzioType.chip,
              height: 1.15)),
    );
  }
}

/// Büyük başlık; [mark] kelimesinin altında kısa lime el çizimi vurgu, isteğe bağlı sonda emoji görseli.
class JuzzioAuthTitle extends StatelessWidget {
  const JuzzioAuthTitle(
      {super.key,
      required this.prefix,
      required this.mark,
      this.trailingEmoji});
  final String prefix;
  final String mark;
  final String? trailingEmoji;

  static const TextStyle style = TextStyle(
    fontFamily: JuzzioType.family,
    color: Colors.white,
    fontSize: JuzzioType.heroTitle,
    fontWeight: FontWeight.w800,
    height: 1.12,
    letterSpacing: -0.8,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double w(String s) => (TextPainter(
            text: TextSpan(text: s, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler)
          ..layout())
        .width;
    final all = TextPainter(
        text: TextSpan(text: '$prefix$mark', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout();
    final emojiSize = scaler.scale(JuzzioType.heroTitle) * 1.25;
    final left = w(prefix);
    final markW = w(mark);
    final totalW = all.width + (trailingEmoji == null ? 0 : emojiSize + 6);
    return Semantics(
      header: true,
      label: '$prefix$mark',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: totalW,
            height: all.height + 10,
            child: Stack(clipBehavior: Clip.none, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$prefix$mark',
                    style: style, maxLines: 1, softWrap: false),
                if (trailingEmoji != null) ...[
                  const SizedBox(width: 6),
                  Image.asset(trailingEmoji!,
                      width: emojiSize,
                      height: emojiSize,
                      filterQuality: FilterQuality.high),
                ],
              ]),
              Positioned(
                left: left + markW * 0.08,
                top: all.height - 3,
                child: JuzzioTitleScribble(
                    width: markW * 0.86, color: JuzzioColorTokens.accent),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// L8 — Form bileşenleri
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthTextField extends StatefulWidget {
  const JuzzioAuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.hasError = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool hasError;
  final bool enabled;

  @override
  State<JuzzioAuthTextField> createState() => _JuzzioAuthTextFieldState();
}

class _JuzzioAuthTextFieldState extends State<JuzzioAuthTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final borderColor = widget.hasError
        ? JuzzioColorTokens.error
        : focused
            ? JuzzioColorTokens.accent
            : JuzzioColorTokens.borderDark;
    return AnimatedContainer(
      duration: JuzzioMotion.focus,
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: JuzzioSizes.authInputHeight),
      decoration: BoxDecoration(
        color: JuzzioColorTokens.input.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(JuzzioRadius.input),
        border: Border.all(
            color: borderColor, width: focused || widget.hasError ? 1.5 : 1.0),
        boxShadow: focused && !widget.hasError
            ? [
                BoxShadow(
                    color: JuzzioColorTokens.accent
                        .withValues(alpha: JuzzioGlassValues.focusGlowAlpha),
                    blurRadius: 12)
              ]
            : const [],
      ),
      child: Row(children: [
        const SizedBox(width: 20),
        Icon(widget.icon,
            size: JuzzioSizes.inputLeadingIcon, color: Colors.white),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            enabled: widget.enabled,
            obscureText: widget.obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            onSubmitted: widget.onSubmitted,
            cursorColor: JuzzioColorTokens.accent,
            style: const TextStyle(
                fontFamily: JuzzioType.family,
                color: Colors.white,
                fontSize: JuzzioType.field,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              hintText: widget.hint,
              hintStyle: const TextStyle(
                  fontFamily: JuzzioType.family,
                  color: JuzzioColorTokens.textSecondary,
                  fontSize: JuzzioType.field,
                  fontWeight: FontWeight.w400),
            ),
          ),
        ),
        if (widget.suffix != null)
          widget.suffix!
        else
          const SizedBox(width: 20),
      ]),
    );
  }
}

/// Şifre görünürlük düğmesi (48dp dokunma alanı)
class JuzzioPasswordEye extends StatelessWidget {
  const JuzzioPasswordEye(
      {super.key,
      required this.obscured,
      required this.onToggle,
      required this.showLabel,
      required this.hideLabel});
  final bool obscured;
  final VoidCallback onToggle;
  final String showLabel;
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        tooltip: obscured ? showLabel : hideLabel,
        onPressed: onToggle,
        constraints: const BoxConstraints(
            minWidth: JuzzioSizes.minTouch, minHeight: JuzzioSizes.minTouch),
        icon: Icon(
            obscured
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.white,
            size: 24),
      ),
    );
  }
}

class JuzzioAuthCheckbox extends StatelessWidget {
  const JuzzioAuthCheckbox(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(JuzzioRadius.sm),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: JuzzioSizes.minTouch),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: JuzzioMotion.focus,
              width: JuzzioSizes.checkbox,
              height: JuzzioSizes.checkbox,
              decoration: BoxDecoration(
                color: value ? JuzzioColorTokens.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(JuzzioRadius.checkbox),
                border: Border.all(color: JuzzioColorTokens.accent, width: 1.6),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 18, color: JuzzioColorTokens.onAccent)
                  : null,
            ),
            const SizedBox(width: 12),
            ExcludeSemantics(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: JuzzioType.family,
                      color: Colors.white,
                      fontSize: JuzzioType.secondaryAction,
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lime metin bağlantısı (tertiary varyant, ≥48dp dokunma alanı)
class JuzzioTextLink extends StatelessWidget {
  const JuzzioTextLink(
      {super.key,
      required this.label,
      required this.onTap,
      this.fontSize = JuzzioType.secondaryAction});
  final String label;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(JuzzioRadius.sm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: JuzzioSizes.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: TextStyle(
                      fontFamily: JuzzioType.family,
                      color: JuzzioColorTokens.accent,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary CTA (56dp, pill, lime) — ok + etiket grubu ortada; yükleniyorken yükseklik sabit.
class JuzzioPrimaryButton extends StatefulWidget {
  const JuzzioPrimaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  State<JuzzioPrimaryButton> createState() => _JuzzioPrimaryButtonState();
}

class _JuzzioPrimaryButtonState extends State<JuzzioPrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _down ? 0.985 : 1.0,
        duration: _down ? JuzzioMotion.pressDown : JuzzioMotion.pressUp,
        child: Material(
          color: enabled || widget.loading
              ? JuzzioColorTokens.accent
              : JuzzioColorTokens.accent.withValues(alpha: 0.55),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onPressed!();
                  }
                : null,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: JuzzioSizes.primaryHeight),
              child: Center(
                child: widget.loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: JuzzioColorTokens.onAccent))
                    : ExcludeSemantics(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.arrow_forward_rounded,
                                size: JuzzioSizes.ctaArrow,
                                color: JuzzioColorTokens.onAccent),
                            const SizedBox(width: 14),
                            Text(widget.label,
                                style: const TextStyle(
                                    fontFamily: JuzzioType.family,
                                    color: JuzzioColorTokens.onAccent,
                                    fontSize: JuzzioType.cta,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JuzzioOrDivider extends StatelessWidget {
  const JuzzioOrDivider({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
        child:
            Container(height: 1, color: Colors.white.withValues(alpha: 0.14)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(label,
              style: const TextStyle(
                  fontFamily: JuzzioType.family,
                  color: JuzzioColorTokens.dividerText,
                  fontSize: JuzzioType.divider)),
        ),
        line,
      ]),
    );
  }
}

/// Sosyal giriş dairesi (K6): etkin → gerçek OAuth; pasif → ikon %38, dokununca bilgi, giriş denenmez.
class JuzzioSocialButton extends StatelessWidget {
  const JuzzioSocialButton({
    super.key,
    required this.provider,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
  });

  /// 'google' | 'apple' | 'github'
  final String provider;
  final bool enabled;
  final VoidCallback? onTap;
  final String semanticLabel;

  static const double passiveOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (provider) {
      'google' => const JuzzioGoogleMark(size: JuzzioSizes.socialLogo),
      'apple' => const Icon(Icons.apple,
          size: JuzzioSizes.socialLogo + 3, color: Colors.white),
      _ => const JuzzioGithubMark(size: JuzzioSizes.socialLogo),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: JuzzioColorTokens.social,
        shape: CircleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.16))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: JuzzioSizes.iconCircleSocial,
            height: JuzzioSizes.iconCircleSocial,
            child: Center(
                child: ExcludeSemantics(
                    child: Opacity(
                        opacity: enabled ? 1 : passiveOpacity, child: mark))),
          ),
        ),
      ),
    );
  }
}

class JuzzioAuthFooter extends StatelessWidget {
  const JuzzioAuthFooter(
      {super.key,
      required this.question,
      required this.action,
      required this.onTap});
  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(question,
            style: const TextStyle(
                fontFamily: JuzzioType.family,
                color: JuzzioColorTokens.footerText,
                fontSize: JuzzioType.footer)),
        JuzzioTextLink(
            label: action, onTap: onTap, fontSize: JuzzioType.footer),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tam ekran düzeni: hero + panel; panel üst kenarı ekrana göre uyarlanır
// ─────────────────────────────────────────────────────────────────────────────
class JuzzioAuthLayout extends StatefulWidget {
  const JuzzioAuthLayout(
      {super.key,
      required this.panel,
      this.onBack,
      this.backLabel = 'Geri',
      this.reduceMotion = false});

  /// Panelin içeriği (chip, başlık, form …)
  final Widget panel;
  final VoidCallback? onBack;
  final String backLabel;
  final bool reduceMotion;

  /// Masaüstü/tablette kompozisyonun en geniş hali
  static const double maxCompositionWidth = 480;

  @override
  State<JuzzioAuthLayout> createState() => _JuzzioAuthLayoutState();
}

class _JuzzioAuthLayoutState extends State<JuzzioAuthLayout> {
  final GlobalKey _contentKey = GlobalKey();
  double? _contentH;

  void _measure() {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_contentH == null || (h - _contentH!).abs() > 0.5) {
      setState(() => _contentH = h);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final bottomInset = mq.padding.bottom;
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth, JuzzioAuthLayout.maxCompositionWidth);
      final h = box.maxHeight;
      final u = w / _Scene.width;
      final defaultTop = _Scene.panelTop * u;
      final minTop = _Scene.panelTopMin * u;
      final contentH = _contentH ?? (h - defaultTop);
      final panelTop = (h - contentH).clamp(minTop, defaultTop);
      final totalH = math.max(h, panelTop + contentH);

      final content = Padding(
        key: _contentKey,
        padding: EdgeInsets.fromLTRB(JuzzioSpace.screenInset, JuzzioSpace.s16,
            JuzzioSpace.screenInset, JuzzioSpace.s16 + bottomInset),
        child: widget.panel,
      );

      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(bottom: kb),
        child: SizedBox(
          height: totalH,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 0,
                width: w,
                child: JuzzioAuthHeroScene(
                    width: w,
                    onBack: widget.onBack,
                    backLabel: widget.backLabel,
                    panelTop: panelTop),
              ),
              // Panel her genişlikte ekranın tamamını kaplar (yanlarda lime şerit kalmaz); içerik 430dp'de ortalı
              Positioned(
                top: panelTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: JuzzioAuthGlassPanel(
                  lowPower: widget.reduceMotion,
                  // İçerik doğal yüksekliğinde ölçülür (ilk karede panelden uzun olsa bile hata vermez)
                  child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: content),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
