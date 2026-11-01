// JUZZIO v0.8.0 birim testleri
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/pq/juzzio_pq.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/social_common_widgets.dart';

import 'juzzio_v080_vectors.dart';

void main() {
  test('Gönderi metnindeki fazla boşluklar sadeleşir', () {
    expect(juzzioTidyText('Merhaba,test     ediyorum'), 'Merhaba,test ediyorum');
    expect(juzzioTidyText('a  b'), 'a b');
    expect(juzzioTidyText('x\n\n\n\ny'), 'x\n\ny');
  });

  test('Açık anahtarsız derlemede yayın imzası zorunlu değil', () {
    expect(JuzzioAppController.verifyReleaseSignature({'version': '0.8.0'}), isTrue);
  });

  test('version.json ML-DSA-65 imza biçimi (CI betiğiyle aynı ileti)', () {
    final pk = base64Decode(kReleasePkB64);
    final sig = base64Decode(kReleaseSigB64);
    final ctx = utf8.encode('juzzio-release');
    expect(JuzzioMlDsa65.verify(pk, utf8.encode('juzzio-release|0.8.0|1234|abcdef0123'), sig, ctx: ctx), isTrue);
    expect(JuzzioMlDsa65.verify(pk, utf8.encode('juzzio-release|0.8.1|1234|abcdef0123'), sig, ctx: ctx), isFalse);
  });

  test('Uygulamaya gömülü 0.8.0 notları en üstte ve 0.6.1/0.7.0 korunuyor', () {
    final notes = JuzzioReleaseNote.mergeAll(const <JuzzioReleaseNote>[]);
    expect(notes.any((n) => n.versionName == '0.8.0'), isTrue);
    expect(notes.any((n) => n.versionName == '0.7.0'), isTrue);
    expect(notes.any((n) => n.versionName == '0.6.1'), isTrue);
  });
}
