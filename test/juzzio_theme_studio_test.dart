// JUZZIO v0.8.2 — Tema Stüdyosu ve tema motoru testleri (Faz 2)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_custom_theme.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';

JuzzioCustomTheme _sample() => JuzzioCustomTheme.blank(id: 'ct_test01', name: 'Deneme', dark: true)
    .withColor('text', const Color(0xFFFAFAFA))
    .withColor('button', const Color(0xFF22D3EE))
    .copyWith(blur: 22, opacity: 0.4, intensity: 1.2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    JuzzioGlassTokens.custom = null;
    JuzzioGlassTokens.intensity = 1.0;
    JuzzioGlassTokens.highContrastResolver = () => false;
    JuzzioGlassTokens.isDarkResolver = () => true;
  });

  group('JSON içe/dışa aktarma', () {
    test('Dışa aktar → içe aktar aynı temayı verir (yeni kimlikle)', () {
      final t = _sample();
      final res = JuzzioCustomTheme.parse(t.toPrettyJson(), newId: 'ct_import1');
      expect(res.ok, isTrue, reason: res.errors.join(';'));
      final r = res.theme!;
      expect(r.id, 'ct_import1');
      expect(r.name, 'Deneme');
      expect(r.dark, isTrue);
      expect(r.blur, 22);
      expect(r.opacity, 0.4);
      expect(r.intensity, 1.2);
      for (final k in JuzzioCustomTheme.colorRoles.keys) {
        expect(r.c(k).toARGB32(), t.c(k).toARGB32(), reason: k);
      }
    });

    test('Bozuk JSON reddedilir', () {
      expect(JuzzioCustomTheme.parse('{bozuk', newId: 'x').ok, isFalse);
      expect(JuzzioCustomTheme.parse('[1,2]', newId: 'x').ok, isFalse);
      expect(JuzzioCustomTheme.parse('', newId: 'x').ok, isFalse);
    });

    test('Yanlış şema / gelecek sürüm reddedilir', () {
      final m = _sample().toJson();
      expect(JuzzioCustomTheme.parse(jsonEncode({...m, 'schema': 'baska'}), newId: 'x').ok, isFalse);
      expect(JuzzioCustomTheme.parse(jsonEncode({...m, 'version': 99}), newId: 'x').ok, isFalse);
    });

    test('Geçersiz HEX reddedilir ve hangi alan olduğu söylenir', () {
      final m = _sample().toJson();
      final colors = Map<String, dynamic>.from(m['colors'] as Map)..['text'] = '#GGGGGG';
      final res = JuzzioCustomTheme.parse(jsonEncode({...m, 'colors': colors}), newId: 'x');
      expect(res.ok, isFalse);
      expect(res.errors.join(), contains('Metin'));
    });

    test('Eksik renk varsayılanla tamamlanır (uyarı ile)', () {
      final m = _sample().toJson();
      final colors = Map<String, dynamic>.from(m['colors'] as Map)..remove('icon');
      final res = JuzzioCustomTheme.parse(jsonEncode({...m, 'colors': colors}), newId: 'x');
      expect(res.ok, isTrue);
      expect(res.warnings.join(), contains('İkon'));
    });

    test('Sınır dışı değerler aralığa alınır', () {
      final m = _sample().toJson();
      final res = JuzzioCustomTheme.parse(
          jsonEncode({...m, 'glass': {'blur': 999, 'opacity': -5, 'intensity': 7}}), newId: 'x');
      expect(res.ok, isTrue);
      expect(res.theme!.blur, JuzzioCustomTheme.blurMax);
      expect(res.theme!.opacity, JuzzioCustomTheme.opacityMin);
      expect(res.theme!.intensity, JuzzioCustomTheme.intensityMax);
      expect(res.warnings.length, 3);
    });

    test('Sayı yerine metin → hata', () {
      final m = _sample().toJson();
      expect(JuzzioCustomTheme.parse(jsonEncode({...m, 'glass': {'blur': 'çok'}}), newId: 'x').ok, isFalse);
    });

    test('16 KB üzeri reddedilir; ad temizlenir', () {
      expect(JuzzioCustomTheme.parse('{"a":"${'x' * 20000}"}', newId: 'x').ok, isFalse);
      expect(JuzzioCustomTheme.sanitizeName('  <b>Kötü\u0000 ad</b>  '), 'bKötü ad/b');
      expect(JuzzioCustomTheme.sanitizeName(''), 'Özel tema');
      expect(JuzzioCustomTheme.sanitizeName('a' * 100).length, JuzzioCustomTheme.maxNameLength);
    });

    test('HEX ayrıştırma', () {
      expect(JuzzioCustomTheme.parseHex('#20D9F2')!.toARGB32(), 0xFF20D9F2);
      expect(JuzzioCustomTheme.parseHex('8020D9F2')!.toARGB32(), 0x8020D9F2);
      expect(JuzzioCustomTheme.parseHex('#123'), isNull);
      expect(JuzzioCustomTheme.parseHex('#ZZZZZZ'), isNull);
      expect(JuzzioCustomTheme.toHex(const Color(0xFF20D9F2)), '#20D9F2');
      expect(JuzzioCustomTheme.toHex(const Color(0x8020D9F2)), '#8020D9F2');
    });

    test('Kayıtlı veride geçersiz kimlik atlanır', () {
      final m = _sample().toJson();
      expect(JuzzioCustomTheme.fromStored({...m, 'id': '../evil'}), isNull);
      expect(JuzzioCustomTheme.fromStored(m)!.id, 'ct_test01');
      expect(JuzzioCustomTheme.fromStored('metin'), isNull);
    });
  });

  group('Tema motoru', () {
    test('12 hazır temanın tamamı geçerli ve metin okunaklı', () {
      expect(kJuzzioAuroraPalettes.length, 12);
      for (final p in kJuzzioAuroraPalettes) {
        expect(juzzioAuroraPaletteById(p.id).id, p.id);
        // koyu metin açık zeminde, açık metin koyu zeminde en az 4.5:1
        expect(JuzzioCustomTheme.contrastRatio(const Color(0xFFF5F5F7), p.base), greaterThanOrEqualTo(4.5), reason: '${p.id} dark');
        expect(JuzzioCustomTheme.contrastRatio(const Color(0xFF111113), p.baseLight), greaterThanOrEqualTo(4.5), reason: '${p.id} light');
      }
    });

    test('Özel tema tüm cam tokenlarını yönetir', () {
      final t = _sample();
      JuzzioGlassTokens.custom = t;
      expect(JuzzioGlassTokens.textPrimary, t.text);
      expect(JuzzioGlassTokens.accentFill, t.button);
      expect(JuzzioGlassTokens.onAccent, t.buttonText);
      expect(JuzzioGlassTokens.heading, t.heading);
      expect(JuzzioGlassTokens.icon, t.icon);
      expect(JuzzioGlassTokens.baseBlur, 22);
      expect(JuzzioGlassTokens.surface.a, closeTo(0.4 * 1.2, 0.01));
      final p = JuzzioPalette(true);
      expect(p.textPrimary, t.text);
      expect(p.coolButtonBg, t.button);
      JuzzioGlassTokens.custom = null;
      expect(JuzzioGlassTokens.baseBlur, JuzzioGlassTokens.blurSigma);
    });

    test('Özel tema paleti düzenlenince yeniden çizilir (kimlik değişir)', () {
      final a = _sample();
      final b = a.withColor('background', const Color(0xFF101010));
      expect(a.toPalette().id, isNot(b.toPalette().id));
      expect(a.toPalette().id, startsWith('custom:ct_test01:'));
      expect(a.copyWith(gradient: false).toPalette().orbs, isEmpty);
    });

    test('Gece zamanlaması (gece yarısını aşan aralık dahil)', () {
      bool d(int h, int m) => JuzzioAppController.isWithinDarkWindow(h * 60 + m, 20 * 60, 7 * 60);
      expect(d(21, 0), isTrue);
      expect(d(2, 30), isTrue);
      expect(d(7, 0), isFalse);
      expect(d(12, 0), isFalse);
      expect(d(19, 59), isFalse);
      expect(JuzzioAppController.isWithinDarkWindow(600, 480, 1020), isTrue);
      expect(JuzzioAppController.isWithinDarkWindow(1100, 480, 1020), isFalse);
    });

    test('Kaydet / yeniden adlandır / çoğalt / sil / uygula / varsayılana dön', () {
      final app = JuzzioAppController.instance;
      for (final t in app.customThemes.toList()) {
        app.deleteCustomTheme(t.id);
      }
      final t = _sample();
      expect(app.saveCustomTheme(t), isTrue);
      app.applyCustomTheme(t.id);
      expect(app.activeCustomThemeId, t.id);
      expect(app.isDark, isTrue);
      expect(app.glassPalette.id, startsWith('custom:'));
      expect(JuzzioGlassTokens.custom?.id, t.id);

      app.renameCustomTheme(t.id, 'Yeni ad');
      expect(app.customThemes.single.name, 'Yeni ad');
      final copy = app.duplicateCustomTheme(t.id)!;
      expect(app.customThemes.length, 2);
      expect(copy.name, isNot('Yeni ad'));

      // canlı önizleme etkin temayı geçici değiştirir, null ile geri döner
      app.previewCustomTheme(copy.copyWith(dark: false));
      expect(app.isDark, isFalse);
      app.previewCustomTheme(null);
      expect(JuzzioGlassTokens.custom?.id, t.id);

      app.clearCustomTheme();
      expect(app.activeCustomTheme, isNull);
      expect(JuzzioGlassTokens.custom, isNull);

      app.applyCustomTheme(copy.id);
      app.deleteCustomTheme(copy.id);
      expect(app.activeCustomTheme, isNull, reason: 'etkin tema silinince varsayılana dönülür');
      app.deleteCustomTheme(t.id);
      expect(app.customThemes, isEmpty);
    });

    test('Kalıcılık: tercih anlık görüntüsü özel temaları ve zamanlamayı içerir', () {
      final app = JuzzioAppController.instance;
      final t = _sample();
      app.saveCustomTheme(t);
      app.setThemeSchedule(startMinutes: 1290, endMinutes: 390);
      final snap = app.preferencesSnapshot();
      expect((snap['customThemes'] as List).length, greaterThanOrEqualTo(1));
      expect((snap['themeSchedule'] as Map)['start'], 1290);
      // anlık görüntü JSON'a çevrilip geri okunabilir
      final restored = JuzzioCustomTheme.fromStored(jsonDecode(jsonEncode((snap['customThemes'] as List).first)));
      expect(restored, isNotNull);
      app.deleteCustomTheme(t.id);
    });

    test('İçe aktarma kontrolcü üzerinden kaydeder; hatalı veride kaydetmez', () {
      final app = JuzzioAppController.instance;
      final before = app.customThemes.length;
      expect(app.importCustomThemeJson('{"schema":"x"}').ok, isFalse);
      expect(app.customThemes.length, before);
      final ok = app.importCustomThemeJson(_sample().toPrettyJson());
      expect(ok.ok, isTrue);
      expect(app.customThemes.length, before + 1);
      app.deleteCustomTheme(ok.theme!.id);
    });

    test('Hazır tema seçmek özel temayı kapatır', () {
      final app = JuzzioAppController.instance;
      final t = _sample();
      app.saveCustomTheme(t);
      app.applyCustomTheme(t.id);
      app.setGlassPalette('emerald');
      expect(app.activeCustomTheme, isNull);
      expect(app.glassPalette.id, 'emerald');
      app.deleteCustomTheme(t.id);
    });
  });
}
