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
import 'dart:ui' show ImageFilter;

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
/// gece: gerçek (fotoğraf dokulu) hilal + sıcak parıltı, metalik yıldız, yumuşak HD bulutlar,
/// sol üstten yükselen ince ışık yayı, vurgu renginde parlayan modern tepe sırtları;
/// gündüz: bulutların ardından doğan güneş, beyaz HD bulutlar, açık tepeler.
class JuzzioDesktopSceneBackdrop extends StatelessWidget {
  const JuzzioDesktopSceneBackdrop({super.key, required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  static const String _moon = 'assets/weather_hd/moon_7_waning_crescent.webp';
  static const String _cloud = 'assets/weather_hd/cloud_white.webp';
  static const String _sun = 'assets/weather_hd/sun_rise_clouds.webp';

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
          final m = math.min(w, h);
          final cloudTint = dark ? const Color(0xFF6B7380) : null;
          final cloudOp = dark ? 0.16 : 0.85;
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned.fill(child: CustomPaint(painter: JuzzioDesktopScenePainter(dark: dark, accent: accent))),
            Positioned(left: w * 0.02, top: h * 0.17, child: _puff(w * 0.26, opacity: cloudOp * 0.9, tint: cloudTint)),
            Positioned(right: -w * 0.04, top: h * 0.36, child: _puff(w * 0.30, opacity: cloudOp, tint: cloudTint)),
            Positioned(left: w * 0.03, top: h * 0.68, child: _puff(w * 0.22, opacity: cloudOp * 0.8, tint: cloudTint)),
            if (dark) ...[
              // hilalin sıcak parıltısı: aynı şeklin bulanık kopyası (kare gölge değil)
              Positioned(
                right: w * 0.075 - m * 0.02,
                top: h * 0.06 - m * 0.02,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: m * 0.025, sigmaY: m * 0.025),
                  child: _img(_moon, m * 0.24 + m * 0.04, tint: const Color(0xFFF4F1B0), opacity: 0.55),
                ),
              ),
              Positioned(right: w * 0.075, top: h * 0.06, child: _img(_moon, m * 0.24)),
              Positioned(
                right: w * 0.045,
                top: h * 0.10,
                child: SizedBox(width: m * 0.07, height: m * 0.07, child: const CustomPaint(painter: _MetalStarPainter())),
              ),
            ] else
              Positioned(right: w * 0.02, top: h * 0.02, child: _img(_sun, m * 0.46)),
          ]);
        },
      ),
    );
  }
}

/// Görseldeki gri, eğimli (bombeli) yıldız
class _MetalStarPainter extends CustomPainter {
  const _MetalStarPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final pts = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      pts.add(Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a)));
    }
    // her kol iki yüz: açık ve koyu (bombeli görünüm)
    for (var i = 0; i < 10; i++) {
      final tri = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(pts[i].dx, pts[i].dy)
        ..lineTo(pts[(i + 1) % 10].dx, pts[(i + 1) % 10].dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = i.isEven ? const Color(0xFF9EA2A6) : const Color(0xFF6E7378));
    }
  }

  @override
  bool shouldRepaint(_MetalStarPainter o) => false;
}

class JuzzioDesktopScenePainter extends CustomPainter {
  JuzzioDesktopScenePainter({required this.dark, required this.accent});
  final bool dark;
  final Color accent;

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Yumuşak tepe sırtı: (x0,y0) → (x1,y1) arası pürüzsüz eğri, iki kontrol noktasıyla
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

  void _hill(Canvas canvas, Size s, List<Offset> pts, {required List<Color> fill, required double rim, required double peakX}) {
    final ridge = _ridge(s, pts);
    final body = Path.from(ridge)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    final top = pts.map((e) => e.dy).reduce(math.min) * s.height;
    canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill)
              .createShader(Rect.fromLTRB(0, top, s.width, s.height)));
    if (rim <= 0) return;
    // ışık sırtı: tepede en parlak, kenarlara doğru söner (görseldeki modern parıltı)
    final along = LinearGradient(
      colors: [accent.withValues(alpha: 0), accent.withValues(alpha: rim), accent.withValues(alpha: 0)],
      stops: [math.max(0, peakX - 0.38), peakX, math.min(1, peakX + 0.38)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..shader = along
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = along);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    // sol üstten yükselen ince ışık yayı
    final arc = Path()
      ..moveTo(w * 0.04, h * 0.40)
      ..quadraticBezierTo(w * 0.30, h * 0.16, w * 0.62, -h * 0.02);
    final arcShader = LinearGradient(
      colors: [accent.withValues(alpha: 0), (dark ? accent : Colors.white).withValues(alpha: dark ? 0.45 : 0.9)],
    ).createShader(Rect.fromLTWH(0, 0, w * 0.62, h * 0.4));
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..shader = arcShader
          ..color = Colors.white.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = arcShader);
    if (dark) {
      final rnd = math.Random(11);
      for (var i = 0; i < 14; i++) {
        _sparkle(canvas, Offset(rnd.nextDouble() * w, rnd.nextDouble() * h * 0.7), 2 + rnd.nextDouble() * 3,
            Colors.white.withValues(alpha: 0.22 + rnd.nextDouble() * 0.3));
      }
    }
    // tepeler: arkadan öne üç katman; orta sırtta vurgu renginde parlayan ışık
    final base = dark ? const Color(0xFF15181C) : const Color(0xFFEFF3E6);
    final deep = dark ? const Color(0xFF0C0E11) : const Color(0xFFE2E9D6);
    _hill(canvas, size, const [Offset(0, 0.86), Offset(0.30, 0.80), Offset(0.62, 0.88), Offset(1, 0.84)],
        fill: [base.withValues(alpha: 0.55), deep.withValues(alpha: 0.65)], rim: dark ? 0.18 : 0.25, peakX: 0.30);
    _hill(canvas, size, const [Offset(0, 0.93), Offset(0.40, 0.90), Offset(0.78, 0.84), Offset(1, 0.80)],
        fill: [base.withValues(alpha: 0.85), deep], rim: dark ? 0.75 : 0.65, peakX: 0.86);
    _hill(canvas, size, const [Offset(0, 0.90), Offset(0.22, 0.94), Offset(0.55, 0.985), Offset(1, 0.97)],
        fill: [deep, deep], rim: dark ? 0.30 : 0.35, peakX: 0.12);
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
