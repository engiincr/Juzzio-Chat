// JUZZIO v1.2.3 — iki kutulu onay: koşullar + 15 yaş + aydınlatma beyanı (zorunlu), ticari ileti (isteğe bağlı)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/juzzio_consent.dart';

String _src(String p) => File(p).readAsStringSync();

/// pumpAndSettle yerine sınırlı süreli pompalama: sonsuz bir animasyon testi asla askıda bırakmaz
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('yalnız iki seçenek; yurt dışı aktarım rıza olarak gönderilmez', () {
    const s = JuzzioConsentState();
    expect(s.requiredAccepted, isFalse);
    final ok = s.copyWith(termsNotice: true);
    expect(ok.requiredAccepted, isTrue);
    final rpc = ok.toRpc();
    expect(rpc['p_privacy'], isTrue);
    expect(rpc['p_terms'], isTrue);
    expect(rpc['p_age'], isTrue);
    expect(rpc['p_cross_border'], isFalse);
    expect(rpc['p_marketing'], isFalse);
    expect(kJuzzioConsentVersion, '2026-11-10.2');
  });

  test('aydınlatma metni onay istemez; m.10 unsurları ve m.9 güvencesi yer alır', () {
    final src = _src('lib/widgets/juzzio_consent.dart');
    for (final k in [
      'Bu metin bir onay metni değildir',
      'Toplama yöntemi',
      'uygun güvencelere',
      'KVKK m.14',
      'Okudum ve anladım',
      'bu bir rıza değildir',
      'İleti Yönetim Sistemi',
    ]) {
      expect(src.contains(k), isTrue, reason: k);
    }
    expect(src.contains('açık rıza veriyorum.\n\nJuzzio'), isFalse);
    expect(src.contains('withAllRequired'), isFalse);
  });

  test('yasal markdown düz metne çevrilir', () {
    final t = juzzioPlainLegal('# Başlık\n\n## 1. Kabul\n\n- **kalın** ve [bağlantı](https://x.y)\n> not');
    expect(t, 'Başlık\n\n1. Kabul\n\n• kalın ve bağlantı\nnot');
  });

  test('sona inildi kuralı', () {
    expect(juzzioReachedEnd(0), isTrue);
    expect(juzzioReachedEnd(24), isTrue);
    expect(juzzioReachedEnd(25), isFalse);
  });

  testWidgets('okuyucu: sona inilmeden onay düğmesi pasif, sonda etkin', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: JuzzioConsentReader(
                      title: 'T',
                      sections: [('A', List.generate(150, (i) => 'satır $i').join('\n'))],
                      confirmLabel: 'Okudum ve anladım',
                    ),
                  ),
                ));
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await _settle(tester);
    final confirmFinder = find.byKey(const ValueKey('consent_confirm'));
    expect(confirmFinder, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(confirmFinder).onPressed, isNull);
    // elle sona kadar kaydır (fling + gerekirse tekrar)
    for (var i = 0; i < 12 && tester.widget<ButtonStyleButton>(confirmFinder).onPressed == null; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await _settle(tester);
    }
    expect(tester.widget<ButtonStyleButton>(confirmFinder).onPressed, isNotNull);
    await tester.tap(confirmFinder);
    await _settle(tester);
    expect(result, isTrue);
  });

  testWidgets('okuyucu: kısa metinde düğme hemen etkin', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: JuzzioConsentReader(title: 'T', sections: [('A', 'kısa')], confirmLabel: 'Tamam'),
      ),
    ));
    await _settle(tester);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('consent_confirm'))).onPressed, isNotNull);
  });

  test('giriş/kayıt: işaretlenmemişse metin otomatik açılır, sonra devam eder', () {
    final m = _src('lib/main.dart');
    expect(m.contains('await juzzioOpenRequiredConsent(context)'), isTrue);
    expect(m.contains('_consent.copyWith(termsNotice: true)'), isTrue);
  });

  test('sunucu: yurt dışı aktarım rızası zorunlu değil', () {
    final sql = _src('supabase/juzzio_database.sql');
    final last = sql.substring(sql.lastIndexOf('CREATE OR REPLACE FUNCTION public.record_juzzio_consent('));
    expect(last.contains('AND COALESCE(p_cross_border, false)) THEN'), isFalse);
  });

  test('Sürüm notu 1.2.3', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.3');
    expect(n.versionName, '1.2.3');
    expect(n.versionCode, 123);
  });
}
