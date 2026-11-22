// GM-028 … GM-034 (v2.2.0): masaüstü gece/gündüz tasarımı, Türk bayrağı ve Halloween özel temaları,
// HD hava görselleri ve yeni Yönetici Paneli "Genel Bakış".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/admin_overview_v22.dart';
import 'package:juzzio/services/juzzio_features_service.dart';
import 'package:juzzio/services/juzzio_special_themes.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_desktop_shell.dart';
import 'package:juzzio/widgets/juzzio_special_theme_layer.dart';
import 'package:juzzio/widgets/juzzio_weather_hd.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('GM-028: masaüstü gece/gündüz tasarımı', () {
    test('sağ panel sahnesi ve yörüngeli simge; paneller yüzen cam', () {
      final s = _src('lib/widgets/juzzio_desktop_shell.dart');
      expect(s.contains('JuzzioDesktopSceneBackdrop(dark: dark, accent: glow)'), isTrue);
      expect(s.contains('JuzzioOrbitAppIcon('), isTrue);
      expect(s.contains('radius: 22'), isTrue);
    });
    for (final dark in [true, false]) {
      testWidgets('placeholder çizilir (dark=$dark)', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Stack(children: [
                Positioned.fill(child: JuzzioDesktopSceneBackdrop(dark: dark, accent: const Color(0xFFC6F135))),
                Center(child: JuzzioOrbitAppIcon(dark: dark, accent: const Color(0xFFC6F135))),
              ]),
            ),
          ),
        ));
        expect(find.byKey(const ValueKey('gm028-orbit-icon')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('GM-029: Türk bayrağı teması', () {
    test('yalnız Türkiye: sunucu ülkesi öncelikli, yoksa bölge TR + UTC+3', () {
      expect(juzzioIsTurkeyUser(serverCountry: 'TR', localeName: 'en_US', utcOffset: const Duration(hours: -5)), isTrue);
      expect(juzzioIsTurkeyUser(serverCountry: 'US', localeName: 'tr_TR', utcOffset: const Duration(hours: 3)), isFalse);
      expect(juzzioIsTurkeyUser(localeName: 'tr_TR', utcOffset: const Duration(hours: 3)), isTrue);
      expect(juzzioIsTurkeyUser(localeName: 'tr_TR', utcOffset: const Duration(hours: 1)), isFalse);
      expect(juzzioIsTurkeyUser(localeName: 'tr-TR.UTF-8', utcOffset: const Duration(hours: 3)), isTrue);
      expect(juzzioIsTurkeyUser(localeName: 'en_US', utcOffset: const Duration(hours: 3)), isFalse);
    });
    test('özel tema seçimi: bayrak Türkiye\'de öncelikli; kapalıysa yok', () {
      expect(juzzioResolveSpecialTheme(turkeyOn: true, halloweenOn: true, turkeyUser: true), JuzzioSpecialTheme.turkey);
      expect(juzzioResolveSpecialTheme(turkeyOn: true, halloweenOn: true, turkeyUser: false), JuzzioSpecialTheme.halloween);
      expect(juzzioResolveSpecialTheme(turkeyOn: true, halloweenOn: false, turkeyUser: false), JuzzioSpecialTheme.none);
      expect(juzzioResolveSpecialTheme(turkeyOn: false, halloweenOn: false, turkeyUser: true), JuzzioSpecialTheme.none);
    });
    test('bayrak resmî oranlar', () {
      const g = JuzzioTurkFlagGeometry(100);
      expect(g.length, 150);
      expect(g.outerRadius, 25);
      expect(g.innerRadius, 20);
      expect(g.innerCenter.dx - g.outerCenter.dx, closeTo(6.25, 0.001));
      expect(g.starRadius, 12.5);
    });
    test('yönetici ayarı: varsayılan kapalı; yapılandırmadan okunur', () {
      expect(const JuzzioAppConfig().specialThemeTurkey, isFalse);
      expect(const JuzzioAppConfig().specialThemeHalloween, isFalse);
      final c = JuzzioAppConfig.fromMap({'special_theme_turkey': true, 'special_theme_halloween': true});
      expect(c.specialThemeTurkey && c.specialThemeHalloween, isTrue);
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql.contains("'special_theme_turkey', 'special_theme_halloween') THEN"), isTrue);
      expect(sql.contains("('special_theme_turkey', 'false'::jsonb)"), isTrue);
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.juzzio_my_country()'), isTrue);
    });
    for (final dark in [true, false]) {
      testWidgets('bayrak katmanı çizilir (dark=$dark)', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: SizedBox(
            width: 400,
            height: 800,
            child: JuzzioSpecialThemeLayer(
              theme: JuzzioSpecialTheme.turkey,
              dark: dark,
              loop: const AlwaysStoppedAnimation<double>(0.3),
              accent: const Color(0xFFC6F135),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('GM-030 / GM-031: HD hava ve Halloween görselleri', () {
    test('tüm görseller pakette ve pubspec\'te', () {
      for (final a in [...kJuzzioHdWeatherAssets, ...kJuzzioHalloweenAssets]) {
        expect(File(a).existsSync(), isTrue, reason: a);
      }
      final pub = _src('pubspec.yaml');
      expect(pub.contains('- assets/weather_hd/'), isTrue);
      expect(pub.contains('- assets/special/halloween/'), isTrue);
    });
    test('her hava türü ve gece/gündüz için katman; ay evresi doğru görsel', () {
      for (final k in JuzzioWeatherKind.values) {
        for (final night in [true, false]) {
          expect(juzzioHdWeatherLayers(k, night: night, dark: true, moonIndex: 4), isNotEmpty, reason: '$k $night');
        }
      }
      final clearNight = juzzioHdWeatherLayers(JuzzioWeatherKind.clear, night: true, dark: true, moonIndex: 2);
      expect(clearNight.first.asset, kJuzzioHdMoonAssets[2]);
      expect(juzzioHdWeatherLayers(JuzzioWeatherKind.clear, night: false, dark: true, moonIndex: 0).first.asset, kHdSunRise);
      expect(juzzioHdWeatherLayers(JuzzioWeatherKind.rain, night: false, dark: true, moonIndex: 0).any((l) => l.fall), isTrue);
      expect(juzzioHdWeatherLayers(JuzzioWeatherKind.snow, night: false, dark: true, moonIndex: 0).any((l) => l.asset == kHdSnowLight), isTrue);
    });
    test('şimşek kısa flaşlar (100–160 ms aralığı, 1100 ms animasyonda)', () {
      expect(juzzioBoltFlash(0), 0);
      expect(juzzioBoltFlash(0.05), 1);
      expect(juzzioBoltFlash(0.27), greaterThan(0.5));
      expect(juzzioBoltFlash(0.9), lessThan(0.1));
      // ilk flaş 0.13 × 1100 ≈ 143 ms
      expect(0.13 * 1100, inInclusiveRange(100, 160));
    });
    test('özel tema etkinken hava katmanı çizilmez', () {
      final a = _src('lib/widgets/juzzio_weather_ambience.dart');
      expect(a.contains('if (special != JuzzioSpecialTheme.none) {'), isTrue);
      expect(a.contains('JuzzioSpecialThemeLayer('), isTrue);
    });
  });

  group('GM-034: Yönetici Paneli Genel Bakış', () {
    test('yüzde, sayı ve dönem toplamları', () {
      expect(juzzioPercentChange(112, 100), closeTo(12, 0.001));
      expect(juzzioPercentChange(5, 0), isNull);
      expect(juzzioFormatPercent(12.44), '+12,4%');
      expect(juzzioFormatPercent(-3.0, lang: 'en'), '−3.0%');
      expect(juzzioGroupedNumber(281756), '281.756');
      expect(juzzioGroupedNumber(8421, lang: 'en'), '8,421');
      final series = [for (var i = 1; i <= 6; i++) {'messages': i}];
      expect(juzzioSeriesPeriodSums(series, 'messages', 3), (15, 6));
      expect(juzzioShortMonth(11, 'tr'), 'Kas');
    });
    test('üst sekmeler referanstaki sırada', () {
      final labels = juzzioAdminTopTabs().map((t) => t.label).toList();
      expect(labels.length, 7);
      expect(labels.first, isNotEmpty);
      expect(juzzioAdminTopTabs().first.section, isNull);
    });
    test('panel bölümleri mevcut', () {
      final a = _src('lib/screens/admin_panel_screen.dart');
      for (final k in [
        'gm034-header',
        'gm034-role-badge',
        'gm034-top-tabs',
        'gm034-range',
        'gm034-activity-chart',
        'gm034-recent',
        'gm034-attention',
        'gm034-health',
        'gm034-special-themes',
      ]) {
        expect(a.contains("ValueKey('$k')"), isTrue, reason: k);
      }
      expect(a.contains("'Admin Panel'"), isTrue);
      expect(_src('supabase/juzzio_database.sql').contains('FUNCTION public.admin_activity_series(p_token TEXT, p_days INTEGER DEFAULT 30)'), isTrue);
    });
    testWidgets('sayaç kartı ve grafik çizilir', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const SizedBox(
              width: 200,
              height: 150,
              child: JuzzioAdminStatCard(color: Colors.green, icon: Icons.people, value: '8.421', label: 'Toplam Kullanıcı', change: 12.4),
            ),
            const SizedBox(
              width: 400,
              child: JuzzioAdminActivityChart(values: [3, 5, 4, 8, 6, 9], labels: ['1', '2', '3', '4', '5', '6'], tooltip: 'x'),
            ),
          ]),
        ),
      ));
      expect(find.text('8.421'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
