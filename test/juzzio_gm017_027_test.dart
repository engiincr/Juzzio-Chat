// GM-017 … GM-027 (v2.2.0 düzeltme listesi) — Windows tam ekran, sohbet menüsü sadeleştirme,
// sohbete özel arka plan, ek menüsü taşması, tepki zıplaması, çevrimiçi gecikmesi, hikâye yanıt
// balonu, kişi kartı, Sinema Parti teması, arama kutuları ve yönetici PIN girişi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/screens/message_search_page.dart';
import 'package:juzzio/screens/theme_preview_page.dart';
import 'package:juzzio/services/juzzio_admin_pin.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_attach_menu.dart';
import 'package:juzzio/widgets/juzzio_chat_background.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  test('GM-017: Windows penceresi tam ekran (büyütülmüş) açılır', () {
    final c = _src('windows/runner/win32_window.cpp');
    expect(c.contains('SW_SHOWMAXIMIZED'), isTrue);
  });

  group('GM-018: sohbet menüsü sade', () {
    final chat = _src('lib/screens/chat_screen.dart');
    final start = chat.indexOf('List<PopupMenuEntry<String>> _conversationMenuItems(');
    final menu = chat.substring(start, chat.indexOf('\n  }\n', start));
    test('1:1 menüde Sinema Parti, Güvenli takip ve Geçmişi temizle yok; Kişi bilgisi var', () {
      expect(menu.contains("'watch_party'"), isFalse);
      expect(menu.contains('Güvenli takip'), isFalse);
      expect(menu.contains("'contact_info'"), isTrue);
    });
    test('Sinema Parti ek menüsünde; Güvenli Varış adı; seçenekler Kişi bilgisi sayfasında', () {
      expect(_src('lib/widgets/juzzio_attach_menu.dart').contains("'watch_party'"), isTrue);
      expect(chat.contains("case 'watch_party':"), isTrue);
      expect(_src('lib/screens/safety_walk_screen.dart').contains('Güvenli Varış'), isTrue);
      final cs = _src('lib/screens/contact_settings_page.dart');
      for (final id in ["'export_chat'", "'safety'", "'clear'", "'safety_number'"]) {
        expect(cs.contains(id), isTrue, reason: id);
      }
    });
  });

  group('GM-019: sohbete özel arka plan', () {
    test('JSON gidiş-dönüş; karartma ve konum sınırlı', () {
      const bg = JuzzioChatBackground(kind: JuzzioChatBgKind.image, imagePath: '/a.png', dim: 0.4, alignX: -0.5);
      final back = JuzzioChatBackground.fromJson(bg.toJson());
      expect(back, bg);
      final wild = JuzzioChatBackground.fromJson({'k': 'image', 'p': 'x', 'd': 5, 'x': 9});
      expect(wild.dim, 0.8);
      expect(wild.alignX, 1.0);
      expect(JuzzioChatBackground.fromJson('bozuk'), JuzzioChatBackground.none);
    });
    test('hazır renk/tema seçenekleri benzersiz', () {
      final ids = kJuzzioChatBgPresets.map((p) => p.id).toSet();
      expect(ids.length, kJuzzioChatBgPresets.length);
      expect(juzzioChatBgPresetById('theme_glow'), isNotNull);
    });
    test('sohbet ekranı katmanı yalnız o sohbetin kimliğiyle çizer', () {
      expect(_src('lib/screens/chat_screen.dart').contains('JuzzioChatBackgroundLayer(roomId: targetStreamRoomId)'), isTrue);
    });
  });

  test('GM-020: ek menüsü sabit karo yüksekliği + liquid glass panel (taşma yok)', () {
    expect(kJuzzioAttachTileHeight, greaterThanOrEqualTo(110));
    final c = _src('lib/widgets/juzzio_attach_menu.dart');
    expect(c.contains('mainAxisExtent: kJuzzioAttachTileHeight'), isTrue);
    expect(c.contains('JuzzioLiquidGlass('), isTrue);
    expect(c.contains('childAspectRatio'), isFalse);
  });

  test('GM-021: tepki emojisi tek kez belirir (yaylanma ve ayrı patlama yok)', () {
    expect(_src('lib/widgets/motion/juzzio_send_fx.dart').contains('Curves.easeOutBack.transform(t)'), isTrue);
    final chat = _src('lib/screens/chat_screen.dart');
    expect(chat.contains('const bool kJuzzioReactionBurstOverlay = false;'), isTrue);
  });

  test('GM-022: çevrimiçi durumu hızlı (8 sn yoklama, 25 sn kalp atışı, 75 sn pencere)', () {
    expect(kJuzzioPresencePoll, const Duration(seconds: 8));
    expect(kJuzzioPresenceHeartbeat, const Duration(seconds: 25));
    expect(kJuzzioPresenceHeartbeat * 3, const Duration(seconds: 75));
    expect(_src('supabase/juzzio_database.sql').contains("INTERVAL '75 seconds'"), isTrue);
  });

  test('GM-023/024: hikâye yanıtı ve kişi kartı köşeli liquid glass', () {
    final chat = _src('lib/screens/chat_screen.dart');
    expect(chat.contains("ValueKey('gm023-story-reply-label')"), isTrue);
    final cards = _src('lib/widgets/juzzio_message_cards.dart');
    expect(cards.contains("ValueKey('gm024-contact-card')"), isTrue);
    expect(cards.contains('radius: 14'), isTrue);
  });

  test('GM-025: Sinema Parti AMOLED siyah değil, temalı zemin + cam paneller', () {
    final c = _src('lib/screens/watch_party_screen.dart');
    expect(c.contains('juzzioWatchPartyBackdrop()'), isTrue);
    expect(c.contains('Color.lerp(JuzzioCallColors.depth.last, Colors.black, 0.3'), isFalse);
    expect(c.contains('JuzzioLiquidGlass('), isTrue);
  });

  group('GM-026: arama kutuları', () {
    test('iç kenarlık yok; Material çipler yerine cam çip', () {
      final c = _src('lib/screens/message_search_page.dart');
      expect(c.contains('enabledBorder: InputBorder.none'), isTrue);
      expect(c.contains('FilterChip('), isFalse);
      expect(c.contains('ActionChip('), isFalse);
      expect(_src('lib/widgets/juzzio_settings_kit.dart').contains("ValueKey('gm026-settings-search')"), isTrue);
    });
    testWidgets('cam çip dokununca geri çağırır', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: JuzzioSearchChip(icon: Icons.photo, label: 'Fotoğraf', selected: true, onTap: () => taps++))),
      ));
      await tester.tap(find.text('Fotoğraf'));
      expect(taps, 1);
    });
  });

  group('GM-027: yönetici PIN girişi', () {
    late JuzzioAdminPin pins;
    setUp(() {
      pins = JuzzioAdminPin.instance..debugStore = <String, String>{};
    });
    tearDown(() => pins.debugStore = null);

    test('PIN kullanıcıya bağlı; doğru PIN açar, yanlış PIN açmaz', () async {
      await pins.setPin('u1', '2468', rounds: 10);
      expect(await pins.hasPin('u1'), isTrue);
      expect(await pins.hasPin('u2'), isFalse);
      expect(await pins.pinLength('u1'), 4);
      expect(await pins.verify('u1', '2468'), isTrue);
      expect(await pins.verify('u2', '2468'), isFalse);
      expect(await pins.verify('u1', '1111'), isFalse);
      expect(await pins.failures('u1'), 1);
      expect(await pins.verify('u1', '2468'), isTrue);
      expect(await pins.failures('u1'), 0);
      expect(pins.debugStore!.values.join().contains('2468'), isFalse, reason: 'PIN açık metin saklanmaz');
    });

    test('5 hatalı denemede PIN silinir ve kilit bildirilir', () async {
      await pins.setPin('u1', '13579', rounds: 10);
      for (var i = 0; i < JuzzioAdminPin.maxAttempts - 1; i++) {
        expect(await pins.verify('u1', '0000'), isFalse);
        expect(pins.lockedOut, isFalse);
      }
      expect(await pins.verify('u1', '0000'), isFalse);
      expect(pins.lockedOut, isTrue);
      expect(await pins.hasPin('u1'), isFalse);
    });

    test('geçersiz PIN reddedilir', () async {
      expect(() => pins.setPin('u1', '12', rounds: 10), throwsArgumentError);
    });

    test('panel girişi Kilitli sohbetler ile aynı PIN ekranını kullanır', () {
      final c = _src('lib/screens/admin_panel_screen.dart');
      expect(c.contains('showJuzzioPinPad('), isTrue);
      expect(c.contains('JuzzioAdminPin.instance'), isTrue);
      expect(c.contains('forgetAdminToken()'), isTrue);
    });
  });

  group('GM-032: aynı renkli temalar', () {
    test('14 benzersiz tema; kaldırılanlar en yakın temaya taşınır', () {
      expect(kJuzzioAuroraPalettes.length, 14);
      final ids = kJuzzioAuroraPalettes.map((p) => p.id).toSet();
      for (final gone in kJuzzioRemovedThemeAliases.keys) {
        expect(ids.contains(gone), isFalse, reason: gone);
        expect(juzzioAuroraPaletteById(gone).id, kJuzzioRemovedThemeAliases[gone]);
      }
    });
  });

  group('GM-033: tema önizleme', () {
    test('etiket "Ad | Parlaklık" biçiminde', () {
      expect(juzzioThemeSettingLabel('Gece Mavisi', 'Parlaklık'), 'Gece Mavisi | Parlaklık');
    });
    test('uygulama temaları listesi tüm temaları içerir; ayrı sohbet teması sayfası yok', () {
      expect(juzzioAppThemePreviewItems().length, kJuzzioAuroraPalettes.length);
      final s = _src('lib/screens/settings_suite_screens.dart');
      expect(s.contains('class JuzzioChatThemeCustomizerPage'), isFalse);
      expect(s.contains("'Tüm sohbet temaları ve önizleme', 'All chat themes"), isFalse);
      final g = _src('lib/widgets/glass/juzzio_theme_gallery.dart');
      expect(g.contains('JuzzioThemePreviewPage.open(context, it.key, chat: true, items: items)'), isTrue);
      final pv = _src('lib/screens/theme_preview_page.dart');
      for (final k in ['gm033-brightness', 'gm033-glass', 'gm033-apply', 'gm033-theme-pager']) {
        expect(pv.contains(k), isTrue, reason: k);
      }
    });
  });
}
