// =============================================================================
// JUZZIO 2.1 — Arama arayüz kiti (yeni tasarım)
//  Sesli arama · Görüntülü arama · Gelen arama · Aramalar sekmesi ortak parçaları.
//  Tüm renkler etkin temadan gelir (JuzzioGlassTokens.space): vurgu = temanın parlak rengi
//  (varsayılan temada limon), zemin = temanın koyu derinlik gradyanı. Arama ekranları her temada
//  koyu zemin kullanır (görüntü ve okunurluk için); vurgu, halka ve dalgalar temaya uyar.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_audio_route.dart';
import '../services/juzzio_desktop_audio.dart';
import 'juzzio_brand.dart';
import 'juzzio_call_gm9276.dart';

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

/// Ortadaki "J Trawave" marka başlığı (koyu zemin üstünde)
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
  // GM-003: masaüstünde gerçek ses aygıtları (hoparlör/kulaklık/mikrofon) listelenir
  if (JuzzioDesktopAudio.instance.supported) return showJuzzioDesktopAudioSheet(context);
  final app = JuzzioAppController.instance;
  final route = JuzzioAudioRouteController.instance;
  await showModalBottomSheet<void>(
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
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
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: JuzzioCallColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// GM-9276 — Tam ekran gelen arama (design/references/gm9276_gelen_arama.png):
/// "J Trawave · sesli arama", eş merkezli halkalı vurgu kenarlı avatar, ad, "seni arıyor…",
/// "Canlı çeviri hazır" + "EN → TR" cam hapları, "Mesajla yanıtla" / "Sonra hatırlat",
/// kırmızı Reddet / vurgu Yanıtla. Zemin temanın aurora sahnesi, yüzeyler Liquid Glass (KR-009).
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
    this.fromLang,
    this.toLang,
    this.translationReady = true,
    this.onMessageReply,
    this.onRemindLater,
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
  /// Arayanın dili ve benim dilim ("EN → TR")
  final String? fromLang;
  final String? toLang;
  /// Canlı çeviri özelliği açık mı?
  final bool translationReady;
  final VoidCallback? onMessageReply;
  final VoidCallback? onRemindLater;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 700;
    final avatarSize = math.min(math.min(size.width * 0.40, 160.0), compact ? 108.0 : 160.0);
    final title = isGroup && (groupTitle ?? '').trim().isNotEmpty ? groupTitle!.trim() : callerName;
    final caption = isGroup
        ? app.trEn('grup araması', 'group call', 'Gruppenanruf')
        : (isVideo ? app.trEn('görüntülü arama', 'video call', 'Videoanruf') : app.trEn('sesli arama', 'voice call', 'Sprachanruf'));
    final pair = juzzioLangPairLabel(fromLang, toLang);
    final status = isGroup
        ? (participants.isEmpty ? callerName : participants.join(', '))
        : app.trEn('seni arıyor…', 'is calling you…', 'ruft dich an…');
    return Material(
      color: Colors.transparent,
      child: JuzzioCallStage(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              // GM-014: çok kısa ekranda (≤ 640) taşma yerine kaydırılabilir; normalde boşluklar Spacer ile dağılır
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                children: [
                  SizedBox(height: compact ? 12 : 40),
                  JuzzioCallTitleBrand(caption: caption, size: 22),
                  const Spacer(flex: 2),
                  JuzzioRingedAvatar(
                    size: avatarSize,
                    pulse: true,
                    avatar: isGroup
                        ? Container(
                            width: avatarSize,
                            height: avatarSize,
                            color: JuzzioCallColors.glass,
                            child: Icon(Icons.groups_rounded, color: JuzzioCallColors.text, size: avatarSize * 0.45),
                          )
                        : JuzzioGlassAvatar(imageUrl: avatarUrl, name: callerName, radius: avatarSize / 2, ringWidth: 0),
                  ),
                  SizedBox(height: compact ? 14 : 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: JuzzioCallName(name: title, verified: verified && !isGroup, size: compact ? 28 : 34),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: JuzzioCallColors.textDim, fontSize: 17, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (translationReady || pair.isNotEmpty) ...[
                    SizedBox(height: compact ? 14 : 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (translationReady)
                          JuzzioCallPill(
                            icon: Icons.translate_rounded,
                            label: app.trEn('Canlı çeviri hazır', 'Live translation ready', 'Live-Übersetzung bereit'),
                            accent: true,
                          ),
                        if (pair.isNotEmpty) JuzzioCallPill(label: pair),
                      ],
                    ),
                  ],
                  const Spacer(flex: 3),
                  if (onMessageReply != null || onRemindLater != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (onMessageReply != null)
                          SizedBox(
                            width: 170,
                            child: JuzzioCallRoundAction(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: app.trEn('Mesajla yanıtla', 'Reply with message', 'Mit Nachricht antworten'),
                              onTap: onMessageReply!,
                            ),
                          ),
                        if (onRemindLater != null)
                          SizedBox(
                            width: 170,
                            child: JuzzioCallRoundAction(
                              icon: Icons.schedule_rounded,
                              label: app.trEn('Sonra hatırlat', 'Remind me later', 'Später erinnern'),
                              onTap: onRemindLater!,
                            ),
                          ),
                      ],
                    ),
                  SizedBox(height: compact ? 20 : 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        JuzzioCallActionButton(
                          icon: Icons.call_end_rounded,
                          label: app.trEn('Reddet', 'Decline', 'Ablehnen'),
                          onTap: onDecline,
                          size: 76,
                        ),
                        JuzzioCallActionButton(
                          icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          label: app.trEn('Yanıtla', 'Answer', 'Annehmen'),
                          onTap: onAccept,
                          accept: true,
                          size: 76,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 36),
                ],
                      ),
                    ),
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


/// GM-003 — Masaüstü ses aygıtı seçici: çıkış (hoparlör/kulaklık) ve mikrofon.
/// Seçim cihazda saklanır, sonraki aramalarda da uygulanır.
Future<void> showJuzzioDesktopAudioSheet(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final audio = JuzzioDesktopAudio.instance;
  unawaited(audio.refresh());
  await showModalBottomSheet<void>(
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: audio,
      builder: (ctx, _) {
        final accent = JuzzioGlassTokens.glow;
        Widget title(String t) => Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
              child: Text(t.toUpperCase(),
                  style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: JuzzioGlassTokens.textMuted,
                      fontSize: 12,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700)),
            );
        // GM-006: satırlar uygulamanın Liquid Glass bileşeniyle; seçili satır temanın vurgu kenarıyla
        Widget row(MediaDeviceLike d, bool selected, IconData icon, Future<void> Function() onTap) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JuzzioLiquidGlass(
                radius: 18,
                glowBorder: selected,
                strong: selected,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(icon, color: selected ? accent : JuzzioGlassTokens.textSecondary, size: 21),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(d.label.isEmpty ? d.id : d.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: JuzzioConfig.fontRegularBold,
                                    color: JuzzioGlassTokens.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (selected) Icon(Icons.check_circle_rounded, color: accent, size: 21),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.82, maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: JuzzioLiquidGlass(
                  radius: 28,
                  strong: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(color: JuzzioGlassTokens.borderStrong, borderRadius: BorderRadius.circular(9)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(app.trEn('Ses aygıtları', 'Audio devices', 'Audiogeräte'),
                            style: TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: JuzzioGlassTokens.heading,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          app.trEn(
                            'Karşı tarafın sesi seçtiğin çıkıştan gelir. Seçimin sonraki aramalarda da kullanılır.',
                            'You hear the other person through the output you pick. Your choice is kept for future calls.',
                            'Du hörst die andere Person über die gewählte Ausgabe. Die Auswahl bleibt für weitere Anrufe.',
                          ),
                          style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5, height: 1.35),
                        ),
                        if (audio.lastError != null) ...[
                          const SizedBox(height: 8),
                          Text(audio.lastError!, style: const TextStyle(color: JuzzioCallColors.danger, fontSize: 12.5, height: 1.3)),
                        ],
                        const SizedBox(height: 6),
                        title(app.trEn('Ses çıkışı', 'Output', 'Ausgabe')),
                        if (audio.outputs.isEmpty)
                          Text(app.trEn('Çıkış aygıtı bulunamadı.', 'No output device found.', 'Kein Ausgabegerät gefunden.'),
                              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13)),
                        for (final d in audio.outputs)
                          row(MediaDeviceLike(d.deviceId, d.label), audio.selectedOutput?.deviceId == d.deviceId,
                              Icons.volume_up_rounded, () => audio.selectOutput(d)),
                        title(app.trEn('Mikrofon', 'Microphone', 'Mikrofon')),
                        for (final d in audio.inputs)
                          row(MediaDeviceLike(d.deviceId, d.label), audio.selectedInput?.deviceId == d.deviceId, Icons.mic_rounded,
                              () => audio.selectInput(d)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Sayfa içi kullanım için aygıt kimliği + adı (livekit MediaDevice'a bağımlılığı arayüzde sınırlar)
class MediaDeviceLike {
  const MediaDeviceLike(this.id, this.label);
  final String id;
  final String label;
}


/// GM-007 — Masaüstü ekran paylaşımı kaynak seçici (ekranlar + pencereler, önizlemeli).
/// Seçilen kaynağın kimliğini döner; vazgeçilirse null. Liquid Glass (KR-009).
Future<String?> showJuzzioScreenSourcePicker(
  BuildContext context,
  Future<List<webrtc.DesktopCapturerSource>> Function() load,
) {
  final app = JuzzioAppController.instance;
  final future = load();
  return showModalBottomSheet<String>(
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final accent = JuzzioGlassTokens.glow;
      Widget tile(webrtc.DesktopCapturerSource src) => JuzzioLiquidGlass(
            radius: 18,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(ctx).pop(src.id),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.35),
                            child: src.thumbnail != null && src.thumbnail!.isNotEmpty
                                ? Image.memory(src.thumbnail!, fit: BoxFit.contain, gaplessPlayback: true)
                                : Icon(src.type == webrtc.SourceType.Screen ? Icons.desktop_windows_rounded : Icons.web_asset_rounded,
                                    color: JuzzioGlassTokens.textMuted, size: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(src.name.isEmpty ? app.trEn('Ekran', 'Screen', 'Bildschirm') : src.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: JuzzioGlassTokens.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          );
      Widget section(String t, List<webrtc.DesktopCapturerSource> list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8, left: 4),
                child: Text(t.toUpperCase(),
                    style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioGlassTokens.textMuted,
                        fontSize: 12,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700)),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.32,
                children: [for (final s in list) tile(s)],
              ),
            ],
          );
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.86, maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: JuzzioLiquidGlass(
                radius: 28,
                strong: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: FutureBuilder<List<webrtc.DesktopCapturerSource>>(
                  future: future,
                  builder: (ctx, snap) {
                    final header = <Widget>[
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: JuzzioGlassTokens.borderStrong, borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Icon(Icons.screen_share_rounded, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(app.trEn('Neyi paylaşmak istiyorsun?', 'What do you want to share?', 'Was möchtest du teilen?'),
                              style: TextStyle(
                                  fontFamily: JuzzioConfig.fontRegularBold,
                                  color: JuzzioGlassTokens.heading,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ];
                    if (snap.connectionState != ConnectionState.done) {
                      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ...header,
                        const SizedBox(height: 28),
                        Center(child: CircularProgressIndicator(color: accent)),
                        const SizedBox(height: 28),
                      ]);
                    }
                    final all = snap.data ?? const <webrtc.DesktopCapturerSource>[];
                    final screens = all.where((x) => x.type == webrtc.SourceType.Screen).toList();
                    final windows = all.where((x) => x.type == webrtc.SourceType.Window).toList();
                    return SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ...header,
                        if (snap.hasError || all.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              app.trEn('Paylaşılabilecek ekran bulunamadı.', 'No screen available to share.', 'Kein Bildschirm zum Teilen gefunden.'),
                              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13.5),
                            ),
                          ),
                        if (screens.isNotEmpty) section(app.trEn('Ekranlar', 'Screens', 'Bildschirme'), screens),
                        if (windows.isNotEmpty) section(app.trEn('Pencereler', 'Windows', 'Fenster'), windows),
                      ]),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
