// =============================================================================
// JUZZIO v0.9.4 — Grup sohbeti etkinlikleri (oluşturma sayfası + mesaj kartı)
//  Sunucu: create_room_event / rsvp_room_event / room_event_details / cancel_room_event.
//  Hatırlatma, başlangıçtan [remind] dakika önce tüm üyelere push olarak gelir (pg_cron).
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

class JuzzioEventDetails {
  final String title;
  final String description;
  final DateTime startsAt;
  final bool cancelled;
  final bool isCreator;
  final int going;
  final int maybe;
  final int declined;
  final String? myStatus;

  const JuzzioEventDetails({
    required this.title,
    required this.description,
    required this.startsAt,
    required this.cancelled,
    required this.isCreator,
    required this.going,
    required this.maybe,
    required this.declined,
    required this.myStatus,
  });

  static JuzzioEventDetails fromMap(Map<String, dynamic> m) => JuzzioEventDetails(
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        startsAt: DateTime.tryParse('${m['starts_at']}')?.toLocal() ?? DateTime.now(),
        cancelled: m['cancelled'] == true,
        isCreator: m['mine_creator'] == true,
        going: int.tryParse('${m['going']}') ?? 0,
        maybe: int.tryParse('${m['maybe']}') ?? 0,
        declined: int.tryParse('${m['declined']}') ?? 0,
        myStatus: m['my_status']?.toString(),
      );
}

String juzzioFormatEventTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} · ${two(t.hour)}:${two(t.minute)}';
}

class JuzzioEventCard extends StatefulWidget {
  const JuzzioEventCard({super.key, required this.eventId, required this.isMe});
  final String eventId;
  final bool isMe;

  @override
  State<JuzzioEventCard> createState() => _JuzzioEventCardState();
}

class _JuzzioEventCardState extends State<JuzzioEventCard> {
  final _app = JuzzioAppController.instance;
  JuzzioEventDetails? _d;
  Object? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Diğer üyelerin katılım yanıtları için hafif yenileme (kart ekrandayken)
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await SupabaseService.instance.client.rpc('room_event_details', params: {'p_event': widget.eventId});
      if (!mounted) return;
      setState(() {
        _d = JuzzioEventDetails.fromMap(Map<String, dynamic>.from(r as Map));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _rsvp(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.instance.client.rpc('rsvp_room_event', params: {'p_event': widget.eventId, 'p_status': status});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cancel() async {
    try {
      await SupabaseService.instance.client.rpc('cancel_room_event', params: {'p_event': widget.eventId});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final fg = widget.isMe ? Colors.white : p.textPrimary;
    final d = _d;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: _error == null
            ? const SizedBox(width: 24, height: 24, child: JuzzioOrbitLoader(strokeWidth: 2))
            : TextButton(onPressed: _load, child: Text(_app.trEn('Etkinlik yüklenemedi · tekrar dene', 'Event failed to load · retry', 'Termin nicht geladen · erneut'))),
      );
    }
    Widget choice(String status, String label, int count) {
      final sel = d.myStatus == status;
      return Padding(
        padding: const EdgeInsets.only(right: 6, top: 6),
        child: ChoiceChip(
          label: Text('$label · $count'),
          selected: sel,
          onSelected: d.cancelled || _busy ? null : (_) => _rsvp(status),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.event_rounded, color: fg, size: 20),
        const SizedBox(width: 6),
        Flexible(
          child: Text(d.title,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15, decoration: d.cancelled ? TextDecoration.lineThrough : null)),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        d.cancelled ? _app.trEn('İptal edildi', 'Cancelled', 'Abgesagt') : juzzioFormatEventTime(d.startsAt),
        style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12.5),
      ),
      if (d.description.trim().isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(d.description, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13)),
      ],
      Wrap(children: [
        choice('going', _app.trEn('Katılıyorum', 'Going', 'Dabei'), d.going),
        choice('maybe', _app.trEn('Belki', 'Maybe', 'Vielleicht'), d.maybe),
        choice('declined', _app.trEn('Katılmıyorum', 'Can\'t go', 'Nicht dabei'), d.declined),
      ]),
      if (d.isCreator && !d.cancelled)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _cancel, child: Text(_app.trEn('Etkinliği iptal et', 'Cancel event', 'Termin absagen'), style: TextStyle(color: fg))),
        ),
    ]);
  }
}

/// Grup sohbetinde etkinlik oluşturur. Başarıda true döner.
Future<bool> showJuzzioCreateEventSheet(BuildContext context, {required String roomId}) async {
  final app = JuzzioAppController.instance;
  final title = TextEditingController();
  final desc = TextEditingController();
  var when = DateTime.now().add(const Duration(hours: 1));
  when = DateTime(when.year, when.month, when.day, when.hour, 0);
  var remind = 15;
  var busy = false;
  String? error;
  final ok = await showJuzzioSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioPalette(app.isDark).sheetBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(app.trEn('Etkinlik planla', 'Plan an event', 'Termin planen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            TextField(controller: title, maxLength: 150, decoration: InputDecoration(labelText: app.trEn('Başlık', 'Title', 'Titel'))),
            TextField(controller: desc, maxLength: 1000, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: app.trEn('Açıklama (isteğe bağlı)', 'Description (optional)', 'Beschreibung (optional)'))),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(juzzioFormatEventTime(when)),
              subtitle: Text(app.trEn('Tarih ve saat', 'Date and time', 'Datum und Uhrzeit')),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: when,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                if (t == null) return;
                setS(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
            ),
            Text(app.trEn('Hatırlatma', 'Reminder', 'Erinnerung'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 8, children: [
              for (final m in const [0, 15, 60, 1440])
                ChoiceChip(
                  label: Text(m == 0
                      ? app.trEn('Başlarken', 'At start', 'Bei Beginn')
                      : m == 1440
                          ? app.trEn('1 gün önce', '1 day before', '1 Tag vorher')
                          : app.trEn('$m dk önce', '$m min before', '$m Min. vorher')),
                  selected: remind == m,
                  onSelected: (_) => setS(() => remind = m),
                ),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty) {
                        setS(() => error = app.trEn('Başlık gerekli', 'A title is required', 'Titel erforderlich'));
                        return;
                      }
                      if (!when.isAfter(DateTime.now())) {
                        setS(() => error = app.trEn('Geçmiş bir zaman seçilemez', 'Pick a future time', 'Bitte eine zukünftige Zeit wählen'));
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await SupabaseService.instance.client.rpc('create_room_event', params: {
                          'p_room': roomId,
                          'p_title': title.text.trim(),
                          'p_starts_at': when.toUtc().toIso8601String(),
                          'p_description': desc.text.trim(),
                          'p_remind_minutes': remind,
                        });
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        // Hata sayfanın İÇİNDE gösterilir (snackbar alttaki sayfada kalıp görünmüyordu)
                        setS(() {
                          busy = false;
                          error = SupabaseService.instance.friendlyError(e);
                        });
                      }
                    },
              child: Text(app.trEn('Oluştur', 'Create', 'Erstellen')),
            ),
          ]),
        ),
      ),
    ),
  );
  return ok == true;
}
