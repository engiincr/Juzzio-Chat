// =============================================================================
// JUZZIO v0.9.0 — Business kabuğu (son talimat §5): 5 sekme
//   Genel Bakış · Gelen Kutusu · Müşteriler · İş Alanı · Profil
// Tüm sayılar ve listeler sunucudan (RLS + yetki) gelir; veri yoksa boş durum gösterilir.
// Yetkisi olmayan bölüm sunucuda reddedilir ve burada "yetkin yok" olarak görünür.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_business_service.dart';
import '../../services/supabase_service.dart';
import 'business_customers.dart';
import 'business_inbox.dart';
import 'business_workspace.dart';

class JuzzioBusinessShell extends StatefulWidget {
  const JuzzioBusinessShell({
    super.key,
    required this.onOpenRoom,
    required this.onSwitchToPersonal,
    required this.chatRooms,
  });

  final ValueChanged<String> onOpenRoom;
  final VoidCallback onSwitchToPersonal;

  /// (oda kimliği, görünen ad, birebirde karşı taraf) — gelen kutusuna sohbet eklemek için
  final List<(String, String, String?)> Function() chatRooms;

  @override
  State<JuzzioBusinessShell> createState() => _JuzzioBusinessShellState();
}

class _JuzzioBusinessShellState extends State<JuzzioBusinessShell> {
  int _tab = 0;
  final _app = JuzzioAppController.instance;

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    String t(String tr, String en, String de) => _app.trEn(tr, en, de);
    final pages = [
      _BusinessOverviewTab(onGoTab: (i) => setState(() => _tab = i)),
      JuzzioBusinessInboxTab(onOpenRoom: widget.onOpenRoom, chatRooms: widget.chatRooms),
      JuzzioBusinessCustomersTab(onOpenRoom: widget.onOpenRoom),
      const JuzzioBusinessWorkspaceTab(),
      _BusinessProfileTab(onSwitchToPersonal: widget.onSwitchToPersonal),
    ];
    return Column(
      children: [
        Expanded(child: IndexedStack(index: _tab, children: pages)),
        NavigationBar(
          selectedIndex: _tab,
          backgroundColor: p.sheetBg,
          onDestinationSelected: (i) => setState(() => _tab = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard_rounded), label: t('Genel Bakış', 'Overview', 'Übersicht')),
            NavigationDestination(icon: const Icon(Icons.inbox_outlined), selectedIcon: const Icon(Icons.inbox_rounded), label: t('Gelen Kutusu', 'Inbox', 'Posteingang')),
            NavigationDestination(icon: const Icon(Icons.people_outline_rounded), selectedIcon: const Icon(Icons.people_rounded), label: t('Müşteriler', 'Customers', 'Kunden')),
            NavigationDestination(icon: const Icon(Icons.work_outline_rounded), selectedIcon: const Icon(Icons.work_rounded), label: t('İş Alanı', 'Workspace', 'Arbeitsbereich')),
            NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront_rounded), label: t('Profil', 'Profile', 'Profil')),
          ],
        ),
      ],
    );
  }
}

/// Ortak: yükleme / hata / boş durumları olan sunucu verisi gösterici.
class JuzzioAsyncSection<T> extends StatelessWidget {
  const JuzzioAsyncSection({super.key, required this.future, required this.builder, this.isEmpty, this.emptyText});
  final Future<T> future;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return FutureBuilder<T>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          final msg = SupabaseService.instance.friendlyError(snap.error!);
          final denied = msg.contains('not_allowed') || snap.error.toString().contains('42501') || snap.error.toString().contains('not_allowed');
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              denied ? app.trEn('Bu bölüm için yetkin yok.', 'You don\'t have access to this section.', 'Kein Zugriff auf diesen Bereich.') : msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary),
            ),
          );
        }
        final data = snap.data as T;
        if (isEmpty != null && isEmpty!(data)) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(emptyText ?? app.trEn('Henüz kayıt yok.', 'Nothing here yet.', 'Noch keine Einträge.'),
                textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
          );
        }
        return builder(data);
      },
    );
  }
}

class _BusinessOverviewTab extends StatefulWidget {
  const _BusinessOverviewTab({required this.onGoTab});
  final ValueChanged<int> onGoTab;

  @override
  State<_BusinessOverviewTab> createState() => _BusinessOverviewTabState();
}

class _BusinessOverviewTabState extends State<_BusinessOverviewTab> {
  late Future<Map<String, dynamic>> _f = JuzzioBusinessService.instance.overview();

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    String t(String tr, String en, String de) => app.trEn(tr, en, de);
    Widget kpi(String label, Object? v, IconData icon, {VoidCallback? onTap}) => Semantics(
          button: onTap != null,
          label: '$label: ${v ?? 0}',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: JuzzioGlass(
              radius: 18,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: p.amberGlow, size: 20),
                const SizedBox(height: 6),
                Text('${v ?? 0}', style: TextStyle(color: p.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12)),
              ]),
            ),
          ),
        );
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _f = JuzzioBusinessService.instance.overview());
        await _f;
      },
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('Günlük özet', 'Daily summary', 'Tagesübersicht'), style: TextStyle(color: p.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        JuzzioAsyncSection<Map<String, dynamic>>(
          future: _f,
          builder: (o) => GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width < 360 ? 2 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              kpi(t('Bugünkü mesajlar', 'Messages today', 'Nachrichten heute'), o['messages_today'], Icons.chat_rounded, onTap: () => widget.onGoTab(1)),
              kpi(t('Yanıt bekleyen', 'Awaiting reply', 'Wartet auf Antwort'), o['awaiting_reply'], Icons.mark_chat_unread_rounded, onTap: () => widget.onGoTab(1)),
              kpi(t('Açık talepler', 'Open requests', 'Offene Anfragen'), o['open_conversations'], Icons.inbox_rounded, onTap: () => widget.onGoTab(1)),
              kpi(t('Yaklaşan randevu', 'Upcoming appointments', 'Anstehende Termine'), o['appointments_upcoming'], Icons.event_rounded, onTap: () => widget.onGoTab(3)),
              kpi(t('Bekleyen görev', 'Open tasks', 'Offene Aufgaben'), o['tasks_open'], Icons.task_alt_rounded, onTap: () => widget.onGoTab(3)),
              kpi(t('Takip hatırlatması', 'Follow-ups due', 'Fällige Nachverfolgungen'), o['followups_due'], Icons.alarm_rounded, onTap: () => widget.onGoTab(2)),
              kpi(t('Müşteri', 'Customers', 'Kunden'), o['customers'], Icons.people_rounded, onTap: () => widget.onGoTab(2)),
              kpi(t('Ort. ilk yanıt (dk)', 'Avg first reply (min)', 'Ø erste Antwort (Min)'), o['avg_first_reply_min'] ?? '—', Icons.timer_rounded),
              kpi(t('Çözülen (30 gün)', 'Resolved (30d)', 'Gelöst (30T)'), o['resolved_period'], Icons.check_circle_rounded),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(t('Değerler yalnız Juzzio\'daki gerçek kayıtlardan hesaplanır; veri yoksa 0 görünür.',
            'Values are computed only from real records in Juzzio; 0 when there is no data.', 'Werte stammen nur aus echten Daten.'),
            style: TextStyle(color: p.textMuted, fontSize: 11.5)),
      ]),
    );
  }
}

class _BusinessProfileTab extends StatefulWidget {
  const _BusinessProfileTab({required this.onSwitchToPersonal});
  final VoidCallback onSwitchToPersonal;

  @override
  State<_BusinessProfileTab> createState() => _BusinessProfileTabState();
}

class _BusinessProfileTabState extends State<_BusinessProfileTab> {
  final _svc = JuzzioBusinessService.instance;
  late Future<Map<String, dynamic>> _f = _svc.myAccount();

  Future<void> _edit(Map<String, dynamic> acc) async {
    final app = JuzzioAppController.instance;
    String t(String tr, String en, String de) => app.trEn(tr, en, de);
    final fields = <String, TextEditingController>{
      'display_name': TextEditingController(text: acc['display_name']?.toString() ?? ''),
      'professional_title': TextEditingController(text: acc['professional_title']?.toString() ?? ''),
      'description': TextEditingController(text: acc['description']?.toString() ?? ''),
      'website': TextEditingController(text: acc['website']?.toString() ?? ''),
      'contact_email': TextEditingController(text: acc['contact_email']?.toString() ?? ''),
      'contact_phone': TextEditingController(text: acc['contact_phone']?.toString() ?? ''),
      'location': TextEditingController(text: acc['location']?.toString() ?? ''),
    };
    final labels = {
      'display_name': t('İşletme adı', 'Business name', 'Name'),
      'professional_title': t('Unvan', 'Title', 'Titel'),
      'description': t('Açıklama', 'Description', 'Beschreibung'),
      'website': t('Web sitesi', 'Website', 'Webseite'),
      'contact_email': t('E-posta', 'Email', 'E-Mail'),
      'contact_phone': t('Telefon', 'Phone', 'Telefon'),
      'location': t('Konum (isteğe bağlı)', 'Location (optional)', 'Ort (optional)'),
    };
    final hours = TextEditingController(text: (acc['working_hours'] as Map?)?.isNotEmpty == true
        ? (acc['working_hours'] as Map).entries.map((e) => '${e.key}=${(e.value as List).join('-')}').join(', ')
        : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Business profilini düzenle', 'Edit business profile', 'Profil bearbeiten')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in fields.entries)
              TextField(controller: e.value, maxLines: e.key == 'description' ? 3 : 1, decoration: InputDecoration(labelText: labels[e.key])),
            TextField(
              controller: hours,
              decoration: InputDecoration(
                labelText: t('Çalışma saatleri', 'Working hours', 'Öffnungszeiten'),
                helperText: 'mon=09:00-18:00, tue=09:00-18:00 …',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    );
    if (ok == true) {
      final wh = <String, List<String>>{};
      for (final part in hours.text.split(',')) {
        final m = RegExp(r'^\s*(mon|tue|wed|thu|fri|sat|sun)\s*=\s*(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})\s*$').firstMatch(part.toLowerCase());
        if (m != null) wh[m.group(1)!] = [m.group(2)!, m.group(3)!];
      }
      try {
        await _svc.updateProfile({for (final e in fields.entries) e.key: e.value.text, 'working_hours': wh});
        setState(() => _f = _svc.myAccount());
      } catch (e) {
        if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
      }
    }
    for (final c in fields.values) {
      c.dispose();
    }
    hours.dispose();
  }

  Future<void> _ownerAction(String action) async {
    final app = JuzzioAppController.instance;
    String t(String tr, String en, String de) => app.trEn(tr, en, de);
    final texts = {
      'pause': t('Business geçici olarak devre dışı bırakılsın mı? Müşteri kayıtların ve ekip verilerin korunur; istediğinde devam ettirebilirsin.',
          'Temporarily disable Business? Your records are kept; you can resume any time.', 'Business vorübergehend deaktivieren?'),
      'close': t('Business hesabı KAPATILSIN mı? Bu, Personal görünüme geçmekten farklıdır: ekip erişimi kapanır, işletme verilerin silinmez ama sen dahil kimse erişemez; yeniden başvurarak açabilirsin.',
          'CLOSE the Business account? Different from switching to Personal: team access ends, data is not deleted but becomes inaccessible until you re-apply.',
          'Business-Konto SCHLIESSEN?'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(texts[action]!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Onayla', 'Confirm', 'Bestätigen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.ownerAction(action);
      widget.onSwitchToPersonal();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    String t(String tr, String en, String de) => app.trEn(tr, en, de);
    return JuzzioAsyncSection<Map<String, dynamic>>(
      future: _f,
      builder: (acc) => ListView(padding: const EdgeInsets.all(16), children: [
        JuzzioGlass(
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(acc['display_name']?.toString() ?? '',
                    style: TextStyle(color: p.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              // Doğrulama rozeti YALNIZ sunucu doğruladıysa
              if (acc['is_verified'] == true) Icon(Icons.verified_rounded, color: p.amberGlow),
            ]),
            if ((acc['professional_title'] ?? '').toString().isNotEmpty)
              Text(acc['professional_title'].toString(), style: TextStyle(color: p.textSecondary)),
            const SizedBox(height: 6),
            Text((acc['description'] ?? '').toString(), style: TextStyle(color: p.textPrimary)),
            const SizedBox(height: 6),
            for (final k in ['website', 'contact_email', 'contact_phone', 'location'])
              if ((acc[k] ?? '').toString().isNotEmpty) Text(acc[k].toString(), style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 12),
        JuzzioGlass(
          radius: 22,
          child: Column(children: [
            ListTile(leading: const Icon(Icons.edit_rounded), title: Text(t('Business profilini düzenle', 'Edit business profile', 'Profil bearbeiten')), onTap: () => _edit(acc)),
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(t('Personal moduna dön', 'Back to Personal', 'Zurück zu Personal')),
              subtitle: Text(t('Yalnız görünüm değişir; hiçbir veri silinmez.', 'Only the view changes; no data is deleted.', 'Nur die Ansicht ändert sich.')),
              onTap: () async {
                try {
                  await _svc.setView('personal');
                } catch (_) {}
                widget.onSwitchToPersonal();
              },
            ),
            ListTile(leading: const Icon(Icons.pause_circle_outline_rounded), title: Text(t('Geçici olarak devre dışı bırak', 'Temporarily disable', 'Vorübergehend deaktivieren')), onTap: () => _ownerAction('pause')),
            ListTile(
              leading: Icon(Icons.store_mall_directory_outlined, color: p.dangerRed),
              title: Text(t('Business hesabını kapat', 'Close Business account', 'Business-Konto schließen'), style: TextStyle(color: p.dangerRed)),
              onTap: () => _ownerAction('close'),
            ),
          ]),
        ),
      ]),
    );
  }
}
