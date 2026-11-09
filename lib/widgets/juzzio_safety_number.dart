// =============================================================================
// JUZZIO v0.9.5 — Uçtan uca şifreleme güvenlik numarası (Signal/WhatsApp benzeri)
//  İki kişi aynı 60 haneyi (veya aynı QR'ı) görüyorsa aralarında araya giren (MITM) yoktur.
//  Karşı taraf uygulamayı yeniden kurarsa / cihaz değiştirirse numara değişir.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_e2ee.dart';
import 'juzzio_motion.dart';

Future<void> showJuzzioSafetyNumberSheet(BuildContext context, {required String peerUid, required String peerName}) {
  final app = JuzzioAppController.instance;
  return showJuzzioSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioPalette(app.isDark).sheetBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => FutureBuilder<String?>(
      future: JuzzioE2ee.instance.safetyNumber(peerUid),
      builder: (ctx, snap) {
        final p = JuzzioPalette(app.isDark);
        final num = snap.data;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_rounded, size: 34, color: Color(0xFF34C759)),
              const SizedBox(height: 8),
              Text(app.trEn('Güvenlik numarası', 'Safety number', 'Sicherheitsnummer'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                app.trEn('$peerName ile sohbetinizin uçtan uca şifreli olduğunu doğrulayın: aşağıdaki numara onun telefonunda da AYNI görünmelidir.',
                    'Verify your chat with $peerName is end-to-end encrypted: the number below must look the SAME on their phone.',
                    'Vergleiche diese Nummer mit $peerName: sie muss auf beiden Geräten GLEICH sein.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(24), child: JuzzioOrbitLoader())
              else if (num == null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    app.trEn('Anahtarlar alınamadı. Karşı tarafın uygulaması güncel değilse veya çevrimdışıysanız numara gösterilemez.',
                        'Keys could not be loaded. The number cannot be shown if the other app is outdated or you are offline.',
                        'Schlüssel nicht verfügbar.'),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(data: 'juzzio-safety:${num.replaceAll(RegExp(r'\s'), '')}', size: 170),
                ),
                const SizedBox(height: 14),
                SelectableText(num, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 17, height: 1.6, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: num));
                    HapticFeedback.selectionClick();
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(app.trEn('Kopyala', 'Copy', 'Kopieren')),
                ),
              ],
            ]),
          ),
        );
      },
    ),
  );
}
