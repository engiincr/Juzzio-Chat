// =============================================================================
// TRAWAVE (GM-039) — Çoklu cihaz anahtar eşitleme
//
//  Sorun: Her cihaz kendi kimlik anahtarını üretip profile yayınlıyordu. Aynı hesap
//  telefonda ve bilgisayarda açıkken son yayınlayan cihaz "geçerli" oluyor, diğeri yeni
//  mesajlar için "Bu mesajın anahtarı bu cihazda yok" gösteriyordu.
//
//  Çözüm (WhatsApp/Signal bağlı cihaz yaklaşımı):
//   • Hesabın TEK bir kimlik anahtarlığı vardır; tüm cihazlar aynı anahtarlığı taşır.
//   • Anahtarlığı olmayan (yeni) cihaz kendi rakip anahtarını YAYINLAMAZ; bunun yerine
//     cihaza özel bir taşıma anahtarı (X25519) üretir ve `e2ee_key_envelopes` tablosuna
//     "bekliyor" isteği yazar.
//   • Anahtarlığı taşıyan cihaz isteği kullanıcıya gösterir ("Bu sen misin?"). Onaylanınca
//     anahtarlık, geçici X25519 + HKDF-SHA256 + AES-256-GCM ile YALNIZ o cihazın taşıma
//     anahtarına şifrelenip zarfa konur. Sunucu zarfı açamaz.
//   • Daha önce onaylanmış cihazın (aynı taşıma anahtarı) sonraki istekleri (30 günlük
//     anahtar yenilemesi) otomatik mühürlenir.
//   • Kurtarma: diğer cihaz yoksa Google Drive yedeği geri yüklenir veya yeni anahtar
//     oluşturulur (eski mesajlar o cihazda açılmaz).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'juzzio_e2ee.dart';
import 'juzzio_features_service.dart';
import 'supabase_service.dart';

/// Başka bir cihazın anahtar isteği
class JuzzioKeyRequest {
  const JuzzioKeyRequest({required this.id, required this.device, required this.pub, required this.label, required this.createdAt});
  final String id;
  final String device;
  final String pub;
  final String label;
  final DateTime? createdAt;

  static JuzzioKeyRequest? fromMap(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final dev = (m['target_device'] ?? '').toString();
    final pub = (m['target_pub'] ?? '').toString();
    if (id.isEmpty || dev.isEmpty || pub.isEmpty) return null;
    return JuzzioKeyRequest(
      id: id,
      device: dev,
      pub: pub,
      label: (m['label'] ?? '').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal(),
    );
  }
}

enum JuzzioKeySyncState {
  /// Anahtarlık bu cihazda (normal)
  ready,

  /// Bu cihaz anahtarlığı bekliyor (başka cihazdan onay / yedek)
  waiting,
}

/// Zarf şifrelemesi (saf; test edilir): geçici X25519 → HKDF → AES-256-GCM
class JuzzioKeyEnvelopeCrypto {
  static final X25519 _x = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _salt = utf8.encode('trawave-keysync-v1');

  static List<int> _info(String uid, String device) => utf8.encode('keyring|$uid|$device');

  /// (gönderenin geçici açık anahtarı, şifreli metin)
  static Future<(String, String)> seal({required String uid, required String device, required String targetPub, required String keyring}) async {
    final eph = await _x.newKeyPair();
    final ephPub = base64Encode((await eph.extractPublicKey()).bytes);
    final shared = await _x.sharedSecretKey(keyPair: eph, remotePublicKey: SimplePublicKey(base64Decode(targetPub), type: KeyPairType.x25519));
    final key = await _hkdf.deriveKey(secretKey: shared, nonce: _salt, info: _info(uid, device));
    final box = await _aes.encrypt(utf8.encode(keyring), secretKey: key, nonce: _aes.newNonce(), aad: _info(uid, device));
    return (ephPub, base64Encode(box.concatenation()));
  }

  static Future<String?> open({required String uid, required String device, required SimpleKeyPair mine, required String senderPub, required String ciphertext}) async {
    try {
      final shared = await _x.sharedSecretKey(keyPair: mine, remotePublicKey: SimplePublicKey(base64Decode(senderPub), type: KeyPairType.x25519));
      final key = await _hkdf.deriveKey(secretKey: shared, nonce: _salt, info: _info(uid, device));
      final box = SecretBox.fromConcatenation(base64Decode(ciphertext), nonceLength: 12, macLength: 16);
      return utf8.decode(await _aes.decrypt(box, secretKey: key, aad: _info(uid, device)));
    } catch (_) {
      return null;
    }
  }
}

class JuzzioKeySync extends ChangeNotifier {
  JuzzioKeySync._();
  static final JuzzioKeySync instance = JuzzioKeySync._();

  static const String table = 'e2ee_key_envelopes';
  static const String _seedPrefix = 'juzzio_ks_dev_v1_';
  static const String _trustedPrefix = 'juzzio_ks_trusted_v1_';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static final X25519 _x = X25519();

  JuzzioKeySyncState state = JuzzioKeySyncState.ready;
  List<JuzzioKeyRequest> incoming = const [];

  /// Sunucu tablosu henüz yoksa (SQL 10.57 uygulanmadıysa) özellik sessizce kapalı kalır
  bool serverReady = true;

  String _uid = '';
  SimpleKeyPair? _pair;
  String _pub = '';
  Timer? _poll;
  final Set<String> _trusted = {};
  bool _busy = false;

  Future<void> _ensure(String uid) async {
    if (_uid == uid && _pair != null) return;
    _uid = uid;
    var seed = await _secure.read(key: '$_seedPrefix$uid');
    if (seed == null || seed.isEmpty) {
      final r = Random.secure();
      seed = base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await _secure.write(key: '$_seedPrefix$uid', value: seed);
    }
    _pair = await _x.newKeyPairFromSeed(base64Decode(seed));
    _pub = base64Encode((await _pair!.extractPublicKey()).bytes);
    _trusted
      ..clear()
      ..addAll(((await _secure.read(key: '$_trustedPrefix$uid')) ?? '').split(',').where((e) => e.isNotEmpty));
  }

  static String deviceLabel() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Cihaz';
  }

  /// Bu cihaz anahtarlık bekliyor: isteği yazar (varsa tazeler) ve gelen zarfı denetler.
  /// Zarf açılırsa anahtarlık JSON'u döner.
  Future<String?> requestAndReceive(String uid) async {
    try {
      await _ensure(uid);
      final dev = await JuzzioFeaturesService.instance.deviceId();
      final db = SupabaseService.instance.client;
      final row = await db.from(table).select().eq('user_id', uid).eq('target_device', dev).maybeSingle();
      if (row != null && row['status'] == 'sealed' && row['target_pub'] == _pub) {
        final ring = await JuzzioKeyEnvelopeCrypto.open(
            uid: uid, device: dev, mine: _pair!, senderPub: '${row['sender_pub']}', ciphertext: '${row['ciphertext']}');
        if (ring != null) {
          await db.from(table).update({'status': 'consumed', 'ciphertext': null}).eq('id', row['id']);
          state = JuzzioKeySyncState.ready;
          notifyListeners();
          return ring;
        }
      }
      if (row == null || row['target_pub'] != _pub || row['status'] != 'pending') {
        await db.from(table).upsert({
          'user_id': uid,
          'target_device': dev,
          'target_pub': _pub,
          'label': deviceLabel(),
          'status': 'pending',
          'sender_pub': null,
          'ciphertext': null,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,target_device');
      }
      serverReady = true;
    } on Exception catch (e) {
      // tablo yok (SQL uygulanmadı) → eski davranışa düşülür
      if ('$e'.contains('e2ee_key_envelopes') || '$e'.contains('PGRST205') || '$e'.contains('42P01')) serverReady = false;
    }
    if (state != JuzzioKeySyncState.waiting) {
      state = JuzzioKeySyncState.waiting;
      notifyListeners();
    }
    return null;
  }

  /// Anahtarlığı taşıyan cihaz: bekleyen istekleri getirir; güvenilen cihazlarınkini otomatik mühürler.
  Future<void> refreshIncoming(String uid) async {
    if (_busy || !JuzzioE2ee.instance.hasKeys) return;
    _busy = true;
    try {
      await _ensure(uid);
      final dev = await JuzzioFeaturesService.instance.deviceId();
      final rows = await SupabaseService.instance.client
          .from(table)
          .select()
          .eq('user_id', uid)
          .eq('status', 'pending')
          .neq('target_device', dev)
          .order('created_at', ascending: false)
          .limit(10);
      final list = [for (final r in (rows as List)) if (r is Map) JuzzioKeyRequest.fromMap(Map<String, dynamic>.from(r))].whereType<JuzzioKeyRequest>().toList();
      final manual = <JuzzioKeyRequest>[];
      for (final r in list) {
        if (_trusted.contains(r.pub)) {
          await _seal(uid, r);
        } else {
          manual.add(r);
        }
      }
      incoming = manual;
      serverReady = true;
      notifyListeners();
    } catch (e) {
      if ('$e'.contains('e2ee_key_envelopes') || '$e'.contains('PGRST205') || '$e'.contains('42P01')) {
        serverReady = false;
        stopPolling(); // SQL 10.57 uygulanana kadar gereksiz istek yok
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _seal(String uid, JuzzioKeyRequest r) async {
    final (senderPub, ct) = await JuzzioKeyEnvelopeCrypto.seal(uid: uid, device: r.device, targetPub: r.pub, keyring: JuzzioE2ee.instance.exportKeyring());
    await SupabaseService.instance.client.from(table).update({
      'status': 'sealed',
      'sender_pub': senderPub,
      'ciphertext': ct,
      'sealed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', r.id).eq('status', 'pending');
  }

  /// Kullanıcı "Bu benim" dedi: anahtarlık o cihaza mühürlenir, cihaz güvenilenlere eklenir.
  Future<bool> approve(JuzzioKeyRequest r) async {
    try {
      await _ensure(_uid.isEmpty ? (SupabaseService.instance.currentUserId ?? '') : _uid);
      await _seal(_uid, r);
      _trusted.add(r.pub);
      await _secure.write(key: '$_trustedPrefix$_uid', value: _trusted.join(','));
      incoming = [for (final x in incoming) if (x.id != r.id) x];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> reject(JuzzioKeyRequest r) async {
    try {
      await SupabaseService.instance.client.from(table).update({'status': 'rejected'}).eq('id', r.id);
    } catch (_) {}
    incoming = [for (final x in incoming) if (x.id != r.id) x];
    notifyListeners();
  }

  /// Uygulama açıkken düzenli denetim (bekleyen cihaz: zarf; anahtarlı cihaz: istekler)
  void startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => tick());
    tick();
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> tick() async {
    final uid = SupabaseService.instance.currentUserId ?? '';
    if (uid.isEmpty) return;
    if (state == JuzzioKeySyncState.waiting) {
      final ring = await requestAndReceive(uid);
      if (ring != null) await JuzzioE2ee.instance.adoptLinkedKeyring(ring);
    } else {
      await refreshIncoming(uid);
    }
  }

  /// Hesap değişince (çıkış / başka hesap) cihaz durumu sıfırlanır
  void resetForAccount() {
    state = JuzzioKeySyncState.ready;
    incoming = const [];
    _uid = '';
    _pair = null;
    _trusted.clear();
  }
}
