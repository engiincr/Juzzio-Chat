// =============================================================================
// JUZZIO v0.9.0 — G23/G24 uçtan uca şifreli medya (AES-256-GCM + SHA-256 zarfı)
//  * Her dosya için RASTGELE 256-bit anahtar ve 96-bit nonce; dosya cihazda şifrelenir,
//    depolamaya yalnızca şifreli bayt (application/octet-stream) yüklenir.
//  * Anahtar bilgisi {k, n, h, mime} mesajın E2EE zarfının İÇİNDE ('m' alanı) taşınır;
//    sunucu anahtarı hiç görmez.
//  * h = şifreli baytların SHA-256 özeti. Açarken önce özet, sonra GCM etiketi doğrulanır;
//    biri tutmazsa null döner → arayüz "açılamadı" gösterir (fail-closed, ham veri gösterilmez).
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class JuzzioMediaKey {
  const JuzzioMediaKey({required this.key, required this.nonce, required this.sha256Hex, required this.mime});
  final String key; // base64
  final String nonce; // base64
  final String sha256Hex;
  final String mime;

  Map<String, dynamic> toJson() => {'k': key, 'n': nonce, 'h': sha256Hex, 'mime': mime};

  static JuzzioMediaKey? fromJson(Object? o) {
    if (o is! Map) return null;
    final k = (o['k'] ?? '').toString();
    final n = (o['n'] ?? '').toString();
    final h = (o['h'] ?? '').toString().toLowerCase();
    if (k.isEmpty || n.isEmpty || !RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
    try {
      if (base64Decode(k).length != 32 || base64Decode(n).length != 12) return null;
    } catch (_) {
      return null;
    }
    return JuzzioMediaKey(key: k, nonce: n, sha256Hex: h, mime: (o['mime'] ?? '').toString());
  }
}

class JuzzioSealedMedia {
  const JuzzioSealedMedia(this.cipher, this.key);
  final Uint8List cipher;
  final JuzzioMediaKey key;
}

class JuzzioMediaCrypto {
  JuzzioMediaCrypto._();

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  static Uint8List _random(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Future<String> sha256Hex(List<int> data) async => _hex((await Sha256().hash(data)).bytes);

  static Future<JuzzioSealedMedia> seal(List<int> plain, {required String mime}) async {
    final key = _random(32);
    final nonce = _random(12);
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key), nonce: nonce, aad: utf8.encode('juzzio-media-v1'));
    final cipher = Uint8List.fromList(box.cipherText + box.mac.bytes);
    return JuzzioSealedMedia(
      cipher,
      JuzzioMediaKey(key: base64Encode(key), nonce: base64Encode(nonce), sha256Hex: await sha256Hex(cipher), mime: mime),
    );
  }

  /// Özet veya GCM doğrulaması başarısızsa null (fail-closed).
  static Future<Uint8List?> open(List<int> cipher, JuzzioMediaKey k) async {
    if (cipher.length < 16) return null;
    if (await sha256Hex(cipher) != k.sha256Hex) return null;
    try {
      final box = SecretBox(
        cipher.sublist(0, cipher.length - 16),
        nonce: base64Decode(k.nonce),
        mac: Mac(cipher.sublist(cipher.length - 16)),
      );
      final out = await _aes.decrypt(box, secretKey: SecretKey(base64Decode(k.key)), aad: utf8.encode('juzzio-media-v1'));
      return Uint8List.fromList(out);
    } catch (_) {
      return null;
    }
  }
}
