// =============================================================================
// JUZZIO v0.3.0 — Engellenen cihaz / hesap ekranı
// Yönetici paneli bir hesabı (ve isteğe bağlı cihazlarını) engellediğinde gösterilir.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_colors.dart';
import '../main.dart' show JuzzioRootFlow;
import '../services/juzzio_features_service.dart';

class JuzzioBannedScreen extends StatefulWidget {
  final String reasonCode;
  /// Süreli uzaklaştırmada bitiş zamanı (null → kalıcı engel)
  final DateTime? until;
  final bool moderation;
  const JuzzioBannedScreen({super.key, required this.reasonCode, this.until, this.moderation = false});

  @override
  State<JuzzioBannedScreen> createState() => _JuzzioBannedScreenState();
}

class _JuzzioBannedScreenState extends State<JuzzioBannedScreen> {
  bool _checking = false;
  late String _reason = widget.reasonCode;
  late DateTime? _until = widget.until;

  String _remainingText(JuzzioAppController app) {
    final until = _until;
    if (until == null) {
      return app.trEn('Hesabınız kalıcı olarak engellendi. Bu cihazdan yeni hesap açılamaz.',
          'Your account is permanently banned. A new account cannot be created from this device.',
          'Dein Konto ist dauerhaft gesperrt. Von diesem Gerät kann kein neues Konto erstellt werden.');
    }
    final left = until.difference(DateTime.now());
    final mins = left.inMinutes < 1 ? 1 : left.inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    final span = h > 0 ? '$h ${app.trEn('sa', 'h', 'Std.')} $m ${app.trEn('dk', 'min', 'Min.')}' : '$m ${app.trEn('dk', 'min', 'Min.')}';
    return app.trEn('Uzaklaştırma süresi: $span sonra hesabınız yeniden açılır.',
        'Suspension: your account reopens in $span.', 'Sperre: Dein Konto wird in $span wieder freigegeben.');
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    final res = await JuzzioFeaturesService.instance.checkDeviceAccess();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _reason = res.reason;
      _until = res.until;
    });
    if (!res.banned) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      } else {
        // Uzaklaştırma bittiyse (ekran tek başına açıktı) giriş akışına dönülür
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const JuzzioRootFlow()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    const reasons = {
      'spam', 'harassment', 'hate_speech', 'inappropriate_content', 'fake_account',
      'scam', 'violence', 'underage', 'impersonation', 'other',
    };
    final reasonKey = reasons.contains(_reason) ? _reason : 'other';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block_rounded, color: JuzzioColors.red500, size: 84),
                const SizedBox(height: 18),
                Text(
                  app.t('banned_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  app.t('banned_body').replaceAll('{reason}', app.t('ban_reason_$reasonKey')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
                if (widget.moderation || _until != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      _remainingText(app),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _checking ? null : _recheck,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  child: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(app.t('common_retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
