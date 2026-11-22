// =============================================================================
// JUZZIO v2.0.0 — Windows/macOS Masaüstü Kabuk
//
// Geniş masaüstü penceresinde (≥ 900 px) gerçek 3-panel düzeni sağlar:
//   • SOL  : NavigationRail + Juzzio logosu + kullanıcı bilgisi
//   • ORTA : Sekme içeriği (sohbet listesi, aramalar, keşfet, profil…)
//   • SAĞ  : Aktif konuşma veya "Sohbet seç" yer tutucusu
//
// Aynı zamanda klavye kısayollarını yönetir:
//   Ctrl+K  → Hızlı arama / Komut Merkezi
//   Ctrl+N  → Yeni konuşma
//   Ctrl+F  → Mevcut konuşmada ara (uygulama içinden tetiklenir)
//   Esc     → Diyaloğu kapat / geri dön
// =============================================================================

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/juzzio_glass.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import 'juzzio_brand.dart';

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

bool get juzzioIsDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// 3-panel düzeni için minimum pencere genişliği.
const double kJuzzioDesktopThreePanelMin = 900;

/// Orta panelin minimum genişliği.
const double kJuzzioCenterPanelMinWidth = 320;

/// Sol kenar çubuğunun genişliği.
const double kJuzzioNavRailWidth = 72;

// ---------------------------------------------------------------------------
// Klavye kısayol intents
// ---------------------------------------------------------------------------

class JuzzioShortcutIntent extends Intent {
  const JuzzioShortcutIntent(this.action);
  final JuzzioDesktopAction action;
}

enum JuzzioDesktopAction { quickSearch, newChat, findInChat, goBack }

// ---------------------------------------------------------------------------
// JuzzioDesktopShell
// ---------------------------------------------------------------------------

/// Masaüstü kabuğu. Geniş pencerede 3-panel ve klavye kısayolları sağlar.
/// Dar pencerede veya mobilde şeffaf geçiş yapar (child'ı doğrudan döner).
class JuzzioDesktopShell extends StatelessWidget {
  const JuzzioDesktopShell({
    super.key,
    required this.child,
    required this.navRail,
    required this.rightPanel,
    required this.onShortcut,
    this.forceDesktop,
  });

  /// Merkez panel içeriği (sekmeler).
  final Widget child;

  /// Sol NavigationRail widget'ı.
  final Widget navRail;

  /// Sağ panel (aktif konuşma veya yer tutucu).
  final Widget rightPanel;

  /// Klavye kısayolları tetiklendiğinde çağrılır.
  final void Function(JuzzioDesktopAction) onShortcut;

  /// Test için zorla; null → yalnız geniş masaüstünde etkin.
  final bool? forceDesktop;

  static bool shouldUseThreePanel(BuildContext context) {
    if (!juzzioIsDesktopPlatform) return false;
    return MediaQuery.sizeOf(context).width >= kJuzzioDesktopThreePanelMin;
  }

  @override
  Widget build(BuildContext context) {
    if (!(forceDesktop ?? shouldUseThreePanel(context))) return child;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => onShortcut(JuzzioDesktopAction.quickSearch),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => onShortcut(JuzzioDesktopAction.newChat),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => onShortcut(JuzzioDesktopAction.findInChat),
        const SingleActivator(LogicalKeyboardKey.escape): () => onShortcut(JuzzioDesktopAction.goBack),
      },
      child: Focus(
        autofocus: true,
        child: _DesktopThreePanelLayout(
          navRail: navRail,
          center: child,
          right: rightPanel,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DesktopThreePanelLayout
// ---------------------------------------------------------------------------

class _DesktopThreePanelLayout extends StatelessWidget {
  const _DesktopThreePanelLayout({
    required this.navRail,
    required this.center,
    required this.right,
  });

  final Widget navRail;
  final Widget center;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final border = JuzzioGlassTokens.spaceCardBorder;
    final size = MediaQuery.sizeOf(context);
    // GM-9276 (gm9276_masaustu_sohbetler.png): sohbet listesi sabit genişlikte (~%30, 320–420 px),
    // açık sohbet kalan alanın tamamını kullanır.
    final listWidth = juzzioDesktopListWidth(size.width);

    // GM-028 (v2.2.0): kenar çubuğu ve sohbet listesi pencereden ayrık, yuvarlak köşeli yüzen
    // cam paneller; sağda gece/gündüz sahnesi (JuzzioDesktopSceneBackdrop) — referans tasarım.
    return Row(
      children: [
        // Sol kenar çubuğu
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
          child: SizedBox(width: kJuzzioNavRailWidth - 8, child: navRail),
        ),
        // Sohbet listesi (cam panel)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          child: SizedBox(
            width: listWidth,
            child: JuzzioLiquidGlass(
              radius: 22,
              blur: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: border.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(22), child: center),
              ),
            ),
          ),
        ),
        // Açık sohbet
        Expanded(child: right),
      ],
    );
  }
}

/// GM-9276: masaüstü sohbet listesi genişliği (saf, test edilir)
double juzzioDesktopListWidth(double windowWidth) =>
    ((windowWidth - kJuzzioNavRailWidth) * 0.34).clamp(kJuzzioCenterPanelMinWidth, 420.0).toDouble();

// ---------------------------------------------------------------------------
// JuzzioDesktopNavRail  (sol kenar çubuğu)
// ---------------------------------------------------------------------------

class JuzzioDesktopNavRail extends StatelessWidget {
  const JuzzioDesktopNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onNewChat,
    this.unreadBadge = 0,
    this.alertBadge = 0,
    this.userName = '',
    this.userAvatarUrl,
    this.onProfileTap,
  });

  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  /// Ctrl+N ve liste başlığındaki kalem düğmesiyle aynı eylem (rayda ayrı düğme yok)
  final VoidCallback onNewChat;
  final int unreadBadge;
  final int alertBadge;
  final String userName;
  final String? userAvatarUrl;
  final VoidCallback? onProfileTap;

  /// GM-9276: J logosu, cam ikon sütunu (seçili: vurgu kenarlı yuvarlak kare), altta kullanıcı.
  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final app = JuzzioAppController.instance;
    final items = <(IconData, IconData, String, int)>[
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, app.trEn('Sohbetler', 'Chats', 'Chats'), unreadBadge),
      (Icons.explore_outlined, Icons.explore_rounded, app.trEn('Keşfet', 'Explore', 'Erkunden'), 0),
      (Icons.call_outlined, Icons.call_rounded, app.trEn('Aramalar', 'Calls', 'Anrufe'), 0),
      (Icons.notifications_none_rounded, Icons.notifications_rounded, app.trEn('Bildirimler', 'Notifications', 'Benachrichtigungen'), alertBadge),
      (Icons.person_outline_rounded, Icons.person_rounded, app.trEn('Profil', 'Profile', 'Profil'), 0),
    ];

    Widget item(int i) {
      final it = items[i];
      final sel = selectedIndex == i;
      final icon = Icon(it.$1, color: sel ? glow : JuzzioGlassTokens.textSecondary, size: 25);
      final box = sel
          ? JuzzioLiquidGlass(
              radius: 16,
              glowBorder: true,
              tint: glow,
              blur: 0,
              child: SizedBox(width: 50, height: 50, child: Center(child: icon)),
            )
          : SizedBox(width: 50, height: 50, child: Center(child: icon));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Tooltip(
          message: it.$3,
          waitDuration: const Duration(milliseconds: 400),
          child: Semantics(
            button: true,
            selected: sel,
            label: it.$3,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onDestinationSelected(i),
              child: Badge(
                isLabelVisible: it.$4 > 0,
                backgroundColor: glow,
                textColor: JuzzioGlassTokens.onGlow,
                label: Text(it.$4 > 99 ? '99+' : '${it.$4}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                child: box,
              ),
            ),
          ),
        ),
      );
    }

    final initial = userName.trim().isEmpty ? '?' : String.fromCharCode(userName.trim().runes.first).toUpperCase();
    // GM-028 (v2.2.0): kenar çubuğu yüzen, köşeli cam kart (referans masaüstü tasarımı)
    return JuzzioLiquidGlass(
      radius: 22,
      blur: 20,
      child: Column(
        children: [
          const SizedBox(height: 22),
          Tooltip(
            message: app.trEn('Yeni sohbet (Ctrl+N)', 'New chat (Ctrl+N)', 'Neuer Chat (Strg+N)'),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onNewChat,
              child: const Padding(padding: EdgeInsets.all(4), child: JuzzioLogoGlyph(size: 40)),
            ),
          ),
          const SizedBox(height: 26),
          for (var i = 0; i < items.length; i++) item(i),
          const Spacer(),
          Tooltip(
            message: userName.isEmpty ? app.trEn('Profil', 'Profile', 'Profil') : userName,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onProfileTap ?? () => onDestinationSelected(4),
              child: SizedBox(
                width: 46,
                height: 46,
                child: (userAvatarUrl ?? '').trim().isNotEmpty
                    ? JuzzioGlassAvatar(imageUrl: userAvatarUrl, name: userName, radius: 23)
                    : JuzzioLiquidGlass(
                        shape: BoxShape.circle,
                        blur: 0,
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JuzzioDesktopRightPlaceholder  (sağ panel yer tutucu)
// ---------------------------------------------------------------------------

/// Sağ panelde aktif konuşma yokken gösterilen hoş geldin ekranı.
class JuzzioDesktopRightPlaceholder extends StatelessWidget {
  const JuzzioDesktopRightPlaceholder({super.key, required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    // GM-028 (v2.2.0): Engin'in masaüstü tasarımı — gece: hilal-yıldız, yıldızlar, ışık yayı,
    // tepeler; gündüz: güneş, bulutlar, açık tepeler. Ortada yörüngeli sohbet simgesi.
    final app = JuzzioAppController.instance;
    final glow = JuzzioGlassTokens.glow;
    final dark = app.isDark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: JuzzioDesktopSceneBackdrop(dark: dark, accent: glow)),
        // GM-035: görseldeki yerleşim — panelin ortası, biraz yukarıda
        Align(
          alignment: const Alignment(0, -0.12),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JuzzioOrbitAppIcon(dark: dark, accent: glow),
                const SizedBox(height: 18),
                Text(
                  'Trawave',
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioGlassTokens.heading,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  app.trEn('Bir sohbet seçerek başlayın', 'Select a chat to start', 'Wähle einen Chat aus'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 18),
                ),
                const SizedBox(height: 26),
                Material(
                  key: const ValueKey('gm028-new-chat'),
                  color: glow,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onNewChat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: -6)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, color: JuzzioGlassTokens.onGlow, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            app.trEn('Yeni Sohbet', 'New Chat', 'Neuer Chat'),
                            style: TextStyle(color: JuzzioGlassTokens.onGlow, fontWeight: FontWeight.w800, fontSize: 17),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  app.trEn(
                    'Ctrl+K: Hızlı arama  •  Ctrl+N: Yeni sohbet',
                    'Ctrl+K: Quick search  •  Ctrl+N: New chat',
                    'Ctrl+K: Schnellsuche  •  Ctrl+N: Neuer Chat',
                  ),
                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// GM-028: yörünge halkalı, cam kare sohbet simgesi (gece halkanın ucunda hilal + yıldız)
class JuzzioOrbitAppIcon extends StatelessWidget {
  const JuzzioOrbitAppIcon({super.key, required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('gm028-orbit-icon'),
      width: 230,
      height: 180,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        // yörüngenin arka yarısı
        Positioned.fill(child: CustomPaint(painter: _OrbitPainter(accent: accent, dark: dark, front: false))),
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [const Color(0xFF3A3D42), const Color(0xFF15171A)]
                  : [const Color(0xFFFFFFFF), const Color(0xFFE6EAE0)],
            ),
            border: Border.all(color: dark ? const Color(0x33FFFFFF) : const Color(0x66FFFFFF)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.5 : 0.10), blurRadius: 30, offset: const Offset(0, 14)),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [Color.lerp(accent, Colors.black, 0.55)!, Color.lerp(accent, Colors.black, 0.78)!]
                    : [Color.lerp(accent, Colors.white, 0.55)!, Color.lerp(accent, Colors.white, 0.25)!],
              ),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: dark ? 0.35 : 0.45), blurRadius: 24, spreadRadius: -4)],
            ),
            child: Icon(Icons.chat_bubble_outline_rounded, color: dark ? accent : Color.lerp(accent, Colors.black, 0.55), size: 54),
          ),
        ),
        // yörüngenin ön yarısı (simgenin önünden geçer)
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _OrbitPainter(accent: accent, dark: dark, front: true)))),
      ]),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.accent, required this.dark, required this.front});
  final Color accent;
  final bool dark;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 4);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.42);
    final rect = Rect.fromCenter(center: Offset.zero, width: size.width * 0.98, height: size.height * 0.40);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = accent.withValues(alpha: dark ? 0.9 : 0.7);
    final glowP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = accent.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    // ön yarı: alt kısım (0..π), arka yarı: üst kısım (π..2π)
    final start = front ? 0.0 : math.pi;
    canvas.drawArc(rect, start, math.pi, false, glowP);
    canvas.drawArc(rect, start, math.pi, false, p);
    canvas.restore();
    if (!front && dark) {
      // halkanın sağ üst ucunda küçük hilal + yıldız (dönmüş elipsin noktası ekrana çevrilir)
      const rot = -0.42;
      final local = Offset(rect.width / 2 * math.cos(-0.5), rect.height / 2 * math.sin(-0.5));
      final mc = c + Offset(local.dx * math.cos(rot) - local.dy * math.sin(rot), local.dx * math.sin(rot) + local.dy * math.cos(rot)) +
          const Offset(-4, -12);
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: mc, radius: 11)),
        Path()..addOval(Rect.fromCircle(center: mc + const Offset(5, -3), radius: 9.5)),
      );
      canvas.drawPath(moon, Paint()..color = const Color(0xFFFFF7D6));
      final sc = mc + const Offset(14, -2);
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final rr = i.isEven ? 4.6 : 1.9;
        final ang = -math.pi / 2 + i * math.pi / 5;
        final pt = Offset(sc.dx + rr * math.cos(ang), sc.dy + rr * math.sin(ang));
        i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(star..close(), Paint()..color = const Color(0xFFFFF7D6));
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter o) => o.accent != accent || o.dark != dark || o.front != front;
}

/// GM-028 / GM-035 (v2.2.0): masaüstü sağ panel sahnesi — Engin'in görseline birebir:
/// gece: lacivert-antrasit gök, ince limon kenar ışıklı yumuşak hilal + mat yıldız,
/// sol üstten yükselen ipeksi ışık yayı, koyu HD bulutlar, kenarı yer yer limonla aydınlanan
/// modern kumul tepeler; gündüz: bulutların ardından doğan güneş, beyaz HD bulutlar, açık tepeler.
/// Ölçüler referans karesinden (sahne 1142×941) oranlanmıştır.
class JuzzioDesktopSceneBackdrop extends StatelessWidget {
  const JuzzioDesktopSceneBackdrop({super.key, required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  static const String _cloud = 'assets/weather_hd/cloud_white.webp';

  Widget _img(String a, double w, {double opacity = 1, Color? tint}) {
    Widget i = Image.asset(a, width: w, fit: BoxFit.contain, filterQuality: FilterQuality.high, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    if (tint != null) i = ColorFiltered(colorFilter: ColorFilter.mode(tint, BlendMode.modulate), child: i);
    return Opacity(opacity: opacity, child: i);
  }

  /// Paketteki bulutun bir kenarı düz kesik: aynası ile üst üste bindirilerek iki ucu da doğal,
  /// yumuşak bir bulut elde edilir (GM-037 kesik bulut kuralı).
  Widget _puff(double w, {required double opacity, Color? tint}) => SizedBox(
        width: w,
        height: w * 0.36,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 0, top: 0, child: _img(_cloud, w * 0.62, opacity: opacity, tint: tint)),
          Positioned(
              left: w * 0.38,
              top: w * 0.02,
              child: Transform.flip(flipX: true, child: _img(_cloud, w * 0.62, opacity: opacity, tint: tint))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        key: const ValueKey('gm028-scene'),
        builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final cloudTint = dark ? const Color(0xFF5E6675) : null;
          final cloudOp = dark ? 0.20 : 0.85;
          final moonR = h * 0.092;
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned.fill(child: CustomPaint(painter: JuzzioDesktopScenePainter(dark: dark, accent: accent))),
            if (dark) ...[
              Positioned(left: w * 0.06, top: h * 0.205, child: _puff(w * 0.13, opacity: cloudOp, tint: cloudTint)),
              Positioned(left: w * 0.78, top: h * 0.365, child: _puff(w * 0.19, opacity: cloudOp, tint: cloudTint)),
              Positioned(left: w * 0.03, top: h * 0.715, child: _puff(w * 0.13, opacity: cloudOp * 0.85, tint: cloudTint)),
              Positioned(
                key: const ValueKey('gm035-crescent'),
                left: w * 0.73 - moonR * 1.5,
                top: h * 0.165 - moonR * 1.5,
                child: SizedBox(
                    width: moonR * 3,
                    height: moonR * 3,
                    child: CustomPaint(painter: JuzzioCrescentPainter(rim: const Color(0xFFE4F0A0), glow: accent))),
              ),
              Positioned(
                left: w * 0.784 - h * 0.024,
                top: h * 0.136 - h * 0.024,
                child: SizedBox(width: h * 0.048, height: h * 0.048, child: const CustomPaint(painter: _MetalStarPainter())),
              ),
            ] else ...[
              // gündüz: güneş ressamda; güneşin altına binen bulut + dağınık yumuşak bulutlar
              Positioned(left: w * 0.055, top: h * 0.135, child: _puff(w * 0.17, opacity: 0.9)),
              Positioned(left: w * 0.565, top: h * 0.155, child: _puff(w * 0.22, opacity: 0.95)),
              Positioned(left: w * 0.75, top: h * 0.335, child: _puff(w * 0.20, opacity: 0.9)),
              Positioned(left: w * 0.06, top: h * 0.555, child: _puff(w * 0.16, opacity: 0.8)),
            ],
          ]);
        },
      ),
    );
  }
}

/// GM-035: referanstaki hilal — yarı saydam gri-mavi gövde, dış kenarında ince limon ışık,
/// sol altta yumuşak parıltı; iç (karanlık) taraf gökle aynı, beyaz zemin yok.
class JuzzioCrescentPainter extends CustomPainter {
  const JuzzioCrescentPainter({required this.rim, required this.glow});
  final Color rim;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 3;
    final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final innerC = c + Offset(r * 0.30, -r * 0.20);
    final inner = Path()..addOval(Rect.fromCircle(center: innerC, radius: r * 0.86));
    final crescent = Path.combine(PathOperation.difference, outer, inner);
    // ışığın geldiği yön: sol-alt (≈ 160°)
    final sweep = SweepGradient(
      center: Alignment.center,
      colors: [
        glow.withValues(alpha: 0),
        glow.withValues(alpha: 0.0),
        rim.withValues(alpha: 0.95),
        rim.withValues(alpha: 0.95),
        glow.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.25, 0.40, 0.56, 0.72],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    // 1) dış parıltı
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..shader = sweep
          ..color = glow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14));
    // 2) gövde: kenarda açık, içe doğru gök rengine karışan yarı saydam gri-mavi
    canvas.drawPath(
        crescent,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(-0.30 + 0.0, 0.20),
            radius: 0.95,
            colors: const [Color(0x33525C6C), Color(0x667A8494), Color(0x99A2AAB0)],
            stops: const [0.55, 0.85, 1.0],
          ).createShader(Rect.fromCircle(center: innerC, radius: r * 1.05)));
    // 3) ince ışık kenarı (yalnız hilal üzerinde)
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.2)), inner));
    canvas.drawCircle(
        c,
        r - 0.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.022)
          ..shader = sweep);
    canvas.restore();
    // 4) iç kenarda çok hafif soğuk çizgi (görseldeki ikinci, soluk kenar)
    canvas.save();
    canvas.clipPath(outer);
    canvas.drawCircle(
        innerC,
        r * 0.86,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x2EA9B4C2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(JuzzioCrescentPainter o) => o.rim != rim || o.glow != glow;
}

/// Görseldeki mat, hafif bombeli adaçayı-gri yıldız
class _MetalStarPainter extends CustomPainter {
  const _MetalStarPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final pts = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.46;
      final a = -math.pi / 2 + 0.22 + i * math.pi / 5;
      pts.add(Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a)));
    }
    for (var i = 0; i < 10; i++) {
      final tri = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(pts[i].dx, pts[i].dy)
        ..lineTo(pts[(i + 1) % 10].dx, pts[(i + 1) % 10].dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = i.isEven ? const Color(0xFFA3A898) : const Color(0xFF8A8F82));
    }
  }

  @override
  bool shouldRepaint(_MetalStarPainter o) => false;
}

class JuzzioDesktopScenePainter extends CustomPainter {
  JuzzioDesktopScenePainter({required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  /// Referans gök rengi (gece): lacivert-antrasit
  static const Color kNightSky = Color(0xFF181D27);

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, Paint()..color = color);
  }

  Path _ridge(Size s, List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx * s.width, pts.first.dy * s.height);
    for (var i = 1; i < pts.length; i++) {
      final a = Offset(pts[i - 1].dx * s.width, pts[i - 1].dy * s.height);
      final b = Offset(pts[i].dx * s.width, pts[i].dy * s.height);
      final mx = (a.dx + b.dx) / 2;
      p.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    return p;
  }

  /// Kumul tepe: gövde gökten çok az farklı; sırt çizgisi soluk gri-mavi, [litFrom..litTo] arasında
  /// vurgu renginde ince ışık + yumuşak parıltı (referanstaki gibi yalnız bir bölümü aydınlanır).
  void _dune(Canvas canvas, Size s, List<Offset> pts,
      {required Color top, required Color bottom, required double litFrom, required double litPeak, required double litTo, required double lit}) {
    final ridge = _ridge(s, pts);
    final body = Path.from(ridge)
      ..lineTo(pts.last.dx * s.width, s.height)
      ..lineTo(pts.first.dx * s.width, s.height)
      ..close();
    final yTop = pts.map((e) => e.dy).reduce(math.min) * s.height;
    canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])
              .createShader(Rect.fromLTRB(0, yTop, s.width, s.height)));
    final base = dark ? const Color(0xFF7C8698) : const Color(0xFFFFFFFF);
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = base.withValues(alpha: dark ? 0.16 : 0.55));
    if (lit <= 0) return;
    final along = LinearGradient(
      colors: [accent.withValues(alpha: 0), accent.withValues(alpha: lit), accent.withValues(alpha: 0)],
      stops: [litFrom, litPeak, litTo],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..shader = along
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = along);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    if (dark) {
      // referanstaki lacivert-antrasit gök (temanın zeminini hafifçe bu tona çeker)
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kNightSky.withValues(alpha: 0.78), const Color(0xFF161B25).withValues(alpha: 0.82)],
            ).createShader(Offset.zero & size));
    } else {
      // referanstaki açık gri-beyaz gök + yumuşak, ışınsız güneş diski (hâle ile)
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3E6E9EA), Color(0xB3EEEEEA)],
            ).createShader(Offset.zero & size));
      final sc = Offset(w * 0.743, h * 0.17);
      final sr = h * 0.06;
      canvas.drawCircle(
          sc,
          sr * 3.2,
          Paint()
            ..shader = RadialGradient(colors: [const Color(0xFFFFF7D6).withValues(alpha: 0.75), const Color(0xFFFFF7D6).withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: sc, radius: sr * 3.2)));
      canvas.drawCircle(
          sc,
          sr,
          Paint()
            ..shader = const RadialGradient(center: Alignment(-0.2, -0.25), colors: [Color(0xFFFFFDF0), Color(0xFFFCEFBE), Color(0xFFF7E3A0)], stops: [0.0, 0.7, 1.0])
                .createShader(Rect.fromCircle(center: sc, radius: sr))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, sr * 0.06));
    }
    // sol üstten yükselen ipeksi ışık yayı: geniş soluk bant + ortası limonla aydınlanan ince çizgi
    final arc = Path()
      ..moveTo(w * 0.05, h * 0.31)
      ..cubicTo(w * 0.22, h * 0.24, w * 0.40, h * 0.17, w * 0.53, -h * 0.01);
    final silk = Path()
      ..moveTo(w * 0.00, h * 0.36)
      ..cubicTo(w * 0.20, h * 0.26, w * 0.36, h * 0.14, w * 0.47, -h * 0.01);
    canvas.drawPath(
        silk,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.05
          ..color = (dark ? const Color(0xFF8C96A8) : Colors.white).withValues(alpha: dark ? 0.035 : 0.25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.03));
    final arcLit = LinearGradient(
      colors: [
        accent.withValues(alpha: 0),
        (dark ? accent : Colors.white).withValues(alpha: dark ? 0.55 : 0.9),
        (dark ? const Color(0xFF8C96A8) : Colors.white).withValues(alpha: dark ? 0.10 : 0.3),
      ],
      stops: const [0.10, 0.36, 0.62],
    ).createShader(Rect.fromLTWH(0, 0, w * 0.55, h * 0.31));
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..shader = arcLit
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..shader = arcLit);
    if (dark) {
      const spots = [Offset(0.22, 0.155), Offset(0.42, 0.24), Offset(0.62, 0.07), Offset(0.66, 0.39), Offset(0.20, 0.535), Offset(0.80, 0.61), Offset(0.90, 0.52)];
      for (final o in spots) {
        _sparkle(canvas, Offset(o.dx * w, o.dy * h), 4.5, const Color(0xFFB8C0CC).withValues(alpha: 0.55));
      }
    }
    // kumul tepeler (arkadan öne)
    final skyT = dark ? const Color(0xFF1A1F2B) : const Color(0xFFF1F2EE);
    final skyB = dark ? const Color(0xFF151A24) : const Color(0xFFE9ECE6);
    final front = dark ? const Color(0xFF131722) : const Color(0xFFEEF0EA);
    // sağ arka tepe: ortası limonla aydınlanır
    _dune(canvas, size, const [Offset(0.0, 0.99), Offset(0.45, 0.955), Offset(0.66, 0.85), Offset(0.88, 0.775), Offset(1.0, 0.77)],
        top: skyT, bottom: skyB, litFrom: 0.62, litPeak: 0.79, litTo: 0.95, lit: dark ? 0.75 : 0.6);
    // sol tepe
    _dune(canvas, size, const [Offset(0.0, 0.875), Offset(0.20, 0.838), Offset(0.40, 0.89), Offset(0.60, 0.965), Offset(1.0, 1.02)],
        top: skyT, bottom: skyB, litFrom: 0.20, litPeak: 0.33, litTo: 0.45, lit: dark ? 0.70 : 0.55);
    // orta tepe (yalnız soluk gri-mavi sırt)
    _dune(canvas, size, const [Offset(0.0, 1.02), Offset(0.38, 0.935), Offset(0.52, 0.875), Offset(0.70, 0.89), Offset(0.86, 0.94), Offset(1.0, 0.95)],
        top: front, bottom: front, litFrom: 0, litPeak: 0.5, litTo: 1, lit: 0);
    // en ön, koyu taban
    _dune(canvas, size, const [Offset(0.0, 0.97), Offset(0.35, 0.95), Offset(0.70, 0.985), Offset(1.0, 0.975)],
        top: front, bottom: front, litFrom: 0, litPeak: 0.5, litTo: 1, lit: 0);
  }

  @override
  bool shouldRepaint(JuzzioDesktopScenePainter o) => o.dark != dark || o.accent != accent;
}

// ---------------------------------------------------------------------------
// JuzzioCommandCenterOverlay  (Ctrl+K popup)
// ---------------------------------------------------------------------------

/// Ctrl+K ile tetiklenen hızlı arama/komut merkezi overlay'i.
Future<void> showJuzzioCommandCenter({
  required BuildContext context,
  required List<String> recentConversationNames,
  required void Function(String) onSelectConversation,
  required VoidCallback onNewChat,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _JuzzioCommandCenterDialog(
      recentConversationNames: recentConversationNames,
      onSelectConversation: onSelectConversation,
      onNewChat: onNewChat,
    ),
  );
}

class _JuzzioCommandCenterDialog extends StatefulWidget {
  const _JuzzioCommandCenterDialog({
    required this.recentConversationNames,
    required this.onSelectConversation,
    required this.onNewChat,
  });

  final List<String> recentConversationNames;
  final void Function(String) onSelectConversation;
  final VoidCallback onNewChat;

  @override
  State<_JuzzioCommandCenterDialog> createState() => _JuzzioCommandCenterDialogState();
}

class _JuzzioCommandCenterDialogState extends State<_JuzzioCommandCenterDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return widget.recentConversationNames.take(5).toList();
    final q = _query.toLowerCase();
    return widget.recentConversationNames
        .where((n) => n.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final border = JuzzioGlassTokens.spaceCardBorder;
    final surface = JuzzioGlassTokens.space.depth[1];
    final app = JuzzioAppController.instance;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 120),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 480),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.08), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Arama alanı
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: glow, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: app.trEn('Sohbet ara...', 'Search chats...', 'Chats suchen...'),
                        hintStyle: TextStyle(color: JuzzioGlassTokens.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded, color: JuzzioGlassTokens.textSecondary, size: 18),
                  ),
                ],
              ),
            ),
            Divider(color: border, height: 1),
            // Sonuçlar
            if (_filtered.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final name = _filtered[i];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSelectConversation(name);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: glow.withValues(alpha: 0.15),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(color: glow, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(name, style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  app.trEn('Sonuç bulunamadı', 'No results', 'Keine Ergebnisse'),
                  style: TextStyle(color: JuzzioGlassTokens.textSecondary),
                ),
              ),
            Divider(color: border, height: 1),
            // Yeni sohbet
            InkWell(
              onTap: () {
                Navigator.pop(context);
                widget.onNewChat();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, color: glow, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      app.trEn('Yeni sohbet aç', 'Open new chat', 'Neuen Chat öffnen'),
                      style: TextStyle(color: glow, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: glow.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Ctrl+N', style: TextStyle(color: glow, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JuzzioLogoMark — Juzzio 2.0 marka işareti (NavigationRail ve splash için)
// ---------------------------------------------------------------------------

class JuzzioLogoMark extends StatelessWidget {
  const JuzzioLogoMark({super.key, this.size = 40, this.glowColor});
  final double size;
  final Color? glowColor;

  // v2.1: yeni marka — kodla çizilen yeşil şerit "J" (uygulama ikonuyla aynı)
  @override
  Widget build(BuildContext context) => JuzzioLogoTile(size: size);
}
