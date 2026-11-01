// v0.8.1 tema motoru birim testleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    JuzzioGlassTokens.intensity = 1.0;
    JuzzioGlassTokens.highContrastResolver = () => false;
    JuzzioGlassTokens.isDarkResolver = () => true;
  });

  test('Bilinmeyen/bozuk tema kimliği güvenli varsayılana döner', () {
    expect(juzzioAuroraPaletteById(null).id, kJuzzioAuroraPalettes.first.id);
    expect(juzzioAuroraPaletteById('').id, kJuzzioAuroraPalettes.first.id);
    expect(juzzioAuroraPaletteById('<script>').id, kJuzzioAuroraPalettes.first.id);
  });

  test('Tema kataloğu benzersiz ve genişletilmiş', () {
    final ids = kJuzzioAuroraPalettes.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(<String>['juzzio_liquid', 'obsidian_oled', 'lavender_mist', 'rose_quartz', 'cyber_neon', 'high_contrast']));
  });

  test('Cam yoğunluğu yüzey opaklığını ölçekler', () {
    JuzzioGlassTokens.intensity = 1.0;
    final base = JuzzioGlassTokens.surface.a;
    JuzzioGlassTokens.intensity = 1.4;
    expect(JuzzioGlassTokens.surface.a, greaterThan(base));
    JuzzioGlassTokens.intensity = 0.6;
    expect(JuzzioGlassTokens.surface.a, lessThan(base));
  });

  test('Yüksek kontrast kenarları ve ikincil metni belirginleştirir', () {
    final b = JuzzioGlassTokens.border.a;
    final t = JuzzioGlassTokens.textSecondary;
    JuzzioGlassTokens.highContrastResolver = () => true;
    expect(JuzzioGlassTokens.border.a, greaterThan(b));
    expect(JuzzioGlassTokens.textSecondary.computeLuminance(), greaterThan(t.computeLuminance()));
  });

  test('Açık ve koyu tema aynı cam bileşen temalarını üretir', () {
    final dark = buildJuzzioDarkTheme(fontFamily: 'x', transitions: const PageTransitionsTheme());
    final light = buildJuzzioDarkTheme(fontFamily: 'x', transitions: const PageTransitionsTheme(), dark: false);
    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(light.dialogTheme.backgroundColor, isNotNull);
    expect(light.snackBarTheme.behavior, SnackBarBehavior.floating);
  });

  test('Cam yoğunluğu güvenli aralıkta tutulur', () {
    final app = JuzzioAppController.instance;
    app.setGlassIntensity(9, persist: false);
    expect(app.glassIntensity, 1.4);
    app.setGlassIntensity(-3, persist: false);
    expect(app.glassIntensity, 0.6);
    app.setGlassIntensity(double.nan, persist: false);
    expect(app.glassIntensity, 1.0);
  });
}
