// =============================================================================
// JUZZIO GM-002 (K2) — Girişten sonra, açıklamayla bildirim izni
//  Eski ilk açılış "Bildirimleri aç" ekranı kaldırıldı. İzin artık giriş koşulu değildir;
//  kullanıcı Mesajlar'a ilk geldiğinde bir kez, amacı anlatılarak sorulur.
//  Reddedilirse uygulamanın geri kalanı normal çalışır; tekrar ısrar edilmez.
//  Kamera/mikrofon burada İSTENMEZ (ilgili özellik kullanılırken istenir).
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_design_tokens.dart';
import '../services/fcm_push_service.dart';

class JuzzioNotificationPrompt {
  JuzzioNotificationPrompt._();

  static bool _running = false;

  static Future<File> _flag() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/juzzio_notification_prompt_v1');
  }

  /// Mesajlar ekranı açıldıktan sonra çağrılır. Yalnız Android/iOS; en fazla bir kez sorar.
  static Future<void> maybeAsk(BuildContext context) async {
    if (_running || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    _running = true;
    try {
      final flag = await _flag();
      if (flag.existsSync()) return;
      final status = await Permission.notification.status;
      if (status.isGranted ||
          status.isPermanentlyDenied ||
          status.isRestricted) {
        await flag.writeAsString('1');
        return;
      }
      if (!context.mounted) return;
      final t = JuzzioAppController.instance.trEn;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JuzzioRadius.xl),
          ),
          icon: const Icon(
            Icons.notifications_active_outlined,
            color: JuzzioColorTokens.accent,
            size: 32,
          ),
          title: Text(
            t(
              'Bildirimleri açalım mı?',
              'Turn on notifications?',
              'Benachrichtigungen aktivieren?',
            ),
          ),
          content: Text(
            t(
              'Yeni mesajları ve gelen aramaları kaçırmaman için Trawave bildirim göndermek istiyor. '
                  'İstediğin zaman Ayarlar’dan değiştirebilirsin; izin vermesen de uygulama çalışmaya devam eder.',
              'Trawave would like to notify you about new messages and incoming calls. '
                  'You can change this anytime in Settings; the app keeps working either way.',
              'Trawave möchte dich über neue Nachrichten und eingehende Anrufe informieren. '
                  'Du kannst das jederzeit in den Einstellungen ändern; die App funktioniert so oder so.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Şimdi değil', 'Not now', 'Nicht jetzt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('İzin ver', 'Allow', 'Erlauben')),
            ),
          ],
        ),
      );
      await flag.writeAsString('1');
      if (ok == true) {
        final result = await Permission.notification.request();
        if (result.isGranted) {
          // İzin verildiyse FCM token kaydı yenilenir (K2)
          unawaited(JuzzioFcmPushService.instance.initializeAndSync());
        }
      }
    } catch (_) {
      // izin denetimi başarısız olursa uygulama akışı etkilenmez
    } finally {
      _running = false;
    }
  }
}
