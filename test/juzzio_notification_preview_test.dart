// JUZZIO v0.9.0 — N-D bildirimde mesaj içeriği (cihazda çözme, fail-closed)
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_notification_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const room = '0f8fad5b-d9cb-469f-a165-70867728950e';
  const msg = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

  Map<String, dynamic> row({String type = 'text', String text = 'Merhaba', Map<String, dynamic>? meta, String r = room}) => {
        'id': msg,
        'room_id': r,
        'sender_id': 'aaaaaaaa-0000-0000-0000-000000000001',
        'message_type': type,
        'original_text': text,
        'metadata': meta ?? <String, dynamic>{},
        'created_at': DateTime.now().toIso8601String(),
      };

  tearDown(() {
    JuzzioNotificationPreview.fetchOverride = null;
    JuzzioNotificationPreview.decryptOverride = null;
  });

  test('kip ayrıştırma: bilinmeyen değer full', () {
    expect(juzzioPreviewModeFrom('hidden'), JuzzioNotificationPreviewMode.hidden);
    expect(juzzioPreviewModeFrom('sender'), JuzzioNotificationPreviewMode.sender);
    expect(juzzioPreviewModeFrom('x'), JuzzioNotificationPreviewMode.full);
    expect(juzzioPreviewModeFrom(null), JuzzioNotificationPreviewMode.full);
  });

  test('geçersiz kimlikte ağ çağrısı bile yapılmaz', () async {
    var calls = 0;
    JuzzioNotificationPreview.fetchOverride = (_, __) async {
      calls++;
      return row();
    };
    expect(await JuzzioNotificationPreview.resolve(roomId: 'x', messageId: msg), isNull);
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: "1' OR 1=1"), isNull);
    expect(calls, 0);
  });

  test('şifreli mesaj cihazda çözülür ve tek satıra kısaltılır', () async {
    JuzzioNotificationPreview.fetchOverride = (_, __) async => row(text: 'juzzio_e2ee_pq3_v2_xxx', meta: {'e2ee': {'v': 2}});
    JuzzioNotificationPreview.decryptOverride = (m) async => 'Selam\n\n  nasılsın?';
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), 'Selam nasılsın?');
  });

  test('çözülemezse null → genel metin (şifre metni ASLA gösterilmez)', () async {
    JuzzioNotificationPreview.fetchOverride = (_, __) async => row(text: 'juzzio_e2ee_pq3_v2_xxx', meta: {'e2ee': {'v': 2}});
    JuzzioNotificationPreview.decryptOverride = (m) async => null;
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
  });

  test('başka odanın mesajı, silinmiş veya süresi dolmuş mesaj gösterilmez', () async {
    JuzzioNotificationPreview.decryptOverride = (m) async => m.originalText;
    JuzzioNotificationPreview.fetchOverride =
        (_, __) async => row(r: '11111111-1111-1111-1111-111111111111');
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
    JuzzioNotificationPreview.fetchOverride = (_, __) async => {...row(), 'is_deleted': true};
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
    JuzzioNotificationPreview.fetchOverride = (_, __) async =>
        {...row(), 'expires_at': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String()};
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
    JuzzioNotificationPreview.fetchOverride = (_, __) async => null;
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
  });

  test('medya türleri etiketle gösterilir; ağ hatası null', () async {
    JuzzioNotificationPreview.fetchOverride = (_, __) async => row(type: 'voice', text: '');
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), contains('🎤'));
    JuzzioNotificationPreview.fetchOverride = (_, __) async => throw StateError('net');
    expect(await JuzzioNotificationPreview.resolve(roomId: room, messageId: msg), isNull);
  });

  test('uzun metin 240 karakterde kesilir', () {
    final out = JuzzioNotificationPreview.clip('a' * 500);
    expect(out.length, JuzzioNotificationPreview.maxLength);
    expect(out.endsWith('…'), isTrue);
  });

  test('kanal köprüsü {text} döner', () async {
    JuzzioNotificationPreview.fetchOverride = (_, __) async => row();
    JuzzioNotificationPreview.decryptOverride = (m) async => m.originalText;
    expect(await JuzzioNotificationPreview.handleChannelArgs({'room_id': room, 'message_id': msg}), {'text': 'Merhaba'});
  });
}
