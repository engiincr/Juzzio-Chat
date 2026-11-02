// JUZZIO v0.9.0 — N-A sohbet etkinlik durumu çözümleyici / gönderici
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_chat_activity.dart';

void main() {
  late DateTime now;
  setUp(() => now = DateTime(2026, 11, 2, 10));

  group('öncelik çözümleyici', () {
    test('kaydediliyor > yazıyor > çevrimiçi > son görülme', () {
      final r = JuzzioChatActivityResolver(clock: () => now);
      final seen = DateTime(2026, 11, 2, 9);
      expect(r.resolve(lastSeen: seen).kind, JuzzioHeaderStatusKind.lastSeen);
      expect(r.resolve(isOnline: true, lastSeen: seen).kind, JuzzioHeaderStatusKind.online);
      r.onRemote('b', JuzzioActivityState.typing);
      expect(r.resolve(isOnline: true).kind, JuzzioHeaderStatusKind.typing);
      r.onRemote('c', JuzzioActivityState.recording);
      final st = r.resolve(isOnline: true);
      expect(st.kind, JuzzioHeaderStatusKind.recording);
      expect(st.userIds, ['c']);
      expect(r.resolve().kind, JuzzioHeaderStatusKind.recording);
    });

    test('3 sn TTL: olay yenilenmezse durum düşer (takılı kalmaz)', () {
      final r = JuzzioChatActivityResolver(clock: () => now);
      r.onRemote('b', JuzzioActivityState.typing);
      now = now.add(const Duration(milliseconds: 2900));
      expect(r.resolve().kind, JuzzioHeaderStatusKind.typing);
      now = now.add(const Duration(milliseconds: 200));
      expect(r.resolve(isOnline: true).kind, JuzzioHeaderStatusKind.online);
      expect(r.hasActive, isFalse);
    });

    test('idle olayı hemen kaldırır', () {
      final r = JuzzioChatActivityResolver(clock: () => now);
      expect(r.onRemote('b', JuzzioActivityState.typing), isTrue);
      expect(r.onRemote('b', JuzzioActivityState.typing), isFalse);
      expect(r.onRemote('b', JuzzioActivityState.idle), isTrue);
      expect(r.resolve().kind, JuzzioHeaderStatusKind.none);
    });

    test('kendi kimliği ve odada olmayan (sahte) kimlik yok sayılır', () {
      final r = JuzzioChatActivityResolver(clock: () => now);
      expect(r.onRemote('me', JuzzioActivityState.typing, selfId: 'me'), isFalse);
      expect(r.onRemote('x', JuzzioActivityState.typing, allowedUserIds: {'b'}), isFalse);
      expect(r.resolve().kind, JuzzioHeaderStatusKind.none);
    });

    test('grupta en yeni yazan önce', () {
      final r = JuzzioChatActivityResolver(clock: () => now);
      r.onRemote('b', JuzzioActivityState.typing);
      now = now.add(const Duration(milliseconds: 100));
      r.onRemote('c', JuzzioActivityState.typing);
      expect(r.resolve().userIds, ['c', 'b']);
    });

    test('bilinmeyen tel değeri idle sayılır', () {
      expect(juzzioActivityFromWire('typing'), JuzzioActivityState.typing);
      expect(juzzioActivityFromWire('recording'), JuzzioActivityState.recording);
      expect(juzzioActivityFromWire('<script>'), JuzzioActivityState.idle);
      expect(juzzioActivityFromWire(null), JuzzioActivityState.idle);
    });
  });

  group('gönderici', () {
    test('tuş başına yayın yapılmaz; 2 sn canlı tutma', () {
      final s = JuzzioActivitySender(clock: () => now);
      expect(s.set(JuzzioActivityState.typing), JuzzioActivityState.typing);
      now = now.add(const Duration(milliseconds: 300));
      expect(s.set(JuzzioActivityState.typing), isNull);
      now = now.add(const Duration(milliseconds: 1800));
      expect(s.set(JuzzioActivityState.typing), JuzzioActivityState.typing);
    });

    test('4 sn tuş yoksa yazma kendiliğinden biter', () {
      final s = JuzzioActivitySender(clock: () => now);
      s.set(JuzzioActivityState.typing);
      now = now.add(const Duration(seconds: 2));
      expect(s.tick(), JuzzioActivityState.typing);
      now = now.add(const Duration(seconds: 2));
      expect(s.tick(), JuzzioActivityState.idle);
      expect(s.tick(), isNull);
    });

    test('kayıt yazmaya ezilmez; kayıt boyunca canlı tutulur; idle tek kez', () {
      final s = JuzzioActivitySender(clock: () => now);
      expect(s.set(JuzzioActivityState.recording), JuzzioActivityState.recording);
      expect(s.set(JuzzioActivityState.typing), isNull);
      now = now.add(const Duration(seconds: 10));
      expect(s.tick(), JuzzioActivityState.recording);
      expect(s.set(JuzzioActivityState.idle), JuzzioActivityState.idle);
      expect(s.set(JuzzioActivityState.idle), isNull);
    });
  });
}
