// JUZZIO v0.9.8 birim testleri — 3D kil el ile kumaş yenileme
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';

void main() {
  test('Faz 2 sarkaç: −15° → +25° → merkez', () {
    expect(juzzioPendulumDegrees(0), 0);
    expect(juzzioPendulumDegrees(0.30), closeTo(-15, 0.01));
    expect(juzzioPendulumDegrees(0.75), closeTo(25, 0.01));
    expect(juzzioPendulumDegrees(1.10), closeTo(-8, 0.01));
    expect(juzzioPendulumDegrees(1.40).abs(), lessThan(0.01));
    // tepe noktalarında yavaşlar (smoothstep): ortadaki hız uçlardan büyük
    final mid = (juzzioPendulumDegrees(0.53) - juzzioPendulumDegrees(0.52)).abs();
    final end = (juzzioPendulumDegrees(0.75) - juzzioPendulumDegrees(0.74)).abs();
    expect(mid, greaterThan(end));
    // yenileme uzarsa salınım sürer ama ±9°'yi aşmaz
    for (var t = 1.5; t < 8; t += 0.1) {
      expect(juzzioPendulumDegrees(t).abs(), lessThanOrEqualTo(9.0001));
    }
  });

  test('Faz 1 içerik kayması 140–156 px aralığında (v0.9.9)', () {
    expect(juzzioClothExtent(560), inInclusiveRange(140, 156));
    expect(juzzioClothExtent(2000), lessThanOrEqualTo(156));
  });

  test('Faz 3-5 süreleri talimattaki zaman çizelgesiyle aynı', () {
    expect(kJuzzioClenchDur, closeTo(0.30, 1e-9)); // 1,8–2,1 sn
    expect(kJuzzioYankDur, closeTo(0.50, 1e-9)); // 2,1–2,6 sn
    expect(kJuzzioSmoothDur, closeTo(0.25, 1e-9)); // ~250 ms ütüleme
  });

  test('v1.1.1: raster el/kumaş varlıkları kaldırıldı (vektör çizim)', () {
    expect(Directory('assets/cloth').existsSync(), isFalse);
    expect(File('pubspec.yaml').readAsStringSync().contains('assets/cloth/'), isFalse);
  });
}
