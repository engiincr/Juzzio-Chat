// JUZZIO v0.9.9 birim testleri — kumaş yenileme 11 maddelik revizyon
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';

void main() {
  final g = JuzzioClothGeometry(screenWidth: 360, topInset: 47);

  test('1) Dynamic Island tam siyah; el çentik alt kenarından çıkar', () {
    expect(kJuzzioIslandColor, const Color(0xFF000000));
    expect(g.islandBottomY, greaterThan(g.islandCenterY));
    // kök (reveal = 0) iken elin ucu tam çentiğin alt kenarında
    expect(g.rootY(0) + g.openTip, closeTo(g.islandBottomY, 1e-9));
    // tam açıkken kök çentik merkezinde sabit
    expect(g.rootY(g.maxVisible), closeTo(g.islandCenterY, 1e-9));
  });

  test('2) İlk 35 px çekişte yalnız parmak uçları görünür', () {
    final c = juzzioClothExtent(35);
    final r = juzzioPeekReveal(c, g.restContent, g.maxVisible);
    expect(r, greaterThan(4)); // parmak uçları görünür
    expect(r, lessThan(22)); // avuç/bilek henüz görünmez
    expect(juzzioPeekReveal(g.restContent, g.restContent, g.maxVisible), closeTo(g.maxVisible, 1e-9));
  });

  test('3) Bilek genişliği ≈ çentik genişliğinin %55\'i', () {
    expect(63 * g.scale / g.islandWidth, closeTo(0.55, 0.02));
  });

  test('4) Sarkaç pozları −15°…+25°, komşu kare seçimi', () {
    expect(kJuzzioSwingAngles.first, -15);
    expect(kJuzzioSwingAngles.last, 25);
    expect(juzzioSwingFrame(0), (3, 4, 0.0));
    final (i0, i1, f) = juzzioSwingFrame(22.5);
    expect((i0, i1), (7, 8));
    expect(f, closeTo(0.5, 1e-9));
    expect(juzzioSwingFrame(40).$1, 8);
  });

  test('7) Kumaş renkleri: aydınlıkta siyah yok, koyuda beyaz yok', () {
    double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    expect(kJuzzioFoldLightRidge, const Color(0xFFFFFFFF));
    expect(kJuzzioFoldLightValley, const Color(0xFFC8CDD6));
    expect(lum(kJuzzioFoldLightValley), greaterThan(0.75));
    expect(kJuzzioFoldDarkValley, const Color(0xFF07080B));
    expect(kJuzzioFoldDarkRidge, const Color(0xFF222630));
    expect(lum(kJuzzioFoldDarkRidge), lessThan(0.2));
  });

  test('9) İçerik 140–155 px kayar; el ucu ile içerik arasında boşluk', () {
    for (final w in [320.0, 360.0, 393.0, 430.0]) {
      for (final top in [0.0, 24.0, 47.0, 59.0]) {
        final q = JuzzioClothGeometry(screenWidth: w, topInset: top);
        expect(q.restContent, inInclusiveRange(140, 155));
        expect(q.threshold, lessThan(q.restContent));
      }
    }
    expect(g.contentTop + g.restContent, greaterThan(g.islandCenterY + g.openTip + 16));
  });

  test('10) Yukarı çekmede içerik yumruğun alt sınırına bağlı', () {
    final from = g.rootY(g.maxVisible + 8) + g.fistLow;
    expect(juzzioYankContent(fistLowY: from, fistLowFromY: from, islandBottomY: g.islandBottomY, rest: 150), 150);
    expect(juzzioYankContent(fistLowY: g.islandBottomY, fistLowFromY: from, islandBottomY: g.islandBottomY, rest: 150), 0);
    final mid = (from + g.islandBottomY) / 2;
    expect(juzzioYankContent(fistLowY: mid, fistLowFromY: from, islandBottomY: g.islandBottomY, rest: 150), closeTo(75, 1e-9));
  });

  test('11) Ütüleme 250 ms', () {
    expect(kJuzzioSmoothDur, closeTo(0.25, 1e-9));
  });

  test('Sürüm notu 0.9.9 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '0.9.9');
    expect(n.versionCode, 99);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
