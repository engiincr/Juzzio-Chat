import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_media_crypto.dart';

void main() {
  final plain = Uint8List.fromList(List<int>.generate(5000, (i) => i % 251));

  test('şifrele → aç aynı baytları verir, şifreli veri düz veriden farklı', () async {
    final s = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    expect(s.cipher.length, plain.length + 16);
    expect(s.cipher.sublist(0, 32), isNot(equals(plain.sublist(0, 32))));
    expect(await JuzzioMediaCrypto.open(s.cipher, s.key), equals(plain));
  });

  test('tek bayt değişirse açılmaz (SHA-256 / GCM, fail-closed)', () async {
    final s = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    final bad = Uint8List.fromList(s.cipher)..[10] ^= 1;
    expect(await JuzzioMediaCrypto.open(bad, s.key), isNull);
  });

  test('yanlış anahtarla açılmaz', () async {
    final a = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    final b = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    final wrong = JuzzioMediaKey(key: b.key.key, nonce: a.key.nonce, sha256Hex: a.key.sha256Hex, mime: 'image/jpeg');
    expect(await JuzzioMediaCrypto.open(a.cipher, wrong), isNull);
  });

  test('her dosyaya yeni anahtar ve nonce', () async {
    final a = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    final b = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    expect(a.key.key, isNot(b.key.key));
    expect(a.key.nonce, isNot(b.key.nonce));
  });

  test('bozuk zarf alanı reddedilir', () {
    expect(JuzzioMediaKey.fromJson({'k': 'x', 'n': 'y', 'h': 'z'}), isNull);
    expect(JuzzioMediaKey.fromJson(null), isNull);
  });

  test('zarf JSON gidiş-dönüş', () async {
    final s = await JuzzioMediaCrypto.seal(plain, mime: 'image/png');
    final k = JuzzioMediaKey.fromJson(s.key.toJson());
    expect(k, isNotNull);
    expect(k!.mime, 'image/png');
    expect(await JuzzioMediaCrypto.open(s.cipher, k), equals(plain));
  });
}
