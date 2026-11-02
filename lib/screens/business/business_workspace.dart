// =============================================================================
// JUZZIO v0.9.0 — Business > İş Alanı (son talimat §5.4)
//  Alt bölümler (yeni ana sekme DEĞİL): Randevular · Hizmetler · Ekip · Görevler · Analizler ·
//  Otomasyonlar. Analizler yalnız gerçek veriden (business_overview); veri yoksa boş durum.
//  Ekip rolleri uygulama personel rolleriyle karışmaz; rol/izin kontrolü sunucuda.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_business_service.dart';
import '../../services/supabase_service.dart';
import 'business_customers.dart';
import 'business_shell.dart';

String _wt(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);
void _wsnack(BuildContext c, String s) => ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(s)));

/// Randevu oluştur/düzenle (true = kaydedildi)
Future<bool> juzzioEditAppointmentDialog(BuildContext context, {String? customerId, Map<String, dynamic>? existing}) async {
  final svc = JuzzioBusinessService.instance;
  List<Map<String, dynamic>> customers = const [], services = const [];
  Map<String, String> names = const {};
  try {
    customers = await svc.customers();
    services = await svc.services();
    names = await svc.memberNames();
  } catch (e) {
    if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
    return false;
  }
  if (!context.mounted) return false;
  String? cust = existing?['customer_id']?.toString() ?? customerId;
  String? service = existing?['service_id']?.toString();
  String? who = existing?['assignee_id']?.toString();
  DateTime? start = DateTime.tryParse(existing?['starts_at']?.toString() ?? '')?.toLocal();
  final desc = TextEditingController(text: existing?['description']?.toString() ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(existing == null ? _wt('Randevu Oluştur', 'Create appointment', 'Termin erstellen') : _wt('Randevuyu Düzenle', 'Edit appointment', 'Termin bearbeiten')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String?>(
              isExpanded: true,
              value: customers.any((c) => c['id'].toString() == cust) ? cust : null,
              hint: Text(_wt('Müşteri', 'Customer', 'Kunde')),
              items: [for (final c in customers) DropdownMenuItem<String?>(value: c['id'].toString(), child: Text(c['name'].toString()))],
              onChanged: (v) => setD(() => cust = v),
            ),
            DropdownButton<String?>(
              isExpanded: true,
              value: services.any((s) => s['id'].toString() == service) ? service : null,
              hint: Text(_wt('Hizmet', 'Service', 'Leistung')),
              items: [for (final s in services.where((s) => s['is_active'] == true)) DropdownMenuItem<String?>(value: s['id'].toString(), child: Text('${s['name']} (${s['duration_min']} dk)'))],
              onChanged: (v) => setD(() => service = v),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded),
              label: Text(start == null ? _wt('Tarih ve saat', 'Date & time', 'Datum & Zeit') : juzzioFmtDateTime(start)),
              onPressed: () async {
                final d = await juzzioPickDateTime(ctx, initial: start);
                if (d != null) setD(() => start = d);
              },
            ),
            DropdownButton<String?>(
              isExpanded: true,
              value: names.containsKey(who) ? who : null,
              hint: Text(_wt('Sorumlu çalışan', 'Responsible member', 'Verantwortlich')),
              items: [for (final e in names.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value))],
              onChanged: (v) => setD(() => who = v),
            ),
            TextField(controller: desc, maxLength: 2000, maxLines: 3, decoration: InputDecoration(labelText: _wt('Açıklama', 'Description', 'Beschreibung'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    ),
  );
  var saved = false;
  if (ok == true) {
    if (start == null) {
      if (context.mounted) _wsnack(context, _wt('Tarih ve saat gerekli', 'Date and time required', 'Datum und Zeit erforderlich'));
    } else {
      final dur = (services.where((s) => s['id'].toString() == service).firstOrNull?['duration_min'] as num?)?.toInt() ?? 30;
      final values = {
        'customer_id': cust,
        'service_id': service,
        'assignee_id': who,
        'starts_at': start!.toUtc().toIso8601String(),
        'ends_at': start!.add(Duration(minutes: dur)).toUtc().toIso8601String(),
        'description': desc.text.trim(),
        if (existing != null) 'reminded_at': null, // saat değişirse yeniden hatırlatılır
      };
      try {
        if (existing == null) {
          await svc.insert('business_appointments', values);
        } else {
          await svc.update('business_appointments', existing['id'].toString(), values);
        }
        saved = true;
      } catch (e) {
        if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
      }
    }
  }
  desc.dispose();
  return saved;
}

/// Görev oluştur (true = kaydedildi)
Future<bool> juzzioEditTaskDialog(BuildContext context, {String? customerId}) async {
  final svc = JuzzioBusinessService.instance;
  Map<String, String> names = const {};
  try {
    names = await svc.memberNames();
  } catch (_) {}
  if (!context.mounted) return false;
  final title = TextEditingController();
  final desc = TextEditingController();
  String? who;
  DateTime? due;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(_wt('Görev oluştur', 'Create task', 'Aufgabe erstellen')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, maxLength: 200, autofocus: true, decoration: InputDecoration(labelText: _wt('Başlık', 'Title', 'Titel'))),
            TextField(controller: desc, maxLength: 2000, maxLines: 3, decoration: InputDecoration(labelText: _wt('Açıklama', 'Description', 'Beschreibung'))),
            DropdownButton<String?>(
              isExpanded: true,
              value: who,
              hint: Text(_wt('Çalışana ata', 'Assign to member', 'Zuweisen')),
              items: [for (final e in names.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value))],
              onChanged: (v) => setD(() => who = v),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(due == null ? _wt('Son tarih', 'Due date', 'Fällig') : juzzioFmtDateTime(due)),
              onPressed: () async {
                final d = await juzzioPickDateTime(ctx);
                if (d != null) setD(() => due = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    ),
  );
  var saved = false;
  if (ok == true && title.text.trim().isNotEmpty) {
    try {
      await svc.insert('business_tasks', {
        'title': title.text.trim(),
        'description': desc.text.trim(),
        if (who != null) 'assignee_id': who,
        if (customerId != null) 'customer_id': customerId,
        if (due != null) 'due_at': due!.toUtc().toIso8601String(),
      });
      saved = true;
    } catch (e) {
      if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
    }
  }
  title.dispose();
  desc.dispose();
  return saved;
}

class JuzzioBusinessWorkspaceTab extends StatelessWidget {
  const JuzzioBusinessWorkspaceTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    final items = <(IconData, String, Widget Function())>[
      (Icons.event_available_rounded, _wt('Randevular', 'Appointments', 'Termine'), () => const _AppointmentsPage()),
      (Icons.design_services_rounded, _wt('Hizmetler ve katalog', 'Services & catalog', 'Leistungen'), () => const _ServicesPage()),
      (Icons.groups_rounded, _wt('Ekip', 'Team', 'Team'), () => const _TeamPage()),
      (Icons.task_alt_rounded, _wt('Görevler', 'Tasks', 'Aufgaben'), () => const _TasksPage()),
      (Icons.insights_rounded, _wt('Analizler', 'Analytics', 'Analysen'), () => const _AnalyticsPage()),
      (Icons.smart_toy_outlined, _wt('Otomasyonlar', 'Automations', 'Automationen'), () => const _AutomationsInfoPage()),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: p.sheetBg, foregroundColor: p.textPrimary, elevation: 0, title: Text(_wt('İş Alanı', 'Workspace', 'Arbeitsbereich'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: JuzzioGlass(
              radius: 18,
              child: ListTile(
                leading: Icon(i.$1, color: p.amberGlow),
                title: Text(i.$2, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => i.$3())),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Ortak alt sayfa iskeleti
class _SubPage extends StatelessWidget {
  const _SubPage({required this.title, required this.body, this.fab});
  final String title;
  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(backgroundColor: p.sheetBg, foregroundColor: p.textPrimary, elevation: 0, title: Text(title)),
      floatingActionButton: fab,
      body: body,
    );
  }
}

class _AppointmentsPage extends StatefulWidget {
  const _AppointmentsPage();
  @override
  State<_AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<_AppointmentsPage> {
  final _svc = JuzzioBusinessService.instance;
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _f = _load();
  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async => (await _svc.appointments(), await _svc.customers());
  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return _SubPage(
      title: _wt('Randevular', 'Appointments', 'Termine'),
      fab: FloatingActionButton.extended(
        onPressed: () async {
          if (await juzzioEditAppointmentDialog(context)) _reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(_wt('Randevu Oluştur', 'Create appointment', 'Termin')),
      ),
      body: JuzzioAsyncSection<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        future: _f,
        isEmpty: (d) => d.$1.isEmpty,
        emptyText: _wt('Henüz randevu yok.', 'No appointments yet.', 'Noch keine Termine.'),
        builder: (d) {
          final cust = {for (final c in d.$2) c['id'].toString(): c['name'].toString()};
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            for (final a in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: JuzzioGlass(
                  radius: 16,
                  child: ListTile(
                    leading: Icon(a['status'] == 'cancelled' ? Icons.event_busy_rounded : Icons.event_rounded,
                        color: a['status'] == 'cancelled' ? p.dangerRed : p.amberGlow),
                    title: Text('${juzzioFmtDateTime(DateTime.tryParse(a['starts_at'].toString()))} · ${cust[a['customer_id']?.toString()] ?? ''}',
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                    subtitle: Text('${a['status']} ${a['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        try {
                          switch (v) {
                            case 'edit':
                            case 'time':
                              if (await juzzioEditAppointmentDialog(context, existing: a)) _reload();
                            case 'cancel':
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  content: Text(_wt('Randevu iptal edilsin mi?', 'Cancel this appointment?', 'Termin absagen?')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Back', 'Zurück'))),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('İptal Et', 'Cancel it', 'Absagen'))),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _svc.update('business_appointments', a['id'].toString(), {'status': 'cancelled'});
                                _reload();
                              }
                            case 'done':
                              await _svc.update('business_appointments', a['id'].toString(), {'status': 'completed'});
                              _reload();
                            case 'customer':
                              final cid = a['customer_id']?.toString();
                              if (cid != null) {
                                await JuzzioBusinessCustomerDetailPage.open(context, customerId: cid, onOpenRoom: (_) {});
                              }
                          }
                        } catch (e) {
                          if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(_wt('Randevuyu Düzenle', 'Edit', 'Bearbeiten'))),
                        PopupMenuItem(value: 'time', child: Text(_wt('Saati Değiştir', 'Change time', 'Zeit ändern'))),
                        PopupMenuItem(value: 'done', child: Text(_wt('Tamamlandı', 'Completed', 'Erledigt'))),
                        PopupMenuItem(value: 'cancel', child: Text(_wt('İptal Et', 'Cancel', 'Absagen'))),
                        PopupMenuItem(value: 'customer', child: Text(_wt('Müşteriyi Görüntüle', 'View customer', 'Kunde ansehen'))),
                      ],
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _ServicesPage extends StatefulWidget {
  const _ServicesPage();
  @override
  State<_ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<_ServicesPage> {
  final _svc = JuzzioBusinessService.instance;
  late Future<List<Map<String, dynamic>>> _f = _svc.services();

  Future<void> _edit([Map<String, dynamic>? s]) async {
    final name = TextEditingController(text: s?['name']?.toString() ?? '');
    final dur = TextEditingController(text: '${s?['duration_min'] ?? 30}');
    final price = TextEditingController(text: s?['price_text']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_wt('Hizmet', 'Service', 'Leistung')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 120, decoration: InputDecoration(labelText: _wt('Ad', 'Name', 'Name'))),
          TextField(controller: dur, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _wt('Süre (dk)', 'Duration (min)', 'Dauer (Min)'))),
          TextField(controller: price, maxLength: 40, decoration: InputDecoration(labelText: _wt('Fiyat (metin)', 'Price (text)', 'Preis'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final values = {'name': name.text.trim(), 'duration_min': (int.tryParse(dur.text) ?? 30).clamp(5, 1440), 'price_text': price.text.trim()};
      try {
        if (s == null) {
          await _svc.insert('business_services', values);
        } else {
          await _svc.update('business_services', s['id'].toString(), values);
        }
        setState(() => _f = _svc.services());
      } catch (e) {
        if (mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
      }
    }
    for (final c in [name, dur, price]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SubPage(
      title: _wt('Hizmetler ve katalog', 'Services & catalog', 'Leistungen'),
      fab: FloatingActionButton(onPressed: () => _edit(), tooltip: _wt('Hizmet ekle', 'Add service', 'Hinzufügen'), child: const Icon(Icons.add_rounded)),
      body: JuzzioAsyncSection<List<Map<String, dynamic>>>(
        future: _f,
        isEmpty: (l) => l.isEmpty,
        emptyText: _wt('Hizmet tanımlanmamış.', 'No services yet.', 'Keine Leistungen.'),
        builder: (l) => ListView(padding: const EdgeInsets.all(16), children: [
          for (final s in l)
            SwitchListTile(
              title: Text('${s['name']} · ${s['duration_min']} dk ${s['price_text'] ?? ''}'),
              value: s['is_active'] == true,
              onChanged: (v) async {
                try {
                  await _svc.update('business_services', s['id'].toString(), {'is_active': v});
                  setState(() => _f = _svc.services());
                } catch (e) {
                  if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
                }
              },
              secondary: IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _edit(s)),
            ),
        ]),
      ),
    );
  }
}

class _TeamPage extends StatefulWidget {
  const _TeamPage();
  @override
  State<_TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<_TeamPage> {
  final _svc = JuzzioBusinessService.instance;
  late Future<(List<Map<String, dynamic>>, Map<String, String>)> _f = _load();
  Future<(List<Map<String, dynamic>>, Map<String, String>)> _load() async => (await _svc.members(), await _svc.memberNames());

  static const roles = ['admin', 'manager', 'support_agent', 'content_manager', 'moderator', 'analyst'];

  String _roleLabel(String r) => switch (r) {
        'owner' => _wt('Sahip', 'Owner', 'Inhaber'),
        'admin' => _wt('Yönetici', 'Admin', 'Admin'),
        'manager' => _wt('Müdür', 'Manager', 'Manager'),
        'support_agent' => _wt('Destek', 'Support agent', 'Support'),
        'content_manager' => _wt('İçerik yöneticisi', 'Content manager', 'Content-Manager'),
        'moderator' => _wt('Moderatör', 'Moderator', 'Moderator'),
        'analyst' => _wt('Analist', 'Analyst', 'Analyst'),
        _ => r,
      };

  String _permsText(String r) => switch (r) {
        'owner' => _wt('Tüm yetkiler', 'All permissions', 'Alle Rechte'),
        'admin' => _wt('Gelen kutusu, müşteriler, randevu, görev, ekip, analiz, otomasyon, profil', 'Inbox, customers, appointments, tasks, team, analytics, automation, profile', 'Alles außer Schließen'),
        'manager' => _wt('Gelen kutusu + atama, müşteriler, randevu, görev, ekip (okuma), analiz', 'Inbox + assign, customers, appointments, tasks, team (read), analytics', ''),
        'support_agent' => _wt('Gelen kutusu, müşteriler, randevu, görev', 'Inbox, customers, appointments, tasks', ''),
        'content_manager' => _wt('Analiz, görevler', 'Analytics, tasks', ''),
        'moderator' => _wt('Gelen kutusu ve müşteriler (okuma), görevler', 'Inbox and customers (read), tasks', ''),
        'analyst' => _wt('Analiz, müşteriler (okuma)', 'Analytics, customers (read)', ''),
        _ => '',
      };

  Future<void> _invite() async {
    final u = TextEditingController();
    var role = 'support_agent';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_wt('Çalışan Davet Et', 'Invite member', 'Mitglied einladen')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: u, decoration: InputDecoration(labelText: _wt('Kullanıcı adı', 'Username', 'Benutzername'), prefixText: '@')),
            DropdownButton<String>(
              isExpanded: true,
              value: role,
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(_roleLabel(r)))],
              onChanged: (v) => setD(() => role = v ?? role),
            ),
            Text(_permsText(role), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('Davet et', 'Invite', 'Einladen'))),
          ],
        ),
      ),
    );
    if (ok == true && u.text.trim().isNotEmpty) {
      try {
        await _svc.inviteMember(u.text.replaceAll('@', ''), role);
        if (mounted) _wsnack(context, _wt('Davet gönderildi', 'Invitation sent', 'Einladung gesendet'));
        setState(() => _f = _load());
      } catch (e) {
        if (mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
      }
    }
    u.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return _SubPage(
      title: _wt('Ekip', 'Team', 'Team'),
      fab: FloatingActionButton.extended(onPressed: _invite, icon: const Icon(Icons.person_add_rounded), label: Text(_wt('Çalışan Davet Et', 'Invite', 'Einladen'))),
      body: JuzzioAsyncSection<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: _f,
        builder: (d) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          for (final m in d.$1.where((m) => m['status'] != 'removed' && m['status'] != 'declined'))
            JuzzioGlass(
              radius: 16,
              child: ListTile(
                title: Text(d.$2[m['user_id'].toString()] ?? (m['status'] == 'invited' ? _wt('Davet bekliyor', 'Invitation pending', 'Einladung offen') : m['user_id'].toString()),
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                subtitle: Text('${_roleLabel(m['role'].toString())} · ${m['status']}\n${_permsText(m['role'].toString())}', style: const TextStyle(fontSize: 12)),
                isThreeLine: true,
                trailing: m['role'] == 'owner'
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (v) async {
                          try {
                            if (v == 'remove') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  content: Text(_wt('Erişim kaldırılsın mı? Atandığı konuşmalar sahibine döner.', 'Remove access? Their conversations return to the owner.', 'Zugriff entfernen?')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_wt('Vazgeç', 'Cancel', 'Abbrechen'))),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_wt('Erişimi Kaldır', 'Remove access', 'Entfernen'))),
                                  ],
                                ),
                              );
                              if (ok == true) await _svc.setMember(m['user_id'].toString(), remove: true);
                            } else {
                              await _svc.setMember(m['user_id'].toString(), role: v);
                            }
                            setState(() => _f = _load());
                          } catch (e) {
                            if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
                          }
                        },
                        itemBuilder: (_) => [
                          for (final r in roles) PopupMenuItem(value: r, child: Text('${_wt('Rol Ata', 'Assign role', 'Rolle')}: ${_roleLabel(r)}')),
                          PopupMenuItem(value: 'remove', child: Text(_wt('Erişimi Kaldır', 'Remove access', 'Zugriff entfernen'))),
                        ],
                      ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _TasksPage extends StatefulWidget {
  const _TasksPage();
  @override
  State<_TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<_TasksPage> {
  final _svc = JuzzioBusinessService.instance;
  late Future<(List<Map<String, dynamic>>, Map<String, String>)> _f = _load();
  Future<(List<Map<String, dynamic>>, Map<String, String>)> _load() async => (await _svc.tasks(), await _svc.memberNames());

  @override
  Widget build(BuildContext context) {
    return _SubPage(
      title: _wt('Görevler', 'Tasks', 'Aufgaben'),
      fab: FloatingActionButton(
        tooltip: _wt('Görev oluştur', 'Create task', 'Aufgabe'),
        onPressed: () async {
          if (await juzzioEditTaskDialog(context)) setState(() => _f = _load());
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: JuzzioAsyncSection<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: _f,
        isEmpty: (d) => d.$1.isEmpty,
        emptyText: _wt('Görev yok.', 'No tasks.', 'Keine Aufgaben.'),
        builder: (d) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          for (final t in d.$1)
            CheckboxListTile(
              value: t['done_at'] != null,
              title: Text(t['title'].toString()),
              subtitle: Text([d.$2[t['assignee_id']?.toString()] ?? '', juzzioFmtDateTime(DateTime.tryParse(t['due_at']?.toString() ?? ''))].where((e) => e.isNotEmpty).join(' · ')),
              onChanged: (v) async {
                try {
                  await _svc.update('business_tasks', t['id'].toString(), {'done_at': v == true ? DateTime.now().toUtc().toIso8601String() : null});
                  setState(() => _f = _load());
                } catch (e) {
                  if (context.mounted) _wsnack(context, SupabaseService.instance.friendlyError(e));
                }
              },
            ),
        ]),
      ),
    );
  }
}

class _AnalyticsPage extends StatefulWidget {
  const _AnalyticsPage();
  @override
  State<_AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<_AnalyticsPage> {
  int _days = 30;
  late Future<Map<String, dynamic>> _f = JuzzioBusinessService.instance.overview(days: _days);

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    Widget row(String label, Object? v, [Object? prev]) => ListTile(
          title: Text(label, style: TextStyle(color: p.textPrimary)),
          trailing: Text(prev == null ? '${v ?? 0}' : '${v ?? 0}  (${_wt('önceki', 'prev', 'vorher')}: $prev)',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        );
    return _SubPage(
      title: _wt('Analizler', 'Analytics', 'Analysen'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 7, label: Text(_wt('7 gün', '7 days', '7 Tage'))),
            ButtonSegment(value: 30, label: Text(_wt('30 gün', '30 days', '30 Tage'))),
            ButtonSegment(value: 90, label: Text(_wt('90 gün', '90 days', '90 Tage'))),
          ],
          selected: {_days},
          onSelectionChanged: (s) => setState(() {
            _days = s.first;
            _f = JuzzioBusinessService.instance.overview(days: _days);
          }),
        ),
        const SizedBox(height: 12),
        JuzzioAsyncSection<Map<String, dynamic>>(
          future: _f,
          builder: (o) => JuzzioGlass(
            radius: 18,
            child: Column(children: [
              row(_wt('Mesaj sayısı', 'Messages', 'Nachrichten'), o['messages_period'], o['messages_prev_period']),
              row(_wt('Ort. ilk yanıt süresi (dk)', 'Avg first reply (min)', 'Ø erste Antwort (Min)'), o['avg_first_reply_min'] ?? '—'),
              row(_wt('Müşteri sayısı', 'Customers', 'Kunden'), o['customers']),
              row(_wt('Yeni müşteri', 'New customers', 'Neue Kunden'), o['customers_new_period']),
              row(_wt('Randevu sayısı', 'Appointments', 'Termine'), o['appointments_period']),
              row(_wt('Tamamlanan görevler', 'Completed tasks', 'Erledigte Aufgaben'), o['tasks_done_period']),
              row(_wt('Çözülen talepler', 'Resolved requests', 'Gelöste Anfragen'), o['resolved_period']),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(_wt('Yalnız gerçek kayıtlar: gelen kutusuna eklenen konuşmalar, müşteri/randevu/görev tabloları. Örnek veri gösterilmez.',
            'Only real records are used. No sample data is shown.', 'Nur echte Daten.'), style: TextStyle(color: p.textMuted, fontSize: 11.5)),
      ]),
    );
  }
}

class _AutomationsInfoPage extends StatelessWidget {
  const _AutomationsInfoPage();

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return _SubPage(
      title: _wt('Otomasyonlar', 'Automations', 'Automationen'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        JuzzioGlass(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Text(
            _wt('Etkin otomasyonlar:\n• Karşılama ve mesai dışı otomatik yanıt (Gelen Kutusu > Ayarlar)\n• Müşteri takip hatırlatmaları (zamanı gelince sorumlu kişiye bildirim)\n• Randevu hatırlatmaları (randevudan önce sorumlu kişiye)\n\nÇalışma kaydı: otomatik yanıtlar sunucuda kaydedilir; aynı kişiye 12 saatte en fazla 1 yanıt (döngü/spam koruması).',
                'Active automations:\n• Welcome and away replies (Inbox > Settings)\n• Customer follow-up reminders\n• Appointment reminders\n\nAuto replies are logged server-side; at most 1 per person per 12 h.',
                'Aktive Automationen: Begrüßung/Abwesenheit, Nachverfolgung, Terminerinnerungen.'),
            style: TextStyle(color: p.textPrimary, height: 1.5),
          ),
        ),
      ]),
    );
  }
}
