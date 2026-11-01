// JUZZIO v0.8.0 — kuantum sonrası kriptografi bilinen-yanıt (KAT) testleri.
// Vektörler bağımsız referans uygulamalardan (Python hashlib, OpenSSL/AWS-LC ML-KEM/ML-DSA) alındı.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/pq/juzzio_pq.dart';

import 'juzzio_pq_vectors.dart';

Uint8List _hex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final pat = List<int>.generate(200, (i) => i % 251);

  test('SHA-3 / SHAKE (FIPS 202)', () {
    expect(_toHex(juzzioSha3_256(utf8.encode('abc'))), kSha3_256Abc);
    expect(_toHex(juzzioSha3_512(pat)), kSha3_512Pat);
    expect(_toHex(juzzioShake128(pat, 300)), kShake128Pat300);
    expect(_toHex(juzzioShake256(pat, 99)), kShake256Pat99);
    final x = JuzzioKeccak.shake128()..absorb(pat);
    expect(_toHex([...x.squeeze(10), ...x.squeeze(290)]), kShake128Pat300);
  });

  test('ML-KEM-768 (FIPS 203) anahtar, kapsülleme ve kapsül açma', () {
    final seed = List<int>.generate(64, (i) => i);
    final (ek, dk) = JuzzioMlKem768.keyPairFromSeed(seed);
    expect(ek.length, 1184);
    expect(dk.length, 2400);
    expect(_toHex(juzzioSha3_256(ek)), kMlKemEkSha3);
    expect(_toHex(juzzioSha3_256(dk)), kMlKemDkSha3);
    final (ss, ct) = JuzzioMlKem768.encapsulate(ek, List<int>.filled(32, 7));
    expect(_toHex(ss), kMlKemSs);
    expect(_toHex(juzzioSha3_256(ct)), kMlKemCtSha3);
    expect(_toHex(JuzzioMlKem768.decapsulate(dk, ct)), kMlKemSs);
    // Bağımsız referans uygulamanın ürettiği şifreli metin
    expect(_toHex(JuzzioMlKem768.decapsulate(dk, _hex(kMlKemRefCt))), kMlKemRefSs);
    // Bozulmuş şifreli metin → örtük ret (farklı sır)
    final bad = Uint8List.fromList(ct)..[3] ^= 1;
    expect(_toHex(JuzzioMlKem768.decapsulate(dk, bad)) == kMlKemSs, isFalse);
  });

  test('ML-DSA-65 (FIPS 204) imza doğrulama', () {
    final pk = _hex(kMlDsaPk);
    final sig = _hex(kMlDsaSig);
    final msg = utf8.encode(kMlDsaMsg);
    final ctx = utf8.encode(kMlDsaCtx);
    expect(JuzzioMlDsa65.verify(pk, msg, sig, ctx: ctx), isTrue);
    expect(JuzzioMlDsa65.verify(pk, utf8.encode('${kMlDsaMsg}x'), sig, ctx: ctx), isFalse);
    expect(JuzzioMlDsa65.verify(pk, msg, sig), isFalse);
    final bad = Uint8List.fromList(sig)..[200] ^= 1;
    expect(JuzzioMlDsa65.verify(pk, msg, bad, ctx: ctx), isFalse);
  });
}
