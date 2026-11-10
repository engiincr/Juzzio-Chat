// JUZZIO v1.2.2 — mesaj gönderme uçuşu geri geldi: aynı yazı tipi, pembe parlama yok, zıplamasız iniş
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/motion/juzzio_send_fx.dart';

String _src(String p) => File(p).readAsStringSync();

const _style = JuzzioSendFlightStyle(
  textStyle: TextStyle(fontFamily: 'JuzzioTest', color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35),
  bubbleColor: Color(0xFF3355FF),
  composerColor: Color(0xFF222222),
  composerTextColor: Color(0xFFEEEEEE),
);

double _opacityOf(WidgetTester tester, Finder target) =>
    tester.widget<Opacity>(find.descendant(of: target, matching: find.byType(Opacity)).first).opacity;

void main() {
  testWidgets('uçuş sırasında balon gizli, indiği an görünür; katman kalkar', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const Align(
            alignment: Alignment.topRight,
            child: JuzzioFlightTarget(
              flightKey: 'cm_1',
              child: SizedBox(width: 120, height: 44, child: Text('Merhaba')),
            ),
          );
        }),
      ),
    ));
    JuzzioSendFlight.launch(ctx, key: 'cm_1', from: const Rect.fromLTWH(10, 500, 300, 48), text: 'Merhaba', style: _style);
    // hedef, uçuş başladıktan sonra kendini bağlar
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const Align(
            alignment: Alignment.topRight,
            child: JuzzioFlightTarget(
              key: ValueKey('t2'),
              flightKey: 'cm_1',
              child: SizedBox(width: 120, height: 44, child: Text('Merhaba')),
            ),
          );
        }),
      ),
    ));
    final target = find.byType(JuzzioFlightTarget);
    expect(JuzzioSendFlight.isPending('cm_1'), isTrue);
    expect(_opacityOf(tester, target), 0.0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, target), 0.0);
    await tester.pump(JuzzioSendFlight.duration);
    await tester.pump();
    expect(JuzzioSendFlight.isPending('cm_1'), isFalse);
    expect(_opacityOf(tester, target), 1.0);
    await tester.pump(const Duration(seconds: 3));
  });

  test('uçuşun yazı stili balonla aynı (font değişimi yok), pembe gölge yok, aşmasız eğri', () {
    final s = _src('lib/widgets/motion/juzzio_send_fx.dart');
    // v1.2.7: aynı stil + alt çizgisiz (sarı çizgi düzeltmesi)
    expect(RegExp(r'st\.textStyle\.copyWith\(\s*color: textColor,').hasMatch(s), isTrue);
    expect(s.contains('Curves.easeInOutCubic'), isTrue);
    final flight = s.substring(s.indexOf('class _FlightViewState'), s.indexOf('class JuzzioBubbleEntrance'));
    expect(flight.contains('glow'), isFalse);
    expect(flight.contains('boxShadow'), isFalse);
    expect(flight.contains('kJuzzioSpring'), isFalse);
    expect(s.contains('!JuzzioSendFlight.isPending(widget.entranceKey)'), isTrue);
  });

  test('sohbet ekranı uçuşu balonla aynı stil kaynağından başlatır', () {
    final c = _src('lib/screens/chat_screen.dart');
    expect(c.contains('_launchSendFlight(txt, clientMsgId'), isTrue);
    expect(c.contains('textStyle: _outgoingBubbleTextStyle(p)'), isTrue);
    expect(c.contains('_outgoingBubbleTextStyle(p).copyWith('), isTrue);
    expect(c.contains('JuzzioFlightTarget('), isTrue);
  });

  test('Sürüm notu 1.2.2', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.2');
    expect(n.versionName, '1.2.2');
    expect(n.versionCode, 122);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
