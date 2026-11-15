// =============================================================================
// JUZZIO v1.2.9 — Ses koruyucu (tek merkez)
//  Şu durumlarda uygulamadaki TÜM müzikler (profil, hikâye, sohbette paylaşılan müzik) durur
//  ve açık hikâye duraklar:
//   • arama geldiğinde / arama başlatıldığında            → reason: 'call'
//   • uygulama arka plana alındığında                     → reason: 'background'
//   • başka bir uygulama ses başlattığında (YouTube vb.)  → reason: 'focus'
//   • kulaklık çıkarıldığında                             → reason: 'noisy'
// =============================================================================

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

class JuzzioAudioGuard with WidgetsBindingObserver {
  JuzzioAudioGuard._();
  static final JuzzioAudioGuard instance = JuzzioAudioGuard._();

  /// Her kesintide artar; dinleyiciler (hikâye görüntüleyici, müzik oynatıcılar) durur
  final ValueNotifier<int> interruptions = ValueNotifier<int>(0);
  String lastReason = '';
  bool _installed = false;
  final List<Future<void> Function()> _stoppers = [];

  /// Müzik oynatıcıları kendini kaydeder (döngüsel içe aktarma olmadan durdurulabilsin)
  void registerStopper(Future<void> Function() stop) {
    if (!_stoppers.contains(stop)) _stoppers.add(stop);
  }

  void interrupt(String reason) {
    lastReason = reason;
    interruptions.value++;
    for (final s in List.of(_stoppers)) {
      unawaited(s().catchError((_) {}));
    }
  }

  Future<void> install() async {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((e) {
        if (e.begin) interrupt('focus');
      });
      session.becomingNoisyEventStream.listen((_) => interrupt('noisy'));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) interrupt('background');
  }
}
