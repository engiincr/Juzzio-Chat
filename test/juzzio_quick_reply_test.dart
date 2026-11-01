// JUZZIO v0.9.0 — N-E bildirimden hızlı yanıt: idempotency + fail-closed
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_e2ee.dart';
import 'package:juzzio/services/juzzio_quick_reply.dart';

void main() {
  const room = '0f8fad5b-d9cb-469f-a165-70867728950e';

  tearDown(() {
    JuzzioQuickReply.senderOverride = null;
    JuzzioQuickReply.currentUserOverride = null;
  });

  test('geçersiz oda/metin/kimlik gönderilmez', () async {
    var calls = 0;
    JuzzioQuickReply.currentUserOverride = () => 'u';
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async => calls++;
    expect(await JuzzioQuickReply.sendWithStatus(roomId: 'x', text: 'hi'), JuzzioQuickReplyStatus.invalid);
    expect(await JuzzioQuickReply.sendWithStatus(roomId: room, text: '   '), JuzzioQuickReplyStatus.invalid);
    expect(await JuzzioQuickReply.sendWithStatus(roomId: room, text: 'a' * 4001), JuzzioQuickReplyStatus.invalid);
    expect(await JuzzioQuickReply.sendWithStatus(roomId: room, text: 'hi', clientMsgId: 'bad id!'),
        JuzzioQuickReplyStatus.invalid);
    expect(calls, 0);
  });

  test('oturum yoksa gönderilmez', () async {
    var calls = 0;
    JuzzioQuickReply.currentUserOverride = () => null;
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async => calls++;
    expect(await JuzzioQuickReply.sendWithStatus(roomId: room, text: 'hi'), JuzzioQuickReplyStatus.signedOut);
    expect(calls, 0);
  });

  test('Android client_msg_id aynen iletilir (yeniden denemede aynı kimlik → sunucuda tek mesaj)', () async {
    final seen = <String>[];
    JuzzioQuickReply.currentUserOverride = () => 'u';
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async {
      seen.add(clientMsgId);
      expect(text, 'merhaba');
    };
    const id = 'qr_0123456789abcdef0123456789abcdef';
    final r1 = await JuzzioQuickReply.handleChannelArgs({'room_id': room, 'text': '  merhaba ', 'client_msg_id': id});
    final r2 = await JuzzioQuickReply.handleChannelArgs({'room_id': room, 'text': 'merhaba', 'client_msg_id': id});
    expect(r1, {'ok': true, 'status': 'ok'});
    expect(r2['ok'], isTrue);
    expect(seen, [id, id]);
  });

  test('kimlik verilmezse güvenli rastgele kimlik üretilir', () async {
    String? got;
    JuzzioQuickReply.currentUserOverride = () => 'u';
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async => got = clientMsgId;
    expect(await JuzzioQuickReply.send(roomId: room, text: 'hi'), isTrue);
    expect(got, matches(RegExp(r'^qr_[0-9a-f]{32}$')));
  });

  test('şifreleme yapılamazsa fail-closed: ayrı durum kodu, başarı DEĞİL', () async {
    JuzzioQuickReply.currentUserOverride = () => 'u';
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async =>
        throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.peerKeyMissing);
    final r = await JuzzioQuickReply.handleChannelArgs({'room_id': room, 'text': 'gizli'});
    expect(r, {'ok': false, 'status': 'e2eeUnavailable'});
  });

  test('ağ hatası → failed', () async {
    JuzzioQuickReply.currentUserOverride = () => 'u';
    JuzzioQuickReply.senderOverride = ({required roomId, required text, required clientMsgId}) async =>
        throw StateError('net');
    expect(await JuzzioQuickReply.sendWithStatus(roomId: room, text: 'x'), JuzzioQuickReplyStatus.failed);
  });
}
