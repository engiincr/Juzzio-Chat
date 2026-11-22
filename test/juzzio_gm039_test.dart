// GM-039: çoklu cihaz anahtar eşitleme
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_key_sync.dart';
import 'package:juzzio/widgets/juzzio_device_link_ui.dart';

void main() {
  group('GM-039 zarf şifrelemesi', () {
    test('mühürlenen anahtarlık yalnız hedef cihazın anahtarıyla açılır', () async {
      final x = X25519();
      final target = await x.newKeyPair();
      final targetPub = (await target.extractPublicKey()).bytes;
      final other = await x.newKeyPair();
      const ring = '{"v":2,"current":"abc","keys":{}}';
      final (sender, ct) = await JuzzioKeyEnvelopeCrypto.seal(
          uid: 'u1', device: 'device-0001', targetPub: _b64(targetPub), keyring: ring);
      expect(ct.contains('current'), isFalse); // düz metin değil
      expect(await JuzzioKeyEnvelopeCrypto.open(uid: 'u1', device: 'device-0001', mine: target, senderPub: sender, ciphertext: ct), ring);
      // başka cihaz, başka hesap veya başka cihaz kimliği açamaz
      expect(await JuzzioKeyEnvelopeCrypto.open(uid: 'u1', device: 'device-0001', mine: other, senderPub: sender, ciphertext: ct), isNull);
      expect(await JuzzioKeyEnvelopeCrypto.open(uid: 'u2', device: 'device-0001', mine: target, senderPub: sender, ciphertext: ct), isNull);
      expect(await JuzzioKeyEnvelopeCrypto.open(uid: 'u1', device: 'device-0002', mine: target, senderPub: sender, ciphertext: ct), isNull);
    });

    test('istek satırı ayrıştırılır; eksik alan reddedilir', () {
      expect(JuzzioKeyRequest.fromMap({'id': '1', 'target_device': 'dev12345', 'target_pub': 'p', 'label': 'Windows PC'})?.label, 'Windows PC');
      expect(JuzzioKeyRequest.fromMap({'id': '1', 'target_device': '', 'target_pub': 'p'}), isNull);
    });

    test('istek zamanı metni', () {
      final now = DateTime(2026, 11, 23, 12, 0);
      expect(juzzioLinkRequestTime(null), '');
      expect(juzzioLinkRequestTime(now.subtract(const Duration(minutes: 5)), now: now), contains('5'));
    });

    test('yeni cihaz rakip anahtar yayınlamaz; SQL tablo ve RLS dosyada', () {
      final e2ee = File('lib/services/juzzio_e2ee.dart').readAsStringSync();
      expect(e2ee.contains('!_keys.containsKey(published)'), isTrue);
      expect(e2ee.contains('JuzzioKeySync.instance.requestAndReceive(uid)'), isTrue);
      final sql = File('supabase/juzzio_database.sql').readAsStringSync();
      expect(sql.contains('CREATE TABLE IF NOT EXISTS public.e2ee_key_envelopes'), isTrue);
      expect(sql.contains('USING (user_id = auth.uid())'), isTrue);
      expect(sql.contains("RAISE EXCEPTION 'device_not_registered'"), isTrue);
    });
  });
}

String _b64(List<int> b) => base64Encode(b);
