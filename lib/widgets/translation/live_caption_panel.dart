// v0.8.1 — Şartname §11 LiveCaptionPanel: yalnızca sunum katmanı. Metinler gerçek
// konuşma tanıma/çeviri state'inden verilmelidir; servise kendiliğinden bağlanmaz.
import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';
import '../glass/glass_surface.dart';

class LiveCaptionPanel extends StatelessWidget {
  final String originalText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final bool isProcessing;
  final VoidCallback? onPlayTranslation;

  const LiveCaptionPanel({
    super.key,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.isProcessing = false,
    this.onPlayTranslation,
  });

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final t = JuzzioGlassTokens.textPrimary;
    TextStyle label(Color c) => TextStyle(color: c, fontSize: 11, letterSpacing: 0.7, fontWeight: FontWeight.w700);
    return GlassSurface(
      blur: JuzzioGlassTokens.blurNavigation,
      radius: 24,
      opacity: 0.32,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.translate, color: JuzzioColors.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(app.trEn('Juzzio Canlı Çeviri', 'Juzzio Live Translation', 'Juzzio Live-Übersetzung'),
                  style: TextStyle(color: t, fontWeight: FontWeight.w700)),
            ),
            if (isProcessing)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: JuzzioColors.cyan)),
          ]),
          if (originalText.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(app.trEn('ORİJİNAL KONUŞMA', 'ORIGINAL SPEECH', 'ORIGINAL'), style: label(JuzzioGlassTokens.textSecondary)),
            const SizedBox(height: 6),
            Text(originalText, style: TextStyle(color: t, fontSize: 15)),
          ],
          if (translatedText.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: JuzzioColors.cyan.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: JuzzioColors.cyan.withValues(alpha: 0.18)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.trEn('ÇEVİRİ', 'TRANSLATED TEXT', 'ÜBERSETZUNG'), style: label(JuzzioColors.cyanSoft)),
                const SizedBox(height: 8),
                Text(translatedText, style: TextStyle(color: t, fontSize: 16)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text('$sourceLanguage → $targetLanguage',
                        style: const TextStyle(color: JuzzioColors.cyanSoft, fontSize: 12)),
                  ),
                  if (onPlayTranslation != null)
                    IconButton(
                      tooltip: app.trEn('Çeviriyi seslendir', 'Play translated speech', 'Vorlesen'),
                      onPressed: onPlayTranslation,
                      icon: const Icon(Icons.volume_up_outlined, color: JuzzioColors.cyan),
                    ),
                ]),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
