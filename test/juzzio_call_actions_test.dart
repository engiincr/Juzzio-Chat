// JUZZIO v0.9.0 — N-F gelen arama bildirimi eylemleri
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/fcm_push_service.dart';
import 'package:juzzio/services/juzzio_call_actions.dart';

void main() {
  const call = 'cdcdcdcd-0000-4000-8000-0000000000f1';
  tearDown(() => JuzzioCallActions.rpcOverride = null);

  test('geçersiz çağrı kimliği sunucuya gitmez', () async {
    var n = 0;
    JuzzioCallActions.rpcOverride = (_) async {
      n++;
      return 'rejected';
    };
    expect(await JuzzioCallActions.decline('x'), 'error');
    expect(await JuzzioCallActions.handleChannelArgs({'call_id': call, 'action': 'accept'}), {'status': 'error'});
    expect(n, 0);
  });

  test('reddet sunucu sonucunu döndürür; hata → error', () async {
    JuzzioCallActions.rpcOverride = (id) async => id == call ? 'rejected' : null;
    expect(await JuzzioCallActions.handleChannelArgs({'call_id': call, 'action': 'decline'}), {'status': 'rejected'});
    JuzzioCallActions.rpcOverride = (_) async => 'answered';
    expect(await JuzzioCallActions.decline(call), 'answered');
    JuzzioCallActions.rpcOverride = (_) async => throw StateError('not_allowed');
    expect(await JuzzioCallActions.decline(call), 'error');
  });

  test('bildirim yükü Kabul eylemini taşır', () {
    final p = JuzzioPushEventPayload.fromMap({
      'event_type': 'incoming_call',
      'target_secondary_id': call,
      'call_action': 'accept',
    });
    expect(p.callAction, 'accept');
    expect(JuzzioPushEventPayload.fromMap({'event_type': 'message'}).callAction, '');
  });
}
