// =============================================================================
// JUZZIO v1.1.0 — Açılış / yükleme ekranı
//  Yeni logo (civciv + cam sohbet balonu) etrafında #07 Orbit yörünge halkası döner,
//  altında #03 Sparkler ilerleme çubuğu ve sırayla değişen durum metni
//  ("Bağlanıyor → Şifreleme doğrulanıyor → Mesajlar eşitleniyor").
//  JuzzioLaunchCurtain: soğuk açılışta Android açılış ekranından kesintisiz devam eder,
//  uygulama hazır olunca yaylı ölçek + solma ile açılır (altında sayfa zaten yükleniyor).
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import 'juzzio_motion.dart';

/// Marka zemin renkleri (Android açılış zeminiyle aynı → geçişte renk sıçraması olmaz)
const List<Color> kJuzzioBrandBackdrop = [Color(0xFF2B1677), Color(0xFF170D49), Color(0xFF0B1A4A)];
const Color kJuzzioBrandLime = Color(0xFFD6FF4A);

class JuzzioSplash extends StatefulWidget {
  const JuzzioSplash({super.key, this.showBackdrop = true, this.statuses});

  /// false → yalnız logo + yörünge (mevcut zeminin üstünde)
  final bool showBackdrop;

  /// Sırayla gösterilecek durumlar (varsayılan: bağlantı / şifreleme / eşitleme)
  final List<String>? statuses;

  @override
  State<JuzzioSplash> createState() => _JuzzioSplashState();
}

class _JuzzioSplashState extends State<JuzzioSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  Timer? _cycle;
  int _i = 0;

  List<String> get _statuses {
    final app = JuzzioAppController.instance;
    return widget.statuses ??
        [
          app.trEn('Bağlanıyor', 'Connecting', 'Verbinden'),
          app.trEn('Şifreleme doğrulanıyor', 'Verifying encryption', 'Verschlüsselung wird geprüft'),
          app.trEn('Mesajlar eşitleniyor', 'Syncing messages', 'Nachrichten werden synchronisiert'),
        ];
  }

  @override
  void initState() {
    super.initState();
    if (!JuzzioAppController.instance.reduceMotion) _breath.repeat(reverse: true);
    _cycle = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _statuses.length);
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    _cycle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final logo = (shortest * 0.30).clamp(96.0, 150.0);
    final ring = logo * 1.55;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // nefes alan lime hâle
                AnimatedBuilder(
                  animation: _breath,
                  builder: (context, _) => Container(
                    width: logo * (1.05 + 0.12 * _breath.value),
                    height: logo * (1.05 + 0.12 * _breath.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: kJuzzioBrandLime.withValues(alpha: 0.18 + 0.12 * _breath.value), blurRadius: 48, spreadRadius: 4)],
                    ),
                  ),
                ),
                SizedBox(width: ring, height: ring, child: const JuzzioOrbitLoader(color: kJuzzioBrandLime, strokeWidth: 3)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(logo * 0.226),
                  child: Image.asset('assets/logo/juzzio_logo.png', width: logo, height: logo, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => SizedBox(width: logo, height: logo)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Juzzio',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 14),
          SizedBox(
            width: math.min(220.0, shortest * 0.55),
            child: const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(99)),
              child: JuzzioSparklerBar(minHeight: 3, color: kJuzzioBrandLime, backgroundColor: Color(0x22FFFFFF)),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c),
            ),
            child: Text(
              '${_statuses[_i % _statuses.length]}…',
              key: ValueKey(_i),
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (!widget.showBackdrop) return content;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(-0.6, -0.7), radius: 1.6, colors: kJuzzioBrandBackdrop),
      ),
      child: content,
    );
  }
}

/// Soğuk açılışta sayfanın üstünde marka perdesi; [minDuration] sonra yaylanarak açılır.
class JuzzioLaunchCurtain extends StatefulWidget {
  const JuzzioLaunchCurtain({super.key, required this.child, this.minDuration = const Duration(milliseconds: 1100)});
  final Widget child;
  final Duration minDuration;

  @override
  State<JuzzioLaunchCurtain> createState() => _JuzzioLaunchCurtainState();
}

class _JuzzioLaunchCurtainState extends State<JuzzioLaunchCurtain> with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _gone = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (JuzzioAppController.instance.reduceMotion) {
      _gone = true;
      return;
    }
    _t = Timer(widget.minDuration, () {
      if (!mounted) return;
      _out.forward().whenComplete(() {
        if (mounted) setState(() => _gone = true);
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _out.isAnimating,
          child: AnimatedBuilder(
            animation: _out,
            builder: (context, child) {
              final t = kJuzzioSpring.transform(_out.value);
              return Opacity(
                opacity: (1 - _out.value).clamp(0.0, 1.0),
                child: Transform.scale(scale: 1 + 0.12 * t, child: child),
              );
            },
            child: const Material(type: MaterialType.transparency, child: JuzzioSplash()),
          ),
        ),
      ],
    );
  }
}
