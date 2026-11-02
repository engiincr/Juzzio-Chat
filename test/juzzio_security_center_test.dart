import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_security_center.dart';

void main() {
  test('cihaz kaydı ayrıştırılır, mevcut cihaz işaretlenir', () {
    final d = JuzzioDeviceEntry.fromMap({'device': 'abc123', 'platform': 'android', 'last_seen': '2026-11-01T10:00:00Z', 'current': true});
    expect(d.suffix, 'abc123');
    expect(d.current, isTrue);
    expect(d.lastSeen, isNotNull);
  });

  test('bilinmeyen olay türü gösterilmez (uydurma uyarı yok)', () {
    expect(JuzzioSecurityEvent.fromMap({'id': 1, 'kind': 'hacked'}), isNull);
    final e = JuzzioSecurityEvent.fromMap({'id': 2, 'kind': 'new_device', 'detail': {'device': 'xyz789'}, 'seen': false});
    expect(e, isNotNull);
    expect(e!.detail['device'], 'xyz789');
    expect(e.seen, isFalse);
  });

  test('özet eksik alanlarda güvenli varsayılan', () {
    final o = JuzzioSecurityOverview.fromMap(const {});
    expect(o.devices, 0);
    expect(o.unseenAlerts, 0);
    expect(o.e2eeReady, isFalse);
  });
}
