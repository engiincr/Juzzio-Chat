// GM-014-K — 18 tema × gece/gündüz okunurluk testi (WCAG kontrast oranı).
// Her temada: vurgu dolgusunun üstündeki yazı (onGlow) ≥ 4.5:1,
// vurgu rengindeki yazı/ikon (glow gece, glowLight gündüz) zemin üzerinde ≥ 4.5:1 (küçük metin dahil).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('19 tema kayıtlı (Amber Altın dahil) ve varsayılan Grafit Limon', () {
    expect(kJuzzioAuroraPalettes.length, greaterThanOrEqualTo(14)); // GM-032
    expect(kJuzzioAuroraPalettes.first.id, 'graphite_lime');
    expect(kJuzzioAuroraPalettes.any((p) => p.id == 'amber_gold'), isTrue);
  });

  for (final pal in kJuzzioAuroraPalettes) {
    for (final dark in [true, false]) {
      test('${pal.id} · ${dark ? 'gece' : 'gündüz'}: düğme yazısı ve vurgu metni okunur', () {
        final sp = pal.space;
        final fill = sp.glow;
        final on = sp.onGlow(dark);
        expect(_contrast(on, fill), greaterThanOrEqualTo(4.5), reason: 'onGlow/glow ${pal.id}');
        final bgs = dark ? sp.depth : sp.depthLight;
        final accentText = dark ? sp.glow : sp.glowLight;
        for (final bg in bgs) {
          expect(_contrast(accentText, bg), greaterThanOrEqualTo(4.5), reason: 'vurgu metni / zemin ${pal.id} ${dark ? 'gece' : 'gündüz'}');
        }
      });
    }
  }
}
