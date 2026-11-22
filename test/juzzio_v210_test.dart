// Juzzio 2.1 — yeniden tasarım (Neon Lime) testleri
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/config.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/screens/profile/juzzio_profile_qr_page.dart';
import 'package:juzzio/services/juzzio_discover_service.dart';
import 'package:juzzio/widgets/juzzio_auth_hero.dart';
import 'package:juzzio/widgets/juzzio_brand.dart';
import 'package:juzzio/widgets/juzzio_neon_kit.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_sky21.dart';
import 'package:juzzio/services/juzzio_mfa_service.dart';
import 'package:juzzio/services/juzzio_data_export.dart';
import 'package:juzzio/services/social_service.dart' show juzzioStorageCategory;
import 'package:juzzio/widgets/juzzio_a11y_filter.dart';
import 'package:juzzio/screens/admin_modules_v21.dart';
import 'package:juzzio/widgets/juzzio_auto_download.dart';
import 'package:juzzio/screens/admin_legal_report.dart';
import 'package:juzzio/services/juzzio_legal_package.dart' show juzzioLegalSummary, juzzioVerificationReadme;
import 'package:juzzio/core/app_theme_and_locale.dart' show JuzzioAppController;

String _src(String p) => File(p).readAsStringSync();

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('Faz 1 — güvenlik', () {
    test('SQL: istemci rollerinden TRUNCATE ve anon yazma geri alınır', () {
      final s = _src('supabase/juzzio_database.sql');
      expect(s.contains('REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;'), isTrue);
      expect(s.contains('REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;'), isTrue);
      expect(s.contains('FUNCTION public.admin_security_privileges(p_token TEXT)'), isTrue);
    });
    test('CI kapısı istemci rolüne TRUNCATE verilmesini engeller', () {
      expect(_src('scripts/ci_guards.py').contains('def check_sql_grants'), isTrue);
    });
  });

  group('Faz 2 — marka ve bileşen kiti', () {
    test('Neon Lime vurgu rengi tasarımdan ölçülen değer', () {
      expect(JuzzioBrandColors.lime, const Color(0xFFC6F135));
      expect(_src('lib/core/theme/juzzio_aurora.dart').contains('0xFFD7F36B'), isFalse);
    });
    test('resmî logo: tek kaynaktan vektör + tüm platform ikonları', () {
      expect(File('assets/brand/juzzio_logo_source.png').existsSync(), isTrue);
      expect(_src('tools/brand_logo.py').contains('juzzio_logo_source.png'), isTrue);
      expect(JuzzioLogoGeometry.logoLime, const Color(0xFFBAFA08));
      final b = JuzzioLogoGeometry.glyph(100).getBounds();
      expect(b.left, greaterThanOrEqualTo(-1));
      expect(b.right, lessThanOrEqualTo(101));
      expect(b.width, greaterThan(50));
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(File('android/app/src/main/res/drawable-$d/ic_stat_juzzio.png').existsSync(), isTrue);
      }
      expect(_src('android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt').contains('R.drawable.ic_stat_juzzio'), isTrue);
      expect(File('windows/runner/resources/app_icon.ico').existsSync(), isTrue);
      expect(_src('tools/brand/juzzio_logo.svg').contains('#BAFA08'), isTrue);
    });
    test('başlatıcı ikonları üretilmiş', () {
      for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(File('android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png').existsSync(), isTrue);
      }
    });
    testWidgets('logo, kelime markası ve başlık hatasız çizilir', (tester) async {
      await tester.pumpWidget(_host(const Column(mainAxisSize: MainAxisSize.min, children: [
        JuzzioLogoGlyph(size: 40),
        JuzzioLogoTile(size: 48),
        JuzzioWordmark(size: 22),
        JuzzioScreenHeader(title: 'Ayarlar', subtitle: 'Uygulama tercihlerini yönet'),
      ])));
      expect(find.text('Juzzio'), findsWidgets);
      expect(find.text('Ayarlar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('hap sekme ve çipler seçimi bildirir', (tester) async {
      var tab = 0;
      var chip = 0;
      await tester.pumpWidget(_host(Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 360,
          child: JuzzioNeonTabs(
            tabs: const [JuzzioNeonTab('Gelen İstekler', count: 12), JuzzioNeonTab('Gönderilen', count: 4)],
            selected: tab,
            onChanged: (i) => tab = i,
          ),
        ),
        JuzzioNeonChips(labels: const ['Tümü', 'Cevapsız', 'Gelen', 'Giden'], selected: chip, onChanged: (i) => chip = i),
      ])));
      await tester.tap(find.text('Gönderilen'));
      await tester.tap(find.text('Gelen'));
      expect(tab, 1);
      expect(chip, 2);
      expect(find.text('12'), findsOneWidget);
    });
    testWidgets('ayar satırı ve düğmeler dokunuşu iletir', (tester) async {
      var taps = 0;
      var on = false;
      await tester.pumpWidget(_host(SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          JuzzioNeonGroup(children: [
            JuzzioNeonRow(icon: Icons.person_outline, title: 'Hesap ve Profil', value: 'Koyu Tema', onTap: () => taps++),
            JuzzioNeonRow.toggle(icon: Icons.translate, title: 'Otomatik Çeviri', value: on, onChanged: (v) => on = v),
          ]),
          JuzzioLimeButton(label: 'Kayıt Ol', icon: Icons.arrow_forward, onPressed: () => taps++),
          JuzzioLimeButton(label: 'Çıkış Yap', style: JuzzioLimeButtonStyle.danger, onPressed: () => taps++),
        ]),
      )));
      await tester.tap(find.text('Hesap ve Profil'));
      await tester.tap(find.text('Kayıt Ol'));
      await tester.tap(find.text('Çıkış Yap'));
      await tester.tap(find.byType(Switch));
      expect(taps, 3);
      expect(on, isTrue);
    });
    test('alt menüde seçili sekme göstergesi ve başlıkta logo', () {
      final k = _src('lib/widgets/juzzio_space_kit.dart');
      expect(k.contains('width: active ? 18 : 0'), isTrue);
      expect(k.contains('JuzzioLogoGlyph(size: size * 1.05)'), isTrue);
    });
  });

  group('Faz 3 — giriş akışı', () {
    test('kayıt/giriş: üst sahne, limon düğme, beni hatırla, şifremi unuttum, geçiş bağlantısı', () {
      final m = _src('lib/main.dart');
      // v2.1.1: tasarım şablonu birebir — limon sahne, "Juzzio'ya Katıl" / "Tekrar Hoş Geldin!" + vurgu çizgisi
      // GM-002 (21.11.2026): arayüz widgets/auth/ altına taşındı (iş mantığı main.dart'ta kaldı, K3)
      final v = _src('lib/widgets/auth/juzzio_auth_view.dart');
      final kit = _src('lib/widgets/auth/juzzio_auth_kit.dart');
      expect(m.contains('JuzzioAuthView('), isTrue);
      expect(v.contains("t('Katıl', 'Juzzio', 'Juzzio')"), isTrue);
      expect(v.contains("t('Geldin!', 'back!', 'zurück!')"), isTrue);
      expect(v.contains('JuzzioAuthTitle('), isTrue);
      expect(v.contains("static const providers = ['google', 'apple', 'github'];"), isTrue);
      expect(m.contains('Future<void> _forgotPassword()'), isTrue);
      expect(m.contains('resetPasswordForEmail(email)'), isTrue);
      expect(m.contains('setRememberedLoginId(_rememberMe'), isTrue);
      expect(v.contains('JuzzioPrimaryButton('), isTrue);
      expect(kit.contains('JuzzioColorTokens.accent'), isTrue);
    });
    test('şifre hiçbir zaman hatırlanmaz; yalnız kimlik', () {
      final a = _src('lib/core/app_theme_and_locale.dart');
      expect(a.contains("'rememberedLoginId': _rememberedLoginId"), isTrue);
      expect(a.contains('rememberedPassword'), isFalse);
    });
    test('sosyal giriş varsayılan kapalı, dönüş adresi bildirimde tanımlı', () {
      expect(JuzzioConfig.oauthProviders, isEmpty);
      expect(_src('android/app/src/main/AndroidManifest.xml').contains('android:host="login-callback"'), isTrue);
    });
    testWidgets('giriş sahnesi hatasız çizilir', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 360, child: JuzzioAuthHero(height: 220))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('😎'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Faz 4 — ana sekmeler', () {
    test('Keşfet kartı yalnız açık bilgileri okur; bozuk satırı atlar', () {
      final list = JuzzioDiscoverCard.listFrom([
        {'id': 'u1', 'username': 'elif', 'display_name': 'Elif', 'avatar_url': '', 'lang': 'tr', 'online': true, 'is_verified': true},
        {'username': 'kimliksiz'},
        'bozuk',
      ]);
      expect(list.length, 1);
      expect(list.first.avatarUrl, isNull);
      expect(list.first.online, isTrue);
      expect(list.first.isVerified, isTrue);
    });
    test('Keşfet: isteğe bağlı görünürlük, eşleşme, geri al (SQL)', () {
      final s = _src('supabase/juzzio_database.sql');
      expect(s.contains('ADD COLUMN IF NOT EXISTS discoverable BOOLEAN NOT NULL DEFAULT true'), isTrue);
      expect(s.contains('FUNCTION public.discover_act(p_target UUID, p_action TEXT)'), isTrue);
      expect(s.contains("REVOKE ALL ON public.discover_actions FROM PUBLIC, anon, authenticated;"), isTrue);
    });
    test('Keşfet sekmesi kart + eşleşmeler + beğeniler + akış', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains('JuzzioExploreHub(feed: feed, onOpenProfile: _openUserProfilePage)'), isTrue);
      final v = _src('lib/screens/social/juzzio_discover_view.dart');
      for (final k in ["'Eşleşmeler'", "'Beğeniler'", "'Akış'", "_act('super')", "_act('pass')", '_undo']) {
        expect(v.contains(k), isTrue, reason: k);
      }
    });
    test('Arkadaşlık İstekleri sayfası: gelen/gönderilen, ortak arkadaş, tümünü kabul et', () {
      final f = _src('lib/screens/social/juzzio_friend_requests_page.dart');
      expect(f.contains('Tümünü Kabul Et'), isTrue);
      expect(f.contains('Arkadaşlarımı Bul'), isTrue);
      expect(f.contains('ortak arkadaş'), isTrue);
      expect(_src('lib/screens/chat_screen.dart').contains('onTap: _openFriendRequestsPage'), isTrue);
      expect(_src('supabase/juzzio_database.sql').contains('FUNCTION public.mutual_friend_counts(p_users UUID[])'), isTrue);
    });
    test('Aramalar (v2.1 tasarım): Tümü / Görüntülü / Sesli / Cevapsız sekmeleri, Tümünü Temizle', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains("['voice', appCtrl.trEn('Sesli', 'Voice', 'Sprache')]"), isTrue);
      expect(c.contains("['missed', appCtrl.trEn('Cevapsız', 'Missed', 'Verpasst')]"), isTrue);
      expect(c.contains("appCtrl.trEn('Tümünü Temizle', 'Clear All', 'Alle löschen')"), isTrue);
      expect(c.contains('_buildFeatureShortcutsRow'), isFalse);
    });
  });

  group('Faz 5–6 — profil, bildirimler, arama', () {
    test('karekod bağlantısından kullanıcı adı çıkarılır; yabancı bağlantı reddedilir', () {
      expect(juzzioUsernameFromScan('https://github.com/engiincr/Juzzio-Chat/releases/latest?u=Elif_Demir'), 'elif_demir');
      expect(juzzioUsernameFromScan('@tugkancr'), 'tugkancr');
      expect(juzzioUsernameFromScan('https://kotu.site/?x=1'), isNull);
      expect(juzzioUsernameFromScan('a b c'), isNull);
      expect(juzzioUsernameFromScan(''), isNull);
    });
    test('profilde karekod düğmesi', () {
      expect(_src('lib/screens/profile/juzzio_profile_view.dart').contains('onTap: _openQrPage'), isTrue);
    });
    test('bildirim filtreleri: İstekler · Bahsetmeler · Sistem', () {
      final s = _src('lib/screens/settings_suite_screens.dart');
      expect(s.contains("MapEntry('request'"), isTrue);
      expect(s.contains("MapEntry('mention'"), isTrue);
      expect(s.contains("MapEntry('system'"), isTrue);
      expect(_src('lib/services/social_service.dart').contains("if (eventCategory == 'request')"), isTrue);
    });
    test('görüntülü aramada Canlı Çeviri Aktif rozeti', () {
      final c = _src('lib/screens/call_screen.dart');
      expect(c.contains('if (_showSubtitles) _liveTranslationBadge(top: 72)'), isTrue);
    });
  });

  test('sürüm 2.1.0: yapılandırma ve uygulama içi notlar', () {
    expect(JuzzioConfig.appVersion, '2.1.0');
    expect(_src('pubspec.yaml').contains('version: 2.1.0+210'), isTrue);
    final n = kJuzzioBundledReleaseNotes.first;
    expect(n.versionName, '2.1.0');
    for (final l in ['tr', 'en', 'de']) {
      expect(n.sections[l]!.features.length >= 5, isTrue, reason: l);
    }
  });

  group('Faz 6.3 — ekran paylaşımı ve kamera ile QR', () {
    test('Android ekran paylaşımı mediaProjection ön plan servisini kullanır', () {
      final m = _src('android/app/src/main/AndroidManifest.xml');
      expect(m.contains('android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION'), isTrue);
      expect(m.contains('mediaProjection'), isTrue);
      final svc = _src('android/app/src/main/kotlin/com/juzzio/app/JuzzioCallService.kt');
      expect(svc.contains('FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION'), isTrue);
    });
    test('Arama denetleyicisi ekran paylaşımını açıp kapatır, aramada durdurur', () {
      final d = _src('lib/services/deepgram_livekit_service.dart');
      expect(d.contains('Future<bool> setScreenShare(bool on'), isTrue);
      expect(d.contains('requestCapturePermission'), isTrue);
      expect(d.contains('setScreenShareForeground'), isTrue);
      final c = _src('lib/screens/call_screen.dart');
      expect(c.contains('_toggleScreenShare'), isTrue);
      expect(c.contains('Icons.stop_screen_share_rounded'), isTrue);
      expect(c.contains('TrackSource.screenShareVideo'), isTrue);
    });
    test('QR sayfası kamera ile tarar, yapıştırma yedeği kalır', () {
      final q = _src('lib/screens/profile/juzzio_profile_qr_page.dart');
      expect(q.contains('MobileScanner('), isTrue);
      expect(q.contains('JuzzioQrCameraScanPage.pasteSignal'), isTrue);
      expect(q.contains('_scanPaste'), isTrue);
      expect(_src('pubspec.yaml').contains('mobile_scanner:'), isTrue);
    });
    test('Keşfet herkese açık hesaplarda varsayılan görünür; profilden kapatılabilir', () {
      final s = _src('supabase/juzzio_database.sql');
      expect(s.contains('ALTER COLUMN discoverable SET DEFAULT true'), isTrue);
      expect(s.contains('discoverable_set_at'), isTrue);
      expect(_src('lib/screens/settings_suite_screens.dart').contains('JuzzioDiscoverVisibilityTile'), isTrue);
    });
  });

  group('Gökyüzü 2.1 — konum ve ülke saatine göre ambiyans', () {
    // İstanbul örneği: UTC+3, gün doğumu 07:20, batımı 16:50 (yerel)
    const off = 3 * 3600;
    final rise = juzzioParseLocalIso('2026-11-21T07:20', off)!;
    final sset = juzzioParseLocalIso('2026-11-21T16:50', off)!;
    test('konum saati UTC farkıyla hesaplanır', () {
      expect(rise, DateTime.utc(2026, 11, 21, 4, 20));
      expect(juzzioLocationNow(DateTime.utc(2026, 11, 21, 21, 0), off).hour, 0);
      expect(juzzioParseLocalIso(null, off), isNull);
    });
    test('evre gerçek gün doğumu/batımına göre', () {
      JuzzioSkyPhase at(int h, int m) => juzzioSkyPhase(DateTime.utc(2026, 11, 21, h, m), sunrises: [rise], sunsets: [sset]);
      expect(at(4, 10), JuzzioSkyPhase.dawn); // 07:10 yerel
      expect(at(9, 0), JuzzioSkyPhase.day); // 12:00
      expect(at(13, 20), JuzzioSkyPhase.golden); // 16:20
      expect(at(14, 5), JuzzioSkyPhase.dusk); // 17:05
      expect(at(19, 0), JuzzioSkyPhase.night); // 22:00
    });
    test('güneş yayda ilerler; gece ilerleyişi 0..1', () {
      expect(juzzioSunProgress(rise, [rise], [sset]), 0);
      final noon = rise.add(sset.difference(rise) ~/ 2);
      expect(juzzioSunProgress(noon, [rise], [sset]), closeTo(0.5, 0.01));
      expect(juzzioSunProgress(sset.add(const Duration(hours: 1)), [rise], [sset]), isNull);
      final n = juzzioNightProgress(sset.add(const Duration(hours: 3)), [rise, rise.add(const Duration(days: 1))], [sset]);
      expect(n, inInclusiveRange(0.1, 0.4));
    });
    test('gündüz ay ve yıldız çizilmez, gece güneş çizilmez', () {
      final day = JuzzioSkyScene(kind: JuzzioWeatherKind.clear, phase: JuzzioSkyPhase.day, sunProgress: 0.5, nightProgress: 0, moonPhase: 0.5);
      expect(day.showMoon, isFalse);
      expect(juzzioStarVisibility(JuzzioSkyPhase.day, 0), 0);
      final night = JuzzioSkyScene(kind: JuzzioWeatherKind.clear, phase: JuzzioSkyPhase.night, nightProgress: 0.4, moonPhase: 0.5);
      expect(night.showSun, isFalse);
      expect(night.showMoon, isTrue);
      expect(juzzioStarVisibility(JuzzioSkyPhase.night, 0), greaterThan(juzzioStarVisibility(JuzzioSkyPhase.night, 90)));
    });
    test('yağış, bulutluluk ve rüzgâr sahneyi değiştirir', () {
      expect(juzzioRainDrops(JuzzioWeatherKind.rain, 8), greaterThan(juzzioRainDrops(JuzzioWeatherKind.rain, 0)));
      expect(juzzioRainDrops(JuzzioWeatherKind.clear, 5), 0);
      expect(juzzioCloudCount(JuzzioWeatherKind.clouds, 100), greaterThan(juzzioCloudCount(JuzzioWeatherKind.clear, 0)));
      expect(juzzioWindSlant(50), greaterThan(juzzioWindSlant(5)));
      expect(JuzzioLightning21Painter.intensity(0.06), greaterThan(0.9));
      expect(JuzzioLightning21Painter.intensity(1), 0);
    });
    test('Open-Meteo isteği gün doğumu/batımı ve saat dilimini ister; konum yine yuvarlanır', () {
      final u = juzzioWeatherUri(41.0369, 28.9857);
      expect(u.queryParameters['daily'], 'sunrise,sunset');
      expect(u.queryParameters['timezone'], 'auto');
      expect(u.queryParameters['latitude'], '41.0');
      expect(_src('lib/widgets/juzzio_weather_ambience.dart').contains('JuzzioSky21Painter('), isTrue);
    });
  });

  group('Faz 7.1 / 8.1 / 9.3 — Ayarlar', () {
    test('Ayarlar ana sayfası neon gruplar ve yeni sayfalarla', () {
      final s = _src('lib/screens/settings_suite_screens.dart');
      expect(s.contains('JuzzioCallSettingsPage()'), isTrue);
      expect(s.contains('showJuzzioLogoutDialog(context)'), isTrue);
      expect(s.contains("'Hesap ve Profil'"), isTrue);
      expect(s.contains("'Medya ve Depolama'"), isTrue);
    });
  });

  group('Faz 7–9 — Ayarlar (2FA, sessiz saatler, çeviri kipi, depolama, erişilebilirlik, KVKK)', () {
    test('2FA yardımcıları', () {
      expect(juzzioMfaStatusVerified('FactorStatus.verified'), isTrue);
      expect(juzzioMfaStatusVerified('unverified'), isFalse);
      expect(juzzioAalName('AuthenticatorAssuranceLevels.aal2'), 'aal2');
      expect(juzzioCleanTotpCode(' 123 456 '), '123456');
      expect(juzzioCleanTotpCode('12345'), isNull);
    });
    test('girişte ve açılışta 2FA kodu istenir', () {
      expect(_src('lib/services/supabase_service.dart').contains('JuzzioMfaService.instance.needsChallenge()'), isTrue);
      final m = _src('lib/main.dart');
      expect(m.contains('mfaCodePrompt: () => showJuzzioMfaCodeDialog(context)'), isTrue);
      expect(RegExp('needsChallenge').allMatches(m).length, greaterThanOrEqualTo(1));
    });
    test('sessiz saatler gece yarısını aşar; aramalar hariç', () {
      expect(JuzzioAppController.isWithinQuietHours(23 * 60 + 30, 23 * 60, 7 * 60), isTrue);
      expect(JuzzioAppController.isWithinQuietHours(6 * 60, 23 * 60, 7 * 60), isTrue);
      expect(JuzzioAppController.isWithinQuietHours(12 * 60, 23 * 60, 7 * 60), isFalse);
      expect(JuzzioAppController.isWithinQuietHours(12 * 60, 9 * 60, 17 * 60), isTrue);
      expect(JuzzioAppController.isWithinQuietHours(5, 600, 600), isFalse);
      final k = _src('android/app/src/main/kotlin/com/juzzio/app/JuzzioFirebaseMessagingService.kt');
      expect(k.contains('eventType != "incoming_call"') && k.contains('JuzzioQuietHours.isActive'), isTrue);
    });
    test('çeviri kipi sunucuya gider', () {
      final s = _src('lib/services/supabase_service.dart');
      expect(RegExp("'quality': _app.translationQuality").allMatches(s).length, 3);
      expect(_src('supabase/functions/translate-bridge/index.ts').contains('parseQuality(body.quality)'), isTrue);
    });
    test('depolama kategorileri', () {
      expect(juzzioStorageCategory('/a/b/IMG_1.JPG'), 'photos');
      expect(juzzioStorageCategory('c:\\x\\v.mp4'), 'videos');
      expect(juzzioStorageCategory('/v/ses.m4a'), 'audio');
      expect(juzzioStorageCategory('/d/x.pdf'), 'documents');
      expect(juzzioStorageCategory('/d.dir/dosya'), 'other');
    });
    test('renk düzeltme matrisleri beyazı korur', () {
      for (final m in ['protanopia', 'deuteranopia', 'tritanopia', 'grayscale']) {
        final x = juzzioColorVisionMatrix(m)!;
        expect(x.length, 20);
        for (var r = 0; r < 3; r++) {
          expect(x[r * 5] + x[r * 5 + 1] + x[r * 5 + 2], closeTo(1, 0.01));
        }
      }
      expect(juzzioColorVisionMatrix('off'), isNull);
    });
    test('verilerimi indir yalnız kendi verisi; mesaj içeriği yok', () {
      expect(juzzioExportFileName(DateTime(2026, 11, 21)), 'Juzzio_verilerim_2026-11-21.json');
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.juzzio_export_my_data()'), isTrue);
      expect(sql.contains("GRANT EXECUTE ON FUNCTION public.juzzio_export_my_data() TO authenticated"), isTrue);
    });
  });

  group('Faz 10–16 — Yönetici modülleri', () {
    test('34 numaralı modül, her biri sekme, canlı sayı ya da bilgi', () {
      expect(kJuzzioAdminModules.length, 34);
      expect(kJuzzioAdminModules.map((m) => m.no).toSet().length, 34);
      for (final m in kJuzzioAdminModules) {
        final kinds = [m.tab != null, m.stats != null, m.info != null, m.page != null].where((x) => x).length;
        expect(kinds, 1, reason: m.tr);
        if (m.tab != null) expect(m.tab, inInclusiveRange(0, 16));
      }
    });
    test('her canlı modül sunucuda tanımlı', () {
      final sql = _src('supabase/juzzio_database.sql');
      for (final k in kJuzzioAdminModules.map((m) => m.stats).whereType<String>().toSet()) {
        expect(sql.contains("WHEN '$k' THEN"), isTrue, reason: k);
      }
      expect(sql.contains("IF NOT public.admin_check_token(p_token) THEN RAISE EXCEPTION 'super_admin_required'"), isTrue);
    });
    test('CSV dışa aktarma düzleştirir ve kaçışlar', () {
      final rows = juzzioFlattenForCsv({'a': 1, 'b': {'c': 'x,y'}, 'l': [1, 2]});
      expect(rows.first, ['key', 'value']);
      expect(rows.any((r) => r[0] == 'b.c' && r[1] == 'x,y'), isTrue);
      expect(rows.any((r) => r[0] == 'l[1]' && r[1] == '2'), isTrue);
      expect(juzzioCsvEncode([['k', 'x,y']]), 'k,"x,y"');
    });
  });

  group('Görüntülü arama kalitesi — 1080p60 / en düşük 480p60, donma yok', () {
    test('profil 1080p·60 ve 480p·60; 30 fps ve 360p yok', () {
      final d = _src('lib/services/deepgram_livekit_service.dart');
      expect(d.contains('dimensions: VideoDimensionsPresets.h1080_169'), isTrue);
      expect(d.contains('dimensions: VideoDimensions(854, 480)'), isTrue);
      expect(RegExp(r'maxFramerate: 60').allMatches(d).length, greaterThanOrEqualTo(2));
      expect(d.contains('maxFramerate: 30'), isFalse);
      expect(d.contains('maxFramerate: 15'), isFalse);
      expect(d.contains('h360_169'), isFalse);
      expect(d.contains('setVideoFPS'), isFalse);
    });
    test('donmaya yol açan uyarlamalar kapalı', () {
      final d = _src('lib/services/deepgram_livekit_service.dart');
      expect(d.contains('adaptiveStream: false'), isTrue);
      expect(d.contains('degradationPreference: DegradationPreference.maintainFramerate'), isTrue);
      final i = d.indexOf('Future<void> _applyPowerProfile(bool low)');
      final body = d.substring(i, d.indexOf('/// v0.9.6', i));
      expect(body.contains('setCameraEnabled'), isFalse);
      expect(body.contains('VideoQuality.LOW'), isFalse);
    });
    test('kamera anında çevrilir; ayna yalnız kendi ön kameramda', () {
      expect(_src('lib/services/deepgram_livekit_service.dart').contains('webrtc.Helper.switchCamera'), isTrue);
      final c = _src('lib/screens/call_screen.dart');
      expect(c.contains('_controller.switchCameraFast()'), isTrue);
      expect(c.contains('VideoViewMirrorMode.mirror'), isTrue);
    });
  });

  group('İkinci süper yönetici (@ari) ve İngilizce yasal paket', () {
    test('ek yönetici hesaba bağlı; şifre dosyada yok, yalnız bcrypt özeti', () {
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql.contains('CREATE TABLE IF NOT EXISTS public.admin_user_secrets'), isTrue);
      expect(sql.contains("FROM public.profiles WHERE lower(username) = 'ari' ORDER BY created_at LIMIT 1"), isTrue);
      expect(sql.contains('660876'), isFalse);
      expect(sql.contains('AND NOT EXISTS (SELECT 1 FROM public.admin_user_secrets u WHERE u.user_id = auth.uid() AND u.must_change)'), isTrue);
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.admin_change_my_password(p_token TEXT, p_old TEXT, p_new TEXT)'), isTrue);
    });
    test('ilk girişte şifre değiştirme ekranı', () {
      final a = _src('lib/screens/admin_panel_screen.dart');
      expect(a.contains('JuzzioAdminChangePasswordPage(token: res.token!, forced: true'), isTrue);
      expect(juzzioAdminPasswordOk('YeniSifre2026'), isTrue);
      expect(juzzioAdminPasswordOk('kisa1'), isFalse);
      expect(juzzioAdminPasswordOk('sadeceharf'), isFalse);
    });
    test('yasal rapor, özet ve doğrulama kılavuzu İngilizce üretilebilir', () {
      final b = <String, dynamic>{'profile': {'username': 'x', 'id': 'u1'}, 'account': {}, 'messages': []};
      final en = juzzioLegalReportText(b, english: true);
      expect(en, contains('USER'));
      expect(en, contains('STATEMENT OF TECHNICAL IMPOSSIBILITY'));
      expect(en, contains(juzzioTechnicalImpossibilityStatementEn));
      expect(en.contains('KULLANICI'), isFalse);
      expect(juzzioLegalReportText(b), contains('KULLANICI'));
      expect(juzzioLegalSummary(b, english: true).first.key, 'Account examined');
      expect(juzzioVerificationReadme(hasTimestamp: false, tsaHost: '', english: true), contains('VERIFICATION GUIDE'));
      expect(_src('lib/screens/admin_god_tab.dart').contains("english: english,"), isTrue);
    });
  });

  group('Kalan işler: otomatik indirme, biyometrik, doğrulama, A/B, PDF, Play paketi, neon alt sayfalar', () {
    test('otomatik indirme kuralı', () {
      expect(juzzioShouldAutoDownload('always', unmetered: false, isMine: false), isTrue);
      expect(juzzioShouldAutoDownload('wifi', unmetered: false, isMine: false), isFalse);
      expect(juzzioShouldAutoDownload('wifi', unmetered: true, isMine: false), isTrue);
      expect(juzzioShouldAutoDownload('never', unmetered: true, isMine: false), isFalse);
      expect(juzzioShouldAutoDownload('never', unmetered: false, isMine: true), isTrue);
      expect(RegExp('JuzzioAutoDownloadGate\\(').allMatches(_src('lib/screens/chat_screen.dart')).length, 2);
    });
    test('yönetici: biyometrik, doğrulama başvuruları, A/B, PDF', () {
      final k = _src('android/app/src/main/kotlin/com/juzzio/app/JuzzioBiometric.kt');
      expect(k.contains('BiometricPrompt.Builder'), isTrue);
      expect(_src('lib/screens/admin_panel_screen.dart').contains('juzzioAdminBiometricOk()'), isTrue);
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.verification_submit'), isTrue);
      expect(sql.contains('CREATE OR REPLACE FUNCTION public.my_feature_flags()'), isTrue);
      final m = _src('lib/screens/admin_modules_v21.dart');
      expect(m.contains('juzzioAdminModulePdf('), isTrue);
      expect(kJuzzioAdminModules.firstWhere((x) => x.no == 19).page, 'verification');
      expect(kJuzzioAdminModules.firstWhere((x) => x.no == 27).page, 'flags');
    });
    test('Play paketi APK kurma iznini kaldırır, normal APK değişmez', () {
      expect(_src('android/app/src/play/AndroidManifest.xml').contains('REQUEST_INSTALL_PACKAGES" tools:node="remove"'), isTrue);
      expect(_src('android/app/build.gradle').contains('System.getenv("JUZZIO_PLAY") == "1"'), isTrue);
      expect(_src('.github/workflows/android-ci.yml').contains('JUZZIO_PLAY=1 flutter build appbundle'), isTrue);
      expect(_src('lib/core/app_theme_and_locale.dart').contains('JuzzioConfig.playStoreBuild'), isTrue);
    });
    test('ayar alt sayfaları neon: ortalı başlık, yuvarlak geri, neon kartlar', () {
      final st = _src('lib/screens/settings_suite_screens.dart');
      expect(RegExp('leading: const JuzzioNeonBackButton\\(\\)').allMatches(st).length, greaterThanOrEqualTo(25));
      expect(st.contains('backgroundColor: p.bgPrimary,'), isFalse);
    });
  });
}
