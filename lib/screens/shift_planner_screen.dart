// =============================================================================
// JUZZIO v0.9.4 — Vardiya planlayıcı (08-16 · 16-00 · 00-08 · izin · fazla mesai)
//  v1.0.0: TARİH ARALIĞI ile toplu planlama — başlangıç/bitiş günü + saatler (gece yarısını
//  aşan vardiyalar dahil, ör. 00:00–12:00 veya 20:00–08:00), isteğe bağlı hafta içi/sonu
//  seçimi, grupla paylaşım ve gruba "plan güncellendi" mesajı. Tek kayıtla tüm günler yazılır.
//  • Kendi vardiya takvimin (ay görünümü, güne dokun → vardiya seç).
//  • Vardiyayı bir grup sohbetiyle paylaşırsan grup üyeleri "Ekip takvimi"nde görür
//    (RLS: yalnız o grubun üyeleri). Gün başına tek kayıt.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';
import '../widgets/juzzio_motion.dart';

class JuzzioShift {
  final String id;
  final String userId;
  final String? roomId;
  final DateTime date;
  final String code;
  final String note;
  final String ownerName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  const JuzzioShift({
    required this.id,
    required this.userId,
    required this.roomId,
    required this.date,
    required this.code,
    required this.note,
    this.ownerName = '',
    this.startsAt,
    this.endsAt,
  });

  /// "00:00–12:00" (saat yoksa boş)
  String get hoursLabel {
    final a = startsAt, b = endsAt;
    if (a == null || b == null) return '';
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${hm(a)}–${hm(b)}';
  }

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
      startsAt: DateTime.tryParse('${m['starts_at'] ?? ''}')?.toLocal(),
      endsAt: DateTime.tryParse('${m['ends_at'] ?? ''}')?.toLocal(),
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

/// Hazır vardiyaların varsayılan saatleri (izin/fazla mesai için yok)
(TimeOfDay, TimeOfDay)? juzzioShiftDefaultHours(String code) {
  switch (code) {
    case 'morning_08_16':
      return (const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 16, minute: 0));
    case 'evening_16_00':
      return (const TimeOfDay(hour: 16, minute: 0), const TimeOfDay(hour: 0, minute: 0));
    case 'night_00_08':
      return (const TimeOfDay(hour: 0, minute: 0), const TimeOfDay(hour: 8, minute: 0));
    default:
      return null;
  }
}

/// v1.0.0: tarih aralığından toplu vardiya kayıtları üretir (saf fonksiyon, test edilir).
///  • [from]..[to] dahil her gün; [weekdays] (1=Pzt … 7=Paz) boşsa tüm günler.
///  • Bitiş saati başlangıçtan önce/eşitse vardiya ERTESİ GÜN biter (gece vardiyası).
///  • En fazla 92 gün (bir çeyrek) — yanlışlıkla yıllık kayıt oluşmasın.
List<Map<String, dynamic>> juzzioBuildShiftRows({
  required String userId,
  required DateTime from,
  required DateTime to,
  required String code,
  TimeOfDay? start,
  TimeOfDay? end,
  String? roomId,
  String note = '',
  Set<int> weekdays = const {},
}) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  if (b.isBefore(a)) return const [];
  final rows = <Map<String, dynamic>>[];
  final now = DateTime.now().toUtc().toIso8601String();
  for (var d = a; !d.isAfter(b) && rows.length < 92; d = DateTime(d.year, d.month, d.day + 1)) {
    if (weekdays.isNotEmpty && !weekdays.contains(d.weekday)) continue;
    DateTime? s, e;
    if (start != null && end != null) {
      s = DateTime(d.year, d.month, d.day, start.hour, start.minute);
      e = DateTime(d.year, d.month, d.day, end.hour, end.minute);
      if (!e.isAfter(s)) e = e.add(const Duration(days: 1));
    }
    rows.add({
      'user_id': userId,
      'shift_date': _ymd(d),
      'shift_code': code,
      'room_id': roomId,
      'note': note,
      'starts_at': s?.toUtc().toIso8601String(),
      'ends_at': e?.toUtc().toIso8601String(),
      'updated_at': now,
    });
  }
  return rows;
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
            .lte('shift_date', _ymd(now.add(const Duration(days: 13))))
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
    TimeOfDay? start = existing?.startsAt != null ? TimeOfDay.fromDateTime(existing!.startsAt!) : null;
    TimeOfDay? end = existing?.endsAt != null ? TimeOfDay.fromDateTime(existing!.endsAt!) : null;
    final note = TextEditingController(text: existing?.note ?? '');
    final res = await showJuzzioSheet<String>(
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
                  onSelected: (_) => setS(() {
                    code = c;
                    final h = juzzioShiftDefaultHours(c);
                    if (h != null) {
                      start = h.$1;
                      end = h.$2;
                    } else if (!_needsHours(c)) {
                      start = null;
                      end = null;
                    }
                  }),
                ),
            ]),
            if (code != null && _needsHours(code!)) ...[
              const SizedBox(height: 12),
              _hoursRow(ctx, start, end, (a, b) => setS(() {
                    start = a;
                    end = b;
                  })),
            ],
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
        final rows = juzzioBuildShiftRows(
          userId: uid,
          from: day,
          to: day,
          code: code!,
          start: _needsHours(code!) ? start : null,
          end: _needsHours(code!) ? end : null,
          roomId: room,
          note: note.text.trim(),
        );
        await db.upsert(rows, onConflict: 'user_id,shift_date');
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

  static bool _needsHours(String code) => code != 'off_day' && code != 'annual_leave';

  String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Başlangıç–bitiş saati seçici (bitiş başlangıçtan önceyse ertesi gün biter)
  Widget _hoursRow(BuildContext ctx, TimeOfDay? start, TimeOfDay? end, void Function(TimeOfDay?, TimeOfDay?) onChanged) {
    Future<void> pick(bool isStart) async {
      final t = await showTimePicker(
        context: ctx,
        initialTime: (isStart ? start : end) ?? (isStart ? const TimeOfDay(hour: 8, minute: 0) : const TimeOfDay(hour: 16, minute: 0)),
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
      );
      if (t == null) return;
      isStart ? onChanged(t, end) : onChanged(start, t);
    }

    final overnight = start != null && end != null && (end.hour * 60 + end.minute) <= (start.hour * 60 + start.minute);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pick(true),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(start == null ? _app.trEn('Başlangıç', 'Start', 'Beginn') : _hm(start)),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18)),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => pick(false),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(end == null ? _app.trEn('Bitiş', 'End', 'Ende') : _hm(end)),
          ),
        ),
      ]),
      if (overnight)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_app.trEn('Gece vardiyası: ertesi gün biter', 'Overnight: ends the next day', 'Nachtschicht: endet am Folgetag'),
              style: TextStyle(color: JuzzioGlassTokens.glowText, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
    ]);
  }

  /// v1.0.0: tarih aralığıyla toplu vardiya — "bir hafta boyunca 00:00–12:00" tek seferde
  Future<void> _addRange() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    final now = DateTime.now();
    DateTimeRange range = DateTimeRange(start: DateTime(now.year, now.month, now.day), end: DateTime(now.year, now.month, now.day + 6));
    var code = 'custom';
    TimeOfDay? start = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay? end = const TimeOfDay(hour: 16, minute: 0);
    final days = <int>{1, 2, 3, 4, 5, 6, 7};
    String? room = _teamRoom;
    var notify = true;
    var busy = false;
    String? error;
    final note = TextEditingController();
    final dayNames = [
      _app.trEn('Pt', 'Mo', 'Mo'), _app.trEn('Sa', 'Tu', 'Di'), _app.trEn('Ça', 'We', 'Mi'), _app.trEn('Pe', 'Th', 'Do'),
      _app.trEn('Cu', 'Fr', 'Fr'), _app.trEn('Ct', 'Sa', 'Sa'), _app.trEn('Pz', 'Su', 'So'),
    ];
    String dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    final saved = await showJuzzioSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuzzioPalette(_app.isDark).sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final rows = juzzioBuildShiftRows(
            userId: uid,
            from: range.start,
            to: range.end,
            code: code,
            start: _needsHours(code) ? start : null,
            end: _needsHours(code) ? end : null,
            roomId: room,
            note: note.text.trim(),
            weekdays: days.length == 7 ? const {} : days,
          );
          return Padding(
            padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(ctx).viewInsets.bottom + 18),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_app.trEn('Tarih aralığı planla', 'Plan a date range', 'Zeitraum planen'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                const SizedBox(height: 4),
                Text(_app.trEn('Aralığı ve saatleri seç; tüm günler tek seferde kaydedilir.', 'Pick the range and hours; every day is saved at once.',
                    'Zeitraum und Uhrzeiten wählen; alle Tage werden auf einmal gespeichert.'), style: TextStyle(color: JuzzioGlassTokens.textSecondary)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                      initialDateRange: range,
                    );
                    if (r != null) setS(() => range = r);
                  },
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text('${dm(range.start)} – ${dm(range.end)}.${range.end.year}  ·  ${range.duration.inDays + 1} ${_app.trEn('gün', 'days', 'Tage')}'),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in kJuzzioShiftCodes)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: juzzioShiftColor(c), radius: 6),
                      label: Text(juzzioShiftLabel(c, _app)),
                      selected: code == c,
                      onSelected: (_) => setS(() {
                        code = c;
                        final h = juzzioShiftDefaultHours(c);
                        if (h != null) {
                          start = h.$1;
                          end = h.$2;
                        }
                      }),
                    ),
                ]),
                if (_needsHours(code)) ...[
                  const SizedBox(height: 12),
                  _hoursRow(ctx, start, end, (a, b) => setS(() {
                        start = a;
                        end = b;
                      })),
                ],
                const SizedBox(height: 12),
                Text(_app.trEn('Günler', 'Days', 'Tage'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (var w = 1; w <= 7; w++)
                    FilterChip(
                      label: Text(dayNames[w - 1]),
                      selected: days.contains(w),
                      onSelected: (v) => setS(() {
                        if (v) {
                          days.add(w);
                        } else if (days.length > 1) {
                          days.remove(w);
                        }
                      }),
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
                  if (room != null)
                    JuzzioSwitchListTile(style: JuzzioToggleStyle.check,
                      contentPadding: EdgeInsets.zero,
                      value: notify,
                      onChanged: (v) => setS(() => notify = v),
                      title: Text(_app.trEn('Gruba bildir', 'Notify the group', 'Gruppe benachrichtigen')),
                      subtitle: Text(_app.trEn('Grup sohbetine plan özeti gönderilir', 'A plan summary is posted to the group chat', 'Eine Planübersicht wird im Gruppenchat gepostet')),
                    ),
                ],
                TextField(
                  controller: note,
                  maxLength: 500,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: _app.trEn('Not (isteğe bağlı)', 'Note (optional)', 'Notiz (optional)')),
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
                FilledButton.icon(
                  onPressed: busy || rows.isEmpty || (_needsHours(code) && code == 'custom' && (start == null || end == null))
                      ? null
                      : () async {
                          setS(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await SupabaseService.instance.client.from('user_shifts').upsert(rows, onConflict: 'user_id,shift_date');
                            if (room != null && notify) {
                              final hours = _needsHours(code) && start != null && end != null ? ' · ${_hm(start!)}–${_hm(end!)}' : '';
                              await SupabaseService.instance.sendTextMessage(
                                text: '📅 ${_app.trEn('Vardiya planı', 'Shift plan', 'Schichtplan')}: ${dm(range.start)}–${dm(range.end)} · '
                                    '${juzzioShiftLabel(code, _app)}$hours (${rows.length} ${_app.trEn('gün', 'days', 'Tage')})'
                                    '${note.text.trim().isEmpty ? '' : '\n${note.text.trim()}'}',
                                targetRoomId: room,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setS(() {
                              busy = false;
                              error = SupabaseService.instance.friendlyError(e);
                            });
                          }
                        },
                  icon: busy ? const SizedBox(width: 16, height: 16, child: JuzzioOrbitLoader(strokeWidth: 2)) : const Icon(Icons.event_available_rounded),
                  label: Text(_app.trEn('${rows.length} günü kaydet', 'Save ${rows.length} days', '${rows.length} Tage speichern')),
                ),
              ]),
            ),
          );
        },
      ),
    );
    note.dispose();
    if (saved == true) {
      if (room != null) setState(() => _teamRoom = room);
      await _load();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_app.trEn('Vardiya planı kaydedildi', 'Shift plan saved', 'Schichtplan gespeichert'))));
      }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRange,
        icon: const Icon(Icons.date_range_rounded),
        label: Text(_app.trEn('Aralık planla', 'Plan range', 'Zeitraum')),
      ),
      body: JuzzioClothRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
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
          if (_loading) const JuzzioSparklerBar(minHeight: 2),
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
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$d', style: TextStyle(color: c != null ? Colors.white : p.textPrimary, fontWeight: FontWeight.w700)),
                        if (s != null && s.startsAt != null)
                          FittedBox(
                            child: Text(
                              '${s.startsAt!.hour.toString().padLeft(2, '0')}-${s.endsAt!.hour.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ]),
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
            Text(_app.trEn('Ekip takvimi (14 gün)', 'Team calendar (14 days)', 'Teamkalender (14 Tage)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
                title: Text('${s.ownerName} · ${juzzioShiftLabel(s.code, _app)}${s.hoursLabel.isEmpty ? '' : ' · ${s.hoursLabel}'}'),
                subtitle: Text('${s.date.day}.${s.date.month}${s.note.isNotEmpty ? ' · ${s.note}' : ''}'),
              ),
          ],
        ]),
      ),
    );
  }
}
