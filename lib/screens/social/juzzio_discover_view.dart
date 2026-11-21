// =============================================================================
// JUZZIO 2.1 — Keşfet sekmesi (tasarım: "KEŞFET")
//  Üst: "Keşfet" başlığı · "Yeni insanlarla tanış, sohbet et, dünyayı keşfet."
//  Sekmeler: Keşfet (kart) · Eşleşmeler · Beğeniler · Akış (küresel paylaşımlar)
//  Kart eylemleri: geri al · geç · süper beğeni · beğen · mesaj (profil)
//  Herkese açık hesaplar varsayılan olarak kartlarda çıkar; Profil Düzenle'den / buradan kapatılabilir.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_discover_service.dart';
import '../../widgets/juzzio_neon_kit.dart';
import '../../widgets/social_common_widgets.dart';

class JuzzioExploreHub extends StatefulWidget {
  const JuzzioExploreHub({super.key, required this.feed, required this.onOpenProfile});

  /// Mevcut küresel akış (Akış sekmesinde gösterilir)
  final Widget feed;
  final void Function(String userId) onOpenProfile;

  @override
  State<JuzzioExploreHub> createState() => _JuzzioExploreHubState();
}

class _JuzzioExploreHubState extends State<JuzzioExploreHub> {
  final _app = JuzzioAppController.instance;
  final _svc = JuzzioDiscoverService.instance;
  int _tab = 0;
  bool? _enabled;
  bool _loading = true;
  String? _error;
  List<JuzzioDiscoverCard> _deck = [];
  List<JuzzioDiscoverCard> _matches = [];
  List<JuzzioDiscoverCard> _likes = [];
  final List<JuzzioDiscoverCard> _history = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final en = await _svc.isEnabled();
      final res = await Future.wait([_svc.candidates(), _svc.matches(), _svc.likesMe()]);
      if (!mounted) return;
      setState(() {
        _enabled = en;
        _deck = List.of(res[0]);
        _matches = res[1];
        _likes = res[2];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _app.trEn('Keşfet şu an yüklenemedi.', 'Explore could not be loaded.', 'Entdecken konnte nicht geladen werden.');
      });
    }
  }

  Future<void> _toggleEnabled(bool on) async {
    try {
      await _svc.setEnabled(on);
      if (mounted) setState(() => _enabled = on);
    } catch (_) {}
  }

  Future<void> _act(String action) async {
    if (_deck.isEmpty) return;
    final card = _deck.first;
    HapticFeedback.lightImpact();
    setState(() {
      _deck.removeAt(0);
      _history.add(card);
    });
    try {
      final matched = await _svc.act(card.id, action);
      if (matched && mounted) {
        setState(() => _matches = [card, ..._matches.where((m) => m.id != card.id)]);
        _showMatch(card);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history.remove(card);
        _deck.insert(0, card);
      });
    }
    if (_deck.length < 3) {
      try {
        final more = await _svc.candidates();
        if (!mounted) return;
        final have = {..._deck.map((e) => e.id), ..._history.map((e) => e.id)};
        setState(() => _deck.addAll(more.where((m) => !have.contains(m.id))));
      } catch (_) {}
    }
  }

  Future<void> _undo() async {
    if (_history.isEmpty) return;
    final card = _history.removeLast();
    setState(() => _deck.insert(0, card));
    try {
      await _svc.act(card.id, 'undo');
      if (mounted) setState(() => _matches.removeWhere((m) => m.id == card.id));
    } catch (_) {}
  }

  void _showMatch(JuzzioDiscoverCard c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('Eşleştiniz! 🎉', "It's a match! 🎉", "Es ist ein Match! 🎉")),
        content: Text(_app.trEn('${c.displayName} de seni beğendi. Hemen merhaba de!', '${c.displayName} liked you too. Say hi!',
            '${c.displayName} mag dich auch. Sag Hallo!')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_app.trEn('Sonra', 'Later', 'Später'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onOpenProfile(c.id);
            },
            child: Text(_app.trEn('Profile git', 'Open profile', 'Profil öffnen')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_app.trEn('Keşfet', 'Explore', 'Entdecken'),
                  style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: JuzzioGlassTokens.heading,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6)),
              const SizedBox(height: 2),
              Text(
                _app.trEn('Yeni insanlarla tanış, sohbet et, dünyayı keşfet.', 'Meet new people, chat and explore the world.',
                    'Lerne neue Leute kennen, chatte und entdecke die Welt.'),
                style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: JuzzioNeonTabs(
            tabs: [
              JuzzioNeonTab(_app.trEn('Keşfet', 'Discover', 'Entdecken'), icon: Icons.explore_outlined),
              JuzzioNeonTab(_app.trEn('Eşleşmeler', 'Matches', 'Matches'), count: _matches.length),
              JuzzioNeonTab(_app.trEn('Beğeniler', 'Likes', 'Likes'), count: _likes.length),
              JuzzioNeonTab(_app.trEn('Akış', 'Feed', 'Feed'), icon: Icons.public_rounded),
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _discover(),
              _list(_matches, empty: _app.trEn('Henüz eşleşmen yok. Beğendiğin kişi seni de beğenirse burada görünür.',
                  'No matches yet. When someone you like likes you back, they appear here.', 'Noch keine Matches.')),
              _list(_likes, empty: _app.trEn('Seni beğenen yeni kimse yok.', 'No new likes yet.', 'Noch keine neuen Likes.')),
              widget.feed,
            ],
          ),
        ),
      ],
    );
  }

  Widget _discover() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: JuzzioGlassTokens.textSecondary)),
          const SizedBox(height: 12),
          JuzzioLimeButton(label: _app.trEn('Tekrar dene', 'Retry', 'Erneut'), onPressed: _reload, expand: false),
        ]),
      );
    }
    return Column(
      children: [
        if (_enabled == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: JuzzioNeonCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Icon(Icons.visibility_outlined, color: JuzzioGlassTokens.glowText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _app.trEn('Keşfet\'te görünmüyorsun. Açarsan başkaları seni kartlarda görür ve beğenebilir.',
                        'You are hidden from Explore. Turn on so others can see and like you.', 'Du bist in Entdecken verborgen.'),
                    style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 12.5),
                  ),
                ),
                Switch(value: false, onChanged: (v) => _toggleEnabled(v)),
              ]),
            ),
          ),
        Expanded(
          child: _deck.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.travel_explore_rounded, size: 56, color: JuzzioGlassTokens.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        _app.trEn('Şimdilik yeni kimse yok. Daha sonra tekrar bak!', 'No one new right now. Check back later!',
                            'Gerade niemand Neues. Schau später wieder!'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: JuzzioGlassTokens.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      JuzzioLimeButton(
                          label: _app.trEn('Yenile', 'Refresh', 'Aktualisieren'), icon: Icons.refresh_rounded, onPressed: _reload, expand: false),
                    ]),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Stack(
                    children: [
                      if (_deck.length > 1)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: const Offset(10, 8),
                            child: Transform.rotate(angle: 0.04, child: _card(_deck[1], back: true)),
                          ),
                        ),
                      Positioned.fill(
                        child: Dismissible(
                          key: ValueKey('dc_${_deck.first.id}'),
                          direction: DismissDirection.horizontal,
                          onDismissed: (d) => _act(d == DismissDirection.startToEnd ? 'like' : 'pass'),
                          child: _card(_deck.first),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(Icons.replay_rounded, JuzzioGlassTokens.textSecondary, 44, _history.isEmpty ? null : _undo,
                  _app.trEn('Geri al', 'Undo', 'Rückgängig')),
              _action(Icons.close_rounded, const Color(0xFFFF4D6A), 56, _deck.isEmpty ? null : () => _act('pass'),
                  _app.trEn('Geç', 'Pass', 'Weiter')),
              _action(Icons.star_rounded, const Color(0xFF8B5CF6), 62, _deck.isEmpty ? null : () => _act('super'),
                  _app.trEn('Süper beğen', 'Super like', 'Super-Like')),
              _action(Icons.favorite_rounded, JuzzioGlassTokens.glow, 56, _deck.isEmpty ? null : () => _act('like'),
                  _app.trEn('Beğen', 'Like', 'Like')),
              _action(Icons.send_rounded, const Color(0xFF38BDF8), 44,
                  _deck.isEmpty ? null : () => widget.onOpenProfile(_deck.first.id), _app.trEn('Mesaj', 'Message', 'Nachricht')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, Color color, double size, VoidCallback? onTap, String label) {
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: JuzzioGlassTokens.spaceCard,
          shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.4)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: color, size: size * 0.48)),
          ),
        ),
      ),
    );
  }

  Widget _card(JuzzioDiscoverCard c, {bool back = false}) {
    final img = c.coverUrl ?? c.avatarUrl;
    final glow = JuzzioGlassTokens.glow;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: back ? JuzzioGlassTokens.spaceCardBorder : const Color(0xFF8B5CF6).withValues(alpha: 0.6), width: 1.4),
        boxShadow: back ? null : [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.25), blurRadius: 24, spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF2A1F4D), Color(0xFF12131A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: img == null
                  ? Center(child: JuzzioUserAvatar(imageUrl: c.avatarUrl, displayName: c.displayName, radius: 64))
                  : Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(c.displayName.isEmpty ? c.username : c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                    if (c.isVerified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: Color(0xFFA78BFA), size: 20)],
                  ]),
                  Text('@${c.username}${c.lang.isEmpty ? '' : ' · ${c.lang.toUpperCase()}'}',
                      style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 13)),
                  if (c.bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
                  ],
                  if (c.online) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: glow, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(_app.trEn('Çevrimiçi', 'Online', 'Online'), style: TextStyle(color: glow, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<JuzzioDiscoverCard> items, {required String empty}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = items[i];
          return JuzzioNeonCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            radius: 18,
            onTap: () => widget.onOpenProfile(c.id),
            child: Row(children: [
              JuzzioUserAvatar(imageUrl: c.avatarUrl, displayName: c.displayName, radius: 24, isOnline: c.online, showOnlineDot: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.displayName.isEmpty ? c.username : c.displayName,
                      style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800)),
                  Text('@${c.username}', style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                ]),
              ),
              if (c.superLike) const Icon(Icons.star_rounded, color: Color(0xFF8B5CF6)),
              Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textSecondary),
            ]),
          );
        },
      ),
    );
  }
}

/// v2.1: Profil Düzenle / Gizlilik içinde "Keşfet'te görün" anahtarı (kendi yükler, anında kaydeder)
class JuzzioDiscoverVisibilityTile extends StatefulWidget {
  const JuzzioDiscoverVisibilityTile({super.key});

  @override
  State<JuzzioDiscoverVisibilityTile> createState() => _JuzzioDiscoverVisibilityTileState();
}

class _JuzzioDiscoverVisibilityTileState extends State<JuzzioDiscoverVisibilityTile> {
  final _app = JuzzioAppController.instance;
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    JuzzioDiscoverService.instance.isEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _set(bool v) async {
    setState(() {
      _busy = true;
      _on = v;
    });
    try {
      await JuzzioDiscoverService.instance.setEnabled(v);
    } catch (_) {
      if (mounted) setState(() => _on = !v);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return JuzzioNeonRow.toggle(
      icon: Icons.explore_outlined,
      title: _app.trEn("Keşfet'te görün", 'Appear in Explore', 'In Entdecken erscheinen'),
      subtitle: _app.trEn(
        'Açıkken herkese açık profilin Keşfet kartlarında yeni insanlara gösterilir. Gizli hesaplar hiç gösterilmez.',
        'When on, your public profile is shown to new people on Explore cards. Private accounts are never shown.',
        'Wenn an, wird dein öffentliches Profil in Entdecken angezeigt. Private Konten nie.',
      ),
      value: _on ?? false,
      onChanged: (_on == null || _busy || _app.isPrivateAccount) ? null : _set,
    );
  }
}
