// =============================================================================
// JUZZIO v0.8.0 — Ayarlar → Sohbet yedeği (Google Drive, uçtan uca şifreli)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_backup_service.dart';

class JuzzioBackupPage extends StatefulWidget {
  const JuzzioBackupPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioBackupPage()));

  @override
  State<JuzzioBackupPage> createState() => _JuzzioBackupPageState();
}

class _JuzzioBackupPageState extends State<JuzzioBackupPage> {
  final _app = JuzzioAppController.instance;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _show = false;
  DateTime? _last;
  String? _msg;
  bool _msgError = false;

  @override
  void initState() {
    super.initState();
    JuzzioBackupService.instance.lastBackupAt().then((d) {
      if (mounted) setState(() => _last = d);
    });
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _msgError = error;
      });

  Future<void> _backup() async {
    if (_pw.text.length < 8) {
      _say(JuzzioBackupService.message(const JuzzioBackupException('weak_password')), error: true);
      return;
    }
    if (_pw.text != _pw2.text) {
      _say(_app.trEn('Şifreler aynı değil.', 'Passwords do not match.', 'Passwörter stimmen nicht überein.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final at = await JuzzioBackupService.instance.backup(_pw.text);
      _last = at;
      _say(_app.trEn(
          'Yedek ${JuzzioBackupService.instance.googleEmail ?? 'Google Drive'} hesabına şifreli olarak kaydedildi.',
          'Encrypted backup saved to ${JuzzioBackupService.instance.googleEmail ?? 'Google Drive'}.',
          'Verschlüsseltes Backup gespeichert.'));
    } catch (e) {
      _say(JuzzioBackupService.message(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final info = await JuzzioBackupService.instance.findBackup();
      if (info == null) {
        _say(JuzzioBackupService.message(const JuzzioBackupException('not_found')), error: true);
        return;
      }
      if (!mounted) return;
      final ok = await showJuzzioRestorePasswordSheet(context, info);
      if (ok == true) {
        _say(_app.trEn('Yedek geri yüklendi: şifreli mesajlar, anahtarlar ve ayarlar geri geldi.',
            'Backup restored: encrypted messages, keys and settings are back.', 'Backup wiederhergestellt.'));
      }
    } catch (e) {
      _say(JuzzioBackupService.message(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: p.inputBg,
          prefixIcon: Icon(Icons.key_rounded, color: p.textSecondary),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: p.textSecondary),
            onPressed: () => setState(() => _show = !_show),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.glassBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.glassBorder)),
        );
    Widget point(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 18, color: p.textPrimary),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: TextStyle(color: p.textSecondary, fontSize: 12.8, height: 1.4))),
          ]),
        );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Sohbet yedeği', 'Chat backup', 'Chat-Backup'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          JuzzioGlass(
            radius: 26,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.cloud_upload_rounded, color: p.textPrimary, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _last == null
                          ? _app.trEn('Henüz yedek yok', 'No backup yet', 'Noch kein Backup')
                          : _app.trEn('Son yedek: ${_fmt(_last!)}', 'Last backup: ${_fmt(_last!)}', 'Letztes Backup: ${_fmt(_last!)}'),
                      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                point(Icons.lock_rounded, _app.trEn(
                    'Yedek, belirlediğin şifreden Argon2id ile türetilen anahtarla AES-256-GCM şifrelenir. Şifreni biz dahil kimse bilmez; unutursan yedek açılamaz.',
                    'Encrypted with AES-256-GCM using a key derived from your password with Argon2id. Nobody, including us, knows your password.',
                    'Mit AES-256-GCM verschlüsselt (Argon2id-Schlüssel aus deinem Passwort).')),
                point(Icons.add_to_drive_rounded, _app.trEn(
                    'Seçtiğin Google hesabının Drive\'ındaki gizli uygulama klasörüne kaydedilir.',
                    'Stored in the hidden app folder of the Google Drive account you choose.',
                    'Im versteckten App-Ordner deines Google Drive gespeichert.')),
                point(Icons.inventory_2_rounded, _app.trEn(
                    'İçerik: şifreli mesaj anahtarları, tema ve tüm ayarlar, yıldızlı mesajlar, engellenen kullanıcı adları. Mesajlar, aramalar ve engellenenler zaten hesabında durur.',
                    'Includes encryption keys, theme and all settings, starred messages, blocked names. Messages and calls are kept in your account.',
                    'Enthält Schlüssel und Einstellungen; Nachrichten liegen im Konto.')),
                point(Icons.person_off_rounded, _app.trEn(
                    'Yedek hesabına bağlıdır: hesabını silip yeniden açarsan eski yedek yüklenemez.',
                    'Backups are tied to your account: a deleted and re-created account cannot restore them.',
                    'An dein Konto gebunden.')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(controller: _pw, obscureText: !_show, style: TextStyle(color: p.textPrimary),
              decoration: deco(_app.trEn('Yedek şifresi (en az 8 karakter)', 'Backup password (min 8)', 'Backup-Passwort (min. 8)'))),
          const SizedBox(height: 10),
          TextField(controller: _pw2, obscureText: !_show, style: TextStyle(color: p.textPrimary),
              decoration: deco(_app.trEn('Şifre tekrar', 'Repeat password', 'Passwort wiederholen'))),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.coolButtonBg,
              foregroundColor: p.coolButtonFg,
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _backup,
            icon: _busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.coolButtonFg))
                : const Icon(Icons.backup_rounded),
            label: Text(_app.trEn('Google Drive\'a yedekle', 'Back up to Google Drive', 'In Google Drive sichern'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: p.glassBorder),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.settings_backup_restore_rounded),
            label: Text(_app.trEn('Yedeği geri yükle', 'Restore backup', 'Backup wiederherstellen'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 14),
            Text(_msg!, textAlign: TextAlign.center,
                style: TextStyle(color: _msgError ? p.dangerRed : p.onlineGreen, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}

/// Şifre sorup geri yükler. true → başarılı
Future<bool?> showJuzzioRestorePasswordSheet(BuildContext context, JuzzioBackupInfo info) {
  final app = JuzzioAppController.instance;
  final ctrl = TextEditingController();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      var busy = false;
      String? err;
      return StatefulBuilder(builder: (ctx, setS) {
        final p = JuzzioPalette(app.isDark);
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: JuzzioGlass(
              radius: 28,
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(app.trEn('Yedeği geri yükle', 'Restore backup', 'Backup wiederherstellen'),
                      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(
                    app.trEn('Google Drive\'da bu hesaba ait şifreli yedek bulundu. Yedek şifreni gir.',
                        'An encrypted backup for this account was found. Enter your backup password.', 'Backup gefunden. Passwort eingeben.'),
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    autofocus: true,
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(
                      labelText: app.trEn('Yedek şifresi', 'Backup password', 'Backup-Passwort'),
                      filled: true,
                      fillColor: p.inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: TextStyle(color: p.dangerRed, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.coolButtonBg,
                      foregroundColor: p.coolButtonFg,
                      minimumSize: const Size.fromHeight(50),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: busy
                        ? null
                        : () async {
                            setS(() {
                              busy = true;
                              err = null;
                            });
                            try {
                              await JuzzioBackupService.instance.restore(info, ctrl.text);
                              if (ctx.mounted) Navigator.of(ctx).pop(true);
                            } catch (e) {
                              setS(() {
                                busy = false;
                                err = JuzzioBackupService.message(e);
                              });
                            }
                          },
                    child: busy
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: p.coolButtonFg))
                        : Text(app.trEn('Geri yükle', 'Restore', 'Wiederherstellen'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        );
      });
    },
  );
}

/// Girişten sonra bir kez: "Yedeği geri yükle" önerisi
Future<void> maybeOfferJuzzioRestore(BuildContext context) async {
  final svc = JuzzioBackupService.instance;
  if (!await svc.shouldOfferRestore() || !context.mounted) return;
  final app = JuzzioAppController.instance;
  final p = JuzzioPalette(app.isDark);
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: JuzzioGlass(
        radius: 28,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.settings_backup_restore_rounded, color: p.textPrimary, size: 34),
            const SizedBox(height: 10),
            Text(app.trEn('Yedeği geri yükle?', 'Restore your backup?', 'Backup wiederherstellen?'),
                textAlign: TextAlign.center, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            Text(
              app.trEn('Daha önce Google Drive\'a yedek aldıysan şifreli mesajların, anahtarların ve ayarların geri gelir.',
                  'If you backed up to Google Drive before, your encrypted messages, keys and settings come back.', 'Stellt Schlüssel und Einstellungen wieder her.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.coolButtonBg, foregroundColor: p.coolButtonFg, shape: const StadiumBorder(),
                  minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(app.trEn('Geri yükle', 'Restore', 'Wiederherstellen'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(app.trEn('Şimdi değil', 'Not now', 'Nicht jetzt'), style: TextStyle(color: p.textSecondary)),
            ),
          ],
        ),
      ),
    ),
  );
  await svc.markRestoreChecked();
  if (yes != true || !context.mounted) return;
  try {
    final info = await svc.findBackup();
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(JuzzioBackupService.message(const JuzzioBackupException('not_found')))));
      return;
    }
    await showJuzzioRestorePasswordSheet(context, info);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(JuzzioBackupService.message(e))));
  }
}
