// =============================================================================
// JUZZIO v0.9.0 — G26 anket kartı / oluşturma, G27 zamanlama sayfası
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_polls_service.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

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
            ? const SizedBox(height: 24, width: 24, child: JuzzioOrbitLoader(strokeWidth: 2))
            : TextButton(onPressed: _load, child: Text(_app.trEn('Anket yüklenemedi · tekrar dene', 'Poll failed to load · retry', 'Umfrage nicht geladen · erneut'))),
      );
    }
    // v1.0.0 modern anket kartı: üst etiket + durum çipi, büyük soru, oran çubuklu seçenek
    // döşemeleri (dolgu arka planda canlı büyür), yüzde, kazanan vurgusu, alt bilgi şeridi.
    final glow = JuzzioGlassTokens.glow;
    final onGlow = JuzzioGlassTokens.onGlow;
    final sub = fg.withValues(alpha: 0.72);
    final tileBg = widget.isMe ? Colors.white.withValues(alpha: 0.12) : JuzzioGlassTokens.spaceInset;
    final fill = widget.isMe ? Colors.white.withValues(alpha: 0.24) : glow.withValues(alpha: _app.isDark ? 0.22 : 0.35);
    final maxCount = r.counts.isEmpty ? 0 : r.counts.reduce((a, b) => a > b ? a : b);
    final calm = _app.reduceMotion;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: widget.isMe ? Colors.white.withValues(alpha: 0.18) : glow, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bar_chart_rounded, size: 14, color: widget.isMe ? Colors.white : onGlow),
              const SizedBox(width: 4),
              Text(_app.trEn('ANKET', 'POLL', 'UMFRAGE'),
                  style: TextStyle(color: widget.isMe ? Colors.white : onGlow, fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 1.2)),
            ]),
          ),
          const SizedBox(width: 6),
          if (r.multi) _chip(_app.trEn('Çoklu', 'Multi', 'Mehrfach'), Icons.done_all_rounded, fg),
          if (r.anonymous) _chip(_app.trEn('Gizli', 'Anonymous', 'Anonym'), Icons.visibility_off_outlined, fg),
          const Spacer(),
          _chip(r.closed ? _app.trEn('Kapandı', 'Closed', 'Beendet') : _app.trEn('Açık', 'Open', 'Offen'),
              r.closed ? Icons.lock_outline_rounded : Icons.circle, fg, dot: !r.closed),
        ]),
        const SizedBox(height: 10),
        Text(r.question, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 16.5, height: 1.25, letterSpacing: -0.2)),
        const SizedBox(height: 12),
        for (var i = 0; i < r.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: !r.closed,
              selected: r.myVotes.contains(i),
              label: '${r.options[i]}, ${r.counts[i]}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: r.closed ? null : () => _tap(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: r.myVotes.contains(i)
                            ? (widget.isMe ? Colors.white : glow)
                            : (widget.isMe ? Colors.white.withValues(alpha: 0.18) : JuzzioGlassTokens.spaceCardBorder),
                        width: r.myVotes.contains(i) ? 1.6 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(children: [
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: r.share(i)),
                              duration: Duration(milliseconds: calm ? 0 : 650),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, __) => FractionallySizedBox(widthFactor: v.clamp(0.0, 1.0), heightFactor: 1, child: ColoredBox(color: fill)),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          child: Row(children: [
                            AnimatedSwitcher(
                              duration: Duration(milliseconds: calm ? 0 : 200),
                              child: r.myVotes.contains(i)
                                  ? Container(
                                      key: const ValueKey('on'),
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(color: widget.isMe ? Colors.white : glow, shape: BoxShape.circle),
                                      child: Icon(Icons.check_rounded, size: 14, color: widget.isMe ? Colors.black : onGlow),
                                    )
                                  : Container(
                                      key: const ValueKey('off'),
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        shape: r.multi ? BoxShape.rectangle : BoxShape.circle,
                                        borderRadius: r.multi ? BorderRadius.circular(6) : null,
                                        border: Border.all(color: sub, width: 1.6),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(r.options[i],
                                  style: TextStyle(color: fg, fontWeight: r.myVotes.contains(i) ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                            ),
                            if (r.closed && maxCount > 0 && r.counts[i] == maxCount) ...[
                              Icon(Icons.emoji_events_rounded, size: 16, color: widget.isMe ? Colors.white : JuzzioGlassTokens.glowText),
                              const SizedBox(width: 4),
                            ],
                            Text('${(r.share(i) * 100).round()}%', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 13)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (r.byOption != null)
          for (var i = 0; i < r.options.length; i++)
            if ((r.byOption![i] ?? const []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${r.options[i]}: ${r.byOption![i]!.join(', ')}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 11.5)),
              ),
        const SizedBox(height: 2),
        Row(children: [
          Icon(Icons.how_to_vote_outlined, size: 15, color: sub),
          const SizedBox(width: 5),
          Text('${r.voters} ${_app.trEn('oy', r.voters == 1 ? 'vote' : 'votes', 'Stimmen')}',
              style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (r.isCreator && !r.closed)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
              onPressed: _close,
              icon: const Icon(Icons.lock_outline_rounded, size: 15),
              label: Text(_app.trEn('Kapat', 'Close', 'Schließen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ]),
      ]),
    );
  }

  Widget _chip(String label, IconData icon, Color fg, {bool dot = false}) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: dot ? 7 : 12, color: dot ? JuzzioGlassTokens.glow : fg.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10.5, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
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
  return showJuzzioSheet<void>(
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
            JuzzioSwitchListTile(value: multi, onChanged: (v) => setS(() => multi = v), title: Text(app.trEn('Çoklu seçim', 'Multiple choice', 'Mehrfachauswahl'))),
            JuzzioSwitchListTile(style: JuzzioToggleStyle.check,
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
  final result = await showJuzzioSheet<bool>(
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
  // v1.2.0: mesaj artık bu sayfada yazılır (önce yazma kutusuna yazmak gerekmez)
  late final TextEditingController _text = TextEditingController(text: widget.text.trim());

  @override
  void initState() {
    super.initState();
    _at = DateTime(_at.year, _at.month, _at.day, _at.hour, (_at.minute ~/ 5) * 5);
    _text.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await JuzzioPollsService.instance.pending(widget.roomId);
      if (mounted) setState(() => _pending = l);
    } catch (_) {}
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null || !mounted) return;
    setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  void _preset(Duration d) => setState(() => _at = DateTime.now().add(d));

  void _tomorrowMorning() {
    final n = DateTime.now().add(const Duration(days: 1));
    setState(() => _at = DateTime(n.year, n.month, n.day, 9, 0));
  }

  Future<void> _schedule() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _snack(_app.trEn('Zamanlanacak mesajı yaz', 'Write the message to schedule', 'Nachricht eingeben'));
      return;
    }
    if (_at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      _snack(_app.trEn('En az 1 dakika sonrası seçilmeli', 'Pick a time at least 1 minute ahead', 'Mindestens 1 Minute in der Zukunft'));
      return;
    }
    setState(() => _busy = true);
    try {
      await JuzzioPollsService.instance.schedule(roomId: widget.roomId, sendAt: _at, text: text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');
  String _fmt(DateTime t) => '${t.day}.${t.month}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';
  String _dateLabel(DateTime t) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(t, now)) return _app.trEn('Bugün', 'Today', 'Heute');
    if (DateUtils.isSameDay(t, now.add(const Duration(days: 1)))) return _app.trEn('Yarın', 'Tomorrow', 'Morgen');
    return '${_two(t.day)}.${_two(t.month)}.${t.year}';
  }

  Widget _picker({required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return Expanded(
      child: Material(
        color: JuzzioGlassTokens.surfaceStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: JuzzioGlassTokens.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Icon(icon, color: JuzzioGlassTokens.glowText, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  Text(value, style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    return Padding(
      padding: EdgeInsets.only(left: 18, right: 18, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: JuzzioGlassTokens.glow.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.schedule_send_rounded, color: JuzzioGlassTokens.glowText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_app.trEn('Mesajı zamanla', 'Schedule message', 'Nachricht planen'), style: TextStyle(color: tc, fontWeight: FontWeight.w900, fontSize: 18)),
                Text(_app.trEn('Seçtiğin anda otomatik gönderilir', 'Sent automatically at the chosen time', 'Wird zur gewählten Zeit gesendet'),
                    style: TextStyle(color: t2, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: widget.text.trim().isEmpty,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: tc, fontSize: 15, height: 1.4),
            decoration: InputDecoration(
              hintText: _app.trEn('Mesajını yaz…', 'Write your message…', 'Nachricht schreiben…'),
              hintStyle: TextStyle(color: t2),
              filled: true,
              fillColor: JuzzioGlassTokens.surfaceStrong,
              counterStyle: TextStyle(color: t2),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: JuzzioGlassTokens.glow, width: 1.4)),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            _picker(icon: Icons.calendar_month_rounded, label: _app.trEn('Tarih', 'Date', 'Datum'), value: _dateLabel(_at), onTap: _pickDate),
            const SizedBox(width: 10),
            _picker(icon: Icons.access_time_filled_rounded, label: _app.trEn('Saat', 'Time', 'Uhrzeit'), value: '${_two(_at.hour)}:${_two(_at.minute)}', onTap: _pickTime),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: Text(_app.trEn('1 saat sonra', 'In 1 hour', 'In 1 Std.')), onPressed: () => _preset(const Duration(hours: 1))),
            ActionChip(label: Text(_app.trEn('3 saat sonra', 'In 3 hours', 'In 3 Std.')), onPressed: () => _preset(const Duration(hours: 3))),
            ActionChip(label: Text(_app.trEn('Yarın 09:00', 'Tomorrow 09:00', 'Morgen 09:00')), onPressed: _tomorrowMorning),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: JuzzioGlassTokens.accentFill,
                foregroundColor: JuzzioGlassTokens.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _busy || _text.text.trim().isEmpty ? null : _schedule,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: JuzzioOrbitLoader(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.schedule_send_rounded),
              label: Text('${_app.trEn('Zamanla', 'Schedule', 'Planen')} · ${_dateLabel(_at)} ${_two(_at.hour)}:${_two(_at.minute)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          if (_pending.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(_app.trEn('Bekleyen planlar', 'Pending', 'Ausstehend'), style: TextStyle(color: tc, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final s in _pending)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: JuzzioGlassTokens.surface, borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  dense: true,
                  leading: Icon(s.encrypted ? Icons.lock_clock_rounded : Icons.schedule_send_rounded, color: JuzzioGlassTokens.glowText),
                  title: Text(s.encrypted ? _app.trEn('Şifreli mesaj', 'Encrypted message', 'Verschlüsselte Nachricht') : s.preview,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: tc)),
                  subtitle: Text(_fmt(s.sendAt), style: TextStyle(color: t2)),
                  trailing: IconButton(
                    tooltip: _app.trEn('İptal et', 'Cancel', 'Abbrechen'),
                    icon: Icon(Icons.close_rounded, color: t2),
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
              ),
          ],
        ]),
      ),
    );
  }
}
