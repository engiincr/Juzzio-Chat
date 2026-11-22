// GM-015 — Ayarlar sayfası yeni tasarımı ("Juzzio Ayarlar" tuvali)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/widgets/juzzio_settings_kit.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  const sections = [
    JuzzioSettingsSection('Hesap ve güvenlik', [
      JuzzioSettingsItem(icon: Icons.person, title: 'Hesap ve Profil', subtitle: 'Kullanıcı adı, e-posta'),
      JuzzioSettingsItem(icon: Icons.shield, title: 'Gizlilik ve Güvenlik', keywords: 'pin engel'),
    ]),
    JuzzioSettingsSection('Görünüm', [
      JuzzioSettingsItem(icon: Icons.palette, title: 'Tema ve görünüm', keywords: 'gece gündüz'),
    ]),
  ];

  test('arama: Türkçe harf duyarsız, boş bölüm gizlenir', () {
    expect(juzzioSettingsNorm('GİZLİLİK'), 'gizlilik');
    expect(juzzioSettingsNorm('Görünüm'), 'gorunum');
    expect(juzzioFilterSettings(sections, ''), sections);
    final r = juzzioFilterSettings(sections, 'gizlilik');
    expect(r.length, 1);
    expect(r.first.items.single.title, 'Gizlilik ve Güvenlik');
    expect(juzzioFilterSettings(sections, 'GECE').single.items.single.title, 'Tema ve görünüm');
    expect(juzzioFilterSettings(sections, 'e-posta').single.items.single.title, 'Hesap ve Profil');
    expect(juzzioFilterSettings(sections, 'zzz'), isEmpty);
  });

  test('Türkçe büyük harf', () {
    expect(juzzioSettingsUpper('Hesap ve güvenlik', turkish: true), 'HESAP VE GÜVENLİK');
    expect(juzzioSettingsUpper('Account & security', turkish: false), 'ACCOUNT & SECURITY');
  });

  test('ana sayfa yeni tasarım bileşenleriyle kurulur, tüm eski işlevler duruyor', () {
    final s = _read('lib/screens/settings_suite_screens.dart');
    for (final k in [
      'JuzzioSettingsTitleBar(',
      'JuzzioSettingsProfileCard(',
      'JuzzioSettingsSearchField(',
      'JuzzioSettingsSectionView(',
      'JuzzioAccountProfileHubPage(',
      'JuzzioPrivacySecurityHubPage()',
      'JuzzioLanguageSettingsPage()',
      'JuzzioCallSettingsPage()',
      'JuzzioChatsSettingsPage()',
      'JuzzioNotificationsSettingsPage()',
      'JuzzioStorageSettingsPage()',
      'JuzzioAppearanceSettingsPage()',
      'JuzzioAccessibilitySettingsPage()',
      'JuzzioBatteryOptimizationPage()',
      'JuzzioHelpAndSupportPage(',
      'JuzzioDeveloperPage()',
      'openJuzzioAdminPanel(context)',
      '_logout(context)',
      '_showQrSyncDialog(context, p, uname)',
    ]) {
      expect(s, contains(k), reason: k);
    }
  });

  test('kit sabit renk yerine tema belirteçleri kullanır', () {
    final k = _read('lib/widgets/juzzio_settings_kit.dart');
    expect(k, contains('JuzzioGlassTokens.glowText'));
    expect(k, contains('JuzzioGlassTokens.onGlow'));
    expect(k, contains('JuzzioLiquidGlass('));
    expect(k.contains('Colors.white'), isFalse);
    expect(k.contains('Colors.black'), isFalse);
  });

  testWidgets('satır ve bölüm taşmadan çizilir (dar ekran)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [
          JuzzioSettingsSectionView(
            section: JuzzioSettingsSection('Sohbet ve arama', [
              JuzzioSettingsItem(
                icon: Icons.translate,
                title: 'Dil ve canlı çeviri — çok uzun bir başlık deneme metni',
                subtitle: 'Çok uzun bir açıklama satırı taşma olmamalı ve üç nokta ile bitmeli',
                value: 'Türkçe (Türkiye) uzun değer',
              ),
              JuzzioSettingsItem(icon: Icons.logout, title: 'Çıkış Yap', danger: true, showChevron: false),
            ]),
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('SOHBET VE ARAMA'), findsOneWidget);
  });
}
