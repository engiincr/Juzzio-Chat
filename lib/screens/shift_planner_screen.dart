// =============================================================================
// JUZZIO v0.9.4 — Vardiya planlayıcı (08-16 · 16-00 · 00-08 · izin · fazla mesai)
//  • Kendi vardiya takvimin (ay görünümü, güne dokun → vardiya seç).
//  • Vardiyayı bir grup sohbetiyle paylaşırsan grup üyeleri "Ekip takvimi"nde görür
//    (RLS: yalnız o grubun üyeleri). Gün başına tek kayıt.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

class JuzzioShift {
  final String id;
  final String userId;
  final String? roomId;
  final DateTime date;
  final String code;
  final String note;
  final String ownerName;
  const JuzzioShift({required this.id, required this.userId, required this.roomId, required this.date, required this.code, required this.note, this.ownerName = ''});

  static JuzzioShift fromMap(Map<String, dynamic> m) {
    final prof = m['profiles'];
    return JuzzioShift(
      id: (m['id'] ?? '').toString(),
      userId: (m['user_id'] ?? '').toString(),
      roomId: m['room_id']?.toString(),
      date: DateTime.tryParse('${m['shift_date']}') ?? DateTime.now(),
      code: (m['shift_code'] ?? 'custom').toString(),
      note: (m['note'] ?? '').toString(),
      ownerName: prof is Map ? ((prof['display_name'] ?? '').toString().isNotEmpty ? prof['display_name'].toString() : (prof['username'] ?? '').toString()) : '',
    );
  }
}

const List<String> kJuzzioShiftCodes = ['morning_08_16', 'evening_16_00', 'night_00_08', 'overtime', 'off_day', 'annual_leave', 'custom'];

Color juzzioShiftColor(String code) {
  switch (code) {
    case 'morning_08_16':
      return const Color(0xFFFFB300);
    case 'evening_16_00':
      return const Color(0xFFFF7043);
    case 'night_00_08':
      return const Color(0xFF5C6BC0);
    case 'overtime':
      return const Color(0xFFE53935);
    case 'off_day':
      return const Color(0xFF43A047);
    case 'annual_leave':
      return const Color(0xFF26A69A);
    default:
      return const Color(0xFF78909C);
  }
}

String juzzioShiftLabel(String code, JuzzioAppController app) {
  switch (code) {
    case 'morning_08_16':
      return app.trEn('Sabah 08-16', 'Morning 08-16', 'Früh 08-16');
    case 'evening_16_00':
      return app.trEn('Akşam 16-00', 'Evening 16-00', 'Spät 16-00');
    case 'night_00_08':
      return app.trEn('Gece 00-08', 'Night 00-08', 'Nacht 00-08');
    case 'overtime':
      return app.trEn('Fazla mesai', 'Overtime', 'Überstunden');
    case 'off_day':
      return app.trEn('İzinli', 'Day off', 'Frei');
    case 'annual_leave':
      return app.trEn('Yıllık izin', 'Annual leave', 'Urlaub');
    default:
      return app.trEn('Özel', 'Custom', 'Individuell');
  }
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class JuzzioShiftPlannerScreen extends StatefulWidget {
  const JuzzioShiftPlannerScreen({super.key, this.groups = const []});
  /// Paylaşılabilecek grup sohbetleri (kimlik → ad)
  final List<MapEntry<String, String>> groups;

  static Future<void> open(BuildContext context, {List<MapEntry<String, String>> groups = const []}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioShiftPlannerScreen(groups: groups)));

  @override
  State<JuzzioShiftPlannerScreen> createState() => _JuzzioShiftPlannerScreenState();
}

class _JuzzioShiftPlannerScreenState extends State<JuzzioShiftPlannerScreen> {
  final _app = JuzzioAppController.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, JuzzioShift> _mine = {};
  String? _teamRoom;
  List<JuzzioShift> _team = [];
  bool _loading = true;
  String? _error;
  late List<MapEntry<String, String>> _groups = widget.groups;

  @override
  void initState() {
    super.initState();
    _load();
    if (_groups.isEmpty) _loadGroups();
  }

  /// Üyesi olunan grup sohbetleri (RLS: rooms yalnız üyeye görünür)
  Future<void> _loadGroups() async {
    try {
      final rows = await SupabaseService.instance.client.from('rooms').select('id, title').eq('is_group', true).order('updated_at', ascending: false).limit(50);
      if (!mounted) return;
      setState(() => _groups = [
            for (final r in rows as List) MapEntry((r['id'] ?? '').toString(), (r['title'] ?? '').toString()),
          ]);
    } catch (_) {}
  }

  Future<void> _load() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final from = DateTime(_month.year, _month.month, 1);
      final to = DateTime(_month.year, _month.month + 1, 0);
      final rows = await SupabaseService.instance.client
          .from('user_shifts')
          .select()
          .eq('user_id', uid)
          .gte('shift_date', _ymd(from))
          .lte('shift_date', _ymd(to));
      final mine = <String, JuzzioShift>{};
      for (final r in rows as List) {
        final s = JuzzioShift.fromMap(Map<String, dynamic>.from(r as Map));
        mine[_ymd(s.date)] = s;
      }
      var team = <JuzzioShift>[];
      if (_teamRoom != null) {
        final now = DateTime.now();
        final t = await SupabaseService.instance.client
            .from('user_shifts')
            .select('*, profiles(display_name, username)')
            .eq('room_id', _teamRoom!)
            .gte('shift_date', _ymd(now))
            .lte('shift_date', _ymd(now.add(const Duration(days: 6))))
            .order('shift_date');
        team = [for (final r in t as List) JuzzioShift.fromMap(Map<String, dynamic>.from(r as Map))];
      }
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _team = team;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = SupabaseService.instance.friendlyError(e);
        });
      }
    }
  }

  Future<void> _editDay(DateTime day) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    final existing = _mine[_ymd(day)];
    String? code = existing?.code;
    String? room = existing?.roomId;
    final note = TextEditingController(text: existing?.note ?? '');
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuzzioPalette(_app.isDark).sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${day.day}.${day.month}.${day.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in kJuzzioShiftCodes)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: juzzioShiftColor(c), radius: 6),
                  label: Text(juzzioShiftLabel(c, _app)),
                  selected: code == c,
                  onSelected: (_) => setS(() => code = c),
                ),
            ]),
            if (_groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: room,
                decoration: InputDecoration(labelText: _app.trEn('Ekip grubuyla paylaş', 'Share with team group', 'Mit Teamgruppe teilen')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(_app.trEn('Paylaşma (yalnız ben)', 'Don\'t share (only me)', 'Nicht teilen (nur ich)'))),
                  for (final g in _groups) DropdownMenuItem<String?>(value: g.key, child: Text(g.value)),
                ],
                onChanged: (v) => setS(() => room = v),
              ),
            ],
            TextField(controller: note, maxLength: 500, decoration: InputDecoration(labelText: _app.trEn('Not (isteğe bağlı)', 'Note (optional)', 'Notiz (optional)'))),
            Row(children: [
              if (existing != null)
                TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(_app.trEn('Sil', 'Delete', 'Löschen'), style: const TextStyle(color: Colors.redAccent))),
              const Spacer(),
              FilledButton(onPressed: code == null ? null : () => Navigator.pop(ctx, 'save'), child: Text(_app.trEn('Kaydet', 'Save', 'Speichern'))),
            ]),
          ]),
        ),
      ),
    );
    try {
      final db = SupabaseService.instance.client.from('user_shifts');
      if (res == 'delete' && existing != null) {
        await db.delete().eq('id', existing.id);
      } else if (res == 'save' && code != null) {
        await db.upsert({
          'user_id': uid,
          'shift_date': _ymd(day),
          'shift_code': code,
          'room_id': room,
          'note': note.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,shift_date');
      } else {
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    } finally {
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7; // Pazartesi başlangıç
    final today = DateTime.now();
    final counts = <String, int>{};
    for (final s in _mine.values) {
      counts[s.code] = (counts[s.code] ?? 0) + 1;
    }
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(title: Text(_app.trEn('Vardiya planım', 'My shifts', 'Meine Schichten'))),
      body: JuzzioClothRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month - 1));
              _load();
            }),
            Expanded(child: Text('${_month.month.toString().padLeft(2, '0')}.${_month.year}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month + 1));
              _load();
            }),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final w in [_app.trEn('Pt', 'Mo', 'Mo'), _app.trEn('Sa', 'Tu', 'Di'), _app.trEn('Ça', 'We', 'Mi'), _app.trEn('Pe', 'Th', 'Do'), _app.trEn('Cu', 'Fr', 'Fr'), _app.trEn('Ct', 'Sa', 'Sa'), _app.trEn('Pz', 'Su', 'So')])
                Center(child: Text(w, style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w700, fontSize: 12))),
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                Builder(builder: (_) {
                  final day = DateTime(_month.year, _month.month, d);
                  final s = _mine[_ymd(day)];
                  final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
                  final c = s == null ? null : juzzioShiftColor(s.code);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _editDay(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c?.withValues(alpha: 0.85) ?? p.textMuted.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: isToday ? Border.all(color: JuzzioColors.blue600, width: 2) : null,
                      ),
                      alignment: Alignment.center,
                      child: Text('$d', style: TextStyle(color: c != null ? Colors.white : p.textPrimary, fontWeight: FontWeight.w700)),
                    ),
                  );
                }),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 6, children: [
            for (final c in kJuzzioShiftCodes)
              Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 5, backgroundColor: juzzioShiftColor(c)),
                const SizedBox(width: 4),
                Text('${juzzioShiftLabel(c, _app)}${counts[c] != null ? ' (${counts[c]})' : ''}', style: TextStyle(color: p.textSecondary, fontSize: 12)),
              ]),
          ]),
          if (_groups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(_app.trEn('Ekip takvimi (7 gün)', 'Team calendar (7 days)', 'Teamkalender (7 Tage)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            DropdownButton<String?>(
              value: _teamRoom,
              isExpanded: true,
              hint: Text(_app.trEn('Grup seç', 'Choose a group', 'Gruppe wählen')),
              items: [for (final g in _groups) DropdownMenuItem<String?>(value: g.key, child: Text(g.value))],
              onChanged: (v) {
                setState(() => _teamRoom = v);
                _load();
              },
            ),
            if (_teamRoom != null && _team.isEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(_app.trEn('Bu grupta paylaşılmış vardiya yok.', 'No shared shifts in this group.', 'Keine geteilten Schichten.'), style: TextStyle(color: p.textSecondary))),
            for (final s in _team)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 8, backgroundColor: juzzioShiftColor(s.code)),
                title: Text('${s.ownerName} · ${juzzioShiftLabel(s.code, _app)}'),
                subtitle: Text('${s.date.day}.${s.date.month}${s.note.isNotEmpty ? ' · ${s.note}' : ''}'),
              ),
          ],
        ]),
      ),
    );
  }
}
