// GM-007 (21.11.2026) — Görüntülü aramada ekran paylaşımı başlatılamıyordu
// Kök neden: masaüstünde LiveKit'e kaynak (sourceId) verilmiyor ve kaynak listesi çekilmiyordu;
// flutter_webrtc Windows'ta bu durumda "source not found!" hatası verir.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  final svc = _src('lib/services/deepgram_livekit_service.dart');
  final screen = _src('lib/screens/call_screen.dart');
  final kit = _src('lib/widgets/juzzio_call_kit21.dart');

  test(
      'masaüstü: kaynak listesi önce çekilir ve seçilen kaynak LiveKit e verilir',
      () {
    expect(svc.contains('webrtc.desktopCapturer.getSources('), isTrue);
    expect(svc.contains('ScreenShareCaptureOptions(sourceId: id'), isTrue);
    expect(
        svc.contains(
            'Future<bool> setScreenShare(bool on, {String? sourceId})'),
        isTrue);
  });

  test('kaynak seçilmezse ilk ekran kullanılır; ekran yoksa anlaşılır hata',
      () {
    expect(svc.contains("s.type == webrtc.SourceType.Screen"), isTrue);
    expect(svc.contains("lastScreenShareError = 'no_source'"), isTrue);
  });

  test('Android: izin reddi ayrı bildirilir, ön plan servisi akışı korunur',
      () {
    expect(svc.contains("lastScreenShareError = 'permission'"), isTrue);
    expect(svc.contains("'setScreenShareForeground', {'on': true"), isTrue);
    expect(svc.contains('webrtc.Helper.requestCapturePermission()'), isTrue);
  });

  test(
      'arama ekranı: masaüstünde önce ekran/pencere seçici açılır, vazgeçilirse paylaşım başlamaz',
      () {
    expect(
        screen.contains(
            'showJuzzioScreenSourcePicker(context, _controller.desktopShareSources)'),
        isTrue);
    expect(
        screen.contains('if (sourceId == null || !mounted) return;'), isTrue);
    expect(screen.contains("err == 'permission'"), isTrue);
  });

  test(
      'seçici uygulamanın Liquid Glass bileşeniyle çizilir (KR-009), sabit renk yok',
      () {
    final i = kit.indexOf('Future<String?> showJuzzioScreenSourcePicker');
    expect(i, greaterThan(0));
    final picker = kit.substring(i);
    expect(picker.contains('JuzzioLiquidGlass('), isTrue);
    expect(RegExp(r'Color\(0x').hasMatch(picker), isFalse);
  });
}
