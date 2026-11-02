// JUZZIO v0.9.0 §4.1–§4.3 — Yaşam Merkezi saf mantığı
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_life_service.dart';

JuzzioLifeTask t(String id, {DateTime? due, DateTime? done, String kind = 'task'}) =>
    JuzzioLifeTask(id: id, kind: kind, title: id, dueAt: due, doneAt: done, createdAt: DateTime(2026));

void main() {
  final now = DateTime(2026, 11, 2, 12);

  test('hatırlatma seçenekleri son tarihten hesaplanır', () {
    final due = DateTime(2026, 11, 3, 9);
    expect(JuzzioLifeMath.remindFor(due, 'none'), isNull);
    expect(JuzzioLifeMath.remindFor(null, 'at'), isNull);
    expect(JuzzioLifeMath.remindFor(due, 'at'), due);
    expect(JuzzioLifeMath.remindFor(due, '10m'), DateTime(2026, 11, 3, 8, 50));
    expect(JuzzioLifeMath.remindFor(due, '1h'), DateTime(2026, 11, 3, 8));
    expect(JuzzioLifeMath.remindFor(due, '1d'), DateTime(2026, 11, 2, 9));
  });

  test('gruplama: gecikmiş / bugün / yaklaşan / tarihsiz / tamamlanan', () {
    final g = JuzzioLifeMath.group([
      t('late', due: DateTime(2026, 11, 1, 10)),
      t('today2', due: DateTime(2026, 11, 2, 18)),
      t('today1', due: DateTime(2026, 11, 2, 8)),
      t('soon', due: DateTime(2026, 11, 5)),
      t('nodate'),
      t('done', due: DateTime(2026, 11, 1), done: DateTime(2026, 11, 1, 11)),
    ], now);
    expect(g.overdue.map((e) => e.id), ['late']);
    expect(g.today.map((e) => e.id), ['today1', 'today2']);
    expect(g.upcoming.map((e) => e.id), ['soon']);
    expect(g.undated.map((e) => e.id), ['nodate']);
    expect(g.done.map((e) => e.id), ['done']);
  });

  test('sunucu satırı ayrıştırılır; mesaj hatırlatıcısı tanınır', () {
    final m = JuzzioLifeTask.fromMap({
      'id': 'x',
      'kind': 'message_reminder',
      'title': '',
      'remind_at': '2026-11-02T10:00:00Z',
      'room_id': 'r',
      'message_id': 'm',
      'created_at': '2026-11-01T10:00:00Z',
    });
    expect(m.isMessageReminder, isTrue);
    expect(m.when, isNotNull);
    expect(m.isDone, isFalse);
  });

  test('istek kimliği sunucu biçimine uygun', () {
    expect(JuzzioLifeMath.requestId(), matches(RegExp(r'^lt_[0-9a-f]{24}$')));
  });
}
