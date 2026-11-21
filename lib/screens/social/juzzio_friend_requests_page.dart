// =============================================================================
// JUZZIO 2.1 — Arkadaşlık İstekleri (tasarım: "ARKADAŞLIK İSTEKLERİ")
//  • Gelen / Gönderilen hap sekmeleri (sayılı)
//  • Satır: avatar (çevrimiçi noktası) · ad · mavi tik · @kullanıcı adı · "N ortak arkadaş"
//    · Kabul Et (limon) / Reddet — gönderilenlerde "Geri Çek"
//  • Altta: Tümünü Kabul Et · Arkadaşlarımı Bul
//  Veriler canlı arkadaşlık akışından gelir (RLS: yalnız kişinin kendi kayıtları).
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/supabase_service.dart';
import '../../widgets/juzzio_brand.dart';
import '../../widgets/juzzio_neon_kit.dart';
import '../../widgets/social_common_widgets.dart';

class JuzzioFriendRequestsPage extends StatefulWidget {
  const JuzzioFriendRequestsPage({
    super.key,
    required this.respond,
    required this.onFindFriends,
    this.verifiedIds = const {},
    this.onlineIds = const {},
  });

  /// chat_screen içindeki mevcut kabul/ret akışı (bildirim, sayaç güncellemesi orada)
  final Future<void> Function(JuzzioFriendship req, bool accept) respond;
  final VoidCallback onFindFriends;
  final Set<String> verifiedIds;
  final Set<String> onlineIds;

  @override
  State<JuzzioFriendRequestsPage> createState() => _JuzzioFriendRequestsPageState();
}

class _JuzzioFriendRequestsPageState extends State<JuzzioFriendRequestsPage> {
  final _app = JuzzioAppController.instance;
  StreamSubscription<List<JuzzioFriendship>>? _sub;
  List<JuzzioFriendship> _all = const [];
  Map<String, int> _mutual = const {};
  final Set<String> _busy = {};
  int _tab = 0;
  bool _loaded = false;

  String get _me => SupabaseService.instance.currentUserId ?? '';

  List<JuzzioFriendship> get _incoming => _all.where((f) => f.receiverId == _me && f.status == 'pending').toList();
  List<JuzzioFriendship> get _outgoing => _all.where((f) => f.requesterId == _me && f.status == 'pending').toList();

  @override
  void initState() {
    super.initState();
    _sub = SupabaseService.instance.watchFriendships().listen((rows) {
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loaded = true;
      });
      _loadMutual();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadMutual() async {
    final ids = <String>{
      for (final f in _incoming) f.requesterId,
      for (final f in _outgoing) f.receiverId,
    }.where((e) => !_mutual.containsKey(e)).toList();
    if (ids.isEmpty) return;
    final m = await SupabaseService.instance.mutualFriendCounts(ids);
    if (!mounted || m.isEmpty) return;
    setState(() => _mutual = {..._mutual, ...m});
  }

  Future<void> _answer(JuzzioFriendship f, bool accept) async {
    if (_busy.contains(f.id)) return;
    setState(() => _busy.add(f.id));
    try {
      await widget.respond(f, accept);
    } finally {
      if (mounted) setState(() => _busy.remove(f.id));
    }
  }

  Future<void> _withdraw(JuzzioFriendship f) async {
    if (_busy.contains(f.id)) return;
    setState(() => _busy.add(f.id));
    try {
      await SupabaseService.instance.removeFriend(f.receiverId);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy.remove(f.id));
    }
  }

  Future<void> _acceptAll() async {
    final list = _incoming;
    if (list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('Tümünü kabul et', 'Accept all', 'Alle annehmen')),
        content: Text(_app.trEn('${list.length} isteğin hepsi kabul edilsin mi?', 'Accept all ${list.length} requests?',
            'Alle ${list.length} Anfragen annehmen?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_app.trEn('Kabul et', 'Accept', 'Annehmen'))),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in list) {
      await _answer(f, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incoming;
    final outgoing = _outgoing;
    final list = _tab == 0 ? incoming : outgoing;
    return Scaffold(
      backgroundColor: JuzzioGlassTokens.space.depth.last,
      body: SafeArea(
        child: Column(
          children: [
            JuzzioScreenHeader(
              title: _app.trEn('Arkadaşlık İstekleri', 'Friend Requests', 'Freundschaftsanfragen'),
              subtitle: _app.trEn('Seni arkadaş olarak eklemek isteyen kişiler', 'People who want to add you as a friend',
                  'Personen, die dich als Freund hinzufügen möchten'),
              leadingIcon: Icons.person_add_alt_1_outlined,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: JuzzioNeonTabs(
                tabs: [
                  JuzzioNeonTab(_app.trEn('Gelen İstekler', 'Received', 'Erhalten'), icon: Icons.person_add_alt_outlined, count: incoming.length),
                  JuzzioNeonTab(_app.trEn('Gönderilen İstekler', 'Sent', 'Gesendet'), icon: Icons.send_outlined, count: outgoing.length),
                ],
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _row(list[i], incoming: _tab == 0),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                children: [
                  if (_tab == 0 && incoming.length > 1) ...[
                    JuzzioLimeButton(
                      label: _app.trEn('Tümünü Kabul Et', 'Accept All', 'Alle annehmen'),
                      icon: Icons.check_rounded,
                      style: JuzzioLimeButtonStyle.outline,
                      onPressed: _acceptAll,
                    ),
                    const SizedBox(height: 10),
                  ],
                  JuzzioNeonCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    radius: 26,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onFindFriends();
                    },
                    child: Row(
                      children: [
                        Icon(Icons.person_search_outlined, color: JuzzioGlassTokens.textPrimary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_app.trEn('Arkadaşlarımı Bul', 'Find Friends', 'Freunde finden'),
                              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 56, color: JuzzioGlassTokens.textMuted),
            const SizedBox(height: 12),
            Text(
              _tab == 0
                  ? _app.trEn('Bekleyen arkadaşlık isteğin yok.', 'No pending friend requests.', 'Keine offenen Anfragen.')
                  : _app.trEn('Gönderdiğin bekleyen istek yok.', 'No sent requests pending.', 'Keine gesendeten Anfragen offen.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(JuzzioFriendship f, {required bool incoming}) {
    final id = incoming ? f.requesterId : f.receiverId;
    final name = incoming ? f.requesterName : f.receiverName;
    final user = incoming ? f.requesterUsername : f.receiverUsername;
    final avatar = incoming ? f.requesterAvatar : f.receiverAvatar;
    final mutual = _mutual[id] ?? 0;
    final busy = _busy.contains(f.id);
    final glow = JuzzioGlassTokens.glow;
    return JuzzioNeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 18,
      child: Row(
        children: [
          JuzzioUserAvatar(
            imageUrl: avatar,
            displayName: name.isEmpty ? user : name,
            radius: 24,
            isOnline: widget.onlineIds.contains(id),
            showOnlineDot: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name.isEmpty ? user : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 14.5)),
                  ),
                  if (widget.verifiedIds.contains(id)) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 15, color: glow),
                  ],
                ]),
                Text('@$user', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                if (mutual > 0)
                  Row(children: [
                    Icon(Icons.people_alt_outlined, size: 13, color: JuzzioGlassTokens.textMuted),
                    const SizedBox(width: 4),
                    Text(_app.trEn('$mutual ortak arkadaş', '$mutual mutual friends', '$mutual gemeinsame Freunde'),
                        style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 11.5)),
                  ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else if (incoming) ...[
            _smallButton(_app.trEn('Kabul Et', 'Accept', 'Annehmen'), Icons.check_rounded, filled: true, onTap: () => _answer(f, true)),
            const SizedBox(width: 6),
            _smallButton(_app.trEn('Reddet', 'Decline', 'Ablehnen'), Icons.close_rounded, filled: false, onTap: () => _answer(f, false)),
          ] else
            _smallButton(_app.trEn('Geri Çek', 'Withdraw', 'Zurückziehen'), Icons.undo_rounded, filled: false, onTap: () => _withdraw(f)),
        ],
      ),
    );
  }

  Widget _smallButton(String label, IconData icon, {required bool filled, required VoidCallback onTap}) {
    final glow = JuzzioGlassTokens.glow;
    return Material(
      color: filled ? glow : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: filled ? glow : JuzzioGlassTokens.spaceCardBorder)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: filled ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.textPrimary),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: filled ? JuzzioGlassTokens.onGlow : JuzzioGlassTokens.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}
