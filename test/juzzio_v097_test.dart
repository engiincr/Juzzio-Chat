// JUZZIO v0.9.7 birim testleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/legal_texts.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';
import 'package:juzzio/screens/release_notes_screen.dart';
import 'package:juzzio/services/juzzio_media_cache.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';
import 'package:juzzio/widgets/juzzio_notification_stack.dart';
import 'package:juzzio/widgets/juzzio_ui_kit.dart';

void main() {
  test('Kumaş: içerik kayması monoton, 156 px ile sınırlı (v0.9.9)', () {
    expect(juzzioClothExtent(0), 0);
    expect(juzzioClothExtent(-20), 0);
    var last = 0.0;
    for (final p in [10.0, 50.0, 120.0, 300.0, 900.0]) {
      final e = juzzioClothExtent(p);
      expect(e, greaterThan(last));
      expect(e, lessThanOrEqualTo(156));
      last = e;
    }
    // Tetikleme eşiğine (dinlenme kaymasının %80'i ≈ 121) makul bir çekişle ulaşılır
    expect(juzzioClothExtent(240), greaterThan(JuzzioClothGeometry(screenWidth: 360, topInset: 47).threshold - 4));
  });

  test('Bildirim yığını: arkadaki kartlar küçülür, aşağı kayar ve solar', () {
    final a = juzzioStackTransform(0), b = juzzioStackTransform(1), c = juzzioStackTransform(2);
    expect(a.scale, 1);
    expect(a.opacity, 1);
    expect(b.scale, lessThan(a.scale));
    expect(c.scale, lessThan(b.scale));
    expect(b.dy, greaterThan(a.dy));
    expect(c.opacity, lessThan(b.opacity));
    expect(juzzioStackTransform(5).opacity, 0);
  });

  test('Avatar gradyanı temaya bağlı ve ada göre kararlı', () {
    const accents = [Color(0xFF20D9F2), Color(0xFF397BFF)];
    final x1 = juzzioAvatarGradient('Ayşe', accents);
    final x2 = juzzioAvatarGradient('Ayşe', accents);
    expect(x1, x2);
    final other = juzzioAvatarGradient('Ayşe', const [Color(0xFFA78BFA), Color(0xFF1E3A8A)]);
    expect(other, isNot(x1)); // tema değişince renk değişir
    for (final c in x1) {
      expect(HSLColor.fromColor(c).saturation, greaterThan(0.2)); // gri değil
    }
    expect(juzzioReadableOn(const Color(0xFFFFFFFF)), const Color(0xFF111113));
    expect(juzzioReadableOn(const Color(0xFF000000)), Colors.white);
  });

  test('Okunmamış rozet etiketi', () {
    expect(juzzioUnreadLabel(1), '1');
    expect(juzzioUnreadLabel(99), '99');
    expect(juzzioUnreadLabel(150), '99+');
  });

  test('Medya önbelleği: önce süresi geçenler, sonra LRU', () {
    final now = DateTime(2026, 11, 9);
    final files = <(String, int, DateTime)>[
      ('old', 10, now.subtract(const Duration(days: 90))),
      ('a', 40, now.subtract(const Duration(days: 5))),
      ('b', 40, now.subtract(const Duration(days: 2))),
      ('c', 40, now.subtract(const Duration(hours: 1))),
    ];
    // Sınır içinde ama yaşı geçen silinir
    expect(JuzzioMediaDiskCache.planPrune(files, limit: 1000, target: 800, maxAgeDays: 60, now: now), ['old']);
    // Sınır aşıldı: yaşı geçen + en eski kullanılan (a) hedefe kadar
    expect(JuzzioMediaDiskCache.planPrune(files, limit: 100, target: 80, maxAgeDays: 60, now: now), ['old', 'a']);
    // Yaş sınırı kapalı (0)
    expect(JuzzioMediaDiskCache.planPrune(files, limit: 1000, target: 800, maxAgeDays: 0, now: now), isEmpty);
  });

  test('Yenilikler: en son görülen sürümden bu yana tüm sürümler', () {
    final all = JuzzioReleaseNote.mergeAll(const <JuzzioReleaseNote>[]);
    final since = juzzioNotesSince(all, '0.9.3', '0.9.7');
    expect(since.map((n) => n.versionName).toList(), ['0.9.7', '0.9.6', '0.9.5', '0.9.4']);
    expect(juzzioNotesSince(all, '', '0.9.7').map((n) => n.versionName), ['0.9.7']);
  });

  test('0.9.7 sürüm notu bugünkü tüm değişiklikleri içerir (tr + en)', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((e) => e.versionName == '0.9.7');
    final tr = n.sectionFor('tr'), en = n.sectionFor('en');
    expect(tr.reason, isNotEmpty);
    expect(en.reason, isNotEmpty);
    expect(tr.features.length, greaterThanOrEqualTo(15));
    expect(en.features.length, tr.features.length);
    expect(en.fixes, isNotEmpty);
    expect(en.security, isNotEmpty);
    for (final v in ['0.9.4', '0.9.5', '0.9.6']) {
      expect(en.features.any((f) => f.contains('($v)')), isTrue, reason: v);
    }
  });

  test('Yasal metinler iki dilde', () {
    expect(kJuzzioPrivacyMd, contains('KVKK'));
    expect(kJuzzioPrivacyMdEn, contains('Privacy Policy'));
    expect(kJuzzioTermsMdEn, contains('Terms of Use'));
    expect(kJuzzioLicenseTextEn, contains('All rights reserved'));
    expect(kJuzzioPrivacyMdEn, contains('v0.9.7'));
  });

  test('16 cam teması; yenileri listede', () {
    final ids = kJuzzioAuroraPalettes.map((p) => p.id).toSet();
    expect(ids, containsAll(['aurora_borealis', 'frosted_pearl', 'midnight_sapphire', 'nordic_frost']));
    expect(ids.length, 16);
  });
}
