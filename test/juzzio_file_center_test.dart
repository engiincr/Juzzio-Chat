import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/file_center_page.dart';

void main() {
  test('mesaj türleri doğru kategoriye düşer', () {
    expect(JuzzioFileCenterFilter.kindOf('image'), JuzzioFileKind.media);
    expect(JuzzioFileCenterFilter.kindOf('video'), JuzzioFileKind.media);
    expect(JuzzioFileCenterFilter.kindOf('document'), JuzzioFileKind.documents);
    expect(JuzzioFileCenterFilter.kindOf('voice'), JuzzioFileKind.voice);
    expect(JuzzioFileCenterFilter.kindOf('text'), isNull);
  });

  test('sayımlar yalnız dosya türlerini içerir', () {
    final c = JuzzioFileCenterFilter.counts(['image', 'text', 'voice', 'video', 'document', 'voice']);
    expect(c[JuzzioFileKind.media], 2);
    expect(c[JuzzioFileKind.documents], 1);
    expect(c[JuzzioFileKind.voice], 2);
  });
}
