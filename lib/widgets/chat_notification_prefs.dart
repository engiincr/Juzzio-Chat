// =============================================================================
// JUZZIO v0.9.0 — Sohbet Bilgileri > Bildirimleri Özelleştir (son talimat §6.4)
//  Sessize alma süresi, önizleme (cihaz ayarından daha gizli olabilir), titreşim.
//  Ses: mevcut "Özel bildirim tonu" satırı (kişiye özel ton) kullanılır — ikinci ses ayarı yok.
//  Kayıt sunucuda (set_room_notification_prefs, yalnız kendi satırı); başarısızlıkta eski değere
//  dönülür ve hata gösterilir (sahte "kaydedildi" yok).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

/// Saf yardımcı: sunucu yanıtından görünür durum (test edilebilir).
class JuzzioRoomNotifState {
  const JuzzioRoomNotifState({this.mutedUntil, this.preview = 'inherit', this.vibrate = true});
  final DateTime? mutedUntil;
  final String preview;
  final bool vibrate;

  factory JuzzioRoomNotifState.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const JuzzioRoomNotifState();
    final p = m['preview']?.toString() ?? 'inherit';
    return JuzzioRoomNotifState(
      mutedUntil: DateTime.tryParse(m['muted_until']?.toString() ?? ''),
      preview: const {'inherit', 'full', 'sender', 'hidden'}.contains(p) ? p : 'inherit',
      vibrate: m['vibrate'] != false,
    );
  }

  bool isMuted(DateTime now) => mutedUntil != null && mutedUntil!.isAfter(now);

  /// Süresiz sessiz (sunucu 100 yıl yazar)
  bool isMutedForever(DateTime now) => mutedUntil != null && mutedUntil!.difference(now).inDays > 365 * 50;
}

class JuzzioChatNotificationPrefsTile extends StatefulWidget {
  const JuzzioChatNotificationPrefsTile({super.key, required this.roomId});
  final String roomId;

  @override
  State<JuzzioChatNotificationPrefsTile> createState() => _JuzzioChatNotificationPrefsTileState();
}

class _JuzzioChatNotificationPrefsTileState extends State<JuzzioChatNotificationPrefsTile> {
  final _app = JuzzioAppController.instance;
  JuzzioRoomNotifState _state = const JuzzioRoomNotifState();
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final m = await SupabaseService.instance.getRoomNotificationPrefs(widget.roomId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = m == null;
      _state = JuzzioRoomNotifState.fromMap(m);
    });
  }

  String _summary() {
    final now = DateTime.now();
    if (_loading) return _app.trEn('Yükleniyor…', 'Loading…', 'Wird geladen…');
    if (_error) return _app.trEn('Yüklenemedi — tekrar dene', 'Could not load — retry', 'Laden fehlgeschlagen — erneut');
    if (_state.isMutedForever(now)) return _app.trEn('Sessiz (her zaman)', 'Muted (always)', 'Stumm (immer)');
    if (_state.isMuted(now)) {
      final t = _state.mutedUntil!.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return _app.trEn('Sessiz: ${t.day}.${t.month} $hh:$mm\'e kadar', 'Muted until ${t.day}.${t.month} $hh:$mm',
          'Stumm bis ${t.day}.${t.month} $hh:$mm');
    }
    return _app.trEn('Açık', 'On', 'An');
  }

  Future<void> _save({int? muteMinutes, String? preview, bool? vibrate}) async {
    final before = _state;
    try {
      final m = await SupabaseService.instance
          .setRoomNotificationPrefs(widget.roomId, muteMinutes: muteMinutes, preview: preview, vibrate: vibrate);
      if (!mounted) return;
      setState(() => _state = JuzzioRoomNotifState.fromMap(m));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = before);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(SupabaseService.instance.friendlyError(e))),
      );
    }
  }

  Future<void> _openSheet() async {
    if (_error) {
      await _load();
      if (_error) return;
    }
    if (!mounted) return;
    await showJuzzioSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final p = JuzzioPalette(_app.isDark);
        final style = TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700);
        final sub = TextStyle(color: p.textSecondary, fontSize: 12);
        Future<void> apply({int? muteMinutes, String? preview, bool? vibrate}) async {
          await _save(muteMinutes: muteMinutes, preview: preview, vibrate: vibrate);
          setSheet(() {});
        }

        Widget muteChip(String label, int minutes) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
              child: ActionChip(label: Text(label), onPressed: () => apply(muteMinutes: minutes)),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: JuzzioGlass(
              radius: 24,
              color: p.sheetBg,
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text(_app.trEn('Bildirimleri özelleştir', 'Customize notifications', 'Mitteilungen anpassen'),
                          style: style.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    ListTile(
                      leading: Icon(Icons.notifications_paused_rounded, color: p.textPrimary),
                      title: Text(_app.trEn('Sessize al', 'Mute', 'Stummschalten'), style: style),
                      subtitle: Text(_summary(), style: sub),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(children: [
                        muteChip(_app.trEn('1 saat', '1 hour', '1 Stunde'), 60),
                        muteChip(_app.trEn('8 saat', '8 hours', '8 Stunden'), 480),
                        muteChip(_app.trEn('1 hafta', '1 week', '1 Woche'), 10080),
                        muteChip(_app.trEn('Her zaman', 'Always', 'Immer'), -1),
                        if (_state.isMuted(DateTime.now())) muteChip(_app.trEn('Sesi aç', 'Unmute', 'Ton an'), 0),
                      ]),
                    ),
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_app.trEn('Önizleme', 'Preview', 'Vorschau'), style: style),
                    ),
                    for (final opt in <(String, String)>[
                      ('inherit', _app.trEn('Cihaz ayarını kullan', 'Use device setting', 'Geräteeinstellung')),
                      ('sender', _app.trEn('Yalnızca gönderen', 'Sender only', 'Nur Absender')),
                      ('hidden', _app.trEn('Gizli', 'Hidden', 'Verborgen')),
                    ])
                      RadioListTile<String>(
                        dense: true,
                        value: opt.$1,
                        groupValue: _state.preview == 'full' ? 'inherit' : _state.preview,
                        activeColor: p.amberGlow,
                        title: Text(opt.$2, style: style),
                        onChanged: (v) => v == null ? null : apply(preview: v),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _app.trEn('Sohbet ayarı cihaz ayarından daha açık olamaz; yalnızca daha gizli olabilir.',
                            'A chat setting can only be more private than the device setting.',
                            'Eine Chat-Einstellung kann nur privater sein als die Geräteeinstellung.'),
                        style: sub,
                      ),
                    ),
                    JuzzioSwitchListTile(
                      activeColor: p.amberGlow,
                      secondary: Icon(Icons.vibration_rounded, color: p.textPrimary),
                      title: Text(_app.trEn('Titreşim', 'Vibration', 'Vibration'), style: style),
                      value: _state.vibrate,
                      onChanged: (v) => apply(vibrate: v),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Icon(Icons.tune_rounded, color: p.textPrimary),
      title: Text(_app.trEn('Bildirimleri özelleştir', 'Customize notifications', 'Mitteilungen anpassen'),
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
      subtitle: Text(_summary(), style: TextStyle(color: p.textSecondary, fontSize: 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
      onTap: _openSheet,
    );
  }
}
