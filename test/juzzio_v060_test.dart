// JUZZIO v0.6.0 — cam temaları, içerik filtresi ve uygulama ayarları testleri.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/content_filter.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/services/juzzio_features_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool isOrange(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.saturation > 0.35 && hsl.lightness > 0.25 && hsl.lightness < 0.9 && hsl.hue >= 12 && hsl.hue <= 48;
  }

  test('Cam temaları benzersiz ve turuncu ton içermez', () {
    final ids = kJuzzioAuroraPalettes.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(<String>['ocean', 'amethyst', 'emerald', 'lagoon', 'chrome']));
    for (final p in kJuzzioAuroraPalettes) {
      expect(isOrange(p.swatchA), isFalse, reason: p.id);
      expect(isOrange(p.swatchB), isFalse, reason: p.id);
      for (final o in [...p.orbs, ...p.orbsLight]) {
        expect(isOrange(o.color.withValues(alpha: 1)), isFalse, reason: '${p.id} orb');
      }
    }
    expect(juzzioAuroraPaletteById('yok').id, 'juzzio_liquid');
    expect(juzzioAuroraPaletteById('emerald').id, 'emerald');
  });

  test('Ad filtresi müstehcen adları reddeder, gerçek adları kabul eder', () {
    expect(JuzzioContentFilter.isClean('Seksi Amcık 34'), isFalse);
    expect(JuzzioContentFilter.isClean('pornhub kral'), isFalse);
    expect(JuzzioContentFilter.isClean('Amina Yılmaz', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('Oral Çalışlar', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('Engin Çelik', requireLetters: true), isTrue);
  });

  test('Konuşma ön elemesi yalnız ağır ifadeleri yakalar', () {
    expect(JuzzioContentFilter.speechLooksExplicit('siktir git'), isTrue);
    expect(JuzzioContentFilter.speechLooksExplicit('O R O S P U'), isTrue);
    expect(JuzzioContentFilter.speechLooksExplicit('merhaba nasılsın, toplantı yarın'), isFalse);
    expect(JuzzioContentFilter.speechLooksExplicit('I got it, thanks'), isFalse);
  });

  test('Uygulama ayarları v0.6 alanlarını okur ve sınırlar', () {
    final cfg = JuzzioAppConfig.fromMap(<String, dynamic>{
      'default_glass_palette': 'amethyst',
      'call_moderation_enabled': false,
      'call_moderation_interval_sec': 500,
      'posts_enabled': false,
      'announcement_banner': 'Bakım 22:00',
    });
    expect(cfg.defaultGlassPalette, 'amethyst');
    expect(cfg.callModerationEnabled, isFalse);
    expect(cfg.speechModerationEnabled, isTrue);
    expect(cfg.callModerationIntervalSec, 60);
    expect(cfg.postsEnabled, isFalse);
    expect(cfg.announcementBanner, 'Bakım 22:00');
    const defaults = JuzzioAppConfig();
    expect(defaults.callModerationIntervalSec, 6);
    expect(defaults.globalFeedEnabled, isTrue);
  });
}
