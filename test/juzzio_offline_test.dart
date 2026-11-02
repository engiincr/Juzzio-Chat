// JUZZIO v0.9.2 — çevrimdışı önbellek yardımcıları
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_media_cache.dart';
import 'package:juzzio/services/supabase_service.dart';

void main() {
  const base = 'https://proj.supabase.co/storage/v1/object';

  test('imzalı adresin token\'ı değişse de aynı önbellek dosyası', () {
    final a = JuzzioMediaDiskCache.keyFor('$base/public/chat-media/u/r/a.jpg');
    final b = JuzzioMediaDiskCache.keyFor('$base/sign/chat-media/u/r/a.jpg?token=x1');
    final c = JuzzioMediaDiskCache.keyFor('$base/sign/chat-media/u/r/a.jpg?token=x2');
    expect(a, b);
    expect(b, c);
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('farklı nesne / farklı dış adres farklı anahtar', () {
    expect(JuzzioMediaDiskCache.keyFor('$base/public/chat-media/u/r/a.jpg'),
        isNot(JuzzioMediaDiskCache.keyFor('$base/public/chat-media/u/r/b.jpg')));
    expect(JuzzioMediaDiskCache.keyFor('https://example.com/x.png'), isNot(JuzzioMediaDiskCache.keyFor('https://example.com/y.png')));
  });

  test('oturum yokken önbellek dosyası dönmez (ağ yoluna düşer)', () {
    expect(JuzzioMediaDiskCache.instance.cachedFile('$base/public/chat-media/u/r/a.jpg'), isNull);
  });

  test('mesaj önbellek adı yalnız güvenli karakter içerir', () {
    expect(SupabaseService.messageCacheName('ab-12/../x'), 'msgs_ab-12x');
  });

  test('süresi dolan mesaj önbellekten gösterilmez', () {
    final now = DateTime.utc(2026, 11, 2, 12);
    final rows = [
      {'id': '1', 'room_id': 'r', 'sender_id': 's', 'created_at': '2026-11-02T10:00:00Z', 'original_text': 'kalıcı'},
      {'id': '2', 'room_id': 'r', 'sender_id': 's', 'created_at': '2026-11-02T10:00:00Z', 'original_text': 'süreli', 'expires_at': '2026-11-02T11:00:00Z'},
      {'id': '3', 'room_id': 'r', 'sender_id': 's', 'created_at': '2026-11-02T10:00:00Z', 'original_text': 'henüz', 'expires_at': '2026-11-02T13:00:00Z'},
    ];
    final list = SupabaseService.visibleMessagesFromRows(rows, now: now);
    expect(list.map((m) => m.id), ['1', '3']);
  });

  test('profil önbellek adı güvenli', () {
    expect(SupabaseService.profileCacheName('aaaa-1/..'), 'profile_aaaa-1');
  });
}
