// =============================================================================
// JUZZIO v0.9.0 — Yaşam Merkezi (son talimat §4.1: Ana Sayfa > Görevlerim / Takvimim)
//  Görev listesi (Bugün · Yaklaşan · Tarihsiz · Tamamlananlar), takvim görünümü, görev
//  oluşturma/düzenleme/silme, hatırlatma. Yeni ana sekme DEĞİL — Ana Sayfa'dan açılır.
//  Durumlar: yükleniyor / boş / hata (tekrar dene) / çevrimdışı hatası; sahte veri yok.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_life_service.dart';
import '../services/supabase_service.dart';
import 'shift_planner_screen.dart';
import '../widgets/juzzio_cloth_refresh.dart';
import '../widgets/juzzio_motion.dart';

enum JuzzioLifeView { list, calendar, done }

class JuzzioLifeCenterPage extends StatefulWidget {
  const JuzzioLifeCenterPage({super.key, this.initialView = JuzzioLifeView.list, this.openNewTask = false});
  final JuzzioLifeView initialView;
  final bool openNewTask;

  static Future<void> open(BuildContext context, {JuzzioLifeView view = JuzzioLifeView.list, bool newTask = false}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => JuzzioLifeCenterPage(initialView: view, openNewTask: newTask),
      ));

  @override
  State<JuzzioLifeCenterPage> createState() => _JuzzioLifeCenterPageState();
}

class _JuzzioLifeCenterPageState extends State<JuzzioLifeCenterPage> {
  final _svc = JuzzioLifeService.instance;
  final _app = JuzzioAppController.instance;
  late JuzzioLifeView _view = widget.initialView;
  bool _loading = true;
  Object? _error;
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.openNewTask) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editTask(null);
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _svc.refresh();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
      if (mounted) setState(() {});
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _confirmDelete(JuzzioLifeTask t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('Silinsin mi?', 'Delete?', 'Löschen?')),
        content: Text(t.isMessageReminder
            ? _app.trEn('Bu mesaj hatırlatıcısı silinecek.', 'This message reminder will be deleted.', 'Diese Erinnerung wird gelöscht.')
            : _app.trEn('"${t.title}" kalıcı olarak silinecek.', '"${t.title}" will be deleted permanently.', '"${t.title}" wird dauerhaft gelöscht.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_app.trEn('Sil', 'Delete', 'Löschen'))),
        ],
      ),
    );
    if (ok == true) await _run(() => _svc.deleteTask(t.id));
  }

  Future<void> _editTask(JuzzioLifeTask? existing, {DateTime? presetDay, bool reminderFocus = false}) async {
    final saved = await showJuzzioSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JuzzioTaskEditor(existing: existing, presetDay: presetDay, reminderFocus: reminderFocus),
    );
    if (saved == true && mounted) setState(() {});
  }

  String _fmt(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}.${d.month}.${d.year} $hh:$mm';
  }

  Widget _tile(JuzzioLifeTask t, JuzzioPalette p) {
    final w = t.when;
    final overdue = !t.isDone && w != null && w.isBefore(DateTime.now()) && !JuzzioLifeMath.sameDay(w, DateTime.now());
    final title = t.isMessageReminder ? _app.trEn('Mesajı yanıtla', 'Reply to message', 'Auf Nachricht antworten') : t.title;
    return Semantics(
      label: '${t.isDone ? _app.trEn('Tamamlandı', 'Done', 'Erledigt') : ''} $title',
      child: ListTile(
        leading: Checkbox(
          value: t.isDone,
          onChanged: (v) => _run(() => _svc.setDone(t.id, v == true)),
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            decoration: t.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          [
            if (w != null) _fmt(w),
            if (t.remindAt != null && !t.isDone) '⏰',
            if (t.description.isNotEmpty) t.description,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: overdue ? p.dangerRed : p.textSecondary, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: _app.trEn('Seçenekler', 'Options', 'Optionen'),
          onSelected: (v) {
            if (v == 'edit') _editTask(t);
            if (v == 'delete') _confirmDelete(t);
          },
          itemBuilder: (_) => [
            if (!t.isMessageReminder) PopupMenuItem(value: 'edit', child: Text(_app.trEn('Düzenle', 'Edit', 'Bearbeiten'))),
            PopupMenuItem(value: 'delete', child: Text(_app.trEn('Sil', 'Delete', 'Löschen'))),
          ],
        ),
        onTap: t.isMessageReminder ? null : () => _editTask(t),
      ),
    );
  }

  Widget _section(String title, List<JuzzioLifeTask> items, JuzzioPalette p) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JuzzioGlass(
        radius: 20,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Semantics(
                header: true,
                child: Text('$title (${items.length})', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
              ),
            ),
            for (final t in items) _tile(t, p),
          ],
        ),
      ),
    );
  }

  Widget _empty(JuzzioPalette p, String text) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.checklist_rounded, size: 48, color: p.textMuted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
          ],
        ),
      );

  Widget _body(JuzzioPalette p) {
    if (_loading && !_svc.loaded) return const Center(child: JuzzioOrbitLoader());
    if (_error != null && !_svc.loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: p.textMuted),
            const SizedBox(height: 8),
            Text(SupabaseService.instance.friendlyError(_error!), textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(_app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'))),
          ]),
        ),
      );
    }
    final g = JuzzioLifeMath.group(_svc.tasks, DateTime.now());
    switch (_view) {
      case JuzzioLifeView.done:
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (g.done.isEmpty) _empty(p, _app.trEn('Henüz tamamlanan görev yok.', 'No completed tasks yet.', 'Noch keine erledigten Aufgaben.')),
          _section(_app.trEn('Tamamlananlar', 'Completed', 'Erledigt'), g.done, p),
        ]);
      case JuzzioLifeView.calendar:
        final dayTasks = _svc.tasks.where((t) => t.when != null && JuzzioLifeMath.sameDay(t.when!, _selectedDay)).toList()
          ..sort((a, b) => a.when!.compareTo(b.when!));
        return ListView(padding: const EdgeInsets.all(16), children: [
          JuzzioGlass(
            radius: 20,
            child: CalendarDatePicker(
              initialDate: _selectedDay,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              onDateChanged: (d) => setState(() => _selectedDay = d),
            ),
          ),
          const SizedBox(height: 12),
          if (dayTasks.isEmpty)
            _empty(p, _app.trEn('Bu gün için görev yok.', 'No tasks for this day.', 'Keine Aufgaben an diesem Tag.')),
          _section(_app.trEn('Seçilen gün', 'Selected day', 'Ausgewählter Tag'), dayTasks, p),
        ]);
      case JuzzioLifeView.list:
        final none = g.overdue.isEmpty && g.today.isEmpty && g.upcoming.isEmpty && g.undated.isEmpty;
        return JuzzioClothRefresh(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (none)
              _empty(p, _app.trEn('Açık görevin yok. "+ Görev Ekle" ile başla.', 'No open tasks. Start with "+ Add Task".',
                  'Keine offenen Aufgaben. Mit „+ Aufgabe“ beginnen.')),
            _section(_app.trEn('Gecikmiş', 'Overdue', 'Überfällig'), g.overdue, p),
            _section(_app.trEn('Bugün', 'Today', 'Heute'), g.today, p),
            _section(_app.trEn('Yaklaşan', 'Upcoming', 'Anstehend'), g.upcoming, p),
            _section(_app.trEn('Tarihsiz', 'No date', 'Ohne Datum'), g.undated, p),
          ]),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_app, _svc]),
      builder: (context, _) {
        final p = JuzzioPalette(_app.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(_app.trEn('Yaşam Merkezi', 'Life Center', 'Lebenszentrale')),
            actions: [
              // v0.9.4: vardiya planlayıcı (08-16 / 16-00 / 00-08, ekip takvimi)
              IconButton(
                tooltip: _app.trEn('Vardiya planım', 'My shifts', 'Meine Schichten'),
                icon: const Icon(Icons.work_history_rounded),
                onPressed: () => JuzzioShiftPlannerScreen.open(context),
              ),
              IconButton(
                tooltip: _app.trEn('Bugün', 'Today', 'Heute'),
                icon: const Icon(Icons.today_rounded),
                onPressed: () => setState(() {
                  _view = JuzzioLifeView.list;
                  _selectedDay = DateTime.now();
                }),
              ),
              IconButton(
                tooltip: _app.trEn('Takvime Git', 'Go to calendar', 'Zum Kalender'),
                icon: const Icon(Icons.calendar_month_rounded),
                onPressed: () => setState(() => _view = JuzzioLifeView.calendar),
              ),
              IconButton(
                tooltip: _app.trEn('Tamamlananlar', 'Completed', 'Erledigt'),
                icon: const Icon(Icons.task_alt_rounded),
                onPressed: () => setState(() => _view = JuzzioLifeView.done),
              ),
            ],
          ),
          body: _body(p),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'life_reminder',
                tooltip: _app.trEn('+ Hatırlatma', '+ Reminder', '+ Erinnerung'),
                onPressed: () => _editTask(null, reminderFocus: true),
                child: const Icon(Icons.alarm_add_rounded),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'life_task',
                onPressed: () => _editTask(null, presetDay: _view == JuzzioLifeView.calendar ? _selectedDay : null),
                icon: const Icon(Icons.add_rounded),
                label: Text(_app.trEn('Görev Ekle', 'Add Task', 'Aufgabe')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JuzzioTaskEditor extends StatefulWidget {
  const _JuzzioTaskEditor({this.existing, this.presetDay, this.reminderFocus = false});
  final JuzzioLifeTask? existing;
  final DateTime? presetDay;
  final bool reminderFocus;

  @override
  State<_JuzzioTaskEditor> createState() => _JuzzioTaskEditorState();
}

class _JuzzioTaskEditorState extends State<_JuzzioTaskEditor> {
  final _app = JuzzioAppController.instance;
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  DateTime? _date;
  TimeOfDay? _time;
  late String _remind;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final w = widget.existing?.dueAt ?? widget.presetDay ?? (widget.reminderFocus ? DateTime.now().add(const Duration(hours: 1)) : null);
    if (w != null) {
      _date = DateTime(w.year, w.month, w.day);
      _time = widget.existing?.dueAt != null || widget.reminderFocus ? TimeOfDay(hour: w.hour, minute: w.minute) : null;
    }
    _remind = widget.existing?.remindAt != null ? 'at' : (widget.reminderFocus ? 'at' : 'none');
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  DateTime? get _due {
    final d = _date;
    if (d == null) return null;
    final t = _time ?? const TimeOfDay(hour: 9, minute: 0);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = _app.trEn('Başlık gerekli.', 'Title is required.', 'Titel erforderlich.'));
      return;
    }
    final due = _due;
    final remind = JuzzioLifeMath.remindFor(due, _remind);
    if (remind != null && remind.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
      setState(() => _error = _app.trEn('Hatırlatma zamanı geçmişte olamaz.', 'Reminder time cannot be in the past.',
          'Erinnerungszeit darf nicht in der Vergangenheit liegen.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = JuzzioLifeService.instance;
      final ex = widget.existing;
      if (ex == null) {
        await svc.createTask(title: _title.text, description: _desc.text, dueAt: due, remindAt: remind);
      } else {
        await svc.updateTask(ex.id,
            title: _title.text, description: _desc.text, dueAt: due, remindAt: remind, clearDates: due == null || remind == null);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = SupabaseService.instance.friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final due = _due;
    final style = TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: JuzzioGlass(
            radius: 24,
            color: p.sheetBg,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.existing == null
                        ? _app.trEn('Yeni görev', 'New task', 'Neue Aufgabe')
                        : _app.trEn('Görevi düzenle', 'Edit task', 'Aufgabe bearbeiten'),
                    style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    maxLength: 200,
                    autofocus: widget.existing == null,
                    textInputAction: TextInputAction.next,
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(labelText: _app.trEn('Başlık', 'Title', 'Titel')),
                  ),
                  TextField(
                    controller: _desc,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(labelText: _app.trEn('Açıklama', 'Description', 'Beschreibung')),
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded),
                      label: Text(_date == null
                          ? _app.trEn('Tarih', 'Date', 'Datum')
                          : '${_date!.day}.${_date!.month}.${_date!.year}'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => _date = d);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(_time == null ? _app.trEn('Saat', 'Time', 'Uhrzeit') : _time!.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
                        if (t != null) {
                          setState(() {
                            _time = t;
                            _date ??= DateTime.now();
                          });
                        }
                      },
                    ),
                    if (_date != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _date = null;
                          _time = null;
                          _remind = 'none';
                        }),
                        child: Text(_app.trEn('Tarihi kaldır', 'Clear date', 'Datum entfernen')),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: due == null ? 'none' : _remind,
                    decoration: InputDecoration(labelText: _app.trEn('Hatırlatma', 'Reminder', 'Erinnerung')),
                    dropdownColor: p.cardBg,
                    items: [
                      DropdownMenuItem(value: 'none', child: Text(_app.trEn('Yok', 'None', 'Keine'))),
                      DropdownMenuItem(value: 'at', child: Text(_app.trEn('Zamanında', 'At time', 'Zur Zeit'))),
                      DropdownMenuItem(value: '10m', child: Text(_app.trEn('10 dk önce', '10 min before', '10 Min. vorher'))),
                      DropdownMenuItem(value: '1h', child: Text(_app.trEn('1 saat önce', '1 hour before', '1 Std. vorher'))),
                      DropdownMenuItem(value: '1d', child: Text(_app.trEn('1 gün önce', '1 day before', '1 Tag vorher'))),
                    ],
                    onChanged: due == null ? null : (v) => setState(() => _remind = v ?? 'none'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: p.dangerRed, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: JuzzioOrbitLoader(strokeWidth: 2))
                        : Text(_app.trEn('Kaydet', 'Save', 'Speichern')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
