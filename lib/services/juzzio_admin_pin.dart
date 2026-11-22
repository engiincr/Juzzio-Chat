// GM-027 (v2.2.0) — Yönetici paneli PIN girişi.
//
// Yönetici bir kez panel şifresiyle girdikten sonra ("Oturumu Hatırla" ile cihazda saklanan
// sunucu belirteci) panel, Kilitli sohbetler ile AYNI PIN ekranıyla açılır. Giriş yapan kullanıcı
// oturumdan otomatik bilinir; yalnız PIN sorulur.
//
// Güvenlik:
//  • PIN cihazda yalnız PBKDF2-SHA256 (60 000 tur, 16 bayt tuz) türevi olarak güvenli depoda tutulur.
//  • PIN yalnız cihazdaki belirtecin kilidini açar; yetki her işlemde sunucuda (admin_check_token)
//    denetlenir. Belirteç geçersizse PIN sorulmaz, şifre ekranı açılır.
//  • 5 hatalı denemede belirteç cihazdan silinir → bir sonraki girişte panel şifresi gerekir.
//  • PIN kullanıcıya bağlıdır: başka hesapla girilirse PIN eşleşmez (anahtar kullanıcı kimliğiyle).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'juzzio_chat_lock.dart';

class JuzzioAdminPin {
  JuzzioAdminPin._();
  static final JuzzioAdminPin instance = JuzzioAdminPin._();

  static const int maxAttempts = 5;
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  /// Testlerde bellek içi depo kullanılabilir.
  Map<String, String>? debugStore;

  static String keyFor(String userId) => 'juzzio_admin_pin_v1_$userId';

  Future<String?> _read(String k) async {
    final m = debugStore;
    if (m != null) return m[k];
    try {
      return await _secure.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String k, String? v) async {
    final m = debugStore;
    if (m != null) {
      if (v == null) {
        m.remove(k);
      } else {
        m[k] = v;
      }
      return;
    }
    try {
      if (v == null) {
        await _secure.delete(key: k);
      } else {
        await _secure.write(key: k, value: v);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _record(String userId) async {
    final raw = await _read(keyFor(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPin(String userId) async => (await _record(userId)) != null;

  Future<int?> pinLength(String userId) async => ((await _record(userId))?['n'] as num?)?.toInt();

  Future<int> failures(String userId) async => ((await _record(userId))?['f'] as num?)?.toInt() ?? 0;

  Future<void> setPin(String userId, String pin, {int rounds = JuzzioChatLockMath.iterations}) async {
    if (!JuzzioChatLockMath.validPin(pin)) throw ArgumentError('invalid_pin');
    final rnd = math.Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hash = await JuzzioChatLockMath.derive(pin, salt, rounds: rounds);
    await _write(
      keyFor(userId),
      jsonEncode({'s': base64Encode(salt), 'h': base64Encode(hash), 'n': pin.length, 'r': rounds, 'f': 0}),
    );
  }

  /// PIN doğruysa true. Yanlışsa hata sayacı artar; [maxAttempts]'e ulaşınca kayıt silinir
  /// ve [lockedOut] true olur (çağıran taraf saklı belirteci de silmelidir).
  bool lockedOut = false;

  Future<bool> verify(String userId, String pin) async {
    lockedOut = false;
    final rec = await _record(userId);
    if (rec == null) return false;
    final salt = base64Decode('${rec['s']}');
    final want = base64Decode('${rec['h']}');
    final rounds = (rec['r'] as num?)?.toInt() ?? JuzzioChatLockMath.iterations;
    final got = await JuzzioChatLockMath.derive(pin, salt, rounds: rounds);
    if (JuzzioChatLockMath.equal(got, want)) {
      if ((rec['f'] as num? ?? 0) != 0) {
        rec['f'] = 0;
        await _write(keyFor(userId), jsonEncode(rec));
      }
      return true;
    }
    final f = ((rec['f'] as num?)?.toInt() ?? 0) + 1;
    if (f >= maxAttempts) {
      lockedOut = true;
      await clear(userId);
    } else {
      rec['f'] = f;
      await _write(keyFor(userId), jsonEncode(rec));
    }
    return false;
  }

  Future<void> clear(String userId) => _write(keyFor(userId), null);
}
