// JUZZIO v0.8.4 — Liquid Glass tasarım ailesi, sohbet teması olarak cam paletleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_custom_theme.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final app = JuzzioAppController.instance;

  tearDown(() {
    JuzzioGlassTokens.characterResolver = () => JuzzioGlassCharacter.standard;
    JuzzioGlassTokens.custom = null;
    JuzzioGlassTokens.intensity = 1.0;
    app.setChatTheme(0);
    app.setChatThemeIntensity(1.0);
  });

  test('12 temanın her biri kendi cam karakterine sahip', () {
    expect(kJuzzioAuroraPalettes.length, 12);
    for (final p in kJuzzioAuroraPalettes) {
      expect(kJuzzioGlassCharacters.containsKey(p.id), isTrue, reason: p.id);
      final c = p.character;
      expect(c.tr.trim(), isNotEmpty);
      expect(c.en.trim(), isNotEmpty);
      for (final v in [c.blur, c.opacity, c.sheen, c.depth]) {
        expect(v, inInclusiveRange(0.4, 2.0), reason: p.id);
      }
    }
    expect(kJuzzioAuroraPalettes.first.id, 'juzzio_liquid');
    expect(juzzioAuroraPaletteById('cyber_neon').character.glow, greaterThan(0));
  });

  test('Cam paleti sohbet teması olarak seçilir, doğrulanır ve kaydedilir', () {
    app.setChatPalette('amethyst');
    expect(app.chatPaletteId, 'amethyst');
    expect(app.chatPalette?.id, 'amethyst');
    expect(app.preferencesSnapshot()['chatPalette'], 'amethyst');
    app.setChatPalette('yok_boyle_tema');
    expect(app.chatPaletteId, isEmpty);
    expect(app.chatPalette, isNull);
  });

  test('Klasik sohbet ön ayarı seçilince cam paleti temizlenir; yoğunluk ayarı paleti korur', () {
    app.setChatPalette('lagoon');
    app.setChatThemeIntensity(1.2);
    expect(app.chatPaletteId, 'lagoon', reason: 'parlaklık kaydırıcısı seçimi bozmamalı');
    expect(app.chatThemeIntensity, closeTo(1.2, 1e-9));
    app.setChatTheme(3);
    expect(app.chatPaletteId, isEmpty);
    expect(app.selectedChatThemeIndex, 3);
  });

  test('Sohbet balonu seçilen cam paletinin rengini taşır ve beyaz yazı okunur kalır', () {
    app.setChatThemeIntensity(1.0);
    double lum(Color c) => c.computeLuminance();
    for (final dark in [true, false]) {
      final p = JuzzioPalette(dark);
      for (final pal in kJuzzioAuroraPalettes) {
        app.setChatPalette(pal.id);
        final bubble = p.outgoingBubble;
        final page = dark ? pal.base : pal.baseLight;
        final onPage = Color.alphaBlend(bubble, page);
        final ratio = 1.05 / (lum(onPage) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${pal.id} dark=$dark kontrast=$ratio');
      }
    }
  });

  test('Cam karakteri opaklık ve blur değerlerini ölçekler; özel temada devre dışı', () {
    final baseAlpha = JuzzioGlassTokens.surface.a;
    final baseBlur = JuzzioGlassTokens.baseBlur;
    JuzzioGlassTokens.characterResolver = () => juzzioAuroraPaletteById('glass_white').character;
    expect(JuzzioGlassTokens.surface.a, lessThan(baseAlpha));
    expect(JuzzioGlassTokens.baseBlur, greaterThan(baseBlur));
    JuzzioGlassTokens.characterResolver = () => juzzioAuroraPaletteById('high_contrast').character;
    expect(JuzzioGlassTokens.surface.a, greaterThan(baseAlpha));
    JuzzioGlassTokens.custom = JuzzioCustomTheme.blank(id: 'ct_test01', name: 'T', dark: true);
    expect(identical(JuzzioGlassTokens.character, JuzzioGlassCharacter.standard), isTrue);
  });
}
