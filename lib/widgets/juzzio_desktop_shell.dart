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

    return Row(
      children: [
        // Sol kenar çubuğu
        SizedBox(
          width: kJuzzioNavRailWidth,
          child: navRail,
        ),
        // Sohbet listesi (cam panel)
        SizedBox(
          width: listWidth,
          child: JuzzioLiquidGlass(
            radius: 0,
            blur: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: border))),
              child: center,
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
    return JuzzioLiquidGlass(
      radius: 0,
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
    // GM-014 (KR-010): sabit koyu zemin ve sabit renkler kaldırıldı — açık temada da
    // sayfanın tema zemini (aurora) görünür; yazı ve düğme renkleri tema belirteçlerinden.
    final app = JuzzioAppController.instance;
    final glow = JuzzioGlassTokens.glow;
    final glowText = JuzzioGlassTokens.glowText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: glow.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: glow.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded, color: glowText, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Juzzio',
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: JuzzioGlassTokens.heading,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              app.trEn('Bir sohbet seçerek başlayın', 'Select a chat to start', 'Wähle einen Chat aus'),
              textAlign: TextAlign.center,
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Material(
              color: glow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onNewChat,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded, color: JuzzioGlassTokens.onGlow, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        app.trEn('Yeni Sohbet', 'New Chat', 'Neuer Chat'),
                        style: TextStyle(color: JuzzioGlassTokens.onGlow, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              app.trEn(
                'Ctrl+K: Hızlı arama • Ctrl+N: Yeni sohbet',
                'Ctrl+K: Quick search • Ctrl+N: New chat',
                'Ctrl+K: Schnellsuche • Ctrl+N: Neuer Chat',
              ),
              style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
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
