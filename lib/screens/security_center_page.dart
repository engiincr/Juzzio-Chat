// =============================================================================
// JUZZIO v0.9.0 — Profil > Ayarlar > Güvenlik Merkezi (C-A5)
//  Özet (gerçek sunucu verisi), cihazlar, diğer oturumları kapat (onaylı),
//  güvenlik uyarıları (yalnız sunucuda kayıtlı olaylar), şifreli yedek durumu.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_backup_service.dart';
import '../services/juzzio_security_center.dart';
import '../services/supabase_service.dart';

class JuzzioSecurityCenterPage extends StatefulWidget {
  const JuzzioSecurityCenterPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioSecurityCenterPage()));

  @override
  State<JuzzioSecurityCenterPage> createState() => _JuzzioSecurityCenterPageState();
}

class _JuzzioSecurityCenterPageState extends State<JuzzioSecurityCenterPage> {
  final _app = JuzzioAppController.instance;
  final _svc = JuzzioSecurityCenterService.instance;
  JuzzioSecurityOverview? _overview;
  List<JuzzioDeviceEntry> _devices = const [];
  List<JuzzioSecurityEvent> _events = const [];
  DateTime? _lastBackup;
  bool _loading = true;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([_svc.overview(), _svc.devices(), _svc.events()]);
      _overview = r[0] as JuzzioSecurityOverview;
      _devices = r[1] as List<JuzzioDeviceEntry>;
      _events = r[2] as List<JuzzioSecurityEvent>;
      try {
        _lastBackup = await JuzzioBackupService.instance.lastBackupAt();
      } catch (_) {
        _lastBackup = null;
      }
      if (_overview!.unseenAlerts > 0) await _svc.markSeen();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(_app.trEn('Onayla', 'Confirm', 'Bestätigen'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _signOutOthers() async {
    if (_busy) return;
    final ok = await _confirm(
      _app.trEn('Diğer oturumları kapat', 'Sign out other sessions', 'Andere Sitzungen abmelden'),
      _app.trEn('Bu cihaz dışındaki tüm cihazlarda oturumun kapanacak. Mesajların silinmez.',
          'You will be signed out on every device except this one. Your messages are not deleted.',
          'Du wirst auf allen anderen Geräten abgemeldet. Nachrichten werden nicht gelöscht.'),
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _svc.signOutOtherSessions();
      _snack(_app.trEn('Diğer oturumlar kapatıldı', 'Other sessions signed out', 'Andere Sitzungen abgemeldet'));
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forget(JuzzioDeviceEntry d) async {
    final ok = await _confirm(
      _app.trEn('Cihazı listeden kaldır', 'Remove device', 'Gerät entfernen'),
      _app.trEn('Cihaz …${d.suffix} listeden kaldırılacak. Oturumunu da kapatmak için "Diğer oturumları kapat"ı kullan.',
          'Device …${d.suffix} will be removed from the list. Use "Sign out other sessions" to end its session too.',
          'Gerät …${d.suffix} wird entfernt. Nutze „Andere Sitzungen abmelden“, um die Sitzung zu beenden.'),
    );
    if (!ok) return;
    try {
      final done = await _svc.forgetDevice(d.suffix);
      if (!done) _snack(_app.trEn('Cihaz kaldırılamadı', 'Could not remove device', 'Gerät konnte nicht entfernt werden'));
      await _load();
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    }
  }

  String _date(DateTime? t) => t == null ? '—' : '${t.day}.${t.month}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _eventText(JuzzioSecurityEvent e) {
    final dev = (e.detail['device'] ?? '').toString();
    switch (e.kind) {
      case 'new_device':
        return _app.trEn('Hesabına yeni bir cihazdan giriş yapıldı (…$dev)', 'New device signed in (…$dev)', 'Neues Gerät angemeldet (…$dev)');
      case 'device_removed':
        return _app.trEn('Cihaz listeden kaldırıldı (…$dev)', 'Device removed (…$dev)', 'Gerät entfernt (…$dev)');
      case 'e2ee_key_changed':
        return _app.trEn('Şifreleme anahtarın yenilendi', 'Your encryption key changed', 'Dein Schlüssel wurde geändert');
    }
    return '';
  }

  Widget _section(JuzzioPalette p, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8),
              child: Text(title, style: TextStyle(color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
          ),
          JuzzioGlass(radius: 20, child: Column(children: children)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(SupabaseService.instance.friendlyError(_error!), style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: Text(_app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'))),
        ]),
      );
    } else {
      final o = _overview!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _section(p, _app.trEn('Özet', 'Overview', 'Übersicht'), [
            ListTile(
              leading: Icon(o.e2eeReady ? Icons.lock_rounded : Icons.lock_open_rounded, color: o.e2eeReady ? p.onlineGreen : p.amberGlow),
              title: Text(
                  o.e2eeReady
                      ? _app.trEn('Uçtan uca şifreleme etkin', 'End-to-end encryption active', 'Ende-zu-Ende-Verschlüsselung aktiv')
                      : _app.trEn('Şifreleme anahtarı henüz yok', 'No encryption key yet', 'Noch kein Schlüssel'),
                  style: TextStyle(color: p.textPrimary)),
            ),
            ListTile(
              leading: Icon(Icons.cloud_done_rounded, color: _lastBackup != null ? p.onlineGreen : p.textMuted),
              title: Text(_app.trEn('Şifreli yedek', 'Encrypted backup', 'Verschlüsseltes Backup'), style: TextStyle(color: p.textPrimary)),
              subtitle: Text(
                  _lastBackup == null
                      ? _app.trEn('Bu cihazda yedek alınmadı', 'No backup made on this device', 'Kein Backup auf diesem Gerät')
                      : '${_app.trEn('Son yedek', 'Last backup', 'Letztes Backup')}: ${_date(_lastBackup)}',
                  style: TextStyle(color: p.textSecondary, fontSize: 12)),
            ),
          ]),
          _section(p, '${_app.trEn('Cihazlar', 'Devices', 'Geräte')} (${_devices.length})', [
            for (final d in _devices)
              ListTile(
                leading: Icon(Icons.smartphone_rounded, color: d.current ? p.onlineGreen : p.textSecondary),
                title: Text('${d.platform.isEmpty ? '?' : d.platform} …${d.suffix}${d.current ? ' · ${_app.trEn('bu cihaz', 'this device', 'dieses Gerät')}' : ''}',
                    style: TextStyle(color: p.textPrimary)),
                subtitle: Text('${_app.trEn('Son görülme', 'Last seen', 'Zuletzt')}: ${_date(d.lastSeen)}',
                    style: TextStyle(color: p.textSecondary, fontSize: 12)),
                trailing: d.current
                    ? null
                    : IconButton(
                        tooltip: _app.trEn('Listeden kaldır', 'Remove', 'Entfernen'),
                        icon: Icon(Icons.delete_outline_rounded, color: p.textSecondary),
                        onPressed: () => _forget(d),
                      ),
              ),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: p.amberGlow),
              title: Text(_app.trEn('Diğer oturumları kapat', 'Sign out other sessions', 'Andere Sitzungen abmelden'),
                  style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
              enabled: !_busy,
              onTap: _signOutOthers,
            ),
          ]),
          _section(p, _app.trEn('Güvenlik uyarıları', 'Security alerts', 'Sicherheitswarnungen'), [
            if (_events.isEmpty)
              ListTile(
                title: Text(_app.trEn('Kayıtlı güvenlik olayı yok', 'No security events recorded', 'Keine Sicherheitsereignisse'),
                    style: TextStyle(color: p.textSecondary)),
              ),
            for (final e in _events)
              ListTile(
                leading: Icon(e.kind == 'new_device' ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                    color: e.kind == 'new_device' ? p.amberGlow : p.textSecondary),
                title: Text(_eventText(e), style: TextStyle(color: p.textPrimary, fontWeight: e.seen ? FontWeight.w400 : FontWeight.w700)),
                subtitle: Text(_date(e.createdAt), style: TextStyle(color: p.textSecondary, fontSize: 12)),
              ),
          ]),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Güvenlik Merkezi', 'Security Center', 'Sicherheitscenter')),
      ),
      body: body,
    );
  }
}
