// GM-014 — varsayılan mavi tema (KR-011) ve uygulama içi gelen arama bildirimi.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:juzzio/core/juzzio_temp_dir.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/screens/social/juzzio_creator_studio.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/widgets/juzzio_chick_art.dart';
import 'package:juzzio/widgets/juzzio_weather_ambience.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('GM-014-A varsayılan tema mavi', () {
    test('palet listesinin ilki ve bilinmeyen kimlik ocean (Gece Mavisi)', () {
      expect(kJuzzioAuroraPalettes.first.id, 'ocean');
      expect(juzzioAuroraPaletteById('yok').id, 'ocean');
      expect(juzzioAuroraPaletteById('').id, 'ocean');
    });

    test('ilk açılış ve göç mavi; kullanıcının kendi seçimi ezilmez', () {
      final src = _read('lib/core/app_theme_and_locale.dart');
      expect(src, contains("String _glassPaletteId = 'ocean';"));
      expect(src, contains("raw['paletteV22'] != true"));
      expect(src, contains("raw['paletteUserPicked'] != true"));
      expect(src, contains("'paletteV22': true,"));
      expect(src, contains('_paletteUserPicked = true;'));
    });
  });

  group('GM-014-B gelen arama — uygulama içindeyken üstten bildirim yok', () {
    final src = _read('lib/screens/chat_screen.dart');

    test('sistem bildirimi yalnız arka planda', () {
      expect(src,
          contains('if (_isAppInBackground) _notifyIncomingCallSystem(call);'));
      expect(
          src, contains('void _notifyIncomingCallSystem(JuzzioCallLog call)'));
    });

    test('çalarken arka plana geçilirse bildirim bir kez çıkar', () {
      expect(
          src,
          contains(
              'if (ringingCall != null && !_isInCall) _notifyIncomingCallSystem(ringingCall);'));
      expect(src, contains('if (_incomingCallNotifiedId == call.id) return;'));
    });

    test('ön plandaki FCM arama olayı ekrana bildirim basmaz', () {
      expect(src, contains("if (et == 'incoming_call') return;"));
      final kt = _read(
          'android/app/src/main/kotlin/com/juzzio/app/JuzzioFirebaseMessagingService.kt');
      expect(
          kt,
          contains(
              'if (MainActivity.isAppInForeground && MainActivity.activeMethodChannel != null)'));
    });
  });

  group('GM-014-C güvenlik (SQL dosyası)', () {
    final sql = _read('supabase/juzzio_database.sql');
    final tail = sql.substring(sql.lastIndexOf('10.46 (GM-014)'));

    test('yönetici paylaşımları panel oturumu ister', () {
      expect(
          tail,
          contains(
              'CREATE OR REPLACE FUNCTION public.juzzio_admin_unlocked(p_uid UUID)'));
      expect(
          tail,
          contains(
              'REVOKE ALL ON FUNCTION public.juzzio_admin_unlocked(UUID) FROM PUBLIC, anon, authenticated;'));
      for (final fn in [
        'admin_post_official_story',
        'admin_delete_official_story',
        'admin_community_post'
      ]) {
        expect(tail, contains('CREATE OR REPLACE FUNCTION public.$fn('));
      }
      expect(RegExp('admin_session_required').allMatches(tail).length, 3);
      expect(_read('lib/core/juzzio_server_errors.dart'),
          contains("case 'admin_session_required':"));
    });

    test('eski JSON listeler herkese açık profilde tutulmaz', () {
      expect(tail, contains('CREATE TRIGGER trg_profile_hide_legacy'));
    });

    test('sunucu varsayılan teması ocean (dosyanın son sözü)', () {
      final last = sql.lastIndexOf("'default_glass_palette', '\"");
      expect(sql.substring(last, last + 40), contains('"ocean"'));
    });
  });

  group('GM-014-D hava/ay katmanı düğmelerin üstüne binmez', () {
    test('başlık ve alt şerit bölgesi tamamen temiz, aralık sıralı', () {
      for (final h in [560.0, 720.0, 900.0, 1400.0]) {
        final st = juzzioAmbienceMaskStops(h, topInset: 44, bottomInset: 34);
        expect(st[0] * h,
            greaterThanOrEqualTo(44 + kJuzzioAmbienceHeaderClear - 0.01));
        expect((1 - st[3]) * h,
            greaterThanOrEqualTo(34 + kJuzzioAmbienceDockClear - 0.01));
        for (var i = 1; i < st.length; i++) {
          expect(st[i], greaterThanOrEqualTo(st[i - 1]));
        }
      }
      expect(kJuzzioAmbienceContentAlpha, lessThan(0.7));
    });

    test('ay/güneş arka planda çizilmez, başlıktaki sabit simgede durur', () {
      final amb = _read('lib/widgets/juzzio_weather_ambience.dart');
      expect(amb, contains('celestial: false'));
      expect(amb, contains('BlendMode.dstIn'));
      final chat = _read('lib/screens/chat_screen.dart');
      expect(RegExp(r'JuzzioSkyIcon\(size: \d+\)').allMatches(chat).length,
          greaterThanOrEqualTo(2));
    });
  });

  group('GM-014-E Hikâye Oluştur (referans görsel) — Süre aracı', () {
    test('süre döngüsü 5 → 10 → 20 → 30 → 5', () {
      expect(juzzioNextStoryPhotoSec(30), 5);
      expect(juzzioNextStoryPhotoSec(5), 10);
      expect(juzzioNextStoryPhotoSec(10), 20);
      expect(juzzioNextStoryPhotoSec(20), 30);
      expect(juzzioNextStoryPhotoSec(99), 5);
    });
    test('eski kayıtlar (7/15/0) varsayılan 30 sn, seçilen süre aynen', () {
      expect(juzzioStoryPhotoDisplayMs(7), 30000);
      expect(juzzioStoryPhotoDisplayMs(15), 30000);
      expect(juzzioStoryPhotoDisplayMs(0), 30000);
      expect(juzzioStoryPhotoDisplayMs(10), 10000);
    });
    test('araç sırası: Metin · Çıkartma · Efekt · Filtre · Müzik · Kırp · Süre',
        () {
      final src = _read('lib/screens/social/juzzio_creator_studio.dart');
      final order = [
        "'Metin'",
        "'Çıkartma'",
        "'Efekt'",
        "'Filtre'",
        "'Müzik'",
        "'Kırp', 'Crop'",
        "'Süre'"
      ];
      var last = -1;
      for (final k in order) {
        final i = src.indexOf(k, last + 1);
        expect(i, greaterThan(last), reason: k);
        last = i;
      }
      expect(src, contains('videoDurationSec: _photoSec,'));
      expect(_read('lib/screens/chat_screen.dart'),
          contains('juzzioStoryPhotoDisplayMs(st.videoDurationSec'));
    });
  });

  group('GM-014-F Keşfet (referans görsel)', () {
    final v = _read('lib/screens/social/juzzio_discover_view.dart');
    test('üst şerit: J Juzzio + filtre · konum · şimşek; 3 sekme', () {
      expect(v, contains('JuzzioSpaceBrand(size: 26)'));
      for (final k in [
        'Icons.tune_rounded',
        'Icons.location_on_outlined',
        'Icons.bolt_rounded',
        '_openFilters',
        '_openVisibility'
      ]) {
        expect(v, contains(k), reason: k);
      }
      expect(v, contains('selected: _tab.clamp(0, 2)'));
    });
    test('filtre kart kaybetmez (park edilir), akış korunur', () {
      expect(v, contains('final List<JuzzioDiscoverCard> _parked'));
      expect(v, contains('widget.feed'));
    });
  });

  group('GM-014-I1 uygulamadaki civciv (fotoğraf esaslı)', () {
    test('kabarık tüy kümeleri gövde kenarında, sabit ve eşit dağılır', () {
      const body = Rect.fromLTWH(0, 0, 200, 190);
      final a = juzzioChickFluffPoints(body);
      final b = juzzioChickFluffPoints(body);
      expect(a.length, 34);
      expect(a, b);
      for (final p in a) {
        final dx = (p.dx - 100) / 100, dy = (p.dy - 95) / 95;
        final d = dx * dx + dy * dy;
        expect(d, inInclusiveRange(0.85, 1.0));
      }
    });
    test('civciv renkleri ve çizgi tüy yerine yumuşak küme', () {
      final src = _read('lib/widgets/juzzio_chick_art.dart');
      expect(src, contains('0xFFFFD23A'));
      expect(src, contains('juzzioPaintChickFluffRim('));
    });
  });

  group('GM-014-J eski/kullanılmayan kod temizliği', () {
    test('kaldırılan eski bileşenler kaynakta yok', () {
      final all = [
        'lib/widgets/juzzio_call_kit21.dart',
        'lib/widgets/juzzio_space_kit.dart',
        'lib/widgets/juzzio_neon_kit.dart',
        'lib/widgets/juzzio_ui_kit.dart',
        'lib/screens/call_screen.dart',
        'lib/main.dart',
      ].map(_read).join();
      for (final k in [
        'class JuzzioCallBadge',
        'class JuzzioCallSquareButton',
        'class JuzzioCallTimerPill',
        'class JuzzioCallParticleWave',
        'class JuzzioSpaceCard',
        'class JuzzioOAuthButton',
        'class JuzzioUnreadPill',
        '_buildLanguageStatusPill',
        '_consentError',
      ]) {
        expect(all.contains(k), isFalse, reason: k);
      }
    });
  });

  group('GM-014-K ekran testinde bulunanlar', () {
    test('konum yoksa hava durumu ülkenin başkentiyle çalışır', () {
      expect(juzzioApproxCoordsForLocale('tr_TR', const Duration(hours: 3)),
          (39.93, 32.86));
      expect(juzzioApproxCoordsForLocale('tr-TR', const Duration(hours: 3)),
          (39.93, 32.86));
      expect(juzzioApproxCoordsForLocale('en_US', const Duration(hours: -5)),
          (38.90, -77.04));
      final f = juzzioApproxCoordsForLocale('xx', const Duration(hours: 3));
      expect(f.$2, closeTo(45, 0.01));
    });
    test('ayarlar ve diğer düz siyah sayfalar tema zeminini (aurora) kullanır',
        () {
      for (final f in [
        'lib/screens/settings_suite_screens.dart',
        'lib/screens/settings/juzzio_settings_v21.dart',
        'lib/screens/admin_modules_v21.dart',
      ]) {
        final src = _read(f);
        expect(
            src.contains('backgroundColor: JuzzioGlassTokens.space.depth.last'),
            isFalse,
            reason: f);
        expect(src, contains('JuzzioAuroraPage(child: Scaffold('));
      }
    });
  });

  group('GM-014-K2 masaüstü ve Görünüm', () {
    test('masaüstü boş sağ panel tema zemininde, sabit koyu renk yok', () {
      final src = _read('lib/widgets/juzzio_desktop_shell.dart');
      final a = src.indexOf('class JuzzioDesktopRightPlaceholder');
      final body = src.substring(a, src.indexOf('\n}\n', a));
      expect(body.contains('Color(0xFF080A0F)'), isFalse);
      expect(body.contains('space.depth'), isFalse);
      expect(body.contains('Juzzio 2.0'), isFalse);
      expect(body, contains('JuzzioGlassTokens.onGlow'));
    });
    test('Görünüm: gece/gündüz tek kontrol', () {
      final v21 = _read('lib/screens/settings/juzzio_settings_v21.dart');
      final a = v21.indexOf('class JuzzioAppearanceQuickCard');
      final card = v21.substring(a, v21.indexOf('\n}\n', a));
      expect(card.contains('setThemeSelectionMode'), isFalse);
      expect(_read('lib/screens/settings_suite_screens.dart'),
          contains('JuzzioThemeModeSelector()'));
    });
  });

  group('GM-014-K3 masaüstü geçici klasör güvenliği', () {
    test(
        'masaüstünde geçici klasör ortak sayılır (Juzzio alt klasörü kullanılır)',
        () {
      expect(juzzioTempIsShared(isWeb: false, os: 'windows'), isTrue);
      expect(juzzioTempIsShared(isWeb: false, os: 'macos'), isTrue);
      expect(juzzioTempIsShared(isWeb: false, os: 'android'), isFalse);
      expect(juzzioTempIsShared(isWeb: false, os: 'ios'), isFalse);
    });
    test('hiçbir yer doğrudan ortak TEMP klasörünü silmez/ölçmez', () {
      for (final f in [
        'lib/services/social_service.dart',
        'lib/screens/chat_screen.dart',
        'lib/core/app_theme_and_locale.dart',
        'lib/services/juzzio_media_cache.dart',
      ]) {
        expect(_read(f).contains('getTemporaryDirectory()'), isFalse,
            reason: f);
      }
    });
    test('Görünüm sayfasında vurgu yazıları okunur renk (glowText)', () {
      final s = _read('lib/screens/settings_suite_screens.dart');
      expect(
          RegExp(r'TextStyle\([^)\n]*color: JuzzioGlassTokens\.glow[,)]')
              .hasMatch(s),
          isFalse);
    });
  });

  test('GM-014-K4 tema galerileri tema/gece-gündüz değişince yeniden çizilir',
      () {
    final g = _read('lib/widgets/glass/juzzio_theme_gallery.dart');
    expect(RegExp('ListenableBuilder\\(listenable: app').allMatches(g).length,
        greaterThanOrEqualTo(2));
  });
}
