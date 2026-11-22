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
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JuzzioOrbitAppIcon(dark: dark, accent: glow),
                const SizedBox(height: 18),
                Text(
                  'Juzzio',
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

/// GM-028: masaüstü sağ panel sahnesi (gece: hilal-yıldız, yıldızlar, ışık yayı, tepeler;
/// gündüz: güneş, bulutlar, açık tepeler). Saf çizim; görsel dosyası yok.
class JuzzioDesktopSceneBackdrop extends StatelessWidget {
  const JuzzioDesktopSceneBackdrop({super.key, required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(key: const ValueKey('gm028-scene'), painter: JuzzioDesktopScenePainter(dark: dark, accent: accent)));
}

class JuzzioDesktopScenePainter extends CustomPainter {
  JuzzioDesktopScenePainter({required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  void _cloud(Canvas canvas, Offset at, double s, Color color) {
    final p = Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06);
    final path = Path()
      ..addOval(Rect.fromCenter(center: at + Offset(-s * 0.55, s * 0.08), width: s * 0.9, height: s * 0.42))
      ..addOval(Rect.fromCenter(center: at + Offset(-s * 0.15, -s * 0.12), width: s * 0.75, height: s * 0.62))
      ..addOval(Rect.fromCenter(center: at + Offset(s * 0.3, -s * 0.02), width: s * 0.8, height: s * 0.5))
      ..addOval(Rect.fromCenter(center: at + Offset(s * 0.65, s * 0.1), width: s * 0.7, height: s * 0.34));
    canvas.drawPath(path, p);
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    // ışık yayı (sol üstten sağa kıvrılan ince parıltı)
    final arc = Path()
      ..moveTo(w * 0.02, h * 0.30)
      ..quadraticBezierTo(w * 0.35, h * 0.12, w * 0.60, -h * 0.02);
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..color = (dark ? accent : Colors.white).withValues(alpha: dark ? 0.06 : 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = (dark ? accent : Colors.white).withValues(alpha: dark ? 0.45 : 0.9));
    if (dark) {
      // yıldızlar
      final rnd = math.Random(11);
      for (var i = 0; i < 16; i++) {
        _sparkle(canvas, Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * 0.7), 2 + rnd.nextDouble() * 3,
            Colors.white.withValues(alpha: 0.25 + rnd.nextDouble() * 0.35));
      }
      // hilal + yıldız (sağ üst, ince ışıklı kenar)
      final mc = Offset(w * 0.86, h * 0.16);
      final mr = math.min(w, h) * 0.085;
      final crescent = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: mc, radius: mr)),
        Path()..addOval(Rect.fromCircle(center: mc + Offset(mr * 0.36, -mr * 0.12), radius: mr * 0.86)),
      );
      canvas.drawPath(
          crescent,
          Paint()
            ..color = const Color(0xFFFFF4C2).withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.drawPath(crescent, Paint()..color = const Color(0xFF2A2C25));
      canvas.drawPath(
          crescent,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = const Color(0xFFE9F5A6).withValues(alpha: 0.85));
      final star = Path();
      final sc = mc + Offset(mr * 1.2, -mr * 0.35);
      final sr = mr * 0.30;
      for (var i = 0; i < 10; i++) {
        final rr = i.isEven ? sr : sr * 0.42;
        final a = -math.pi / 2 + i * math.pi / 5;
        final pt = Offset(sc.dx + rr * math.cos(a), sc.dy + rr * math.sin(a));
        i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
      }
      star.close();
      canvas.drawPath(star, Paint()..color = const Color(0xFF8D9188));
      // ince bulutlar
      _cloud(canvas, Offset(w * 0.18, h * 0.26), w * 0.09, Colors.white.withValues(alpha: 0.05));
      _cloud(canvas, Offset(w * 0.90, h * 0.42), w * 0.10, Colors.white.withValues(alpha: 0.05));
      _cloud(canvas, Offset(w * 0.16, h * 0.76), w * 0.08, Colors.white.withValues(alpha: 0.04));
    } else {
      // güneş + hale
      final sc = Offset(w * 0.86, h * 0.17);
      final sr = math.min(w, h) * 0.075;
      canvas.drawCircle(sc, sr * 3.2, Paint()..shader = RadialGradient(colors: [const Color(0x66FFF3B0), const Color(0x00FFF3B0)]).createShader(Rect.fromCircle(center: sc, radius: sr * 3.2)));
      canvas.drawCircle(sc, sr, Paint()..color = const Color(0xFFFFF1B8));
      _cloud(canvas, Offset(w * 0.80, h * 0.22), w * 0.10, Colors.white.withValues(alpha: 0.95));
      _cloud(canvas, Offset(w * 0.20, h * 0.18), w * 0.07, Colors.white.withValues(alpha: 0.85));
      _cloud(canvas, Offset(w * 0.93, h * 0.38), w * 0.08, Colors.white.withValues(alpha: 0.85));
      _cloud(canvas, Offset(w * 0.18, h * 0.58), w * 0.07, Colors.white.withValues(alpha: 0.75));
    }
    // tepeler (üç katman, üstte vurgu renginde ince ışık kenarı)
    void hill(double y0, double amp, double phase, Color fill, double rimAlpha) {
      final path = Path()..moveTo(0, h);
      path.lineTo(0, h * y0);
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final x = w * i / steps;
        final y = h * y0 - math.sin(i / steps * math.pi * 1.6 + phase) * h * amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = fill);
      final rim = Path()..moveTo(0, h * y0 - math.sin(phase) * h * amp);
      for (var i = 0; i <= steps; i++) {
        final x = w * i / steps;
        rim.lineTo(x, h * y0 - math.sin(i / steps * math.pi * 1.6 + phase) * h * amp);
      }
      canvas.drawPath(
          rim,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = accent.withValues(alpha: rimAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
    }

    if (dark) {
      hill(0.86, 0.05, 0.6, const Color(0xFF16181A).withValues(alpha: 0.85), 0.18);
      hill(0.90, 0.07, 2.4, const Color(0xFF111315).withValues(alpha: 0.92), 0.55);
    } else {
      hill(0.84, 0.05, 0.6, Colors.white.withValues(alpha: 0.55), 0.25);
      hill(0.89, 0.07, 2.4, const Color(0xFFF3F6EC).withValues(alpha: 0.85), 0.6);
    }
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
