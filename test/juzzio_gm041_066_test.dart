// GM-041 … GM-066 (Engin'in 22.11.2026 23:19 listesi) — kaynak denetimleri
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/juzzio_brand_names.dart';
import 'package:juzzio/screens/settings_suite_screens.dart' show juzzioNormalizeBlockUsername;
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
}
