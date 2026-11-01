// JUZZIO v0.3.0 — dil kataloğu, içerik filtresi, arama önizlemesi ve yerel ayar testleri.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/content_filter.dart';
import 'package:juzzio/core/notification_text.dart';
import 'package:juzzio/l10n/juzzio_strings_v030.dart';
import 'package:juzzio/main.dart' show juzzioIsRtl, juzzioMaterialLocale;
import 'package:juzzio/screens/admin_panel_screen.dart' show kJuzzioBanReasons;
import 'package:juzzio/widgets/profile_extras.dart';

Set<String> _placeholders(String s) => RegExp(r'\{[a-zA-Z_]+\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Her v0.3.0 anahtarı tr/en/de dillerinde dolu ve yer tutucular aynı', () {
    for (final entry in kJuzzioV030Strings.entries) {
      final tr = entry.value['tr'];
      final en = entry.value['en'];
      final de = entry.value['de'];
      expect(tr != null && tr.trim().isNotEmpty, isTrue, reason: '${entry.key} tr');
      expect(en != null && en.trim().isNotEmpty, isTrue, reason: '${entry.key} en');
      expect(de != null && de.trim().isNotEmpty, isTrue, reason: '${entry.key} de');
      expect(_placeholders(en!), equals(_placeholders(tr!)), reason: '${entry.key} en yer tutucu');
      expect(_placeholders(de!), equals(_placeholders(tr)), reason: '${entry.key} de yer tutucu');
    }
  });

  test('Dinamik olarak üretilen anahtarların hepsi katalogda var', () {
    final keys = <String>[
      for (final t in ['general', ...kJuzzioGroupTypes]) 'group_type_$t',
      for (final r in ['owner', 'moderator', 'member']) 'group_role_$r',
      for (final m in [15, 60, 480, 1440, 10080]) 'group_mute_$m',
      for (final s in [0, 1, 2, 3]) 'chick_stage_$s',
      for (final g in ['female', 'male', 'unspecified']) 'gender_$g',
      for (final r in kJuzzioBanReasons) 'ban_reason_$r',
      for (final t in ['post', 'comment', 'story', 'user', 'message', 'group']) 'report_target_$t',
      for (final s in ['open', 'reviewed', 'resolved', 'dismissed']) 'report_status_$s',
      for (final b in JuzzioBadgeStyle.all.values) ...[b.labelKey, b.descKey],
    ];
    for (final k in keys) {
      expect(kJuzzioV030Strings.containsKey(k), isTrue, reason: k);
    }
  });

  test('İçerik filtresi: argo engellenir, normal kelimeler yanlış pozitif vermez', () {
    expect(JuzzioContentFilter.isClean('Mezuniyet Projesi', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('Nudeln kochen', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('Abi Neşe', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('Matematik Çalışma', requireLetters: true), isTrue);
    expect(JuzzioContentFilter.isClean('o r o s p u grubu', requireLetters: true), isFalse);
    expect(JuzzioContentFilter.isClean('s1ktir', requireLetters: true), isFalse);
    expect(JuzzioContentFilter.isClean('send nudes'), isFalse);
    expect(JuzzioContentFilter.isClean('aaaaaaa', requireLetters: true), isFalse);
    expect(JuzzioContentFilter.isClean('!!', requireLetters: true), isFalse);
  });

  test('Arama önizleme anahtarları çözülür, kullanıcı içeriği korunur', () {
    expect(juzzioLocalizedCallPreview('Merhaba'), isNull);
    final group = juzzioLocalizedCallPreview('call:group_video:Ekip');
    expect(group, isNotNull);
    expect(group!.startsWith('Ekip • '), isTrue);
    expect(juzzioLocalizedCallPreview('call:voice'), isNotNull);
    expect(juzzioLocalizedCallPreview('Grup • Sesli arama'), isNotNull);
  });

  test('Yerel ayar ve yazı yönü eşlemesi', () {
    expect(juzzioIsRtl('ar'), isTrue);
    expect(juzzioIsRtl('fa'), isTrue);
    expect(juzzioIsRtl('ckb'), isTrue);
    expect(juzzioIsRtl('tr'), isFalse);
    expect(juzzioMaterialLocale('de'), equals(const Locale('de')));
    expect(juzzioMaterialLocale('zh-tw').scriptCode, equals('Hant'));
    // Material desteklemediği bir dil İngilizce sistem metinlerine düşer (uygulama metinleri dil paketinden gelir)
    expect(juzzioMaterialLocale('zz'), equals(const Locale('en')));
  });
}
