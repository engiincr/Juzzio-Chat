import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';

/// OTA: version.json bozulmalarına dayanıklılık (GitHub Actions'taki
/// "JSONDecodeError: Extra data" hatasının uygulama tarafındaki karşılığı).
void main() {
  const good = '{"version":"0.3.0","build":30,"buildNumber":30,"versionCode":30,'
      '"url":"https://example.com/a.apk","changelog":{"tr":"Türkçe {not}","en":"x"}}';

  List<int> utf16le(String s, {bool bom = false}) {
    final out = <int>[if (bom) ...[0xFF, 0xFE]];
    for (final u in s.codeUnits) {
      out..add(u & 0xFF)..add(u >> 8);
    }
    return out;
  }

  void expectGood(Map<String, dynamic>? m) {
    expect(m, isNotNull);
    expect(m!['version'], '0.3.0');
    expect(m['build'], 30);
    expect((m['changelog'] as Map)['tr'], 'Türkçe {not}');
  }

  test('geçerli JSON', () {
    expectGood(JuzzioAppController.parseVersionManifest(utf8.encode(good)));
  });

  test('UTF-16 kuyruklu (PowerShell Add-Content)', () {
    expectGood(JuzzioAppController.parseVersionManifest([...utf8.encode('$good\n'), 13, 0, 10, 0]));
  });

  test('ardışık iki JSON (Extra data)', () {
    expectGood(JuzzioAppController.parseVersionManifest(utf8.encode('$good\n$good')));
  });

  test('UTF-8 BOM', () {
    expectGood(JuzzioAppController.parseVersionManifest([0xEF, 0xBB, 0xBF, ...utf8.encode(good)]));
  });

  test('tamamen UTF-16 (BOM ile ve BOM olmadan)', () {
    expectGood(JuzzioAppController.parseVersionManifest(utf16le(good, bom: true)));
    expectGood(JuzzioAppController.parseVersionManifest(utf16le(good)));
  });

  test('bozuk / boş girdiler null döner, istisna fırlatmaz', () {
    expect(JuzzioAppController.parseVersionManifest(const []), isNull);
    expect(JuzzioAppController.parseVersionManifest(utf8.encode('   ')), isNull);
    expect(JuzzioAppController.parseVersionManifest(utf8.encode('{"version": "0.1')), isNull);
    expect(JuzzioAppController.parseVersionManifest(utf8.encode('[1,2,3]')), isNull);
  });
}
