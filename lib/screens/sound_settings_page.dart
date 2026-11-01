// =============================================================================
// JUZZIO v0.7.0 — Ayarlar → Zil sesleri ve uyarı tonları
//  Genel mesaj bildirim tonu ve arama zil sesi; kişiye özel seçim için
//  sohbette kişinin adına dokun → "Özel bildirim tonu / Özel zil sesi".
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/juzzio_sounds.dart';
import '../core/theme/juzzio_glass.dart';

class JuzzioSoundSettingsPage extends StatefulWidget {
  const JuzzioSoundSettingsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioSoundSettingsPage()));

  @override
  State<JuzzioSoundSettingsPage> createState() => _JuzzioSoundSettingsPageState();
}

class _JuzzioSoundSettingsPageState extends State<JuzzioSoundSettingsPage> {
  final _sounds = JuzzioSounds.instance;

  @override
  void initState() {
    super.initState();
    _sounds.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([app, _sounds]),
      builder: (context, _) {
        final p = JuzzioPalette(app.isDark);
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(app.trEn('Zil sesleri ve uyarı tonları', 'Ringtones & alert tones', 'Klingeltöne & Hinweistöne'),
                style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              JuzzioSoundPickerCard(
                title: app.trEn('Mesaj bildirim tonu', 'Message notification tone', 'Nachrichtenton'),
                icon: Icons.notifications_active_rounded,
                options: JuzzioSounds.messageTones,
                selected: _sounds.messageTone,
                ring: false,
                onSelected: _sounds.setMessageTone,
              ),
              const SizedBox(height: 12),
              JuzzioSoundPickerCard(
                title: app.trEn('Arama zil sesi', 'Call ringtone', 'Anruf-Klingelton'),
                icon: Icons.ring_volume_rounded,
                options: JuzzioSounds.ringtones,
                selected: _sounds.ringtone,
                ring: true,
                onSelected: _sounds.setRingtone,
              ),
              const SizedBox(height: 12),
              JuzzioGlass(
                radius: 22,
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_pin_rounded, color: p.textPrimary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        app.trEn(
                          'Kişiye özel ton ve zil sesi: sohbette kişinin adına dokun → "Özel bildirim tonu" veya "Özel zil sesi".',
                          'Per-contact tones: in a chat tap the contact\'s name → "Custom notification tone" or "Custom ringtone".',
                          'Pro Kontakt: im Chat auf den Namen tippen → „Eigener Ton" oder „Eigener Klingelton".',
                        ),
                        style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ses seçim kartı (genel ayarlar ve kişiye özel ayarlar ortak kullanır)
class JuzzioSoundPickerCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<JuzzioSound> options;
  final String? selected;
  final bool ring;
  final ValueChanged<String> onSelected;
  /// Kişiye özel ekranda "Genel ayarı kullan" seçeneği
  final VoidCallback? onUseDefault;
  final String? defaultLabel;

  const JuzzioSoundPickerCard({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.ring,
    required this.onSelected,
    this.onUseDefault,
    this.defaultLabel,
  });

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    Widget tile({required String label, required bool isSel, required VoidCallback onTap, VoidCallback? onPreview}) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              Icon(isSel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: isSel ? p.textPrimary : p.textMuted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textPrimary, fontWeight: isSel ? FontWeight.w900 : FontWeight.w600, fontSize: 14)),
              ),
              if (onPreview != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: app.trEn('Dinle', 'Preview', 'Anhören'),
                  onPressed: onPreview,
                  icon: Icon(Icons.play_circle_outline_rounded, color: p.textSecondary),
                ),
            ],
          ),
        ),
      );
    }

    return JuzzioGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Icon(icon, color: p.textPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (onUseDefault != null)
            tile(
              label: defaultLabel ?? app.trEn('Genel ayarı kullan', 'Use general setting', 'Allgemeine Einstellung'),
              isSel: selected == null,
              onTap: onUseDefault!,
            ),
          for (final o in options)
            tile(
              label: o.label,
              isSel: selected == o.id,
              onTap: () {
                onSelected(o.id);
                JuzzioSounds.instance.preview(o.id, ring: ring);
              },
              onPreview: () => JuzzioSounds.instance.preview(o.id, ring: ring),
            ),
        ],
      ),
    );
  }
}
