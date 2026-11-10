// =============================================================================
// JUZZIO v1.2.0 — Kilitli sohbetler (tamamlandı)
//  Önceden "Kilitli sohbetler"e dokunmak, PIN henüz yoksa sessizce hiçbir şey yapmıyordu.
//  Artık ayrı bir sayfa:
//   • PIN yoksa: ne işe yaradığı anlatılır ve PIN oluşturulur.
//   • PIN varsa: PIN ile açılır; kilitli sohbetler listelenir, dokununca açılır.
//   • "Sohbet kilitle": listeden sohbet seçip doğrudan kilitleme; her satırda kilit kaldırma.
//   • Kilitleme bildirim önizlemesini sunucuda 'gizli' yapar (tüm cihazlarda).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_chat_lock.dart';
import '../services/supabase_service.dart';
import '../widgets/chat_lock_ui.dart';
import '../widgets/juzzio_motion.dart';
import '../widgets/juzzio_space_kit.dart';

class JuzzioLockedChatsPage extends StatefulWidget {
  const JuzzioLockedChatsPage({super.key, required this.conversations, required this.onOpen});

  final List<JuzzioConversation> conversations;
  final void Function(JuzzioConversation c) onOpen;

  @override
  State<JuzzioLockedChatsPage> createState() => _JuzzioLockedChatsPageState();
}

class _JuzzioLockedChatsPageState extends State<JuzzioLockedChatsPage> {
  final _app = JuzzioAppController.instance;
  final _lock = JuzzioChatLock.instance;
  bool _checking = true;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_lock.loaded) await _lock.load();
    final has = await _lock.hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _checking = false;
    });
    if (has && !_lock.isUnlocked) await _unlock();
  }

  Future<void> _unlock({bool create = false}) async {
    final ok = await juzzioRequireChatPin(context, allowCreate: create);
    if (!mounted) return;
    final has = await _lock.hasPin();
    if (!mounted) return;
    setState(() => _hasPin = has);
    if (ok) JuzzioHaptics.success();
  }

  String _title(JuzzioConversation c) => c.isGroup ? c.title : (c.partnerDisplayName ?? c.partnerUsername ?? c.title);
  String? _avatar(JuzzioConversation c) => c.isGroup ? c.avatarUrl : c.partnerAvatarUrl;

  Future<void> _setLocked(JuzzioConversation c, bool lock) async {
    await _lock.setLocked(c.roomId, lock);
    try {
      await SupabaseService.instance.setRoomNotificationPrefs(c.roomId, preview: lock ? 'hidden' : 'inherit');
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _pickToLock() async {
    final p = JuzzioPalette(_app.isDark);
    final candidates = widget.conversations.where((c) => !_lock.isLocked(c.roomId)).toList();
    final picked = await showJuzzioSheet<JuzzioConversation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: Column(children: [
            const SizedBox(height: 14),
            Text(_app.trEn('Kilitlenecek sohbeti seç', 'Choose a chat to lock', 'Chat zum Sperren wählen'),
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            Expanded(
              child: candidates.isEmpty
                  ? Center(child: Text(_app.trEn('Kilitlenecek sohbet yok', 'No chats to lock', 'Keine Chats'), style: TextStyle(color: p.textSecondary)))
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final c in candidates)
                        ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: JuzzioSpacePhoto(url: _avatar(c), name: _title(c), size: 42),
                          ),
                          title: Text(_title(c), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                          trailing: Icon(Icons.lock_outline_rounded, color: p.textSecondary),
                          onTap: () => Navigator.pop(ctx, c),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
    if (picked != null) await _setLocked(picked, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    return ListenableBuilder(
      listenable: _lock,
      builder: (context, _) {
        final unlocked = _hasPin && _lock.isUnlocked;
        final locked = widget.conversations.where((c) => _lock.isLocked(c.roomId)).toList();
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(_app.trEn('Kilitli sohbetler', 'Locked chats', 'Gesperrte Chats'),
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900)),
          ),
          floatingActionButton: unlocked
              ? FloatingActionButton.extended(
                  onPressed: _pickToLock,
                  backgroundColor: JuzzioGlassTokens.accentFill,
                  foregroundColor: JuzzioGlassTokens.onAccent,
                  icon: const Icon(Icons.lock_rounded),
                  label: Text(_app.trEn('Sohbet kilitle', 'Lock a chat', 'Chat sperren'), style: const TextStyle(fontWeight: FontWeight.w800)),
                )
              : null,
          body: _checking
              ? const Center(child: JuzzioOrbitLoader())
              : !unlocked
                  ? _gate(p)
                  : locked.isEmpty
                      ? _empty(p)
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                          for (final c in locked)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: JuzzioGlassTokens.surfaceStrong,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: JuzzioGlassTokens.border),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: JuzzioSpacePhoto(url: _avatar(c), name: _title(c), size: 46),
                                ),
                                title: Text(_title(c), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
                                subtitle: Text(
                                  c.unreadCount > 0
                                      ? _app.trEn('${c.unreadCount} okunmamış mesaj', '${c.unreadCount} unread', '${c.unreadCount} ungelesen')
                                      : _app.trEn('Kilitli · bildirim içeriği gizli', 'Locked · notification content hidden', 'Gesperrt · Inhalt verborgen'),
                                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                                ),
                                trailing: IconButton(
                                  tooltip: _app.trEn('Kilidi kaldır', 'Unlock chat', 'Entsperren'),
                                  icon: Icon(Icons.lock_open_rounded, color: p.textSecondary),
                                  onPressed: () => _setLocked(c, false),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onOpen(c);
                                },
                              ),
                            ),
                        ]),
        );
      },
    );
  }

  Widget _gate(JuzzioPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [JuzzioGlassTokens.glow, JuzzioGlassTokens.glow.withValues(alpha: 0.4)]),
                boxShadow: [BoxShadow(color: JuzzioGlassTokens.glow.withValues(alpha: 0.4), blurRadius: 24)],
              ),
              child: Icon(Icons.lock_person_rounded, size: 40, color: JuzzioGlassTokens.onAccent),
            ),
            const SizedBox(height: 18),
            Text(
              _hasPin
                  ? _app.trEn('Kilitli sohbetlerini görmek için PIN gir', 'Enter your PIN to see locked chats', 'PIN eingeben')
                  : _app.trEn('Özel sohbetlerini PIN ile kilitle', 'Lock private chats with a PIN', 'Private Chats mit PIN sperren'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _app.trEn('Kilitli sohbetler listede görünmez, yalnız bu sayfadan PIN ile açılır ve bildirimlerde içerik gösterilmez.',
                  'Locked chats are hidden from the list, open only here with your PIN, and their notifications hide the content.',
                  'Gesperrte Chats sind verborgen und öffnen nur mit PIN.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: JuzzioGlassTokens.accentFill,
                foregroundColor: JuzzioGlassTokens.onAccent,
                minimumSize: const Size(220, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _unlock(create: !_hasPin),
              icon: Icon(_hasPin ? Icons.lock_open_rounded : Icons.password_rounded),
              label: Text(_hasPin ? _app.trEn('PIN ile aç', 'Unlock with PIN', 'Mit PIN öffnen') : _app.trEn('PIN oluştur', 'Create PIN', 'PIN erstellen'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );

  Widget _empty(JuzzioPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 56, color: p.textSecondary.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(_app.trEn('Henüz kilitli sohbet yok', 'No locked chats yet', 'Noch keine gesperrten Chats'),
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              _app.trEn('"Sohbet kilitle" ile buradan ya da sohbet bilgileri → Gizlilik → "Sohbeti Kilitle" ile kilitleyebilirsin.',
                  'Use "Lock a chat" here, or Chat info → Privacy → "Lock chat".', 'Hier „Chat sperren“ oder in den Chat-Infos.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, height: 1.4),
            ),
          ]),
        ),
      );
}
