// JUZZIO v0.9.0 §6.4 — sohbet bazlı bildirim ayarı durumu
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/chat_notification_prefs.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 10);

  test('sunucu yanıtı yoksa varsayılan: açık, cihaz ayarı, titreşim', () {
    final s = JuzzioRoomNotifState.fromMap(null);
    expect(s.isMuted(now), isFalse);
    expect(s.preview, 'inherit');
    expect(s.vibrate, isTrue);
  });

  test('süreli ve süresiz sessiz ayırt edilir', () {
    final h = JuzzioRoomNotifState.fromMap({'muted_until': '2026-11-02T11:00:00Z', 'preview': 'hidden', 'vibrate': false});
    expect(h.isMuted(now), isTrue);
    expect(h.isMutedForever(now), isFalse);
    expect(h.preview, 'hidden');
    expect(h.vibrate, isFalse);
    final f = JuzzioRoomNotifState.fromMap({'muted_until': '2126-11-02T10:00:00Z'});
    expect(f.isMutedForever(now), isTrue);
    final past = JuzzioRoomNotifState.fromMap({'muted_until': '2026-11-01T10:00:00Z'});
    expect(past.isMuted(now), isFalse);
  });

  test('bilinmeyen önizleme değeri cihaz ayarına düşer', () {
    expect(JuzzioRoomNotifState.fromMap({'preview': 'loud'}).preview, 'inherit');
  });
}
