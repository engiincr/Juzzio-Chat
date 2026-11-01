// =============================================================================
// JUZZIO v0.8.0 — Kuantum sonrası (post-quantum) kriptografi, saf Dart
//
//  • Keccak-f[1600]: SHA3-256, SHA3-512, SHAKE128, SHAKE256 (FIPS 202)
//  • ML-KEM-768 (FIPS 203): anahtar üretimi, kapsülleme, kapsül açma
//    (örtük ret / implicit rejection dahil)
//  • ML-DSA-65 (FIPS 204): imza DOĞRULAMA (güncelleme bildirimi ve APK özetinin
//    imzasını doğrulamak için; imzalama CI'da yapılır)
//
//  Bu dosya, aynı algoritmaların Python karşılığıyla satır satır eşleşecek şekilde
//  yazıldı; Python sürümü OpenSSL/AWS-LC tabanlı resmi ML-KEM-768 ve ML-DSA-65
//  uygulamalarına karşı doğrulandı. Bilinen yanıt (KAT) testleri:
//  test/juzzio_pq_test.dart. Yalnızca Dart VM (Android/iOS) için: 64 bit tamsayı
//  aritmetiği kullanır.
// =============================================================================

import 'dart:typed_data';

// -----------------------------------------------------------------------------
// Keccak / SHA-3 / SHAKE
// -----------------------------------------------------------------------------
const List<int> _rc = <int>[
  0x0000000000000001, 0x0000000000008082, -0x7FFFFFFFFFFF7F76, -0x7FFFFFFF7FFF8000, //
  0x000000000000808B, 0x0000000080000001, -0x7FFFFFFF7FFF7F7F, -0x7FFFFFFFFFFF7FF7,
  0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
  0x000000008000808B, -0x7FFFFFFFFFFFFF75, -0x7FFFFFFFFFFF7F77, -0x7FFFFFFFFFFF7FFD,
  -0x7FFFFFFFFFFF7FFE, -0x7FFFFFFFFFFFFF80, 0x000000000000800A, -0x7FFFFFFF7FFFFFF6,
  -0x7FFFFFFF7FFF7F7F, -0x7FFFFFFFFFFF7F80, 0x0000000080000001, -0x7FFFFFFF7FFF7FF8,
];
const List<int> _rot = <int>[0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14];

int _rotl(int x, int n) {
  n %= 64;
  if (n == 0) return x;
  return (x << n) | (x >>> (64 - n));
}

void _f1600(List<int> a) {
  final c = List<int>.filled(5, 0);
  final d = List<int>.filled(5, 0);
  final b = List<int>.filled(25, 0);
  for (var rnd = 0; rnd < 24; rnd++) {
    for (var x = 0; x < 5; x++) {
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
    }
    for (var x = 0; x < 5; x++) {
      d[x] = c[(x + 4) % 5] ^ _rotl(c[(x + 1) % 5], 1);
    }
    for (var i = 0; i < 25; i++) {
      a[i] ^= d[i % 5];
    }
    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 5; y++) {
        b[y + 5 * ((2 * x + 3 * y) % 5)] = _rotl(a[x + 5 * y], _rot[x + 5 * y]);
      }
    }
    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 5; y++) {
        a[x + 5 * y] = b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y]);
      }
    }
    a[0] ^= _rc[rnd];
  }
}

/// Akış (streaming) Keccak süngeri: absorb → squeeze (squeeze tekrar çağrılabilir).
class JuzzioKeccak {
  final int rate;
  final int pad;
  final List<int> _a = List<int>.filled(25, 0);
  final List<int> _buf = <int>[];
  final List<int> _out = <int>[];
  bool _squeezing = false;

  JuzzioKeccak(this.rate, this.pad);

  factory JuzzioKeccak.shake128() => JuzzioKeccak(168, 0x1f);
  factory JuzzioKeccak.shake256() => JuzzioKeccak(136, 0x1f);

  void _block(List<int> b) {
    for (var i = 0; i < rate ~/ 8; i++) {
      var v = 0;
      for (var k = 7; k >= 0; k--) {
        v = (v << 8) | (b[8 * i + k] & 0xff);
      }
      _a[i] ^= v;
    }
    _f1600(_a);
  }

  void absorb(List<int> data) {
    if (_squeezing) throw StateError('absorb after squeeze');
    _buf.addAll(data);
    while (_buf.length >= rate) {
      _block(_buf.sublist(0, rate));
      _buf.removeRange(0, rate);
    }
  }

  void _finish() {
    final b = List<int>.filled(rate, 0);
    for (var i = 0; i < _buf.length; i++) {
      b[i] = _buf[i];
    }
    b[_buf.length] ^= pad;
    b[rate - 1] ^= 0x80;
    _block(b);
    _buf.clear();
    _squeezing = true;
  }

  Uint8List squeeze(int n) {
    if (!_squeezing) _finish();
    while (_out.length < n) {
      for (var i = 0; i < rate ~/ 8; i++) {
        final v = _a[i];
        for (var k = 0; k < 8; k++) {
          _out.add((v >>> (8 * k)) & 0xff);
        }
      }
      _f1600(_a);
    }
    final r = Uint8List.fromList(_out.sublist(0, n));
    _out.removeRange(0, n);
    return r;
  }
}

Uint8List juzzioSha3_256(List<int> d) => (JuzzioKeccak(136, 6)..absorb(d)).squeeze(32);
Uint8List juzzioSha3_512(List<int> d) => (JuzzioKeccak(72, 6)..absorb(d)).squeeze(64);
Uint8List juzzioShake128(List<int> d, int n) => (JuzzioKeccak(168, 0x1f)..absorb(d)).squeeze(n);
Uint8List juzzioShake256(List<int> d, int n) => (JuzzioKeccak(136, 0x1f)..absorb(d)).squeeze(n);

Uint8List _cat(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

bool _ctEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

int _brv(int i, int bits) {
  var r = 0;
  for (var k = 0; k < bits; k++) {
    r = (r << 1) | ((i >> k) & 1);
  }
  return r;
}

int _powMod(int b, int e, int m) {
  var r = 1;
  b %= m;
  while (e > 0) {
    if (e & 1 == 1) r = r * b % m;
    b = b * b % m;
    e >>= 1;
  }
  return r;
}

// -----------------------------------------------------------------------------
// ML-KEM-768 (FIPS 203)
// -----------------------------------------------------------------------------
class JuzzioMlKem768 {
  static const int q = 3329;
  static const int k = 3;
  static const int eta1 = 2;
  static const int eta2 = 2;
  static const int du = 10;
  static const int dv = 4;
  static const int publicKeyBytes = 1184;
  static const int secretKeyBytes = 2400;
  static const int ciphertextBytes = 1088;

  static final List<int> _zetas = List<int>.generate(128, (i) => _powMod(17, _brv(i, 7), q));
  static final List<int> _gammas = List<int>.generate(128, (i) => _powMod(17, 2 * _brv(i, 7) + 1, q));

  static List<int> _ntt(List<int> f0) {
    final f = List<int>.from(f0);
    var i = 1;
    var len = 128;
    while (len >= 2) {
      for (var start = 0; start < 256; start += 2 * len) {
        final z = _zetas[i++];
        for (var j = start; j < start + len; j++) {
          final t = z * f[j + len] % q;
          f[j + len] = (f[j] - t) % q;
          f[j] = (f[j] + t) % q;
        }
      }
      len ~/= 2;
    }
    return f;
  }

  static List<int> _intt(List<int> f0) {
    final f = List<int>.from(f0);
    var i = 127;
    var len = 2;
    while (len <= 128) {
      for (var start = 0; start < 256; start += 2 * len) {
        final z = _zetas[i--];
        for (var j = start; j < start + len; j++) {
          final t = f[j];
          f[j] = (t + f[j + len]) % q;
          f[j + len] = z * (f[j + len] - t) % q;
        }
      }
      len *= 2;
    }
    for (var j = 0; j < 256; j++) {
      f[j] = f[j] * 3303 % q;
    }
    return f;
  }

  static List<int> _mul(List<int> f, List<int> g) {
    final h = List<int>.filled(256, 0);
    for (var i = 0; i < 128; i++) {
      final a0 = f[2 * i], a1 = f[2 * i + 1], b0 = g[2 * i], b1 = g[2 * i + 1];
      h[2 * i] = (a0 * b0 + a1 * b1 % q * _gammas[i]) % q;
      h[2 * i + 1] = (a0 * b1 + a1 * b0) % q;
    }
    return h;
  }

  static List<int> _add(List<int> f, List<int> g) => List<int>.generate(256, (i) => (f[i] + g[i]) % q);
  static List<int> _sub(List<int> f, List<int> g) => List<int>.generate(256, (i) => (f[i] - g[i]) % q);

  static List<int> _sampleNtt(List<int> seed) {
    final x = JuzzioKeccak.shake128()..absorb(seed);
    final a = <int>[];
    while (a.length < 256) {
      final c = x.squeeze(3);
      final d1 = c[0] + 256 * (c[1] % 16);
      final d2 = c[1] ~/ 16 + 16 * c[2];
      if (d1 < q) a.add(d1);
      if (d2 < q && a.length < 256) a.add(d2);
    }
    return a;
  }

  static List<int> _cbd(List<int> b, int eta) {
    final f = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var x = 0, y = 0;
      for (var j = 0; j < eta; j++) {
        var p = 2 * i * eta + j;
        x += (b[p >> 3] >> (p & 7)) & 1;
        p = 2 * i * eta + eta + j;
        y += (b[p >> 3] >> (p & 7)) & 1;
      }
      f[i] = (x - y) % q;
    }
    return f;
  }

  static Uint8List _prf(List<int> s, int n, int eta) => juzzioShake256(_cat([s, [n]]), 64 * eta);

  static Uint8List _enc(List<int> f, int d) {
    final out = Uint8List(32 * d);
    var bit = 0;
    for (final a in f) {
      for (var j = 0; j < d; j++) {
        if ((a >> j) & 1 == 1) out[bit >> 3] |= 1 << (bit & 7);
        bit++;
      }
    }
    return out;
  }

  static List<int> _dec(List<int> b, int d) {
    final m = d == 12 ? q : (1 << d);
    final f = <int>[];
    var bit = 0;
    for (var i = 0; i < 256; i++) {
      var a = 0;
      for (var j = 0; j < d; j++) {
        a |= ((b[bit >> 3] >> (bit & 7)) & 1) << j;
        bit++;
      }
      f.add(a % m);
    }
    return f;
  }

  static List<int> _compress(List<int> f, int d) =>
      [for (final x in f) (((x << d) + q ~/ 2) ~/ q) % (1 << d)];
  static List<int> _decompress(List<int> f, int d) => [for (final y in f) (y * q + (1 << (d - 1))) >> d];

  static List<List<List<int>>> _genMatrix(List<int> rho) => List.generate(
      k, (i) => List.generate(k, (j) => _sampleNtt(_cat([rho, [j, i]]))));

  static (Uint8List, Uint8List) _pkeKeygen(List<int> d) {
    final g = juzzioSha3_512(_cat([d, [k]]));
    final rho = g.sublist(0, 32), sigma = g.sublist(32);
    final a = _genMatrix(rho);
    var n = 0;
    final s = <List<int>>[], e = <List<int>>[];
    for (var i = 0; i < k; i++) {
      s.add(_cbd(_prf(sigma, n++, eta1), eta1));
    }
    for (var i = 0; i < k; i++) {
      e.add(_cbd(_prf(sigma, n++, eta1), eta1));
    }
    final sh = [for (final x in s) _ntt(x)];
    final eh = [for (final x in e) _ntt(x)];
    final ek = BytesBuilder(copy: false);
    for (var i = 0; i < k; i++) {
      var acc = List<int>.filled(256, 0);
      for (var j = 0; j < k; j++) {
        acc = _add(acc, _mul(a[i][j], sh[j]));
      }
      ek.add(_enc(_add(acc, eh[i]), 12));
    }
    ek.add(rho);
    final dk = BytesBuilder(copy: false);
    for (final x in sh) {
      dk.add(_enc(x, 12));
    }
    return (ek.toBytes(), dk.toBytes());
  }

  static Uint8List _pkeEncrypt(List<int> ek, List<int> m, List<int> r) {
    final th = [for (var i = 0; i < k; i++) _dec(ek.sublist(384 * i, 384 * i + 384), 12)];
    final rho = ek.sublist(384 * k);
    final a = _genMatrix(rho);
    var n = 0;
    final y = <List<int>>[], e1 = <List<int>>[];
    for (var i = 0; i < k; i++) {
      y.add(_cbd(_prf(r, n++, eta1), eta1));
    }
    for (var i = 0; i < k; i++) {
      e1.add(_cbd(_prf(r, n++, eta2), eta2));
    }
    final e2 = _cbd(_prf(r, n++, eta2), eta2);
    final yh = [for (final x in y) _ntt(x)];
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < k; i++) {
      var acc = List<int>.filled(256, 0);
      for (var j = 0; j < k; j++) {
        acc = _add(acc, _mul(a[j][i], yh[j]));
      }
      out.add(_enc(_compress(_add(_intt(acc), e1[i]), du), du));
    }
    final mu = _decompress(_dec(m, 1), 1);
    var acc = List<int>.filled(256, 0);
    for (var j = 0; j < k; j++) {
      acc = _add(acc, _mul(th[j], yh[j]));
    }
    final v = _add(_add(_intt(acc), e2), mu);
    out.add(_enc(_compress(v, dv), dv));
    return out.toBytes();
  }

  static Uint8List _pkeDecrypt(List<int> dk, List<int> c) {
    final u = [for (var i = 0; i < k; i++) _decompress(_dec(c.sublist(32 * du * i, 32 * du * (i + 1)), du), du)];
    final v = _decompress(_dec(c.sublist(32 * du * k), dv), dv);
    final sh = [for (var i = 0; i < k; i++) _dec(dk.sublist(384 * i, 384 * i + 384), 12)];
    var acc = List<int>.filled(256, 0);
    for (var j = 0; j < k; j++) {
      acc = _add(acc, _mul(sh[j], _ntt(u[j])));
    }
    return _enc(_compress(_sub(v, _intt(acc)), 1), 1);
  }

  /// Belirlenimci anahtar üretimi: seed = d (32 bayt) ‖ z (32 bayt)
  /// Dönüş: (açık anahtar ek 1184 B, gizli anahtar dk 2400 B)
  static (Uint8List, Uint8List) keyPairFromSeed(List<int> seed64) {
    if (seed64.length != 64) throw ArgumentError('ML-KEM seed must be 64 bytes');
    final d = seed64.sublist(0, 32), z = seed64.sublist(32);
    final (ek, dkp) = _pkeKeygen(d);
    return (ek, _cat([dkp, ek, juzzioSha3_256(ek), z]));
  }

  /// Kapsülleme: m = 32 bayt rastgele. Dönüş: (paylaşılan sır 32 B, şifreli metin 1088 B)
  static (Uint8List, Uint8List) encapsulate(List<int> ek, List<int> m) {
    if (ek.length != publicKeyBytes || m.length != 32) throw ArgumentError('ML-KEM encaps input');
    // FIPS 203 §7.2 açık anahtar denetimi: ByteEncode12(ByteDecode12(ek)) == ek
    for (var i = 0; i < k; i++) {
      final part = ek.sublist(384 * i, 384 * i + 384);
      if (!_ctEq(_enc(_dec(part, 12), 12), part)) throw ArgumentError('ML-KEM invalid public key');
    }
    final g = juzzioSha3_512(_cat([m, juzzioSha3_256(ek)]));
    return (g.sublist(0, 32), _pkeEncrypt(ek, m, g.sublist(32)));
  }

  /// Kapsül açma (örtük ret: geçersiz şifreli metinde sahte ama belirlenimci sır döner)
  static Uint8List decapsulate(List<int> dk, List<int> c) {
    if (dk.length != secretKeyBytes || c.length != ciphertextBytes) throw ArgumentError('ML-KEM decaps input');
    final dkp = dk.sublist(0, 384 * k);
    final ekp = dk.sublist(384 * k, 768 * k + 32);
    final h = dk.sublist(768 * k + 32, 768 * k + 64);
    final z = dk.sublist(768 * k + 64);
    final m = _pkeDecrypt(dkp, c);
    final g = juzzioSha3_512(_cat([m, h]));
    final kBar = juzzioShake256(_cat([z, c]), 32);
    return _ctEq(_pkeEncrypt(ekp, m, g.sublist(32)), c) ? g.sublist(0, 32) : kBar;
  }
}

// -----------------------------------------------------------------------------
// ML-DSA-65 (FIPS 204) — yalnızca doğrulama
// -----------------------------------------------------------------------------
class JuzzioMlDsa65 {
  static const int q = 8380417;
  static const int d = 13;
  static const int tau = 49;
  static const int lambda = 192;
  static const int gamma1 = 1 << 19;
  static const int gamma2 = (q - 1) ~/ 32;
  static const int kk = 6;
  static const int l = 5;
  static const int eta = 4;
  static const int beta = tau * eta;
  static const int omega = 55;
  static const int publicKeyBytes = 1952;
  static const int signatureBytes = 3309;

  static final List<int> _zetas = List<int>.generate(256, (i) => _powMod(1753, _brv(i, 8), q));

  static List<int> _ntt(List<int> w0) {
    final w = List<int>.from(w0);
    var m = 0;
    var len = 128;
    while (len >= 1) {
      for (var start = 0; start < 256; start += 2 * len) {
        final z = _zetas[++m];
        for (var j = start; j < start + len; j++) {
          final t = z * w[j + len] % q;
          w[j + len] = (w[j] - t) % q;
          w[j] = (w[j] + t) % q;
        }
      }
      len ~/= 2;
    }
    return w;
  }

  static List<int> _intt(List<int> w0) {
    final w = List<int>.from(w0);
    var m = 256;
    var len = 1;
    while (len < 256) {
      for (var start = 0; start < 256; start += 2 * len) {
        final z = (q - _zetas[--m]) % q;
        for (var j = start; j < start + len; j++) {
          final t = w[j];
          w[j] = (t + w[j + len]) % q;
          w[j + len] = z * ((t - w[j + len]) % q) % q;
        }
      }
      len *= 2;
    }
    return [for (final x in w) x * 8347681 % q];
  }

  static List<int> _rejNtt(List<int> seed) {
    final x = JuzzioKeccak.shake128()..absorb(seed);
    final a = <int>[];
    while (a.length < 256) {
      final b = x.squeeze(3);
      final z = ((b[2] & 127) << 16) | (b[1] << 8) | b[0];
      if (z < q) a.add(z);
    }
    return a;
  }

  static List<int> _sampleInBall(List<int> rho) {
    final x = JuzzioKeccak.shake256()..absorb(rho);
    final s = x.squeeze(8);
    final c = List<int>.filled(256, 0);
    for (var i = 256 - tau; i < 256; i++) {
      var j = x.squeeze(1)[0];
      while (j > i) {
        j = x.squeeze(1)[0];
      }
      c[i] = c[j];
      final bitIndex = i + tau - 256;
      final bit = (s[bitIndex >> 3] >> (bitIndex & 7)) & 1;
      c[j] = bit == 1 ? q - 1 : 1;
    }
    return c;
  }

  static List<int> _unpack(List<int> b, int bits, int count) {
    final out = <int>[];
    var acc = 0, nb = 0, idx = 0;
    for (var n = 0; n < count; n++) {
      while (nb < bits) {
        acc |= b[idx++] << nb;
        nb += 8;
      }
      out.add(acc & ((1 << bits) - 1));
      acc >>= bits;
      nb -= bits;
    }
    return out;
  }

  static List<int> _pack4(List<int> vals) {
    final out = <int>[];
    for (var i = 0; i < vals.length; i += 2) {
      out.add(vals[i] | (vals[i + 1] << 4));
    }
    return out;
  }

  static (int, int) _decompose(int r) {
    final rp = r % q;
    var r0 = rp % (2 * gamma2);
    if (r0 > gamma2) r0 -= 2 * gamma2;
    if (rp - r0 == q - 1) return (0, r0 - 1);
    return ((rp - r0) ~/ (2 * gamma2), r0);
  }

  static int _useHint(int h, int r) {
    const m = (q - 1) ~/ (2 * gamma2);
    final (r1, r0) = _decompose(r);
    if (h == 1 && r0 > 0) return (r1 + 1) % m;
    if (h == 1 && r0 <= 0) return (r1 - 1) % m;
    return r1;
  }

  /// ML-DSA.Verify(pk, M, σ, ctx) — FIPS 204 Algoritma 3 + 8
  static bool verify(List<int> pk, List<int> msg, List<int> sig, {List<int> ctx = const <int>[]}) {
    if (pk.length != publicKeyBytes || sig.length != signatureBytes || ctx.length > 255) return false;
    final rho = pk.sublist(0, 32);
    final t1 = [for (var i = 0; i < kk; i++) _unpack(pk.sublist(32 + 320 * i, 32 + 320 * (i + 1)), 10, 256)];
    const off = lambda ~/ 4;
    final ct = sig.sublist(0, off);
    final z = <List<int>>[];
    for (var i = 0; i < l; i++) {
      final v = _unpack(sig.sublist(off + 640 * i, off + 640 * (i + 1)), 20, 256);
      z.add([for (final x in v) gamma1 - x]);
    }
    final y = sig.sublist(off + 640 * l);
    final h = List.generate(kk, (_) => List<int>.filled(256, 0));
    var idx = 0;
    for (var i = 0; i < kk; i++) {
      if (y[omega + i] < idx || y[omega + i] > omega) return false;
      final first = idx;
      while (idx < y[omega + i]) {
        if (idx > first && y[idx - 1] >= y[idx]) return false;
        h[i][y[idx]] = 1;
        idx++;
      }
    }
    for (var i = idx; i < omega; i++) {
      if (y[i] != 0) return false;
    }
    for (final p in z) {
      for (final c in p) {
        if (c.abs() >= gamma1 - beta) return false;
      }
    }
    final tr = juzzioShake256(pk, 64);
    final mu = juzzioShake256(_cat([tr, [0, ctx.length], ctx, msg]), 64);
    final ch = _ntt(_sampleInBall(ct));
    final zh = [for (final p in z) _ntt([for (final x in p) x % q])];
    final w1 = <int>[];
    for (var i = 0; i < kk; i++) {
      final acc = List<int>.filled(256, 0);
      for (var j = 0; j < l; j++) {
        final a = _rejNtt(_cat([rho, [j, i]]));
        for (var n = 0; n < 256; n++) {
          acc[n] = (acc[n] + a[n] * zh[j][n]) % q;
        }
      }
      final t = _ntt([for (final x in t1[i]) (x << d) % q]);
      for (var n = 0; n < 256; n++) {
        acc[n] = (acc[n] - ch[n] * t[n]) % q;
      }
      final wa = _intt(acc);
      w1.addAll(_pack4([for (var n = 0; n < 256; n++) _useHint(h[i][n], wa[n])]));
    }
    return _ctEq(juzzioShake256(_cat([mu, w1]), off), ct);
  }
}
