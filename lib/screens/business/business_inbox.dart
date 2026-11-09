// =============================================================================
// JUZZIO v0.9.0 — Business > Gelen Kutusu (son talimat §5.2)
//  Konuşma kayıtları (oda bağlantısı + müşteri + sorumlu + durum + öncelik + etiket). Mesaj
//  içeriği KOPYALANMAZ: sohbet açıldığında normal (E2EE) sohbet ekranında okunur. Kişisel sohbet
//  otomatik eklenmez — "Konuşma ekle" ile sahibin açıkça seçtiği sohbetler eklenir.
//  Sorumlu Ata / Atamayı Değiştir (sunucu: inbox.assign + ekip üyeliği + denetim kaydı),
//  Görevi Tamamla (çözüldü), Müşteri Detayı, Talep Oluştur (görev), Şablon Kullan (hazır yanıt).
//  Ayarlar > Otomatik Yanıtlar (karşılama / mesai dışı).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_business_service.dart';
import '../../services/supabase_service.dart';
import 'business_customers.dart';
import 'business_shell.dart';

class JuzzioBusinessInboxTab extends StatefulWidget {
  const JuzzioBusinessInboxTab({super.key, required this.onOpenRoom, required this.chatRooms});
  final ValueChanged<String> onOpenRoom;
  final List<(String, String, String?)> Function() chatRooms;

  @override
  State<JuzzioBusinessInboxTab> createState() => _JuzzioBusinessInboxTabState();
}

class _JuzzioBusinessInboxTabState extends State<JuzzioBusinessInboxTab> {
  final _svc = JuzzioBusinessService.instance;
  final _app = JuzzioAppController.instance;
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, Map<String, String>)> _f = _load();
  String _filter = 'all'; // all | unread? → awaiting | mine | resolved

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, Map<String, String>)> _load() async {
    final convs = await _svc.conversations();
    final custs = await _svc.customers();
    final names = await _svc.memberNames();
    return (convs, custs, names);
  }

  void _reload() => setState(() => _f = _load());
  String _t(String tr, String en, String de) => _app.trEn(tr, en, de);
  void _snack(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));

  Future<void> _run(Future<void> Function() op, {String? ok}) async {
    try {
      await op();
      if (ok != null) _snack(ok);
      _reload();
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _assign(Map<String, dynamic> c, Map<String, String> names) async {
    String? who = c['assignee_id']?.toString();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(c['assignee_id'] == null ? _t('Sorumlu Ata', 'Assign', 'Zuweisen') : _t('Atamayı Değiştir', 'Change assignee', 'Zuweisung ändern')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String?>(
              isExpanded: true,
              value: names.containsKey(who) ? who : null,
              hint: Text(_t('Çalışan seç', 'Select member', 'Mitglied wählen')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(_t('Atanmamış', 'Unassigned', 'Nicht zugewiesen'))),
                for (final e in names.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setD(() => who = v),
            ),
            TextField(controller: reason, maxLength: 300, decoration: InputDecoration(labelText: _t('Atama nedeni (isteğe bağlı)', 'Reason (optional)', 'Grund (optional)'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Kaydet', 'Save', 'Speichern'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() => _svc.assignConversation(c['id'].toString(), who, reason: reason.text), ok: _t('Atama kaydedildi', 'Assignment saved', 'Gespeichert'));
    }
    reason.dispose();
  }

  Future<void> _addConversation(List<Map<String, dynamic>> custs, List<Map<String, dynamic>> convs) async {
    final existing = {for (final c in convs) c['room_id'].toString()};
    final rooms = widget.chatRooms().where((r) => !existing.contains(r.$1)).toList();
    final pick = await showModalBottomSheet<(String, String, String?)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text(_t('Gelen kutusuna eklenecek sohbet', 'Chat to add to the inbox', 'Chat zum Posteingang hinzufügen'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(_t('Yalnız seçtiğin sohbet eklenir; mesaj içerikleri kopyalanmaz. Ekip üyeleri yalnız kayıt bilgisini görür.',
                'Only the selected chat is added; message contents are not copied. Team members only see the record.',
                'Nur der gewählte Chat; Inhalte werden nicht kopiert.')),
          ),
          if (rooms.isEmpty) ListTile(title: Text(_t('Eklenecek sohbet yok', 'No chats to add', 'Keine Chats'))),
          for (final r in rooms) ListTile(leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text(r.$2), onTap: () => Navigator.pop(ctx, r)),
        ]),
      ),
    );
    if (pick == null) return;
    await _run(() async {
      // Birebir sohbette karşı taraf müşteri kaydına bağlanır (yoksa oluşturulur)
      String? customerId;
      final partner = pick.$3;
      if (partner != null) {
        customerId = custs.where((c) => c['customer_user_id']?.toString() == partner).map((c) => c['id'].toString()).firstOrNull;
        if (customerId == null) {
          await _svc.insert('business_customers', {'customer_user_id': partner, 'name': pick.$2});
          customerId = (await _svc.customers()).where((c) => c['customer_user_id']?.toString() == partner).map((c) => c['id'].toString()).firstOrNull;
        }
      }
      await _svc.insert('business_conversations', {'room_id': pick.$1, if (customerId != null) 'customer_id': customerId});
    }, ok: _t('Gelen kutusuna eklendi', 'Added to inbox', 'Hinzugefügt'));
  }

  Future<void> _autoReplies() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _svc.autoReplies();
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
      return;
    }
    if (!mounted) return;
    Map<String, dynamic>? row(String k) => rows.where((r) => r['kind'] == k).firstOrNull;
    final welcome = TextEditingController(text: row('welcome')?['body']?.toString() ?? '');
    final away = TextEditingController(text: row('away')?['body']?.toString() ?? '');
    var wOn = row('welcome')?['enabled'] == true;
    var aOn = row('away')?['enabled'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_t('Otomatik Yanıtlar', 'Automatic replies', 'Automatische Antworten')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_t('Yalnız gelen kutusuna eklenmiş konuşmalarda, müşteri yazınca gönderilir; aynı kişiye 12 saatte en fazla 1 kez. Yanıt "Otomatik yanıt" olarak işaretlenir ve şifrelenmez — gizli bilgi yazma.',
                  'Sent only in inbox conversations when a customer writes; at most once per 12h per person. Marked as automatic and not encrypted — do not include secrets.',
                  'Nur in Posteingang-Chats; max. 1× pro 12 h; nicht verschlüsselt.'), style: const TextStyle(fontSize: 12)),
              SwitchListTile(value: wOn, onChanged: (v) => setD(() => wOn = v), title: Text(_t('Karşılama mesajı', 'Welcome message', 'Begrüßung'))),
              TextField(controller: welcome, maxLength: 1000, maxLines: 3),
              SwitchListTile(value: aOn, onChanged: (v) => setD(() => aOn = v), title: Text(_t('Mesai dışı mesaj', 'Away message', 'Abwesenheit'))),
              TextField(controller: away, maxLength: 1000, maxLines: 3),
              Text(_t('Mesai saatleri Profil > Business profilini düzenle bölümünden ayarlanır.', 'Working hours are set in Profile > Edit business profile.', 'Öffnungszeiten im Profil.'),
                  style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Kaydet', 'Save', 'Speichern'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() async {
        await _svc.upsertAutoReply('welcome', enabled: wOn, body: welcome.text);
        await _svc.upsertAutoReply('away', enabled: aOn, body: away.text);
      }, ok: _t('Otomatik yanıtlar kaydedildi', 'Automatic replies saved', 'Gespeichert'));
    }
    welcome.dispose();
    away.dispose();
  }

  Future<void> _useTemplate() async {
    final templates = [
      _t('Merhaba, mesajınız için teşekkürler. Kısa süre içinde dönüş yapacağız.', 'Hello, thanks for your message. We will get back to you shortly.', 'Hallo, danke für Ihre Nachricht.'),
      _t('Randevunuz onaylandı. Görüşmek üzere!', 'Your appointment is confirmed. See you!', 'Ihr Termin ist bestätigt.'),
      _t('Talebiniz çözüldü olarak işaretlendi. Başka bir konuda yardımcı olabilir miyiz?', 'Your request is resolved. Anything else we can help with?', 'Ihre Anfrage ist gelöst.'),
    ];
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final t in templates) ListTile(leading: const Icon(Icons.short_text_rounded), title: Text(t), onTap: () => Navigator.pop(ctx, t)),
        ]),
      ),
    );
    if (pick == null) return;
    await Clipboard.setData(ClipboardData(text: pick));
    _snack(_t('Şablon kopyalandı — sohbette yapıştır', 'Template copied — paste it in the chat', 'Vorlage kopiert'));
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final me = _svc.myBusinessId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_t('Gelen Kutusu', 'Inbox', 'Posteingang')),
        actions: [
          IconButton(tooltip: _t('Şablon Kullan', 'Use template', 'Vorlage'), icon: const Icon(Icons.short_text_rounded), onPressed: _useTemplate),
          IconButton(tooltip: _t('Otomatik Yanıtlar', 'Automatic replies', 'Auto-Antworten'), icon: const Icon(Icons.settings_rounded), onPressed: _autoReplies),
        ],
      ),
      body: JuzzioAsyncSection<(List<Map<String, dynamic>>, List<Map<String, dynamic>>, Map<String, String>)>(
        future: _f,
        builder: (d) {
          final (convs, custs, names) = d;
          final roomName = {for (final r in widget.chatRooms()) r.$1: r.$2};
          final custName = {for (final c in custs) c['id'].toString(): c['name'].toString()};
          final shown = convs.where((c) {
            switch (_filter) {
              case 'open':
                return c['status'] != 'resolved';
              case 'mine':
                return c['assignee_id'] == me;
              case 'assigned':
                return c['assignee_id'] != null;
              case 'resolved':
                return c['status'] == 'resolved';
              default:
                return true;
            }
          }).toList();
          return Column(children: [
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
                for (final f in <(String, String)>[
                  ('all', _t('Tümü', 'All', 'Alle')),
                  ('open', _t('Yanıt bekleyenler', 'Awaiting', 'Offen')),
                  ('assigned', _t('Atanmış', 'Assigned', 'Zugewiesen')),
                  ('mine', _t('Bana atanan', 'Mine', 'Meine')),
                  ('resolved', _t('Çözümlenmiş', 'Resolved', 'Gelöst')),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ]),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(_t('Bu filtrede konuşma yok. "Konuşma ekle" ile bir müşteri sohbetini gelen kutusuna ekle.',
                          'No conversations here. Use "Add conversation" to add a customer chat.', 'Keine Konversationen.'),
                          textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
                    ))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        final id = c['id'].toString();
                        final cust = custName[c['customer_id']?.toString()] ?? roomName[c['room_id'].toString()] ?? _t('Müşteri', 'Customer', 'Kunde');
                        final who = names[c['assignee_id']?.toString()];
                        final last = DateTime.tryParse(c['last_activity_at']?.toString() ?? '')?.toLocal();
                        final prio = c['priority'].toString();
                        return JuzzioGlass(
                          radius: 18,
                          child: ListTile(
                            onTap: () => widget.onOpenRoom(c['room_id'].toString()),
                            leading: Icon(
                              c['status'] == 'resolved' ? Icons.check_circle_rounded : Icons.forum_rounded,
                              color: prio == 'urgent' || prio == 'high' ? p.dangerRed : p.amberGlow,
                            ),
                            title: Text(cust, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              [
                                who != null ? '👤 $who' : _t('Atanmamış', 'Unassigned', 'Nicht zugewiesen'),
                                _statusLabel(c['status'].toString()),
                                _prioLabel(prio),
                                if (last != null) '${last.day}.${last.month} ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
                              ].join(' · '),
                              style: TextStyle(color: p.textSecondary, fontSize: 12),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                switch (v) {
                                  case 'assign':
                                    await _assign(c, names);
                                  case 'resolve':
                                    await _run(() => _svc.update('business_conversations', id, {'status': 'resolved'}),
                                        ok: _t('Çözüldü olarak işaretlendi', 'Marked resolved', 'Gelöst'));
                                  case 'reopen':
                                    await _run(() => _svc.update('business_conversations', id, {'status': 'open'}));
                                  case 'urgent':
                                    await _run(() => _svc.update('business_conversations', id, {'priority': prio == 'urgent' ? 'normal' : 'urgent'}));
                                  case 'customer':
                                    final cid = c['customer_id']?.toString();
                                    if (cid != null && mounted) {
                                      await JuzzioBusinessCustomerDetailPage.open(context, customerId: cid, onOpenRoom: widget.onOpenRoom);
                                    } else {
                                      _snack(_t('Bu konuşma bir müşteriye bağlı değil', 'Not linked to a customer', 'Kein Kunde verknüpft'));
                                    }
                                  case 'ticket':
                                    await _run(() => _svc.insert('business_tasks', {
                                          'title': '${_t('Talep', 'Request', 'Anfrage')}: $cust',
                                          if (c['customer_id'] != null) 'customer_id': c['customer_id'],
                                          if (c['assignee_id'] != null) 'assignee_id': c['assignee_id'],
                                        }), ok: _t('Talep oluşturuldu (İş Alanı > Görevler)', 'Request created (Workspace > Tasks)', 'Anfrage erstellt'));
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'assign', child: Text(c['assignee_id'] == null ? _t('Sorumlu Ata', 'Assign', 'Zuweisen') : _t('Atamayı Değiştir', 'Change assignee', 'Ändern'))),
                                if (c['status'] != 'resolved') PopupMenuItem(value: 'resolve', child: Text(_t('Görevi Tamamla', 'Mark resolved', 'Erledigt'))),
                                if (c['status'] == 'resolved') PopupMenuItem(value: 'reopen', child: Text(_t('Yeniden aç', 'Reopen', 'Wieder öffnen'))),
                                PopupMenuItem(value: 'urgent', child: Text(prio == 'urgent' ? _t('Önceliği normal yap', 'Set normal priority', 'Normal') : _t('Acil olarak işaretle', 'Mark urgent', 'Dringend'))),
                                PopupMenuItem(value: 'customer', child: Text(_t('Müşteri Detayı', 'Customer details', 'Kundendetails'))),
                                PopupMenuItem(value: 'ticket', child: Text(_t('Talep Oluştur', 'Create request', 'Anfrage erstellen'))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => _addConversation(custs, convs),
                icon: const Icon(Icons.add_comment_rounded),
                label: Text(_t('Konuşma ekle', 'Add conversation', 'Konversation hinzufügen')),
              ),
            ),
          ]);
        },
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'resolved' => _t('Çözümlendi', 'Resolved', 'Gelöst'),
        'pending' => _t('Beklemede', 'Pending', 'Ausstehend'),
        _ => _t('Açık', 'Open', 'Offen'),
      };

  String _prioLabel(String s) => switch (s) {
        'urgent' => _t('Acil', 'Urgent', 'Dringend'),
        'high' => _t('Yüksek', 'High', 'Hoch'),
        'low' => _t('Düşük', 'Low', 'Niedrig'),
        _ => _t('Normal', 'Normal', 'Normal'),
      };
}
