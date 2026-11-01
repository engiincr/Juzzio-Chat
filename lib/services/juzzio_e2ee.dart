// =============================================================================
// JUZZIO v0.8.0 — Kuantum sonrası (PQ3 tarzı) uçtan uca şifreleme
//
//  Mimari (Apple iMessage PQ3 ile aynı yaklaşım):
//   • Kimlik anahtarı = X25519 (klasik) + ML-KEM-768 (FIPS 203, kuantum sonrası).
//     Özel anahtarlar YALNIZCA cihazın donanım destekli güvenli deposunda
//     (Android Keystore / flutter_secure_storage) durur, sunucuya hiç gitmez.
//   • HİBRİT anahtar anlaşması: oturum (epoch) anahtarı =
//        HKDF-SHA256( X25519(statik,statik) ‖ X25519(geçici,statik) ‖ ML-KEM-768 sırrı )
//     Saldırgan ancak X25519 ve ML-KEM'i AYNI ANDA kırarsa okuyabilir.
//   • HNDL ("şimdi topla, sonra çöz") koruması: bugün kaydedilen şifreli trafik,
//     gelecekte kuantum bilgisayarla X25519 kırılsa bile ML-KEM nedeniyle açılamaz.
//   • Yeniden anahtarlama (rekeying): her 50 mesajda veya 24 saatte bir yeni oturum
//     anahtarı (yeni geçici X25519 + yeni ML-KEM kapsülü); kimlik anahtarları 30
//     günde bir yenilenir. Her mesaj kendi anahtarıyla (HKDF) şifrelenir.
//   • Mesaj şifreleme: AES-256-GCM (256 bit simetrik — kuantuma dayanıklı).
//   • Kimlik doğrulama: statik X25519 bileşeni gönderenin kimliğini bağlar
//     (PQ3'te olduğu gibi kimlik doğrulama klasik, gizlilik kuantum sonrası).
//   • v1 (0.7.0) mesajları geriye dönük okunur; yeni mesajlar v2 gönderilir.
//   • Anahtarlar Google Drive'a, kullanıcının şifresinden Argon2id ile türetilen
//     anahtarla AES-256-GCM şifreli yedeklenebilir (juzzio_backup_service.dart).
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/pq/juzzio_pq.dart';
import 'supabase_service.dart';

class _IdentityKey {
  final String id;
  final List<int> xSeed; // X25519 özel anahtar tohumu (32)
  final List<int> kemSeed; // ML-KEM-768 tohumu (64)
  final DateTime created;
  SimpleKeyPair? xPair;
  String xPub = '';
  Uint8List? kemEk;
  Uint8List? kemDk;

  _IdentityKey(this.id, this.xSeed, this.kemSeed, this.created);

  Map<String, dynamic> toJson() => {
        'x': base64Encode(xSeed),
        'k': base64Encode(kemSeed),
        'c': created.toUtc().toIso8601String(),
      };
}

class _Epoch {
  final String id;
  final Uint8List key;
  final String peerKeyId;
  final String epk;
  final String kct;
  final String selfWrap;
  final DateTime created;
  int counter = 0;
  _Epoch(this.id, this.key, this.peerKeyId, this.epk, this.kct, this.selfWrap, this.created);
}

class JuzzioE2ee {
  JuzzioE2ee._();
  static final JuzzioE2ee instance = JuzzioE2ee._();

  static const String _v1Prefix = 'juzzio_e2ee_x25519_v1_';
  static const String _v2Prefix = 'juzzio_e2ee_pq3_v2_';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static final List<int> _saltV1 = utf8.encode('juzzio-e2ee-v1');
  static final List<int> _saltV2 = utf8.encode('juzzio-pq3-v2');
  static const int _rekeyMessages = 50;
  static const Duration _rekeyAge = Duration(hours: 24);
  static const Duration _identityRotation = Duration(days: 30);

  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Random _rng = Random.secure();

  String _owner = '';
  Future<void>? _init;
  SimpleKeyPair? _v1Pair;
  String _v1Pub = '';
  final Map<String, _IdentityKey> _keys = {};
  String _currentId = '';

  final Map<String, (String, String, String, DateTime)> _peerKeys = {}; // uid → (x25519, kemEk, keyId, zaman)
  final Map<String, String?> _roomPeers = {};
  final Map<String, _Epoch> _sendEpochs = {}; // peerUid → oturum
  final Map<String, Uint8List> _epochKeys = {}; // epochId → anahtar
  final Map<String, (String, String)> _plainCache = {};

  _IdentityKey? get _current => _keys[_currentId];
  String get myPublicKey => _current?.xPub ?? _v1Pub;

  Uint8List _random(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  Future<void> ensureReady() {
    final uid = SupabaseService.instance.currentUserId ?? '';
    if (uid.isEmpty) return Future<void>.value();
    if (_owner != uid) {
      _owner = uid;
      _init = null;
      _keys.clear();
      _currentId = '';
      _v1Pair = null;
      _v1Pub = '';
      _sendEpochs.clear();
      _epochKeys.clear();
      _plainCache.clear();
    }
    return _init ??= _load(uid);
  }

  Future<_IdentityKey> _materialize(_IdentityKey k) async {
    k.xPair ??= await _x25519.newKeyPairFromSeed(k.xSeed);
    if (k.xPub.isEmpty) k.xPub = base64Encode((await k.xPair!.extractPublicKey()).bytes);
    if (k.kemEk == null) {
      final (ek, dk) = JuzzioMlKem768.keyPairFromSeed(k.kemSeed);
      k.kemEk = ek;
      k.kemDk = dk;
    }
    return k;
  }

  static String _keyIdFor(String xPub, List<int> kemEk) =>
      _hex(juzzioSha3_256([...base64Decode(xPub), ...kemEk]).sublist(0, 8));

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  Future<void> _load(String uid) async {
    try {
      // v1 (0.7.0) anahtarı: eski mesajlar için korunur
      final v1 = await _secure.read(key: '$_v1Prefix$uid');
      if (v1 != null && v1.isNotEmpty) {
        _v1Pair = await _x25519.newKeyPairFromSeed(base64Decode(v1));
        _v1Pub = base64Encode((await _v1Pair!.extractPublicKey()).bytes);
      }
      final raw = await _secure.read(key: '$_v2Prefix$uid');
      if (raw != null && raw.isNotEmpty) importKeyring(raw, persist: false);
      final cur = _current;
      if (cur == null || DateTime.now().difference(cur.created) > _identityRotation) {
        await _rotateIdentity(uid, firstFromV1: cur == null ? v1 : null);
      }
      await _materialize(_current!);
      await _publish(uid);
    } catch (_) {
      _init = null;
    }
  }

  /// Yeni kimlik anahtarı (yeniden anahtarlama). Eski anahtarlar geçmiş mesajlar için saklanır.
  Future<void> _rotateIdentity(String uid, {String? firstFromV1}) async {
    final xSeed = firstFromV1 != null ? base64Decode(firstFromV1) : _random(32);
    final kemSeed = _random(64);
    final tmp = await _materialize(_IdentityKey('', xSeed, kemSeed, DateTime.now()));
    final id = _keyIdFor(tmp.xPub, tmp.kemEk!);
    final k = _IdentityKey(id, xSeed, kemSeed, DateTime.now())
      ..xPair = tmp.xPair
      ..xPub = tmp.xPub
      ..kemEk = tmp.kemEk
      ..kemDk = tmp.kemDk;
    _keys[id] = k;
    _currentId = id;
    _sendEpochs.clear();
    await _secure.write(key: '$_v2Prefix$uid', value: exportKeyring());
  }

  Future<void> _publish(String uid) async {
    final cur = _current!;
    final client = SupabaseService.instance.client;
    final row = await client.from('profiles').select('e2ee_key_id').eq('id', uid).maybeSingle();
    if ((row?['e2ee_key_id'] ?? '').toString() != cur.id) {
      await client.from('profiles').update({
        'e2ee_public_key': cur.xPub,
        'e2ee_pq_key': base64Encode(cur.kemEk!),
        'e2ee_key_id': cur.id,
      }).eq('id', uid);
    }
  }

  /// Anahtarlığın JSON hâli (yalnızca şifreli yedeğe yazılır; düz metin olarak hiçbir yere gitmez).
  String exportKeyring() => jsonEncode({
        'v': 2,
        'current': _currentId,
        'keys': {for (final e in _keys.entries) e.key: e.value.toJson()},
      });

  /// Yedekten geri yüklenen anahtarları birleştirir (mevcutlar korunur).
  void importKeyring(String raw, {bool persist = true, bool adoptCurrent = false}) {
    final obj = jsonDecode(raw);
    if (obj is! Map || obj['keys'] is! Map) return;
    (obj['keys'] as Map).forEach((id, v) {
      if (v is! Map || _keys.containsKey(id)) return;
      _keys[id.toString()] = _IdentityKey(
        id.toString(),
        base64Decode(v['x'].toString()),
        base64Decode(v['k'].toString()),
        DateTime.tryParse('${v['c']}') ?? DateTime.now(),
      );
    });
    final cur = (obj['current'] ?? '').toString();
    if ((_currentId.isEmpty || adoptCurrent) && _keys.containsKey(cur)) _currentId = cur;
    _plainCache.clear();
    if (persist && _owner.isNotEmpty) {
      _secure.write(key: '$_v2Prefix$_owner', value: exportKeyring());
    }
  }

  /// Geri yükleme sonrası: yedekteki güncel anahtar yeniden yayınlanır.
  Future<void> afterRestore() async {
    final uid = _owner;
    if (uid.isEmpty || _current == null) return;
    await _materialize(_current!);
    await _publish(uid);
  }

  bool get hasKeys => _keys.isNotEmpty;

  Future<(String, String, String)?> _peerBundle(String peerUid) async {
    final hit = _peerKeys[peerUid];
    if (hit != null && DateTime.now().difference(hit.$4).inMinutes < 10) return (hit.$1, hit.$2, hit.$3);
    try {
      final row = await SupabaseService.instance.client
          .from('profiles')
          .select('e2ee_public_key, e2ee_pq_key, e2ee_key_id')
          .eq('id', peerUid)
          .maybeSingle();
      final x = (row?['e2ee_public_key'] ?? '').toString();
      final kem = (row?['e2ee_pq_key'] ?? '').toString();
      final id = (row?['e2ee_key_id'] ?? '').toString();
      _peerKeys[peerUid] = (x, kem, id, DateTime.now());
      return (x, kem, id);
    } catch (_) {
      return hit == null ? null : (hit.$1, hit.$2, hit.$3);
    }
  }

  Future<String?> peerForRoom(String roomId) async {
    if (_roomPeers.containsKey(roomId)) return _roomPeers[roomId];
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return null;
    try {
      final room = await svc.client.from('rooms').select('is_group').eq('id', roomId).maybeSingle();
      if (room == null || room['is_group'] == true) {
        _roomPeers[roomId] = null;
        return null;
      }
      final rows = await svc.client.from('room_participants').select('user_id').eq('room_id', roomId).neq('user_id', uid).limit(1);
      final peer = rows.isEmpty ? null : rows.first['user_id']?.toString();
      _roomPeers[roomId] = peer;
      return peer;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _dh(SimpleKeyPair mine, String peerPubB64) async {
    final s = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(base64Decode(peerPubB64), type: KeyPairType.x25519),
    );
    return s.extractBytes();
  }

  Future<Uint8List> _epochKey(List<int> dhStatic, List<int> dhEph, List<int> kemSs, String epochId) async {
    final k = await _hkdf.deriveKey(
      secretKey: SecretKey([...dhStatic, ...dhEph, ...kemSs]),
      nonce: _saltV2,
      info: utf8.encode('juzzio-pq3-epoch|$epochId'),
    );
    return Uint8List.fromList(await k.extractBytes());
  }

  Future<SecretKey> _messageKey(Uint8List epochKey, String epochId, int n) =>
      _hkdf.deriveKey(secretKey: SecretKey(epochKey), nonce: _saltV2, info: utf8.encode('msg|$epochId|$n'));

  Future<SecretKey> _selfKey(_IdentityKey k) => _hkdf.deriveKey(
        secretKey: SecretKey([...k.xSeed, ...k.kemSeed]),
        nonce: _saltV2,
        info: utf8.encode('self-wrap|${k.id}'),
      );

  Future<_Epoch?> _epochFor(String peerUid) async {
    final cur = _current;
    if (cur == null) return null;
    await _materialize(cur);
    final bundle = await _peerBundle(peerUid);
    if (bundle == null || bundle.$1.isEmpty || bundle.$2.isEmpty || bundle.$3.isEmpty) return null;
    final existing = _sendEpochs[peerUid];
    if (existing != null &&
        existing.peerKeyId == bundle.$3 &&
        existing.counter < _rekeyMessages &&
        DateTime.now().difference(existing.created) < _rekeyAge) {
      return existing;
    }
    // Yeni oturum: geçici X25519 + ML-KEM kapsülü
    final eph = await _x25519.newKeyPair();
    final ephPub = base64Encode((await eph.extractPublicKey()).bytes);
    final (kemSs, kemCt) = JuzzioMlKem768.encapsulate(base64Decode(bundle.$2), _random(32));
    final epochId = _hex(_random(12));
    final dh1 = await _dh(cur.xPair!, bundle.$1);
    final dh2 = await _dh(eph, bundle.$1);
    final key = await _epochKey(dh1, dh2, kemSs, epochId);
    // Gönderen kendi mesajını sonradan okuyabilsin diye oturum anahtarı kendi anahtarıyla sarılır
    final wrap = await _aes.encrypt(key, secretKey: await _selfKey(cur), nonce: _aes.newNonce(), aad: utf8.encode(epochId));
    final e = _Epoch(epochId, key, bundle.$3, ephPub, base64Encode(kemCt), base64Encode(wrap.concatenation()), DateTime.now());
    _sendEpochs[peerUid] = e;
    _epochKeys[epochId] = key;
    return e;
  }

  /// Şifreli yük (metadata.e2ee). Karşı tarafın kuantum sonrası anahtarı yoksa (eski sürüm)
  /// 0.7.0 (v1) yöntemi, o da yoksa null (şifresiz) döner.
  Future<Map<String, dynamic>?> encryptForRoom(String roomId, {required String text, required String translated}) async {
    await ensureReady();
    final peer = await peerForRoom(roomId);
    if (peer == null) return null;
    final clear = utf8.encode(jsonEncode({'t': text, 'x': translated}));
    try {
      final ep = await _epochFor(peer);
      if (ep != null) {
        final n = ++ep.counter;
        final mk = await _messageKey(ep.key, ep.id, n);
        final box = await _aes.encrypt(clear, secretKey: mk, nonce: _aes.newNonce(), aad: utf8.encode('${ep.id}|$n'));
        final cur = _current!;
        return {
          'v': 2,
          'alg': 'x25519+mlkem768/hkdf-sha256/aes-256-gcm',
          'sk': cur.id,
          'spk': cur.xPub,
          'rk': ep.peerKeyId,
          'ep': ep.id,
          'epk': ep.epk,
          'kct': ep.kct,
          'sw': ep.selfWrap,
          'n': n,
          'c': base64Encode(box.concatenation()),
        };
      }
    } catch (_) {}
    return _encryptV1(peer, clear);
  }

  Future<Map<String, dynamic>?> _encryptV1(String peer, List<int> clear) async {
    final bundle = await _peerBundle(peer);
    final mine = _current?.xPair ?? _v1Pair;
    final myPub = _current?.xPub ?? _v1Pub;
    if (bundle == null || bundle.$1.isEmpty || mine == null) return null;
    try {
      final key = await _v1Key(mine, myPub, bundle.$1);
      final box = await _aes.encrypt(clear, secretKey: key, nonce: _aes.newNonce());
      return {'v': 1, 'alg': 'x25519-hkdf-aes256gcm', 'spk': myPub, 'rpk': bundle.$1, 'c': base64Encode(box.concatenation())};
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _v1Key(SimpleKeyPair mine, String myPub, String peerPub) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(base64Decode(peerPub), type: KeyPairType.x25519),
    );
    final pair = [myPub, peerPub]..sort();
    return _hkdf.deriveKey(secretKey: shared, nonce: _saltV1, info: utf8.encode('${pair[0]}|${pair[1]}'));
  }

  Future<List<JuzzioMessage>> decryptAll(List<JuzzioMessage> list) async {
    if (!list.any((m) => m.metadata['e2ee'] is Map)) return list;
    await ensureReady();
    final out = <JuzzioMessage>[];
    for (final m in list) {
      out.add(await decryptMessage(m));
    }
    return out;
  }

  Future<JuzzioMessage> decryptMessage(JuzzioMessage m) async {
    final e = m.metadata['e2ee'];
    if (e is! Map || m.isDeleted) return m;
    final hit = _plainCache[m.id];
    if (hit != null) return m.withText(hit.$1, hit.$2);
    await ensureReady();
    try {
      final clear = (e['v'] == 2) ? await _decryptV2(Map<String, dynamic>.from(e)) : await _decryptV1(Map<String, dynamic>.from(e));
      if (clear == null) return m.withText(_lockedText(), '');
      final obj = jsonDecode(utf8.decode(clear));
      final t = (obj is Map ? obj['t'] : '')?.toString() ?? '';
      final x = (obj is Map ? obj['x'] : '')?.toString() ?? '';
      if (_plainCache.length > 4000) _plainCache.clear();
      _plainCache[m.id] = (t, x);
      return m.withText(t, x);
    } catch (_) {
      return m.withText(_lockedText(), '');
    }
  }

  Future<List<int>?> _decryptV2(Map<String, dynamic> e) async {
    final epochId = (e['ep'] ?? '').toString();
    final n = (e['n'] as num?)?.toInt() ?? 0;
    var key = _epochKeys[epochId];
    if (key == null) {
      final sk = (e['sk'] ?? '').toString();
      final rk = (e['rk'] ?? '').toString();
      if (_keys.containsKey(rk)) {
        // Alıcı: ML-KEM kapsülünü aç + iki X25519
        final mine = await _materialize(_keys[rk]!);
        final kemSs = JuzzioMlKem768.decapsulate(mine.kemDk!, base64Decode((e['kct'] ?? '').toString()));
        final dh1 = await _dh(mine.xPair!, (e['spk'] ?? '').toString());
        final dh2 = await _dh(mine.xPair!, (e['epk'] ?? '').toString());
        key = await _epochKey(dh1, dh2, kemSs, epochId);
      } else if (_keys.containsKey(sk)) {
        // Gönderen (kendi mesajı): kendine sarılmış oturum anahtarını aç
        final mine = _keys[sk]!;
        final box = SecretBox.fromConcatenation(base64Decode((e['sw'] ?? '').toString()), nonceLength: 12, macLength: 16);
        key = Uint8List.fromList(await _aes.decrypt(box, secretKey: await _selfKey(mine), aad: utf8.encode(epochId)));
      } else {
        return null;
      }
      _epochKeys[epochId] = key;
    }
    final box = SecretBox.fromConcatenation(base64Decode((e['c'] ?? '').toString()), nonceLength: 12, macLength: 16);
    return _aes.decrypt(box, secretKey: await _messageKey(key, epochId, n), aad: utf8.encode('$epochId|$n'));
  }

  Future<List<int>?> _decryptV1(Map<String, dynamic> e) async {
    final spk = (e['spk'] ?? '').toString();
    final rpk = (e['rpk'] ?? '').toString();
    final candidates = <(SimpleKeyPair, String)>[
      if (_v1Pair != null) (_v1Pair!, _v1Pub),
      for (final k in _keys.values)
        if (k.xPair != null) (k.xPair!, k.xPub),
    ];
    for (final k in _keys.values) {
      if (k.xPair == null) await _materialize(k);
    }
    for (final k in _keys.values) {
      if (!candidates.any((c) => c.$2 == k.xPub)) candidates.add((k.xPair!, k.xPub));
    }
    for (final (pair, pub) in candidates) {
      final peer = pub == spk ? rpk : (pub == rpk ? spk : null);
      if (peer == null) continue;
      final key = await _v1Key(pair, pub, peer);
      final box = SecretBox.fromConcatenation(base64Decode((e['c'] ?? '').toString()), nonceLength: 12, macLength: 16);
      return _aes.decrypt(box, secretKey: key);
    }
    return null;
  }

  String _lockedText() =>
      '🔒 Bu mesajın anahtarı bu cihazda yok. Ayarlar → Sohbet yedeği → Yedeği geri yükle ile açabilirsin.';
}
