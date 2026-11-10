// =============================================================================
// JUZZIO v0.9.0 — Hassas sohbet koruması (son talimat §4.6: Sohbet Bilgileri > Gizlilik)
//
//  • Uygulama PIN'i (4–8 rakam): PBKDF2-HMAC-SHA256 (rastgele tuz, 60 000 tur) ile özetlenip
//    cihazın güvenli deposunda (Android Keystore destekli flutter_secure_storage) tutulur.
//    PIN'in kendisi hiçbir yere yazılmaz, sunucuya gönderilmez.
//  • Kilitli sohbetler bu CİHAZA özeldir: sohbet listesinde gizlenir, "Kilitli sohbetler"
//    girişinden PIN ile açılır; uygulama arka plana geçince yeniden kilitlenir.
//  • Kilitlenen sohbetin bildirim önizlemesi sunucuda 'gizli' yapılır (içerik/gönderen sızmaz).
//  • Kaba kuvvet koruması: 5 hatalı denemeden sonra artan bekleme (30 sn × 2^n, en fazla 1 saat).
//  • Biyometrik doğrulama: bu sürümde YOK — local_auth için MainActivity'nin
//    FlutterFragmentActivity + AppCompat temasına taşınması gerekir; cihazda doğrulanmadan
//    yapılmadı (bkz. docs/IMPLEMENTATION_PROGRESS_v0.9.0.md).
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Saf PIN/bekleme mantığı (birim testli).
class JuzzioChatLockMath {
  JuzzioChatLockMath._();

  static const int iterations = 60000;
  static final RegExp pinRe = RegExp(r'^[0-9]{4,8}$');

  static bool validPin(String pin) => pinRe.hasMatch(pin);

  static Future<List<int>> derive(String pin, List<int> salt, {int rounds = iterations}) async {
    final algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256);
    final key = await algo.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    return key.extractBytes();
  }

  /// Sabit zamanlı karşılaştırma.
  static bool equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// [failures] ardışık hatadan sonra bekleme (ilk 4 hata serbest).
  static Duration lockoutFor(int failures) {
    if (failures < 5) return Duration.zero;
    final secs = 30 * math.pow(2, math.min(failures - 5, 7)).toInt();
    return Duration(seconds: math.min(secs, 3600));
  }
}

class JuzzioChatLock extends ChangeNotifier {
  JuzzioChatLock._();
  static final JuzzioChatLock instance = JuzzioChatLock._();

  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _kHash = 'juzzio_chatlock_hash_v1';
  static const String _kRooms = 'juzzio_chatlock_rooms_v1';
  static const String _kFails = 'juzzio_chatlock_fails_v1';

  /// Test için depolama değiştirilebilir.
  @visibleForTesting
  static Map<String, String>? memoryStore;

  final Set<String> _locked = <String>{};
  bool _unlocked = false;
  bool _loaded = false;
  int _failures = 0;
  DateTime? _blockedUntil;

  bool get loaded => _loaded;

  /// v1.2.4: PIN doğrulandıktan sonra yalnız KISA bir süre (2 dk) açık sayılır; kilitli sohbetten
  /// çıkınca, uygulama arka plana geçince ya da süre dolunca yeniden kilitlenir.
  /// (Önceden PIN oluşturulduğu an kilit "açık" kalıyor ve kilitli sohbete şifresiz giriliyordu.)
  static const Duration unlockGrace = Duration(minutes: 2);
  DateTime? _unlockedAt;
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool get isUnlocked => juzzioChatUnlockValid(_unlocked, _unlockedAt, clock(), unlockGrace);
  Set<String> get lockedRooms => Set.unmodifiable(_locked);
  bool isLocked(String roomId) => _locked.contains(roomId);
  DateTime? get blockedUntil => _blockedUntil;

  Future<String?> _read(String k) async => memoryStore != null ? memoryStore![k] : _secure.read(key: k);
  Future<void> _write(String k, String? v) async {
    if (memoryStore != null) {
      if (v == null) {
        memoryStore!.remove(k);
      } else {
        memoryStore![k] = v;
      }
      return;
    }
    if (v == null) {
      await _secure.delete(key: k);
    } else {
      await _secure.write(key: k, value: v);
    }
  }

  Future<void> load() async {
    final rooms = await _read(_kRooms);
    _locked
      ..clear()
      ..addAll((rooms ?? '').split(',').where((e) => e.isNotEmpty));
    _failures = int.tryParse(await _read(_kFails) ?? '') ?? 0;
    _loaded = true;
    notifyListeners();
  }

  Future<bool> hasPin() async => (await _read(_kHash))?.isNotEmpty == true;

  Future<void> setPin(String pin) async {
    if (!JuzzioChatLockMath.validPin(pin)) throw ArgumentError('invalid_pin');
    final salt = List<int>.generate(16, (_) => math.Random.secure().nextInt(256));
    final hash = await JuzzioChatLockMath.derive(pin, salt);
    await _write(_kHash, '${base64Encode(salt)}:${base64Encode(hash)}');
    // v1.2.4: PIN oluşturmak kilidi AÇMAZ — sohbete girişte PIN yine sorulur
    _unlocked = false;
    _unlockedAt = null;
    notifyListeners();
  }

  /// PIN doğrulama. Bekleme süresindeyse false + [blockedUntil] dolu.
  Future<bool> unlock(String pin) async {
    final now = DateTime.now();
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) return false;
    final stored = await _read(_kHash);
    if (stored == null || !stored.contains(':')) return false;
    final parts = stored.split(':');
    final salt = base64Decode(parts[0]);
    final expected = base64Decode(parts[1]);
    final got = await JuzzioChatLockMath.derive(pin, salt);
    if (JuzzioChatLockMath.equal(got, expected)) {
      _failures = 0;
      _blockedUntil = null;
      await _write(_kFails, '0');
      _unlocked = true;
      _unlockedAt = clock();
      notifyListeners();
      return true;
    }
    _failures++;
    await _write(_kFails, '$_failures');
    final wait = JuzzioChatLockMath.lockoutFor(_failures);
    _blockedUntil = wait == Duration.zero ? null : now.add(wait);
    notifyListeners();
    return false;
  }

  /// Uygulama arka plana geçince çağrılır.
  void relock() {
    if (!_unlocked) return;
    _unlocked = false;
    _unlockedAt = null;
    notifyListeners();
  }

  Future<void> setLocked(String roomId, bool locked) async {
    if (locked) {
      _locked.add(roomId);
    } else {
      _locked.remove(roomId);
    }
    await _write(_kRooms, _locked.join(','));
    notifyListeners();
  }

  /// PIN'i ve tüm kilitleri kaldırır (yalnız PIN doğrulandıktan sonra arayüzden çağrılır).
  Future<void> reset() async {
    _locked.clear();
    await _write(_kRooms, null);
    await _write(_kHash, null);
    await _write(_kFails, '0');
    _failures = 0;
    _blockedUntil = null;
    _unlocked = false;
    _unlockedAt = null;
    notifyListeners();
  }
}

/// Kilit hâlâ açık mı (saf; test edilir)
bool juzzioChatUnlockValid(bool unlocked, DateTime? at, DateTime now, Duration grace) =>
    unlocked && at != null && now.difference(at) >= Duration.zero && now.difference(at) < grace;
