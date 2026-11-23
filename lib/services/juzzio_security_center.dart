// =============================================================================
// JUZZIO v0.9.0 — Güvenlik Merkezi servisi (C-A5)
//  Tüm veriler sunucudan (10.22): cihazlar, doğrulanabilir güvenlik olayları, özet.
//  Diğer oturumları kapatma Supabase Auth `signOut(scope: others)` ile yapılır.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import 'juzzio_features_service.dart';
import 'supabase_service.dart';

class JuzzioDeviceEntry {
  const JuzzioDeviceEntry({required this.suffix, required this.platform, required this.firstSeen, required this.lastSeen, required this.current,
      this.model = '', this.country = '', this.place = ''});
  final String model;
  final String country; // ISO-2 (IP başlığından)
  final String place; // "Türkiye / Aydın" (cihazın kendi yaklaşık konumundan)
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
        model: (m['model'] ?? '').toString().trim(),
        country: (m['country'] ?? '').toString().trim().toUpperCase(),
        place: (m['place'] ?? '').toString().trim(),
      );

  /// GM-050: "Xiaomi 15 Ultra | Türkiye / Aydın". Model yoksa platform adı; kimlik soneki gösterilmez.
  String title({String lang = 'tr'}) {
    final name = model.isNotEmpty ? model : juzzioPlatformLabel(platform);
    final loc = place.isNotEmpty ? place : juzzioCountryName(country, lang: lang);
    return loc.isEmpty ? name : '$name | $loc';
  }
}

String juzzioPlatformLabel(String p) => switch (p.toLowerCase()) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'windows' => 'Windows PC',
      'macos' => 'Mac',
      'linux' => 'Linux PC',
      _ => 'Cihaz',
    };

/// Yerleşik kısa ülke adı tablosu (bilinmeyen kod → kodun kendisi)
String juzzioCountryName(String cc, {String lang = 'tr'}) {
  if (cc.length != 2 || cc == 'XX' || cc == 'T1') return '';
  const tr = {
    'TR': 'Türkiye', 'US': 'ABD', 'GB': 'Birleşik Krallık', 'DE': 'Almanya', 'FR': 'Fransa', 'NL': 'Hollanda',
    'IT': 'İtalya', 'ES': 'İspanya', 'RU': 'Rusya', 'UA': 'Ukrayna', 'AZ': 'Azerbaycan', 'GR': 'Yunanistan',
    'BG': 'Bulgaristan', 'IR': 'İran', 'IQ': 'Irak', 'SA': 'Suudi Arabistan', 'AE': 'BAE', 'CY': 'Kıbrıs',
    'AT': 'Avusturya', 'CH': 'İsviçre', 'BE': 'Belçika', 'SE': 'İsveç', 'NO': 'Norveç', 'PL': 'Polonya',
    'CN': 'Çin', 'JP': 'Japonya', 'KR': 'Güney Kore', 'IN': 'Hindistan', 'CA': 'Kanada', 'BR': 'Brezilya',
  };
  const en = {
    'TR': 'Türkiye', 'US': 'USA', 'GB': 'United Kingdom', 'DE': 'Germany', 'FR': 'France', 'NL': 'Netherlands',
    'IT': 'Italy', 'ES': 'Spain', 'RU': 'Russia', 'UA': 'Ukraine', 'AZ': 'Azerbaijan', 'GR': 'Greece',
  };
  if (lang == 'tr') return tr[cc] ?? cc;
  return en[cc] ?? cc;
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
    final ok = (await _db.rpc('forget_my_device', params: {'p_device_suffix': suffix, 'p_current_device': cur})) == true;
    if (ok) await SupabaseService.instance.recordLifecycle('device_removed', suffix);
    return ok;
  }

  Future<void> markSeen() => _db.rpc('mark_my_security_events_seen');

  /// Bu cihaz dışındaki tüm oturumları sonlandırır (refresh token'lar iptal edilir).
  Future<void> signOutOtherSessions() async {
    await SupabaseService.instance.recordLifecycle('sign_out_others');
    await _db.auth.signOut(scope: SignOutScope.others);
  }
}
