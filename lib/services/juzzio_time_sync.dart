// =============================================================================
// JUZZIO v0.9.4 — Sunucu saati eşitleme (cihaz saati değiştirme koruması)
//  • Açılışta ve uygulama öne geldiğinde get_server_time() RPC'si çağrılır; ağ gecikmesinin
//    yarısı düşülerek ofset = sunucu − cihaz hesaplanır.
//  • |ofset| > 2 dk ise kullanıcıya "Tarih ve saatinizi eşitleyin" uyarısı gösterilir
//    (Android Tarih ve Saat ayarlarına tek dokunuşla gider).
//  • JuzzioClock.now() uygulama içi süre hesaplarında (civciv bekleme, hikâye süresi vb.)
//    cihaz saati yerine sunucuya göre düzeltilmiş saati verir.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'supabase_service.dart';

/// Ofset (sunucu − cihaz) kabul sınırı.
const Duration kJuzzioClockTolerance = Duration(minutes: 2);

/// Saf hesap: RTT'nin yarısını ekleyerek ofseti bulur (test edilebilir).
Duration juzzioClockOffset({required DateTime serverUtc, required DateTime sentUtc, required DateTime receivedUtc}) {
  final rtt = receivedUtc.difference(sentUtc);
  final deviceAtServerMoment = sentUtc.add(rtt ~/ 2);
  return serverUtc.difference(deviceAtServerMoment);
}

bool juzzioClockDrifted(Duration offset) => offset.abs() > kJuzzioClockTolerance;

class JuzzioClock {
  JuzzioClock._();
  static Duration _offset = Duration.zero;
  static Duration get offset => _offset;
  static DateTime now() => DateTime.now().add(_offset);
  static DateTime nowUtc() => DateTime.now().toUtc().add(_offset);
  @visibleForTesting
  static set debugOffset(Duration d) => _offset = d;
}

class JuzzioTimeSync extends ChangeNotifier {
  JuzzioTimeSync._();
  static final JuzzioTimeSync instance = JuzzioTimeSync._();
  static const MethodChannel _native = MethodChannel('juzzio/notifications');

  bool _drifted = false;
  DateTime? _lastCheck;
  bool _checking = false;

  bool get drifted => _drifted;
  Duration get offset => JuzzioClock.offset;

  Future<void> check({bool force = false}) async {
    if (_checking) return;
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last).abs() < const Duration(minutes: 1)) return;
    _checking = true;
    try {
      final sent = DateTime.now().toUtc();
      final raw = await SupabaseService.instance.client.rpc('get_server_time').timeout(const Duration(seconds: 8));
      final received = DateTime.now().toUtc();
      final server = DateTime.tryParse(raw.toString())?.toUtc();
      if (server == null) return;
      // Ağ çok yavaşsa (RTT > 10 sn) ölçüm güvenilmez; önceki değer korunur
      if (received.difference(sent) > const Duration(seconds: 10)) return;
      final off = juzzioClockOffset(serverUtc: server, sentUtc: sent, receivedUtc: received);
      JuzzioClock._offset = off;
      final was = _drifted;
      _drifted = juzzioClockDrifted(off);
      _lastCheck = DateTime.now();
      if (was != _drifted) notifyListeners();
    } catch (_) {
      // çevrimdışı: ölçüm yapılamadı, uyarı durumu değişmez
    } finally {
      _checking = false;
    }
  }

  Future<void> openDateSettings() async {
    try {
      await _native.invokeMethod('openDateSettings');
    } catch (_) {}
  }
}
