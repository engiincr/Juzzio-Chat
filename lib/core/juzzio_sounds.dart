// =============================================================================
// JUZZIO v0.7.0 — Zil sesleri ve uyarı tonları
//  • Uygulamaya özel mesaj tonları ve zil sesleri (android/res/raw).
//  • Varsayılan ton/zil + kişiye özel ton/zil.
//  • Tercihler user_sound_prefs tablosunda tutulur; sunucu bildirimi gönderirken
//    alıcının seçtiği sese ait Android kanalını kullanır (uygulama kapalıyken de).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';
import 'app_theme_and_locale.dart';

class JuzzioSound {
  final String id;
  final String tr;
  final String en;
  final String de;
  const JuzzioSound(this.id, this.tr, this.en, this.de);

  String get label => JuzzioAppController.instance.trEn(tr, en, de);
}

class JuzzioSounds extends ChangeNotifier {
  JuzzioSounds._();
  static final JuzzioSounds instance = JuzzioSounds._();
  static const MethodChannel _ch = MethodChannel('juzzio/notifications');

  static const List<JuzzioSound> messageTones = [
    JuzzioSound('juzzio_tone_glass', 'Juzzio Cam', 'Juzzio Glass', 'Juzzio Glas'),
    JuzzioSound('juzzio_tone_drop', 'Damla', 'Drop', 'Tropfen'),
    JuzzioSound('juzzio_tone_pop', 'Pop', 'Pop', 'Pop'),
    JuzzioSound('juzzio_tone_chime', 'Çan', 'Chime', 'Glockenspiel'),
    JuzzioSound('default', 'Telefonun varsayılanı', 'Phone default', 'Telefonstandard'),
  ];

  static const List<JuzzioSound> ringtones = [
    JuzzioSound('juzzio_ring_aurora', 'Juzzio Aurora', 'Juzzio Aurora', 'Juzzio Aurora'),
    JuzzioSound('juzzio_ring_crystal', 'Kristal', 'Crystal', 'Kristall'),
    JuzzioSound('juzzio_ring_pulse', 'Nabız', 'Pulse', 'Puls'),
    JuzzioSound('juzzio_ring_breeze', 'Esinti', 'Breeze', 'Brise'),
    JuzzioSound('default', 'Telefonun varsayılanı', 'Phone default', 'Telefonstandard'),
  ];

  String _messageTone = 'juzzio_tone_glass';
  String _ringtone = 'juzzio_ring_aurora';
  Map<String, Map<String, String>> _contact = {};
  bool _loaded = false;

  String get messageTone => _messageTone;
  String get ringtone => _ringtone;

  static String labelFor(String id, {required bool ring}) {
    for (final s in ring ? ringtones : messageTones) {
      if (s.id == id) return s.label;
    }
    return JuzzioAppController.instance.trEn('Varsayılan', 'Default', 'Standard');
  }

  /// Kişiye özel seçim (yoksa null → genel varsayılan kullanılır)
  String? contactTone(String userId) => _contact[userId]?['tone'];
  String? contactRing(String userId) => _contact[userId]?['ring'];
  String toneFor(String? userId) => (userId != null ? contactTone(userId) : null) ?? _messageTone;
  String ringFor(String? userId) => (userId != null ? contactRing(userId) : null) ?? _ringtone;

  String messageChannelFor(String? userId) {
    final id = toneFor(userId);
    return id == 'default' ? 'juzzio_high_priority_v2' : 'juzzio_msg_$id';
  }

  String callChannelFor(String? userId) {
    final id = ringFor(userId);
    return id == 'default' ? 'juzzio_calls_priority_v2' : 'juzzio_call_$id';
  }

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return;
    try {
      final row = await svc.client.from('user_sound_prefs').select().eq('user_id', uid).maybeSingle();
      if (row != null) {
        _messageTone = (row['message_tone'] ?? _messageTone).toString();
        _ringtone = (row['ringtone'] ?? _ringtone).toString();
        final cp = row['contact_prefs'];
        if (cp is Map) {
          _contact = {
            for (final e in cp.entries)
              if (e.value is Map) e.key.toString(): Map<String, String>.from((e.value as Map).map((k, v) => MapEntry(k.toString(), v.toString()))),
          };
        }
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return;
    await svc.client.from('user_sound_prefs').upsert({
      'user_id': uid,
      'message_tone': _messageTone,
      'ringtone': _ringtone,
      'contact_prefs': _contact,
    });
  }

  Future<void> setMessageTone(String id) async {
    _messageTone = id;
    notifyListeners();
    await _save();
  }

  Future<void> setRingtone(String id) async {
    _ringtone = id;
    notifyListeners();
    await _save();
  }

  /// [tone]/[ring] null → kişiye özel seçimi kaldırır (genel varsayılan kullanılır)
  Future<void> setContactSounds(String userId, {String? tone, String? ring, bool clearTone = false, bool clearRing = false}) async {
    final m = Map<String, String>.from(_contact[userId] ?? const {});
    if (tone != null) m['tone'] = tone;
    if (ring != null) m['ring'] = ring;
    if (clearTone) m.remove('tone');
    if (clearRing) m.remove('ring');
    if (m.isEmpty) {
      _contact.remove(userId);
    } else {
      _contact[userId] = m;
    }
    notifyListeners();
    await _save();
  }

  Future<void> preview(String id, {required bool ring}) async {
    try {
      await _ch.invokeMethod('previewSound', {'id': id, 'ring': ring});
    } catch (_) {}
  }

  Future<void> startRinging(String? callerId) async {
    try {
      await _ch.invokeMethod('startRingtone', {'id': ringFor(callerId)});
    } catch (_) {}
  }

  Future<void> stopRinging() async {
    try {
      await _ch.invokeMethod('stopRingtone');
    } catch (_) {}
  }
}
