// =============================================================================
// JUZZIO 2.1 — Arama arayüz kiti (yeni tasarım)
//  Sesli arama · Görüntülü arama · Gelen arama · Aramalar sekmesi ortak parçaları.
//  Tüm renkler etkin temadan gelir (JuzzioGlassTokens.space): vurgu = temanın parlak rengi
//  (varsayılan temada limon), zemin = temanın koyu derinlik gradyanı. Arama ekranları her temada
//  koyu zemin kullanır (görüntü ve okunurluk için); vurgu, halka ve dalgalar temaya uyar.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_audio_route.dart';
import 'juzzio_brand.dart';

/// Arama ekranlarının renkleri (temadan)
class JuzzioCallColors {
  JuzzioCallColors._();
  static Color get accent => JuzzioGlassTokens.glow;
  static Color get onAccent => JuzzioGlassTokens.onGlow;
  static List<Color> get depth => JuzzioGlassTokens.space.depth;
  static const Color danger = Color(0xFFFF3B47);
  static const Color text = Color(0xFFF5F6F8);
  static const Color textDim = Color(0xB3F5F6F8);
  static const Color glass = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0x29FFFFFF);

  static BoxDecoration backdrop() {
    final d = depth;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(d.first, Colors.black, 0.25)!,
          Color.lerp(d.length > 1 ? d[1] : d.first, Colors.black, 0.45)!,
          Color.lerp(d.last, Colors.black, 0.55)!,
        ],
      ),
    );
  }
}

bool get _reduceMotion => JuzzioAppController.instance.reduceMotion;

/// Ortadaki "J Juzzio" marka başlığı (koyu zemin üstünde)
class JuzzioCallBrand extends StatelessWidget {
  const JuzzioCallBrand({super.key, this.size = 20, this.caption});
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        JuzzioWordmark(size: size, color: JuzzioCallColors.text),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: JuzzioCallColors.accent,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

/// Cam yuvarlak düğme (üst çubuk ve kontrol rafı)
class JuzzioCallCircleButton extends StatelessWidget {
  const JuzzioCallCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.active = false,
    this.danger = false,
    this.ring = false,
    this.badge,
    this.iconSize,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  /// Vurgu dolgulu (ör. açık hoparlör / ekran paylaşımı)
  final bool active;
  final bool danger;
  /// Vurgu halkası (tasarım: etkin hoparlör)
  final bool ring;
  final Widget? badge;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final accent = JuzzioCallColors.accent;
    final fill = danger
        ? JuzzioCallColors.danger
        : active
            ? accent
            : JuzzioCallColors.glass;
    final fg = danger ? Colors.white : (active ? JuzzioCallColors.onAccent : JuzzioCallColors.text);
    Widget core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: ring ? accent : (danger || active ? Colors.transparent : JuzzioCallColors.glassBorder),
          width: ring ? 2 : 1,
        ),
        boxShadow: [
          if (danger) BoxShadow(color: JuzzioCallColors.danger.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6)),
          if (ring || active) BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
      child: Icon(icon, color: fg, size: iconSize ?? size * 0.46),
    );
    if (!danger && !active) {
      core = ClipOval(
        child: BackdropFilter(
          enabled: !JuzzioGlassTokens.reducedEffects,
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: core,
        ),
      );
    }
    Widget btn = Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: badge == null
            ? core
            : Stack(clipBehavior: Clip.none, children: [core, Positioned(right: -2, top: -2, child: badge!)]),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

/// Doğrulanmış rozeti (tema vurgusu)
class JuzzioCallVerified extends StatelessWidget {
  const JuzzioCallVerified({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified_rounded, size: size, color: JuzzioCallColors.accent);
}

/// İsim + (doğrulanmış) rozeti
class JuzzioCallName extends StatelessWidget {
  const JuzzioCallName({super.key, required this.name, this.verified = false, this.size = 24});
  final String name;
  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: JuzzioCallColors.text,
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (verified) ...[const SizedBox(width: 6), JuzzioCallVerified(size: size * 0.78)],
      ],
    );
  }
}

/// Parlayan halkalı avatar: vurgu halkası, isteğe bağlı eş merkezli ışık halkaları, çevrimiçi
/// noktası ve köşe rozeti (ör. ses dalgası / J logosu).
class JuzzioCallGlowAvatar extends StatefulWidget {
  const JuzzioCallGlowAvatar({
    super.key,
    required this.avatar,
    required this.size,
    this.online = false,
    this.badge,
    this.rings = 0,
    this.pulse = false,
    this.speaking = false,
  });

  /// İçteki yuvarlak avatar (boyutu [size] olmalı)
  final Widget avatar;
  final double size;
  final bool online;
  final Widget? badge;
  /// Dıştaki eş merkezli ışık halkası sayısı (gelen arama tasarımı: 3)
  final int rings;
  final bool pulse;
  final bool speaking;

  @override
  State<JuzzioCallGlowAvatar> createState() => _JuzzioCallGlowAvatarState();
}

class _JuzzioCallGlowAvatarState extends State<JuzzioCallGlowAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if ((widget.pulse || widget.rings > 0) && !_reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = JuzzioCallColors.accent;
    final s = widget.size;
    final ringGap = s * 0.16;
    final outer = s + (widget.rings * ringGap * 2) + 16;
    return SizedBox(
      width: outer,
      height: outer,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (var i = widget.rings; i >= 1; i--)
                Container(
                  width: s + i * ringGap * 2 + (math.sin((t + i * 0.18) * math.pi * 2) * 3),
                  height: s + i * ringGap * 2 + (math.sin((t + i * 0.18) * math.pi * 2) * 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.035 * (widget.rings - i + 1)),
                    border: Border.all(color: accent.withValues(alpha: 0.10 + 0.08 * (widget.rings - i)), width: 1),
                  ),
                ),
              // Ana parlak halka
              Container(
                width: s + 10,
                height: s + 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: widget.speaking ? 3.4 : 2.6),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35 + (widget.pulse ? 0.20 * math.sin(t * math.pi * 2).abs() : 0)),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              SizedBox(width: s, height: s, child: ClipOval(child: widget.avatar)),
              if (widget.online)
                Positioned(
                  right: (outer - s) / 2 + s * 0.06,
                  bottom: (outer - s) / 2 + s * 0.06,
                  child: Container(
                    width: math.max(12, s * 0.13),
                    height: math.max(12, s * 0.13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D27B),
                      shape: BoxShape.circle,
                      border: Border.all(color: JuzzioCallColors.depth.last, width: 2.5),
                    ),
                  ),
                ),
              if (widget.badge != null)
                Positioned(
                  right: (outer - s) / 2 - 2,
                  bottom: (outer - s) / 2 - 2,
                  child: widget.badge!,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Köşe rozeti: vurgu dolgulu daire içinde simge veya J logosu
class JuzzioCallBadge extends StatelessWidget {
  const JuzzioCallBadge({super.key, this.icon, this.logo = false, this.size = 34});
  final IconData? icon;
  final bool logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: logo ? JuzzioBrandColors.ink : JuzzioCallColors.accent,
        border: Border.all(color: logo ? JuzzioCallColors.accent : JuzzioCallColors.depth.last, width: 2.4),
        boxShadow: [BoxShadow(color: JuzzioCallColors.accent.withValues(alpha: 0.4), blurRadius: 12)],
      ),
      alignment: Alignment.center,
      child: logo
          ? JuzzioLogoGlyph(size: size * 0.56)
          : Icon(icon ?? Icons.graphic_eq_rounded, size: size * 0.55, color: JuzzioCallColors.onAccent),
    );
  }
}

/// Hareketli ses dalgası çubukları
class JuzzioCallWaveBars extends StatefulWidget {
  const JuzzioCallWaveBars({super.key, this.bars = 9, this.height = 22, this.active = true, this.color, this.barWidth = 3});
  final int bars;
  final double height;
  final bool active;
  final Color? color;
  final double barWidth;

  @override
  State<JuzzioCallWaveBars> createState() => _JuzzioCallWaveBarsState();
}

class _JuzzioCallWaveBarsState extends State<JuzzioCallWaveBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.active && !_reduceMotion) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant JuzzioCallWaveBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_reduceMotion && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? JuzzioCallColors.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.bars, (i) {
          final mid = (widget.bars - 1) / 2;
          final shape = 1 - ((i - mid).abs() / (mid + 1)) * 0.55;
          final phase = math.sin((_c.value * 2 * math.pi) + i * 0.9);
          final h = widget.active ? widget.height * shape * (0.45 + 0.55 * phase.abs()) : widget.height * 0.22;
          return Container(
            margin: EdgeInsets.symmetric(horizontal: widget.barWidth * 0.45),
            width: widget.barWidth,
            height: math.max(3, h),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.55 + 0.45 * shape), borderRadius: BorderRadius.circular(9)),
          );
        }),
      ),
    );
  }
}

/// Alt kısımdaki parçacık dalgası (sesli arama tasarımı)
class JuzzioCallParticleWave extends StatefulWidget {
  const JuzzioCallParticleWave({super.key, this.height = 120});
  final double height;

  @override
  State<JuzzioCallParticleWave> createState() => _JuzzioCallParticleWaveState();
}

class _JuzzioCallParticleWaveState extends State<JuzzioCallParticleWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (!_reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(painter: _ParticleWavePainter(_c.value, JuzzioCallColors.accent)),
          ),
        ),
      ),
    );
  }
}

class _ParticleWavePainter extends CustomPainter {
  _ParticleWavePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const rows = 7;
    final cols = (size.width / 7).floor();
    for (var r = 0; r < rows; r++) {
      final rowT = r / (rows - 1);
      for (var c = 0; c < cols; c++) {
        final x = c / cols * size.width;
        final wave = math.sin((x / size.width * 2.4 * math.pi) + t * 2 * math.pi + r * 0.35) * (size.height * 0.18) +
            math.sin((x / size.width * 5.1 * math.pi) - t * 2 * math.pi) * (size.height * 0.05);
        final y = size.height * (0.30 + rowT * 0.55) + wave * (1 - rowT * 0.4);
        final edge = math.sin(c / cols * math.pi); // kenarlarda söner
        final a = (0.12 + 0.55 * (1 - rowT)) * edge;
        paint.color = color.withValues(alpha: a.clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), 1.1 + (1 - rowT) * 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleWavePainter old) => old.t != t || old.color != color;
}

/// Sesli arama kare düğmesi (Sessize Al / Hoparlör). [onArrow] verilirse sağda ses çıkışı oku çıkar.
class JuzzioCallSquareButton extends StatelessWidget {
  const JuzzioCallSquareButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.onArrow,
    this.arrowTooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onArrow;
  final String? arrowTooltip;

  @override
  Widget build(BuildContext context) {
    final accent = JuzzioCallColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              toggled: active,
              label: label,
              child: GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: active ? accent.withValues(alpha: 0.16) : JuzzioCallColors.glass,
                    border: Border.all(color: active ? accent : JuzzioCallColors.glassBorder, width: active ? 1.8 : 1),
                    boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 18)] : const [],
                  ),
                  child: Icon(icon, size: 30, color: active ? accent : JuzzioCallColors.text),
                ),
              ),
            ),
            if (onArrow != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: arrowTooltip ?? '',
                child: GestureDetector(
                  onTap: onArrow,
                  child: Container(
                    width: 30,
                    height: 74,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: JuzzioCallColors.glass,
                      border: Border.all(color: JuzzioCallColors.glassBorder),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: JuzzioCallColors.text),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: JuzzioCallColors.text),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: active ? accent : JuzzioCallColors.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Süre hapı (sesli aramada iki yanında dalga)
class JuzzioCallTimerPill extends StatelessWidget {
  const JuzzioCallTimerPill({super.key, required this.text, this.leading});
  final String text;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: JuzzioCallColors.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JuzzioCallColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 15, color: JuzzioCallColors.accent),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: JuzzioCallColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _routeLabel(JuzzioAudioOutput o, String? btName) {
  final app = JuzzioAppController.instance;
  return switch (o) {
    JuzzioAudioOutput.earpiece => app.trEn('Telefon (ahize)', 'Phone (earpiece)', 'Telefon (Hörmuschel)'),
    JuzzioAudioOutput.speaker => app.trEn('Hoparlör', 'Speaker', 'Lautsprecher'),
    JuzzioAudioOutput.wired => app.trEn('Kablolu kulaklık', 'Wired headset', 'Kabel-Headset'),
    JuzzioAudioOutput.bluetooth =>
      (btName != null && btName.trim().isNotEmpty) ? btName.trim() : app.trEn('Bluetooth kulaklık', 'Bluetooth headset', 'Bluetooth-Headset'),
  };
}

IconData juzzioAudioOutputIcon(JuzzioAudioOutput o) => switch (o) {
      JuzzioAudioOutput.earpiece => Icons.phone_in_talk_rounded,
      JuzzioAudioOutput.speaker => Icons.volume_up_rounded,
      JuzzioAudioOutput.wired => Icons.headset_rounded,
      JuzzioAudioOutput.bluetooth => Icons.bluetooth_audio_rounded,
    };

/// Ses çıkışı seçici (ahize / hoparlör / kablolu / Bluetooth)
Future<void> showJuzzioAudioOutputSheet(
  BuildContext context, {
  required Future<void> Function(JuzzioAudioOutput) onSelect,
}) async {
  final app = JuzzioAppController.instance;
  final route = JuzzioAudioRouteController.instance;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ListenableBuilder(
      listenable: route,
      builder: (ctx, _) {
        final order = [
          JuzzioAudioOutput.earpiece,
          JuzzioAudioOutput.speaker,
          JuzzioAudioOutput.wired,
          JuzzioAudioOutput.bluetooth,
        ].where(route.available.contains).toList();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Color.lerp(JuzzioCallColors.depth.last, Colors.black, 0.35),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: JuzzioCallColors.glassBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: JuzzioCallColors.glassBorder, borderRadius: BorderRadius.circular(9)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  app.trEn('Ses çıkışı', 'Audio output', 'Audioausgabe'),
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioCallColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  app.trEn(
                    'Kulaklık takılınca ses otomatik ona geçer; çıkarınca ahizeye döner.',
                    'Audio moves to your headset when plugged in and back to the earpiece when removed.',
                    'Beim Einstecken wechselt der Ton zum Headset, beim Entfernen zurück zur Hörmuschel.',
                  ),
                  style: const TextStyle(color: JuzzioCallColors.textDim, fontSize: 12.5, height: 1.3),
                ),
                const SizedBox(height: 12),
                for (final o in order)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: route.current == o ? JuzzioCallColors.accent.withValues(alpha: 0.14) : JuzzioCallColors.glass,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: route.current == o ? JuzzioCallColors.accent : JuzzioCallColors.glassBorder),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await onSelect(o);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              Icon(juzzioAudioOutputIcon(o), color: route.current == o ? JuzzioCallColors.accent : JuzzioCallColors.text),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _routeLabel(o, route.bluetoothName),
                                  style: const TextStyle(
                                    fontFamily: JuzzioConfig.fontRegularBold,
                                    color: JuzzioCallColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (route.current == o) Icon(Icons.check_circle_rounded, color: JuzzioCallColors.accent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Yuvarlak vurgulu eylem düğmesi + altında etiket (gelen arama: Reddet / Kabul Et)
class JuzzioCallActionButton extends StatelessWidget {
  const JuzzioCallActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accept = false,
    this.size = 74,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accept;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = accept ? JuzzioCallColors.accent : JuzzioCallColors.danger;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 26, spreadRadius: 1)],
              ),
              child: Icon(icon, size: size * 0.42, color: accept ? JuzzioCallColors.onAccent : Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: JuzzioCallColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// v2.1 — Tam ekran gelen arama (tasarım 4)
class JuzzioIncomingCallView extends StatelessWidget {
  const JuzzioIncomingCallView({
    super.key,
    required this.callerName,
    required this.avatarUrl,
    required this.isVideo,
    required this.onAccept,
    required this.onDecline,
    this.isGroup = false,
    this.groupTitle,
    this.verified = false,
    this.participants = const [],
  });

  final String callerName;
  final String? avatarUrl;
  final bool isVideo;
  final bool isGroup;
  final String? groupTitle;
  final bool verified;
  final List<String> participants;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final size = MediaQuery.sizeOf(context);
    final avatarSize = math.min(size.width * 0.42, 172.0);
    final title = isGroup && (groupTitle ?? '').trim().isNotEmpty ? groupTitle!.trim() : callerName;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: JuzzioCallColors.backdrop(),
        child: Stack(
          children: [
            // Üstte ve altta hafif vurgu ışığı
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.85,
                      colors: [JuzzioCallColors.accent.withValues(alpha: 0.10), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  JuzzioCallBrand(
                    size: 22,
                    caption: app.trEn('CANLI ÇEVİRİ • GÖRÜNTÜLÜ • SESLİ', 'LIVE TRANSLATION • VIDEO • VOICE', 'LIVE-ÜBERSETZUNG • VIDEO • SPRACHE'),
                  ),
                  const Spacer(flex: 2),
                  JuzzioCallGlowAvatar(
                    size: avatarSize,
                    rings: 3,
                    pulse: true,
                    badge: const JuzzioCallBadge(logo: true, size: 40),
                    avatar: isGroup
                        ? Container(
                            color: JuzzioCallColors.glass,
                            child: Icon(Icons.groups_rounded, color: JuzzioCallColors.text, size: avatarSize * 0.45),
                          )
                        : JuzzioGlassAvatar(imageUrl: avatarUrl, name: callerName, radius: avatarSize / 2),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: JuzzioCallName(name: title, verified: verified && !isGroup, size: 28),
                  ),
                  if (isGroup) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        participants.isEmpty ? callerName : participants.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: JuzzioCallColors.textDim, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    app.trEn('Gelen Arama...', 'Incoming call...', 'Eingehender Anruf...'),
                    style: const TextStyle(color: JuzzioCallColors.textDim, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: JuzzioCallColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: JuzzioCallColors.accent.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, size: 18, color: JuzzioCallColors.accent),
                        const SizedBox(width: 8),
                        Text(
                          isGroup
                              ? (isVideo
                                  ? app.trEn('Görüntülü Konferans', 'Video Conference', 'Videokonferenz')
                                  : app.trEn('Sesli Konferans', 'Voice Conference', 'Sprachkonferenz'))
                              : (isVideo
                                  ? app.trEn('Görüntülü Arama', 'Video Call', 'Videoanruf')
                                  : app.trEn('Sesli Arama', 'Voice Call', 'Sprachanruf')),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: JuzzioCallColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const JuzzioCallWaveBars(bars: 21, height: 30),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        JuzzioCallActionButton(
                          icon: Icons.call_end_rounded,
                          label: app.trEn('Reddet', 'Decline', 'Ablehnen'),
                          onTap: onDecline,
                        ),
                        JuzzioCallActionButton(
                          icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          label: app.trEn('Kabul Et', 'Accept', 'Annehmen'),
                          onTap: onAccept,
                          accept: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "12 dk 34 sn" / "1 sa 05 dk" / "45 sn" (Aramalar sekmesi; saf, test edilir)
String juzzioCallDurationLong(int seconds, {String? lang}) {
  final l = lang ?? JuzzioAppController.instance.uiLang;
  final tr = l == 'tr';
  final de = l == 'de';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final hu = tr ? 'sa' : (de ? 'Std.' : 'h');
  final mu = tr ? 'dk' : (de ? 'Min.' : 'min');
  final su = tr ? 'sn' : (de ? 'Sek.' : 's');
  if (h > 0) return '$h $hu ${m.toString().padLeft(2, '0')} $mu';
  if (m > 0) return '$m $mu ${s.toString().padLeft(2, '0')} $su';
  return '$s $su';
}

/// "Bugün 09:17" / "Dün 21:04" / "18.11 14:30" (saf, test edilir)
String juzzioCallWhenLabel(DateTime when, {DateTime? now, String? lang}) {
  final l = lang ?? JuzzioAppController.instance.uiLang;
  final n = (now ?? DateTime.now()).toLocal();
  final d = when.toLocal();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '${l == 'tr' ? 'Bugün' : (l == 'de' ? 'Heute' : 'Today')} $hm';
  if (diff == 1) return '${l == 'tr' ? 'Dün' : (l == 'de' ? 'Gestern' : 'Yesterday')} $hm';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} $hm';
}
