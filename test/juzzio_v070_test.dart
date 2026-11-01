// JUZZIO v0.7.0 birim testleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/juzzio_sounds.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';
import 'package:juzzio/widgets/juzzio_video_kit.dart';
import 'package:juzzio/widgets/profile_extras.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GitHub sürüm notu Markdown\'dan ayrıntılara dönüşür', () {
    const md = '''# Juzzio v9.9.9 — Deneme

## Neden bu güncelleme?

Hataları düzeltmek için.

## ✨ Yeni özellikler

- Birinci özellik
- **İkinci** özellik

## 🛠️ Düzeltilen hatalar

- Bir hata

## 🔒 Güvenlik ve gizlilik

- Bir açık kapatıldı

<details><summary>English</summary>
## Why this update?
English only
</details>
''';
    final d = JuzzioAppController.parseReleaseMarkdown(md);
    final tr = d['tr'] as Map;
    expect(tr['reason'], 'Hataları düzeltmek için.');
    expect(tr['features'], ['Birinci özellik', 'İkinci özellik']);
    expect(tr['fixes'], ['Bir hata']);
    expect(tr['security'], ['Bir açık kapatıldı']);
    expect(JuzzioAppController.parseReleaseMarkdown('boş'), isEmpty);
  });

  test('Uygulamaya gömülü 0.7.0 notları var', () {
    final notes = JuzzioReleaseNote.mergeAll(const <JuzzioReleaseNote>[]);
    expect(notes.any((n) => n.versionName == '0.7.0'), isTrue);
    expect(notes.first.sectionFor('tr').fixes, isNotEmpty);
  });

  test('Müzik yalnızca önizleme bağlantısıyla çalınır', () {
    expect(juzzioIsPlayableMusic('https://youtu.be/dQw4w9WgXcQ'), isFalse);
    expect(juzzioIsPlayableMusic('http://x/y.m4a'), isFalse);
    expect(juzzioIsPlayableMusic('https://audio-ssl.itunes.apple.com/a.m4a'), isTrue);
  });

  test('Ses kanalları kişiye özel seçimle eşleşir', () {
    final s = JuzzioSounds.instance;
    expect(s.messageChannelFor(null), 'juzzio_msg_juzzio_tone_glass');
    expect(s.callChannelFor('x'), 'juzzio_call_juzzio_ring_aurora');
    expect(JuzzioSounds.ringtones.any((e) => e.id == 'default'), isTrue);
  });

  test('Cam belirteçleri temaya duyarlı', () {
    JuzzioGlassTokens.isDarkResolver = () => true;
    final darkText = JuzzioGlassTokens.textPrimary;
    JuzzioGlassTokens.isDarkResolver = () => false;
    final lightText = JuzzioGlassTokens.textPrimary;
    expect(darkText.computeLuminance(), greaterThan(0.8));
    expect(lightText.computeLuminance(), lessThan(0.1));
    expect(JuzzioGlassTokens.accentFill.computeLuminance(), lessThan(0.1));
    JuzzioGlassTokens.isDarkResolver = () => true;
  });

  test('Cam Beyaz teması mevcut; hikâye yazı oranı sabit', () {
    expect(juzzioAuroraPaletteById('glass_white').id, 'glass_white');
    expect(kJuzzioStoryTextSizeRatio * 360, closeTo(25.9, 0.1));
    expect(const Color(0xFFFFFFFF).computeLuminance(), 1.0);
  });
}
