// JUZZIO v1.2.4 — çevrimdışı öncelikli çalışma, sohbet kaydırma, bildirimler, galeri, dil senkronu,
// yönetici paneli, kilitli sohbet, tepkiler, iletme, yapımcı videosu
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_ui_sync.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/screens/admin_god_tab.dart' show juzzioMergeReleaseHistory;
import 'package:juzzio/services/juzzio_chat_lock.dart';
import 'package:juzzio/services/juzzio_gallery_saver.dart';
import 'package:juzzio/services/juzzio_net.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_consent.dart';
import 'package:juzzio/widgets/juzzio_message_cards.dart';
import 'package:juzzio/widgets/juzzio_password_strength.dart';
import 'package:juzzio/widgets/juzzio_swipe_reply.dart';

String _src(String p) => File(p).readAsStringSync();

JuzzioMessage _msg({String? image, String? video, String? doc, String? docName, bool viewOnce = false}) => JuzzioMessage(
      id: 'abcdef1234567890',
      roomId: 'r',
      senderId: 's',
      senderName: 'S',
      messageType: image != null ? 'image' : (video != null ? 'video' : 'document'),
      sourceLang: 'tr',
      targetLang: 'en',
      originalText: '',
      translatedText: '',
      imageUrl: image,
      videoUrl: video,
      documentUrl: doc,
      documentName: docName,
      isViewOnce: viewOnce,
      createdAt: DateTime(2026, 11, 10),
    );

void main() {
  group('Çevrimdışı öncelikli', () {
    test('bağlantı türü → ağ var mı', () {
      expect(juzzioHasNetwork(const [ConnectivityResult.none]), isFalse);
      expect(juzzioHasNetwork(const [ConnectivityResult.wifi]), isTrue);
      expect(juzzioHasNetwork(const [ConnectivityResult.none, ConnectivityResult.mobile]), isTrue);
    });

    test('bağlantı gelince geri bildirim tetiklenir', () async {
      final net = JuzzioNet.instance;
      var hits = 0;
      net.addRegainHook(() async => hits++);
      final sub = net.onRegained.listen((_) {});
      net.setOnline(false);
      expect(net.online, isFalse);
      net.setOnline(true);
      await Future<void>.delayed(Duration.zero);
      expect(hits, 1);
      net.setOnline(true); // değişmedi → tekrar tetiklenmez
      await Future<void>.delayed(Duration.zero);
      expect(hits, 1);
      await sub.cancel();
    });

    test('önbellekli akışlar: aramalar, hikâyeler, arkadaşlıklar, bildirimler, görevler, Keşfet, profil sayaçları', () {
      final svc = _src('lib/services/supabase_service.dart');
      expect(svc.contains("'call_logs',"), isTrue);
      expect(svc.contains("'stories_active',"), isTrue);
      expect(svc.contains("'friendships',"), isTrue);
      expect(svc.contains('keepOnEmpty: true'), isTrue);
      expect(svc.contains('prefetchStoryMedia(list)'), isTrue);
      final social = _src('lib/services/social_service.dart');
      expect(social.contains("'notifs_live'"), isTrue);
      expect(social.contains('feedCacheName(filter, topic)'), isTrue);
      expect(social.contains("'saved_posts_full'"), isTrue);
      expect(social.contains("countsCache = 'counts_"), isTrue);
      expect(_src('lib/services/juzzio_life_service.dart').contains("'life_tasks',"), isTrue);
      final feed = _src('lib/screens/social/juzzio_global_feed.dart');
      expect(feed.contains('cachedFeedPosts('), isTrue);
      expect(feed.contains('_offlineTail()'), isTrue);
    });

    test('çevrimdışı profil düzenleme sıraya alınır; görsel yerine yükleme logosu', () {
      final svc = _src('lib/services/supabase_service.dart');
      expect(svc.contains("writeOrQueue('profile', {'t': 'profile', 'fields': fields})"), isTrue);
      expect(svc.contains('_patchCachedMyProfile'), isTrue);
      final img = _src('lib/services/juzzio_media_url.dart');
      expect(img.contains('_netWait()'), isTrue);
      expect(img.contains('onRegained'), isTrue);
    });

    test('profil müziği ve hikâye videosu önbellekten çalar', () {
      expect(_src('lib/widgets/profile_extras.dart').contains('juzzioSetMusicSource(p, url)'), isTrue);
      expect(_src('lib/widgets/media_viewer.dart').contains('VideoPlayerController.file(cached)'), isTrue);
    });
  });

  group('Sohbet kaydırma', () {
    test('yatay kaydırma yalnız belirgin yatay hareketi kabul eder', () {
      expect(juzzioIsHorizontalIntent(const Offset(20, 2)), isTrue);
      expect(juzzioIsHorizontalIntent(const Offset(20, 15)), isFalse);
      expect(juzzioIsHorizontalIntent(const Offset(4, 30)), isFalse);
      expect(JuzzioDirectionalHorizontalDrag(), isA<HorizontalDragGestureRecognizer>());
    });

    test('eski sayfa yüklenince zorla aşağı inilmez; önbellek yeniden yayınlanmaz', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains('isNewer'), isTrue);
      expect(c.contains('skipCache: growing'), isTrue);
      expect(c.contains('ValueListenableBuilder<bool>('), isTrue);
      expect(_src('lib/services/supabase_service.dart').contains('if (skipCache) return;'), isTrue);
    });
  });

  group('Galeriye kaydetme', () {
    test('fotoğraf/video/belge hedefi; tek görüntülemelik kaydedilmez', () {
      final img = juzzioGalleryTarget(_msg(image: 'https://x/a/b.png'))!;
      expect(img.kind, 'image');
      expect(img.mime, 'image/png');
      final vid = juzzioGalleryTarget(_msg(video: 'https://x/v.mp4'))!;
      expect(vid.kind, 'video');
      final doc = juzzioGalleryTarget(_msg(doc: 'https://x/d', docName: 'rapor.pdf'))!;
      expect(doc.kind, 'document');
      expect(doc.mime, 'application/pdf');
      expect(doc.name, 'rapor.pdf');
      expect(juzzioGalleryTarget(_msg(image: 'https://x/a.jpg', viewOnce: true)), isNull);
    });
  });

  group('Tepkiler', () {
    test('emojiye göre gruplanır, en çok önce; kişi başı tek tepki', () {
      final g = juzzioGroupReactions({'a': '❤️', 'b': '😂', 'c': '❤️', 'd': ''});
      expect(g.keys.first, '❤️');
      expect(g['❤️'], ['a', 'c']);
      expect(g['😂'], ['b']);
      expect(g.values.expand((e) => e).length, 3);
    });

    test('iletilen gönderi/hikâye bağlantısı ayrıştırılır', () {
      expect(juzzioSharedRef('📌 @a: x (juzzio://post/0f8fad5b-d9cb-469f-a165-70867728950e)'), ('post', '0f8fad5b-d9cb-469f-a165-70867728950e'));
      expect(juzzioSharedRef('juzzio://story/1234abcd'), ('story', '1234abcd'));
      expect(juzzioSharedRef('merhaba'), isNull);
    });
  });

  group('Kilitli sohbet', () {
    setUp(() => JuzzioChatLock.memoryStore = <String, String>{});
    tearDown(() => JuzzioChatLock.memoryStore = null);

    test('PIN oluşturmak kilidi açmaz; açık kalma süresi sınırlı', () async {
      final lock = JuzzioChatLock.instance;
      await lock.reset();
      await lock.setPin('482913');
      expect(lock.isUnlocked, isFalse);
      expect(await lock.unlock('482913'), isTrue);
      expect(lock.isUnlocked, isTrue);
      final t0 = DateTime.now();
      expect(juzzioChatUnlockValid(true, t0, t0.add(const Duration(minutes: 1)), JuzzioChatLock.unlockGrace), isTrue);
      expect(juzzioChatUnlockValid(true, t0, t0.add(const Duration(minutes: 3)), JuzzioChatLock.unlockGrace), isFalse);
      lock.relock();
      expect(lock.isUnlocked, isFalse);
      await lock.reset();
    });
  });

  group('Yönetici paneli', () {
    test('geçmiş paketler birleşir, sıralanır, tekrar etmez', () {
      final merged = juzzioMergeReleaseHistory(
        [
          {'version_name': '1.2.3', 'version_code': 123, 'id': 'srv'},
        ],
        kJuzzioBundledReleaseNotes,
      );
      final codes = merged.map((r) => r['version_code']).toList();
      expect(codes.first, greaterThanOrEqualTo(124));
      expect(codes.toSet().length, codes.length);
      expect(merged.firstWhere((r) => r['version_code'] == 123)['id'], 'srv');
    });

    test('yasal paket kullanıcı adıyla; sürüm seçici; profil başlığı', () {
      final god = _src('lib/screens/admin_god_tab.dart');
      expect(god.contains("'admin_legal_export_by_username'"), isTrue);
      expect(god.contains('_minBuildPicker(fg)'), isTrue);
      expect(_src('supabase/juzzio_database.sql').contains('FUNCTION public.admin_legal_export_by_username'), isTrue);
      expect(_src('lib/screens/admin_panel_screen.dart').contains("'Hoşgeldin! \$_welcomeFullName'"), isTrue);
    });
  });

  group('Arayüz ve kayıt', () {
    test('dil değişimi tüm ekranları yeniden çizer', () {
      expect(JuzzioUiSync.shouldRebuild(lang: 'en', revision: 1, lastLang: 'tr', lastRevision: 1), isTrue);
      expect(JuzzioUiSync.shouldRebuild(lang: 'tr', revision: 2, lastLang: 'tr', lastRevision: 1), isTrue);
      expect(JuzzioUiSync.shouldRebuild(lang: 'tr', revision: 1, lastLang: 'tr', lastRevision: 1), isFalse);
      expect(_src('lib/main.dart').contains('JuzzioUiSync.attach();'), isTrue);
    });

    test('onay metni otomatik çeviri uyarısı', () {
      expect(juzzioConsentIsMachineTranslated('tr'), isFalse);
      expect(juzzioConsentIsMachineTranslated('en-US'), isFalse);
      expect(juzzioConsentIsMachineTranslated('de'), isTrue);
      expect(juzzioConsentIsMachineTranslated('ar'), isTrue);
    });

    test('şifre gücü', () {
      expect(juzzioPasswordScore(''), 0);
      expect(juzzioPasswordScore('123456'), 1);
      expect(juzzioPasswordScore('abcdefgh'), lessThanOrEqualTo(2));
      expect(juzzioPasswordScore('Juzzio-Kuantum-2026!'), lessThanOrEqualTo(1)); // "juzzio" içerir
      expect(juzzioPasswordScore('Kar!Tanesi-Mavi9'), 4);
    });

    testWidgets('şifre gücü çubuğu hatasız çizilir', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: JuzzioPasswordStrengthBar(password: 'Kar!Tanesi-Mavi9'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    test('cinsiyet simgeleri, durum şeridi, bildirimler, yapımcı videosu', () {
      final m = _src('lib/main.dart');
      expect(m.contains('Icons.female_rounded'), isTrue);
      expect(m.contains('Icons.male_rounded'), isTrue);
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains("realFriends.where((f) => !storyOwners.containsKey(f.id))"), isFalse);
      expect(c.contains('_showReactionsWho(p, msg)'), isTrue);
      expect(c.contains("action(Icons.delete_outline_rounded, app.trEn('Sil', 'Delete', 'Löschen')"), isTrue);
      expect(c.contains('_queueLocalMedia(roomId'), isTrue);
      final kt = _src('android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt');
      expect(kt.contains('NotificationCompat.MessagingStyle'), isTrue);
      expect(kt.contains('SEMANTIC_ACTION_MARK_AS_READ'), isTrue);
      expect(File('assets/creator/juzzio_creator_reel.mp4').lengthSync(), lessThan(4 * 1024 * 1024));
      expect(_src('pubspec.yaml').contains('assets/creator/juzzio_creator_reel.mp4'), isTrue);
    });

    test('çevrimdışı son görülme gerçek değer', () {
      expect(_src('lib/services/supabase_service.dart').contains("'presence_\${userId"), isTrue);
    });
  });

  test('Sürüm notu 1.2.4', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.4');
    expect(n.versionName, '1.2.4');
    expect(n.versionCode, 124);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });

  test('v1.2.5: güncelleme doğrulaması önbellek beklemez; duyuru yayından sonra', () {
    final core = _src('lib/core/app_theme_and_locale.dart');
    expect(core.contains('_otaSignedSecurity'), isTrue);
    expect(core.contains('/releases/download/v\$_otaRemoteVersion/version.json'), isTrue);
    expect(core.contains('_waitForOtaVerification()'), isTrue);
    final ci = _src('.github/workflows/android-ci.yml');
    expect(ci.indexOf('Juzzio Topluluğu sürüm duyurusu'), greaterThan(ci.indexOf('Tüm kullanıcılara anında güncelleme bildirimi')));
    expect(ci.contains('.apk.sha256" version.json)'), isTrue);
    expect(_src('scripts/release_meta.py').contains('sec["build"] = int(data["build"])'), isTrue);
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.5');
    expect(n.versionName, '1.2.5');
    expect(n.versionCode, 125);
  });

  test('JuzzioConsentState hâlâ iki kutu', () {
    expect(const JuzzioConsentState().requiredAccepted, isFalse);
  });
}
