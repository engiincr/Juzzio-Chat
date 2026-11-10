// =============================================================================
// JUZZIO v1.2.0 — Doğum günü kutlaması
//  "Happy Birthday", "Doğum günün kutlu olsun", "İyi ki doğdun" … içeren bir mesaj
//  geldiğinde/gönderildiğinde TOPLAM 4 SANİYE süren bir kutlama oynar:
//   • ekranın solundan ve sağından orantılı, ışık-gölgeli (3B görünümlü) iki el
//     konfeti patlatıcısıyla (party popper) içeri girer ve patlatır;
//   • iki patlatıcıdan renkli konfeti + kıvrımlı serpantin saçılır;
//   • 🌸🎂😍⚡🥳💖❤️ emojileri aşağıdan yumuşakça yükselir ve yumuşakça kaybolur;
//   • mesaj balonunun çevresinde elektrik dalgası dolaşır.
//  Her mesaj için bir kez (yeni mesaj = son 8 sn) oynar; "Hareketi azalt" açıkken oynamaz.
//  Tüm çizim vektördür (CustomPainter) — görsel dosyası yok.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import 'juzzio_motion_core.dart';

/// Toplam kutlama süresi (kullanıcı isteği: 4 sn)
const Duration kJuzzioBirthdayDuration = Duration(seconds: 4);

/// Yükselen emojiler (kullanıcı isteğiyle aynı sıra)
const List<String> kJuzzioBirthdayEmojis = <String>['🌸', '🎂', '😍', '⚡', '🥳', '💖', '❤️'];

const List<String> _kBirthdayPhrases = <String>[
  'happy birthday', 'happy bday', 'happy b-day', 'hbd', 'happy birth day',
  'doğum günün kutlu', 'doğum gününü kutlu', 'doğum günün mutlu', 'doğumgünün kutlu', 'nice mutlu yıllara',
  'iyi ki doğdun', 'iyiki doğdun', 'iyi ki varsın doğum', 'mutlu yıllar',
  'dogum gunun kutlu', 'dogum gununu kutlu', 'iyi ki dogdun', 'iyiki dogdun',
  'alles gute zum geburtstag', 'happy geburtstag', 'feliz cumpleaños', 'feliz cumpleanos', 'joyeux anniversaire',
  'buon compleanno', 'с днём рождения', 'с днем рождения', '🎂',
];

/// Mesaj bir doğum günü kutlaması mı? (saf; test edilir)
bool juzzioIsBirthdayMessage(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return false;
  final tr = raw.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final plain = raw.replaceAll('İ', 'i').toLowerCase();
  for (final k in _kBirthdayPhrases) {
    if (k == 'hbd') {
      final re = RegExp(r'(^|[^a-z])hbd([^a-z]|$)');
      if (re.hasMatch(plain)) return true;
      continue;
    }
    if (tr.contains(k) || plain.contains(k)) return true;
  }
  return false;
}

/// Balonu saran elektrik dalgası + (ilk oynatmada) tam ekran kutlama katmanı
class JuzzioBirthdayFx extends StatefulWidget {
  const JuzzioBirthdayFx({
    super.key,
    required this.playKey,
    required this.createdAt,
    required this.child,
    this.radius = 20,
  });

  /// Mesaj kimliği (yerel → sunucu kaydında tekrar oynamaz)
  final String playKey;
  final DateTime createdAt;
  final Widget child;
  final double radius;

  static final Set<String> _played = <String>{};

  static bool shouldPlay(String key, DateTime createdAt, DateTime now) {
    if (_played.contains(key)) return false;
    return now.difference(createdAt).inSeconds.abs() <= 8;
  }

  @override
  State<JuzzioBirthdayFx> createState() => _JuzzioBirthdayFxState();
}

class _JuzzioBirthdayFxState extends State<JuzzioBirthdayFx> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  OverlayEntry? _overlay;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final play = !JuzzioAppController.instance.reduceMotion &&
        !JuzzioGlassTokens.reducedEffects &&
        JuzzioBirthdayFx.shouldPlay(widget.playKey, widget.createdAt, DateTime.now());
    JuzzioBirthdayFx._played.add(widget.playKey);
    if (JuzzioBirthdayFx._played.length > 400) JuzzioBirthdayFx._played.remove(JuzzioBirthdayFx._played.first);
    if (!play) return;
    final c = AnimationController(vsync: this, duration: kJuzzioBirthdayDuration);
    _c = c;
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _removeOverlay();
        if (mounted) setState(() => _done = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) {
        _overlay = OverlayEntry(builder: (_) => Positioned.fill(child: IgnorePointer(child: JuzzioBirthdayStage(progress: c))));
        overlay.insert(_overlay!);
      }
      JuzzioHaptics.success();
      c.forward();
    });
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    // ağaç yapısı kutlama bitince de aynı kalır (balonun alt durumları sıfırlanmaz)
    return CustomPaint(
      foregroundPainter: _done ? null : _ElectricBorderPainter(progress: c, radius: widget.radius, color: JuzzioGlassTokens.glow),
      child: widget.child,
    );
  }
}

// -----------------------------------------------------------------------------
// Elektrik dalgası: balon kenarında titreşen şimşek + dolaşan iki parlak dalga başı
// -----------------------------------------------------------------------------
class _ElectricBorderPainter extends CustomPainter {
  _ElectricBorderPainter({required this.progress, required this.radius, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final fadeIn = (t / 0.06).clamp(0.0, 1.0);
    final fadeOut = (1 - (t - 0.86) / 0.14).clamp(0.0, 1.0);
    final alpha = fadeIn * fadeOut;
    if (alpha <= 0.01) return;
    final rect = (Offset.zero & size).inflate(4);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius + 4)));
    final metric = path.computeMetrics().first;
    final len = metric.length;
    // titreşen şimşek çizgisi (her ~70 ms yeni desen)
    final frame = (t * 4000 / 70).floor();
    final rnd = math.Random(frame * 7919 + size.width.round());
    final bolt = Path();
    const step = 9.0;
    var first = true;
    for (double d = 0; d <= len; d += step) {
      final tan = metric.getTangentForOffset(d);
      if (tan == null) continue;
      final n = Offset(-tan.vector.dy, tan.vector.dx);
      final jitter = (rnd.nextDouble() - 0.5) * 6;
      final p = tan.position + n * jitter;
      if (first) {
        bolt.moveTo(p.dx, p.dy);
        first = false;
      } else {
        bolt.lineTo(p.dx, p.dy);
      }
    }
    bolt.close();
    final hue = HSLColor.fromColor(color);
    const cyan = Color(0xFF7DF9FF);
    final violet = hue.withHue((hue.hue + 40) % 360).withLightness(0.65).toColor();
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = violet.withValues(alpha: 0.35 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = cyan.withValues(alpha: 0.85 * alpha),
    );
    // dolaşan dalga başları (karşılıklı iki parlak ışık)
    for (final phase in const [0.0, 0.5]) {
      final head = ((t * 1.6 + phase) % 1.0) * len;
      const tail = 70.0;
      for (var i = 0; i < 10; i++) {
        final d = (head - i * tail / 10) % len;
        final tan = metric.getTangentForOffset(d < 0 ? d + len : d);
        if (tan == null) continue;
        final k = 1 - i / 10;
        canvas.drawCircle(
          tan.position,
          4.5 * k + 1,
          Paint()
            ..color = Color.lerp(Colors.white, cyan, i / 10)!.withValues(alpha: alpha * k)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * k),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ElectricBorderPainter old) => old.radius != radius || old.color != color;
}

// -----------------------------------------------------------------------------
// Tam ekran sahne: eller + patlatıcılar + konfeti + yükselen emojiler
// -----------------------------------------------------------------------------
class JuzzioBirthdayStage extends StatefulWidget {
  const JuzzioBirthdayStage({super.key, required this.progress});
  final Animation<double> progress;

  @override
  State<JuzzioBirthdayStage> createState() => _JuzzioBirthdayStageState();
}

class _Bit {
  _Bit({
    required this.left,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.color,
    required this.w,
    required this.h,
    required this.streamer,
    required this.delay,
  });
  final bool left;
  final double vx, vy, spin, w, h, delay;
  final Color color;
  final bool streamer;
}

class _Riser {
  _Riser({required this.emoji, required this.x, required this.start, required this.dur, required this.size, required this.sway});
  final String emoji;
  final double x, start, dur, size, sway;
}

class _JuzzioBirthdayStageState extends State<JuzzioBirthdayStage> {
  final List<_Bit> _bits = <_Bit>[];
  final List<_Riser> _risers = <_Riser>[];
  final Map<String, TextPainter> _emojiCache = <String, TextPainter>{};

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    const colors = <Color>[
      Color(0xFFFF4D8D), Color(0xFFFFD23F), Color(0xFF3EC1F3), Color(0xFF8C6CFF),
      Color(0xFF4BE39A), Color(0xFFFF8A3D), Color(0xFFFFFFFF),
    ];
    for (final left in const [true, false]) {
      for (var i = 0; i < 46; i++) {
        // patlatıcı ağzından merkeze ve yukarı doğru yelpaze
        final a = -math.pi / 2 + (left ? 0.55 : -0.55) + (rnd.nextDouble() - 0.5) * 1.05;
        final sp = 520 + rnd.nextDouble() * 560;
        _bits.add(_Bit(
          left: left,
          vx: math.cos(a) * sp,
          vy: math.sin(a) * sp,
          spin: (rnd.nextDouble() - 0.5) * 14,
          color: colors[rnd.nextInt(colors.length)],
          w: 5 + rnd.nextDouble() * 5,
          h: 8 + rnd.nextDouble() * 7,
          streamer: i % 6 == 0,
          delay: rnd.nextDouble() * 0.08,
        ));
      }
    }
    for (var i = 0; i < 16; i++) {
      _risers.add(_Riser(
        emoji: kJuzzioBirthdayEmojis[i % kJuzzioBirthdayEmojis.length],
        x: 0.08 + rnd.nextDouble() * 0.84,
        start: 0.10 + rnd.nextDouble() * 0.40,
        dur: 0.45 + rnd.nextDouble() * 0.15,
        size: 26 + rnd.nextDouble() * 18,
        sway: 10 + rnd.nextDouble() * 18,
      ));
    }
  }

  @override
  void dispose() {
    for (final tp in _emojiCache.values) {
      tp.dispose();
    }
    super.dispose();
  }

  TextPainter _emoji(String e, double size) {
    final key = '$e@${size.round()}';
    return _emojiCache.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(text: e, style: juzzioEmojiStyle(size.roundToDouble())),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _BirthdayStagePainter(
          progress: widget.progress,
          bits: _bits,
          risers: _risers,
          emoji: _emoji,
        ),
      ),
    );
  }
}

class _BirthdayStagePainter extends CustomPainter {
  _BirthdayStagePainter({required this.progress, required this.bits, required this.risers, required this.emoji}) : super(repaint: progress);

  final Animation<double> progress;
  final List<_Bit> bits;
  final List<_Riser> risers;
  final TextPainter Function(String e, double size) emoji;

  static const double _total = 4.0; // sn
  static const double _popAt = 0.75; // sn — patlama anı

  @override
  void paint(Canvas canvas, Size size) {
    final sec = progress.value * _total;
    final w = size.width;
    final h = size.height;
    final scale = (w / 390).clamp(0.75, 1.35);

    // ---- yükselen emojiler (arka katman) ----
    for (final r in risers) {
      final local = (progress.value - r.start) / r.dur;
      if (local <= 0 || local >= 1) continue;
      final ease = Curves.easeOutCubic.transform(local);
      final y = h * (1.04 - 0.78 * ease);
      final x = w * r.x + math.sin(local * math.pi * 2.2) * r.sway;
      final a = local < 0.18 ? local / 0.18 : (local > 0.7 ? (1 - local) / 0.3 : 1.0);
      final tp = emoji(r.emoji, r.size * scale);
      canvas.saveLayer(Rect.fromLTWH(x - tp.width, y - tp.height, tp.width * 2, tp.height * 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, a.clamp(0.0, 1.0)));
      canvas.translate(x - tp.width / 2, y - tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // ---- eller: giriş (0–0.6 sn), patlamada geri tepme, çıkış (3.2–3.9 sn) ----
    final handY = h * 0.66;
    final inK = const JuzzioSpringCurve(damping: 7, frequency: 2.2).transform((sec / 0.6).clamp(0.0, 1.0));
    final outK = Curves.easeInCubic.transform(((sec - 3.2) / 0.7).clamp(0.0, 1.0));
    final recoil = sec > _popAt ? math.exp(-(sec - _popAt) * 9) * math.sin((sec - _popAt) * 30) * 10 : 0.0;
    final reach = 118 * scale;
    final mouths = <Offset>[];
    for (final left in const [true, false]) {
      final dir = left ? 1.0 : -1.0;
      final hiddenX = left ? -reach * 1.6 : w + reach * 1.6;
      final shownX = left ? reach * 0.62 : w - reach * 0.62;
      final x = hiddenX + (shownX - hiddenX) * inK - (shownX - hiddenX) * outK - dir * recoil;
      final base = Offset(x, handY);
      // patlatıcı merkeze ve yukarı bakar
      final angle = left ? -0.62 : math.pi + 0.62;
      mouths.add(_drawPopperHand(canvas, base, angle, scale, left: left, popped: sec > _popAt));
    }

    // ---- patlama parlaması ----
    if (sec > _popAt && sec < _popAt + 0.35) {
      final k = (sec - _popAt) / 0.35;
      for (final m in mouths) {
        canvas.drawCircle(
          m,
          16 + 50 * k,
          Paint()
            ..color = const Color(0xFFFFF3B0).withValues(alpha: 0.55 * (1 - k))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
    }

    // ---- konfeti + serpantin ----
    if (sec > _popAt) {
      final fadeAll = (1 - (sec - 3.3) / 0.7).clamp(0.0, 1.0);
      for (final b in bits) {
        final tt = sec - _popAt - b.delay;
        if (tt <= 0) continue;
        final m = mouths[b.left ? 0 : 1];
        // sürtünmeli atış: x = v(1-e^{-kt})/k, y + yerçekimi
        const drag = 2.1;
        final f = (1 - math.exp(-drag * tt)) / drag;
        final px = m.dx + b.vx * f * scale;
        final py = m.dy + b.vy * f * scale + 0.5 * 620 * tt * tt * 0.55;
        if (py > h + 40) continue;
        final paint = Paint()..color = b.color.withValues(alpha: fadeAll);
        canvas.save();
        canvas.translate(px, py);
        if (b.streamer) {
          final sp = Path()..moveTo(0, 0);
          for (var i = 1; i <= 6; i++) {
            sp.lineTo(math.sin(tt * 9 + i) * 5, -i * 5.0);
          }
          canvas.drawPath(
            sp,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round
              ..color = b.color.withValues(alpha: fadeAll),
          );
        } else {
          canvas.rotate(b.spin * tt);
          // 3B dönme hissi: genişlik kosinüsle daralıp genişler
          final flip = math.cos(tt * (6 + b.spin.abs())).abs() * 0.85 + 0.15;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.w * flip, height: b.h), const Radius.circular(1.6)),
            paint,
          );
        }
        canvas.restore();
      }
    }
  }

  /// Bir el + patlatıcı çizer, patlatıcının ağzını (ekran koordinatı) döndürür.
  Offset _drawPopperHand(Canvas canvas, Offset base, double angle, double k, {required bool left, required bool popped}) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    canvas.scale(k);
    if (!left) canvas.scale(1, -1); // sağ el: ayna (başparmak yine üstte)

    // ---- patlatıcı koni (el kavrar, ağız +x yönünde) ----
    const coneBack = Offset(-6, 0);
    const coneLen = 96.0;
    final cone = Path()
      ..moveTo(coneBack.dx, coneBack.dy - 9)
      ..lineTo(coneBack.dx + coneLen, -27)
      ..quadraticBezierTo(coneBack.dx + coneLen + 7, 0, coneBack.dx + coneLen, 27)
      ..lineTo(coneBack.dx, 9)
      ..close();
    final coneRect = Rect.fromLTRB(-6, -27, coneLen + 2, 27);
    canvas.drawPath(
      cone,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF9FD0), Color(0xFFE0367E), Color(0xFF8E1F57)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(coneRect),
    );
    // çapraz şeritler
    canvas.save();
    canvas.clipPath(cone);
    final stripe = Paint()
      ..color = const Color(0xFFFFE066)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final x = 8.0 + i * 17;
      canvas.drawLine(Offset(x, -32), Offset(x + 14, 32), stripe);
    }
    // parlak kenar (3B)
    canvas.drawPath(
      Path()
        ..moveTo(0, -8)
        ..lineTo(coneLen - 6, -23),
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    // altın ağız halkası
    final rim = Rect.fromCenter(center: const Offset(coneLen - 2.5, 0), width: 13, height: 56);
    canvas.drawOval(rim, Paint()..color = const Color(0xFFB8860B));
    canvas.drawOval(rim.deflate(2.2), Paint()..color = popped ? const Color(0xFF3A1430) : const Color(0xFFFFD45C));

    // ---- el (yumruk) ----
    const skin = Color(0xFFF6C3A5);
    const shade = Color(0xFFD98F6E);
    const light = Color(0xFFFFE3D2);
    // bilek / kol
    final arm = RRect.fromRectAndRadius(const Rect.fromLTWH(-150, -19, 128, 38), const Radius.circular(19));
    canvas.drawRRect(
      arm,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light, skin, shade])
            .createShader(arm.outerRect),
    );
    // avuç
    final palm = RRect.fromRectAndRadius(const Rect.fromLTWH(-38, -28, 50, 58), const Radius.circular(22));
    canvas.drawShadow(Path()..addRRect(palm), const Color(0xFF000000), 6, false);
    canvas.drawRRect(
      palm,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-0.4, -0.5), radius: 1.1, colors: [light, skin, shade], stops: [0.0, 0.55, 1.0])
            .createShader(palm.outerRect),
    );
    // koniyi saran dört parmak (alt taraf, boğumlu)
    for (var i = 0; i < 4; i++) {
      final c = Offset(-24 + i * 12.5, 26 + (i == 0 || i == 3 ? -2 : 0));
      final r = Rect.fromCenter(center: c, width: 14, height: 19);
      canvas.drawOval(
        r,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-0.3, -0.6), colors: [light, skin, shade], stops: [0.0, 0.5, 1.0])
              .createShader(r),
      );
      canvas.drawArc(r.deflate(1), 0.3, 2.4, false,
          Paint()
            ..color = shade.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    // başparmak (üstte, koninin üzerinden)
    final thumb = RRect.fromRectAndRadius(const Rect.fromLTWH(-20, -36, 40, 16), const Radius.circular(8));
    canvas.drawRRect(
      thumb,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light, skin, shade])
            .createShader(thumb.outerRect),
    );
    canvas.drawOval(
      Rect.fromLTWH(10, -34, 8, 6),
      Paint()..color = const Color(0xFFFFF1EA),
    );
    canvas.restore();

    // ağzın ekran koordinatı
    final mouthLocal = Offset((coneLen - 2.5) * k, 0);
    return base + Offset(math.cos(angle) * mouthLocal.dx, math.sin(angle) * mouthLocal.dx);
  }

  @override
  bool shouldRepaint(covariant _BirthdayStagePainter old) => false;
}

/// Kutlama yalnız [enabled] iken bağlanır (diğer balonlarda ek widget yok)
class JuzzioBirthdayFxGate extends StatelessWidget {
  const JuzzioBirthdayFxGate({super.key, required this.enabled, required this.playKey, required this.createdAt, required this.child});
  final bool enabled;
  final String playKey;
  final DateTime createdAt;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      enabled ? JuzzioBirthdayFx(playKey: playKey, createdAt: createdAt, child: child) : child;
}
