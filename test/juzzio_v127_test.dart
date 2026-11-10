// JUZZIO v1.2.7 — hava teması simgeleri, yenileme eli, gönderme uçuşu, 3B doğum günü, tanıtım videosu
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_intro.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';
import 'package:juzzio/widgets/juzzio_weather_ambience.dart';
import 'package:juzzio/widgets/motion/juzzio_birthday_fx.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('Hava teması: saate göre minik vektör simgeler', () {
    test('gece hilal + yıldız, gündüz güneş, akşam turuncu güneş', () {
      expect(juzzioWeatherDoodles(23, JuzzioWeatherKind.clear), contains(JuzzioWeatherDoodle.moon));
      expect(juzzioWeatherDoodles(2, JuzzioWeatherKind.clear), contains(JuzzioWeatherDoodle.star));
      expect(juzzioWeatherDoodles(12, JuzzioWeatherKind.clear), contains(JuzzioWeatherDoodle.sun));
      expect(juzzioWeatherDoodles(12, JuzzioWeatherKind.clear), isNot(contains(JuzzioWeatherDoodle.moon)));
      expect(juzzioWeatherDoodles(18, JuzzioWeatherKind.clear), contains(JuzzioWeatherDoodle.sunset));
    });
    test('havaya göre: yağmur damla, kar tanesi, fırtına şimşek, bulutlu bulut', () {
      expect(juzzioWeatherDoodles(10, JuzzioWeatherKind.rain), contains(JuzzioWeatherDoodle.drop));
      expect(juzzioWeatherDoodles(10, JuzzioWeatherKind.snow), contains(JuzzioWeatherDoodle.snowflake));
      expect(juzzioWeatherDoodles(22, JuzzioWeatherKind.thunder), contains(JuzzioWeatherDoodle.bolt));
      expect(juzzioWeatherDoodles(22, JuzzioWeatherKind.clouds).first, JuzzioWeatherDoodle.cloud);
      for (final k in JuzzioWeatherKind.values) {
        for (var h = 0; h < 24; h++) {
          expect(juzzioWeatherDoodles(h, k), isNotEmpty);
        }
      }
    });
    test('açık havada da döngü çalışır (simgeler süzülür)', () {
      final s = _src('lib/widgets/juzzio_weather_ambience.dart');
      expect(s.contains('st.kind != JuzzioWeatherKind.clear && JuzzioAppController'), isFalse);
      expect(s.contains('_doodles(canvas, size, v, a);'), isTrue);
    });
  });

  group('Tombul el: ilk çekişte tutar', () {
    test('eşik ≈100 dp çekişte kurulur (eskiden ~145 dp)', () {
      expect(juzzioRefreshArmed(juzzioRefreshTravel(100)), isTrue);
      expect(juzzioRefreshArmed(juzzioRefreshTravel(80)), isFalse);
    });
    test('el yumruk yapınca kilitlenir; parmak biraz geri gelse de yenilenir', () {
      expect(juzzioRefreshShouldFire(60, latched: true), isTrue); // %75
      expect(juzzioRefreshShouldFire(60, latched: false), isFalse);
      expect(juzzioRefreshShouldFire(40, latched: true), isFalse); // %50 → iptal
      expect(juzzioRefreshShouldFire(80, latched: false), isTrue);
    });
    test('el ~%20 büyük', () {
      expect(kJuzzioHandScaleBoost, greaterThanOrEqualTo(1.2));
      final g = JuzzioRefreshGeometry(screenWidth: 390, topInset: 47);
      expect(g.scale, greaterThanOrEqualTo(1.0));
    });
    test('tepede başlamayan ama tepeye varan çekiş de kurulur', () {
      expect(_src('lib/widgets/juzzio_cloth_refresh.dart').contains('if (!_armedDrag && n.dragDetails != null && n.overscroll < 0'), isTrue);
    });
  });

  test('gönderme uçuşu: sarı alt çizgi yok (saydam Material + alt çizgisiz metin)', () {
    final s = _src('lib/widgets/motion/juzzio_send_fx.dart');
    final flight = s.substring(s.indexOf('class _FlightViewState'), s.indexOf('class JuzzioBubbleEntrance'));
    expect(flight.contains('type: MaterialType.transparency'), isTrue);
    expect(flight.contains('decoration: TextDecoration.none'), isTrue);
    expect(flight.contains('_lastTo'), isTrue);
  });

  group('Doğum günü: 3B ve daha uzun', () {
    test('7 sn, iki patlama', () {
      expect(kJuzzioBirthdayDuration, const Duration(seconds: 7));
      expect(kJuzzioBirthdayPops.length, 2);
      expect(kJuzzioBirthdayPops.last, lessThan(kJuzzioBirthdayDuration.inMilliseconds / 1000 - 2));
    });
    test('3B konfeti ışığa göre aydınlanır/kararır', () {
      expect(juzzioConfettiShade(0, 0), closeTo(1.0, 1e-9));
      expect(juzzioConfettiShade(math.pi / 2, 0), closeTo(0.35, 1e-9));
      expect(juzzioConfettiShade(0.6, 0.4), inInclusiveRange(0.35, 1.0));
    });
    test('perspektif dönüşüm kullanılır', () {
      final s = _src('lib/widgets/motion/juzzio_birthday_fx.dart');
      expect(s.contains('setEntry(3, 2, 1 / _focal)'), isTrue);
      expect(s.contains('MatrixUtils.transformPoint(m,'), isTrue);
    });
  });

  group('Tanıtım videosu', () {
    test('ilk yükleme ve bu güncellemede herkese bir kez, sonra yalnız yeni hesaplara', () {
      final now = DateTime(2026, 11, 10, 12);
      expect(juzzioShouldShowIntro(deviceSeen: false, accountSeen: true, now: now), isTrue);
      expect(juzzioShouldShowIntro(deviceSeen: true, accountSeen: false, now: now), isFalse);
      expect(juzzioShouldShowIntro(deviceSeen: true, accountSeen: false, accountCreatedAt: now.subtract(const Duration(hours: 5)), now: now), isTrue);
      expect(juzzioShouldShowIntro(deviceSeen: true, accountSeen: true, accountCreatedAt: now, now: now), isFalse);
      expect(juzzioShouldShowIntro(deviceSeen: true, accountSeen: false, accountCreatedAt: now.subtract(const Duration(days: 30)), now: now), isFalse);
    });
    test('dile göre video ve varlıklar mevcut', () {
      expect(juzzioIntroAssetFor('tr'), kJuzzioIntroAssetTr);
      expect(juzzioIntroAssetFor('en'), kJuzzioIntroAssetEn);
      expect(juzzioIntroAssetFor('de'), kJuzzioIntroAssetEn);
      for (final a in [kJuzzioIntroAssetTr, kJuzzioIntroAssetEn]) {
        expect(File(a).existsSync(), isTrue, reason: a);
        expect(File(a).lengthSync(), lessThan(3 * 1024 * 1024));
        expect(_src('pubspec.yaml').contains(a), isTrue);
      }
    });
    test('ilk girişte ve Yapımcı sayfasında', () {
      expect(_src('lib/screens/chat_screen.dart').contains('await juzzioMaybeShowIntro(context)'), isTrue);
      expect(_src('lib/screens/settings_suite_screens.dart').contains('JuzzioCreatorReelButton(intro: true)'), isTrue);
    });
  });

  test('v1.2.7 sürüm notu en üstte', () {
    final n = kJuzzioBundledReleaseNotes.first;
    expect(n.versionName, '1.2.7');
    expect(n.versionCode, 127);
  });
}
