// =============================================================================
// JUZZIO v0.7.0 — Kişiye özel sohbet ayarları
//  Sohbette kişinin adına dokununca açılır: profili görüntüle, sesli/görüntülü ara,
//  süreli mesajlar, sessize al, özel bildirim tonu, özel zil sesi, engelle.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/juzzio_sounds.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import 'sound_settings_page.dart';

class JuzzioContactSettingsPage extends StatefulWidget {
  final String roomId;
  final String partnerId;
  final String partnerName;
  final String partnerUsername;
  final String? partnerAvatarUrl;
  final String initialTimer;
  final bool initialMuted;
  final VoidCallback onOpenProfile;
  final void Function(bool video) onCall;
  final VoidCallback onBlock;
  final ValueChanged<bool>? onMutedChanged;

  const JuzzioContactSettingsPage({
    super.key,
    required this.roomId,
    required this.partnerId,
    required this.partnerName,
    required this.partnerUsername,
    required this.partnerAvatarUrl,
    required this.initialTimer,
    required this.initialMuted,
    required this.onOpenProfile,
    required this.onCall,
    required this.onBlock,
    this.onMutedChanged,
  });

  @override
  State<JuzzioContactSettingsPage> createState() => _JuzzioContactSettingsPageState();
}

class _JuzzioContactSettingsPageState extends State<JuzzioContactSettingsPage> {
  final _app = JuzzioAppController.instance;
  final _sounds = JuzzioSounds.instance;
  late String _timer = widget.initialTimer.isEmpty ? 'off' : widget.initialTimer;
  late bool _muted = widget.initialMuted;

  @override
  void initState() {
    super.initState();
    _sounds.load();
  }

  String _timerLabel(String t) {
    switch (t) {
      case '24h':
        return _app.trEn('24 saat', '24 hours', '24 Stunden');
      case '7d':
        return _app.trEn('7 gün', '7 days', '7 Tage');
      case '30d':
        return _app.trEn('30 gün', '30 days', '30 Tage');
      default:
        return _app.trEn('Kapalı', 'Off', 'Aus');
    }
  }

  Future<void> _pickTimer() async {
    final p = JuzzioPalette(_app.isDark);
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: JuzzioGlass(
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Text(
                    _app.trEn('Süreli mesajlar', 'Disappearing messages', 'Selbstlöschende Nachrichten'),
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Text(
                    _app.trEn('Bundan sonra gönderilen yeni mesajlar seçilen süre sonunda iki taraf için de silinir.',
                        'New messages will disappear for both sides after the chosen time.',
                        'Neue Nachrichten verschwinden nach der gewählten Zeit für beide.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                  ),
                ),
                for (final t in const ['off', '24h', '7d', '30d'])
                  ListTile(
                    title: Text(_timerLabel(t), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                    trailing: Icon(_timer == t ? Icons.check_circle_rounded : Icons.circle_outlined,
                        color: _timer == t ? p.textPrimary : p.textMuted),
                    onTap: () => Navigator.of(ctx).pop(t),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (v == null || v == _timer) return;
    final old = _timer;
    setState(() => _timer = v);
    try {
      await SupabaseService.instance.client.rpc('set_room_disappearing_timer', params: {'p_room': widget.roomId, 'p_timer': v});
    } catch (e) {
      if (!mounted) return;
      setState(() => _timer = old);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  Future<void> _pickSound({required bool ring}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: _sounds,
        builder: (ctx, _) {
          final p = JuzzioPalette(_app.isDark);
          final current = ring ? _sounds.contactRing(widget.partnerId) : _sounds.contactTone(widget.partnerId);
          final general = JuzzioSounds.labelFor(ring ? _sounds.ringtone : _sounds.messageTone, ring: ring);
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: p.textPrimary,
              elevation: 0,
              title: Text(
                ring ? _app.trEn('Özel zil sesi', 'Custom ringtone', 'Eigener Klingelton') : _app.trEn('Özel bildirim tonu', 'Custom notification tone', 'Eigener Ton'),
                style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                JuzzioSoundPickerCard(
                  title: widget.partnerName,
                  icon: ring ? Icons.ring_volume_rounded : Icons.notifications_active_rounded,
                  options: ring ? JuzzioSounds.ringtones : JuzzioSounds.messageTones,
                  selected: current,
                  ring: ring,
                  defaultLabel: _app.trEn('Genel ayarı kullan ($general)', 'Use general setting ($general)', 'Allgemein ($general)'),
                  onUseDefault: () => _sounds.setContactSounds(widget.partnerId, clearRing: ring, clearTone: !ring),
                  onSelected: (id) => _sounds.setContactSounds(widget.partnerId, ring: ring ? id : null, tone: ring ? null : id),
                ),
              ],
            ),
          );
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_app, _sounds]),
      builder: (context, _) {
        final p = JuzzioPalette(_app.isDark);
        Widget action(IconData icon, String label, VoidCallback onTap) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: p.pillBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    Icon(icon, color: p.textPrimary),
                    const SizedBox(height: 4),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ),
              ),
            ),
          );
        }

        Widget row(IconData icon, String title, String value, VoidCallback onTap, {Color? color}) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: Icon(icon, color: color ?? p.textPrimary),
            title: Text(title, style: TextStyle(color: color ?? p.textPrimary, fontWeight: FontWeight.w800)),
            subtitle: value.isEmpty ? null : Text(value, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
            onTap: onTap,
          );
        }

        final tone = _sounds.contactTone(widget.partnerId);
        final ring = _sounds.contactRing(widget.partnerId);
        final general = _app.trEn('Genel ayar', 'General setting', 'Allgemein');
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(_app.trEn('Kişi bilgisi', 'Contact info', 'Kontaktinfo'),
                style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              JuzzioGlass(
                radius: 28,
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: widget.onOpenProfile,
                      child: JuzzioGlassAvatar(imageUrl: widget.partnerAvatarUrl, name: widget.partnerName, radius: 46),
                    ),
                    const SizedBox(height: 12),
                    Text(widget.partnerName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                    if (widget.partnerUsername.isNotEmpty)
                      Text('@${widget.partnerUsername}', style: TextStyle(color: p.textSecondary, fontSize: 13)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        action(Icons.person_rounded, _app.trEn('Profil', 'Profile', 'Profil'), widget.onOpenProfile),
                        const SizedBox(width: 8),
                        action(Icons.call_rounded, _app.trEn('Sesli', 'Voice', 'Anruf'), () {
                          Navigator.of(context).pop();
                          widget.onCall(false);
                        }),
                        const SizedBox(width: 8),
                        action(Icons.videocam_rounded, _app.trEn('Görüntülü', 'Video', 'Video'), () {
                          Navigator.of(context).pop();
                          widget.onCall(true);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              JuzzioGlass(
                radius: 24,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    row(Icons.timer_rounded, _app.trEn('Süreli mesajlar', 'Disappearing messages', 'Selbstlöschend'),
                        _timerLabel(_timer), _pickTimer),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                      secondary: Icon(Icons.notifications_off_rounded, color: p.textPrimary),
                      title: Text(_app.trEn('Bildirimleri sessize al', 'Mute notifications', 'Stummschalten'),
                          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
                      value: _muted,
                      onChanged: (v) {
                        setState(() => _muted = v);
                        SupabaseService.instance.setRoomPreferences(widget.roomId, muted: v);
                        widget.onMutedChanged?.call(v);
                      },
                    ),
                    row(Icons.music_note_rounded, _app.trEn('Özel bildirim tonu', 'Custom notification tone', 'Eigener Ton'),
                        tone == null ? general : JuzzioSounds.labelFor(tone, ring: false), () => _pickSound(ring: false)),
                    row(Icons.ring_volume_rounded, _app.trEn('Özel zil sesi', 'Custom ringtone', 'Eigener Klingelton'),
                        ring == null ? general : JuzzioSounds.labelFor(ring, ring: true), () => _pickSound(ring: true)),
                    row(Icons.tune_rounded, _app.trEn('Genel zil sesleri ve tonlar', 'General ringtones & tones', 'Allgemeine Töne'), '',
                        () => JuzzioSoundSettingsPage.open(context)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              JuzzioGlass(
                radius: 24,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: row(Icons.block_rounded, _app.trEn('Engelle', 'Block', 'Blockieren'), '', () {
                  Navigator.of(context).pop();
                  widget.onBlock();
                }, color: p.dangerRed),
              ),
            ],
          ),
        );
      },
    );
  }
}
