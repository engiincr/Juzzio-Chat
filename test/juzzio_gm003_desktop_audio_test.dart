// GM-003 (21.11.2026) — Masaüstü arama ses aygıtları: karşı tarafın sesi doğru çıkıştan gelsin
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_desktop_audio.dart';
import 'package:livekit_client/livekit_client.dart';

String _src(String p) => File(p).readAsStringSync();
MediaDevice _out(String id, String label) =>
    MediaDevice(id, label, 'audiooutput', '');

void main() {
  // WebRTC'nin Windows'ta verdiği tipik liste: 0 = Default, 1 = Communication, sonra gerçek aygıtlar
  final win = [
    _out('d0', 'Default - Hoparlör (Realtek(R) Audio)'),
    _out('d1', 'Communication - Kulaklık (USB Headset)'),
    _out('d2', 'Hoparlör (Realtek(R) Audio)'),
    _out('d3', 'Kulaklık (USB Headset)'),
    _out('d4', 'FxSound Speakers (FxSound Audio Enhancer)'),
  ];

  group('juzzioPickDevice', () {
    test('kayıt yoksa normal varsayılan seçilir, iletişim aygıtı seçilmez', () {
      expect(juzzioPickDevice(win)!.deviceId, 'd0');
    });
    test('kayıtlı kimlik önce gelir', () {
      expect(juzzioPickDevice(win, savedId: 'd3')!.deviceId, 'd3');
    });
    test('kimlik değiştiyse kayıtlı ad ile bulunur', () {
      expect(
          juzzioPickDevice(win,
                  savedId: 'eski', savedLabel: 'Kulaklık (USB Headset)')!
              .deviceId,
          'd3');
    });
    test('kayıtlı aygıt çıkarıldıysa varsayılana döner', () {
      expect(juzzioPickDevice(win, savedId: 'yok', savedLabel: 'Yok')!.deviceId,
          'd0');
    });
    test('Default etiketi yoksa iletişim olmayan ilk aygıt', () {
      final l = [
        _out('c', 'Communication - X'),
        _out('r', 'Hoparlör (Realtek)')
      ];
      expect(juzzioPickDevice(l)!.deviceId, 'r');
    });
    test('boş listede null', () {
      expect(juzzioPickDevice(const []), isNull);
    });
  });

  test(
      'arama hattı masaüstünde çıkışı açıkça seçer ve aramadan çıkınca bırakır',
      () {
    final s = _src('lib/services/deepgram_livekit_service.dart');
    expect(s.contains('JuzzioDesktopAudio.instance.attach(_room!)'), isTrue);
    expect(s.contains('JuzzioDesktopAudio.instance.reapply()'), isTrue);
    expect(s.contains('JuzzioDesktopAudio.instance.detach()'), isTrue);
    final d = _src('lib/services/juzzio_desktop_audio.dart');
    expect(d.contains('room.setAudioOutputDevice(d)'), isTrue);
    expect(d.contains('room.setAudioInputDevice(d)'), isTrue);
  });

  test('arama ekranı: masaüstünde hoparlör düğmesi aygıt seçiciyi açar', () {
    final c = _src('lib/screens/call_screen.dart');
    expect(
        c.contains(
            'JuzzioDesktopAudio.instance.supported ? _openAudioOutputPicker : _controller.toggleSpeakerphone'),
        isTrue);
    final k = _src('lib/widgets/juzzio_call_kit21.dart');
    expect(
        k.contains(
            'if (JuzzioDesktopAudio.instance.supported) return showJuzzioDesktopAudioSheet(context);'),
        isTrue);
  });
}
