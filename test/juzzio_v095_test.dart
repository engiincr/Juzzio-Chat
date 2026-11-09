// JUZZIO v0.9.5 birim testleri
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/notification_text.dart';
import 'package:juzzio/screens/call_screen.dart';
import 'package:juzzio/screens/watch_party_screen.dart';
import 'package:juzzio/services/juzzio_e2ee.dart';

void main() {
  test('Arama: Çalıyor / Aranıyor kararı', () {
    final now = DateTime.utc(2026, 11, 9, 12);
    expect(juzzioPeerReachable(isOnline: true, lastSeen: now.subtract(const Duration(seconds: 30)), now: now), isTrue);
    expect(juzzioPeerReachable(isOnline: true, lastSeen: now.subtract(const Duration(minutes: 5)), now: now), isFalse);
    expect(juzzioPeerReachable(isOnline: false, lastSeen: now, now: now), isFalse);
    expect(juzzioPeerReachable(isOnline: true, lastSeen: null, now: now), isFalse);
  });

  test('Watch Party: beklenen konum', () {
    final t = DateTime.utc(2026, 11, 9, 20);
    expect(juzzioWatchExpectedPosition(positionMs: 5000, playing: false, rate: 1, changedAt: t, nowUtc: t.add(const Duration(seconds: 10))), 5000);
    expect(juzzioWatchExpectedPosition(positionMs: 5000, playing: true, rate: 1, changedAt: t, nowUtc: t.add(const Duration(seconds: 10))), 15000);
    expect(juzzioWatchExpectedPosition(positionMs: 0, playing: true, rate: 1.5, changedAt: t, nowUtc: t.add(const Duration(seconds: 2))), 3000);
    // saat geri kaymışsa negatif süre eklenmez
    expect(juzzioWatchExpectedPosition(positionMs: 1000, playing: true, rate: 1, changedAt: t, nowUtc: t.subtract(const Duration(seconds: 5))), 1000);
  });

  test('Güvenlik numarası iki tarafta aynı, anahtar değişince farklı', () async {
    final a = await juzzioSafetyNumber('uid-a', 'xa|ka', 'uid-b', 'xb|kb');
    final b = await juzzioSafetyNumber('uid-b', 'xb|kb', 'uid-a', 'xa|ka');
    expect(a, b);
    expect(a.replaceAll(RegExp(r'\s'), '').length, 60);
    final c = await juzzioSafetyNumber('uid-a', 'xa|ka', 'uid-b', 'xEVIL|kb');
    expect(c == a, isFalse);
  });

  test('Bildirim önizleme parçaları', () {
    expect(juzzioPreviewParts('poll|Pizza mı?|Evet|2|2', 'poll'), ['Pizza mı?', 'Evet', '2', '2']);
    expect(juzzioPreviewParts('sos|battery|https://m|4', 'sos')!.first, 'battery');
    expect(juzzioPreviewParts('x', 'poll'), isNull);
  });
}
