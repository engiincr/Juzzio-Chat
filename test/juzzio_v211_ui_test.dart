// v2.1 — yeni arama arayüzü, ses çıkışı, Sinema Parti, yönetici paneli, güncelleme anahtarı
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_auth_hero.dart';
import 'package:juzzio/services/juzzio_audio_route.dart';
import 'package:juzzio/widgets/juzzio_call_kit21.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('Ses çıkışı', () {
    test('kulaklık çıkarılınca hoparlöre DEĞİL ahizeye döner', () {
      expect(
        juzzioRouteAfterUnplug(JuzzioAudioOutput.wired, {JuzzioAudioOutput.earpiece, JuzzioAudioOutput.speaker}),
        JuzzioAudioOutput.earpiece,
      );
      expect(
        juzzioRouteAfterUnplug(JuzzioAudioOutput.bluetooth, {JuzzioAudioOutput.earpiece, JuzzioAudioOutput.speaker}),
        JuzzioAudioOutput.earpiece,
      );
    });
    test('başka kulaklık takılıysa ona geçer', () {
      expect(
        juzzioRouteAfterUnplug(
            JuzzioAudioOutput.bluetooth, {JuzzioAudioOutput.earpiece, JuzzioAudioOutput.speaker, JuzzioAudioOutput.wired}),
        JuzzioAudioOutput.wired,
      );
    });
    test('anahtar dönüşümü', () {
      for (final o in JuzzioAudioOutput.values) {
        expect(juzzioAudioOutputFrom(juzzioAudioOutputKey(o)), o);
      }
    });
    test('Android yerel katman: tak → kulaklık, çıkar → ahize', () {
      final k = _src('android/app/src/main/kotlin/com/juzzio/app/JuzzioAudioRoute.kt');
      expect(k.contains('onAudioDevicesAdded'), isTrue);
      expect(k.contains('onAudioDevicesRemoved'), isTrue);
      expect(k.contains('else -> ROUTE_EARPIECE'), isTrue);
      final m = _src('android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt');
      expect(m.contains('"juzzio/audio_route_events"'), isTrue);
      expect(m.contains('"audioRouteSet"'), isTrue);
    });
  });

  group('Arama ekranları (tasarım şablonları)', () {
    final c = _src('lib/screens/call_screen.dart');
    test('sesli arama: tuş takımı yok, Sessize al + Hoparlör (basılı tut: ses çıkışı) — GM-9276 tasarımı', () {
      expect(c.contains('Widget _buildVoiceCallView('), isTrue);
      expect(c.toLowerCase().contains('dialpad'), isFalse);
      expect(c.contains("'Tuş Takımı'"), isFalse);
      expect(c.contains("_app.loc('Sessize al', 'Mute', 'Stumm')"), isTrue);
      expect(c.contains('onLongPress: _openAudioOutputPicker'), isTrue);
      expect(c.contains('JuzzioRingedAvatar('), isTrue);
    });
    test('görüntülü arama: HD hapı, PiP çevirme, ekran paylaşımı, tutamaçlı raf', () {
      expect(c.contains('Future<void> _openQualitySheet()'), isTrue);
      expect(c.contains('_controlsExpanded'), isTrue);
      expect(c.contains('Icons.stop_screen_share_rounded'), isTrue);
      expect(c.contains('const JuzzioLogoGlyph(size: 34)'), isTrue);
    });
    test('eski arayüz parçaları kaldırıldı', () {
      expect(c.contains('_buildAudioOnlyLayer'), isFalse);
      expect(c.contains('_buildTopHeaderBar'), isFalse);
      expect(c.contains('_bottomCircleBtn'), isFalse);
    });
    test('gelen arama tam ekran', () {
      final chat = _src('lib/screens/chat_screen.dart');
      expect(chat.contains('return JuzzioIncomingCallView('), isTrue);
      expect(chat.contains('Positioned.fill(child: _buildIncomingCallBanner(p, s))'), isTrue);
    });
  });

  group('Aramalar sekmesi yardımcıları', () {
    test('süre metni', () {
      expect(juzzioCallDurationLong(754, lang: 'tr'), '12 dk 34 sn');
      expect(juzzioCallDurationLong(45, lang: 'tr'), '45 sn');
      expect(juzzioCallDurationLong(3900, lang: 'en'), '1 h 05 min');
    });
    test('tarih etiketi', () {
      final now = DateTime(2026, 11, 21, 12);
      expect(juzzioCallWhenLabel(DateTime(2026, 11, 21, 9, 17), now: now, lang: 'tr'), 'Bugün 09:17');
      expect(juzzioCallWhenLabel(DateTime(2026, 11, 20, 21, 4), now: now, lang: 'tr'), 'Dün 21:04');
      expect(juzzioCallWhenLabel(DateTime(2026, 11, 18, 14, 30), now: now, lang: 'en'), '18.11 14:30');
    });
  });

  test('diyaloglar açılır pencerede opak (alttaki sayfa okunmaz olmaz)', () {
    expect(_src('lib/widgets/juzzio_neon_kit.dart').contains('JuzzioLiquidGlass('), isTrue);
    expect(_src('lib/core/theme/juzzio_glass.dart').contains('ModalRoute.of(context) is PopupRoute'), isTrue);
    expect(_src('lib/screens/settings/juzzio_settings_v21.dart').contains('class JuzzioMfaCodePage'), isTrue);
  });

  test('Sinema Parti odası yeni tasarım', () {
    final w = _src('lib/screens/watch_party_screen.dart');
    expect(w.contains('Future<void> _openRoomMenu('), isTrue);
    expect(w.contains("_app.trEn('Sinemadakiler', 'In the cinema', 'Im Kino')"), isTrue);
    expect(w.contains('Color(0xFF7B5CFF)'), isFalse);
  });

  test('yönetici paneli: sekme çubuğu yok, bölümler tam sayfa', () {
    final a = _src('lib/screens/admin_panel_screen.dart');
    expect(a.contains('TabBar('), isFalse);
    expect(a.contains('class _AdminSectionPage'), isTrue);
    expect(a.contains('void _openSection(int i)'), isTrue);
  });

  test('GitHub güncelleme bildirimi yönetici anahtarına bağlı, varsayılan kapalı', () {
    final sql = _src('supabase/juzzio_database.sql');
    expect(sql.contains("('github_updates_enabled', 'false'::jsonb)"), isTrue);
    final ci = _src('.github/workflows/android-ci.yml');
    expect("juzzio_setting_bool('github_updates_enabled', false)".allMatches(ci).length, 3);
    expect(_src('lib/screens/chat_screen.dart').contains('if (cfg.githubUpdatesEnabled) JuzzioAppController.instance.checkForOtaUpdate();'), isTrue);
    expect(_src('lib/screens/admin_god_tab.dart').contains("'github_updates_enabled', v"), isTrue);
  });

  test('macOS DMG: .app dinamik bulunur', () {
    final ci = _src('.github/workflows/android-ci.yml');
    expect(ci.contains('Trawave Chat.app'), isFalse);
    expect(ci.contains("-name '*.app'"), isTrue);
  });

  test('sohbetler üst kısayol kutuları kaldırıldı', () {
    expect(_src('lib/screens/chat_screen.dart').contains('_buildFeatureShortcutsRow'), isFalse);
  });

  testWidgets('giriş başlığı tek satır, vurgu çizgisi kelimenin altında; dar ekranda taşmaz', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 260,
            child: JuzzioMarkedTitle(
              prefix: 'Tekrar Hoş ',
              mark: 'Geldin!',
              suffix: ' 👋',
              scribbleColor: Color(0xFFC6F135),
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(JuzzioTitleScribble), findsOneWidget);
  });
}
