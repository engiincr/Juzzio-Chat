// JUZZIO v0.9.0 §4.4 — gelişmiş sohbet araması filtresi (cihazda çözülmüş mesaja uygulanır)
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/message_search_page.dart';
import 'package:juzzio/services/supabase_service.dart';

JuzzioMessage m(String text, {String type = 'text', DateTime? at, String? doc, bool deleted = false}) => JuzzioMessage.fromMap({
      'id': text.hashCode.toString(),
      'room_id': 'r',
      'sender_id': 's',
      'message_type': type,
      'original_text': text,
      'document_name': doc,
      'is_deleted': deleted,
      'created_at': (at ?? DateTime(2026, 11, 2, 12)).toUtc().toIso8601String(),
    });

void main() {
  test('metin büyük/küçük ve Türkçe İ/ı duyarsız', () {
    const f = JuzzioMessageSearchFilter(text: 'İSTANBUL');
    expect(f.matches(m('istanbul toplantısı'), isSaved: false), isTrue);
    expect(const JuzzioMessageSearchFilter(text: 'ılık').matches(m('ILIK su'), isSaved: false), isTrue);
    expect(f.matches(m('ankara'), isSaved: false), isFalse);
  });

  test('tür, bağlantı, kayıtlı ve silinmiş filtreleri', () {
    expect(const JuzzioMessageSearchFilter(types: {'image'}).matches(m('', type: 'image'), isSaved: false), isTrue);
    expect(const JuzzioMessageSearchFilter(types: {'image'}).matches(m('x'), isSaved: false), isFalse);
    expect(const JuzzioMessageSearchFilter(linksOnly: true).matches(m('bak https://juzzio.app'), isSaved: false), isTrue);
    expect(const JuzzioMessageSearchFilter(linksOnly: true).matches(m('bağlantı yok'), isSaved: false), isFalse);
    expect(const JuzzioMessageSearchFilter(savedOnly: true).matches(m('a'), isSaved: true), isTrue);
    expect(const JuzzioMessageSearchFilter(savedOnly: true).matches(m('a'), isSaved: false), isFalse);
    expect(const JuzzioMessageSearchFilter().matches(m('a', deleted: true), isSaved: false), isFalse);
    expect(const JuzzioMessageSearchFilter(text: 'rapor').matches(m('', type: 'document', doc: 'Rapor.pdf'), isSaved: false), isTrue);
  });

  test('tarih aralığı bitiş gününü kapsar', () {
    final f = JuzzioMessageSearchFilter(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 2));
    expect(f.matches(m('a', at: DateTime(2026, 11, 2, 23, 59)), isSaved: false), isTrue);
    expect(f.matches(m('a', at: DateTime(2026, 11, 3, 0, 1)), isSaved: false), isFalse);
    expect(f.matches(m('a', at: DateTime(2026, 10, 31, 23)), isSaved: false), isFalse);
    expect(const JuzzioMessageSearchFilter().isEmpty, isTrue);
  });
}
