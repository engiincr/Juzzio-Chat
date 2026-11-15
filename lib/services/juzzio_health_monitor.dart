// =============================================================================
// JUZZIO v1.2.9 — Sistem Sağlığı ve Otomatik Onarım
//  Arka planda (açılıştan 20 sn sonra, sonra 15 dk'da bir, bir çeviri/arama hatası
//  bildirildiğinde 30 sn içinde) şu parçaları yoklar ve sorun görürse kendiliğinden düzeltir:
//
//   • Sunucu (Supabase)           → juzzio_health_ping
//   • Sohbet çevirisi             → "merhaba" çevrilebiliyor mu? (cihaz yolu + sunucu köprüsü)
//       onarım: Google bekleme süresi sıfırlanır, yol değiştirilir (cihaz ↔ sunucu)
//   • Çeviri sağlayıcısı          → resmî API mı (Google Cloud / DeepL) yoksa ücretsiz uç nokta mı
//       onarım: resmî API varsa cihaz resmî olmayan uç noktayı bırakır (politika uyumu)
//   • Canlı altyazı / sesli mesaj → Deepgram anahtarı sunucuda var mı, geçerli mi
//       onarım: Deepgram yoksa aramalarda cihazın konuşma tanıyıcısı (yedek) hazır mı
//   • Arama sunucusu (LiveKit)    → 443 portuna ulaşılıyor mu
//   • Yedek TURN (ExpressTURN)    → 3478 portuna ulaşılıyor mu
//       onarım: LiveKit'e ulaşılamıyor ama yedek açıksa aramalar 30 dk doğrudan yedekle başlar
//
//  Yoklamalarda kişisel içerik gönderilmez. Toplam veri: yoklama başına birkaç KB (egress dostu).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import 'deepgram_livekit_service.dart';
import 'juzzio_error_reporter.dart';
import 'supabase_service.dart';

enum JuzzioHealthState { unknown, checking, ok, degraded, down }

class JuzzioHealthItem {
  final String id;
  JuzzioHealthState state;
  String detail;
  int latencyMs;
  DateTime? checkedAt;
  String autoFix;
  JuzzioHealthItem(this.id, {this.state = JuzzioHealthState.unknown, this.detail = '', this.latencyMs = 0, this.autoFix = ''});
}

/// Yoklama sonucundan genel durum (saf; test edilir): herhangi biri down → down; degraded → degraded
JuzzioHealthState juzzioOverallHealth(Iterable<JuzzioHealthState> states) {
  var worst = JuzzioHealthState.ok;
  var any = false;
  for (final s in states) {
    if (s == JuzzioHealthState.unknown || s == JuzzioHealthState.checking) continue;
    any = true;
    if (s == JuzzioHealthState.down) return JuzzioHealthState.down;
    if (s == JuzzioHealthState.degraded) worst = JuzzioHealthState.degraded;
  }
  return any ? worst : JuzzioHealthState.unknown;
}

/// Deepgram sunucu yanıtını duruma çevirir (saf; test edilir)
JuzzioHealthState juzzioDeepgramState(String v) {
  if (v == 'ok') return JuzzioHealthState.ok;
  if (v == 'missing' || v == 'invalid_key') return JuzzioHealthState.down;
  return JuzzioHealthState.degraded;
}

class JuzzioHealthMonitor extends ChangeNotifier {
  JuzzioHealthMonitor._();
  static final JuzzioHealthMonitor instance = JuzzioHealthMonitor._();
  static const MethodChannel _native = MethodChannel('juzzio/notifications');

  final Map<String, JuzzioHealthItem> items = {
    for (final id in const ['server', 'translate', 'provider', 'deepgram', 'device_speech', 'livekit', 'backup_turn'])
      id: JuzzioHealthItem(id),
  };
  bool running = false;
  DateTime? lastRun;
  Timer? _periodic;
  Timer? _debounce;
  int _translateFails = 0;
  final List<String> fixLog = [];

  JuzzioHealthState get overall => juzzioOverallHealth(items.values.map((e) => e.state));

  /// Uygulama açılışında bir kez çağrılır (oturum açıldıktan sonra)
  void start() {
    if (_periodic != null) return;
    Timer(const Duration(seconds: 20), () => unawaited(runAll()));
    _periodic = Timer.periodic(const Duration(minutes: 15), (_) => unawaited(runAll()));
  }

  void stop() {
    _periodic?.cancel();
    _periodic = null;
  }

  /// Bir özellik hata verdiğinde çağrılır → 30 sn içinde yoklama + onarım
  void reportFailure(String area) {
    if (area == 'translate') _translateFails++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 30), () => unawaited(runAll()));
  }

  /// İnternet geri gelince (bağlantı izleyicisi kancası) yoklama planlanır
  Future<void> onNetworkRegained() async => reportFailure('network');

  void _fix(String item, String text) {
    items[item]?.autoFix = text;
    fixLog.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} · $text');
    if (fixLog.length > 30) fixLog.removeLast();
  }

  void _set(String id, JuzzioHealthState st, {String detail = '', int ms = 0}) {
    final it = items[id]!;
    // v1.2.9: çalışmayan/kısıtlı parça yönetici paneline nokta atışı hata kaydı olarak gider
    // (cihaz yerelden bağımsız: aynı sorun her kullanıcıdan tek kayıtta toplanır, kurucuya bildirim)
    if ((st == JuzzioHealthState.down || st == JuzzioHealthState.degraded) && it.state != st &&
        !(id == 'provider' && detail == 'unofficial') && !(id == 'device_speech')) {
      unawaited(JuzzioErrorReporter.instance.reportHandled('health:$id', '${st.name} $detail ${ms}ms'));
    }
    it.state = st;
    it.detail = detail;
    it.latencyMs = ms;
    it.checkedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> runAll() async {
    if (running) return;
    final svc = SupabaseService.instance;
    if (svc.currentUserId == null) return;
    running = true;
    for (final it in items.values) {
      it.state = JuzzioHealthState.checking;
    }
    notifyListeners();
    try {
      await Future.wait([_server(), _bridge(), _tcp('livekit', _liveKitHost(), 443), _tcp('backup_turn', JuzzioConfig.backupTurnHost, JuzzioConfig.backupTurnPort), _deviceSpeech()]);
      await _translate();
      // Arama yolu onarımı: ana sunucuya ulaşılamıyor, yedek açıksa → aramalar yedekle başlar
      if (items['livekit']!.state == JuzzioHealthState.down && items['backup_turn']!.state == JuzzioHealthState.ok) {
        DeepgramLiveKitController.markPrimaryUnreachable();
        _fix('livekit', 'Ana arama sunucusuna ulaşılamadı → aramalar 30 dk yedek TURN ile başlayacak');
      } else if (items['livekit']!.state == JuzzioHealthState.ok && DeepgramLiveKitController.preferBackupTurn) {
        DeepgramLiveKitController.clearBackupPreference();
        _fix('livekit', 'Ana arama sunucusu yeniden erişilebilir → yedek tercihi kaldırıldı');
      }
    } finally {
      running = false;
      lastRun = DateTime.now();
      notifyListeners();
    }
  }

  String _liveKitHost() {
    final u = Uri.tryParse(JuzzioConfig.liveKitUrl);
    return u?.host ?? '';
  }

  Future<void> _server() async {
    final sw = Stopwatch()..start();
    try {
      final r = await SupabaseService.instance.client.rpc('juzzio_health_ping').timeout(const Duration(seconds: 8));
      final ok = r is Map && r['ok'] == true;
      _set('server', ok ? JuzzioHealthState.ok : JuzzioHealthState.degraded, ms: sw.elapsedMilliseconds,
          detail: ok && (r['file_blocks_24h'] ?? 0) is num && (r['file_blocks_24h'] as num) > 0 ? 'file_blocks:${r['file_blocks_24h']}' : '');
    } catch (_) {
      _set('server', JuzzioHealthState.down, ms: sw.elapsedMilliseconds);
    }
  }

  Future<void> _bridge() async {
    final sw = Stopwatch()..start();
    try {
      final res = await SupabaseService.instance.client.functions
          .invoke('translate-bridge', body: {'mode': 'health'}).timeout(const Duration(seconds: 15));
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is! Map) throw StateError('bad');
      final provider = '${data['translate_provider'] ?? 'unofficial'}';
      final official = provider != 'unofficial';
      _set('provider', official ? JuzzioHealthState.ok : JuzzioHealthState.degraded, detail: provider, ms: sw.elapsedMilliseconds);
      final svc = SupabaseService.instance;
      if (official && data['translate'] == 'ok' && !svc.preferServerTranslation) {
        svc.preferServerTranslation = true;
        _fix('provider', 'Sunucuda resmî çeviri API\'si var → cihaz resmî olmayan uç noktayı bıraktı');
      }
      final dg = '${data['deepgram'] ?? 'missing'}';
      _set('deepgram', juzzioDeepgramState(dg), detail: dg, ms: sw.elapsedMilliseconds);
    } catch (_) {
      _set('provider', JuzzioHealthState.degraded, detail: 'bridge_unreachable', ms: sw.elapsedMilliseconds);
      _set('deepgram', JuzzioHealthState.degraded, detail: 'bridge_unreachable', ms: sw.elapsedMilliseconds);
    }
  }

  Future<void> _translate() async {
    final svc = SupabaseService.instance;
    Future<bool> probe() async {
      final t = await svc.translateText(text: 'merhaba dünya', sourceLang: 'tr', targetLang: 'en', noCache: true)
          .timeout(const Duration(seconds: 12), onTimeout: () => '');
      final low = t.toLowerCase();
      return t.isNotEmpty && !low.contains('merhaba');
    }

    final sw = Stopwatch()..start();
    var ok = false;
    try {
      ok = await probe();
    } catch (_) {}
    if (!ok) {
      // Onarım 1: bekleme süresini sıfırla ve yolu değiştir (cihaz ↔ sunucu), tekrar dene
      svc.resetTranslationCooldown();
      svc.preferServerTranslation = !svc.preferServerTranslation;
      _fix('translate', svc.preferServerTranslation
          ? 'Cihazdan çeviri çalışmadı → sunucu köprüsüne geçildi'
          : 'Sunucu köprüsü çalışmadı → cihazdan çeviriye geçildi');
      try {
        ok = await probe();
      } catch (_) {}
      if (!ok) {
        // Onarım 2: diğer yola da dön (hangisi çalışırsa)
        svc.preferServerTranslation = !svc.preferServerTranslation;
        try {
          ok = await probe();
        } catch (_) {}
      }
    }
    if (ok) _translateFails = 0;
    _set('translate', ok ? JuzzioHealthState.ok : JuzzioHealthState.down,
        ms: sw.elapsedMilliseconds, detail: svc.preferServerTranslation ? 'server' : 'device');
  }

  Future<void> _tcp(String id, String host, int port) async {
    if (host.isEmpty) {
      _set(id, JuzzioHealthState.unknown);
      return;
    }
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      s.destroy();
      _set(id, JuzzioHealthState.ok, ms: sw.elapsedMilliseconds, detail: '$host:$port');
    } catch (_) {
      _set(id, JuzzioHealthState.down, ms: sw.elapsedMilliseconds, detail: '$host:$port');
    }
  }

  Future<void> _deviceSpeech() async {
    if (!Platform.isAndroid) {
      _set('device_speech', JuzzioHealthState.unknown);
      return;
    }
    try {
      final ok = await _native.invokeMethod<bool>('speechAvailable') ?? false;
      _set('device_speech', ok ? JuzzioHealthState.ok : JuzzioHealthState.degraded);
    } catch (_) {
      _set('device_speech', JuzzioHealthState.degraded);
    }
  }

  @visibleForTesting
  int get translateFailures => _translateFails;
}
