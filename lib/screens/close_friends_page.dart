// =============================================================================
// JUZZIO v0.7.0 — Yakın arkadaşlar (favori arkadaşlar)
//  Hikâyeyi "Yakın arkadaşlar" ile paylaştığında yalnızca bu listedekiler görür.
//  Liste yalnızca sana görünür; eklenen kişiye bildirim gitmez.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';

class JuzzioCloseFriendsService {
  JuzzioCloseFriendsService._();
  static final JuzzioCloseFriendsService instance = JuzzioCloseFriendsService._();

  Future<Set<String>> fetchIds() async {
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return <String>{};
    final rows = await svc.client.from('close_friends').select('friend_id').eq('owner_id', uid);
    return {for (final r in rows) (r['friend_id'] ?? '').toString()}..remove('');
  }

  Future<void> setCloseFriend(String friendId, bool value) async {
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return;
    if (value) {
      await svc.client.from('close_friends').upsert({'owner_id': uid, 'friend_id': friendId});
    } else {
      await svc.client.from('close_friends').delete().eq('owner_id', uid).eq('friend_id', friendId);
    }
  }
}

class JuzzioCloseFriendsPage extends StatefulWidget {
  const JuzzioCloseFriendsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioCloseFriendsPage()));

  @override
  State<JuzzioCloseFriendsPage> createState() => _JuzzioCloseFriendsPageState();
}

class _JuzzioCloseFriendsPageState extends State<JuzzioCloseFriendsPage> {
  final _app = JuzzioAppController.instance;
  List<JuzzioUserProfile> _friends = const [];
  Set<String> _close = <String>{};
  bool _loading = true;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([
        SupabaseService.instance.fetchAcceptedFriendProfiles(),
        JuzzioCloseFriendsService.instance.fetchIds(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = res[0] as List<JuzzioUserProfile>;
        _close = res[1] as Set<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  Future<void> _toggle(JuzzioUserProfile f) async {
    HapticFeedback.selectionClick();
    final next = !_close.contains(f.id);
    setState(() => next ? _close.add(f.id) : _close.remove(f.id));
    try {
      await JuzzioCloseFriendsService.instance.setCloseFriend(f.id, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => next ? _close.remove(f.id) : _close.add(f.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final q = _q.trim().toLowerCase();
    final list = _friends
        .where((f) => q.isEmpty || f.displayName.toLowerCase().contains(q) || f.username.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final ca = _close.contains(a.id) ? 0 : 1;
        final cb = _close.contains(b.id) ? 0 : 1;
        return ca != cb ? ca - cb : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    const star = Color(0xFF34C759);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Yakın arkadaşlar', 'Close friends', 'Enge Freunde'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          JuzzioGlass(
            radius: 22,
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.stars_rounded, color: star),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _app.trEn(
                      'Hikâyeni "Yakın arkadaşlar" ile paylaşırsan yalnızca bu listedekiler görür; diğer arkadaşların ve herkes göremez. Liste yalnızca sana görünür, eklenen kişiye bildirim gitmez.',
                      'Stories shared with "Close friends" are visible only to people on this list — hidden from your other friends and everyone else. Only you can see the list; nobody is notified.',
                      'Mit „Enge Freunde" geteilte Storys sehen nur Personen auf dieser Liste. Nur du siehst die Liste; niemand wird benachrichtigt.',
                    ),
                    style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: p.inputBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.glassBorder),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: TextStyle(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: _app.trEn('Arkadaş ara', 'Search friends', 'Freunde suchen'),
                hintStyle: TextStyle(color: p.textMuted),
                prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              _app.trEn('${_close.length} kişi seçili', '${_close.length} selected', '${_close.length} ausgewählt'),
              style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: TextStyle(color: p.dangerRed)),
          if (!_loading && _friends.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_app.trEn('Henüz arkadaşın yok.', 'You have no friends yet.', 'Noch keine Freunde.'),
                  textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
            ),
          for (final f in list)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              onTap: () => _toggle(f),
              leading: JuzzioGlassAvatar(
                imageUrl: f.avatarUrl,
                name: f.displayName,
                radius: 22,
                ringColor: _close.contains(f.id) ? star : null,
              ),
              title: Text(f.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
              subtitle: Text('@${f.username}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  _close.contains(f.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(_close.contains(f.id)),
                  color: _close.contains(f.id) ? star : p.textMuted,
                  size: 26,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
