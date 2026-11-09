// =============================================================================
// JUZZIO v0.9.0 — G26 anket kartı / oluşturma, G27 zamanlama sayfası
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_polls_service.dart';
import '../services/supabase_service.dart';

class JuzzioPollCard extends StatefulWidget {
  const JuzzioPollCard({super.key, required this.pollId, required this.isMe});
  final String pollId;
  final bool isMe;

  @override
  State<JuzzioPollCard> createState() => _JuzzioPollCardState();
}

class _JuzzioPollCardState extends State<JuzzioPollCard> {
  final _app = JuzzioAppController.instance;
  JuzzioPollResults? _r;
  bool _busy = false;
  Object? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // v0.9.4: diğer üyelerin oyları canlı görünsün (oylar RLS ile gizli; sayım RPC'den gelir)
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_busy) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await JuzzioPollsService.instance.results(widget.pollId);
      if (mounted) setState(() {
        _r = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _snack(Object e) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));

  Future<void> _tap(int i) async {
    final r = _r;
    if (r == null || r.closed || _busy) return;
    setState(() => _busy = true);
    try {
      await JuzzioPollsService.instance.vote(widget.pollId, JuzzioPollResults.nextVotes(current: r.myVotes, tapped: i, multi: r.multi));
      await _load();
    } catch (e) {
      _snack(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_app.trEn('Anketi kapat', 'Close poll', 'Umfrage schließen')),
        content: Text(_app.trEn('Kapatılan ankete artık oy verilemez.', 'No more votes can be cast.', 'Danach keine Stimmen mehr.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(_app.trEn('Kapat', 'Close', 'Schließen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await JuzzioPollsService.instance.close(widget.pollId);
      await _load();
    } catch (e) {
      _snack(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final fg = widget.isMe ? Colors.white : p.textPrimary;
    final r = _r;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _error == null
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(onPressed: _load, child: Text(_app.trEn('Anket yüklenemedi · tekrar dene', 'Poll failed to load · retry', 'Umfrage nicht geladen · erneut'))),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.question, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 4),
      Text(
        [
          if (r.multi) _app.trEn('Çoklu seçim', 'Multiple choice', 'Mehrfachauswahl'),
          if (r.anonymous) _app.trEn('Gizli oylama', 'Anonymous', 'Anonym'),
          if (r.closed) _app.trEn('Kapandı', 'Closed', 'Geschlossen'),
          '${r.voters} ${_app.trEn('kişi oy verdi', 'voted', 'abgestimmt')}',
        ].join(' · '),
        style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < r.options.length; i++)
        Semantics(
          button: !r.closed,
          selected: r.myVotes.contains(i),
          label: '${r.options[i]}, ${r.counts[i]}',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: r.closed ? null : () => _tap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(r.myVotes.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r.options[i], style: TextStyle(color: fg))),
                  Text('${r.counts[i]}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: r.share(i), minHeight: 5, backgroundColor: fg.withValues(alpha: 0.15), color: fg),
                ),
                if (r.byOption != null && (r.byOption![i] ?? const []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(r.byOption![i]!.join(', '), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
                  ),
              ]),
            ),
          ),
        ),
      if (r.isCreator && !r.closed)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _close, child: Text(_app.trEn('Anketi kapat', 'Close poll', 'Umfrage schließen'), style: TextStyle(color: fg))),
        ),
    ]);
  }
}

Future<void> showJuzzioCreatePollSheet(BuildContext context, {required String roomId}) {
  final app = JuzzioAppController.instance;
  final q = TextEditingController();
  final opts = [TextEditingController(), TextEditingController()];
  var multi = false;
  var anonymous = false;
  var busy = false;
  String? error;
  int? deadlineHours; // v0.9.5: süre dolunca otomatik kapanır, sonuç herkese bildirilir
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioPalette(app.isDark).sheetBg,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(app.trEn('Anket oluştur', 'Create poll', 'Umfrage erstellen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            TextField(controller: q, maxLength: 300, decoration: InputDecoration(labelText: app.trEn('Soru', 'Question', 'Frage'))),
            for (var i = 0; i < opts.length; i++)
              TextField(controller: opts[i], maxLength: 100, decoration: InputDecoration(labelText: '${app.trEn('Seçenek', 'Option', 'Option')} ${i + 1}')),
            if (opts.length < 10)
              TextButton.icon(
                onPressed: () => setS(() => opts.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded),
                label: Text(app.trEn('Seçenek ekle', 'Add option', 'Option hinzufügen')),
              ),
            SwitchListTile(value: multi, onChanged: (v) => setS(() => multi = v), title: Text(app.trEn('Çoklu seçim', 'Multiple choice', 'Mehrfachauswahl'))),
            SwitchListTile(
              value: anonymous,
              onChanged: (v) => setS(() => anonymous = v),
              title: Text(app.trEn('Gizli oylama', 'Anonymous voting', 'Anonyme Abstimmung')),
              subtitle: Text(app.trEn('Kimin neye oy verdiği kimseye gösterilmez', 'Nobody sees who voted for what', 'Niemand sieht, wer wofür stimmte')),
            ),
            Text(app.trEn('Otomatik kapanış', 'Auto close', 'Automatisch schließen'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, children: [
              for (final h in const [0, 1, 24, 72])
                ChoiceChip(
                  label: Text(h == 0 ? app.trEn('Yok', 'None', 'Keine') : (h < 24 ? app.trEn('$h saat', '$h h', '$h Std.') : app.trEn('${h ~/ 24} gün', '${h ~/ 24} d', '${h ~/ 24} T.'))),
                  selected: (deadlineHours ?? 0) == h,
                  onSelected: (_) => setS(() => deadlineHours = h == 0 ? null : h),
                ),
            ]),
            const SizedBox(height: 8),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final options = opts.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                      if (q.text.trim().isEmpty || options.length < 2) {
                        setS(() => error = app.trEn('Soru ve en az 2 seçenek gerekli', 'A question and at least 2 options are required', 'Frage und mind. 2 Optionen nötig'));
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final pollId = await JuzzioPollsService.instance.createPoll(roomId: roomId, question: q.text.trim(), options: options, multi: multi, anonymous: anonymous);
                        if (deadlineHours != null) {
                          await SupabaseService.instance.client.rpc('poll_set_deadline', params: {
                            'p_poll': pollId,
                            'p_closes_at': DateTime.now().toUtc().add(Duration(hours: deadlineHours!)).toIso8601String(),
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        // v0.9.4: hata sayfanın içinde gösterilir — önceden snackbar alttaki sayfaya
                        // düşüp görünmüyordu ve anket "hiçbir şey olmuyor" gibi bozuk görünüyordu
                        setS(() {
                          busy = false;
                          error = SupabaseService.instance.friendlyError(e);
                        });
                      }
                    },
              child: Text(app.trEn('Gönder', 'Send', 'Senden')),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Metni ileri bir zamana planlar; aynı sayfada bu sohbetteki bekleyen planları listeler/iptal eder.
Future<bool> showJuzzioScheduleSheet(BuildContext context, {required String roomId, required String text}) async {
  final app = JuzzioAppController.instance;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioPalette(app.isDark).sheetBg,
    builder: (ctx) => _ScheduleSheet(roomId: roomId, text: text),
  );
  return result == true;
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.roomId, required this.text});
  final String roomId;
  final String text;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _app = JuzzioAppController.instance;
  List<JuzzioScheduledMessage> _pending = const [];
  DateTime _at = DateTime.now().add(const Duration(hours: 1));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await JuzzioPollsService.instance.pending(widget.roomId);
      if (mounted) setState(() => _pending = l);
    } catch (_) {}
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _schedule() async {
    if (_at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      _snack(_app.trEn('En az 1 dakika sonrası seçilmeli', 'Pick a time at least 1 minute ahead', 'Mindestens 1 Minute in der Zukunft'));
      return;
    }
    setState(() => _busy = true);
    try {
      await JuzzioPollsService.instance.schedule(roomId: widget.roomId, sendAt: _at, text: widget.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime t) => '${t.day}.${t.month}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_app.trEn('Mesajı zamanla', 'Schedule message', 'Nachricht planen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (widget.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded),
            title: Text(_fmt(_at)),
            trailing: TextButton(onPressed: _pick, child: Text(_app.trEn('Değiştir', 'Change', 'Ändern'))),
          ),
          FilledButton(onPressed: _busy ? null : _schedule, child: Text(_app.trEn('Zamanla', 'Schedule', 'Planen'))),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_app.trEn('Zamanlamak için önce mesajı yaz.', 'Type a message first to schedule it.', 'Zuerst Nachricht eingeben.')),
          ),
        if (_pending.isNotEmpty) ...[
          const Divider(),
          Text(_app.trEn('Bekleyen planlar', 'Pending', 'Ausstehend'), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final s in _pending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(s.encrypted ? Icons.lock_clock_rounded : Icons.schedule_send_rounded),
              title: Text(s.encrypted ? _app.trEn('Şifreli mesaj', 'Encrypted message', 'Verschlüsselte Nachricht') : s.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_fmt(s.sendAt)),
              trailing: IconButton(
                tooltip: _app.trEn('İptal et', 'Cancel', 'Abbrechen'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  try {
                    await JuzzioPollsService.instance.cancel(s.id);
                    await _load();
                  } catch (e) {
                    _snack(SupabaseService.instance.friendlyError(e));
                  }
                },
              ),
            ),
        ],
      ]),
    );
  }
}
