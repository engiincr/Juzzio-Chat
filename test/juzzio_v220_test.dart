// v2.2.0 — hava doodle katmanı, yeni Ayarlar, Arkadaşlar sayfası, ortak arkadaşlar, Amber Altın,
// varsayılan lime, gelen kutusu satırı, tek profil karekodu, ek menüsü ve hata düzeltmeleri.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/config.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/screens/chat_screen.dart';
import 'package:juzzio/services/juzzio_error_reporter.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_attach_menu.dart';
import 'package:juzzio/widgets/juzzio_profile_qr.dart';
import 'package:juzzio/widgets/juzzio_weather_doodles.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('sürüm 2.2.0', () {
    test('yapılandırma, pubspec ve uygulama içi notlar', () {
      expect(JuzzioConfig.appVersion, '2.2.0');
      expect(_src('pubspec.yaml').contains('version: 2.2.0+220'), isTrue);
      final n = kJuzzioBundledReleaseNotes.first;
      expect(n.versionName, '2.2.0');
      for (final l in ['tr', 'en', 'de']) {
        expect(n.sections[l]!.features.length >= 5, isTrue, reason: l);
      }
      expect(_src('version.json').contains('"version": "2.2.0"'), isTrue);
    });
  });

  group('hava doodle katmanı (referans görseller)', () {
    test('yağmurda damla + çizgi, gündüz güneş, gece yıldız; ay ayrı çizilir', () {
      final rain = juzzioDoodleKinds(JuzzioWeatherKind.rain, night: true);
      expect(rain, contains(JuzzioDoodleKind.drop));
      expect(rain, contains(JuzzioDoodleKind.cloud));
      expect(juzzioRainStreaks(JuzzioWeatherKind.rain), greaterThan(0));
      expect(juzzioRainStreaks(JuzzioWeatherKind.clear), 0);
      expect(juzzioDoodleKinds(JuzzioWeatherKind.clouds, night: false), contains(JuzzioDoodleKind.sun));
      expect(juzzioDoodleKinds(JuzzioWeatherKind.clear, night: true), isNot(contains(JuzzioDoodleKind.sun)));
    });

    test('simgeler başlık ve alt şerit bölgesine konmaz, ekran içinde kalır', () {
      for (final k in JuzzioWeatherKind.values) {
        for (final s in juzzioDoodleLayout(juzzioDoodleKinds(k, night: false), top: 0.2, bottom: 0.88)) {
          expect(s.y, inInclusiveRange(0.2, 0.88));
          expect(s.x, inInclusiveRange(0.0, 1.0));
          expect(s.size, greaterThan(0));
        }
      }
    });

    test('düz ay şekli her evrede dairenin içinde ve boş değil', () {
      for (final ph in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9]) {
        final b = juzzioFlatMoonPath(const Offset(50, 50), 20, ph).getBounds();
        expect(b.width, greaterThan(2), reason: '$ph');
        expect(b.left, greaterThanOrEqualTo(29.5));
        expect(b.right, lessThanOrEqualTo(70.5));
      }
    });

    test('katman içerik arkasında; başlıkta ay simgesi yok, Gökyüzü 2.1 bulutları kullanılmıyor', () {
      final amb = _src('lib/widgets/juzzio_weather_ambience.dart');
      expect(amb, contains('JuzzioHdWeatherScene(')); // GM-030: HD görseller
      expect(amb.contains('JuzzioSky21Painter('), isFalse);
      expect(_src('lib/screens/chat_screen.dart').contains('JuzzioSkyIcon('), isFalse);
      expect(_src('lib/main.dart'), contains('JuzzioAuroraPage.weatherLayerBuilder'));
    });
  });

  group('temalar', () {
    test('varsayılan Grafit Limon, Amber Altın eklendi', () {
      expect(kJuzzioAuroraPalettes.first.id, 'graphite_lime');
      final a = juzzioAuroraPaletteById('amber_gold');
      expect(a.id, 'amber_gold');
      expect(a.nameTr, 'Amber Altın');
      expect(a.space.glow, const Color(0xFFF7DC6F));
    });
  });

  group('gelen kutusu satırı', () {
    String e(int chats, int unread) => juzzioInboxEyebrow(
        inbox: 'Gelen kutusu', chatCount: chats, unread: unread, chatsWord: 'sohbet', newWord: 'yeni mesaj', newWordOne: 'yeni mesaj');
    test('okunmamış varsa yeni mesaj sayısı, yoksa sohbet sayısı', () {
      expect(e(8, 1), 'Gelen kutusu • 1 yeni mesaj');
      expect(e(8, 3), 'Gelen kutusu • 3 yeni mesaj');
      expect(e(8, 0), 'Gelen kutusu · 08 sohbet');
      expect(e(0, 0), 'Gelen kutusu');
    });
  });

  group('ortak arkadaşlar', () {
    test('sunucu satırlarından okunur, metin doğru kurulur', () {
      final m = JuzzioMutualFriends.fromRows([
        {'id': 'a', 'username': 'ali', 'display_name': 'Ali', 'avatar_url': '', 'total': 5},
        {'id': 'b', 'username': 'ayse', 'display_name': 'Ayşe', 'avatar_url': '', 'total': 5},
      ]);
      expect(m.people.length, 2);
      expect(m.total, 5);
      expect(juzzioMutualFriendsLine(m, lang: 'tr'), 'Ali, Ayşe ve 3 kişi daha ortak arkadaşınız');
      final one = JuzzioMutualFriends.fromRows([
        {'id': 'a', 'username': 'ali', 'display_name': '', 'avatar_url': '', 'total': 1},
      ]);
      expect(juzzioMutualFriendsLine(one, lang: 'tr'), 'ali ortak arkadaşınız');
      expect(JuzzioMutualFriends.fromRows(null).isEmpty, isTrue);
    });
    test('SQL işlevi yalnız giriş yapanlara açık', () {
      final sql = _src('supabase/juzzio_database.sql');
      expect(sql, contains('FUNCTION public.mutual_friends(p_user UUID, p_limit INTEGER DEFAULT 12)'));
      expect(sql, contains('REVOKE ALL ON FUNCTION public.mutual_friends(UUID, INTEGER) FROM PUBLIC, anon;'));
    });
  });

  group('profil karekodu', () {
    test('iki ekran aynı bileşeni kullanır', () {
      expect(_src('lib/screens/profile/juzzio_profile_card_page.dart'), contains('JuzzioProfileQr('));
      expect(_src('lib/screens/profile/juzzio_profile_qr_page.dart'), contains('JuzzioProfileQr('));
    });
    test('kart rengi ve okunur göz rengi', () {
      expect(juzzioProfileCardColor('#16A34A', Colors.blue), const Color(0xFF16A34A));
      expect(juzzioProfileCardColor('xx', Colors.blue), Colors.blue);
      expect(juzzioQrEyeColor(const Color(0xFFFFFFFF)).computeLuminance(), lessThanOrEqualTo(0.35));
    });
  });

  test('ek menüsü renkleri tanımlı', () {
    for (final id in ['document', 'gallery_photo', 'gallery_video', 'view_once', 'location', 'contact', 'schedule']) {
      expect(kJuzzioAttachColors[id], isNotNull, reason: id);
    }
  });

  test('LiveKit iç gürültüsü raporlanmaz', () {
    expect(juzzioIsBenignLiveKitNoise('livekit exception: [timeoutexception] timeout'), isTrue);
    expect(juzzioIsBenignLiveKitNoise('unable to rtcpeerconnection::addtransceiver: addtransceiver(): track is null'), isTrue);
    expect(juzzioIsBenignLiveKitNoise('null check operator used on a null value'), isFalse);
  });

  test('Arkadaşlar sayfası: Ekle sekmesi, ayrı alt pencere yok', () {
    final f = _src('lib/screens/social/juzzio_friend_requests_page.dart');
    expect(f, contains('Widget _addTab()'));
    final c = _src('lib/screens/chat_screen.dart');
    expect(c, contains('Future<void> _showFriendSearchAndRequestsSheet() => _openFriendRequestsPage(tab: 0);'));
  });
}
