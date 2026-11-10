// =============================================================================
// JUZZIO v1.2.0 — Doğum günü kutlaması
//  "Happy Birthday", "Doğum günün kutlu olsun", "İyi ki doğdun" … içeren bir mesaj
//  geldiğinde/gönderildiğinde TOPLAM 7 SANİYE süren bir kutlama oynar (v1.2.7: 4 → 7 sn):
//   • ekranın solundan ve sağından orantılı, ışık-gölgeli (3B görünümlü) iki el
//     konfeti patlatıcısıyla (party popper) içeri girer ve patlatır;
//   • iki patlatıcıdan renkli konfeti + kıvrımlı serpantin saçılır;
//   • 🌸🎂😍⚡🥳💖❤️ emojileri aşağıdan yumuşakça yükselir ve yumuşakça kaybolur;
//   • mesaj balonunun çevresinde elektrik dalgası dolaşır.
//  Her mesaj için bir kez (yeni mesaj = son 8 sn) oynar; "Hareketi azalt" açıkken oynamaz.
//  v1.2.7 — 3 BOYUTLU sahne (kullanıcı: "kenardan çıkan efektler çok yapmacık ve vektörel"):
//   • eller ve patlatıcılar gerçek PERSPEKTİF dönüşümüyle (Matrix4, derinlik) çizilir; içeri
//     girerken yana dönüp öne eğilir, patlamada geri teper; koni silindirik ışıkla, ağız
//     derinlikli iç gölge ve metalik halkayla gölgelenir, kolların altında yumuşak temas gölgesi;
//   • konfeti parçaları 3B uzayda üç eksende döner, ön/arka yüzü ışığa göre aydınlanıp kararır;
//     serpantinler bükülen kurdele gibi daralıp genişler; parlak 3B küreler ve yıldızlar eklenir;
//   • iki patlama (1.0 sn ve 3.2 sn), konfeti yavaşça süzülür, sahne 7 sn sürer.
//  Tüm çizim kodla yapılır (CustomPainter) — görsel dosyası yok, APK büyümez.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import 'juzzio_motion_core.dart';

/// Toplam kutlama süresi (v1.2.7 kullanıcı isteği: daha uzun → 7 sn)
const Duration kJuzzioBirthdayDuration = Duration(seconds: 7);

/// Patlama anları (sn): ilk patlama + ikinci (daha büyük) patlama
const List<double> kJuzzioBirthdayPops = <double>[1.0, 3.2];

/// 3B bir konfeti yaprağının ışığa göre parlaklığı (0.35..1). [rx]/[ry] radyan.
/// Yüzey normali kameraya döndükçe aydınlanır, yan döndükçe kararır (saf; test edilir).
double juzzioConfettiShade(double rx, double ry) {
  final n = (math.cos(rx) * math.cos(ry)).abs();
  return 0.35 + 0.65 * n;
}

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
    final frame = (t * kJuzzioBirthdayDuration.inMilliseconds / 70).floor();
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

enum _BitKind { leaf, streamer, orb, star }

class _Bit {
  _Bit({
    required this.left,
    required this.burst,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.rx,
    required this.ry,
    required this.rz,
    required this.wx,
    required this.wy,
    required this.wz,
    required this.color,
    required this.w,
    required this.h,
    required this.kind,
    required this.delay,
  });
  final bool left;
  final int burst; // 0: ilk patlama, 1: ikinci patlama
  final double vx, vy, vz; // başlangıç hızı (px/sn); z: derinlik
  final double rx, ry, rz; // başlangıç açıları
  final double wx, wy, wz; // açısal hızlar (rad/sn)
  final double w, h, delay;
  final Color color;
  final _BitKind kind;
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
      Color(0xFF4BE39A), Color(0xFFFF8A3D), Color(0xFFFFFFFF), Color(0xFFFFC2E2),
    ];
    for (var burst = 0; burst < kJuzzioBirthdayPops.length; burst++) {
      final n = burst == 0 ? 44 : 58;
      for (final left in const [true, false]) {
        for (var i = 0; i < n; i++) {
          // patlatıcı ağzından merkeze ve yukarı doğru 3B koni şeklinde yelpaze
          final a = -math.pi / 2 + (left ? 0.55 : -0.55) + (rnd.nextDouble() - 0.5) * 1.1;
          final sp = 480 + rnd.nextDouble() * 620;
          final roll = rnd.nextDouble();
          final kind = i % 7 == 0
              ? _BitKind.streamer
              : roll < 0.09
                  ? _BitKind.orb
                  : roll < 0.16
                      ? _BitKind.star
                      : _BitKind.leaf;
          _bits.add(_Bit(
            left: left,
            burst: burst,
            vx: math.cos(a) * sp,
            vy: math.sin(a) * sp,
            vz: (rnd.nextDouble() - 0.35) * 520,
            rx: rnd.nextDouble() * math.pi * 2,
            ry: rnd.nextDouble() * math.pi * 2,
            rz: rnd.nextDouble() * math.pi * 2,
            wx: (rnd.nextDouble() - 0.5) * 16,
            wy: (rnd.nextDouble() - 0.5) * 14,
            wz: (rnd.nextDouble() - 0.5) * 8,
            color: colors[rnd.nextInt(colors.length)],
            w: 6 + rnd.nextDouble() * 6,
            h: 10 + rnd.nextDouble() * 8,
            kind: kind,
            delay: rnd.nextDouble() * 0.10,
          ));
        }
      }
    }
    for (var i = 0; i < 22; i++) {
      _risers.add(_Riser(
        emoji: kJuzzioBirthdayEmojis[i % kJuzzioBirthdayEmojis.length],
        x: 0.08 + rnd.nextDouble() * 0.84,
        start: 0.08 + rnd.nextDouble() * 0.56,
        dur: 0.26 + rnd.nextDouble() * 0.10,
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

  static final double _total = kJuzzioBirthdayDuration.inMilliseconds / 1000.0; // 7 sn
  static const double _handsOutAt = 5.7; // sn — eller çekilmeye başlar
  static const double _focal = 900; // perspektif odak uzaklığı (px)

  /// Perspektif matrisi (Matrix4; derinlik etkisi setEntry(3,2)).
  static Matrix4 _persp() => Matrix4.identity()..setEntry(3, 2, 1 / _focal);

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

    // ---- eller: giriş (0–0.8 sn), her patlamada geri tepme, çıkış (5.7–6.5 sn) ----
    final handY = h * 0.66;
    final inK = const JuzzioSpringCurve(damping: 7, frequency: 2.0).transform((sec / 0.8).clamp(0.0, 1.0));
    final outK = Curves.easeInCubic.transform(((sec - _handsOutAt) / 0.8).clamp(0.0, 1.0));
    var recoil = 0.0;
    for (final at in kJuzzioBirthdayPops) {
      if (sec > at) recoil += math.exp(-(sec - at) * 8) * math.sin((sec - at) * 28) * 12;
    }
    final reach = 118 * scale;
    final mouths = <Offset>[];
    final popped = sec > kJuzzioBirthdayPops.first;
    for (final left in const [true, false]) {
      final dir = left ? 1.0 : -1.0;
      final hiddenX = left ? -reach * 1.7 : w + reach * 1.7;
      final shownX = left ? reach * 0.62 : w - reach * 0.62;
      final x = hiddenX + (shownX - hiddenX) * inK - (shownX - hiddenX) * outK - dir * recoil;
      final base = Offset(x, handY + math.sin(sec * 2.4 + (left ? 0 : 1.3)) * 4 * scale);
      // patlatıcı merkeze ve yukarı bakar; 3B: içeri girerken yandan öne döner, hafif salınır
      final angle = left ? -0.62 : math.pi + 0.62;
      final yaw = (1 - inK) * 0.9 + 0.38 + math.sin(sec * 1.7) * 0.06;
      final pitch = -0.18 + math.sin(sec * 2.1 + (left ? 0 : 0.8)) * 0.05 - recoil * 0.004;
      mouths.add(_drawPopperHand3D(canvas, base, angle, scale, left: left, popped: popped, yaw: yaw, pitch: pitch));
    }

    // ---- patlama parlaması (her patlamada) ----
    for (final at in kJuzzioBirthdayPops) {
      if (sec > at && sec < at + 0.4) {
        final k = (sec - at) / 0.4;
        for (final m in mouths) {
          canvas.drawCircle(
            m,
            18 + 64 * k,
            Paint()
              ..shader = RadialGradient(colors: [
                const Color(0xFFFFFFFF).withValues(alpha: 0.75 * (1 - k)),
                const Color(0xFFFFE27A).withValues(alpha: 0.45 * (1 - k)),
                const Color(0x00FFB347),
              ], stops: const [0.0, 0.35, 1.0])
                  .createShader(Rect.fromCircle(center: m, radius: 18 + 64 * k)),
          );
        }
      }
    }

    // ---- 3B konfeti, kurdele, küre, yıldız ----
    final fadeAll = (1 - (sec - (_total - 0.9)) / 0.9).clamp(0.0, 1.0);
    if (fadeAll <= 0) return;
    for (final b in bits) {
      final at = kJuzzioBirthdayPops[b.burst];
      final tt = sec - at - b.delay;
      if (tt <= 0) continue;
      final m = mouths[b.left ? 0 : 1];
      // hava sürtünmeli atış + yerçekimi; konfeti düşerken salınır (yaprak süzülmesi)
      const drag = 2.2;
      final f = (1 - math.exp(-drag * tt)) / drag;
      final flutter = math.sin(tt * 4.2 + b.rx) * 26 * math.min(1.0, tt);
      final px = m.dx + (b.vx * f + flutter) * scale;
      final py = m.dy + b.vy * f * scale + 0.5 * 360 * tt * tt * 0.55 * (b.kind == _BitKind.orb ? 1.4 : 1.0);
      final pz = b.vz * f; // + uzaklaşır, − yaklaşır
      if (py > h + 60) continue;
      final depthK = (_focal / (_focal + pz)).clamp(0.55, 1.6); // yakın parça büyük, uzak küçük
      canvas.save();
      canvas.translate(px, py);
      canvas.scale(depthK);
      switch (b.kind) {
        case _BitKind.leaf:
          _leaf3D(canvas, b, tt, fadeAll);
        case _BitKind.streamer:
          _ribbon3D(canvas, b, tt, fadeAll);
        case _BitKind.orb:
          _orb3D(canvas, b, fadeAll);
        case _BitKind.star:
          _star3D(canvas, b, tt, fadeAll);
      }
      canvas.restore();
    }
  }

  /// Üç eksende dönen 3B konfeti yaprağı: ön yüz renkli, arka yüz koyu; ışığa göre parlaklık
  void _leaf3D(Canvas canvas, _Bit b, double tt, double alpha) {
    final rx = b.rx + b.wx * tt, ry = b.ry + b.wy * tt, rz = b.rz + b.wz * tt;
    final m = _persp()
      ..rotateZ(rz)
      ..rotateX(rx)
      ..rotateY(ry);
    canvas.transform(m.storage);
    final front = math.cos(rx) * math.cos(ry) >= 0;
    final shade = juzzioConfettiShade(rx, ry);
    final base = front ? b.color : Color.lerp(b.color, Colors.black, 0.35)!;
    final c = Color.lerp(Colors.black, base, shade)!;
    final r = Rect.fromCenter(center: Offset.zero, width: b.w, height: b.h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1.8)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(c, Colors.white, 0.35 * shade)!.withValues(alpha: alpha), c.withValues(alpha: alpha)],
        ).createShader(r),
    );
  }

  /// Bükülen kurdele: boyunca dönerek daralıp genişler, kıvrım yüzeyi ışığa göre gölgelenir
  void _ribbon3D(Canvas canvas, _Bit b, double tt, double alpha) {
    canvas.rotate(b.rz + b.wz * tt * 0.3);
    const segs = 14;
    var prev = Offset.zero;
    for (var i = 1; i <= segs; i++) {
      final y = -i * 5.0;
      final x = math.sin(tt * 7 + i * 0.7 + b.rx) * 7;
      final cur = Offset(x, y);
      final twist = math.cos(tt * 9 + i * 0.55 + b.ry);
      final width = 1.2 + 3.6 * twist.abs();
      final lit = 0.45 + 0.55 * twist.abs();
      final col = Color.lerp(Colors.black, twist >= 0 ? b.color : Color.lerp(b.color, Colors.black, 0.3)!, lit)!;
      canvas.drawLine(
        prev,
        cur,
        Paint()
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = col.withValues(alpha: alpha * (1 - i / (segs * 1.6))),
      );
      prev = cur;
    }
  }

  /// Parlak 3B küre (ışık sol üstten): yansıma noktası + alt gölge tonu
  void _orb3D(Canvas canvas, _Bit b, double alpha) {
    final r = b.w * 0.75;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: alpha),
            b.color.withValues(alpha: alpha),
            Color.lerp(b.color, Colors.black, 0.55)!.withValues(alpha: alpha),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
    canvas.drawCircle(Offset(-r * 0.35, -r * 0.4), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.85 * alpha));
  }

  /// Kabartmalı 3B yıldız: Y ekseninde döner, her kol ışık/gölge iki yüzle çizilir
  void _star3D(Canvas canvas, _Bit b, double tt, double alpha) {
    final ry = b.ry + b.wy * tt * 0.6;
    canvas.transform((_persp()..rotateY(ry)..rotateZ(b.rz + b.wz * tt * 0.2)).storage);
    final r = b.h * 0.65;
    final lit = juzzioConfettiShade(0, ry);
    for (var j = 0; j < 5; j++) {
      final a0 = -math.pi / 2 + j * 2 * math.pi / 5;
      final tip = Offset(math.cos(a0) * r, math.sin(a0) * r);
      final l = Offset(math.cos(a0 - math.pi / 5) * r * 0.42, math.sin(a0 - math.pi / 5) * r * 0.42);
      final rr = Offset(math.cos(a0 + math.pi / 5) * r * 0.42, math.sin(a0 + math.pi / 5) * r * 0.42);
      canvas.drawPath(Path()..moveTo(0, 0)..lineTo(l.dx, l.dy)..lineTo(tip.dx, tip.dy)..close(),
          Paint()..color = Color.lerp(const Color(0xFFB8860B), const Color(0xFFFFF2A8), lit)!.withValues(alpha: alpha));
      canvas.drawPath(Path()..moveTo(0, 0)..lineTo(tip.dx, tip.dy)..lineTo(rr.dx, rr.dy)..close(),
          Paint()..color = Color.lerp(const Color(0xFF8A6300), const Color(0xFFFFD23F), lit)!.withValues(alpha: alpha));
    }
  }

  /// El + patlatıcıyı 3B perspektifle çizer (yaw: Y ekseni, pitch: X ekseni), ağzın ekran
  /// koordinatını döndürür. Altında yumuşak temas gölgesi vardır.
  Offset _drawPopperHand3D(Canvas canvas, Offset base, double angle, double k,
      {required bool left, required bool popped, required double yaw, required double pitch}) {
    // zemin gölgesi (3B derinlik hissi)
    canvas.drawOval(
      Rect.fromCenter(center: base.translate(left ? -30 * k : 30 * k, 64 * k), width: 190 * k, height: 26 * k),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // perspektif merkezi elin kendisi: T(base) · P · R  (sahnenin köşesine kaymaz)
    final m = Matrix4.translationValues(base.dx, base.dy, 0)
      ..multiply(_persp())
      ..rotateY(left ? yaw : -yaw)
      ..rotateX(pitch)
      ..rotateZ(angle);
    canvas.save();
    canvas.transform(m.storage);
    canvas.scale(k);
    if (!left) canvas.scale(1, -1); // sağ el: ayna (başparmak yine üstte)
    _paintPopperAndHand(canvas, popped: popped);
    canvas.restore();
    // ağzın ekran koordinatı: aynı 3B dönüşümden (perspektif bölmesi dahil) geçirilir
    const coneLen = 96.0;
    return MatrixUtils.transformPoint(m, Offset((coneLen - 2.5) * k, 0));
  }

  /// Yerel koordinatta patlatıcı (silindirik ışıklı koni) + kil el (yumruk)
  void _paintPopperAndHand(Canvas canvas, {required bool popped}) {
    const coneBack = Offset(-6, 0);
    const coneLen = 96.0;
    final cone = Path()
      ..moveTo(coneBack.dx, coneBack.dy - 9)
      ..lineTo(coneBack.dx + coneLen, -27)
      ..quadraticBezierTo(coneBack.dx + coneLen + 7, 0, coneBack.dx + coneLen, 27)
      ..lineTo(coneBack.dx, 9)
      ..close();
    final coneRect = Rect.fromLTRB(-6, -27, coneLen + 2, 27);
    // silindirik ışık: üstten gelen ışıkla yuvarlak yüzey (koyu kenar → parlak şerit → koyu)
    canvas.drawPath(
      cone,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7A1749), Color(0xFFE0367E), Color(0xFFFFB3D9), Color(0xFFE0367E), Color(0xFF5E0F37)],
          stops: [0.0, 0.22, 0.38, 0.66, 1.0],
        ).createShader(coneRect),
    );
    // sarmal şeritler (koni yüzeyine göre gölgelenir)
    canvas.save();
    canvas.clipPath(cone);
    for (var i = 0; i < 6; i++) {
      final x = 8.0 + i * 17;
      final stripe = Path()
        ..moveTo(x, -34)
        ..lineTo(x + 7, -34)
        ..lineTo(x + 21, 34)
        ..lineTo(x + 14, 34)
        ..close();
      canvas.drawPath(
        stripe,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB08A00), Color(0xFFFFE066), Color(0xFFFFF6C2), Color(0xFFFFD23F), Color(0xFF8C6A00)],
            stops: [0.0, 0.25, 0.38, 0.68, 1.0],
          ).createShader(coneRect),
      );
    }
    // speküler parlama şeridi + ortam kapanması (koninin tabanı koyu)
    canvas.drawPath(
      Path()
        ..moveTo(4, -6)
        ..lineTo(coneLen - 8, -17),
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = 3.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawRect(
      Rect.fromLTRB(-6, -30, 26, 30),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0x66000000), Color(0x00000000)]).createShader(Rect.fromLTRB(-6, -30, 26, 30)),
    );
    canvas.restore();
    // ağız: metalik altın halka + derinlikli iç
    final rim = Rect.fromCenter(center: const Offset(coneLen - 2.5, 0), width: 15, height: 58);
    canvas.drawOval(
      rim,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF1A6), Color(0xFFC99A17), Color(0xFF7A5500), Color(0xFFE8C34A)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ).createShader(rim),
    );
    final hole = rim.deflate(2.6);
    canvas.drawOval(
      hole,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, 0),
          colors: popped
              ? const [Color(0xFF12040C), Color(0xFF3A1430), Color(0xFF6B2A55)]
              : const [Color(0xFFFFF0A0), Color(0xFFFFD45C), Color(0xFFC99A17)],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(hole),
    );

    // ---- el (yumruk) — kil dokusu, alt yüzey gölgeli ----
    const skin = Color(0xFFF6C3A5);
    const shade = Color(0xFFD98F6E);
    const deep = Color(0xFFB86F52);
    const light = Color(0xFFFFE3D2);
    final arm = RRect.fromRectAndRadius(const Rect.fromLTWH(-150, -19, 128, 38), const Radius.circular(19));
    canvas.drawRRect(
      arm,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, skin, shade, deep],
          stops: [0.0, 0.35, 0.75, 1.0],
        ).createShader(arm.outerRect),
    );
    // kolda speküler çizgi
    canvas.drawLine(const Offset(-140, -11), const Offset(-36, -11),
        Paint()
          ..color = const Color(0x88FFFFFF)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    final palm = RRect.fromRectAndRadius(const Rect.fromLTWH(-38, -28, 50, 58), const Radius.circular(22));
    canvas.drawShadow(Path()..addRRect(palm), const Color(0xFF000000), 8, false);
    canvas.drawRRect(
      palm,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-0.4, -0.5), radius: 1.15, colors: [light, skin, shade, deep], stops: [0.0, 0.45, 0.85, 1.0])
            .createShader(palm.outerRect),
    );
    // koniyi saran dört parmak: her boğum küre gibi gölgelenir, aralarında ortam kapanması
    for (var i = 0; i < 4; i++) {
      final c = Offset(-24 + i * 12.5, 26 + (i == 0 || i == 3 ? -2 : 0));
      final r = Rect.fromCenter(center: c, width: 14.5, height: 20);
      canvas.drawOval(
        r.shift(const Offset(0, 1.5)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawOval(
        r,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-0.3, -0.6), colors: [light, skin, shade, deep], stops: [0.0, 0.4, 0.8, 1.0])
              .createShader(r),
      );
      canvas.drawCircle(c.translate(-2.5, -4.5), 2.2, Paint()..color = const Color(0x99FFFFFF));
    }
    // başparmak (üstte, koninin üzerinden) + tırnak parlaması
    final thumb = RRect.fromRectAndRadius(const Rect.fromLTWH(-20, -36, 40, 16), const Radius.circular(8));
    canvas.drawShadow(Path()..addRRect(thumb), const Color(0xFF000000), 3, false);
    canvas.drawRRect(
      thumb,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [light, skin, shade, deep], stops: [0.0, 0.4, 0.8, 1.0])
            .createShader(thumb.outerRect),
    );
    canvas.drawOval(Rect.fromLTWH(10, -34, 8, 6), Paint()..color = const Color(0xFFFFF1EA));
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
