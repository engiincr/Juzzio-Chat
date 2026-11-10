// JUZZIO v1.2.3 — iki kutulu onay: koşullar + 15 yaş + aydınlatma beyanı (zorunlu), ticari ileti (isteğe bağlı)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/juzzio_consent.dart';

String _src(String p) => File(p).readAsStringSync();

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

  testWidgets('okuyucu: sona inilmeden onay düğmesi pasif, sonda etkin', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: JuzzioConsentReader(
                      title: 'T',
                      sections: [('A', List.filled(400, 'satır').join('\n'))],
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
    await tester.pumpAndSettle();
    FilledButton confirm() => tester.widget<FilledButton>(find.byKey(const ValueKey('consent_confirm')));
    expect(confirm().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('consent_to_end')));
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('consent_confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
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

  test('Sürüm notu 1.2.3 en üstte', () {
    final n = kJuzzioBundledReleaseNotes.first;
    expect(n.versionName, '1.2.3');
    expect(n.versionCode, 123);
  });
}
