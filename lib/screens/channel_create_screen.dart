// =============================================================================
// JUZZIO v1.2.0 — Gerçek kanal oluşturma akışı
//  Önceden "Yeni kanal" grup formunu açıyordu. Kanal artık ayrı bir akıştır:
//   1) Kanal adı + açıklama (canlı önizleme kartı)
//   2) Kimler eklensin? (arkadaşlardan seçim, arama)
//   3) Kurallar: yalnız sahip ve yöneticiler paylaşım yapar; üyeler okur, tepki verir.
//      (Bu kural sunucuda da zorunludur — messages_insert_member politikası.)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_motion.dart';
import '../widgets/social_common_widgets.dart';

class JuzzioCreateChannelPage extends StatefulWidget {
  const JuzzioCreateChannelPage({super.key, required this.friends, required this.myName});

  final List<JuzzioUserProfile> friends;
  final String myName;

  @override
  State<JuzzioCreateChannelPage> createState() => _JuzzioCreateChannelPageState();
}

class _JuzzioCreateChannelPageState extends State<JuzzioCreateChannelPage> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _search = TextEditingController();
  final Set<String> _picked = <String>{};
  int _step = 0;
  bool _busy = false;

  JuzzioAppController get _app => JuzzioAppController.instance;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _desc.addListener(() => setState(() {}));
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().length >= 2;

  Future<void> _create() async {
    if (!_nameOk || _busy) return;
    setState(() => _busy = true);
    try {
      final names = widget.friends.where((f) => _picked.contains(f.id)).map((f) => f.displayName).toList();
      final room = await SupabaseService.instance.createGroupOrChannelRoom(
        title: _name.text.trim(),
        isChannel: true,
        disappearingTimer: 'off',
        members: [...names, widget.myName],
        memberIds: _picked.toList(),
        groupType: 'general',
        description: _desc.text.trim(),
      );
      if (!mounted) return;
      JuzzioHaptics.success();
      Navigator.of(context).pop(room);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, color: p.textPrimary),
          onPressed: () => _step == 0 ? Navigator.of(context).pop() : setState(() => _step = 0),
        ),
        title: Text(_app.trEn('Yeni Kanal', 'New Channel', 'Neuer Kanal'),
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 17)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= _step ? JuzzioGlassTokens.glow : p.textSecondary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _step == 0 ? _details(p) : _members(p),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: JuzzioGlassTokens.accentFill,
                foregroundColor: JuzzioGlassTokens.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: !_nameOk || _busy ? null : (_step == 0 ? () => setState(() => _step = 1) : _create),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: JuzzioOrbitLoader(strokeWidth: 2.4, color: Colors.white))
                  : Text(
                      _step == 0
                          ? _app.trEn('Devam', 'Continue', 'Weiter')
                          : (_picked.isEmpty
                              ? _app.trEn('Kanalı oluştur', 'Create channel', 'Kanal erstellen')
                              : _app.trEn('Kanalı oluştur (${_picked.length} kişi)', 'Create channel (${_picked.length})',
                                  'Kanal erstellen (${_picked.length})')),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(JuzzioPalette p) {
    final name = _name.text.trim();
    return ListView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        // canlı önizleme
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [JuzzioGlassTokens.glow.withValues(alpha: 0.30), JuzzioGlassTokens.glow.withValues(alpha: 0.06)],
            ),
            border: Border.all(color: JuzzioGlassTokens.glow.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: JuzzioGlassTokens.glow, borderRadius: BorderRadius.circular(20)),
              alignment: Alignment.center,
              child: name.isEmpty
                  ? Icon(Icons.campaign_rounded, color: JuzzioGlassTokens.onAccent, size: 30)
                  : Text(name.characters.first.toUpperCase(),
                      style: TextStyle(color: JuzzioGlassTokens.onAccent, fontSize: 28, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? _app.trEn('Kanal adın', 'Your channel', 'Dein Kanal') : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  _desc.text.trim().isEmpty ? _app.trEn('Duyurular ve paylaşımlar', 'Announcements and updates', 'Ankündigungen') : _desc.text.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        _field(p, _name, _app.trEn('Kanal adı', 'Channel name', 'Kanalname'), Icons.tag_rounded, max: 60),
        const SizedBox(height: 12),
        _field(p, _desc, _app.trEn('Açıklama (isteğe bağlı)', 'Description (optional)', 'Beschreibung (optional)'), Icons.notes_rounded,
            max: 240, lines: 3),
        const SizedBox(height: 20),
        _rule(p, Icons.campaign_rounded, _app.trEn('Yalnız sen ve yöneticilerin paylaşım yapar', 'Only you and your admins can post', 'Nur du und Admins posten')),
        _rule(p, Icons.visibility_rounded, _app.trEn('Üyeler okur, tepki verir ve bildirim alır', 'Members read, react and get notified', 'Mitglieder lesen und reagieren')),
        _rule(p, Icons.group_add_rounded, _app.trEn('Sonraki adımda kimleri ekleyeceğini seçersin', 'Pick who to add on the next step', 'Im nächsten Schritt Mitglieder wählen')),
      ],
    );
  }

  Widget _rule(JuzzioPalette p, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: JuzzioGlassTokens.glow.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: JuzzioGlassTokens.glowText),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: p.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _field(JuzzioPalette p, TextEditingController c, String hint, IconData icon, {int max = 60, int lines = 1}) {
    return TextField(
      controller: c,
      maxLength: max,
      minLines: lines,
      maxLines: lines,
      style: TextStyle(color: p.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        prefixIcon: Icon(icon, color: p.textSecondary),
        hintText: hint,
        hintStyle: TextStyle(color: p.textSecondary),
        filled: true,
        fillColor: JuzzioGlassTokens.surfaceStrong,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: JuzzioGlassTokens.glow, width: 1.4),
        ),
      ),
    );
  }

  Widget _members(JuzzioPalette p) {
    final q = _search.text.trim().toLowerCase();
    final list = widget.friends
        .where((f) => q.isEmpty || f.displayName.toLowerCase().contains(q) || f.username.toLowerCase().contains(q))
        .toList();
    return Column(
      key: const ValueKey('members'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: _field(p, _search, _app.trEn('Kişi ara', 'Search people', 'Personen suchen'), Icons.search_rounded),
        ),
        if (_picked.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in widget.friends.where((f) => _picked.contains(f.id)))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _picked.remove(f.id)),
                      child: Column(children: [
                        Stack(clipBehavior: Clip.none, children: [
                          JuzzioUserAvatar(imageUrl: f.avatarUrl, displayName: f.displayName, radius: 24),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              decoration: BoxDecoration(color: p.textSecondary, shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 58,
                          child: Text(f.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: p.textSecondary, fontSize: 11)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    widget.friends.isEmpty
                        ? _app.trEn('Henüz arkadaşın yok — kanalı yine de oluşturup sonra üye ekleyebilirsin.',
                            'No friends yet — you can still create the channel and add members later.', 'Noch keine Freunde.')
                        : _app.trEn('Sonuç yok', 'No results', 'Keine Ergebnisse'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final f = list[i];
                    final on = _picked.contains(f.id);
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onTap: () => setState(() => on ? _picked.remove(f.id) : _picked.add(f.id)),
                      leading: JuzzioUserAvatar(imageUrl: f.avatarUrl, displayName: f.displayName, radius: 21),
                      title: Text(f.displayName, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                      subtitle: Text('@${f.username}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? JuzzioGlassTokens.glow : Colors.transparent,
                          border: Border.all(color: on ? JuzzioGlassTokens.glow : p.textSecondary, width: 1.6),
                        ),
                        child: on ? Icon(Icons.check_rounded, size: 16, color: JuzzioGlassTokens.onAccent) : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
