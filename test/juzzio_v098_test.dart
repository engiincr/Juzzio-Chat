// JUZZIO v0.9.8 birim testleri — 3D kil el ile kumaş yenileme
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';

void main() {
  // v1.2.1: sarkaç/kumaş zaman çizelgesi kompakt yenilemeyle kaldırıldı (bkz. juzzio_v121_test.dart)
  test('v1.1.1: raster el/kumaş varlıkları kaldırıldı (vektör çizim)', () {
    expect(Directory('assets/cloth').existsSync(), isFalse);
    expect(File('pubspec.yaml').readAsStringSync().contains('assets/cloth/'), isFalse);
  });
}
