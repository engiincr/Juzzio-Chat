// JUZZIO v0.9.0 N-B — @etiket ayrıştırıcı (SQL juzzio_extract_mentions ile aynı kural)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_mentions.dart';

void main() {
  test('sunucu kuralıyla aynı: tekil, küçük harf, e-posta/uzun ad hariç, sondaki nokta yok', () {
    final text = 'Hi @UserB ve @userb, a@b.com @ab @${'z' * 31} (@userc.)';
    expect(JuzzioMentionParser.usernames(text), ['userb', 'userc']);
  });

  test('en fazla 10 etiket', () {
    final text = List.generate(30, (i) => '@user${100 + i}').join(' ');
    expect(JuzzioMentionParser.usernames(text).length, 10);
  });

  test('parçalar metni kayıpsız yeniden oluşturur', () {
    const t = 'selam @ali_1, nasılsın @veli.';
    final segs = JuzzioMentionParser.segments(t);
    expect(segs.map((s) => s.text).join(), t);
    expect(segs.where((s) => s.isMention).map((s) => s.username), ['ali_1', 'veli']);
  });

  test('yazılmakta olan sorgu ve ekleme', () {
    const t = 'merhaba @al';
    final q = JuzzioMentionParser.activeQuery(t, t.length)!;
    expect(q.query, 'al');
    final r = JuzzioMentionParser.insert(t, t.length, 'ali_1');
    expect(r.text, 'merhaba @ali_1 ');
    expect(r.cursor, r.text.length);
    expect(JuzzioMentionParser.activeQuery('mail a@b', 8), isNull);
    expect(JuzzioMentionParser.activeQuery('yok', 3), isNull);
  });

  testWidgets('etikete dokununca kullanıcı adı iletilir', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JuzzioMentionText('bak @ali_1', style: const TextStyle(fontSize: 14), onTapUsername: (u) => tapped = u),
      ),
    ));
    final finder = find.byType(RichText).first;
    final rich = tester.widget<RichText>(finder);
    var hit = false;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == '@ali_1' && span.recognizer != null) {
        (span.recognizer! as dynamic).onTap();
        hit = true;
      }
      return true;
    });
    expect(hit, isTrue);
    expect(tapped, 'ali_1');
  });

  testWidgets('öneri şeridi yalnız sorgu varken görünür ve seçimi ekler', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          JuzzioMentionSuggestions(
            controller: ctrl,
            fetcher: (q) async => [
              JuzzioMentionCandidate(userId: 'u1', username: '${q}i_1', displayName: 'Ali'),
            ],
          ),
          TextField(controller: ctrl),
        ]),
      ),
    ));
    expect(find.byType(ActionChip), findsNothing);
    ctrl.value = const TextEditingValue(text: 'hey @al', selection: TextSelection.collapsed(offset: 7));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('@ali_1'), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    await tester.pump();
    expect(ctrl.text, 'hey @ali_1 ');
    expect(find.byType(ActionChip), findsNothing);
    ctrl.dispose();
  });
}
