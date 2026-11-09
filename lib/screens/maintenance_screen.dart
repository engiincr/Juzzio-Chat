// =============================================================================
// JUZZIO v0.4.0 — Bakım modu ekranı (yönetici panelinden açılır/kapatılır)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_features_service.dart';
import '../widgets/juzzio_motion.dart';

class JuzzioMaintenanceScreen extends StatefulWidget {
  final String message;

  /// v0.9.6: yönetici "minimum desteklenen sürüm"ü bu derlemenin üstüne çıkardıysa
  /// bakım yerine "güncelleme gerekli" ekranı gösterilir.
  final bool updateRequired;
  const JuzzioMaintenanceScreen({super.key, this.message = '', this.updateRequired = false});

  @override
  State<JuzzioMaintenanceScreen> createState() => _JuzzioMaintenanceScreenState();
}

class _JuzzioMaintenanceScreenState extends State<JuzzioMaintenanceScreen> {
  bool _checking = false;
  late String _message = widget.message;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    final cfg = await JuzzioFeaturesService.instance.fetchAppConfig();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _message = cfg.maintenanceMessage;
    });
    if (widget.updateRequired) {
      if (cfg.minSupportedBuild <= JuzzioConfig.appVersionCode) {
        Navigator.of(context).pop();
      } else {
        await JuzzioAppController.instance.checkForOtaUpdate(manualCheck: true);
      }
      return;
    }
    if (!cfg.maintenanceMode) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [JuzzioColors.brandIndigo, JuzzioColors.midnight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.updateRequired ? Icons.system_update_rounded : Icons.construction_rounded, color: Colors.white, size: 76),
                  const SizedBox(height: 20),
                  Text(
                    widget.updateRequired
                        ? app.trEn('Güncelleme gerekli', 'Update required', 'Update erforderlich')
                        : app.trEn('Kısa bir bakımdayız', 'We are under maintenance', 'Wir führen gerade Wartungsarbeiten durch'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.updateRequired
                        ? app.trEn('Bu Juzzio sürümü artık desteklenmiyor. Güvenliğin için lütfen en yeni sürüme güncelle.',
                            'This Juzzio version is no longer supported. Please update to the latest version for your security.',
                            'Diese Juzzio-Version wird nicht mehr unterstützt. Bitte aktualisiere.')
                        : _message.trim().isNotEmpty
                        ? _message.trim()
                        : app.trEn(
                            'Juzzio\'yu daha iyi hâle getiriyoruz. Lütfen birazdan tekrar deneyin.',
                            'We are making Juzzio better. Please try again shortly.',
                            'Wir verbessern Juzzio. Bitte versuche es gleich noch einmal.',
                          ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.45, fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: JuzzioColors.brandIndigo,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _checking ? null : _recheck,
                    icon: _checking
                        ? const SizedBox(width: 18, height: 18, child: JuzzioOrbitLoader(strokeWidth: 2))
                        : Icon(widget.updateRequired ? Icons.download_rounded : Icons.refresh_rounded),
                    label: Text(widget.updateRequired ? app.trEn('Güncelle', 'Update', 'Aktualisieren') : app.t('common_retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
