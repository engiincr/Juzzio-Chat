// =============================================================================
// JUZZIO v0.9.0 — Business > Müşteriler (son talimat §5.3)
//  Liste (arama, etiket filtresi, takip durumu) + Müşteri Detayı: bilgiler, iletişim, notlar,
//  görüşme geçmişi (gelen kutusu kayıtları), randevular, görevler, takip hatırlatmaları.
//  Butonlar: Mesaj Gönder · Not Ekle · Takip Ekle · Randevu Oluştur · Görev Ata · Müşteriyi Düzenle.
//  Yetki sunucuda (customers.read / customers.write); silme onaylıdır.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_business_service.dart';
import '../../services/supabase_service.dart';
import 'business_shell.dart';
import 'business_workspace.dart';

String _bt(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

void _bsnack(BuildContext context, String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));

String juzzioFmtDateTime(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.day}.${l.month}.${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Tarih+saat seçici (geçmiş serbest/kapalı)
Future<DateTime?> juzzioPickDateTime(BuildContext context, {DateTime? initial, bool allowPast = false}) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: allowPast ? DateTime(2020) : DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial ?? now.add(const Duration(hours: 1))));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

class JuzzioBusinessCustomersTab extends StatefulWidget {
  const JuzzioBusinessCustomersTab({super.key, required this.onOpenRoom});
  final ValueChanged<String> onOpenRoom;

  @override
  State<JuzzioBusinessCustomersTab> createState() => _JuzzioBusinessCustomersTabState();
}

class _JuzzioBusinessCustomersTabState extends State<JuzzioBusinessCustomersTab> {
  final _svc = JuzzioBusinessService.instance;
  late Future<List<Map<String, dynamic>>> _f = _svc.customers();
  String _q = '';
  String? _tag;

  void _reload() => setState(() => _f = _svc.customers());

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final saved = await juzzioEditCustomerDialog(context, c);
    if (saved) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_bt('Müşteriler', 'Customers', 'Kunden')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(_bt('Müşteri ekle', 'Add customer', 'Kunde hinzufügen')),
      ),
      body: JuzzioAsyncSection<List<Map<String, dynamic>>>(
        future: _f,
        builder: (list) {
          final tags = <String>{for (final c in list) ...((c['tags'] as List?) ?? const []).map((e) => e.toString())};
          final q = _q.trim().toLowerCase();
          final shown = list.where((c) {
            if (_tag != null && !((c['tags'] as List?) ?? const []).contains(_tag)) return false;
            if (q.isEmpty) return true;
            return '${c['name']} ${c['email']} ${c['phone']}'.toLowerCase().contains(q);
          }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                style: TextStyle(color: p.textPrimary),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _bt('Müşteri ara', 'Search customers', 'Kunden suchen')),
              ),
            ),
            if (tags.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final t in tags)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: FilterChip(label: Text(t), selected: _tag == t, onSelected: (on) => setState(() => _tag = on ? t : null)),
                    ),
                ]),
              ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(_bt('Müşteri yok', 'No customers', 'Keine Kunden'), style: TextStyle(color: p.textSecondary)))
                  : RefreshIndicator(
                      onRefresh: () async => _reload(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = shown[i];
                          return JuzzioGlass(
                            radius: 16,
                            child: ListTile(
                              title: Text(c['name'].toString(), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                [
                                  if ((c['phone'] ?? '').toString().isNotEmpty) c['phone'],
                                  if (((c['tags'] as List?) ?? const []).isNotEmpty) '#${(c['tags'] as List).join(' #')}',
                                  if (c['follow_status'] == 'pending') _bt('takip bekliyor', 'follow-up pending', 'Nachverfolgung'),
                                ].join(' · '),
                                style: TextStyle(color: p.textSecondary, fontSize: 12),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () async {
                                await JuzzioBusinessCustomerDetailPage.open(context, customerId: c['id'].toString(), onOpenRoom: widget.onOpenRoom);
                                _reload();
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Müşteri ekle/düzenle (true = kaydedildi)
Future<bool> juzzioEditCustomerDialog(BuildContext context, Map<String, dynamic>? c) async {
  final name = TextEditingController(text: c?['name']?.toString() ?? '');
  final email = TextEditingController(text: c?['email']?.toString() ?? '');
  final phone = TextEditingController(text: c?['phone']?.toString() ?? '');
  final tags = TextEditingController(text: ((c?['tags'] as List?) ?? const []).join(', '));
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(c == null ? _bt('Müşteri ekle', 'Add customer', 'Kunde hinzufügen') : _bt('Müşteriyi Düzenle', 'Edit customer', 'Kunde bearbeiten')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, maxLength: 120, decoration: InputDecoration(labelText: _bt('Ad', 'Name', 'Name'), errorText: err)),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _bt('E-posta', 'Email', 'E-Mail'))),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: _bt('Telefon', 'Phone', 'Telefon'))),
            TextField(controller: tags, decoration: InputDecoration(labelText: _bt('Etiketler (virgülle)', 'Tags (comma separated)', 'Tags'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_bt('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                setD(() => err = _bt('Ad gerekli', 'Name required', 'Name erforderlich'));
                return;
              }
              final e = email.text.trim();
              if (e.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
                setD(() => err = _bt('E-posta geçersiz', 'Invalid email', 'Ungültige E-Mail'));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(_bt('Kaydet', 'Save', 'Speichern')),
          ),
        ],
      ),
    ),
  );
  var saved = false;
  if (ok == true) {
    final values = {
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone': phone.text.trim(),
      'tags': tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(20).toList(),
    };
    try {
      if (c == null) {
        await JuzzioBusinessService.instance.insert('business_customers', values);
      } else {
        await JuzzioBusinessService.instance.update('business_customers', c['id'].toString(), values);
      }
      saved = true;
    } catch (e) {
      if (context.mounted) _bsnack(context, SupabaseService.instance.friendlyError(e));
    }
  }
  for (final c in [name, email, phone, tags]) {
    c.dispose();
  }
  return saved;
}

class JuzzioBusinessCustomerDetailPage extends StatefulWidget {
  const JuzzioBusinessCustomerDetailPage({super.key, required this.customerId, required this.onOpenRoom});
  final String customerId;
  final ValueChanged<String> onOpenRoom;

  static Future<void> open(BuildContext context, {required String customerId, required ValueChanged<String> onOpenRoom}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioBusinessCustomerDetailPage(customerId: customerId, onOpenRoom: onOpenRoom)));

  @override
  State<JuzzioBusinessCustomerDetailPage> createState() => _JuzzioBusinessCustomerDetailPageState();
}

class _CustomerBundle {
  _CustomerBundle(this.customer, this.notes, this.followups, this.appointments, this.tasks, this.conversations, this.names);
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> notes, followups, appointments, tasks, conversations;
  final Map<String, String> names;
}

class _JuzzioBusinessCustomerDetailPageState extends State<JuzzioBusinessCustomerDetailPage> {
  final _svc = JuzzioBusinessService.instance;
  late Future<_CustomerBundle> _f = _load();

  Future<_CustomerBundle> _load() async {
    final custs = await _svc.customers();
    final c = custs.where((e) => e['id'].toString() == widget.customerId).firstOrNull;
    return _CustomerBundle(
      c,
      await _svc.customerChildren('business_customer_notes', widget.customerId),
      await _svc.customerChildren('business_followups', widget.customerId),
      await _svc.customerChildren('business_appointments', widget.customerId),
      await _svc.customerChildren('business_tasks', widget.customerId),
      await _svc.customerChildren('business_conversations', widget.customerId),
      await _svc.memberNames(),
    );
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _run(Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) _bsnack(context, ok);
      _reload();
    } catch (e) {
      if (mounted) _bsnack(context, SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _addNote() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_bt('Not Ekle', 'Add note', 'Notiz')),
        content: TextField(controller: c, maxLength: 4000, maxLines: 5, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_bt('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_bt('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await _run(() => _svc.insert('business_customer_notes', {'customer_id': widget.customerId, 'body': c.text.trim()}), _bt('Not eklendi', 'Note added', 'Notiz hinzugefügt'));
    }
    c.dispose();
  }

  Future<void> _addFollowup(Map<String, String> names) async {
    final title = TextEditingController();
    final desc = TextEditingController();
    DateTime? due;
    String? who;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_bt('Takip Ekle', 'Add follow-up', 'Nachverfolgung')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, maxLength: 200, decoration: InputDecoration(labelText: _bt('Takip başlığı', 'Title', 'Titel'))),
              TextField(controller: desc, maxLength: 2000, maxLines: 3, decoration: InputDecoration(labelText: _bt('Açıklama', 'Description', 'Beschreibung'))),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(due == null ? _bt('Tarih ve saat', 'Date & time', 'Datum & Zeit') : juzzioFmtDateTime(due)),
                onPressed: () async {
                  final d = await juzzioPickDateTime(ctx);
                  if (d != null) setD(() => due = d);
                },
              ),
              DropdownButton<String?>(
                isExpanded: true,
                value: who,
                hint: Text(_bt('Sorumlu çalışan', 'Responsible member', 'Verantwortlich')),
                items: [for (final e in names.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value))],
                onChanged: (v) => setD(() => who = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_bt('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_bt('Kaydet', 'Save', 'Speichern'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (title.text.trim().isEmpty || due == null) {
        if (mounted) _bsnack(context, _bt('Başlık ve tarih gerekli', 'Title and date are required', 'Titel und Datum erforderlich'));
      } else {
        await _run(() async {
          await _svc.insert('business_followups', {
            'customer_id': widget.customerId,
            'title': title.text.trim(),
            'description': desc.text.trim(),
            'due_at': due!.toUtc().toIso8601String(),
            if (who != null) 'assignee_id': who,
          });
          await _svc.update('business_customers', widget.customerId, {'follow_status': 'pending'});
        }, _bt('Takip eklendi; zamanı gelince bildirim gönderilir', 'Follow-up added; a notification will be sent when due', 'Hinzugefügt'));
      }
    }
    title.dispose();
    desc.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    Widget section(String title, List<Widget> children, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: JuzzioGlass(
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ListTile(dense: true, title: Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900)), trailing: action),
              if (children.isEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text('—', style: TextStyle(color: p.textMuted)))
              else
                ...children,
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(backgroundColor: p.sheetBg, foregroundColor: p.textPrimary, elevation: 0, title: Text(_bt('Müşteri Detayı', 'Customer details', 'Kundendetails'))),
      body: JuzzioAsyncSection<_CustomerBundle>(
        future: _f,
        builder: (b) {
          final c = b.customer;
          if (c == null) return Center(child: Text(_bt('Müşteri bulunamadı veya yetkin yok', 'Customer not found or no access', 'Nicht gefunden'), style: TextStyle(color: p.textSecondary)));
          final room = b.conversations.isNotEmpty ? b.conversations.first['room_id']?.toString() : null;
          return ListView(padding: const EdgeInsets.all(16), children: [
            section(_bt('Müşteri bilgileri', 'Customer info', 'Kundeninfo'), [
              ListTile(title: Text(c['name'].toString(), style: TextStyle(color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                  subtitle: Text(((c['tags'] as List?) ?? const []).map((e) => '#$e').join(' '))),
            ], action: IconButton(
              tooltip: _bt('Müşteriyi Düzenle', 'Edit customer', 'Bearbeiten'),
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                if (await juzzioEditCustomerDialog(context, c)) _reload();
              },
            )),
            section(_bt('İletişim', 'Contact', 'Kontakt'), [
              if ((c['phone'] ?? '').toString().isNotEmpty) ListTile(dense: true, leading: const Icon(Icons.phone_rounded), title: Text(c['phone'].toString())),
              if ((c['email'] ?? '').toString().isNotEmpty) ListTile(dense: true, leading: const Icon(Icons.email_rounded), title: Text(c['email'].toString())),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.chat_rounded),
                label: Text(_bt('Mesaj Gönder', 'Send message', 'Nachricht')),
                onPressed: room == null
                    ? null
                    : () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        widget.onOpenRoom(room);
                      },
              ),
              OutlinedButton.icon(icon: const Icon(Icons.note_add_rounded), label: Text(_bt('Not Ekle', 'Add note', 'Notiz')), onPressed: _addNote),
              OutlinedButton.icon(icon: const Icon(Icons.alarm_add_rounded), label: Text(_bt('Takip Ekle', 'Add follow-up', 'Nachverfolgung')), onPressed: () => _addFollowup(b.names)),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available_rounded),
                label: Text(_bt('Randevu Oluştur', 'Create appointment', 'Termin')),
                onPressed: () async {
                  if (await juzzioEditAppointmentDialog(context, customerId: widget.customerId)) _reload();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_ind_rounded),
                label: Text(_bt('Görev Ata', 'Assign task', 'Aufgabe')),
                onPressed: () async {
                  if (await juzzioEditTaskDialog(context, customerId: widget.customerId)) _reload();
                },
              ),
            ]),
            const SizedBox(height: 12),
            section(_bt('Notlar', 'Notes', 'Notizen'), [
              for (final n in b.notes)
                ListTile(dense: true, title: Text(n['body'].toString()), subtitle: Text('${b.names[n['author_id']?.toString()] ?? ''} · ${juzzioFmtDateTime(DateTime.tryParse(n['created_at'].toString()))}')),
            ]),
            section(_bt('Görüşme geçmişi', 'Conversation history', 'Gesprächsverlauf'), [
              for (final cv in b.conversations)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.forum_rounded),
                  title: Text('${cv['status']} · ${cv['priority']}'),
                  subtitle: Text(juzzioFmtDateTime(DateTime.tryParse(cv['last_activity_at'].toString()))),
                  onTap: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    widget.onOpenRoom(cv['room_id'].toString());
                  },
                ),
            ]),
            section(_bt('Randevular', 'Appointments', 'Termine'), [
              for (final a in b.appointments)
                ListTile(dense: true, leading: const Icon(Icons.event_rounded), title: Text(juzzioFmtDateTime(DateTime.tryParse(a['starts_at'].toString()))), subtitle: Text(a['status'].toString())),
            ]),
            section(_bt('Görevler', 'Tasks', 'Aufgaben'), [
              for (final t in b.tasks)
                CheckboxListTile(
                  dense: true,
                  value: t['done_at'] != null,
                  title: Text(t['title'].toString()),
                  onChanged: (v) => _run(() => _svc.update('business_tasks', t['id'].toString(), {'done_at': v == true ? DateTime.now().toUtc().toIso8601String() : null}),
                      _bt('Güncellendi', 'Updated', 'Aktualisiert')),
                ),
            ]),
            section(_bt('Takip hatırlatmaları', 'Follow-ups', 'Nachverfolgungen'), [
              for (final f in b.followups)
                CheckboxListTile(
                  dense: true,
                  value: f['done_at'] != null,
                  title: Text(f['title'].toString()),
                  subtitle: Text('${juzzioFmtDateTime(DateTime.tryParse(f['due_at'].toString()))} · ${b.names[f['assignee_id']?.toString()] ?? ''}'),
                  onChanged: (v) => _run(() => _svc.update('business_followups', f['id'].toString(), {'done_at': v == true ? DateTime.now().toUtc().toIso8601String() : null}),
                      _bt('Güncellendi', 'Updated', 'Aktualisiert')),
                ),
            ]),
          ]);
        },
      ),
    );
  }
}
