// =============================================================================
// JUZZIO v0.9.7 — Karanlık / aydınlık geçişinde dairesel "reveal" animasyonu
//  Tema değiştiği anda eski ekranın görüntüsü yakalanır ve üstte tutulur; yeni tema,
//  kullanıcının son dokunduğu noktadan büyüyen bir daireyle açığa çıkar (ani renk
//  patlaması yok). Görüntü yakalanamazsa MaterialApp'in yumuşak renk geçişine düşülür.
//  "Hareketi azalt" açıksa animasyon yapılmaz.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_theme_and_locale.dart';

class JuzzioThemeReveal extends StatefulWidget {
  const JuzzioThemeReveal({super.key, required this.child});
  final Widget child;

  @override
  State<JuzzioThemeReveal> createState() => _JuzzioThemeRevealState();
}

class _JuzzioThemeRevealState extends State<JuzzioThemeReveal> with SingleTickerProviderStateMixin {
  final _app = JuzzioAppController.instance;
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  late bool _wasDark = _app.isDark;
  ui.Image? _snapshot;
  Offset _origin = Offset.zero;
  Offset? _lastTap;

  @override
  void initState() {
    super.initState();
    _app.addListener(_onApp);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        final img = _snapshot;
        setState(() => _snapshot = null);
        img?.dispose();
      }
    });
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    _c.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  void _onApp() {
    final dark = _app.isDark;
    if (dark == _wasDark) return;
    _wasDark = dark;
    if (_app.reduceMotion || !mounted) return;
    // Kare çizimi sırasında (build içinden) tetiklenirse yakalama yapılmaz
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) return;
    // Dinleyici, yeni tema çizilmeden ÖNCE çağrılır: sınırdaki katman hâlâ eski temadır
    try {
      final ro = _boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary || !ro.hasSize) return;
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final img = ro.toImageSync(pixelRatio: math.min(dpr, 2.0));
      final size = ro.size;
      _snapshot?.dispose();
      setState(() {
        _snapshot = img;
        _origin = _lastTap ?? Offset(size.width - 48, 72);
      });
      _c.forward(from: 0);
    } catch (_) {
      _snapshot = null; // yumuşak renk geçişine düş
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _lastTap = e.localPosition,
      child: Stack(textDirection: TextDirection.ltr, fit: StackFit.passthrough, children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (_snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _RevealPainter(
                    image: _snapshot!,
                    origin: _origin,
                    t: Curves.easeInOutCubic.transform(_c.value),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _RevealPainter extends CustomPainter {
  _RevealPainter({required this.image, required this.origin, required this.t});
  final ui.Image image;
  final Offset origin;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - origin).distance).reduce(math.max);
    final radius = far * t;
    // Eski tema, büyüyen dairenin DIŞINDA kalır; içeride yeni tema görünür
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
    canvas.save();
    canvas.clipPath(hole);
    paintImage(canvas: canvas, rect: Offset.zero & size, image: image, fit: BoxFit.fill, filterQuality: FilterQuality.low);
    canvas.restore();
    // Dairenin kenarında ince, yumuşak ışık halkası
    if (t > 0 && t < 1) {
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.25 * (1 - t))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_RevealPainter old) => old.t != t || old.image != image || old.origin != origin;
}
