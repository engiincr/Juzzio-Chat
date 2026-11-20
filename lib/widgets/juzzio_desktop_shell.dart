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
    // Sağ panelin genişliği: kalan alanın ~%45'i, en az 300, en fazla 540 px.
    final rightWidth = ((size.width - kJuzzioNavRailWidth - kJuzzioCenterPanelMinWidth) * 0.65)
        .clamp(300.0, 540.0);

    return Row(
      children: [
        // Sol kenar çubuğu
        SizedBox(
          width: kJuzzioNavRailWidth,
          child: navRail,
        ),
        // Orta/merkez panel
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: border),
                right: BorderSide(color: border),
              ),
            ),
            child: center,
          ),
        ),
        // Sağ panel
        SizedBox(
          width: rightWidth,
          child: right,
        ),
      ],
    );
  }
}

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
  });

  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final VoidCallback onNewChat;
  final int unreadBadge;

  @override
  Widget build(BuildContext context) {
    final glow = JuzzioGlassTokens.glow;
    final depthColors = JuzzioGlassTokens.space.depth;
    final bg = depthColors[0];
    final app = JuzzioAppController.instance;

    final destinations = [
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: unreadBadge > 0,
          label: Text('$unreadBadge', style: const TextStyle(fontSize: 10)),
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        selectedIcon: const Icon(Icons.chat_bubble_rounded),
        label: Text(app.trEn('Sohbet', 'Chats', 'Chats')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore_rounded),
        label: Text(app.trEn('Keşfet', 'Explore', 'Erkunden')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.call_outlined),
        selectedIcon: const Icon(Icons.call_rounded),
        label: Text(app.trEn('Aramalar', 'Calls', 'Anrufe')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.notifications_none_rounded),
        selectedIcon: const Icon(Icons.notifications_rounded),
        label: Text(app.trEn('Bildirim', 'Alerts', 'Infos')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: Text(app.trEn('Profil', 'Profile', 'Profil')),
      ),
    ];

    return Container(
      color: bg,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: JuzzioLogoMark(size: 40, glowColor: glow),
          ),
          // Yeni sohbet butonu
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Tooltip(
              message: app.trEn('Yeni Sohbet (Ctrl+N)', 'New Chat (Ctrl+N)', 'Neuer Chat (Ctrl+N)'),
              child: InkWell(
                onTap: onNewChat,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: glow.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: glow.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.edit_rounded, color: glow, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Nav rail
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.none,
              backgroundColor: Colors.transparent,
              indicatorColor: glow.withValues(alpha: 0.18),
              selectedIconTheme: IconThemeData(color: glow, size: 24),
              unselectedIconTheme: IconThemeData(color: glow.withValues(alpha: 0.5), size: 22),
              destinations: destinations,
            ),
          ),
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
    final glow = JuzzioGlassTokens.glow;
    final app = JuzzioAppController.instance;
    final bg = JuzzioGlassTokens.space.depth;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg[0], bg[1]],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: glow.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: glow.withValues(alpha: 0.25), width: 1.5),
              ),
              child: Icon(Icons.chat_bubble_outline_rounded, color: glow, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              app.trEn('Juzzio 2.0', 'Juzzio 2.0', 'Juzzio 2.0'),
              style: TextStyle(
                color: glow,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              app.trEn(
                'Bir sohbet seçerek başlayın',
                'Select a chat to start',
                'Wähle einen Chat aus',
              ),
              style: TextStyle(
                color: JuzzioGlassTokens.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onNewChat,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: glow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_rounded, color: Color(0xFF080A0F), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      app.trEn('Yeni Sohbet', 'New Chat', 'Neuer Chat'),
                      style: const TextStyle(
                        color: Color(0xFF080A0F),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
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
              style: TextStyle(
                color: JuzzioGlassTokens.textSecondary.withValues(alpha: 0.6),
                fontSize: 11,
              ),
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

  @override
  Widget build(BuildContext context) {
    final lime = glowColor ?? JuzzioGlassTokens.glow;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: lime,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(color: lime.withValues(alpha: 0.35), blurRadius: size * 0.6, spreadRadius: -2),
        ],
      ),
      child: Center(
        child: Text(
          'J',
          style: TextStyle(
            color: const Color(0xFF080A0F),
            fontSize: size * 0.56,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}
