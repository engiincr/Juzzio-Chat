// v1.3.0 — ağır şifreleme işleri ayrı isolate'te (arayüz donmaz) ve sonuçlar değişmez.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_chat_lock.dart';
import 'package:juzzio/services/deepgram_livekit_service.dart' show juzzioInCallNeedsTranslation;
import 'package:juzzio/services/juzzio_media_crypto.dart';

void main() {
  test('büyük medya (isolate yolu) şifrelenir, açılır; kurcalanırsa reddedilir', () async {
    final plain = Uint8List.fromList(List<int>.generate(200 * 1024, (i) => (i * 31) & 0xFF));
    final sealed = await JuzzioMediaCrypto.seal(plain, mime: 'video/mp4');
    expect(sealed.cipher.length, plain.length + 16);
    final opened = await JuzzioMediaCrypto.open(sealed.cipher, sealed.key);
    expect(opened, isNotNull);
    expect(opened, equals(plain));
    final bad = Uint8List.fromList(sealed.cipher)..[100] ^= 0x01;
    expect(await JuzzioMediaCrypto.open(bad, sealed.key), isNull);
  });

  test('küçük medya (yerinde yol) da aynı biçimde çalışır', () async {
    final plain = Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xFF));
    final sealed = await JuzzioMediaCrypto.seal(plain, mime: 'image/jpeg');
    expect(await JuzzioMediaCrypto.open(sealed.cipher, sealed.key), equals(plain));
  });

  test('PIN türetme isolate\'te aynı sonucu verir (belirlenimci)', () async {
    final salt = List<int>.generate(16, (i) => i);
    final a = await JuzzioChatLockMath.derive('0000', salt, rounds: 1000);
    final b = await JuzzioChatLockMath.derive('0000', salt, rounds: 1000);
    final c = await JuzzioChatLockMath.derive('1234', salt, rounds: 1000);
    expect(a.length, 32);
    expect(JuzzioChatLockMath.equal(a, b), isTrue);
    expect(JuzzioChatLockMath.equal(a, c), isFalse);
  });

  test('arama içi mesaj: aynı dil çevrilmez, farklı dil çevrilir', () {
    expect(juzzioInCallNeedsTranslation('Merhaba, nasılsın?', 'merhaba nasılsın'), isFalse);
    expect(juzzioInCallNeedsTranslation('How are you?', 'Nasılsın?'), isTrue);
    expect(juzzioInCallNeedsTranslation('Hi', ''), isFalse);
  });
}
