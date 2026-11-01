// =============================================================================
// JUZZIO v0.6.0 — Yönetici paneli: ek sekmeler ve kullanıcı güç araçları
//  • Denetim merkezi : ihlaller (ceza basamağı), medya kuyruğu, yasaklı kelimeler, ad taraması
//  • Gruplar         : arama, üyeler, yeniden adlandırma, üye çıkarma, grup silme
//  • Canlı           : süren aramalar (sonlandır) + son gönderi/hikâye/yorum (sil)
//  • Kullanıcı güç sayfası: profil düzenleme, fotoğraf kaldırma, oturum kapatma,
//    elle ihlal, ihlal geçmişi, hesabı kalıcı silme
// Tamamı Glassmorphism kartlarla çizilir; tüm işlemler sunucuda yönetici oturumu ister.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';

String _t(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

JuzzioFeaturesService get _f => JuzzioFeaturesService.instance;

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? JuzzioColors.red500 : null,
  ));
}

String _err(Object e) => SupabaseService.instance.friendlyError(e);

String _date(Object? raw) {
  final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Panel genelinde kullanılan cam kart
class JuzzioAdminGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  const JuzzioAdminGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? JuzzioGlassTokens.border : const Color(0x26000000)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0x2EFFFFFF), Color(0x0FFFFFFF)]
              : const [Color(0xE6FFFFFF), Color(0xB3FFFFFF)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }
}

Color _fg() => JuzzioAppController.instance.isDark ? Colors.white : JuzzioColors.ink;
Color _sub() => JuzzioAppController.instance.isDark ? JuzzioGlassTokens.textSecondary : JuzzioColors.slate600;

Widget _sectionHeader(String text, IconData icon, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: _fg()),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _fg()))),
        if (trailing != null) trailing,
      ],
    ),
  );
}

Widget _pill(String text, {Color? color}) {
  final c = color ?? _sub();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.withValues(alpha: 0.45)),
    ),
    child: Text(text, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
  );
}

String _penaltyLabel(String p) {
  switch (p) {
    case 'suspend_1h':
      return _t('1 saat', '1 hour', '1 Std.');
    case 'suspend_4h':
      return _t('4 saat', '4 hours', '4 Std.');
    case 'permanent':
      return _t('Kalıcı', 'Permanent', 'Dauerhaft');
    default:
      return _t('Uyarı', 'Warning', 'Warnung');
  }
}

Color _penaltyColor(String p) {
  switch (p) {
    case 'permanent':
      return JuzzioColors.red500;
    case 'suspend_4h':
      return const Color(0xFFE11D48);
    case 'suspend_1h':
      return const Color(0xFF0EA5E9);
    default:
      return const Color(0xFF8E8E93);
  }
}

String _kindLabel(String k) {
  switch (k) {
    case 'call_nudity':
      return _t('Aramada müstehcen görüntü', 'Explicit video in call', 'Anstößiges Video im Anruf');
    case 'call_speech':
      return _t('Aramada ağır argo', 'Abusive speech in call', 'Beleidigende Sprache im Anruf');
    case 'avatar_nsfw':
      return _t('Uygunsuz profil fotoğrafı', 'Inappropriate profile photo', 'Unangemessenes Profilfoto');
    case 'name':
      return _t('Uygunsuz ad', 'Inappropriate name', 'Unangemessener Name');
    default:
      return _t('Yönetici kararı', 'Admin decision', 'Admin-Entscheidung');
  }
}

Future<bool> _confirm(BuildContext context, String title, String body, {String? action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(action ?? _t('Onayla', 'Confirm', 'Bestätigen')),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String?> _promptText(BuildContext context, String title, {String initial = '', String hint = '', int maxLines = 1}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
        FilledButton(onPressed: () => Navigator.of(d).pop(ctrl.text.trim()), child: Text(_t('Kaydet', 'Save', 'Speichern'))),
      ],
    ),
  );
}

// =============================================================================
// 1) DENETİM MERKEZİ
// =============================================================================
class JuzzioAdminModerationTab extends StatefulWidget {
  final String token;
  const JuzzioAdminModerationTab({super.key, required this.token});

  @override
  State<JuzzioAdminModerationTab> createState() => _JuzzioAdminModerationTabState();
}

class _JuzzioAdminModerationTabState extends State<JuzzioAdminModerationTab> {
  String _section = 'strikes'; // strikes | media | terms | names
  String _mediaFilter = 'pending';
  bool _loading = true;
  Map<String, dynamic> _overview = const {};
  List<Map<String, dynamic>> _strikes = const [];
  List<Map<String, dynamic>> _media = const [];
  List<Map<String, dynamic>> _terms = const [];
  Map<String, dynamic> _scan = const {};
  final TextEditingController _termCtrl = TextEditingController();
  String _termMode = 'contains';
  bool _termSpeech = false;
  String _termQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _termCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ov = await _f.adminModerationOverview(widget.token);
      List<Map<String, dynamic>> strikes = _strikes;
      List<Map<String, dynamic>> media = _media;
      List<Map<String, dynamic>> terms = _terms;
      Map<String, dynamic> scan = _scan;
      switch (_section) {
        case 'strikes':
          strikes = await _f.adminListStrikes(widget.token);
          break;
        case 'media':
          media = await _f.adminMediaQueue(widget.token, status: _mediaFilter);
          break;
        case 'terms':
          terms = await _f.adminListBannedTerms(widget.token);
          break;
        case 'names':
          scan = await _f.adminScanNames(widget.token);
          break;
      }
      if (!mounted) return;
      setState(() {
        _overview = ov;
        _strikes = strikes;
        _media = media;
        _terms = terms;
        _scan = scan;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, _err(e), error: true);
    }
  }

  Future<void> _run(Future<void> Function() job, String okText) async {
    try {
      await job();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _snack(context, okText);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _err(e), error: true);
    }
  }

  Widget _overviewGrid() {
    final items = <(String, String, IconData)>[
      (_t('İhlal (24 sa)', 'Strikes (24h)', 'Verstöße (24 Std.)'), '${_overview['strikes_24h'] ?? 0}', Icons.gpp_maybe_rounded),
      (_t('Toplam ihlal', 'Total strikes', 'Verstöße gesamt'), '${_overview['strikes_total'] ?? 0}', Icons.policy_rounded),
      (_t('Kalıcı engel', 'Permanent bans', 'Dauersperren'), '${_overview['permanent_bans'] ?? 0}', Icons.block_rounded),
      (_t('Şu an uzaklaştırılmış', 'Suspended now', 'Derzeit gesperrt'), '${_overview['suspended_now'] ?? 0}', Icons.timer_rounded),
      (_t('İnceleme bekleyen', 'Pending review', 'Ausstehend'), '${_overview['media_pending'] ?? 0}', Icons.photo_library_rounded),
      (_t('Müstehcen (24 sa)', 'NSFW (24h)', 'NSFW (24 Std.)'), '${_overview['media_nsfw_24h'] ?? 0}', Icons.no_adult_content_rounded),
      (_t('Yasaklı kelime', 'Banned terms', 'Gesperrte Wörter'), '${_overview['banned_terms'] ?? 0}', Icons.spellcheck_rounded),
      (_t('Engelli e-posta', 'Blocked emails', 'Gesperrte E-Mails'), '${_overview['blocked_emails'] ?? 0}', Icons.alternate_email_rounded),
      (_t('Süren arama', 'Active calls', 'Aktive Anrufe'), '${_overview['active_calls'] ?? 0}', Icons.call_rounded),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 82,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        return JuzzioAdminGlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(it.$3, size: 18, color: _sub()),
              const Spacer(),
              Text(it.$2, style: TextStyle(color: _fg(), fontWeight: FontWeight.w900, fontSize: 20)),
              Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _sub(), fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  Widget _segment() {
    final opts = <(String, String, IconData)>[
      ('strikes', _t('İhlaller', 'Strikes', 'Verstöße'), Icons.gavel_rounded),
      ('media', _t('Medya', 'Media', 'Medien'), Icons.image_search_rounded),
      ('terms', _t('Kelimeler', 'Words', 'Wörter'), Icons.spellcheck_rounded),
      ('names', _t('Ad taraması', 'Name scan', 'Namensprüfung'), Icons.manage_search_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in opts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(o.$3, size: 16),
                label: Text(o.$2),
                selected: _section == o.$1,
                onSelected: (_) {
                  setState(() => _section = o.$1);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _strikesList() {
    if (_strikes.isEmpty) {
      return [_empty(_t('Kayıtlı ihlal yok.', 'No strikes recorded.', 'Keine Verstöße.'))];
    }
    return [
      for (final s in _strikes)
        JuzzioAdminGlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JuzzioGlassAvatar(imageUrl: s['avatar_url']?.toString(), name: '${s['display_name'] ?? s['username'] ?? '?'}', radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${s['username'] ?? '-'}', style: TextStyle(color: _fg(), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(_kindLabel('${s['kind']}'), style: TextStyle(color: _sub(), fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill('#${s['strike_no']}'),
                        _pill(_penaltyLabel('${s['penalty']}'), color: _penaltyColor('${s['penalty']}')),
                        if (s['revoked'] == true) _pill(_t('Geri alındı', 'Revoked', 'Aufgehoben'), color: const Color(0xFF34C759)),
                        _pill(_date(s['created_at'])),
                      ],
                    ),
                  ],
                ),
              ),
              if (s['revoked'] != true)
                IconButton(
                  tooltip: _t('Geri al ve engeli kaldır', 'Revoke and lift ban', 'Aufheben und Sperre lösen'),
                  icon: Icon(Icons.undo_rounded, color: _fg()),
                  onPressed: () async {
                    final ok = await _confirm(context, _t('İhlali geri al', 'Revoke strike', 'Verstoß aufheben'),
                        _t('Bu ihlal geri alınır ve otomatik engel kaldırılır.', 'This strike is revoked and the automatic ban lifted.',
                            'Dieser Verstoß wird aufgehoben und die automatische Sperre gelöst.'));
                    if (!ok) return;
                    await _run(() => _f.adminRevokeStrike(widget.token, (s['id'] as num).toInt()),
                        _t('İhlal geri alındı.', 'Strike revoked.', 'Verstoß aufgehoben.'));
                  },
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _mediaList() {
    final filterRow = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in const ['pending', 'nsfw', 'all'])
            ChoiceChip(
              label: Text(f == 'pending'
                  ? _t('Bekleyen', 'Pending', 'Ausstehend')
                  : f == 'nsfw'
                      ? _t('Müstehcen', 'NSFW', 'NSFW')
                      : _t('Tümü', 'All', 'Alle')),
              selected: _mediaFilter == f,
              onSelected: (_) {
                setState(() => _mediaFilter = f);
                _load();
              },
            ),
        ],
      ),
    );
    if (_media.isEmpty) {
      return [filterRow, _empty(_t('Kuyruk boş.', 'Queue is empty.', 'Warteschlange leer.'))];
    }
    return [
      filterRow,
      for (final m in _media)
        JuzzioAdminGlassCard(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: '${m['url'] ?? ''}'.isEmpty
                      ? const ColoredBox(color: Color(0x33000000), child: Icon(Icons.videocam_off_rounded))
                      : Image.network('${m['url']}', fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x33000000))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${m['username'] ?? '-'}', style: TextStyle(color: _fg(), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill('${m['kind']}'),
                        _pill('${m['verdict']}',
                            color: m['verdict'] == 'nsfw'
                                ? JuzzioColors.red500
                                : (m['verdict'] == 'safe' ? const Color(0xFF34C759) : const Color(0xFF8E8E93))),
                        _pill('${m['review_status']}'),
                        _pill(_date(m['created_at'])),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: _t('Onayla', 'Approve', 'Freigeben'),
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759)),
                    onPressed: () => _run(() => _f.adminReviewMedia(widget.token, (m['id'] as num).toInt(), approve: true),
                        _t('Onaylandı.', 'Approved.', 'Freigegeben.')),
                  ),
                  IconButton(
                    tooltip: _t('Reddet + ihlal', 'Reject + strike', 'Ablehnen + Verstoß'),
                    icon: const Icon(Icons.cancel_rounded, color: JuzzioColors.red500),
                    onPressed: () async {
                      final strike = await _confirm(
                        context,
                        _t('Fotoğrafı reddet', 'Reject photo', 'Foto ablehnen'),
                        _t('Fotoğraf profilden kaldırılır ve kişiye ihlal verilir (1 sa / 4 sa / kalıcı).',
                            'The photo is removed and the user receives a strike (1h / 4h / permanent).',
                            'Das Foto wird entfernt und der Nutzer erhält einen Verstoß (1 Std. / 4 Std. / dauerhaft).'),
                        action: _t('Reddet', 'Reject', 'Ablehnen'),
                      );
                      if (!strike) return;
                      await _run(
                          () => _f.adminReviewMedia(widget.token, (m['id'] as num).toInt(), approve: false, strike: true),
                          _t('Reddedildi.', 'Rejected.', 'Abgelehnt.'));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _termsList() {
    final visible = _terms
        .where((t) => _termQuery.isEmpty || '${t['term']}'.contains(_termQuery.toLowerCase()))
        .toList();
    return [
      JuzzioAdminGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _termCtrl,
              decoration: InputDecoration(
                hintText: _t('Yeni yasaklı kelime / kök', 'New banned word / stem', 'Neues gesperrtes Wort / Stamm'),
                prefixIcon: const Icon(Icons.add_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(_t('İçinde geçerse', 'Contains', 'Enthält')),
                  selected: _termMode == 'contains',
                  onSelected: (_) => setState(() => _termMode = 'contains'),
                ),
                ChoiceChip(
                  label: Text(_t('Tam kelime', 'Whole word', 'Ganzes Wort')),
                  selected: _termMode == 'word',
                  onSelected: (_) => setState(() => _termMode = 'word'),
                ),
                FilterChip(
                  label: Text(_t('Aramada ceza', 'Call strike', 'Anruf-Verstoß')),
                  selected: _termSpeech,
                  onSelected: (v) => setState(() => _termSpeech = v),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(_t('Ekle', 'Add', 'Hinzufügen')),
                  onPressed: () {
                    final term = _termCtrl.text.trim();
                    if (term.isEmpty) return;
                    _termCtrl.clear();
                    _run(() => _f.adminUpsertBannedTerm(widget.token, term, mode: _termMode, speech: _termSpeech),
                        _t('Kelime eklendi.', 'Word added.', 'Wort hinzugefügt.'));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: _t('Listede ara', 'Search list', 'Liste durchsuchen'),
          ),
          onChanged: (v) => setState(() => _termQuery = v.trim()),
        ),
      ),
      JuzzioAdminGlassCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final t in visible)
              ListTile(
                dense: true,
                title: Text('${t['term']}', style: TextStyle(color: _fg(), fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${t['match_mode'] == 'word' ? _t('tam kelime', 'whole word', 'ganzes Wort') : _t('içinde geçerse', 'contains', 'enthält')}'
                  '${t['speech_strike'] == true ? ' · ${_t('aramada ceza', 'call strike', 'Anruf-Verstoß')}' : ''}',
                  style: TextStyle(color: _sub(), fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500),
                  onPressed: () => _run(() => _f.adminDeleteBannedTerm(widget.token, '${t['term']}'),
                      _t('Kelime silindi.', 'Word removed.', 'Wort entfernt.')),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _namesList() {
    final users = (_scan['users'] is List) ? (_scan['users'] as List).whereType<Map>().toList() : const <Map>[];
    final groups = (_scan['groups'] is List) ? (_scan['groups'] as List).whereType<Map>().toList() : const <Map>[];
    return [
      _sectionHeader(_t('Uygunsuz kullanıcı alanları', 'Inappropriate user fields', 'Unangemessene Nutzerfelder'),
          Icons.person_off_rounded,
          trailing: _pill('${users.length}')),
      if (users.isEmpty) _empty(_t('Temiz.', 'Clean.', 'Sauber.')),
      for (final u in users)
        JuzzioAdminGlassCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: JuzzioGlassAvatar(imageUrl: u['avatar_url']?.toString(), name: '${u['display_name'] ?? '?'}', radius: 20),
            title: Text('${u['display_name'] ?? ''}', style: TextStyle(color: _fg(), fontWeight: FontWeight.w800)),
            subtitle: Text('@${u['username'] ?? ''}\n${u['bio'] ?? ''}', maxLines: 3, style: TextStyle(color: _sub(), fontSize: 12)),
            isThreeLine: true,
            trailing: IconButton(
              icon: Icon(Icons.edit_rounded, color: _fg()),
              onPressed: () async {
                await showJuzzioAdminUserPowerSheet(
                  context,
                  token: widget.token,
                  userId: '${u['id']}',
                  username: '${u['username'] ?? ''}',
                  displayName: '${u['display_name'] ?? ''}',
                  bio: '${u['bio'] ?? ''}',
                );
                _load();
              },
            ),
          ),
        ),
      const SizedBox(height: 8),
      _sectionHeader(_t('Uygunsuz grup adları', 'Inappropriate group names', 'Unangemessene Gruppennamen'), Icons.groups_rounded,
          trailing: _pill('${groups.length}')),
      if (groups.isEmpty) _empty(_t('Temiz.', 'Clean.', 'Sauber.')),
      for (final g in groups)
        JuzzioAdminGlassCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${g['title'] ?? ''}', style: TextStyle(color: _fg(), fontWeight: FontWeight.w800)),
            subtitle: Text('${g['group_purpose'] ?? ''}', style: TextStyle(color: _sub(), fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.drive_file_rename_outline_rounded, color: _fg()),
                  onPressed: () async {
                    final name = await _promptText(context, _t('Grup adını değiştir', 'Rename group', 'Gruppe umbenennen'),
                        initial: '${g['title'] ?? ''}');
                    if (name == null || name.isEmpty) return;
                    await _run(() => _f.adminUpdateGroup(widget.token, '${g['id']}', title: name, description: ''),
                        _t('Grup adı güncellendi.', 'Group renamed.', 'Gruppe umbenannt.'));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever_rounded, color: JuzzioColors.red500),
                  onPressed: () async {
                    final ok = await _confirm(context, _t('Grubu sil', 'Delete group', 'Gruppe löschen'),
                        _t('Grup ve mesajları kalıcı olarak silinir.', 'The group and its messages are deleted permanently.',
                            'Die Gruppe und ihre Nachrichten werden dauerhaft gelöscht.'),
                        action: _t('Sil', 'Delete', 'Löschen'));
                    if (!ok) return;
                    await _run(() => _f.adminDeleteGroup(widget.token, '${g['id']}'), _t('Grup silindi.', 'Group deleted.', 'Gruppe gelöscht.'));
                  },
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> body;
    switch (_section) {
      case 'media':
        body = _mediaList();
        break;
      case 'terms':
        body = _termsList();
        break;
      case 'names':
        body = _namesList();
        break;
      default:
        body = _strikesList();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _sectionHeader(_t('Denetim merkezi', 'Moderation center', 'Moderationszentrale'), Icons.shield_rounded),
          JuzzioAdminGlassCard(
            child: Text(
              _t('Ceza basamağı: 1. ihlal 1 saat, 2. ihlal 4 saat uzaklaştırma; 3. ihlal kalıcı engel + cihaz ve e-posta yasağı. '
                      'Görüntülü aramada müstehcen görüntü ve ağır argo otomatik algılanır, arama anında kapatılır.',
                  'Penalty ladder: 1st strike 1h, 2nd strike 4h suspension; 3rd strike permanent ban + device and email block. '
                      'Explicit video and abusive speech in calls are detected automatically and the call ends immediately.',
                  'Strafstufen: 1. Verstoß 1 Std., 2. Verstoß 4 Std. Sperre; 3. Verstoß dauerhafte Sperre + Geräte- und E-Mail-Sperre. '
                      'Anstößige Videos und beleidigende Sprache in Anrufen werden automatisch erkannt, der Anruf endet sofort.'),
              style: TextStyle(color: _sub(), height: 1.4, fontSize: 12.5),
            ),
          ),
          _overviewGrid(),
          const SizedBox(height: 12),
          _segment(),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          ...body,
        ],
      ),
    );
  }
}

Widget _empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(text, style: TextStyle(color: _sub()))),
    );

// =============================================================================
// 2) GRUPLAR
// =============================================================================
class JuzzioAdminGroupsTab extends StatefulWidget {
  final String token;
  const JuzzioAdminGroupsTab({super.key, required this.token});

  @override
  State<JuzzioAdminGroupsTab> createState() => _JuzzioAdminGroupsTabState();
}

class _JuzzioAdminGroupsTabState extends State<JuzzioAdminGroupsTab> {
  List<Map<String, dynamic>> _groups = const [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _f.adminListGroups(widget.token, query: _query);
      if (!mounted) return;
      setState(() {
        _groups = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, _err(e), error: true);
    }
  }

  Future<void> _openMembers(Map<String, dynamic> g) async {
    final roomId = '${g['id']}';
    List<Map<String, dynamic>> members = const [];
    try {
      members = await _f.adminGroupMembers(widget.token, roomId);
    } catch (e) {
      if (mounted) _snack(context, _err(e), error: true);
      return;
    }
    if (!mounted) return;
    await showJuzzioGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.62,
          child: Column(
            children: [
              const SizedBox(height: 14),
              Text('${g['title'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(_t('${members.length} üye', '${members.length} members', '${members.length} Mitglieder'),
                  style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    return ListTile(
                      leading: JuzzioGlassAvatar(imageUrl: m['avatar_url']?.toString(), name: '${m['display_name'] ?? '?'}', radius: 19),
                      title: Text('${m['display_name'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      subtitle: Text('@${m['username'] ?? ''} · ${m['role'] ?? ''}', style: const TextStyle(color: Colors.white60)),
                      trailing: IconButton(
                        tooltip: _t('Gruptan çıkar', 'Remove from group', 'Aus Gruppe entfernen'),
                        icon: const Icon(Icons.person_remove_rounded, color: Colors.white),
                        onPressed: () async {
                          try {
                            await _f.adminRemoveGroupMember(widget.token, roomId, '${m['user_id']}');
                            setSheet(() => members = List.of(members)..removeAt(i));
                          } catch (e) {
                            if (mounted) _snack(context, _err(e), error: true);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _sectionHeader(_t('Gruplar', 'Groups', 'Gruppen'), Icons.groups_2_rounded, trailing: _pill('${_groups.length}')),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: _t('Grup adında ara', 'Search group name', 'Gruppenname suchen'),
            ),
            onSubmitted: (v) {
              _query = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading && _groups.isEmpty) _empty(_t('Grup bulunamadı.', 'No groups found.', 'Keine Gruppen gefunden.')),
          for (final g in _groups)
            JuzzioAdminGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${g['title'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _fg(), fontWeight: FontWeight.w900, fontSize: 15.5)),
                      ),
                      _pill(_t('${g['members'] ?? 0} üye', '${g['members'] ?? 0} members', '${g['members'] ?? 0} Mitgl.')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${g['owner_username'] != null ? '@${g['owner_username']} · ' : ''}'
                    '${g['messages'] ?? 0} ${_t('mesaj', 'messages', 'Nachrichten')} · ${_date(g['created_at'])}',
                    style: TextStyle(color: _sub(), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.people_rounded, size: 18),
                        label: Text(_t('Üyeler', 'Members', 'Mitglieder')),
                        onPressed: () => _openMembers(g),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: Text(_t('Yeniden adlandır', 'Rename', 'Umbenennen')),
                        onPressed: () async {
                          final name = await _promptText(context, _t('Grup adı', 'Group name', 'Gruppenname'),
                              initial: '${g['title'] ?? ''}');
                          if (name == null || name.isEmpty) return;
                          try {
                            await _f.adminUpdateGroup(widget.token, '${g['id']}', title: name);
                            _load();
                          } catch (e) {
                            if (mounted) _snack(context, _err(e), error: true);
                          }
                        },
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: JuzzioColors.red500),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: Text(_t('Sil', 'Delete', 'Löschen')),
                        onPressed: () async {
                          final ok = await _confirm(context, _t('Grubu sil', 'Delete group', 'Gruppe löschen'),
                              _t('Grup ve mesajları kalıcı olarak silinir.', 'The group and its messages are deleted permanently.',
                                  'Die Gruppe und ihre Nachrichten werden dauerhaft gelöscht.'),
                              action: _t('Sil', 'Delete', 'Löschen'));
                          if (!ok) return;
                          try {
                            await _f.adminDeleteGroup(widget.token, '${g['id']}');
                            _load();
                          } catch (e) {
                            if (mounted) _snack(context, _err(e), error: true);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// 3) CANLI: süren aramalar + son içerikler
// =============================================================================
class JuzzioAdminLiveTab extends StatefulWidget {
  final String token;
  const JuzzioAdminLiveTab({super.key, required this.token});

  @override
  State<JuzzioAdminLiveTab> createState() => _JuzzioAdminLiveTabState();
}

class _JuzzioAdminLiveTabState extends State<JuzzioAdminLiveTab> {
  List<Map<String, dynamic>> _calls = const [];
  List<Map<String, dynamic>> _content = const [];
  String _kind = 'post';
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final calls = await _f.adminActiveCalls(widget.token);
      final content = await _f.adminRecentContent(widget.token, _kind, query: _query);
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _content = content;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _sectionHeader(_t('Süren aramalar', 'Active calls', 'Aktive Anrufe'), Icons.call_rounded, trailing: _pill('${_calls.length}')),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading && _calls.isEmpty) _empty(_t('Şu an süren arama yok.', 'No active calls right now.', 'Derzeit keine Anrufe.')),
          for (final c in _calls)
            JuzzioAdminGlassCard(
              child: Row(
                children: [
                  Icon(c['is_video'] == true ? Icons.videocam_rounded : Icons.call_rounded, color: _fg()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['is_group'] == true && '${c['group_title'] ?? ''}'.isNotEmpty
                              ? '${c['group_title']}'
                              : '${c['caller_name'] ?? ''} → ${(c['receivers'] is List) ? (c['receivers'] as List).join(', ') : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _fg(), fontWeight: FontWeight.w800),
                        ),
                        Text('${_t('Başladı', 'Started', 'Gestartet')}: ${_date(c['started_at'])} · ${c['answered'] ?? 0} ${_t('katılımcı', 'joined', 'beigetreten')}',
                            style: TextStyle(color: _sub(), fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Aramayı sonlandır', 'End call', 'Anruf beenden'),
                    icon: const Icon(Icons.call_end_rounded, color: JuzzioColors.red500),
                    onPressed: () async {
                      final ok = await _confirm(context, _t('Aramayı sonlandır', 'End call', 'Anruf beenden'),
                          _t('Arama tüm katılımcılar için kapatılır.', 'The call is ended for everyone.', 'Der Anruf wird für alle beendet.'),
                          action: _t('Sonlandır', 'End', 'Beenden'));
                      if (!ok) return;
                      try {
                        await _f.adminEndCall(widget.token, '${c['session_key']}');
                        _load();
                      } catch (e) {
                        if (mounted) _snack(context, _err(e), error: true);
                      }
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          _sectionHeader(_t('Son içerikler', 'Recent content', 'Neueste Inhalte'), Icons.dynamic_feed_rounded),
          Wrap(
            spacing: 8,
            children: [
              for (final k in const ['post', 'story', 'comment'])
                ChoiceChip(
                  label: Text(k == 'post'
                      ? _t('Gönderiler', 'Posts', 'Beiträge')
                      : k == 'story'
                          ? _t('Hikâyeler', 'Stories', 'Storys')
                          : _t('Yorumlar', 'Comments', 'Kommentare')),
                  selected: _kind == k,
                  onSelected: (_) {
                    setState(() => _kind = k);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: _t('Metinde ara', 'Search text', 'Text suchen'),
            ),
            onSubmitted: (v) {
              _query = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 10),
          if (!_loading && _content.isEmpty) _empty(_t('İçerik yok.', 'No content.', 'Keine Inhalte.')),
          for (final c in _content)
            JuzzioAdminGlassCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ('${c['media_url'] ?? ''}'.startsWith('http'))
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Image.network('${c['media_url']}', fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x33000000))),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${c['username'] ?? '-'} · ${_date(c['created_at'])}',
                            style: TextStyle(color: _sub(), fontSize: 12)),
                        const SizedBox(height: 3),
                        Text('${c['text'] ?? ''}'.isEmpty ? '(${c['sub'] ?? ''})' : '${c['text']}',
                            maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: _fg())),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500),
                    onPressed: () async {
                      final ok = await _confirm(context, _t('İçeriği sil', 'Delete content', 'Inhalt löschen'),
                          _t('Bu içerik kalıcı olarak silinir.', 'This content is deleted permanently.', 'Dieser Inhalt wird dauerhaft gelöscht.'),
                          action: _t('Sil', 'Delete', 'Löschen'));
                      if (!ok) return;
                      try {
                        await _f.adminDeleteContent(widget.token, _kind, '${c['id']}');
                        _load();
                      } catch (e) {
                        if (mounted) _snack(context, _err(e), error: true);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4) KULLANICI GÜÇ ARAÇLARI
// =============================================================================
Future<void> showJuzzioAdminUserPowerSheet(
  BuildContext context, {
  required String token,
  required String userId,
  required String username,
  String displayName = '',
  String bio = '',
}) {
  return showJuzzioGlassSheet<void>(
    context: context,
    builder: (ctx) => _AdminUserPowerSheet(
      token: token,
      userId: userId,
      username: username,
      displayName: displayName,
      bio: bio,
    ),
  );
}

class _AdminUserPowerSheet extends StatefulWidget {
  final String token;
  final String userId;
  final String username;
  final String displayName;
  final String bio;

  const _AdminUserPowerSheet({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.bio,
  });

  @override
  State<_AdminUserPowerSheet> createState() => _AdminUserPowerSheetState();
}

class _AdminUserPowerSheetState extends State<_AdminUserPowerSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.displayName);
  late final TextEditingController _user = TextEditingController(text: widget.username);
  late final TextEditingController _bio = TextEditingController(text: widget.bio);
  List<Map<String, dynamic>> _strikes = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStrikes();
  }

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _loadStrikes() async {
    try {
      final list = await _f.adminListStrikes(widget.token, userId: widget.userId);
      if (mounted) setState(() => _strikes = list);
    } catch (_) {}
  }

  Future<void> _do(Future<void> Function() job, String ok) async {
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      _snack(context, ok);
      await _loadStrikes();
    } catch (e) {
      if (mounted) _snack(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon));

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: h * 0.82,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('@${widget.username}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(_t('Yönetici güç araçları', 'Admin power tools', 'Admin-Werkzeuge'), style: const TextStyle(color: Colors.white60)),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: _deco(_t('Ad Soyad', 'Full name', 'Name'), Icons.badge_rounded)),
          const SizedBox(height: 8),
          TextField(controller: _user, decoration: _deco(_t('Kullanıcı adı', 'Username', 'Benutzername'), Icons.alternate_email_rounded)),
          const SizedBox(height: 8),
          TextField(controller: _bio, maxLines: 3, decoration: _deco(_t('Biyografi', 'Bio', 'Bio'), Icons.notes_rounded)),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.save_rounded),
            label: Text(_t('Profili kaydet', 'Save profile', 'Profil speichern')),
            onPressed: _busy
                ? null
                : () => _do(
                      () => _f.adminUpdateUserProfile(
                        widget.token,
                        widget.userId,
                        displayName: _name.text.trim(),
                        username: _user.text.trim() == widget.username ? null : _user.text.trim(),
                        bio: _bio.text,
                      ),
                      _t('Profil güncellendi.', 'Profile updated.', 'Profil aktualisiert.'),
                    ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.hide_image_rounded),
                label: Text(_t('Fotoğrafı kaldır', 'Remove photo', 'Foto entfernen')),
                onPressed: _busy
                    ? null
                    : () => _do(() => _f.adminUpdateUserProfile(widget.token, widget.userId, clearAvatar: true),
                        _t('Fotoğraf kaldırıldı.', 'Photo removed.', 'Foto entfernt.')),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded),
                label: Text(_t('Tüm oturumları kapat', 'Sign out everywhere', 'Überall abmelden')),
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                          await _f.adminSignOutUser(widget.token, widget.userId);
                        }, _t('Oturumlar kapatıldı.', 'Signed out.', 'Abgemeldet.')),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE11D48)),
                icon: const Icon(Icons.gavel_rounded),
                label: Text(_t('İhlal ver', 'Give strike', 'Verstoß erteilen')),
                onPressed: _busy
                    ? null
                    : () async {
                        final reason = await _promptText(context, _t('İhlal sebebi', 'Strike reason', 'Grund'),
                            hint: _t('Ör. uygunsuz davranış', 'e.g. inappropriate behaviour', 'z. B. unangemessenes Verhalten'));
                        if (reason == null) return;
                        await _do(() async {
                          await _f.adminAddStrike(widget.token, widget.userId, reason);
                        }, _t('İhlal verildi (ceza basamağı uygulandı).', 'Strike given (penalty ladder applied).',
                            'Verstoß erteilt (Strafstufe angewendet).'));
                      },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(_t('İhlal geçmişi', 'Strike history', 'Verstoß-Verlauf'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 6),
          if (_strikes.isEmpty)
            Text(_t('İhlal yok.', 'No strikes.', 'Keine Verstöße.'), style: const TextStyle(color: Colors.white60)),
          for (final s in _strikes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.report_rounded, color: _penaltyColor('${s['penalty']}')),
              title: Text('#${s['strike_no']} · ${_kindLabel('${s['kind']}')}', style: const TextStyle(color: Colors.white)),
              subtitle: Text('${_penaltyLabel('${s['penalty']}')} · ${_date(s['created_at'])}${s['revoked'] == true ? ' · ${_t('geri alındı', 'revoked', 'aufgehoben')}' : ''}',
                  style: const TextStyle(color: Colors.white60)),
              trailing: s['revoked'] == true
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.white),
                      onPressed: () => _do(() => _f.adminRevokeStrike(widget.token, (s['id'] as num).toInt()),
                          _t('İhlal geri alındı.', 'Strike revoked.', 'Verstoß aufgehoben.')),
                    ),
            ),
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500, foregroundColor: Colors.white),
            icon: const Icon(Icons.delete_forever_rounded),
            label: Text(_t('Hesabı kalıcı sil', 'Delete account permanently', 'Konto dauerhaft löschen')),
            onPressed: _busy
                ? null
                : () async {
                    final typed = await _promptText(
                      context,
                      _t('Silmek için kullanıcı adını yazın', 'Type the username to delete', 'Benutzernamen zum Löschen eingeben'),
                      hint: widget.username,
                    );
                    if (typed == null || typed.isEmpty) return;
                    final nav = Navigator.of(context);
                    setState(() => _busy = true);
                    try {
                      await _f.adminDeleteUser(widget.token, widget.userId, typed);
                      if (!mounted) return;
                      _snack(context, _t('Hesap silindi.', 'Account deleted.', 'Konto gelöscht.'));
                      nav.pop();
                    } catch (e) {
                      if (mounted) {
                        setState(() => _busy = false);
                        _snack(context, _err(e), error: true);
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// v0.7.0 — Hata bildirimleri ve geri bildirimler (ekran görüntüsüyle)
// =============================================================================
class JuzzioAdminFeedbackTab extends StatefulWidget {
  final String token;
  const JuzzioAdminFeedbackTab({super.key, required this.token});

  @override
  State<JuzzioAdminFeedbackTab> createState() => _JuzzioAdminFeedbackTabState();
}

class _JuzzioAdminFeedbackTabState extends State<JuzzioAdminFeedbackTab> {
  List<Map<String, dynamic>> _items = const [];
  String? _status = 'open';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.instance.client
          .rpc('admin_list_feedback', params: {'p_token': widget.token, 'p_status': _status});
      if (!mounted) return;
      setState(() {
        _items = res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, _err(e), error: true);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> f, String status) async {
    try {
      await SupabaseService.instance.client.rpc('admin_update_feedback',
          params: {'p_token': widget.token, 'p_id': f['id'], 'p_status': status, 'p_note': ''});
      _load();
    } catch (e) {
      if (mounted) _snack(context, _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    String kindLabel(String k) =>
        k == 'idea' ? _t('Öneri', 'Idea', 'Idee') : (k == 'feedback' ? _t('Geri bildirim', 'Feedback', 'Feedback') : _t('Hata', 'Bug', 'Fehler'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _sectionHeader(_t('Hata bildirimleri', 'Bug reports', 'Fehlermeldungen'), Icons.bug_report_rounded,
              trailing: _pill('${_items.length}')),
          Wrap(
            spacing: 8,
            children: [
              for (final s in const <String?>['open', 'in_progress', 'resolved', null])
                ChoiceChip(
                  label: Text(s == 'open'
                      ? _t('Açık', 'Open', 'Offen')
                      : s == 'in_progress'
                          ? _t('İnceleniyor', 'In progress', 'In Arbeit')
                          : s == 'resolved'
                              ? _t('Çözüldü', 'Resolved', 'Gelöst')
                              : _t('Tümü', 'All', 'Alle')),
                  selected: _status == s,
                  onSelected: (_) {
                    setState(() => _status = s);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading && _items.isEmpty) _empty(_t('Bildirim yok.', 'No reports.', 'Keine Meldungen.')),
          for (final f in _items)
            JuzzioAdminGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pill(kindLabel('${f['kind']}')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('@${f['username'] ?? '-'} · ${_date(f['created_at'])}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _sub(), fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText('${f['message'] ?? ''}', style: TextStyle(color: _fg(), height: 1.4)),
                  if ('${f['image_url'] ?? ''}'.startsWith('https://')) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network('${f['image_url']}', height: 220, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text('${f['app_version'] ?? ''} · ${f['device_info'] ?? ''}', style: TextStyle(color: _sub(), fontSize: 11.5)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (f['status'] != 'in_progress')
                        OutlinedButton(onPressed: () => _setStatus(f, 'in_progress'), child: Text(_t('İnceleniyor', 'In progress', 'In Arbeit'))),
                      if (f['status'] != 'resolved')
                        FilledButton(onPressed: () => _setStatus(f, 'resolved'), child: Text(_t('Çözüldü', 'Resolved', 'Gelöst'))),
                      if (f['status'] == 'resolved')
                        TextButton(onPressed: () => _setStatus(f, 'open'), child: Text(_t('Yeniden aç', 'Reopen', 'Wieder öffnen'))),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
