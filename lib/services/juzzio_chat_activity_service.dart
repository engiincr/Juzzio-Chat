// =============================================================================
// JUZZIO v0.9.0 — Sohbet etkinlik kanalı (ek paket N-A)
//
// Supabase Realtime ÖZEL yayın kanalı 'room-activity:<oda>' (yetki: SQL 10.12,
// realtime.messages RLS — yalnız etkin oda üyesi, engel ve çevrimiçi gizliliği sunucuda).
// Yük yalnızca {u: kullanıcı, s: typing|recording|idle}; mesaj metni ASLA gönderilmez.
// Bir anda tek oda dinlenir (açık sohbet). Hata durumunda sessizce devre dışı kalır:
// etkinlik göstergesi isteğe bağlı bir özelliktir, sohbeti asla engellemez.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/juzzio_chat_activity.dart';

class JuzzioChatActivityService extends ChangeNotifier {
  JuzzioChatActivityService._();
  static final JuzzioChatActivityService instance = JuzzioChatActivityService._();

  static const String _event = 'activity';

  final JuzzioChatActivityResolver resolver = JuzzioChatActivityResolver();
  JuzzioActivitySender _sender = JuzzioActivitySender();
  RealtimeChannel? _channel;
  String? _roomId;
  Set<String>? _members;
  Timer? _ticker;

  String? get roomId => _roomId;

  /// Açık sohbet değişince çağrılır (null → dinlemeyi bırak).
  Future<void> watchRoom(String? roomId, {Set<String>? memberIds}) async {
    if (roomId == _roomId) {
      _members = memberIds ?? _members;
      return;
    }
    await _leave();
    if (roomId == null) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    _roomId = roomId;
    _members = memberIds;
    _sender = JuzzioActivitySender();
    try {
      final ch = client.channel(
        'room-activity:$roomId',
        opts: const RealtimeChannelConfig(private: true, self: false),
      );
      ch.onBroadcast(
        event: _event,
        callback: (payload) {
          final u = payload['u']?.toString() ?? '';
          final changed = resolver.onRemote(u, juzzioActivityFromWire(payload['s']),
              selfId: uid, allowedUserIds: _members);
          if (changed) notifyListeners();
        },
      );
      ch.subscribe();
      _channel = ch;
    } catch (_) {
      _channel = null;
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      final out = _sender.tick();
      if (out != null) _send(out);
      if (resolver.prune()) notifyListeners();
    });
    notifyListeners();
  }

  /// Yerel durum: metin alanı değişti → typing; kayıt başladı → recording; gönderildi/çıkıldı → idle.
  void setLocal(JuzzioActivityState state) {
    final out = _sender.set(state);
    if (out != null) _send(out);
  }

  void _send(JuzzioActivityState s) {
    final ch = _channel;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (ch == null || uid == null) return;
    try {
      ch.sendBroadcastMessage(event: _event, payload: {'u': uid, 's': s.name});
    } catch (_) {}
  }

  Future<void> _leave() async {
    _ticker?.cancel();
    _ticker = null;
    if (_sender.state != JuzzioActivityState.idle) _send(JuzzioActivityState.idle);
    final ch = _channel;
    _channel = null;
    _roomId = null;
    _members = null;
    resolver.clear();
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    notifyListeners();
  }
}
