// v1.3.2 — Windows sürümü: masaüstü paneli, giriş hata kodları, emoji yazı tipi sırası
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';
import 'package:juzzio/services/supabase_service.dart' show juzzioFunctionErrorCode;
import 'package:juzzio/widgets/juzzio_desktop_frame.dart';

void main() {
  test('dar pencerede uygulama tam pencere, genişte ortada panel', () {
    expect(juzzioDesktopPanelSize(const Size(440, 900)), isNull);
    expect(juzzioDesktopPanelSize(const Size(600, 900)), isNull);
    final p = juzzioDesktopPanelSize(const Size(1280, 800))!;
    expect(p.width, kJuzzioDesktopPanelWidth);
    expect(p.height, 760);
    final low = juzzioDesktopPanelSize(const Size(1280, 700))!;
    expect(low.height, 700);
  });

  test('giriş hatası: sunucu kodu her biçimde okunur, bilinmeyen hata "şifre hatalı" sayılmaz', () {
    expect(juzzioFunctionErrorCode(401, {'error': 'invalid_credentials'}), 'invalid_credentials');
    expect(juzzioFunctionErrorCode(429, '{"ok":false,"error":"rate_limited"}'), 'rate_limited');
    expect(juzzioFunctionErrorCode(500, 'Internal Server Error'), 'server_error');
    expect(juzzioFunctionErrorCode(429, null), 'rate_limited');
    expect(juzzioFunctionErrorCode(401, '{"message":"Unregistered API key"}'), 'invalid_credentials');
  });

  test('metin yedek yazı tipi emoji yazı tipinden ÖNCE (Windows rakam/boşluk hatası)', () {
    expect(kJuzzioEmojiFallback.first, 'Segoe UI');
    expect(kJuzzioEmojiFallback.last, 'JuzzioEmoji');
  });
}
