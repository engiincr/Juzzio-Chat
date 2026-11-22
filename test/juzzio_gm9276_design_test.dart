// GM-9276 (21.11.2026) — Referans ekranlar: gelen arama, görüntülü arama, masaüstü arama + ses
// aygıtları, masaüstü sohbetler. Saf yardımcılar, taşmasız yerleşim ve kaynak bağlantıları.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_call_gm9276.dart';
import 'package:juzzio/widgets/juzzio_call_kit21.dart';
import 'package:juzzio/widgets/juzzio_desktop_shell.dart';

String _src(String p) => File(p).readAsStringSync();
String _t(String tr, String en, String de) => tr;

void main() {
  group('saf yardımcılar', () {
    test('masaüstü arama düzeni yalnız masaüstünde ve ≥ 900 px', () {
      expect(juzzioUseDesktopCallLayout(desktop: true, width: 1280), isTrue);
      expect(juzzioUseDesktopCallLayout(desktop: true, width: 899), isFalse);
      expect(juzzioUseDesktopCallLayout(desktop: false, width: 1600), isFalse);
    });

    test('ses aygıtı açıklamaları referanstaki gibi', () {
      String sub(String id, String label,
              {bool out = true, bool sel = false, String pf = 'windows'}) =>
          juzzioAudioDeviceInfo(
                  id: id,
                  label: label,
                  output: out,
                  selected: sel,
                  t: _t,
                  platform: pf)
              .subtitle;
      expect(
          sub('default', 'Hoparlör (Realtek(R) Audio)'), 'Windows varsayılanı');
      expect(sub('default', 'Speakers', pf: 'macos'), 'macOS varsayılanı');
      expect(sub('a1', 'Kulaklık (USB Headset)'), 'Bağlı');
      expect(sub('a2', 'FxSound Speakers'), 'Sanal aygıt');
      expect(sub('a3', 'Monitör (NVIDIA High Definition Audio)'), 'HDMI');
      expect(
          sub('m1', 'Mikrofon (USB Headset)', out: false, sel: true), 'Seçili');
      expect(sub('m2', 'Mikrofon Dizisi (Realtek)', out: false), 'Dahili');
      final head = juzzioAudioDeviceInfo(
          id: 'a1',
          label: 'Kulaklık (USB Headset)',
          output: true,
          selected: false,
          t: _t);
      expect(head.icon, Icons.headphones_rounded);
    });

    test('kısa aygıt adı: "Hoparlör (Realtek(R) Audio)" → "Hoparlör (Realtek)"',
        () {
      expect(juzzioShortDeviceName('Hoparlör (Realtek(R) Audio)'),
          'Hoparlör (Realtek)');
      expect(juzzioShortDeviceName('Default - Speakers (USB Audio Device)'),
          'Speakers (USB)');
      expect(juzzioShortDeviceName('FxSound Speakers'), 'FxSound Speakers');
    });

    test('dil çifti etiketi "EN → TR"', () {
      expect(juzzioLangPairLabel('en', 'tr'), 'EN → TR');
      expect(juzzioLangPairLabel('pt-BR', 'tr'), 'PT → TR');
      expect(juzzioLangPairLabel('', 'tr'), '');
    });

    test('mesajla yanıtla: 4 hazır yanıt', () {
      expect(juzzioQuickReplies(_t).length, 4);
    });

    test('masaüstü sohbet listesi genişliği 320–420 px', () {
      expect(juzzioDesktopListWidth(1000), kJuzzioCenterPanelMinWidth);
      expect(juzzioDesktopListWidth(1440), 420);
      expect(juzzioDesktopListWidth(1100), closeTo(349.5, 0.1));
      expect(juzzioDesktopListWidth(2560), 420);
    });
  });

  group('taşmasız yerleşim', () {
    Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    for (final size in const [
      Size(390, 844),
      Size(360, 640),
      Size(1280, 800)
    ]) {
      testWidgets('gelen arama ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await pumpAt(
          tester,
          size,
          JuzzioIncomingCallView(
            callerName: 'Emily Carter',
            avatarUrl: null,
            isVideo: false,
            onAccept: () {},
            onDecline: () {},
            fromLang: 'en',
            toLang: 'tr',
            onMessageReply: () {},
            onRemindLater: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Emily Carter'), findsOneWidget);
        expect(find.text('EN → TR'), findsOneWidget);
        expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      });
    }

    testWidgets('canlı çeviri kartı: karşı taraf + Sen', (tester) async {
      await pumpAt(
        tester,
        const Size(390, 844),
        const Center(
          child: JuzzioLiveTranslationCard(
            pair: 'EN → TR',
            remote: JuzzioCallLine(
                speaker: 'Emily',
                original: 'Are you still coming to Istanbul next month?',
                translated: "Gelecek ay hâlâ İstanbul'a geliyor musun?"),
            mine: JuzzioCallLine(
                speaker: 'Sen',
                original: 'Evet, biletleri bu akşam aldım.',
                translated: 'Yes, I bought the tickets tonight.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text("Gelecek ay hâlâ İstanbul'a geliyor musun?"),
          findsOneWidget);
      expect(find.text('Yes, I bought the tickets tonight.'), findsOneWidget);
    });

    testWidgets('kontrol çubuğu 5 düğmeyle 360 px\'e sığar', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 640),
        Center(
          child: JuzzioCallDock(gap: 12, children: [
            for (var i = 0; i < 4; i++)
              JuzzioCallCircleButton(
                  icon: Icons.mic_none_rounded, size: 52, onTap: () {}),
            JuzzioCallCircleButton(
                icon: Icons.call_end_rounded,
                size: 62,
                danger: true,
                onTap: () {}),
          ]),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('kaynak bağlantıları', () {
    test('arama ekranı yeni düzenleri kullanır; yanlış "uçtan uca" iddiası yok',
        () {
      final c = _src('lib/screens/call_screen.dart');
      expect(c.contains('Widget _buildMobileVideoView('), isTrue);
      expect(c.contains('Widget _buildDesktopCallView('), isTrue);
      expect(c.contains('JuzzioDesktopAudioPanel('), isTrue);
      expect(c.contains('JuzzioLiveTranslationCard('), isTrue);
      expect(c.contains('Uçtan uca şifreli'), isFalse);
    });

    test('tam ekran arama masaüstünde pencerenin tamamını kullanır', () {
      expect(
          _src('lib/widgets/juzzio_desktop_frame.dart')
              .contains('call.view == JuzzioCallView.full'),
          isTrue);
    });

    test('gelen arama: mesajla yanıtla, sonra hatırlat, dil çifti bağlı', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains('onMessageReply: (call.roomId'), isTrue);
      expect(
          c.contains(
              'onRemindLater: call.isGroup ? null : _remindIncomingLater'),
          isTrue);
      expect(c.contains('_buildChatsHomeTab(p, s, appCtrl, desktop: true)'),
          isTrue);
    });

    test('KR-009: yeni yüzeyler Liquid Glass ile', () {
      final k = _src('lib/widgets/juzzio_call_gm9276.dart');
      expect(k.contains('JuzzioLiquidGlass('), isTrue);
      expect(k.contains('forceDark: true'), isTrue);
      expect(k.contains('JuzzioAuroraBackground('), isTrue);
    });
  });
}
