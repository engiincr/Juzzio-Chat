// JUZZIO v1.2.9 — UTF-16 güvenliği, dosya güvenliği, bağlantı riski, sistem sağlığı, arama kalitesi,
// GIF çıkartmaları, müzik kartı, Ay evresi, mesaj istekleri, yasal rapor, neler yeni videosu
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/juzzio_duration_format.dart';
import 'package:juzzio/core/juzzio_intro.dart';
import 'package:juzzio/core/juzzio_server_errors.dart';
import 'package:juzzio/core/juzzio_text_safety.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/screens/admin_legal_report.dart';
import 'package:juzzio/services/juzzio_features_service.dart' show JuzzioDmRequestState;
import 'package:juzzio/services/juzzio_file_guard.dart';
import 'package:juzzio/services/juzzio_health_monitor.dart';
import 'package:juzzio/services/juzzio_legal_package.dart';
import 'package:juzzio/services/supabase_service.dart' show JuzzioIceServer;
import 'package:juzzio/widgets/juzzio_chat_music.dart';
import 'package:juzzio/widgets/juzzio_gif_stickers.dart';
import 'package:juzzio/widgets/juzzio_moon_phase.dart';
import 'package:juzzio/widgets/juzzio_rich_text.dart';
import 'package:juzzio/widgets/motion/juzzio_send_fx.dart' show kJuzzioTextSendFlight;

String _src(String p) => File(p).readAsStringSync();
Uint8List _b(List<int> v) => Uint8List.fromList(v);

void main() {
  group('UTF-16 güvenliği (çökme düzeltmesi)', () {
    test('emoji ile başlayan adın baş harfi bölünmez', () {
      expect(juzzioInitial('😀 Ali'), '😀');
      expect(juzzioIsWellFormed(juzzioInitial('😀 Ali')), isTrue);
      expect(juzzioInitial('  '), '?');
      expect(juzzioInitial('ömer'), 'Ö');
    });
    test('kısaltma vekil çiftini ve ZWJ birleşimini bölmez', () {
      const s = 'ab😀cd';
      expect(juzzioIsWellFormed(juzzioSafeCut(s, 3)), isTrue);
      expect(juzzioSafeCut(s, 3), 'ab');
      expect(juzzioIsWellFormed(juzzioEllipsize('👨‍👩‍👧 aile', 3)), isTrue);
    });
    test('yalnız vekil U+FFFD olur', () {
      final bad = String.fromCharCodes([0x41, 0xD83D, 0x42]);
      expect(juzzioIsWellFormed(bad), isFalse);
      expect(juzzioWellFormed(bad), 'A�B');
    });
  });

  group('Dosya güvenliği', () {
    test('betik ve çalıştırılabilir uzantılar engellenir', () {
      for (final n in ['shell.php', 'x.jsp', 'a.exe', 'b.apk', 'c.html', 'd.svg', 'e.js']) {
        final c = juzzioCheckFile(name: n, head: _b([1, 2, 3, 4]), size: 4, kind: JuzzioUploadKind.document);
        expect(c.ok, isFalse, reason: n);
      }
    });
    test('gizli çift uzantı ve içerik uyuşmazlığı yakalanır', () {
      expect(juzzioCheckFile(name: 'fatura.pdf.exe', head: _b([1, 2]), size: 2, kind: JuzzioUploadKind.document).ok, isFalse);
      // "resim.jpg" ama içeriği Windows çalıştırılabilir (MZ)
      final mz = juzzioCheckFile(name: 'resim.jpg', head: _b([0x4D, 0x5A, 0x90, 0x00]), size: 4, kind: JuzzioUploadKind.image);
      expect(mz.ok, isFalse);
    });
    test('gerçek PNG geçer, dosya adı temizlenir, tehlikeli MIME düşürülür', () {
      final png = juzzioCheckFile(name: 'a.png', head: _b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), size: 8, kind: JuzzioUploadKind.image);
      expect(png.ok, isTrue);
      expect(juzzioCleanFileName('../../etc/<x>.pdf'), isNot(contains('/')));
      expect(juzzioSafeUploadMime('text/html'), 'application/octet-stream');
      expect(juzzioSafeUploadMime('image/svg+xml'), 'application/octet-stream');
    });
  });

  group('Bağlantı riski', () {
    test('IP adresi, kullanıcı bilgisi ve kısaltıcı işaretlenir', () {
      expect(juzzioLinkRisks(Uri.parse('https://192.168.1.4/login')), contains('ip_host'));
      expect(juzzioLinkRisks(Uri.parse('https://paypal.com@kotu.site/')), contains('userinfo'));
      expect(juzzioLinkRisks(Uri.parse('https://juzzio.app/')), isEmpty);
    });
    test('ilk web bağlantısı (e-posta/telefon değil)', () {
      expect(juzzioFirstLink('mail: a@b.com site www.juzzio.app.'), 'https://www.juzzio.app');
      expect(juzzioFirstLink('ara 0532 123 45 67'), isNull);
    });
  });

  group('Sistem sağlığı ve arama', () {
    test('genel durum en kötü olanı yansıtır', () {
      expect(juzzioOverallHealth([JuzzioHealthState.ok, JuzzioHealthState.degraded]), JuzzioHealthState.degraded);
      expect(juzzioOverallHealth([JuzzioHealthState.ok, JuzzioHealthState.down]), JuzzioHealthState.down);
      expect(juzzioOverallHealth([JuzzioHealthState.unknown]), JuzzioHealthState.unknown);
      expect(juzzioDeepgramState('ok'), JuzzioHealthState.ok);
      expect(juzzioDeepgramState('invalid_key'), JuzzioHealthState.down);
    });
    test('TURN listesi yalnız geçerli adresleri alır; yedek gömülü', () {
      final l = JuzzioIceServer.parseList([
        {'urls': ['turn:free.expressturn.com:3478?transport=udp', 'javascript:alert(1)'], 'username': 'u', 'credential': 'c'},
        {'urls': 'http://kotu.site'},
      ]);
      expect(l.length, 1);
      expect(l.first.urls, ['turn:free.expressturn.com:3478?transport=udp']);
      expect(JuzzioIceServer.embeddedBackup(), isNotEmpty);
    });
    test('sunucu hata kodu okunur metne çevrilir (P0001 yerine)', () {
      expect(juzzioServerErrorText('PostgrestException(message: message_request_limit, code: P0001)'), isNotNull);
      expect(juzzioServerErrorText('PostgrestException(message: private_account_friend_required)'), isNotNull);
      expect(juzzioServerErrorText('tamamen bilinmeyen'), isNull);
    });
  });

  group('GIF çıkartmaları', () {
    test('en az 40 benzersiz, sözsüz çıkartma', () {
      expect(kJuzzioGifs.length, greaterThanOrEqualTo(40));
      expect(kJuzzioGifs.map((g) => g.id).toSet().length, kJuzzioGifs.length);
    });
    test('belirteç gidiş-dönüş ve önizleme', () {
      final t = juzzioGifToken('sleepy');
      expect(juzzioGifFromText(t)?.emoji, '😴');
      expect(juzzioGifFromText('[[jgif:yok]]'), isNull);
      expect(juzzioGifFromText('selam [[jgif:sleepy]]'), isNull);
      expect(juzzioGifPreview(t), contains('GIF'));
    });
    test('kendi dilinde aranır', () {
      final app = JuzzioAppController.instance;
      expect(juzzioSearchGifs('', app).length, kJuzzioGifs.length);
      expect(juzzioSearchGifs('😴', app).map((g) => g.id), contains('sleepy'));
    });
  });

  group('Sohbette müzik', () {
    test('gidiş-dönüş; yalnız Apple önizleme ve https kabul edilir', () {
      const t = JuzzioSharedTrack(url: 'https://audio-ssl.itunes.apple.com/a/b.m4a', title: 'Şarkı 🎵', artist: 'Sanatçı', coverUrl: 'https://is1-ssl.mzstatic.com/x.jpg');
      final back = juzzioMusicFromText(juzzioMusicToken(t));
      expect(back?.title, 'Şarkı 🎵');
      expect(back?.artist, 'Sanatçı');
      const bad = JuzzioSharedTrack(url: 'https://kotu.site/a.mp3', title: 'x');
      expect(juzzioMusicFromText(juzzioMusicToken(bad)), isNull);
      final js = base64Url.encode(utf8.encode(jsonEncode({'u': 'https://audio-ssl.itunes.apple.com/a.m4a', 't': 'x', 'c': 'javascript:alert(1)'}))).replaceAll('=', '');
      expect(juzzioMusicFromText('[[jmusic:$js]]'), isNull);
      expect(juzzioMusicPreview(juzzioMusicToken(t)), startsWith('🎵'));
    });
  });

  group('Ay evresi', () {
    test('bilinen yeni ay ve dolunay', () {
      final nm = juzzioMoonPhase(DateTime.utc(2024, 4, 8, 18, 21));
      expect(nm < 0.03 || nm > 0.97, isTrue);
      final fm = juzzioMoonPhase(DateTime.utc(2024, 4, 23, 23, 49));
      expect((fm - 0.5).abs() < 0.03, isTrue);
      expect(juzzioMoonPhaseIndex(fm), 4);
      expect(juzzioMoonIllumination(0.5), closeTo(1, 1e-9));
      expect(juzzioMoonIllumination(0), closeTo(0, 1e-9));
    });
  });

  group('Mesaj istekleri', () {
    test('3 hak bitince veya istek silinince yazma alanı gizlenir', () {
      final a = JuzzioDmRequestState.fromMap({'state': 'outgoing', 'username': 'x', 'remaining': 2, 'blocked': false});
      expect(a.composerHidden, isFalse);
      final b = JuzzioDmRequestState.fromMap({'state': 'outgoing', 'remaining': 0, 'blocked': true});
      expect(b.composerHidden, isTrue);
      final c = JuzzioDmRequestState.fromMap({'state': 'incoming', 'spam': true});
      expect(c.isIncoming && c.spam, isTrue);
      expect(JuzzioDmRequestState.none.composerHidden, isFalse);
    });
    test('sohbet ekranı bant, istek/spam kutusu ve v2 yanıtını kullanır', () {
      final s = _src('lib/screens/chat_screen.dart');
      expect(s.contains('_buildOutgoingRequestWaitBar'), isTrue);
      expect(s.contains("seg(1, appCtrl.trEn('Spam kutusu'"), isTrue);
      expect(_src('lib/services/juzzio_features_service.dart').contains("'respond_message_request_v2'"), isTrue);
    });
  });

  group('Yasal rapor (yalnız kurucu)', () {
    test('okunur rapor dürüst sınırları içerir', () {
      final txt = juzzioLegalReportText({
        'format': 'juzzio_legal_bundle_v2',
        'reason': 'Savcılık yazısı 2026/1',
        'integrity_sha256': 'abc',
        'profile': {'username': 'deneme', 'id': 'u1'},
        'account': {'email': 'a@b.c', 'phone': '+90'},
        'login_events': [
          {'at': '2026-11-15', 'ip': '1.2.3.4', 'country': 'TR', 'model': 'Pixel'}
        ],
        'messages': [
          {'at': 't', 'type': 'text', 'room_id': 'r', 'encrypted': true},
          {'at': 't', 'type': 'text', 'room_id': 'g', 'encrypted': false, 'text': 'merhaba'},
        ],
      });
      expect(txt, contains('@deneme'));
      expect(txt, contains('1.2.3.4'));
      expect(txt, contains('IMEI toplanmaz'));
      expect(txt, contains('uçtan uca şifreli — içerik sunucuda yok'));
      expect(txt, contains('merhaba'));
    });
    test('v3: dondurma arşivi, gruplar, FCM, yaşam döngüsü, HTS, şikâyet kanıtı, imkânsızlık beyanı', () {
      final txt = juzzioLegalReportText({
        'format': 'juzzio_legal_bundle_v3',
        'profile': {'username': 'x'},
        'legal_hold': {'since': 'a', 'until': 'b', 'reason': 'Savcılık 2026/9'},
        'preserved': [
          {'kind': 'messages', 'op': 'UPDATE', 'row_id': 'm1', 'data': {'encrypted': true}},
          {'kind': 'posts', 'op': 'DELETE', 'row_id': 'p1', 'data': {'caption': 'silinen gönderi'}},
        ],
        'groups': [
          {'title': 'Grup', 'founder': 'x', 'is_founder': true, 'role': 'owner', 'member_count': 4}
        ],
        'push_tokens': [
          {'platform': 'android', 'token': 'fcm-abc'}
        ],
        'lifecycle': [
          {'event': 'account_deleted', 'ip': '203.0.113.5'}
        ],
        'call_traffic': [
          {'caller': 'x', 'callee': 'y', 'type': 'voice', 'duration_sec': 42}
        ],
        'report_evidence': [
          {'reporter': 'y', 'evidence': {'messages': [
            {'sender': 'x', 'text': 'tehdit metni', 'reported': true}
          ]}}
        ],
      });
      expect(txt, contains('Savcılık 2026/9'));
      expect(txt, contains('[uçtan uca şifreli — okunamaz]'));
      expect(txt, contains('silinen gönderi'));
      expect(txt, contains('fcm-abc'));
      expect(txt, contains('account_deleted'));
      expect(txt, contains('@x → @y'));
      expect(txt, contains('tehdit metni'));
      expect(txt, contains('ŞİKÂYET EDİLEN'));
      expect(txt, contains(juzzioTechnicalImpossibilityStatement));
    });
  });

  group('Neler yeni videosu', () {
    test('yalnız 1.2.8 ve öncesinden güncelleyenlere bir kez', () {
      expect(juzzioShouldShowWhatsNewVideo(previousVersion: '1.2.8', currentVersion: '1.2.9', alreadySeen: false), isTrue);
      expect(juzzioShouldShowWhatsNewVideo(previousVersion: '1.1.0', currentVersion: '1.2.9', alreadySeen: false), isTrue);
      expect(juzzioShouldShowWhatsNewVideo(previousVersion: '1.2.8', currentVersion: '1.2.9', alreadySeen: true), isFalse);
      expect(juzzioShouldShowWhatsNewVideo(previousVersion: '', currentVersion: '1.2.9', alreadySeen: false), isFalse);
      expect(juzzioShouldShowWhatsNewVideo(previousVersion: '1.2.9', currentVersion: '1.3.0', alreadySeen: false), isFalse);
      expect(File('assets/intro/juzzio_whatsnew_tr.mp4').existsSync(), isTrue);
      expect(File('assets/intro/juzzio_whatsnew_en.mp4').existsSync(), isTrue);
      expect(_src('pubspec.yaml').contains('assets/intro/juzzio_whatsnew_tr.mp4'), isTrue);
    });
  });

  group('Hata düzeltmeleri (kaynak denetimi)', () {
    test('metin gönderimi emoji gibi "Pop" ile gelir; sarı çizgili uçuş kapalı', () {
      expect(kJuzzioTextSendFlight, isFalse);
      expect(_src('lib/screens/chat_screen.dart').contains("pop: bigEmoji || (isMe && msg.messageType == 'text')"), isTrue);
    });
    test('doğum günü kutlaması balondan bağımsız; yalnız sohbetten çıkınca durur', () {
      final fx = _src('lib/widgets/motion/juzzio_birthday_fx.dart');
      expect(fx.contains('class JuzzioBirthdayFxHost'), isTrue);
      final chat = _src('lib/screens/chat_screen.dart');
      final leave = chat.substring(chat.indexOf('void _leaveConversation()'), chat.indexOf('void _openConversation('));
      expect(leave.contains('JuzzioBirthdayFxHost.stop()'), isTrue);
      final back = chat.substring(chat.indexOf('void _handleSystemBack()'), chat.indexOf('void _handleSystemBack()') + 900);
      expect(back.contains('JuzzioBirthdayFxHost'), isFalse);
    });
    test('hikâye görüntüleyici hava katmanını gizler; varsayılan tema Gece Mavisi', () {
      expect(_src('lib/screens/chat_screen.dart').contains('JuzzioAmbienceHide(child: JuzzioStoryViewerModal('), isTrue);
      expect(_src('lib/core/app_theme_and_locale.dart').contains("_defaultGlassPaletteId = 'ocean'"), isTrue);
    });
  });

  group('Süre birimleri her dilde', () {
    test('dk/sn yalnız Türkçede', () {
      expect(juzzioFormatDuration(125, 'tr'), '2 dk 05 sn');
      expect(juzzioFormatDuration(125, 'en'), '2 min 05 s');
      expect(juzzioFormatDuration(125, 'en-US'), '2 min 05 s');
      expect(juzzioFormatDuration(125, 'de'), '2 Min. 05 Sek.');
      expect(juzzioFormatDuration(125, 'ja'), '2分05秒');
      expect(juzzioFormatDuration(3725, 'en'), '1 h 02 min');
      expect(juzzioFormatDuration(9, 'en'), '9 s');
      expect(juzzioFormatDuration(125, 'xx'), '2:05'); // bilinmeyen dil: evrensel biçim
      expect(juzzioFormatDuration(125, 'en').contains('dk'), isFalse);
      expect(juzzioSecondsLabel('10', 'tr'), '10 sn');
      expect(juzzioSecondsLabel('10', 'en'), '10 s');
    });
  });

  group('Yasal teslim paketi (PDF + AES-256 ZIP)', () {
    test('üç adli alan zorunlu; gerekçe satırı', () {
      expect(const JuzzioLegalRequestInfo(authority: 'İstanbul 1. Sulh Ceza Hâkimliği', caseNo: '', purpose: 'HTS').isComplete, isFalse);
      const ok = JuzzioLegalRequestInfo(authority: 'İstanbul 1. Sulh Ceza Hâkimliği', caseNo: '2026/1453 Esas', purpose: 'Trafik kaydı talebi');
      expect(ok.isComplete, isTrue);
      expect(ok.toReason(), contains('2026/1453 Esas'));
    });
    test('şifre 12 hane, her talepte farklı, karışan karakter yok', () {
      final a = juzzioLegalPassword(), b = juzzioLegalPassword();
      expect(a.length, 12);
      expect(a == b, isFalse);
      expect(RegExp(r'^[A-HJ-NP-Za-km-z2-9]{12}$').hasMatch(a), isTrue);
      expect(juzzioLegalPassword(random: Random(1)), juzzioLegalPassword(random: Random(1)));
    });
    test('ZIP şifreli: doğru şifreyle açılır, içerik düz metin olarak görünmez', () {
      final secret = utf8.encode('{"gizli":"juzzio-yasal-veri-0123456789"}');
      final zip = juzzioBuildEncryptedZip({'juzzio_veri.json': secret, 'juzzio_rapor.pdf': [37, 80, 68, 70]}, 'Abc234defGHJ');
      expect(latin1.decode(zip).contains('juzzio-yasal-veri'), isFalse);
      final dec = ZipDecoder().decodeBytes(zip, password: 'Abc234defGHJ');
      expect(dec.files.map((f) => f.name).toSet(), {'juzzio_veri.json', 'juzzio_rapor.pdf'});
      expect(utf8.decode(dec.findFile('juzzio_veri.json')!.content as List<int>), utf8.decode(secret));
      expect(() => juzzioBuildEncryptedZip({'a': [1]}, 'kisa'), throwsArgumentError);
    });
    test('SHA256SUMS biçimi', () {
      final sums = juzzioSha256Sums({'a.txt': utf8.encode('abc')});
      expect(sums, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  a.txt\n');
    });
    test('RFC 3161 isteği ve yanıt denetimi', () {
      final req = juzzioTsaRequest(List<int>.filled(32, 7));
      expect(req.length, 59);
      expect(req.sublist(0, 2), [0x30, 0x39]);
      expect(req.sublist(req.length - 3), [0x01, 0x01, 0xff]);
      expect(() => juzzioTsaRequest([1, 2, 3]), throwsArgumentError);
      // granted + belirteç
      expect(juzzioTsaGranted([0x30, 0x09, 0x30, 0x03, 0x02, 0x01, 0x00, 0x30, 0x02, 0x05, 0x00]), isTrue);
      // rejection (2)
      expect(juzzioTsaGranted([0x30, 0x05, 0x30, 0x03, 0x02, 0x01, 0x02]), isFalse);
      expect(juzzioTsaGranted([1, 2, 3]), isFalse);
    });
    test('IP toplama, genel IP ayrımı ve servis sağlayıcı çözümleme', () {
      final b = {
        'login_events': [
          {'ip': '88.240.1.5'},
          {'ip': '88.240.1.5'},
          {'ip': '192.168.1.9'}
        ],
        'devices': [
          {'last_ip': '2a02:ff0::1'}
        ],
        'lifecycle': [
          {'ip': ''}
        ],
      };
      expect(juzzioCollectIps(b), ['192.168.1.9', '2a02:ff0::1', '88.240.1.5']);
      expect(juzzioIsPublicIp('88.240.1.5'), isTrue);
      expect(juzzioIsPublicIp('192.168.1.9'), isFalse);
      expect(juzzioIsPublicIp('100.64.0.1'), isFalse);
      expect(juzzioIsPublicIp('fe80::1'), isFalse);
      expect(juzzioIsPublicIp('999.1.1.1'), isFalse);
      expect(
          juzzioIspFromRipe({
            'data': {
              'asns': [
                {'asn': 9121, 'holder': 'TTNET Turk Telekomunikasyon'}
              ]
            }
          }),
          'AS9121 — TTNET Turk Telekomunikasyon');
      expect(juzzioIspFromRipe({'data': {'asns': []}}), isNull);
    });
    test('özet tablo: hesap, IP sayısı ve şifreleme uyarısı', () {
      final rows = juzzioLegalSummary({
        'profile': {'username': 'x', 'id': 'u1'},
        'login_events': [
          {'ip': '1.1.1.1'},
          {'ip': '8.8.8.8'}
        ],
        'messages': [
          {'encrypted': true},
          {'encrypted': false}
        ],
      });
      final m = {for (final r in rows) r.key: r.value};
      expect(m['İncelenen hesap'], '@x');
      expect(m['Benzersiz IP adresi sayısı'], '2');
      expect(m['Mesaj kaydı (üst veri)'], contains('1 tanesi uçtan uca şifreli'));
      expect(m['Kritik uyarı'], contains('uçtan uca şifreli'));
    });
    test('PDF varlıkları ve antet logosu ayrı dosya (uygulama logosuna dokunulmaz)', () {
      expect(File('assets/images/pdf_logo.png').existsSync(), isTrue);
      expect(File('assets/fonts/pdf/LiberationSans-Regular.ttf').existsSync(), isTrue);
      final pub = _src('pubspec.yaml');
      for (final w in ['pdf:', 'archive:', 'assets/images/pdf_logo.png', 'assets/fonts/pdf/LiberationSans-Bold.ttf']) {
        expect(pub.contains(w), isTrue, reason: w);
      }
      final pdf = _src('lib/services/juzzio_legal_pdf.dart');
      expect(pdf.contains('juzzio_logo.png\','), isFalse);
      expect(pdf.contains('Bu belge Juzzio Sistemleri tarafından resmi makamların talebi üzerine otomatik olarak oluşturulmuştur.'), isTrue);
      expect(pdf.contains('Uçtan uca şifreleme sebebiyle birebir sohbet içerikleri sunucuda barındırılmamakta ve okunamamaktadır.'), isTrue);
      final tab = _src('lib/screens/admin_god_tab.dart');
      expect(tab.contains('juzzioBuildEncryptedZip(files, password)'), isTrue);
      expect(tab.contains('.json\')'), isFalse, reason: 'ham JSON açık dosya olarak yazılmaz');
    });
  });

  group('Sürüm notu 1.2.9', () {
    test('var ve yasal veri işlevlerinden söz etmez', () {
      final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.9');
      expect(n.versionCode, 129);
      final all = jsonEncode(n.sections.map((k, v) => MapEntry(k, [v.reason, ...v.features, ...v.fixes, ...v.security])));
      for (final w in ['IMEI', 'polis', 'police', 'jandarma', 'MİT', 'yasal dışa', 'legal export', 'IP adresleri', 'login IP']) {
        expect(all.contains(w), isFalse, reason: w);
      }
    });
  });
}
