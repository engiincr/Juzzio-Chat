// =============================================================================
// JUZZIO v0.7.0 — Gizlilik, KVKK, kullanım koşulları ve lisans (uygulama içi)
//  Metinler depodaki yasal dosyalardan üretilir (scripts/gen_legal.py): Türkçe (KVKK)
//  docs/legal/tr/, İngilizce depo kökündeki PRIVACY.md / TERMS.md / LICENSE.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/legal_texts.dart';
import '../core/theme/juzzio_glass.dart';

class JuzzioLegalPage extends StatelessWidget {
  final int initialTab;
  const JuzzioLegalPage({super.key, this.initialTab = 0});

  static Future<void> open(BuildContext context, {int tab = 0}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioLegalPage(initialTab: tab)));

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    final tr = app.uiLang.toLowerCase().startsWith('tr');
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab.clamp(0, 3),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: p.textPrimary,
          elevation: 0,
          title: Text(app.trEn('Gizlilik ve yasal', 'Privacy & legal', 'Datenschutz & Rechtliches'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: p.textPrimary,
            unselectedLabelColor: p.textMuted,
            indicatorColor: p.textPrimary,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: [
              Tab(text: app.trEn('Gizlilik ve KVKK', 'Privacy', 'Datenschutz')),
              Tab(text: app.trEn('Kullanım koşulları', 'Terms', 'Nutzungsbedingungen')),
              Tab(text: app.trEn('Lisans', 'License', 'Lizenz')),
              Tab(text: app.trEn('Atıflar ve açık kaynak', 'Credits & open source', 'Credits & Open Source')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // v0.9.7: uygulama dili Türkçe ise KVKK metni (Türkçe), değilse İngilizce
            _MarkdownView(source: tr ? kJuzzioPrivacyMd : kJuzzioPrivacyMdEn, p: p),
            _MarkdownView(source: tr ? kJuzzioTermsMd : kJuzzioTermsMdEn, p: p),
            _MarkdownView(source: tr ? kJuzzioLicenseText : kJuzzioLicenseTextEn, p: p, plain: true),
            _CreditsView(p: p),
          ],
        ),
      ),
    );
  }
}

/// Yalnızca bu metinlerde kullanılan Markdown alt kümesi: #, ##, -, | tablo |, **kalın**, `kod`.
class _MarkdownView extends StatelessWidget {
  final String source;
  final JuzzioPalette p;
  final bool plain;
  const _MarkdownView({required this.source, required this.p, this.plain = false});

  List<InlineSpan> _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final t = m.group(0)!;
      if (t.startsWith('**')) {
        spans.add(TextSpan(text: t.substring(2, t.length - 2), style: base.copyWith(fontWeight: FontWeight.w900, color: p.textPrimary)));
      } else {
        spans.add(TextSpan(text: t.substring(1, t.length - 1), style: base.copyWith(fontFamily: 'monospace')));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(color: p.textSecondary, fontSize: 13.5, height: 1.5);
    if (plain) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          JuzzioGlass(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: SelectableText(source, style: body.copyWith(fontSize: 12.5)),
          ),
        ],
      );
    }
    final widgets = <Widget>[];
    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 6));
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(line.substring(2),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontSize: 19, fontWeight: FontWeight.w900)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(line.substring(3), style: TextStyle(color: p.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w900)),
        ));
      } else if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body),
              Expanded(child: Text.rich(TextSpan(style: body, children: _inline(line.substring(2), body)))),
            ],
          ),
        ));
      } else if (line.startsWith('|')) {
        if (RegExp(r'^\|\s*:?-').hasMatch(line)) continue;
        final cells = line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        widgets.add(Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.pillBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++)
                Text.rich(TextSpan(
                  style: i == 0 ? body.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800) : body.copyWith(fontSize: 12.5),
                  children: _inline(cells[i], body),
                )),
            ],
          ),
        ));
      } else {
        widgets.add(Text.rich(TextSpan(style: body, children: _inline(line, body))));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        JuzzioGlass(
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets),
        ),
      ],
    );
  }
}

/// v1.2.9 (telif): üçüncü taraf atıfları ve açık kaynak lisansları (zorunlu bildirimler)
class JuzzioThirdPartyCredit {
  final String name;
  final String license;
  final String noteTr;
  final String noteEn;
  const JuzzioThirdPartyCredit(this.name, this.license, this.noteTr, this.noteEn);
}

/// Uygulamada kullanılan üçüncü taraf içerik/hizmetler ve lisansları (saf liste; test edilir)
const List<JuzzioThirdPartyCredit> kJuzzioThirdPartyCredits = [
  JuzzioThirdPartyCredit('Noto Color Emoji (Google)', 'SIL Open Font License 1.1',
      'Uygulama genelindeki emoji yazı tipi.', 'The emoji font used across the app.'),
  JuzzioThirdPartyCredit('Open-Meteo.com', 'CC BY 4.0',
      'Hava durumu teması verisi: "Weather data by Open-Meteo.com".', 'Weather theme data: "Weather data by Open-Meteo.com".'),
  JuzzioThirdPartyCredit('Apple Music / iTunes Search', 'Apple Media Services koşulları',
      '30 sn şarkı önizlemeleri yalnız akıştan çalınır, cihaza kaydedilmez; her parçada Apple Music bağlantısı vardır.',
      '30-second song previews are streamed only, never saved; every track links to Apple Music.'),
  JuzzioThirdPartyCredit('LiveKit', 'Apache License 2.0', 'Sesli/görüntülü arama altyapısı.', 'Voice/video call infrastructure.'),
  JuzzioThirdPartyCredit('Deepgram', 'Ticari API', 'Canlı altyazı ve sesli mesaj dökümü.', 'Live captions and voice-note transcription.'),
  JuzzioThirdPartyCredit('MyMemory (Translated srl)', 'Ücretsiz API koşulları', 'Yedek çeviri sağlayıcısı.', 'Fallback translation provider.'),
  JuzzioThirdPartyCredit('ExpressTURN', 'Hizmet koşulları', 'Yedek arama aktarıcısı (şifreli trafik).', 'Backup call relay (encrypted traffic).'),
  JuzzioThirdPartyCredit('Liberation Sans (Liberation Fonts)', 'SIL Open Font License 1.1',
      'Resmî talep raporlarının (PDF) yazı tipi.', 'Font of official request reports (PDF).'),
  JuzzioThirdPartyCredit('pdf · archive (Dart paketleri)', 'Apache License 2.0 · MIT',
      'PDF üretimi ve AES-256 şifreli ZIP.', 'PDF generation and AES-256 encrypted ZIP.'),
  JuzzioThirdPartyCredit('Trawave müzik ve sesleri', 'Trawave\'ya ait',
      'Tanıtım videoları, zil ve uyarı sesleri kodla üretilmiş özgün eserlerdir; üçüncü taraf ses kullanılmaz.',
      'Intro videos, ringtones and alert sounds are original works generated in code; no third-party audio is used.'),
];

class _CreditsView extends StatelessWidget {
  final JuzzioPalette p;
  const _CreditsView({required this.p});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final tr = app.uiLang.toLowerCase().startsWith('tr');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final c in kJuzzioThirdPartyCredits)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: JuzzioGlass(
              radius: 20,
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.name, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: p.pillBg, borderRadius: BorderRadius.circular(99)),
                    child: Text(c.license, style: TextStyle(color: p.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(tr ? c.noteTr : c.noteEn, style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4)),
              ]),
            ),
          ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Trawave',
            applicationVersion: JuzzioConfig.appVersion,
          ),
          icon: const Icon(Icons.article_rounded),
          label: Text(app.trEn('Tüm açık kaynak lisansları', 'All open-source licenses', 'Alle Open-Source-Lizenzen')),
        ),
      ],
    );
  }
}
