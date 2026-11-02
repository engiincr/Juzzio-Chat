import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_polls_service.dart';

void main() {
  test('tekil seçim: dokunulan seçenek tek oy olur, aynısına tekrar dokunmak geri çeker', () {
    expect(JuzzioPollResults.nextVotes(current: {}, tapped: 1, multi: false), [1]);
    expect(JuzzioPollResults.nextVotes(current: {1}, tapped: 2, multi: false), [2]);
    expect(JuzzioPollResults.nextVotes(current: {1}, tapped: 1, multi: false), isEmpty);
  });

  test('çoklu seçim: aç/kapat', () {
    expect(JuzzioPollResults.nextVotes(current: {0}, tapped: 2, multi: true), [0, 2]);
    expect(JuzzioPollResults.nextVotes(current: {0, 2}, tapped: 0, multi: true), [2]);
  });

  test('sonuç ayrıştırma ve oranlar', () {
    final r = JuzzioPollResults.fromMap({
      'question': 'Q',
      'options': ['a', 'b', 'c'],
      'counts': [1, 3, 0],
      'my_votes': [1],
      'voters': 4,
      'anonymous': false,
      'by_option': {'1': ['Ali', 'Ayşe']},
    });
    expect(r.totalVotes, 4);
    expect(r.share(1), 0.75);
    expect(r.myVotes, {1});
    expect(r.byOption![1], ['Ali', 'Ayşe']);
  });

  test('gizli ankette seçmen listesi istemcide de yok sayılır', () {
    final r = JuzzioPollResults.fromMap({
      'options': ['a', 'b'],
      'counts': [1, 1],
      'anonymous': true,
      'by_option': {'0': ['X']},
    });
    expect(r.byOption, isNull);
    expect(r.share(5), 0);
  });

  test('zamanlanmış kayıt ayrıştırma', () {
    final s = JuzzioScheduledMessage.fromMap({'id': 'x', 'room_id': 'r', 'send_at': '2026-11-02T10:00:00Z', 'preview': '', 'e2ee': {'c': 'A'}});
    expect(s.encrypted, isTrue);
  });
}
