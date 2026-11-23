// GM-041 … GM-066 (Engin'in 22.11.2026 23:19 listesi) — kaynak denetimleri
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/settings/juzzio_settings_v21.dart' show showJuzzioMfaCodeDialog;
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/juzzio_brand_names.dart';
import 'package:juzzio/screens/settings_suite_screens.dart' show juzzioNormalizeBlockUsername;
import 'package:juzzio/services/juzzio_security_center.dart';
import 'package:juzzio/services/juzzio_features_service.dart' show juzzioDeviceModelLabel;
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_weather_hd.dart';

void main() {
  final settings = File('lib/screens/settings_suite_screens.dart').readAsStringSync();

  test('GM-041: Android kesintisiz bildirim izni düğmesi yok', () {
    expect(settings.contains('Android Pil Kısıtlamasını Kaldır (Kesintisiz Bildirim İzni)'), isFalse);
    expect(settings.contains('requestAndroidBatteryExemption'), isFalse);
  });

  test('GM-042: Hakkında resmî; yapımcı bilgisi ve e-posta yok, @trawaveofficial var', () {
    final i = settings.indexOf('class JuzzioDeveloperPage');
    final page = settings.substring(i, settings.indexOf('// 11. OTA', i));
    expect(page.contains('assets/creator/engin.jpg'), isFalse);
    expect(page.contains('mailto:'), isFalse);
    expect(page.contains('JuzzioCreatorReelButton()'), isFalse);
    expect(settings.contains("kTrawaveInstagramUrl = 'https://instagram.com/trawaveofficial'"), isTrue);
    expect(settings.contains("kTrawaveTelegramUrl = 'https://t.me/trawaveofficial'"), isTrue);
  });

  test('GM-045: dil sayısı gerçek listeden (224)', () {
    expect(kJuzzioSupportedLanguages.length, 224);
    final src = File('lib/core/app_theme_and_locale.dart').readAsStringSync();
    expect(src.contains("'Uygulama Dili (224 dil)'"), isTrue);
    expect(RegExp(r"'[^'\n]*139\+[^'\n]*'").hasMatch(src), isFalse);
  });

  test('GM-056: WhatsApp / Trawave kişileri düğmesi yok', () {
    expect(settings.contains("loc('WhatsApp / Trawave Kişileri'"), isFalse);
  });

  test('GM-037: hava önizleme seçicisi arayüzde yok; hata ayıklama yalnız dosyadan', () {
    expect(settings.contains('JuzzioWeatherDebugPreview'), isFalse);
    JuzzioWeatherDebugFile.apply('rain:night');
    expect(JuzzioWeatherService.debugPreview.value?.$1, JuzzioWeatherKind.rain);
    expect(JuzzioWeatherService.debugPreview.value?.$2, isTrue);
    JuzzioWeatherDebugFile.apply('');
    expect(JuzzioWeatherService.debugPreview.value, isNull);
  });

  test('GM-037: güneşli gündüz yalnız gündoğumu; açık temada açık varyant', () {
    final dark = juzzioHdWeatherLayers(JuzzioWeatherKind.clear, night: false, dark: true, moonIndex: 0);
    final light = juzzioHdWeatherLayers(JuzzioWeatherKind.clear, night: false, dark: false, moonIndex: 0);
    expect(dark.single.asset, kHdSunRise);
    expect(light.single.asset, kHdSunRiseLight);
  });

  test('GM-054: engellenecek ad temizlenir; yalnız var olan kullanıcı (sunucu araması) engellenir', () {
    expect(juzzioNormalizeBlockUsername('  @@Ali.Veli_1 '), 'Ali.Veli_1');
    expect(juzzioNormalizeBlockUsername('@ x y'), 'xy');
    expect(settings.contains('searchUsersByUsername(name)'), isTrue);
  });

  test('GM-055: marka adları ve taklitleri kullanıcı adı olamaz', () {
    for (final n in ['apple', 'WhatsApp', '@tinder', 'apple_official', 'official.whatsapp', 'trawave', 'instagram.tr', 'resmi_google']) {
      expect(juzzioUsernameIsBrand(n), isTrue, reason: n);
    }
    for (final n in ['engin', 'pineapple', 'applepie', 'tugkancr', 'ali.veli']) {
      expect(juzzioUsernameIsBrand(n), isFalse, reason: n);
    }
    final sql = File('supabase/juzzio_database.sql').readAsStringSync();
    expect(sql.contains("RAISE EXCEPTION 'username_brand'"), isTrue);
  });

  testWidgets('GM-060: "Kodu yapıştır" kodu bir kez gönderir, alttaki sayfa kapanmaz (gri ekran yok)', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': 'kod: 123 456'};
      return null;
    });
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await showJuzzioMfaCodeDialog(ctx),
              child: const Text('GIRIS_SAYFASI'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('GIRIS_SAYFASI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.content_paste_rounded));
    await tester.pumpAndSettle();
    expect(result, '123456');
    expect(find.text('GIRIS_SAYFASI'), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('GM-050: cihaz listesi model + konum', () {
    test('Xiaomi 15 Ultra | Türkiye / Aydın biçimi', () {
      final d = JuzzioDeviceEntry.fromMap({
        'device': 'a1b2c3', 'platform': 'android', 'current': true,
        'model': 'Xiaomi 15 Ultra', 'country': 'tr', 'place': 'Türkiye / Aydın',
      });
      expect(d.title(), 'Xiaomi 15 Ultra | Türkiye / Aydın');
      expect(d.title().contains('a1b2c3'), isFalse); // kimlik soneki gösterilmez
    });
    test('şehir yoksa ülke kodundan ad, model yoksa platform', () {
      final d = JuzzioDeviceEntry.fromMap({'device': 'zz', 'platform': 'windows', 'country': 'TR'});
      expect(d.title(), 'Windows PC | Türkiye');
      final e = JuzzioDeviceEntry.fromMap({'device': 'zz', 'platform': 'android'});
      expect(e.title(), 'Android');
    });
    test('Windows model etiketi bilgisayar adını göndermez', () {
      expect(juzzioDeviceModelLabel('', os: '"Windows 10 Pro" 10.0 (Build 26100)'), 'Windows 11 PC');
      expect(juzzioDeviceModelLabel('Xiaomi 15 Ultra'), 'Xiaomi 15 Ultra');
    });
    test('platform artık sabit "android" değil; SQL 10.59 dosyada', () {
      final f = File('lib/services/juzzio_features_service.dart').readAsStringSync();
      expect(f.contains("'p_platform': 'android'"), isFalse);
      final sql = File('supabase/juzzio_database.sql').readAsStringSync();
      expect(sql.contains('10.59 (v2.2.0, GM-050)'), isTrue);
      expect(sql.contains("'place', COALESCE(d.last_place, '')"), isTrue);
      final kt = File('android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt').readAsStringSync();
      expect(kt.contains('"reverseGeocode"'), isTrue);
      expect(kt.contains('ro.product.marketname'), isTrue);
    });
  });

  group('GM-064: Engin 23.11 videosu — tema düzeltmeleri', () {
    test('bulut bandı Gelen kutusu satırına (≈ +0.50W) ve logoya binmez', () {
      for (final k in [JuzzioWeatherKind.clouds, JuzzioWeatherKind.rain, JuzzioWeatherKind.drizzle, JuzzioWeatherKind.snow, JuzzioWeatherKind.thunder]) {
        for (final night in [true, false]) {
          for (final l in juzzioHdWeatherLayers(k, night: night, dark: true, moonIndex: 3)) {
            if (l.fall) continue;
            final h = l.width / (kJuzzioHdAspect[l.asset] ?? 1);
            expect(l.anchored, isTrue, reason: '$k ${l.asset}');
            expect(l.top + h, lessThanOrEqualTo(0.42), reason: '$k ${l.asset} alt kenar');
            expect(l.top, greaterThanOrEqualTo(-0.20), reason: '$k ${l.asset} üst kenar (logo)');
          }
        }
      }
      expect(juzzioHdPrecipBottom(100, 400), 100 + 400 * 0.42);
    });
    test('hava sahnesi yalnız arama kutusu görünürken (başka sekme/sayfada hiçbir katman yok)', () {
      final src = File('lib/widgets/juzzio_weather_hd.dart').readAsStringSync();
      expect(src.contains('if (!anchorKnown) return const SizedBox.shrink();'), isTrue);
    });
    test('arama kutusu koyu/süt beyazı buzlu cam (bulut ardında kaybolmaz)', () {
      final src = File('lib/widgets/juzzio_space_kit.dart').readAsStringSync();
      expect(src.contains('Color(0xC2232A35)'), isTrue);
      expect(src.contains('Color(0xE6FFFFFF)'), isTrue);
    });
    test('Türk bayrağı Engin\'in gönderdiği şeffaf görsel; Halloween referans sahnesi tek bant', () {
      final src = File('lib/widgets/juzzio_special_theme_layer.dart').readAsStringSync();
      expect(src.contains('1422 / 639'), isTrue);
      expect(src.contains('gm064-halloween-band'), isTrue);
      expect(File('assets/special/halloween/halloween_band.webp').existsSync(), isTrue);
    });
    test('masaüstü hilal referanstaki gibi haki ince kenar — limon/yeşil parıltı yok', () {
      final src = File('lib/widgets/juzzio_desktop_shell.dart').readAsStringSync();
      expect(src.contains('JuzzioCrescentPainter(rim: const Color(0xFFC4C79B), glow: const Color(0xFF8E9170))'), isTrue);
      expect(src.contains('JuzzioCrescentPainter(rim: const Color(0xFFE4F0A0), glow: accent)'), isFalse);
    });
  });
}
