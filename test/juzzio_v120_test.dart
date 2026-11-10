// JUZZIO v1.2.0 birim testleri — doğum günü, kanallar/topluluk, kartlar, vardiya, hikâye bildirimi
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_community.dart';
import 'package:juzzio/core/notification_text.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_message_cards.dart';
import 'package:juzzio/widgets/juzzio_motion.dart';
import 'package:juzzio/widgets/juzzio_shift_card.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('Doğum günü kutlaması', () {
    test('ifadeler algılanır (TR/EN/DE, büyük harf, aksansız)', () {
      for (final t in [
        'Happy Birthday Fikret!',
        'HAPPY BDAY 🎉',
        'Doğum günün kutlu olsun canım',
        'DOĞUM GÜNÜN KUTLU OLSUN',
        'iyi ki doğdun',
        'iyiki dogdun kanka',
        'Alles Gute zum Geburtstag',
        'hbd!',
      ]) {
        expect(juzzioIsBirthdayMessage(t), isTrue, reason: t);
      }
      for (final t in ['merhaba', 'tebrikler', 'happy new year', 'Bugün hbdx yok', '']) {
        expect(juzzioIsBirthdayMessage(t), isFalse, reason: t);
      }
    });

    test('toplam süre 4 sn, emojiler istenen sırada', () {
      expect(kJuzzioBirthdayDuration, const Duration(seconds: 7)); // v1.2.7: 4 → 7 sn
      expect(kJuzzioBirthdayEmojis, ['🌸', '🎂', '😍', '⚡', '🥳', '💖', '❤️']);
    });

    test('yalnız yeni mesajda ve bir kez oynar', () {
      final now = DateTime(2026, 11, 10, 12);
      expect(JuzzioBirthdayFx.shouldPlay('b1', now.subtract(const Duration(seconds: 3)), now), isTrue);
      expect(JuzzioBirthdayFx.shouldPlay('b2', now.subtract(const Duration(minutes: 2)), now), isFalse);
    });

    testWidgets('kutlama sahnesi ve elektrik çerçevesi hatasız çizilir', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: JuzzioBirthdayFx(
              playKey: 'w1',
              createdAt: DateTime.now(),
              child: const SizedBox(width: 180, height: 48, child: Text('Happy Birthday')),
            ),
          ),
        ),
      ));
      // v1.2.7: sahne 7 sn (3B eller + iki patlama) → tamamı oynatılır
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
    });
  });

  test('düz kalp ayrımı: ❤️‍🔥 kalp olarak çizilmez', () {
    expect(juzzioIsPlainHeart('❤️'), isTrue);
    expect(juzzioIsPlainHeart('❤'), isTrue);
    expect(juzzioIsPlainHeart('❤️‍🔥'), isFalse);
    expect(juzzioIsPlainHeart('❤️‍🩹'), isFalse);
    expect(juzzioIsPlainHeart('🌸'), isFalse);
  });

  testWidgets('tepki rozeti büyük emoji ve toplam sayı gösterir', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: JuzzioReactionBadge(messageId: 'm', counts: {'❤️‍🔥': 2, '🌸': 1}))),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('❤️‍🔥'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final t = tester.widget<Text>(find.text('🌸'));
    expect(t.style!.fontSize, greaterThanOrEqualTo(18));
  });

  // v1.2.2: uçuş kaynağında düzeltilip geri getirildi (bkz. juzzio_v122_test.dart); giriş yine gecikmesiz
  test('giriş gecikmesiz', () {
    final chat = _src('lib/screens/chat_screen.dart');
    expect(chat.contains('delay: Duration.zero,'), isTrue);
  });

  test('arama ekranı: Material ata, kalıcı seçili tepki, yeni pil tasarrufu', () {
    final s = _src('lib/screens/call_screen.dart');
    expect(s.contains('Material(type: MaterialType.transparency, child: JuzzioFloatingReactions'), isTrue);
    expect(s.contains('_controller.sendCallReaction(_callReaction)'), isTrue);
    expect(s.contains('setState(() => _callReaction = picked)'), isTrue);
    expect(s.contains('Widget _batterySaverView()'), isTrue);
    expect(s.contains('recentSegments(count: 4)'), isTrue);
  });

  test('kişi kartı çözümleme', () {
    expect(juzzioParseContactCard('👤 Kişi kartı\nFikret Yılmaz\n@fikret39'), ('Fikret Yılmaz', 'fikret39'));
    expect(juzzioParseContactCard('👤 Contact\n@ali'), ('ali', 'ali'));
    expect(juzzioParseContactCard('merhaba\n@ali'), isNull);
    expect(juzzioParseContactCard('👤 Kişi kartı\nAli'), isNull);
  });

  test('paylaşılan vardiya planı çözümleme (yıl geçişi dahil)', () {
    final sent = DateTime(2026, 11, 10, 9);
    final p = juzzioParseSharedShift('📅 Vardiya planı: 10.11–16.11 · Sabah 08-16 · 08:00–16:00 (5 gün)\nKapı 3', sent)!;
    expect(p.from, DateTime(2026, 11, 10));
    expect(p.to, DateTime(2026, 11, 16));
    expect(p.label, 'Sabah 08-16');
    expect(p.hours, '08:00–16:00');
    expect(p.days, 5);
    expect(p.note, 'Kapı 3');
    final q = juzzioParseSharedShift('📅 Shift plan: 28.12–03.01 · Day off (7 days)', DateTime(2026, 12, 20))!;
    expect(q.from, DateTime(2026, 12, 28));
    expect(q.to, DateTime(2027, 1, 3));
    expect(q.hours, '');
    expect(juzzioParseSharedShift('📅 Toplantı yarın', sent), isNull);
  });

  test('hikâye yanıt türü ve bildirim metni', () {
    expect(juzzioStoryReplyKindMeta('🌸'), {'replyKind': 'reaction', 'reaction': '🌸'});
    expect(juzzioStoryReplyKindMeta('çok güzel'), {'replyKind': 'comment'});
    expect(juzzioStoryReplyKindMeta('', hasImage: true), {'replyKind': 'media'});
    expect(juzzioParseStoryReplyPreview('storyreact|🌸'), ('react', '🌸'));
    expect(juzzioParseStoryReplyPreview('storycomment|harika'), ('comment', 'harika'));
    expect(juzzioParseStoryReplyPreview('storycomment|'), ('comment', ''));
    expect(juzzioParseStoryReplyPreview('📸 Hikâye yanıtı: x'), isNull);
  });

  test('Juzzio Topluluğu adı ve logo', () {
    expect(juzzioIsCommunityTitle('Juzzio Community'), isTrue);
    expect(juzzioIsCommunityTitle('Juzzio Topluluğu'), isTrue);
    expect(juzzioIsCommunityTitle('Benim grubum'), isFalse);
    expect(juzzioCommunityDisplayTitle('tr'), 'Juzzio Topluluğu');
    expect(juzzioCommunityDisplayTitle('en'), 'Juzzio Community');
    expect(juzzioCommunityDisplayTitle('de'), 'Juzzio Community');
    expect(kJuzzioLogoAvatar.startsWith('asset:'), isTrue);
    expect(File(kJuzzioLogoAvatar.substring(6)).existsSync(), isTrue);
    final c = JuzzioConversation.fromMap({'room_id': 'r', 'title': 'Juzzio Community', 'is_group': true, 'is_channel': true});
    expect(c.isCommunity, isTrue);
    expect(c.isChannel, isTrue);
    expect(c.avatarUrl, kJuzzioLogoAvatar);
    final g = JuzzioConversation.fromMap({'room_id': 'g', 'title': 'Aile', 'is_group': true, 'is_channel': false});
    expect(g.isCommunity, isFalse);
  });

  test('topluluk dosya türleri', () {
    expect(juzzioCommunityKindFor('/a/b.JPG'), 'image');
    expect(juzzioCommunityKindFor('klip.mp4'), 'video');
    expect(juzzioCommunityKindFor('sarki.mp3'), 'audio');
    expect(juzzioCommunityKindFor('rapor.pdf'), 'document');
  });

  test('SQL: kanal kuralı, topluluk ve sürüm duyurusu tanımlı; CI duyuruyu gönderir', () {
    final sql = _src('supabase/juzzio_database.sql');
    expect(sql.contains('COALESCE(ch.is_channel, false)'), isTrue);
    expect(sql.contains('CREATE OR REPLACE FUNCTION public.juzzio_ensure_community()'), isTrue);
    expect(sql.contains('trg_juzzio_profile_join_community'), isTrue);
    expect(sql.contains('REVOKE ALL ON FUNCTION public.juzzio_community_post_release(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated'), isTrue);
    expect(sql.contains("'storyreact|'"), isTrue);
    final ci = _src('.github/workflows/android-ci.yml');
    expect(ci.contains('juzzio_community_post_release'), isTrue);
  });

  test('ayarlar: tek gece/gündüz kontrolü, görünüm tek sayfa, ayarlar başlıklı', () {
    final core = _src('lib/core/app_theme_and_locale.dart');
    final i = core.indexOf('class JuzzioModernThemeSelector');
    expect(core.substring(i, core.indexOf('Future<void> juzzioSwitchUiLanguage', i)).contains('JuzzioSwitch('), isFalse);
    final st = _src('lib/screens/settings_suite_screens.dart');
    final a = st.indexOf('class JuzzioAppearanceSettingsPage');
    final ap = st.substring(a, st.indexOf('class JuzzioStorageSettingsPage', a));
    expect(ap.contains('JuzzioThemeModeSelector()'), isTrue);
    expect(ap.contains('JuzzioAppThemeGallery()'), isTrue);
    expect(ap.contains('JuzzioChatThemeGallery()'), isTrue);
    expect(ap.contains('setFontSizeOption'), isTrue);
    expect(ap.contains('JuzzioChatsSettingsPage()'), isFalse); // yazı boyutu artık sohbetlere atmıyor
    expect(st.contains("_groupHeader(p, appCtrl.trEn('Hesap ve güvenlik'"), isTrue);
  });

  test('sohbet içi arama ve kilitli sohbetler sayfası', () {
    final chat = _src('lib/screens/chat_screen.dart');
    expect(chat.contains("item('search_here'"), isTrue);
    expect(chat.contains('initialRoomId: scope'), isTrue);
    expect(chat.contains('JuzzioLockedChatsPage('), isTrue);
    final lp = _src('lib/screens/locked_chats_page.dart');
    expect(lp.contains('allowCreate: create'), isTrue);
  });

  test('Sürüm notu 1.2.0 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.0');
    expect(n.versionName, '1.2.0');
    expect(n.versionCode, 120);
    expect(n.sections.keys, containsAll(['tr', 'en']));
    expect(n.sections['tr']!.features.length, greaterThanOrEqualTo(15));
  });
}
