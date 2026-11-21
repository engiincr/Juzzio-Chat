// v2.1 — Arama ses çıkışı yönlendirmesi (ahize / hoparlör / kablolu kulaklık / Bluetooth)
//
// Kurallar:
//  * Kulaklık bağlıysa ses otomatik kulaklığa gider.
//  * Kulaklık arama sırasında çıkarılırsa ses HOPARLÖRE DEĞİL ahizeye döner (Android yerel katman).
//  * Hoparlör düğmesi hoparlörü açar/kapatır; yanındaki ok ile tüm çıkışlar seçilebilir.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

enum JuzzioAudioOutput { earpiece, speaker, wired, bluetooth }

JuzzioAudioOutput juzzioAudioOutputFrom(String? s) {
  switch (s) {
    case 'speaker':
      return JuzzioAudioOutput.speaker;
    case 'wired':
      return JuzzioAudioOutput.wired;
    case 'bluetooth':
      return JuzzioAudioOutput.bluetooth;
    default:
      return JuzzioAudioOutput.earpiece;
  }
}

String juzzioAudioOutputKey(JuzzioAudioOutput o) => switch (o) {
      JuzzioAudioOutput.earpiece => 'earpiece',
      JuzzioAudioOutput.speaker => 'speaker',
      JuzzioAudioOutput.wired => 'wired',
      JuzzioAudioOutput.bluetooth => 'bluetooth',
    };

/// Kulaklık çıkarıldığında hangi çıkışa dönülür? (Saf kural; testlerde de kullanılır.)
/// Hoparlöre ASLA otomatik geçilmez: kalan başka kulaklık yoksa ahize.
JuzzioAudioOutput juzzioRouteAfterUnplug(JuzzioAudioOutput removed, Set<JuzzioAudioOutput> stillAvailable) {
  if (removed != JuzzioAudioOutput.bluetooth && stillAvailable.contains(JuzzioAudioOutput.bluetooth)) {
    return JuzzioAudioOutput.bluetooth;
  }
  if (removed != JuzzioAudioOutput.wired && stillAvailable.contains(JuzzioAudioOutput.wired)) {
    return JuzzioAudioOutput.wired;
  }
  return JuzzioAudioOutput.earpiece;
}

class JuzzioAudioRouteController extends ChangeNotifier {
  JuzzioAudioRouteController._();
  static final JuzzioAudioRouteController instance = JuzzioAudioRouteController._();

  static const MethodChannel _ch = MethodChannel('juzzio/notifications');
  static const EventChannel _events = EventChannel('juzzio/audio_route_events');

  JuzzioAudioOutput current = JuzzioAudioOutput.earpiece;
  Set<JuzzioAudioOutput> available = {JuzzioAudioOutput.earpiece, JuzzioAudioOutput.speaker};
  String? bluetoothName;
  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isSpeaker => current == JuzzioAudioOutput.speaker;
  bool get hasHeadset => available.contains(JuzzioAudioOutput.wired) || available.contains(JuzzioAudioOutput.bluetooth);

  void _applyState(Object? raw) {
    if (raw is! Map) return;
    current = juzzioAudioOutputFrom(raw['current']?.toString());
    final av = raw['available'];
    if (av is List) {
      available = av.map((e) => juzzioAudioOutputFrom(e?.toString())).toSet()
        ..add(JuzzioAudioOutput.speaker);
    }
    bluetoothName = raw['bluetoothName']?.toString();
    notifyListeners();
  }

  /// Arama başlarken çağrılır. Görüntülüde hoparlör, sesli aramada ahize tercih edilir;
  /// kulaklık takılıysa her durumda kulaklık.
  Future<void> start({required bool preferSpeaker}) async {
    if (!_mobile) return;
    if (_android) {
      _sub ??= _events.receiveBroadcastStream().listen(_applyState, onError: (_) {});
      try {
        _applyState(await _ch.invokeMethod<Object?>('audioRouteStart', {'preferSpeaker': preferSpeaker}));
        _started = true;
      } catch (_) {
        await _fallbackSpeaker(preferSpeaker);
      }
    } else {
      // iOS: AVAudioSession kulaklığı kendisi seçer; biz yalnız hoparlör/ahize ayarlarız
      available = {JuzzioAudioOutput.earpiece, JuzzioAudioOutput.speaker};
      await _fallbackSpeaker(preferSpeaker);
    }
  }

  Future<void> _fallbackSpeaker(bool on) async {
    try {
      await Hardware.instance.setSpeakerphoneOn(on);
    } catch (_) {}
    current = on ? JuzzioAudioOutput.speaker : JuzzioAudioOutput.earpiece;
    notifyListeners();
  }

  Future<void> select(JuzzioAudioOutput o) async {
    if (!_mobile) return;
    if (_android && _started) {
      try {
        _applyState(await _ch.invokeMethod<Object?>('audioRouteSet', {'route': juzzioAudioOutputKey(o)}));
        return;
      } catch (_) {}
    }
    await _fallbackSpeaker(o == JuzzioAudioOutput.speaker);
  }

  /// Hoparlör düğmesi: açıkken kapatınca kulaklık varsa kulaklığa, yoksa ahizeye döner.
  Future<void> toggleSpeaker() async {
    if (isSpeaker) {
      final back = available.contains(JuzzioAudioOutput.bluetooth)
          ? JuzzioAudioOutput.bluetooth
          : available.contains(JuzzioAudioOutput.wired)
              ? JuzzioAudioOutput.wired
              : JuzzioAudioOutput.earpiece;
      await select(back);
    } else {
      await select(JuzzioAudioOutput.speaker);
    }
  }

  Future<void> stop() async {
    if (_android && _started) {
      try {
        await _ch.invokeMethod<Object?>('audioRouteStop');
      } catch (_) {}
    }
    _started = false;
    await _sub?.cancel();
    _sub = null;
  }
}
