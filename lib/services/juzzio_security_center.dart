// =============================================================================
// JUZZIO v0.9.0 — Güvenlik Merkezi servisi (C-A5)
//  Tüm veriler sunucudan (10.22): cihazlar, doğrulanabilir güvenlik olayları, özet.
//  Diğer oturumları kapatma Supabase Auth `signOut(scope: others)` ile yapılır.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import 'juzzio_features_service.dart';

class JuzzioDeviceEntry {
  const JuzzioDeviceEntry({required this.suffix, required this.platform, required this.firstSeen, required this.lastSeen, required this.current});
  final String suffix;
  final String platform;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final bool current;

  static JuzzioDeviceEntry fromMap(Map<String, dynamic> m) => JuzzioDeviceEntry(
        suffix: (m['device'] ?? '').toString(),
        platform: (m['platform'] ?? '').toString(),
        firstSeen: DateTime.tryParse((m['first_seen'] ?? '').toString())?.toLocal(),
        lastSeen: DateTime.tryParse((m['last_seen'] ?? '').toString())?.toLocal(),
        current: m['current'] == true,
      );
}

class JuzzioSecurityEvent {
  const JuzzioSecurityEvent({required this.id, required this.kind, required this.detail, required this.seen, required this.createdAt});
  final int id;
  final String kind;
  final Map<String, dynamic> detail;
  final bool seen;
  final DateTime? createdAt;

  static const knownKinds = {'new_device', 'device_removed', 'e2ee_key_changed'};

  static JuzzioSecurityEvent? fromMap(Map<String, dynamic> m) {
    final kind = (m['kind'] ?? '').toString();
    if (!knownKinds.contains(kind)) return null; // bilinmeyen tür gösterilmez (uydurma uyarı yok)
    final d = m['detail'];
    return JuzzioSecurityEvent(
      id: int.tryParse('${m['id']}') ?? 0,
      kind: kind,
      detail: d is Map ? Map<String, dynamic>.from(d) : const {},
      seen: m['seen'] == true,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal(),
    );
  }
}

class JuzzioSecurityOverview {
  const JuzzioSecurityOverview({required this.devices, required this.unseenAlerts, required this.e2eeReady});
  final int devices;
  final int unseenAlerts;
  final bool e2eeReady;

  static JuzzioSecurityOverview fromMap(Map<String, dynamic> m) => JuzzioSecurityOverview(
        devices: int.tryParse('${m['devices']}') ?? 0,
        unseenAlerts: int.tryParse('${m['unseen_alerts']}') ?? 0,
        e2eeReady: m['e2ee_ready'] == true,
      );
}

class JuzzioSecurityCenterService {
  JuzzioSecurityCenterService._();
  static final JuzzioSecurityCenterService instance = JuzzioSecurityCenterService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<JuzzioSecurityOverview> overview() async {
    final r = await _db.rpc('get_my_security_overview');
    return JuzzioSecurityOverview.fromMap(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<List<JuzzioDeviceEntry>> devices() async {
    final cur = await JuzzioFeaturesService.instance.deviceId();
    final r = await _db.rpc('list_my_devices', params: {'p_current_device': cur});
    return [for (final x in (r is List ? r : const [])) if (x is Map) JuzzioDeviceEntry.fromMap(Map<String, dynamic>.from(x))];
  }

  Future<List<JuzzioSecurityEvent>> events({int limit = 50}) async {
    final rows = await _db.from('security_events').select().order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((x) => JuzzioSecurityEvent.fromMap(Map<String, dynamic>.from(x)))
        .whereType<JuzzioSecurityEvent>()
        .toList();
  }

  Future<bool> forgetDevice(String suffix) async {
    final cur = await JuzzioFeaturesService.instance.deviceId();
    return (await _db.rpc('forget_my_device', params: {'p_device_suffix': suffix, 'p_current_device': cur})) == true;
  }

  Future<void> markSeen() => _db.rpc('mark_my_security_events_seen');

  /// Bu cihaz dışındaki tüm oturumları sonlandırır (refresh token'lar iptal edilir).
  Future<void> signOutOtherSessions() => _db.auth.signOut(scope: SignOutScope.others);
}
