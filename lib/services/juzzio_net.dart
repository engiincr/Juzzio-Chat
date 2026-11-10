// =============================================================================
// JUZZIO v1.2.4 — Bağlantı izleyici (çevrimdışı öncelikli çalışma)
//  • İnternet durumunu tek yerden yayınlar (connectivity_plus).
//  • Bağlantı GERİ GELDİĞİNDE: bekleyen profil/ayar değişiklikleri sunucuya yazılır,
//    canlı akışlar (aramalar, hikâyeler, bildirimler, arkadaşlıklar) yeniden bağlanır,
//    ekranlar sessizce yenilenir. Kullanıcı hiçbir şeyi elle yenilemek zorunda kalmaz.
//  • "Çevrimdışı" yalnız bir İPUCUDUR: önbellekteki içerik her zaman gösterilir; ağ
//    isteği yine denenir (Wi-Fi bağlı ama internet yok durumları da güvenle ele alınır).
// =============================================================================

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Bağlantı sonucu listesinden "ağ var mı" (saf; test edilir)
bool juzzioHasNetwork(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

class JuzzioNet extends ChangeNotifier {
  JuzzioNet._();
  static final JuzzioNet instance = JuzzioNet._();

  bool _online = true;
  bool get online => _online;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  final StreamController<void> _regained = StreamController<void>.broadcast();

  /// Bağlantı yeniden kurulduğunda tetiklenir (çevrimdışı → çevrimiçi geçişi).
  Stream<void> get onRegained => _regained.stream;

  final List<Future<void> Function()> _regainHooks = <Future<void> Function()>[];

  /// Bağlantı gelince çalışacak iş (ör. bekleyen işlemleri gönder). Tekrar eklenmez.
  void addRegainHook(Future<void> Function() hook) {
    if (!_regainHooks.contains(hook)) _regainHooks.add(hook);
  }

  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    try {
      final c = Connectivity();
      c.checkConnectivity().then(_apply).catchError((_) {});
      _sub = c.onConnectivityChanged.listen(_apply, onError: (_) {});
    } catch (_) {
      // test ortamı / eklenti yok: çevrimiçi varsayılır
    }
  }

  void _apply(List<ConnectivityResult> r) => setOnline(juzzioHasNetwork(r));

  /// Ağ isteği başarısız/başarılı olduğunda da çağrılabilir (gerçek durumu düzeltir).
  void setOnline(bool v) {
    if (v == _online) return;
    final regained = v && !_online;
    _online = v;
    notifyListeners();
    if (regained) {
      _regained.add(null);
      for (final h in List.of(_regainHooks)) {
        unawaited(h().catchError((_) {}));
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
