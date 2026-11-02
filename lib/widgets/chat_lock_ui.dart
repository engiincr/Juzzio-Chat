// =============================================================================
// JUZZIO v0.9.0 — Sohbet kilidi arayüzü (§4.6): PIN girişi / PIN oluşturma, Sohbet Bilgileri >
// Gizlilik > "Sohbeti Kilitle" anahtarı. Kilitleme sohbetin bildirim önizlemesini sunucuda
// 'gizli' yapar; kilit kaldırılınca cihaz ayarına döner.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_chat_lock.dart';
import '../services/supabase_service.dart';

/// PIN ister; doğrulanırsa true. PIN yoksa önce oluşturtur ([allowCreate]).
Future<bool> juzzioRequireChatPin(BuildContext context, {bool allowCreate = true}) async {
  final lock = JuzzioChatLock.instance;
  if (!lock.loaded) await lock.load();
  if (lock.isUnlocked) return true;
  final has = await lock.hasPin();
  if (!context.mounted) return false;
  if (!has) {
    if (!allowCreate) return false;
    return await _createPin(context);
  }
  final ok = await showDialog<bool>(context: context, builder: (_) => const _PinDialog());
  return ok == true;
}

Future<bool> _createPin(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(app.trEn('Uygulama PIN\'i oluştur', 'Create app PIN', 'App-PIN erstellen')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(app.trEn('Kilitli sohbetleri açmak için kullanılır. Yalnız bu cihazda saklanır; unutulursa kilitli sohbetler yeniden PIN oluşturularak sıfırlanır.',
              'Used to open locked chats. Stored only on this device; if forgotten, locks are reset with a new PIN.',
              'Zum Öffnen gesperrter Chats. Nur auf diesem Gerät gespeichert.'), style: const TextStyle(fontSize: 12)),
          TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
              decoration: InputDecoration(labelText: app.trEn('PIN (4–8 rakam)', 'PIN (4–8 digits)', 'PIN (4–8 Ziffern)'))),
          TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 8,
              decoration: InputDecoration(labelText: app.trEn('PIN tekrar', 'Repeat PIN', 'PIN wiederholen'), errorText: err)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(
            onPressed: () async {
              if (!JuzzioChatLockMath.validPin(a.text)) {
                setD(() => err = app.trEn('PIN 4–8 rakam olmalı', 'PIN must be 4–8 digits', 'PIN muss 4–8 Ziffern haben'));
                return;
              }
              if (a.text != b.text) {
                setD(() => err = app.trEn('PIN\'ler eşleşmiyor', 'PINs do not match', 'PINs stimmen nicht überein'));
                return;
              }
              await JuzzioChatLock.instance.setPin(a.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(app.trEn('Kaydet', 'Save', 'Speichern')),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _c = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = JuzzioAppController.instance;
    setState(() => _busy = true);
    final ok = await JuzzioChatLock.instance.unlock(_c.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    final until = JuzzioChatLock.instance.blockedUntil;
    setState(() {
      _busy = false;
      _c.clear();
      _err = until != null && until.isAfter(DateTime.now())
          ? app.trEn('Çok fazla hatalı deneme. ${until.difference(DateTime.now()).inSeconds + 1} sn bekle.',
              'Too many attempts. Wait ${until.difference(DateTime.now()).inSeconds + 1}s.',
              'Zu viele Versuche. ${until.difference(DateTime.now()).inSeconds + 1} s warten.')
          : app.trEn('PIN hatalı', 'Wrong PIN', 'Falsche PIN');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return AlertDialog(
      title: Text(app.trEn('Kilitli sohbetler', 'Locked chats', 'Gesperrte Chats')),
      content: TextField(
        controller: _c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: app.trEn('Uygulama PIN\'i', 'App PIN', 'App-PIN'), errorText: _err),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(app.trEn('Aç', 'Unlock', 'Entsperren'))),
      ],
    );
  }
}

/// Sohbet Bilgileri > Gizlilik > "Sohbeti Kilitle"
class JuzzioChatLockTile extends StatefulWidget {
  const JuzzioChatLockTile({super.key, required this.roomId});
  final String roomId;

  @override
  State<JuzzioChatLockTile> createState() => _JuzzioChatLockTileState();
}

class _JuzzioChatLockTileState extends State<JuzzioChatLockTile> {
  @override
  void initState() {
    super.initState();
    if (!JuzzioChatLock.instance.loaded) JuzzioChatLock.instance.load();
  }

  Future<void> _toggle(bool lock) async {
    final app = JuzzioAppController.instance;
    if (!await juzzioRequireChatPin(context)) return;
    await JuzzioChatLock.instance.setLocked(widget.roomId, lock);
    try {
      // Kilitli sohbetin bildirimi içerik/gönderen göstermez (sunucuda, tüm cihazlarda)
      await SupabaseService.instance.setRoomNotificationPrefs(widget.roomId, preview: lock ? 'hidden' : 'inherit');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(app.trEn('Sohbet kilitlendi, ancak bildirim önizlemesi güncellenemedi.',
              'Chat locked, but the notification preview could not be updated.', 'Chat gesperrt, Vorschau konnte nicht aktualisiert werden.')),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return ListenableBuilder(
      listenable: JuzzioChatLock.instance,
      builder: (context, _) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        secondary: Icon(Icons.lock_person_rounded, color: p.textPrimary),
        title: Text(app.trEn('Sohbeti Kilitle', 'Lock chat', 'Chat sperren'),
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        subtitle: Text(
          app.trEn('Listede gizlenir, PIN ile açılır; bildirim içeriği gösterilmez.',
              'Hidden from the list, opened with PIN; notification content hidden.',
              'In der Liste verborgen, mit PIN geöffnet; Mitteilungsinhalt verborgen.'),
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
        value: JuzzioChatLock.instance.isLocked(widget.roomId),
        onChanged: _toggle,
      ),
    );
  }
}
