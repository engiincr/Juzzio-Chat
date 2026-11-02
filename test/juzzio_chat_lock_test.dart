// JUZZIO v0.9.0 §4.6 — sohbet kilidi (PIN, kaba kuvvet koruması, yeniden kilitleme)
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_chat_lock.dart';

void main() {
  setUp(() => JuzzioChatLock.memoryStore = <String, String>{});
  tearDown(() => JuzzioChatLock.memoryStore = null);

  test('PIN biçimi', () {
    expect(JuzzioChatLockMath.validPin('1234'), isTrue);
    expect(JuzzioChatLockMath.validPin('12345678'), isTrue);
    expect(JuzzioChatLockMath.validPin('123'), isFalse);
    expect(JuzzioChatLockMath.validPin('12a4'), isFalse);
    expect(JuzzioChatLockMath.validPin('123456789'), isFalse);
  });

  test('bekleme süresi: ilk 4 hata serbest, sonra katlanarak, en fazla 1 saat', () {
    expect(JuzzioChatLockMath.lockoutFor(4), Duration.zero);
    expect(JuzzioChatLockMath.lockoutFor(5), const Duration(seconds: 30));
    expect(JuzzioChatLockMath.lockoutFor(6), const Duration(seconds: 60));
    expect(JuzzioChatLockMath.lockoutFor(50), const Duration(hours: 1));
  });

  test('PBKDF2 aynı tuzla belirlenimci, farklı PIN farklı; sabit zamanlı eşitlik', () async {
    final salt = List<int>.filled(16, 7);
    final a = await JuzzioChatLockMath.derive('1234', salt, rounds: 1000);
    final b = await JuzzioChatLockMath.derive('1234', salt, rounds: 1000);
    final c = await JuzzioChatLockMath.derive('1235', salt, rounds: 1000);
    expect(JuzzioChatLockMath.equal(a, b), isTrue);
    expect(JuzzioChatLockMath.equal(a, c), isFalse);
    expect(JuzzioChatLockMath.equal(a, a.sublist(1)), isFalse);
  });

  test('PIN depoda düz metin olarak YOK; kilit/aç/yeniden kilitle', () async {
    final lock = JuzzioChatLock.instance;
    await lock.reset();
    await lock.load();
    expect(await lock.hasPin(), isFalse);
    await lock.setPin('482913');
    expect(JuzzioChatLock.memoryStore!.values.any((v) => v.contains('482913')), isFalse);
    await lock.setLocked('room-1', true);
    expect(lock.isLocked('room-1'), isTrue);
    lock.relock();
    expect(lock.isUnlocked, isFalse);
    expect(await lock.unlock('000000'), isFalse);
    expect(await lock.unlock('482913'), isTrue);
    expect(lock.isUnlocked, isTrue);
    await lock.load();
    expect(lock.isLocked('room-1'), isTrue, reason: 'kilitli sohbetler kalıcı');
    await lock.reset();
  });

  test('5 hatalı denemeden sonra doğru PIN de bekleme bitene kadar reddedilir', () async {
    final lock = JuzzioChatLock.instance;
    await lock.reset();
    await lock.setPin('1111');
    lock.relock();
    for (var i = 0; i < 5; i++) {
      expect(await lock.unlock('9999'), isFalse);
    }
    expect(lock.blockedUntil, isNotNull);
    expect(await lock.unlock('1111'), isFalse);
    await lock.reset();
  });
}
