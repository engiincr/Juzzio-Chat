// =============================================================================
// TRAWAVE (GM-039) — Cihaz eşleştirme arayüzü
//  • Yeni cihaz: "Bu cihazı eşleştir" (diğer cihazdan onay · yedekten geri yükle · yeni anahtar)
//  • Anahtarlı cihaz: "Yeni cihaz mesajlarına erişmek istiyor — Bu sen misin?" (Bu benim / Ben değilim)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../screens/backup_page.dart';
import '../services/juzzio_e2ee.dart';
import '../services/juzzio_key_sync.dart';

String juzzioLinkRequestTime(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  final app = JuzzioAppController.instance;
  if (d.inMinutes < 1) return app.trEn('şimdi', 'just now', 'gerade eben');
  if (d.inMinutes < 60) return app.trEn('${d.inMinutes} dk önce', '${d.inMinutes} min ago', 'vor ${d.inMinutes} Min.');
  final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
  return '${t.day}.${t.month}.${t.year} $hh:$mm';
}

Widget _sheetFrame(BuildContext ctx, {required IconData icon, required Color iconColor, required String title, required String body, required List<Widget> actions, Widget? extra}) {
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: JuzzioLiquidGlass(
        radius: 28,
        blur: 26,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: iconColor, size: 30),
            ),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13.5, height: 1.4)),
          if (extra != null) ...[const SizedBox(height: 12), extra],
          const SizedBox(height: 16),
          ...actions,
        ]),
      ),
    ),
  );
}

Widget _primary(String label, VoidCallback onTap, {Key? key}) => FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: JuzzioGlassTokens.glow,
        foregroundColor: JuzzioGlassTokens.onGlow,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );

Widget _secondary(String label, VoidCallback onTap, {Color? color, Key? key}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton(
        key: key,
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: color ?? JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800)),
      ),
    );

/// Yeni cihaz: anahtarlık bekleniyor
Future<void> showJuzzioDeviceLinkSheet(BuildContext context) async {
  final app = JuzzioAppController.instance;
  await showModalBottomSheet<void>(
    context: context,
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _sheetFrame(
      ctx,
      icon: Icons.devices_rounded,
      iconColor: JuzzioGlassTokens.glow,
      title: app.trEn('Bu cihazı eşleştir', 'Link this device', 'Dieses Gerät verknüpfen'),
      body: app.trEn(
        'Mesajların uçtan uca şifreli. Bu cihazda da okuyabilmen için hesabının açık olduğu diğer cihazında çıkan "Bu benim" onayına dokun. Anahtarlar sunucuya açık hâlde hiç gitmez.',
        'Your messages are end-to-end encrypted. To read them here too, tap "It\'s me" on the prompt shown on your other device. Keys never reach the server unencrypted.',
        'Deine Nachrichten sind Ende-zu-Ende-verschlüsselt. Bestätige auf deinem anderen Gerät mit „Das bin ich".',
      ),
      actions: [
        _primary(app.trEn('Tamam, diğer cihazımda onaylayacağım', 'OK, I\'ll confirm on my other device', 'OK, ich bestätige dort'), () => Navigator.of(ctx).pop(),
            key: const ValueKey('gm039-wait')),
        _secondary(app.trEn('Yedekten geri yükle', 'Restore from backup', 'Aus Backup wiederherstellen'), () {
          Navigator.of(ctx).pop();
          maybeOfferJuzzioRestore(context);
        }, key: const ValueKey('gm039-restore')),
        _secondary(app.trEn('Diğer cihazım yok — yeni anahtar oluştur', 'No other device — create a new key', 'Kein anderes Gerät — neuen Schlüssel'), () async {
          Navigator.of(ctx).pop();
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(app.trEn('Yeni anahtar oluşturulsun mu?', 'Create a new key?', 'Neuen Schlüssel erstellen?')),
              content: Text(app.trEn(
                  'Eski şifreli mesajların bu cihazda açılmaz. Diğer cihazların varsa onlar da bu cihazdan onay isteyecek.',
                  'Older encrypted messages won\'t open on this device. Your other devices will then ask this device for approval.',
                  'Ältere verschlüsselte Nachrichten öffnen sich hier nicht.')),
              actions: [
                TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
                TextButton(onPressed: () => Navigator.of(d).pop(true), child: Text(app.trEn('Oluştur', 'Create', 'Erstellen'))),
              ],
            ),
          );
          if (ok == true) await JuzzioE2ee.instance.createFreshIdentity();
        }, color: JuzzioGlassTokens.textSecondary, key: const ValueKey('gm039-fresh')),
      ],
    ),
  );
}

/// Anahtarlı cihaz: başka bir cihaz anahtarlık istiyor
Future<void> showJuzzioDeviceApproveSheet(BuildContext context, JuzzioKeyRequest r) async {
  final app = JuzzioAppController.instance;
  final when = juzzioLinkRequestTime(r.createdAt);
  await showModalBottomSheet<void>(
    context: context,
    // GM-038: şeffaf cam sayfanın arkasında taşan köşe/gölge olmasın
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    isScrollControlled: true,
    builder: (ctx) => _sheetFrame(
      ctx,
      icon: Icons.phonelink_lock_rounded,
      iconColor: const Color(0xFFFFB020),
      title: app.trEn('Yeni cihaz mesajlarına erişmek istiyor', 'A new device wants your messages', 'Ein neues Gerät möchte deine Nachrichten'),
      body: app.trEn(
        'Hesabına giriş yapılan bir cihaz şifreli mesajlarını açmak için anahtarını istiyor. Sen değilsen reddet ve şifreni değiştir.',
        'A device signed in to your account is asking for your encryption key. If it isn\'t you, decline and change your password.',
        'Ein angemeldetes Gerät fragt nach deinem Schlüssel. Wenn du es nicht bist, lehne ab.',
      ),
      extra: JuzzioLiquidGlass(
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(Icons.laptop_windows_rounded, color: JuzzioGlassTokens.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.label.isEmpty ? app.trEn('Bilinmeyen cihaz', 'Unknown device', 'Unbekanntes Gerät') : r.label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800)),
          ),
          if (when.isNotEmpty) Text(when, style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12)),
        ]),
      ),
      actions: [
        _primary(app.trEn('Bu benim', 'It\'s me', 'Das bin ich'), () async {
          Navigator.of(ctx).pop();
          await JuzzioKeySync.instance.approve(r);
        }, key: const ValueKey('gm039-approve')),
        _secondary(app.trEn('Ben değilim', 'It\'s not me', 'Das bin ich nicht'), () async {
          Navigator.of(ctx).pop();
          await JuzzioKeySync.instance.reject(r);
        }, color: const Color(0xFFFF5A6A), key: const ValueKey('gm039-reject')),
      ],
    ),
  );
}
