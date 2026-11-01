// JUZZIO v0.9.0 — güvenlik sertleştirmesi birim testleri
//  G13 OTA SHA-256 · G16 kırpıcı odak noktası · G12 yer tutucu koruması ·
//  G17/G35 PQ isolate eşdeğerliği · denetim C özel medya URL'leri ·
//  denetim D E2EE çeviri izni varsayılanı · G14 tercih kaydı
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/pq/juzzio_pq.dart';
import 'package:juzzio/services/juzzio_e2ee.dart';
import 'package:juzzio/services/juzzio_media_url.dart';

import 'juzzio_pq_vectors.dart';

Uint8List _hex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('G13 OTA APK bütünlüğü', () {
    const abcSha = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

    test('akış hâlinde hesaplanan SHA-256 bilinen vektörle eşleşir', () async {
      final sink = Sha256().newHashSink();
      sink.add(utf8.encode('a'));
      sink.add(utf8.encode('bc'));
      sink.close();
      final digest = (await sink.hash()).bytes;
      expect(_toHex(digest), abcSha);
      expect(JuzzioAppController.otaShaMatches(abcSha, digest), isTrue);
      expect(JuzzioAppController.otaShaMatches(abcSha.toUpperCase(), digest), isTrue);
    });

    test('tek bayt farkı reddedilir', () async {
      final digest = (await Sha256().hash(utf8.encode('abd'))).bytes;
      expect(JuzzioAppController.otaShaMatches(abcSha, digest), isFalse);
    });

    test('beklenen özet yoksa/bozuksa ASLA eşleşmez (fail-closed)', () async {
      final digest = (await Sha256().hash(utf8.encode('abc'))).bytes;
      expect(JuzzioAppController.otaShaMatches('', digest), isFalse);
      expect(JuzzioAppController.otaShaMatches('xyz', digest), isFalse);
      expect(JuzzioAppController.otaShaMatches(abcSha, digest.sublist(0, 31)), isFalse);
      expect(JuzzioAppController.normalizeSha256(' ${abcSha.toUpperCase()} '), abcSha);
      expect(JuzzioAppController.normalizeSha256('1234'), '');
    });
  });

  group('G16 kırpıcı yakınlaştırma', () {
    test('kaydırılmış görüntüde odak noktasının altındaki sahne noktası korunur', () {
      // Kullanıcı 2x yakınlaştırıp (-120, -80) kaydırmış
      final current = Matrix4.diagonal3Values(2, 2, 1)..setTranslationRaw(-120, -80, 0);
      const focal = Offset(160, 160);
      final before = MatrixUtils.transformPoint(Matrix4.inverted(current), focal);
      final next = JuzzioImageCropperModal.zoomAroundFocal(current, 3.5, focal);
      expect(next.getMaxScaleOnAxis(), closeTo(3.5, 1e-9));
      final after = MatrixUtils.transformPoint(Matrix4.inverted(next), focal);
      expect(after.dx, closeTo(before.dx, 1e-6));
      expect(after.dy, closeTo(before.dy, 1e-6));
      // Eski hata: kayma sıfırlanıyordu (translation = 0)
      expect(next.getTranslation().x, isNot(closeTo(0, 1e-6)));
    });

    test('ölçek 1.0–5.0 aralığına sınırlanır', () {
      final m = Matrix4.identity();
      expect(JuzzioImageCropperModal.zoomAroundFocal(m, 9, Offset.zero).getMaxScaleOnAxis(), closeTo(5, 1e-9));
      expect(JuzzioImageCropperModal.zoomAroundFocal(m, 0.2, Offset.zero).getMaxScaleOnAxis(), closeTo(1, 1e-9));
    });
  });

  group('G12 arayüz çevirisi yer tutucuları', () {
    test('maskele → çevir → geri aç', () {
      const src = 'Hello {name}, you have {count} messages';
      final masked = JuzzioAppController.maskUiPlaceholders(src);
      expect(masked, 'Hello __0__, you have __1__ messages');
      expect(JuzzioAppController.unmaskUiPlaceholders(src, 'Merhaba __0__, __1__ mesajın var'),
          'Merhaba {name}, {count} mesajın var');
    });

    test('bozulan çeviri kullanılmaz', () {
      const src = 'Hi {name}';
      expect(JuzzioAppController.unmaskUiPlaceholders(src, 'Merhaba'), isNull);
      expect(JuzzioAppController.unmaskUiPlaceholders(src, 'Merhaba __0__ __1__'), isNull);
      expect(JuzzioAppController.unmaskUiPlaceholders('Plain', '   '), isNull);
    });
  });

  group('G17/G35 kuantum sonrası işlemler arka plan isolate\'inde', () {
    test('ML-KEM-768 async sonuçları senkron KAT vektörleriyle bayt bayt aynı', () async {
      final seed = List<int>.generate(64, (i) => i);
      final (ek, dk) = await JuzzioPqAsync.keyPairFromSeed(seed);
      expect(_toHex(juzzioSha3_256(ek)), kMlKemEkSha3);
      expect(_toHex(juzzioSha3_256(dk)), kMlKemDkSha3);
      final (ss, ct) = await JuzzioPqAsync.encapsulate(ek, List<int>.filled(32, 7));
      expect(_toHex(ss), kMlKemSs);
      expect(_toHex(juzzioSha3_256(ct)), kMlKemCtSha3);
      expect(_toHex(await JuzzioPqAsync.decapsulate(dk, ct)), kMlKemSs);
      expect(_toHex(await JuzzioPqAsync.decapsulate(dk, _hex(kMlKemRefCt))), kMlKemRefSs);
    });

    test('ML-DSA-65 async doğrulama: geçerli imza kabul, değişmiş mesaj ret', () async {
      final pk = _hex(kMlDsaPk);
      final sig = _hex(kMlDsaSig);
      final ctx = utf8.encode(kMlDsaCtx);
      expect(await JuzzioPqAsync.verify(pk, utf8.encode(kMlDsaMsg), sig, ctx: ctx), isTrue);
      expect(await JuzzioPqAsync.verify(pk, utf8.encode('${kMlDsaMsg}x'), sig, ctx: ctx), isFalse);
    });
  });

  group('Denetim C — özel medya erişimi', () {
    const base = 'https://proj.supabase.co/storage/v1/object';

    tearDown(() {
      JuzzioMediaUrl.signerOverride = null;
      JuzzioMediaUrl.clearCache();
    });

    test('özel bucket adresleri imza gerektirir, avatar ve dış adresler gerektirmez', () {
      expect(JuzzioMediaUrl.needsSigning('$base/public/chat-media/u/r/a.jpg'), isTrue);
      expect(JuzzioMediaUrl.needsSigning('$base/public/voice-notes/u/r/a.m4a'), isTrue);
      expect(JuzzioMediaUrl.needsSigning('$base/public/stories/u/s.jpg'), isTrue);
      expect(JuzzioMediaUrl.needsSigning('$base/public/posts/u/p.jpg'), isTrue);
      expect(JuzzioMediaUrl.needsSigning('$base/sign/reels/u/r.mp4?token=x'), isTrue);
      expect(JuzzioMediaUrl.needsSigning('$base/public/avatars/u/a.jpg'), isFalse);
      expect(JuzzioMediaUrl.needsSigning('https://example.com/a.jpg'), isFalse);
      expect(JuzzioMediaUrl.needsSigning(null), isFalse);
    });

    test('yol geçişi (..) içeren adres ayrıştırılmaz', () {
      expect(JuzzioMediaUrl.parse('$base/public/chat-media/u/../x.jpg'), isNull);
      final ref = JuzzioMediaUrl.parse('$base/public/chat-media/u%20x/r/a.jpg?download=1')!;
      expect(ref.bucket, 'chat-media');
      expect(ref.path, 'u x/r/a.jpg');
    });

    test('imzalı adres önbelleklenir; eşzamanlı istekler tek imzaya düşer', () async {
      var calls = 0;
      JuzzioMediaUrl.signerOverride = (bucket, path, ttl) async {
        calls++;
        expect(ttl, JuzzioMediaUrl.signedTtl.inSeconds);
        return '$base/sign/$bucket/$path?token=t$calls';
      };
      const url = '$base/public/chat-media/u/r/a.jpg';
      final results = await Future.wait([JuzzioMediaUrl.resolve(url), JuzzioMediaUrl.resolve(url)]);
      expect(results[0], results[1]);
      expect(await JuzzioMediaUrl.resolve(url), results[0]);
      expect(calls, 1);
      expect(await JuzzioMediaUrl.resolve('$base/public/avatars/u/a.jpg'), '$base/public/avatars/u/a.jpg');
      expect(calls, 1);
    });

    test('imza reddedilirse (yetki yok) hata yükselir; özgün adrese sessizce dönülmez', () async {
      JuzzioMediaUrl.signerOverride = (bucket, path, ttl) async => throw StateError('403');
      await expectLater(JuzzioMediaUrl.resolve('$base/public/voice-notes/u/r/a.m4a'), throwsStateError);
    });

    testWidgets('JuzzioStorageImage imza başarısızsa errorBuilder gösterir', (tester) async {
      JuzzioMediaUrl.signerOverride = (bucket, path, ttl) async => throw StateError('403');
      await tester.pumpWidget(MaterialApp(
        home: JuzzioStorageImage(
          '$base/public/chat-media/u/r/a.jpg',
          errorBuilder: (_, __, ___) => const Text('erisim-yok'),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('erisim-yok'), findsOneWidget);
    });
  });

  group('Denetim D — uçtan uca şifreleme', () {
    test('E2EE mesajları için üçüncü taraf çeviri izni varsayılan olarak KAPALI', () {
      expect(JuzzioAppController.instance.e2eeTranslationOptIn, isFalse);
      expect(JuzzioAppController.instance.preferencesSnapshot()['e2eeTranslationOptIn'], isFalse);
    });

    test('şifreleme yapılamadığında özel istisna; durum mesajda saklanır', () {
      const e = JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
      expect(e.toString(), 'e2ee_required:unavailable');
      expect(JuzzioE2eeStatus.values, containsAll([JuzzioE2eeStatus.peerKeyMissing, JuzzioE2eeStatus.encrypted]));
    });
  });
}
