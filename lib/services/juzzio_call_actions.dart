// =============================================================================
// JUZZIO v0.9.0 — Gelen arama bildirimi eylemleri (ek paket N-F)
// "Reddet": uygulamayı açmadan sunucudaki juzzio_decline_call RPC'si (yalnız aranan kişi,
// yalnız çalan arama — sunucuda doğrulanır, idempotent).
// "Kabul": uygulamayı açar; ChatScreen aynı çağrı kimliği çalarken normal cevaplama yolunu
// (update_call_status 'answered' + LiveKit belirteci sunucuda doğrulanır) kullanır.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class JuzzioCallActions {
  JuzzioCallActions._();

  static final RegExp _uuidRe =
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Test için RPC çağrısı değiştirilebilir.
  static Future<Object?> Function(String callId)? rpcOverride;

  static bool isValidCallId(String id) => _uuidRe.hasMatch(id);

  /// Sonuç: 'rejected' | sunucudaki mevcut durum | 'error'.
  static Future<String> decline(String callId) async {
    if (!isValidCallId(callId)) return 'error';
    try {
      final o = rpcOverride;
      final res = o != null
          ? await o(callId)
          : await Supabase.instance.client.rpc('juzzio_decline_call', params: {'p_call': callId});
      final s = res?.toString() ?? '';
      return s.isEmpty ? 'error' : s;
    } catch (_) {
      return 'error';
    }
  }

  static Future<Map<String, Object?>> handleChannelArgs(Map<dynamic, dynamic> args) async {
    final action = args['action']?.toString();
    final id = args['call_id']?.toString() ?? '';
    if (action != 'decline') return {'status': 'error'};
    return {'status': await decline(id)};
  }
}
