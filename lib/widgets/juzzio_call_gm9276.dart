// =============================================================================
// JUZZIO GM-9276 — Arama ekranları (referans görseller birebir)
//  design/references/gm9276_gelen_arama.png · gm9276_goruntulu_arama.png ·
//  gm9276_masaustu_arama_ses_aygitlari.png
//
//  KR-009: Tüm yüzeyler uygulamanın Liquid Glass bileşeni (JuzzioLiquidGlass) ve tema
//  belirteçleriyle (JuzzioGlassTokens / JuzzioCallColors) çizilir. Zemin etkin temanın aurora
//  sahnesidir (Grafit Limon: grafit derinlik + lime/mor ışıma). Arama ekranları her temada koyu
//  zemin kullanır; cam da bu yüzden temadan bağımsız koyu çizilir (forceDark).
// =============================================================================

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show MediaDevice;

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_aurora.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_desktop_audio.dart';
import 'juzzio_brand.dart';
import 'juzzio_call_kit21.dart';

bool get _reduceMotion => JuzzioAppController.instance.reduceMotion;

/// Masaüstü platformu mu (Windows / macOS / Linux)?
bool get juzzioCallIsDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Masaüstü arama düzeni (orta sahne + sağ "Ses aygıtları" paneli) için en küçük pencere genişliği.
const double kJuzzioDesktopCallMinWidth = 900;

/// Sağ "Ses aygıtları" panelinin genişliği.
const double kJuzzioDesktopAudioPanelWidth = 360;

/// Masaüstü arama düzeni kullanılmalı mı? (saf, test edilir)
bool juzzioUseDesktopCallLayout(
        {required bool desktop, required double width}) =>
    desktop && width >= kJuzzioDesktopCallMinWidth;

// -----------------------------------------------------------------------------
// Zemin ve cam
// -----------------------------------------------------------------------------

/// Arama zemini: etkin temanın aurora sahnesi (her zaman koyu).
class JuzzioCallStage extends StatelessWidget {
  const JuzzioCallStage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
            child: JuzzioAuroraBackground(
                palette: JuzzioAuroraScope.palette(), dark: true)),
        child,
      ],
    );
  }
}

/// Arama ekranlarının koyu Liquid Glass yüzeyi.
class JuzzioCallGlass extends StatelessWidget {
  const JuzzioCallGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.strong = false,
    this.glowBorder = false,
    this.blur = 22,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool strong;
  final bool glowBorder;
  final double blur;

  @override
  Widget build(BuildContext context) => JuzzioLiquidGlass(
        forceDark: true,
        radius: radius,
        padding: padding,
        strong: strong,
        glowBorder: glowBorder,
        blur: blur,
        child: child,
      );
}

// -----------------------------------------------------------------------------
// Başlık, avatar, haplar
// -----------------------------------------------------------------------------

/// "J Trawave · sesli arama"
class JuzzioCallTitleBrand extends StatelessWidget {
  const JuzzioCallTitleBrand({super.key, this.caption, this.size = 22});
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JuzzioWordmark(size: size, color: JuzzioCallColors.text),
        if (caption != null && caption!.isNotEmpty)
          Flexible(
            child: Text(
              '  ·  $caption',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: JuzzioCallColors.textDim,
                  fontSize: size * 0.8,
                  fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

/// Vurgu kenarlı avatar + iki ince eş merkezli halka (gelen ve sesli arama).
/// [pulse] çalarken halkalar yavaşça nefes alır; [speaking] konuşurken ışıma güçlenir.
class JuzzioRingedAvatar extends StatefulWidget {
  const JuzzioRingedAvatar({
    super.key,
    required this.avatar,
    required this.size,
    this.pulse = false,
    this.speaking = false,
  });

  final Widget avatar;
  final double size;
  final bool pulse;
  final bool speaking;

  /// Halkalarla birlikte kapladığı toplam çap.
  static double outerFor(double size) => size * 1.34;

  @override
  State<JuzzioRingedAvatar> createState() => _JuzzioRingedAvatarState();
}

class _JuzzioRingedAvatarState extends State<JuzzioRingedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.pulse && !_reduceMotion) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant JuzzioRingedAvatar old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_reduceMotion && !_c.isAnimating)
      _c.repeat(reverse: true);
    if (!widget.pulse && _c.isAnimating) _c.stop();
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
    final outer = JuzzioRingedAvatar.outerFor(s);
    return SizedBox(
      width: outer,
      height: outer,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = widget.pulse ? Curves.easeInOut.transform(_c.value) : 0.0;
          Widget ring(double d, double alpha) => Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: accent.withValues(alpha: alpha), width: 1.2),
                ),
              );
          return Stack(
            alignment: Alignment.center,
            children: [
              ring(outer * (0.97 + 0.03 * t), 0.14 + 0.06 * t),
              ring(s * 1.18 * (0.98 + 0.02 * t), 0.24 + 0.08 * t),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(
                          alpha: widget.speaking ? 0.42 : 0.22),
                      blurRadius: widget.speaking ? 34 : 24,
                    ),
                  ],
                ),
                child: ClipOval(
                    child: SizedBox.expand(
                        child: FittedBox(
                            fit: BoxFit.cover, child: widget.avatar))),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cam hap: "Canlı çeviri hazır" (vurgu) · "EN → TR"
class JuzzioCallPill extends StatelessWidget {
  const JuzzioCallPill(
      {super.key,
      required this.label,
      this.icon,
      this.accent = false,
      this.onTap});
  final String label;
  final IconData? icon;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = JuzzioCallColors.accent;
    final fg = accent ? a : JuzzioCallColors.text;
    Widget body = JuzzioCallGlass(
      radius: 999,
      glowBorder: accent,
      blur: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8)
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap != null) body = GestureDetector(onTap: onTap, child: body);
    return body;
  }
}

/// Cam daire + altında etiket (gelen arama: "Mesajla yanıtla" / "Sonra hatırlat")
class JuzzioCallRoundAction extends StatelessWidget {
  const JuzzioCallRoundAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.size = 54});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: JuzzioCallGlass(
                radius: 999,
                blur: 14,
                child: Center(
                    child: Icon(icon,
                        color: JuzzioCallColors.text, size: size * 0.44)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: JuzzioCallColors.textDim,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alt cam kontrol çubuğu (hap biçimli)
class JuzzioCallDock extends StatelessWidget {
  const JuzzioCallDock({super.key, required this.children, this.gap = 14});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return JuzzioCallGlass(
      radius: 999,
      strong: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            children[i]
          ],
        ],
      ),
    );
  }
}

/// Masaüstü çubuğundaki "🔊 Hoparlör (Realtek) ˅" hapı
class JuzzioCallOutputPill extends StatelessWidget {
  const JuzzioCallOutputPill(
      {super.key,
      required this.label,
      required this.onTap,
      this.icon = Icons.volume_up_rounded,
      this.open = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final a = JuzzioCallColors.accent;
    return Tooltip(
      message: JuzzioAppController.instance
          .trEn('Ses aygıtları', 'Audio devices', 'Audiogeräte'),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: a.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: a.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: a, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: a,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: a,
                  size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Canlı çeviri kartı
// -----------------------------------------------------------------------------

/// Çeviri kartındaki bir konuşma satırı
class JuzzioCallLine {
  const JuzzioCallLine(
      {required this.speaker,
      required this.original,
      required this.translated,
      this.live = false});
  final String speaker;
  final String original;
  final String translated;

  /// Konuşma sürüyor (henüz kesinleşmedi)
  final bool live;
}

/// "● Canlı çeviri  EN → TR" kartı: karşı tarafın orijinali (soluk) + çevirisi (kalın),
/// ayırıcı, sağa yaslı "Sen" + söylediğin (kalın) + karşıya giden çeviri (soluk).
class JuzzioLiveTranslationCard extends StatelessWidget {
  const JuzzioLiveTranslationCard({
    super.key,
    required this.pair,
    this.remote,
    this.mine,
    this.fontScale = 1.0,
    this.onTap,
    this.onLongPress,
    this.collapsed = false,
  });

  final String pair;
  final JuzzioCallLine? remote;
  final JuzzioCallLine? mine;
  final double fontScale;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final a = JuzzioCallColors.accent;
    final big = (19 * fontScale).clamp(15.0, 28.0);
    final small = (15.5 * fontScale).clamp(12.5, 22.0);
    final header = Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: a, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        // GM-014: dar ekranda / büyük yazıda taşmasın — başlık kısalır, dil çifti sabit kalır
        Expanded(
          child: Text(
            app.trEn('Canlı çeviri', 'Live translation', 'Live-Übersetzung'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: JuzzioCallColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          pair,
          style: const TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: JuzzioCallColors.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
    Widget content;
    if (collapsed) {
      final last = remote?.translated.isNotEmpty == true
          ? remote!.translated
          : (mine?.original ?? '');
      content = Row(children: [
        Expanded(child: header),
        if (last.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            flex: 2,
            child: Text(last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: JuzzioCallColors.text, fontSize: 14)),
          ),
        ],
      ]);
    } else {
      final r = remote;
      final m = mine;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 14),
          if (r == null && m == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                app.trEn('Konuşma bekleniyor…', 'Waiting for speech…',
                    'Warte auf Sprache…'),
                style:
                    TextStyle(color: JuzzioCallColors.textDim, fontSize: small),
              ),
            ),
          if (r != null) ...[
            Text(
              r.live
                  ? '${r.speaker} · ${app.trEn('konuşuyor', 'speaking', 'spricht')}'
                  : r.speaker,
              style: TextStyle(
                  color: JuzzioCallColors.text.withValues(alpha: 0.42),
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (r.original.isNotEmpty && r.original != r.translated)
              Text(r.original,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: JuzzioCallColors.textDim,
                      fontSize: small,
                      height: 1.3)),
            const SizedBox(height: 4),
            Text(
              r.translated.isNotEmpty ? r.translated : r.original,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: JuzzioCallColors.text,
                  fontSize: big,
                  fontWeight: FontWeight.w800,
                  height: 1.28),
            ),
          ],
          if (r != null && m != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                  height: 1, color: Colors.white.withValues(alpha: 0.10)),
            ),
          if (m != null) ...[
            Text(
              m.speaker,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: a,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              m.original.isNotEmpty ? m.original : m.translated,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: JuzzioCallColors.text,
                  fontSize: big,
                  fontWeight: FontWeight.w800,
                  height: 1.28),
            ),
            if (m.translated.isNotEmpty && m.translated != m.original) ...[
              const SizedBox(height: 4),
              Text(m.translated,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: JuzzioCallColors.textDim,
                      fontSize: small,
                      height: 1.3)),
            ],
          ],
        ],
      );
    }
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: JuzzioCallGlass(
        radius: collapsed ? 999 : 30,
        padding: collapsed
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
            : const EdgeInsets.fromLTRB(22, 18, 22, 20),
        child: content,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Ses aygıtları (masaüstü)
// -----------------------------------------------------------------------------

/// Ses aygıtının türü: ikon + kısa açıklama (ör. "Windows varsayılanı", "HDMI", "Sanal aygıt").
class JuzzioAudioDeviceInfo {
  const JuzzioAudioDeviceInfo(this.icon, this.subtitle);
  final IconData icon;
  final String subtitle;
}

/// Saf, test edilir. [t] üç dilli metin seçici (tr, en, de).
JuzzioAudioDeviceInfo juzzioAudioDeviceInfo({
  required String id,
  required String label,
  required bool output,
  required bool selected,
  required String Function(String tr, String en, String de) t,
  String platform = 'windows',
}) {
  final l = label.toLowerCase();
  bool has(List<String> keys) => keys.any(l.contains);
  final headset = has([
    'headset',
    'headphone',
    'kulaklık',
    'kulaklik',
    'airpods',
    'buds',
    'earphone'
  ]);
  final hdmi = has([
    'hdmi',
    'displayport',
    'nvidia high definition',
    'monitor',
    'monitör',
    'amd high definition'
  ]);
  final virtualDev = has([
    'fxsound',
    'virtual',
    'sanal',
    'voicemeeter',
    'vb-audio',
    'cable input',
    'cable output',
    'steam streaming',
    'broadcast'
  ]);
  final bluetooth = has(['bluetooth', 'hands-free', 'handsfree']);
  final builtin = has([
    'realtek',
    'built-in',
    'builtin',
    'dahili',
    'internal',
    'array',
    'dizisi',
    'macbook'
  ]);
  final isDefault =
      id == 'default' || l.startsWith('default') || l.startsWith('varsayılan');

  final IconData icon = output
      ? (headset ? Icons.headphones_rounded : Icons.volume_up_rounded)
      : Icons.mic_none_rounded;

  String sub;
  if (!output && selected) {
    sub = t('Seçili', 'Selected', 'Ausgewählt');
  } else if (isDefault) {
    sub = platform == 'macos'
        ? t('macOS varsayılanı', 'macOS default', 'macOS-Standard')
        : platform == 'windows'
            ? t('Windows varsayılanı', 'Windows default', 'Windows-Standard')
            : t('Sistem varsayılanı', 'System default', 'Systemstandard');
  } else if (virtualDev) {
    sub = t('Sanal aygıt', 'Virtual device', 'Virtuelles Gerät');
  } else if (hdmi) {
    sub = l.contains('displayport') ? 'DisplayPort' : 'HDMI';
  } else if (bluetooth) {
    sub = 'Bluetooth';
  } else if (headset) {
    sub = t('Bağlı', 'Connected', 'Verbunden');
  } else if (builtin) {
    sub = t('Dahili', 'Built-in', 'Integriert');
  } else {
    sub = output
        ? t('Ses çıkışı', 'Audio output', 'Audioausgabe')
        : t('Mikrofon', 'Microphone', 'Mikrofon');
  }
  return JuzzioAudioDeviceInfo(icon, sub);
}

/// "Hoparlör (Realtek(R) Audio)" → "Hoparlör (Realtek)" (saf, test edilir)
String juzzioShortDeviceName(String label) {
  var s = label.trim();
  if (s.toLowerCase().startsWith('default - ')) s = s.substring(10).trim();
  if (s.toLowerCase().startsWith('varsayılan - ')) s = s.substring(13).trim();
  final i = s.indexOf('(');
  if (i <= 0) return s;
  final head = s.substring(0, i).trim();
  final inner = s
      .substring(i + 1)
      .replaceAll(RegExp(r'\(R\)|\(TM\)|®|™', caseSensitive: false), '')
      .replaceAll(')', '')
      .trim();
  final first = inner
      .split(RegExp(r'\s+'))
      .firstWhere((w) => w.isNotEmpty, orElse: () => '');
  return first.isEmpty ? head : '$head ($first)';
}

String get _platformKey => kIsWeb
    ? 'web'
    : Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';

/// Ses çıkışı + mikrofon listesi (panel ve alt sayfada ortak). Liquid Glass satırlar,
/// seçili satır temanın vurgu kenarı + onay işaretiyle.
class JuzzioAudioDeviceList extends StatelessWidget {
  const JuzzioAudioDeviceList({super.key, required this.audio});
  final JuzzioDesktopAudio audio;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final a = JuzzioCallColors.accent;
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 12),
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: JuzzioCallColors.textDim,
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
    Widget row(MediaDevice d,
        {required bool output,
        required bool selected,
        required Future<void> Function() onTap}) {
      final info = juzzioAudioDeviceInfo(
        id: d.deviceId,
        label: d.label,
        output: output,
        selected: selected,
        t: app.trEn,
        platform: _platformKey,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: JuzzioCallGlass(
          radius: 20,
          glowBorder: selected,
          strong: selected,
          blur: 12,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Icon(info.icon,
                        color: selected ? a : JuzzioCallColors.textDim,
                        size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            d.label.isEmpty ? d.deviceId : d.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: JuzzioCallColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(info.subtitle,
                              style: TextStyle(
                                  color: JuzzioCallColors.text
                                      .withValues(alpha: 0.45),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, color: a, size: 24)
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (audio.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(audio.lastError!,
                style: const TextStyle(
                    color: JuzzioCallColors.danger,
                    fontSize: 12.5,
                    height: 1.3)),
          ),
        title(app.trEn('Ses çıkışı', 'Audio output', 'Audioausgabe')),
        if (audio.outputs.isEmpty)
          Text(
              app.trEn('Çıkış aygıtı bulunamadı.', 'No output device found.',
                  'Kein Ausgabegerät gefunden.'),
              style: const TextStyle(
                  color: JuzzioCallColors.textDim, fontSize: 13)),
        for (final d in audio.outputs)
          row(d,
              output: true,
              selected: audio.selectedOutput?.deviceId == d.deviceId,
              onTap: () => audio.selectOutput(d)),
        title(app.trEn('Mikrofon', 'Microphone', 'Mikrofon')),
        if (audio.inputs.isEmpty)
          Text(
              app.trEn('Mikrofon bulunamadı.', 'No microphone found.',
                  'Kein Mikrofon gefunden.'),
              style: const TextStyle(
                  color: JuzzioCallColors.textDim, fontSize: 13)),
        for (final d in audio.inputs)
          row(d,
              output: false,
              selected: audio.selectedInput?.deviceId == d.deviceId,
              onTap: () => audio.selectInput(d)),
      ],
    );
  }
}

/// Canlı seviye ölçer (ince dikey çubuklar). [level] 0..1.
class JuzzioLevelMeter extends StatelessWidget {
  const JuzzioLevelMeter(
      {super.key, required this.level, this.bars = 13, this.height = 26});
  final double level;
  final int bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final a = JuzzioCallColors.accent;
    final lv = level.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 4,
              height: math.max(
                  5.0,
                  height *
                      (0.22 +
                          0.78 * lv * (0.55 + 0.45 * math.sin(i * 1.7).abs()))),
              decoration: BoxDecoration(
                color: a.withValues(alpha: lv < 0.02 ? 0.35 : 1),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Masaüstü sağ paneli: "Ses aygıtları" — çıkış ve mikrofon listesi, altta çıkış seviyesi.
class JuzzioDesktopAudioPanel extends StatefulWidget {
  const JuzzioDesktopAudioPanel(
      {super.key, required this.outputLevel, this.onClose});

  /// Karşı tarafın anlık ses seviyesi (0..1)
  final ValueListenable<double> outputLevel;
  final VoidCallback? onClose;

  @override
  State<JuzzioDesktopAudioPanel> createState() =>
      _JuzzioDesktopAudioPanelState();
}

class _JuzzioDesktopAudioPanelState extends State<JuzzioDesktopAudioPanel> {
  final _audio = JuzzioDesktopAudio.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_audio.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return JuzzioLiquidGlass(
      forceDark: true,
      radius: 0,
      blur: 26,
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      app.trEn('Ses aygıtları', 'Audio devices', 'Audiogeräte'),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioCallColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: app.trEn('Aygıtları yenile', 'Refresh devices',
                        'Geräte aktualisieren'),
                    onPressed: () => _audio.refresh(),
                    icon: const Icon(Icons.settings_suggest_outlined,
                        color: JuzzioCallColors.textDim, size: 22),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: app.trEn(
                          'Paneli kapat', 'Close panel', 'Bereich schließen'),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded,
                          color: JuzzioCallColors.textDim, size: 22),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                app.trEn(
                  'Karşı tarafın sesi seçtiğin çıkıştan gelir. Seçimin sonraki aramalarda da kullanılır.',
                  'You hear the other person through the output you pick. Your choice is kept for future calls.',
                  'Du hörst die andere Person über die gewählte Ausgabe. Die Auswahl bleibt für weitere Anrufe.',
                ),
                style: const TextStyle(
                    color: JuzzioCallColors.textDim,
                    fontSize: 14.5,
                    height: 1.4),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _audio,
                  builder: (_, __) => SingleChildScrollView(
                      child: JuzzioAudioDeviceList(audio: _audio)),
                ),
              ),
              const SizedBox(height: 12),
              JuzzioCallGlass(
                radius: 999,
                blur: 10,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.trEn(
                            'Çıkış seviyesi', 'Output level', 'Ausgangspegel'),
                        style: const TextStyle(
                            color: JuzzioCallColors.textDim,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: widget.outputLevel,
                      builder: (_, v, __) => JuzzioLevelMeter(level: v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Gelen arama yardımcıları
// -----------------------------------------------------------------------------

/// "EN → TR" (karşı tarafın dili → benim dilim). Biri boşsa boş döner. (saf, test edilir)
String juzzioLangPairLabel(String? from, String? to) {
  final f = (from ?? '').trim();
  final t = (to ?? '').trim();
  if (f.isEmpty || t.isEmpty) return '';
  String code(String s) => s.split(RegExp('[-_]')).first.toUpperCase();
  return '${code(f)} → ${code(t)}';
}

/// "Mesajla yanıtla" hazır yanıtları (saf, test edilir)
List<String> juzzioQuickReplies(
        String Function(String tr, String en, String de) t) =>
    [
      t(
          'Şu an konuşamıyorum, sonra arayacağım.',
          "I can't talk right now, I'll call you later.",
          'Ich kann gerade nicht sprechen, ich rufe später an.'),
      t(
          'Toplantıdayım, mesaj yazabilir misin?',
          "I'm in a meeting, can you text me?",
          'Ich bin in einem Meeting, kannst du mir schreiben?'),
      t('Birazdan dönüyorum.', "I'll get back to you shortly.",
          'Ich melde mich gleich.'),
      t(
          'Yoldayım, müsait olunca ararım.',
          "I'm on my way, I'll call when I can.",
          'Ich bin unterwegs, ich rufe an, sobald ich kann.'),
    ];

/// Hazır yanıt seç (ya da kendin yaz). Seçilen metni döner; vazgeçilirse null.
Future<String?> showJuzzioQuickReplySheet(BuildContext context,
    {required String callerName}) {
  final app = JuzzioAppController.instance;
  final custom = TextEditingController();
  return showModalBottomSheet<String>(
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: JuzzioCallGlass(
                radius: 28,
                strong: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      app.trEn('$callerName için mesaj',
                          'Message to $callerName', 'Nachricht an $callerName'),
                      style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: JuzzioCallColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      app.trEn(
                          'Arama reddedilir, mesaj karşı tarafa kendi dilinde ulaşır.',
                          'The call is declined; the message reaches them in their language.',
                          'Der Anruf wird abgelehnt; die Nachricht kommt in ihrer Sprache an.'),
                      style: const TextStyle(
                          color: JuzzioCallColors.textDim,
                          fontSize: 12.5,
                          height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    for (final r in juzzioQuickReplies(app.trEn))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: JuzzioCallGlass(
                          radius: 18,
                          blur: 8,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.pop(ctx, r),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13),
                                child: Text(r,
                                    style: const TextStyle(
                                        color: JuzzioCallColors.text,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: custom,
                            maxLength: 500,
                            minLines: 1,
                            maxLines: 3,
                            style:
                                const TextStyle(color: JuzzioCallColors.text),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (v) {
                              if (v.trim().isNotEmpty)
                                Navigator.pop(ctx, v.trim());
                            },
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: app.trEn('Kendin yaz…',
                                  'Write your own…', 'Selbst schreiben…'),
                              hintStyle: const TextStyle(
                                  color: JuzzioCallColors.textDim),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.07),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        JuzzioCallCircleButton(
                          icon: Icons.send_rounded,
                          active: true,
                          size: 46,
                          tooltip: app.trEn('Gönder', 'Send', 'Senden'),
                          onTap: () {
                            if (custom.text.trim().isNotEmpty)
                              Navigator.pop(ctx, custom.text.trim());
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ).whenComplete(custom.dispose);
}

/// "Sonra hatırlat" süresi seç (dakika). Vazgeçilirse null.
Future<int?> showJuzzioRemindLaterSheet(BuildContext context) {
  final app = JuzzioAppController.instance;
  final options = <(int, String)>[
    (10, app.trEn('10 dakika sonra', 'In 10 minutes', 'In 10 Minuten')),
    (30, app.trEn('30 dakika sonra', 'In 30 minutes', 'In 30 Minuten')),
    (60, app.trEn('1 saat sonra', 'In 1 hour', 'In 1 Stunde')),
  ];
  return showModalBottomSheet<int>(
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: JuzzioCallGlass(
              radius: 28,
              strong: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    app.trEn(
                        'Ne zaman hatırlatayım?',
                        'When should I remind you?',
                        'Wann soll ich dich erinnern?'),
                    style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioCallColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: JuzzioCallGlass(
                        radius: 18,
                        blur: 8,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(ctx, o.$1),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13),
                              child: Row(children: [
                                const Icon(Icons.schedule_rounded,
                                    color: JuzzioCallColors.textDim, size: 20),
                                const SizedBox(width: 12),
                                Text(o.$2,
                                    style: const TextStyle(
                                        color: JuzzioCallColors.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
