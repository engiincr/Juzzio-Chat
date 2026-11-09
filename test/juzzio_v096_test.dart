// JUZZIO v0.9.6 birim testleri
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/call_screen.dart';
import 'package:juzzio/services/juzzio_error_reporter.dart';
import 'package:juzzio/services/juzzio_features_service.dart';
import 'package:juzzio/widgets/juzzio_eye_comfort.dart';

void main() {
  group('Göz Konforu', () {
    test('kapalı / her zaman açık', () {
      final now = DateTime(2026, 11, 9, 13);
      expect(juzzioEyeComfortActive(mode: 'off', now: now), isFalse);
      expect(juzzioEyeComfortActive(mode: 'on', now: now), isTrue);
    });

    test('gece yarısını aşan zamanlama 20:00–07:00', () {
      bool at(int h, int m) => juzzioEyeComfortActive(mode: 'schedule', now: DateTime(2026, 11, 9, h, m), startMin: 1200, endMin: 420);
      expect(at(19, 59), isFalse);
      expect(at(20, 0), isTrue);
      expect(at(23, 30), isTrue);
      expect(at(3, 0), isTrue);
      expect(at(6, 59), isTrue);
      expect(at(7, 0), isFalse);
      expect(at(12, 0), isFalse);
    });

    test('aynı gün içinde zamanlama 13:00–15:00', () {
      bool at(int h) => juzzioEyeComfortActive(mode: 'schedule', now: DateTime(2026, 11, 9, h), startMin: 780, endMin: 900);
      expect(at(12), isFalse);
      expect(at(14), isTrue);
      expect(at(15), isFalse);
    });

    test('gün doğumu / batımı (İstanbul, gün uzunluğu)', () {
      final summer = juzzioSunTimes(DateTime(2026, 6, 21), 41.01, 28.97)!;
      final winter = juzzioSunTimes(DateTime(2026, 12, 21), 41.01, 28.97)!;
      final summerLen = summer.sunset.difference(summer.sunrise).inMinutes;
      final winterLen = winter.sunset.difference(winter.sunrise).inMinutes;
      // Yaz gün dönümü ≈ 15 sa 08 dk, kış ≈ 9 sa 13 dk (NOAA)
      expect(summerLen, inInclusiveRange(15 * 60, 15 * 60 + 15));
      expect(winterLen, inInclusiveRange(9 * 60 + 5, 9 * 60 + 20));
    });

    test('kutup gecesi null döner', () {
      expect(juzzioSunTimes(DateTime(2026, 12, 21), 78.2, 15.6), isNull);
    });

    test('yoğunluk renk alfası sınırlı', () {
      expect(juzzioEyeComfortColor(5).a, lessThan(0.05));
      expect(juzzioEyeComfortColor(200).a, closeTo(0.36, 0.01));
    });
  });

  group('Hata raporlayıcı', () {
    test('hassas veri maskelenir', () {
      final s = juzzioScrubErrorText('mail ali@example.com tel +90 555 123 45 67 token=abc123 https://x.co/a?key=secret');
      expect(s, isNot(contains('ali@example.com')));
      expect(s, isNot(contains('555 123')));
      expect(s, isNot(contains('abc123')));
      expect(s, isNot(contains('secret')));
      expect(s, contains('<email>'));
      expect(s, contains('https://x.co/a?<q>'));
    });

    test('uzunluk sınırı', () {
      expect(juzzioScrubErrorText('x' * 5000).length, 1000);
    });

    test('parmak izi satır numarasından bağımsız ve kararlı', () {
      const a = '#0 Foo.bar (package:juzzio/screens/chat_screen.dart:120:7)\n#1 main (package:juzzio/main.dart:10:3)';
      const b = '#0 Foo.bar (package:juzzio/screens/chat_screen.dart:140:9)\n#1 main (package:juzzio/main.dart:12:3)';
      expect(juzzioErrorFingerprint('StateError', a), juzzioErrorFingerprint('StateError', b));
      expect(juzzioErrorFingerprint('StateError', a), isNot(juzzioErrorFingerprint('RangeError', a)));
      expect(juzzioErrorFingerprint('StateError', a).length, 32);
    });
  });

  test('Uygulama ayarları: medya sınırları ve minimum sürüm', () {
    final c = JuzzioAppConfig.fromMap({
      'voice_max_seconds': 120,
      'audio_bitrate_kbps': 9999,
      'video_max_seconds': 60,
      'min_supported_build': 96,
      'error_reporting_enabled': false,
    });
    expect(c.voiceMaxSeconds, 120);
    expect(c.audioBitrateKbps, 256); // sınıra kırpılır
    expect(c.videoMaxSeconds, 60);
    expect(c.minSupportedBuild, 96);
    expect(c.errorReportingEnabled, isFalse);
    const d = JuzzioAppConfig();
    expect(d.voiceMaxSeconds, 300);
    expect(d.minSupportedBuild, 0);
  });

  test('Veri Koruma önerisi yalnız mobil veride', () {
    expect(juzzioShouldOfferDataSaver([ConnectivityResult.mobile]), isTrue);
    expect(juzzioShouldOfferDataSaver([ConnectivityResult.mobile, ConnectivityResult.wifi]), isFalse);
    expect(juzzioShouldOfferDataSaver([ConnectivityResult.wifi]), isFalse);
    expect(juzzioShouldOfferDataSaver([ConnectivityResult.none]), isFalse);
  });
}
