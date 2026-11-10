// =============================================================================
// JUZZIO v1.1.0 — Mesaj gönderme animasyonları (referans: "10 send-message")
//  • JuzzioPaperPlaneButton  (#02 Paper plane + #05 Swoosh): gönder düğmesi
//  • JuzzioSendFlight        (#06 Input morph + #07 Droplet + #01 Slide up):
//      yazma kutusundaki metin kapsülü koparak damlaya dönüşür, yukarı kayıp
//      sohbet balonu olarak açılır
//  • JuzzioBubbleEntrance    yeni balon yaylı kayarak gelir (#01 / #03 Pop)
//  • juzzioBigEmojiCount     (#08 Big Emoji): yalnız emoji mesajı büyük gösterilir
//  • juzzioIsCelebration + JuzzioConfettiBurst (#09 Confetti)
//  • JuzzioReceiptTicks      (#04 Read receipts): saat → ✓ → ✓✓ → parlayan ✓✓
//  • JuzzioPopIn             (#10 Reaction): tepki rozeti yaylı belirir + halka
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import 'juzzio_motion_core.dart';

// -----------------------------------------------------------------------------
// Kağıt uçak gönder düğmesi
// -----------------------------------------------------------------------------
class JuzzioPaperPlaneButton extends StatefulWidget {
  const JuzzioPaperPlaneButton({super.key, required this.onPressed, this.size = 48, this.tooltip});
  final VoidCallback onPressed;
  final double size;
  final String? tooltip;

  @override
  State<JuzzioPaperPlaneButton> createState() => _JuzzioPaperPlaneButtonState();
}

class _JuzzioPaperPlaneButtonState extends State<JuzzioPaperPlaneButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  bool _pressed = false;

  void _fire() {
    JuzzioHaptics.send();
    if (!juzzioReduceMotion(context)) _c.forward(from: 0);
    widget.onPressed();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final on = JuzzioGlassTokens.onGlow;
    final s = widget.size;
    return Semantics(
      button: true,
      label: widget.tooltip ?? JuzzioAppController.instance.trEn('Gönder', 'Send', 'Senden'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _fire,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glow,
              boxShadow: JuzzioGlassTokens.glowShadow(0.8),
            ),
            child: ClipOval(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  // 0–0,45: uçak sağ üste fırlar (swoosh çizgileriyle) · 0,45–1: soldan alttan yaylı geri gelir
                  double dx, dy, sc, op;
                  if (t == 0) {
                    dx = 0;
                    dy = 0;
                    sc = 1;
                    op = 1;
                  } else if (t < 0.45) {
                    final k = Curves.easeInCubic.transform(t / 0.45);
                    dx = s * 0.75 * k;
                    dy = -s * 0.75 * k;
                    sc = 1 - 0.35 * k;
                    op = 1 - k;
                  } else {
                    final k = const JuzzioSpringCurve().transform((t - 0.45) / 0.55);
                    dx = -s * 0.55 * (1 - k);
                    dy = s * 0.55 * (1 - k);
                    sc = 0.6 + 0.4 * k;
                    op = k.clamp(0.0, 1.0);
                  }
                  final swoosh = t > 0 && t < 0.5 ? math.sin(math.pi * t / 0.5) : 0.0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (swoosh > 0)
                        CustomPaint(size: Size.square(s), painter: _SwooshPainter(progress: t / 0.5, color: on.withValues(alpha: 0.55 * swoosh))),
                      Transform.translate(
                        offset: Offset(dx, dy),
                        child: Opacity(
                          opacity: op,
                          child: Transform.scale(
                            scale: sc,
                            child: Transform.rotate(angle: -0.5, child: Icon(Icons.send_rounded, color: on, size: s * 0.44)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  _SwooshPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    const dir = Offset(0.707, -0.707);
    for (var i = 0; i < 3; i++) {
      final off = Offset(-dir.dy, dir.dx) * ((i - 1) * 6.0);
      final len = size.width * (0.22 + 0.08 * i);
      final start = c + off + dir * (size.width * (progress * 0.6 - 0.25));
      canvas.drawLine(start - dir * len, start, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SwooshPainter o) => o.progress != progress || o.color != color;
}

// -----------------------------------------------------------------------------
// Input morph + Droplet uçuşu (yazma kutusu → balon)
// -----------------------------------------------------------------------------
/// v1.2.2: Uçuşun görünümü — balonla BİREBİR aynı yazı stili, renk ve köşe yarıçapları.
/// (v1.1.0'daki "font değişimi" uçan metnin varsayılan yazı tipiyle çizilmesinden,
///  "pembe parlama" kapsülün vurgu rengine/gölgesine boyanmasından kaynaklanıyordu.)
class JuzzioSendFlightStyle {
  const JuzzioSendFlightStyle({
    required this.textStyle,
    required this.bubbleColor,
    required this.composerColor,
    required this.composerTextColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.bubbleRadius = const BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
      bottomLeft: Radius.circular(20),
      bottomRight: Radius.circular(6),
    ),
  });

  final TextStyle textStyle;
  final Color bubbleColor;
  final Color composerColor;
  final Color composerTextColor;
  final EdgeInsets padding;
  final BorderRadius bubbleRadius;
}

/// Uçuş ↔ gerçek balon el sıkışması (anahtar = clientMsgId)
class JuzzioFlightHandle {
  JuzzioFlightHandle._(this.key);
  final String key;

  /// Gerçek balonun bağlamı (her karede konumu buradan okunur → kaydırma sırasında da doğru iner)
  BuildContext? targetContext;

  /// true olunca gerçek balon görünür olur (aynı karede uçuş katmanı kaldırılır)
  final ValueNotifier<bool> landed = ValueNotifier<bool>(false);
}

class JuzzioSendFlight {
  JuzzioSendFlight._();

  static const Duration duration = Duration(milliseconds: 440);
  static final Map<String, JuzzioFlightHandle> _pending = <String, JuzzioFlightHandle>{};

  /// Bu mesaj için uçuş sürüyor mu (balon girişi bu durumda kendi animasyonunu oynatmaz)
  static bool isPending(String key) => _pending.containsKey(key) && !_pending[key]!.landed.value;
  static JuzzioFlightHandle? handleFor(String key) => _pending[key];

  /// [from]: yazma kutusunun ekran kutusu. Varış noktası gerçek balondan okunur;
  /// balon henüz çizilmediyse [estimateBubbleRect] ile tahmin edilir.
  static void launch(
    BuildContext context, {
    required String key,
    required Rect from,
    required String text,
    required JuzzioSendFlightStyle style,
  }) {
    if (juzzioReduceMotion(context) || JuzzioGlassTokens.reducedEffects) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final handle = JuzzioFlightHandle._(key);
    _pending[key] = handle;
    final estimate = estimateBubbleRect(context, from, text, style);
    late OverlayEntry entry;
    var removed = false;
    void finish() {
      if (removed) return;
      removed = true;
      handle.landed.value = true; // balon bu karede görünür olur
      // katman bir sonraki karede kalkar → arada boş kare / çift görüntü yok
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (entry.mounted) entry.remove();
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (identical(_pending[key], handle)) _pending.remove(key);
        });
      });
    }

    entry = OverlayEntry(
      builder: (_) => _FlightView(
        from: from,
        estimate: estimate,
        handle: handle,
        text: text,
        style: style,
        onDone: finish,
      ),
    );
    overlay.insert(entry);
  }

  /// Sağ hizalı giden balonun tahmini kutusu (balonla aynı yazı stiliyle ölçülür)
  static Rect estimateBubbleRect(BuildContext context, Rect composer, String text, [JuzzioSendFlightStyle? style]) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = style?.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style?.textStyle ?? const TextStyle(fontSize: 15)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 6,
    )..layout(maxWidth: width * 0.72 - pad.horizontal);
    final w = (tp.width + pad.horizontal + 44).clamp(64.0, width * 0.78);
    final h = (tp.height + pad.vertical + 18).clamp(40.0, 180.0);
    return Rect.fromLTWH(width - 16 - w, composer.top - 10 - h, w, h);
  }
}

/// Gerçek balonu sarar: uçuş sürerken balon yerini korur ama görünmez; uçuş indiği karede
/// anında (solma/ölçek olmadan) görünür. Uçuş yoksa çocuğu olduğu gibi döndürür.
class JuzzioFlightTarget extends StatefulWidget {
  const JuzzioFlightTarget({super.key, required this.flightKey, required this.child});
  final String? flightKey;
  final Widget child;

  @override
  State<JuzzioFlightTarget> createState() => _JuzzioFlightTargetState();
}

class _JuzzioFlightTargetState extends State<JuzzioFlightTarget> {
  JuzzioFlightHandle? _h;

  void _attach() {
    final k = widget.flightKey;
    final h = k == null ? null : JuzzioSendFlight.handleFor(k);
    if (identical(h, _h)) {
      _h?.targetContext = context;
      return;
    }
    _h?.landed.removeListener(_onLanded);
    _h = h;
    if (h != null) {
      h.targetContext = context;
      h.landed.addListener(_onLanded);
    }
  }

  void _onLanded() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant JuzzioFlightTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach();
  }

  @override
  void dispose() {
    final h = _h;
    if (h != null) {
      h.landed.removeListener(_onLanded);
      if (identical(h.targetContext, context)) h.targetContext = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final hidden = h != null && !h.landed.value;
    return Opacity(opacity: hidden ? 0.0 : 1.0, child: widget.child);
  }
}

class _FlightView extends StatefulWidget {
  const _FlightView({
    required this.from,
    required this.estimate,
    required this.handle,
    required this.text,
    required this.style,
    required this.onDone,
  });
  final Rect from;
  final Rect estimate;
  final JuzzioFlightHandle handle;
  final String text;
  final JuzzioSendFlightStyle style;
  final VoidCallback onDone;
  @override
  State<_FlightView> createState() => _FlightViewState();
}

class _FlightViewState extends State<_FlightView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: JuzzioSendFlight.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  Rect? _lastTo;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Gerçek balonun bu karedeki kutusu (katman koordinatlarında); yoksa tahmin
  Rect _target(BuildContext context) {
    final tc = widget.handle.targetContext;
    final ro = tc != null && tc.mounted ? tc.findRenderObject() : null;
    final me = context.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize && me is RenderBox && me.attached) {
      final topLeft = me.globalToLocal(ro.localToGlobal(Offset.zero));
      return topLeft & ro.size;
    }
    return widget.estimate;
  }

  Rect _fromLocal(BuildContext context) {
    final me = context.findRenderObject();
    if (me is RenderBox && me.attached) {
      return me.globalToLocal(widget.from.topLeft) & widget.from.size;
    }
    return widget.from;
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.style;
    // v1.2.7: uçuş kök Overlay'de çizilir; orada Material/DefaultTextStyle atası yoktur ve
    // Flutter metni varsayılan hata stiliyle (SARI ÇİFT ALT ÇİZGİ) boyar. Saydam Material +
    // alt çizgisiz DefaultTextStyle ile uçan metin balondakiyle birebir aynı görünür.
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: st.textStyle.copyWith(decoration: TextDecoration.none),
          child: _flight(st),
        ),
      ),
    );
  }

  Widget _flight(JuzzioSendFlightStyle st) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // aşmasız (overshoot yok) eğri → balonun TAM yerine iner, zıplama olmaz
          final move = Curves.easeInOutCubic.transform(t);
          // v1.2.7: gerçek balon uçuşun ortasında ortaya çıktığında hedef tahminden gerçeğe
          // birkaç karede yumuşakça kayar (önceden tek karede sıçrıyordu); son %8'de tam gerçek kutu.
          final actual = _target(context);
          final prev = _lastTo;
          final to = prev == null || t >= 0.92 ? actual : Rect.lerp(prev, actual, 0.35)!;
          _lastTo = to;
          final from = _fromLocal(context);
          // damla: yolun ortasında hafifçe daralıp uzar, varışta balon şekline tam oturur
          final pinch = math.sin(math.pi * t) * 0.28;
          final r = Rect.lerp(from, to, move)!;
          final rect = Rect.fromCenter(
            center: r.center,
            width: math.max(36.0, r.width * (1 - pinch)),
            height: r.height * (1 + pinch * 0.6),
          );
          final morph = Curves.easeOut.transform(t);
          final full = Radius.circular(rect.shortestSide / 2);
          final br = st.bubbleRadius;
          Radius mix(Radius b) => Radius.lerp(full, b, morph)!;
          final textColor = Color.lerp(st.composerTextColor, st.textStyle.color ?? Colors.white, morph);
          // metin balondaki genişlikte dizilir ve yalnız ölçeklenir → satır kırılımı/yazı tipi uçuşta DEĞİŞMEZ
          final innerW = math.max(1.0, to.width - st.padding.horizontal);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color.lerp(st.composerColor, st.bubbleColor, morph),
                    borderRadius: BorderRadius.only(
                      topLeft: mix(br.topLeft),
                      topRight: mix(br.topRight),
                      bottomLeft: mix(br.bottomLeft),
                      bottomRight: mix(br.bottomRight),
                    ),
                  ),
                  padding: EdgeInsets.lerp(const EdgeInsets.symmetric(horizontal: 14, vertical: 10), st.padding, morph),
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: innerW,
                      child: Text(
                        widget.text,
                        style: st.textStyle.copyWith(
                          color: textColor,
                          decoration: TextDecoration.none,
                          decorationColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


// -----------------------------------------------------------------------------
// Yeni balon girişi (+ kutlama konfetisi)
// -----------------------------------------------------------------------------
class JuzzioBubbleEntrance extends StatefulWidget {
  const JuzzioBubbleEntrance({
    super.key,
    required this.entranceKey,
    required this.isMe,
    required this.createdAt,
    required this.child,
    this.celebrate = false,
    this.pop = false,
    this.delay = Duration.zero,
  });

  /// istemci kimliği (yerel → sunucu kaydında tekrar oynamaz)
  final String entranceKey;
  final bool isMe;
  final DateTime createdAt;
  final Widget child;
  final bool celebrate;

  /// büyük emoji: zıplayarak (Pop) gelir
  final bool pop;
  final Duration delay;

  static final Set<String> _played = <String>{};

  /// Bu anahtar daha önce oynatıldı mı / oynatılmalı mı (yeni mesaj = son 8 sn)
  /// v1.2.0: mesaj "yeni" mi (son 8 sn) — kartlardaki tek seferlik animasyonlar için
  static bool isFresh(DateTime createdAt) => DateTime.now().difference(createdAt).inSeconds.abs() <= 8;

  static bool shouldPlay(String key, DateTime createdAt, DateTime now) {
    if (_played.contains(key)) return false;
    final age = now.difference(createdAt);
    return age.inSeconds.abs() <= 8;
  }

  static void markPlayed(String key) {
    _played.add(key);
    if (_played.length > 600) _played.remove(_played.first);
  }

  @override
  State<JuzzioBubbleEntrance> createState() => _JuzzioBubbleEntranceState();
}

class _JuzzioBubbleEntranceState extends State<JuzzioBubbleEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _confetti = false;

  @override
  void initState() {
    super.initState();
    // v1.2.2: bu balona uçuş iniyorsa ayrı giriş oynatılmaz (devir teslim tek karede, zıplama yok)
    final play = !JuzzioAppController.instance.reduceMotion &&
        !JuzzioSendFlight.isPending(widget.entranceKey) &&
        JuzzioBubbleEntrance.shouldPlay(widget.entranceKey, widget.createdAt, DateTime.now());
    JuzzioBubbleEntrance.markPlayed(widget.entranceKey);
    if (play) {
      _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.pop ? 620 : 220));
      // v1.2.0: performans modunda konfeti yok
      _confetti = widget.celebrate && !JuzzioGlassTokens.reducedEffects;
      if (widget.delay == Duration.zero) {
        _c!.forward();
      } else {
        Future<void>.delayed(widget.delay, () {
          if (mounted) _c?.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final align = widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft;
    final body = AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        final t = c.value;
        if (!widget.pop) {
          // v1.2.0: sakin giriş — zıplama/ölçek yok, yazı tipi ve renk sabit; yalnız kısa süzülme
          final e = Curves.easeOutCubic.transform(t);
          return Opacity(
            opacity: e,
            child: Transform.translate(offset: Offset(0, 10 * (1 - e)), child: child),
          );
        }
        final k = const JuzzioSpringCurve(damping: 5, frequency: 2.8).transform(t);
        return Opacity(
          opacity: (t * 3).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - k)),
            child: Transform.scale(alignment: align, scale: 0.3 + 0.7 * k, child: child),
          ),
        );
      },
    );
    if (!_confetti) return body;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        Positioned.fill(child: IgnorePointer(child: JuzzioConfettiBurst(onDone: () {
          if (mounted) setState(() => _confetti = false);
        }))),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Büyük emoji ve kutlama algılama (saf; test edilir)
// -----------------------------------------------------------------------------
bool _isEmojiRune(int r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    r == 0x00A9 ||
    r == 0x00AE ||
    r == 0x203C ||
    r == 0x2049 ||
    r == 0x3030 ||
    r == 0x303D;

/// Metin yalnız 1–3 emojiden oluşuyorsa sayısını, değilse 0 döndürür
int juzzioBigEmojiCount(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 40) return 0;
  var count = 0;
  for (final g in t.characters) {
    if (g.trim().isEmpty) continue;
    final first = g.runes.first;
    if (!_isEmojiRune(first)) return 0;
    count++;
    if (count > 3) return 0;
  }
  return count;
}

const List<String> _kCelebrate = [
  'iyi ki doğdun', 'iyiki doğdun', 'doğum günün kutlu', 'doğum gününü kutlu', 'mutlu yıllar', 'tebrikler', 'tebrik ederim',
  'yeni yılın kutlu', 'bayramın kutlu', 'nice yıllara', 'happy birthday', 'happy bday', 'congrats', 'congratulations',
  'happy new year', 'alles gute zum geburtstag', 'herzlichen glückwunsch', 'frohes neues', 'gratuliere',
  '🎉', '🎂', '🥳', '🎊',
];

/// Kutlama sözcükleri (TR/EN/DE) veya kutlama emojileri içeriyor mu
bool juzzioIsCelebration(String text) {
  if (text.trim().isEmpty) return false;
  final tr = text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final plain = text.replaceAll('İ', 'i').toLowerCase();
  for (final k in _kCelebrate) {
    if (tr.contains(k) || plain.contains(k)) return true;
  }
  return false;
}

// -----------------------------------------------------------------------------
// Konfeti patlaması
// -----------------------------------------------------------------------------
class JuzzioConfettiBurst extends StatefulWidget {
  const JuzzioConfettiBurst({super.key, this.onDone, this.pieces = 34});
  final VoidCallback? onDone;
  final int pieces;
  @override
  State<JuzzioConfettiBurst> createState() => _JuzzioConfettiBurstState();
}

class _Piece {
  _Piece(this.vx, this.vy, this.rot, this.vr, this.color, this.w, this.h);
  double x = 0, y = 0;
  double vx, vy, rot, vr;
  final Color color;
  final double w, h;
}

class _JuzzioConfettiBurstState extends State<JuzzioConfettiBurst> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Piece> _pieces = [];
  Duration _last = Duration.zero;
  double _age = 0;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final glow = JuzzioGlassTokens.glow;
    final palette = <Color>[
      glow,
      HSLColor.fromColor(glow).withHue((HSLColor.fromColor(glow).hue + 60) % 360).toColor(),
      HSLColor.fromColor(glow).withHue((HSLColor.fromColor(glow).hue + 180) % 360).toColor(),
      const Color(0xFFFFD54A),
      const Color(0xFFFF5C8A),
      Colors.white,
    ];
    for (var i = 0; i < widget.pieces; i++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.4;
      final sp = 160 + rnd.nextDouble() * 220;
      _pieces.add(_Piece(math.cos(a) * sp, math.sin(a) * sp, rnd.nextDouble() * math.pi, (rnd.nextDouble() - 0.5) * 12,
          palette[rnd.nextInt(palette.length)], 4 + rnd.nextDouble() * 4, 6 + rnd.nextDouble() * 6));
    }
    _ticker = createTicker(_tick)..start();
    JuzzioHaptics.success();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _age += dt;
    for (final p in _pieces) {
      p.vy += 520 * dt;
      p.vx *= 1 - 1.6 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
    }
    if (_age > 1.5) {
      _ticker.stop();
      widget.onDone?.call();
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ConfettiPainter(_pieces, (1 - (_age - 1.0) / 0.5).clamp(0.0, 1.0)));
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.opacity);
  final List<_Piece> pieces;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = size.center(Offset.zero);
    for (final p in pieces) {
      canvas.save();
      canvas.translate(origin.dx + p.x, origin.dy + p.y);
      canvas.rotate(p.rot);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h * (0.4 + 0.6 * math.cos(p.rot * 2).abs())), const Radius.circular(1.5)),
        Paint()..color = p.color.withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// Okundu bilgisi: saat → ✓ → ✓✓ (gri) → ✓✓ (parlayan) çizim animasyonu
// -----------------------------------------------------------------------------
enum JuzzioReceipt { sending, sent, delivered, read }

class JuzzioReceiptTicks extends StatelessWidget {
  const JuzzioReceiptTicks({super.key, required this.state, this.size = 15, this.idleColor, this.readColor, this.fresh = false});
  final JuzzioReceipt state;

  /// yeni mesaj: bir önceki durumdan çizilerek gelir (ör. ✓ → ✓✓)
  final bool fresh;
  final double size;
  final Color? idleColor;
  final Color? readColor;

  @override
  Widget build(BuildContext context) {
    final idle = idleColor ?? Colors.white54;
    final read = readColor ?? JuzzioGlassTokens.glowText;
    final level = switch (state) {
      JuzzioReceipt.sending => 0.0,
      JuzzioReceipt.sent => 1.0,
      JuzzioReceipt.delivered => 2.0,
      JuzzioReceipt.read => 3.0,
    };
    final app = JuzzioAppController.instance;
    return Semantics(
      label: switch (state) {
        JuzzioReceipt.sending => app.trEn('Gönderiliyor', 'Sending', 'Wird gesendet'),
        JuzzioReceipt.sent => app.trEn('Gönderildi', 'Sent', 'Gesendet'),
        JuzzioReceipt.delivered => app.trEn('İletildi', 'Delivered', 'Zugestellt'),
        JuzzioReceipt.read => app.trEn('Okundu', 'Read', 'Gelesen'),
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: fresh ? math.max(0.0, level - 1) : null, end: level),
        duration: Duration(milliseconds: app.reduceMotion ? 0 : 520),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          size: Size(size * 1.25, size),
          painter: _TicksPainter(level: v, idle: idle, read: read),
        ),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.level, required this.idle, required this.read});
  final double level;
  final Color idle;
  final Color read;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(idle, read, (level - 2).clamp(0.0, 1.0))!;
    if (level < 1) {
      // saat (gönderiliyor) — ilk tik belirdikçe söner
      final a = (1 - level).clamp(0.0, 1.0);
      final c = Offset(h * 0.55, h * 0.5);
      final cp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.1
        ..strokeCap = StrokeCap.round
        ..color = idle.withValues(alpha: a);
      canvas.drawCircle(c, h * 0.36, cp);
      canvas.drawLine(c, c.translate(0, -h * 0.2), cp);
      canvas.drawLine(c, c.translate(h * 0.14, 0), cp);
    }
    void tick(double dx, double progress) {
      if (progress <= 0) return;
      final path = Path()
        ..moveTo(dx + h * 0.08, h * 0.55)
        ..lineTo(dx + h * 0.38, h * 0.82)
        ..lineTo(dx + h * 0.92, h * 0.2);
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * progress.clamp(0.0, 1.0)), p);
      }
    }

    tick(0, level.clamp(0.0, 1.0));
    tick(h * 0.32, (level - 1).clamp(0.0, 1.0));
    if (level > 2.05) {
      // okundu: hafif parıltı
      final g = Paint()
        ..color = read.withValues(alpha: 0.35 * (level - 2).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.3);
      canvas.drawCircle(Offset(size.width * 0.55, h * 0.5), h * 0.45, g);
    }
  }

  @override
  bool shouldRepaint(covariant _TicksPainter o) => o.level != level || o.idle != idle || o.read != read;
}

// -----------------------------------------------------------------------------
// Tepki rozeti: yaylı belirme + ince halka patlaması
// -----------------------------------------------------------------------------
class JuzzioPopIn extends StatefulWidget {
  const JuzzioPopIn({super.key, required this.child, this.ring = true, this.play = true});
  final Widget child;
  final bool ring;

  /// false → animasyonsuz (eski tepkiler kaydırırken yeniden zıplamasın)
  final bool play;
  @override
  State<JuzzioPopIn> createState() => _JuzzioPopInState();
}

class _JuzzioPopInState extends State<JuzzioPopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));

  @override
  void initState() {
    super.initState();
    if (JuzzioAppController.instance.reduceMotion || !widget.play) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final k = const JuzzioSpringCurve(damping: 5.5, frequency: 3).transform(t);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.ring && t > 0 && t < 1)
              IgnorePointer(
                child: Container(
                  width: 18 + 30 * t,
                  height: 18 + 30 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: glow.withValues(alpha: (1 - t) * 0.8), width: 2 * (1 - t) + 0.5),
                  ),
                ),
              ),
            Transform.scale(scale: k.clamp(0.0, 1.4), child: child),
          ],
        );
      },
    );
  }
}
