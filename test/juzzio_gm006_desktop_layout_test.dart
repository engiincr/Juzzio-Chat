// GM-006 (21.11.2026) — Masaüstü: sohbet ana ekranında 3 panel düzeni pencerenin tamamını kullanır
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_desktop_frame.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  final obs = JuzzioDesktopFrameObserver.instance;
  final chat = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  final settings = MaterialPageRoute<void>(builder: (_) => const SizedBox());
  final dialog =
      RawDialogRoute<void>(pageBuilder: (_, __, ___) => const SizedBox());

  test(
      'sohbet ekranı en üstteyken tam pencere; diyalog kararı değiştirmez; üstte sayfa varken çerçeve',
      () {
    obs.didPush(chat, null);
    expect(obs.fullWindow.value, isFalse, reason: 'kayıt yokken çerçeve');
    obs.registerFullWindowRoute(chat);
    expect(obs.fullWindow.value, isTrue);
    obs.didPush(dialog, chat);
    expect(obs.fullWindow.value, isTrue,
        reason: 'diyalog/alt menü düzeni sıçratmaz');
    obs.didPop(dialog, chat);
    obs.didPush(settings, chat);
    expect(obs.fullWindow.value, isFalse,
        reason: 'üstte başka tam sayfa varken ortalanmış panel');
    obs.didPop(settings, chat);
    expect(obs.fullWindow.value, isTrue);
    obs.registerFullWindowRoute(null);
    expect(obs.fullWindow.value, isFalse);
    obs.didPop(chat, null);
  });

  Future<Size> childSize(WidgetTester tester,
      {required bool full, Size window = const Size(1280, 800)}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    obs.fullWindow.value = full;
    addTearDown(() => obs.fullWindow.value = false);
    late Size seen;
    await tester.pumpWidget(MaterialApp(
      home: JuzzioDesktopFrame(
        enabled: true,
        child: Builder(builder: (ctx) {
          seen = MediaQuery.sizeOf(ctx);
          return const SizedBox.expand();
        }),
      ),
    ));
    return seen;
  }

  testWidgets(
      'geniş pencerede: tam pencere modunda içerik 1280 px, değilse 560 px panel',
      (tester) async {
    expect((await childSize(tester, full: true)).width, 1280);
    expect(
        (await childSize(tester, full: false)).width, kJuzzioDesktopPanelWidth);
  });

  testWidgets('900 px altında 3 panel açılmadığı için çerçeve sürer',
      (tester) async {
    expect(
        (await childSize(tester, full: true, window: const Size(800, 700)))
            .width,
        kJuzzioDesktopPanelWidth);
  });

  test(
      'bağlantılar: gözlemci uygulamaya eklendi, sohbet ekranı rotasını kaydeder ve bırakır',
      () {
    expect(
        _src('lib/main.dart').contains('JuzzioDesktopFrameObserver.instance]'),
        isTrue);
    final c = _src('lib/screens/chat_screen.dart');
    expect(
        c.contains('registerFullWindowRoute(ModalRoute.of(context))'), isTrue);
    expect(c.contains('registerFullWindowRoute(null)'), isTrue);
  });

  test('ses aygıtları penceresi uygulamanın Liquid Glass bileşenini kullanır',
      () {
    final k = _src('lib/widgets/juzzio_call_kit21.dart');
    final i = k.indexOf('Future<void> showJuzzioDesktopAudioSheet');
    expect(i, greaterThan(0));
    final sheet = k.substring(i);
    expect(sheet.contains('JuzzioLiquidGlass('), isTrue);
    expect(sheet.contains('glowBorder: selected'), isTrue);
  });
}
