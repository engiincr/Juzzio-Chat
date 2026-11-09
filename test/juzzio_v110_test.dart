// JUZZIO v1.1.0 birim testleri — arama altyazısı hayalet metin düzeltmesi, alıntı önizlemesi,
// hareket kiti (anahtarlar, yükleyiciler, gönderim, büyük emoji, kutlama, okundu tikleri)
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/services/juzzio_speech_gate.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_motion.dart';
import 'package:juzzio/widgets/juzzio_quote_preview.dart';

/// 100 ms'lik PCM16 parçası (16 kHz): [amp] genlikli sinüs (0 = sessizlik)
Uint8List _pcm(double amp, {int ms = 100, double hz = 220}) {
  final n = 16 * ms;
  final bd = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    bd.setInt16(i * 2, (amp * math.sin(2 * math.pi * hz * i / 16000)).round(), Endian.little);
  }
  return bd.buffer.asUint8List();
}

bool _allZero(List<Uint8List> out) => out.every((c) => c.every((b) => b == 0));

JuzzioMessage _msg({String text = '', String? image, String? video, String? audio, String type = 'text', bool deleted = false, int audioMs = 0, String? doc}) =>
    JuzzioMessage(
      id: 'm1',
      roomId: 'r',
      senderId: 's',
      messageType: type,
      sourceLang: 'tr',
      targetLang: 'en',
      originalText: text,
      translatedText: '',
      imageUrl: image,
      videoUrl: video,
      audioUrl: audio,
      documentName: doc,
      audioDurationMs: audioMs,
      isDeleted: deleted,
      createdAt: DateTime(2026, 11, 9),
    );

void main() {
  group('Arama altyazısı: konuşma kapısı (hayalet "Tamam aşkım" düzeltmesi)', () {
    test('sessizlik ve oda gürültüsü tanıyıcıya GERÇEK ses olarak gitmez', () {
      final g = JuzzioSpeechGate();
      var now = DateTime(2026, 11, 9, 23);
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(milliseconds: 100));
        // gürültü (RMS ~140) — kazanç kapalıyken tipik oda gürültüsü
        final out = g.process(_pcm(200), now);
        expect(_allZero(out), isTrue, reason: 'gürültü sıfırlanmalı');
      }
      expect(g.isOpen, isFalse);
      expect(g.voicedWithin(const Duration(seconds: 2), now), isFalse);
    });

    test('gerçek konuşmada kapı açılır, ilk hece için geçmiş eklenir, sonra kapanır', () {
      final g = JuzzioSpeechGate();
      var now = DateTime(2026, 11, 9, 23);
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 100));
        g.process(_pcm(150), now);
      }
      now = now.add(const Duration(milliseconds: 100));
      final first = g.process(_pcm(6000), now);
      expect(g.isOpen, isTrue);
      expect(first.length, greaterThan(1), reason: 'ön-kayıt (pre-roll) + parça');
      expect(_allZero([first.last]), isFalse);
      expect(g.voicedWithin(const Duration(milliseconds: 1500), now), isTrue);
      // susunca bekleme süresi sonunda kapı kapanır ve sıfır gönderilir
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 100));
        g.process(_pcm(100), now);
      }
      expect(g.isOpen, isFalse);
      now = now.add(const Duration(milliseconds: 100));
      expect(_allZero(g.process(_pcm(100), now)), isTrue);
    });

    test('kendi sonucumu kabul kuralları', () {
      // yerel ses yokken hiçbir metin kabul edilmez
      expect(juzzioAcceptOwnTranscript(text: 'Merhaba nasılsın', confidence: 0.99, localVoiceRecent: false), isFalse);
      // bilinen hayalet kalıp, düşük/orta güven → ret
      expect(juzzioAcceptOwnTranscript(text: 'Tamam aşkım.', confidence: 0.8, localVoiceRecent: true), isFalse);
      expect(juzzioAcceptOwnTranscript(text: 'Thanks for watching!', confidence: 0.85, localVoiceRecent: true), isFalse);
      // kısa ve düşük güven → ret
      expect(juzzioAcceptOwnTranscript(text: 'evet tamam', confidence: 0.6, localVoiceRecent: true), isFalse);
      // karşı taraf konuşurken ve ben konuşmuyorken (yankı) → ret
      expect(
        juzzioAcceptOwnTranscript(text: 'Bugün akşam yemeğe çıkalım mı', confidence: 0.9, localVoiceRecent: true, remoteSpeaking: true, localSpeaking: false),
        isFalse,
      );
      // gerçek konuşma → kabul
      expect(juzzioAcceptOwnTranscript(text: 'Bugün akşam yemeğe çıkalım mı', confidence: 0.93, localVoiceRecent: true), isTrue);
      expect(juzzioAcceptOwnTranscript(text: 'Tamam aşkım', confidence: 0.97, localVoiceRecent: true, localSpeaking: true), isTrue);
    });

    test('altyazı mikrofonu: yankı engelleme + gürültü bastırma açık, otomatik kazanç kapalı (kaynak sözleşmesi)', () {
      final src = File('lib/services/deepgram_livekit_service.dart').readAsStringSync();
      final i = src.indexOf('_sharedAudioTap.startStream(');
      final cfg = src.substring(i, src.indexOf(');', i));
      expect(cfg.contains('autoGain: false'), isTrue);
      expect(cfg.contains('echoCancel: true'), isTrue);
      expect(cfg.contains('noiseSuppress: true'), isTrue);
      expect(src.contains('_speechGate.process('), isTrue);
      expect(src.contains("'juzzio_subtitle_retract'"), isTrue);
    });
  });

  group('Alıntı önizlemesi', () {
    test('görsel alıntı resim yazısı değil küçük resim + "Fotoğraf"', () {
      final img = _msg(image: 'https://x/y.jpg', type: 'image');
      expect(juzzioQuoteKind(img), JuzzioQuoteKind.image);
      expect(juzzioQuoteLabel(img, 'tr'), 'Fotoğraf');
      expect(juzzioQuoteLabel(_msg(image: 'https://x/y.jpg', text: '📷'), 'en'), 'Photo');
      // kullanıcının yazdığı açıklama korunur
      expect(juzzioQuoteLabel(_msg(image: 'https://x/y.jpg', text: 'Deniz kenarı'), 'tr'), 'Deniz kenarı');
    });

    test('video, sesli mesaj, belge, silinmiş ve bulunamayan', () {
      expect(juzzioQuoteKind(_msg(video: 'v.mp4')), JuzzioQuoteKind.video);
      expect(juzzioQuoteLabel(_msg(audio: 'a.m4a', type: 'voice', audioMs: 65000), 'tr'), 'Sesli mesaj · 1:05');
      expect(juzzioQuoteLabel(_msg(type: 'document', doc: 'rapor.pdf'), 'tr'), 'rapor.pdf');
      expect(juzzioQuoteKind(_msg(text: 'x', deleted: true)), JuzzioQuoteKind.deleted);
      expect(juzzioQuoteKind(null), JuzzioQuoteKind.missing);
      expect(juzzioQuoteLabel(_msg(text: 'Merhaba'), 'tr'), 'Merhaba');
    });

    testWidgets('alıntıya dokununca alıntılanan mesaja gidilir', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JuzzioQuotePreview(quoted: _msg(text: 'Selam'), senderLabel: 'Ayşe', isMe: false, onTap: () => tapped++),
        ),
      ));
      await tester.tap(find.text('Selam'));
      expect(tapped, 1);
    });

    test('sohbet ekranı alıntıya dokununca _jumpToMessage çağırır (kaynak sözleşmesi)', () {
      final src = File('lib/screens/chat_screen.dart').readAsStringSync();
      expect(src.contains('onTap: () => _jumpToMessage(msg.replyToId!)'), isTrue);
      expect(src.contains('Future<void> _jumpToMessage(String id)'), isTrue);
    });
  });

  group('Hareket kiti', () {
    test('büyük emoji: yalnız 1–3 emoji', () {
      expect(juzzioBigEmojiCount('👍'), 1);
      expect(juzzioBigEmojiCount(' ❤️ 🔥 '), 2);
      expect(juzzioBigEmojiCount('👨‍👩‍👧'), 1);
      expect(juzzioBigEmojiCount('😂😂😂😂'), 0);
      expect(juzzioBigEmojiCount('tamam 👍'), 0);
      expect(juzzioBigEmojiCount('123'), 0);
    });

    test('kutlama algılama (TR/EN/DE, büyük harf)', () {
      expect(juzzioIsCelebration('İyi ki doğdun canım!'), isTrue);
      expect(juzzioIsCelebration('MUTLU YILLAR'), isTrue);
      expect(juzzioIsCelebration('TEBRİKLER'), isTrue);
      expect(juzzioIsCelebration('Happy Birthday!!'), isTrue);
      expect(juzzioIsCelebration('Herzlichen Glückwunsch'), isTrue);
      expect(juzzioIsCelebration('🎉'), isTrue);
      expect(juzzioIsCelebration('Yarın görüşürüz'), isFalse);
    });

    test('yeni balon girişi yalnız taze mesajda ve bir kez oynar', () {
      final now = DateTime(2026, 11, 9, 23);
      expect(JuzzioBubbleEntrance.shouldPlay('k1', now.subtract(const Duration(seconds: 2)), now), isTrue);
      JuzzioBubbleEntrance.markPlayed('k1');
      expect(JuzzioBubbleEntrance.shouldPlay('k1', now, now), isFalse);
      expect(JuzzioBubbleEntrance.shouldPlay('k2', now.subtract(const Duration(minutes: 5)), now), isFalse);
    });

    testWidgets('anahtar: dokununca değişir, sürükleyince de', (tester) async {
      var v = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, set) => JuzzioSwitch(value: v, onChanged: (x) => set(() => v = x)),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(JuzzioSwitch));
      await tester.pumpAndSettle();
      expect(v, isTrue);
      for (final style in JuzzioToggleStyle.values) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: JuzzioSwitch(value: true, onChanged: (_) {}, style: style)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: style.name);
      }
    });

    testWidgets('liste satırı anahtarı: satıra dokunmak değeri çevirir', (tester) async {
      var v = true;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) => JuzzioSwitchListTile(
              value: v,
              style: JuzzioToggleStyle.check,
              title: const Text('Okundu bilgisi'),
              onChanged: (x) => set(() => v = x),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Okundu bilgisi'));
      await tester.pumpAndSettle();
      expect(v, isFalse);
    });

    testWidgets('yörünge yükleyici CircularProgressIndicator gibi boyutlanır', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Center(child: JuzzioOrbitLoader())));
      expect(tester.getSize(find.byType(JuzzioOrbitLoader)), const Size(36, 36));
      await tester.pumpWidget(const MaterialApp(home: Center(child: SizedBox(width: 18, height: 18, child: JuzzioOrbitLoader(strokeWidth: 2)))));
      expect(tester.getSize(find.byType(JuzzioOrbitLoader)), const Size(18, 18));
      await tester.pumpWidget(const MaterialApp(home: Center(child: JuzzioPercentRing(value: 0.62, size: 80))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('62%'), findsOneWidget);
    });

    testWidgets('kıvılcım çubuğu ve okundu tikleri hatasız çizilir', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            JuzzioSparklerBar(value: 0.4),
            JuzzioSparklerBar(),
            JuzzioReceiptTicks(state: JuzzioReceipt.sending),
            JuzzioReceiptTicks(state: JuzzioReceipt.read, fresh: true),
            JuzzioMorphIcon(kind: JuzzioMorph.kebab, open: true),
            JuzzioMorphIcon(kind: JuzzioMorph.ringX, open: false),
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('eylem sayfası seçilen sırayı döndürür', (tester) async {
      int? picked = -1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showJuzzioActionSheet(context, title: 'Sil?', actions: const [JuzzioSheetAction('Sil', destructive: true)]);
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(picked, 0);
    });
  });

  test('Yeni logo: uyarlanabilir + tematik ikon tanımlı, kaynak SVG mevcut', () {
    final xml = File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(xml.contains('<monochrome'), isTrue);
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png').existsSync(), isTrue, reason: d);
    }
    expect(File('tools/brand/juzzio_logo.svg').existsSync(), isTrue);
  });

  test('Sürüm notu 1.1.0 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.1.0');
    expect(n.versionCode, 110);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
