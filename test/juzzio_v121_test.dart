// JUZZIO v1.2.1 birim testleri — yenileme eli, onay formu, girdi doğrulama, hava durumu teması
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_input_guard.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';
import 'package:juzzio/widgets/juzzio_consent.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('Kompakt 3D yenileme eli', () {
    test('el yolu en fazla 80 dp, monoton', () {
      var prev = -1.0;
      for (var p = -20.0; p <= 400; p += 5) {
        final t = juzzioRefreshTravel(p);
        expect(t, greaterThanOrEqualTo(prev));
        expect(t, lessThanOrEqualTo(80.0));
        prev = t;
      }
      expect(juzzioRefreshTravel(1000), 80.0);
      expect(juzzioRefreshTravel(-50), 0.0);
      expect(kJuzzioRefreshMaxTravel, 80.0);
    });

    test('eşik yalnız 80 dp\'de kurulur; yumruk son %30\'da kapanır', () {
      expect(juzzioRefreshArmed(60), isFalse);
      expect(juzzioRefreshArmed(80), isTrue);
      expect(juzzioRefreshCurl(0), 0.0);
      expect(juzzioRefreshCurl(50), 0.0);
      expect(juzzioRefreshCurl(80), closeTo(1.0, 1e-9));
      expect(juzzioRefreshCurl(70), inExclusiveRange(0.0, 1.0));
    });

    test('200 ms sönümlü (0.85) geri dönüş', () {
      expect(kJuzzioSnapBackDuration, const Duration(milliseconds: 200));
      expect(kJuzzioSnapDamping, 0.85);
      expect(juzzioSnapBack(0), 0.0);
      expect(juzzioSnapBack(1), 1.0);
      expect(juzzioSnapBack(0.5), inInclusiveRange(0.5, 1.1));
    });

    test('geometri: çentik boşluğu / gömülü mod', () {
      final g = JuzzioRefreshGeometry(screenWidth: 393, topInset: 59, contentTop: 59);
      expect(g.embedded, isFalse);
      expect(g.originY, lessThanOrEqualTo(0));
      final e = JuzzioRefreshGeometry(screenWidth: 393, topInset: 59, contentTop: 160);
      expect(e.embedded, isTrue);
      expect(e.originY, 0);
      expect(g.scale, inInclusiveRange(0.85, 1.15));
    });

    test('kaynak sözleşmesi: tek tetik kilidi, reduce motion, warm-up, dispose, eski çizim yok', () {
      final s = _src('lib/widgets/juzzio_cloth_refresh.dart');
      expect(s.contains('_inFlight'), isTrue);
      expect(s.contains('disableAnimations'), isTrue);
      expect(s.contains('warmUp()'), isTrue);
      expect(s.contains('_snap.dispose()'), isTrue);
      expect(s.contains('_settle.dispose()'), isTrue);
      expect(s.contains('_ClothScenePainter'), isFalse);
      expect(s.contains('rootBundle'), isFalse);
    });
  });

  group('Kayıt / giriş onay formu', () {
    // v1.2.3: dört kutu ikiye indirildi — ayrıntılı testler juzzio_v123_test.dart içinde
    test('zorunlu kutu olmadan geçilmez; kampanya isteğe bağlı', () {
      const empty = JuzzioConsentState();
      expect(empty.requiredAccepted, isFalse);
      final ok = empty.copyWith(termsNotice: true);
      expect(ok.requiredAccepted, isTrue);
      expect(ok.marketing, isFalse);
      final rpc = ok.copyWith(marketing: true).toRpc();
      expect(rpc['p_version'], kJuzzioConsentVersion);
      expect(rpc['p_age'], isTrue);
      expect(rpc['p_marketing'], isTrue);
    });

    test('kayıt ve girişte zorunlu; sunucu kaydı', () {
      final m = _src('lib/main.dart');
      expect(m.contains('JuzzioConsentPanel('), isTrue);
      expect(m.contains('requiredAccepted'), isTrue);
      expect(m.contains('JuzzioConsentService.instance.record('), isTrue);
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql.contains('record_juzzio_consent'), isTrue);
      expect(sql.contains('juzzio_app_consents'), isTrue);
    });
  });

  group('Girdi doğrulama', () {
    test('kontrol ve yön değiştiren karakterler temizlenir, uzunluk sınırlanır', () {
      expect(juzzioCleanText('a\u0000b‮c​d'), 'abcd');
      expect(juzzioCleanText('satır1\nsatır2'), 'satır1\nsatır2');
      expect(juzzioCleanText('x' * 5000).length, 4000);
      expect(juzzioCleanDisplayName('Ali\nVeli'), 'Ali Veli');
      // emoji ZWJ korunur
      expect(juzzioCleanText('👩‍💻'), '👩‍💻');
    });

    test('arama terimi filtre sözdizimine sızamaz', () {
      expect(juzzioSafeSearchTerm('@fikret39'), 'fikret39');
      expect(juzzioSafeSearchTerm('a,b).or(id.eq.1'), 'aborideq1');
      expect(juzzioSafeSearchTerm('%*\\"'), '');
      expect(juzzioSafeSearchTerm('Çağrı_Öz-1'), 'Çağrı_Öz-1');
    });

    test('yalnız http(s) bağlantıları', () {
      expect(juzzioSafeUrl('javascript:alert(1)'), isNull);
      expect(juzzioSafeUrl('data:text/html,x'), isNull);
      expect(juzzioSafeUrl('https://juzzio.app/a'), 'https://juzzio.app/a');
      expect(juzzioSafeUrl('juzzio.app'), 'https://juzzio.app');
    });

    test('sunucu tarafı sınırlar ve doğrulama tetikleyicileri', () {
      final sql = _src('supabase/juzzio_database.sql');
      for (final k in ['juzzio_client_rate_guard', 'juzzio_rate_hit', 'juzzio_clean_text', 'juzzio_url_ok', 'trg_01_juzzio_validate_message']) {
        expect(sql.contains(k), isTrue, reason: k);
      }
    });
  });

  group('Hava durumu teması', () {
    test('WMO kodları doğru türe eşlenir', () {
      expect(juzzioWeatherKindFromWmo(0), JuzzioWeatherKind.clear);
      expect(juzzioWeatherKindFromWmo(3), JuzzioWeatherKind.clouds);
      expect(juzzioWeatherKindFromWmo(45), JuzzioWeatherKind.fog);
      expect(juzzioWeatherKindFromWmo(53), JuzzioWeatherKind.drizzle);
      expect(juzzioWeatherKindFromWmo(63), JuzzioWeatherKind.rain);
      expect(juzzioWeatherKindFromWmo(81), JuzzioWeatherKind.rain);
      expect(juzzioWeatherKindFromWmo(75), JuzzioWeatherKind.snow);
      expect(juzzioWeatherKindFromWmo(95), JuzzioWeatherKind.thunder);
    });

    test('konum ~10 km yuvarlanır, yalnız Open-Meteo', () {
      expect(juzzioRoundCoord(41.0369), 41.0);
      expect(juzzioRoundCoord(28.9857), 29.0);
      final u = juzzioWeatherUri(41.0369, 28.9857);
      expect(u.host, 'api.open-meteo.com');
      expect(u.queryParameters['latitude'], '41.0');
      expect(u.queryParameters['longitude'], '29.0');
    });

    test('Görünüm\'de anahtar, varsayılan açık', () {
      final s = _src('lib/screens/settings_suite_screens.dart');
      expect(s.contains('weatherThemeEnabled'), isTrue);
      final a = _src('lib/core/app_theme_and_locale.dart');
      expect(a.contains("raw['weatherTheme'] != false"), isTrue);
      expect(_src('lib/main.dart').contains('JuzzioWeatherAmbience()'), isTrue);
    });
  });

  group('Video kaydı düzeltmeleri', () {
    test('arama geçmişinde tek yön simgesi; profil düğmeleri kısa', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains('Icons.call_received_rounded'), isTrue);
      final p = _src('lib/screens/profile/juzzio_profile_view.dart');
      expect(p.contains("_l('Düzenle'"), isTrue);
      expect(p.contains("_l('Paylaş'"), isTrue);
    });
  });

  test('Sürüm notu 1.2.1 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.1');
    expect(n.versionName, '1.2.1');
    expect(n.versionCode, 121);
    expect(n.sections.keys, containsAll(['tr', 'en']));
    expect(n.sections['tr']!.security.length, greaterThanOrEqualTo(4));
  });
}
