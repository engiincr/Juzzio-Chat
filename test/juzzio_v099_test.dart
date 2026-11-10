// JUZZIO v0.9.9 birim testleri — kumaş yenileme 11 maddelik revizyon
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';

void main() {
  final g = JuzzioRefreshGeometry(screenWidth: 360, topInset: 47);

  // v1.2.1: kumaş yenileme kompakt 3B "cloth-pinch" olarak yeniden yazıldı; eski geometri testleri
  // yeni kurallara (80 dp sınırı, çentikten çıkış, tırnaksız kil el) uyarlandı.
  test('1) Dynamic Island tam siyah; el çentiğin alt kenarından çıkar', () {
    expect(kJuzzioIslandColor, const Color(0xFF000000));
    expect(g.islandBottomY, greaterThan(g.islandCenterY));
    expect(g.embedded, isFalse);
    expect(g.originY, closeTo(g.islandBottomY, 1e-9));
  });

  test('3) Kil el: yumrukta parmaklar kısalır, renkler açık ton (siyah yok)', () {
    final open = JuzzioHandShape(0);
    final fist = JuzzioHandShape(1);
    expect(fist.lowestY, lessThan(open.lowestY));
    double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    for (final c in [JuzzioHandColors.skin, JuzzioHandColors.shade, JuzzioHandColors.light]) {
      expect(lum(c), greaterThan(0.35));
    }
  });

  test('9) Gömülü liste: el başlığın değil listenin üst kenarından çıkar', () {
    final e = JuzzioRefreshGeometry(screenWidth: 360, topInset: 47, contentTop: 120);
    expect(e.embedded, isTrue);
    expect(e.originY, 0);
  });

  test('Sürüm notu 0.9.9 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '0.9.9');
    expect(n.versionCode, 99);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });

  test('Bağımlılıklar: file_picker ^13 (win32 ^6 uyumlu), şifreli depo ^11 korunur', () {
    final p = File('pubspec.yaml').readAsStringSync();
    expect(p, contains('file_picker: ^13.'));
    expect(p, contains('flutter_secure_storage: ^11.'));
    expect(File('lib/screens/chat_screen.dart').readAsStringSync(), isNot(contains('FilePicker.platform')));
  });
}
