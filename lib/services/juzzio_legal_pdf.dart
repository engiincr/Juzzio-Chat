// =============================================================================
// JUZZIO v1.2.9 — Yasal rapor: antetli PDF (resmî makamlara teslim)
//  • Üst antet (her sayfa): şeffaf "assets/images/pdf_logo.png" + Talep Eden Kurum / Dosya No / Sebep
//    (uygulama logosu juzzio_logo.png'ye DOKUNULMAZ; PDF'in kendi logosu vardır)
//  • 1. sayfa: talep bilgileri + delil özet tablosu + teknik imkânsızlık beyanı
//  • Ayrıntı bölümleri (lib/screens/admin_legal_report.dart ile aynı bölümler; IP'lerin yanında
//    servis sağlayıcı / ASN)
//  • Son bölüm: BÜTÜNLÜK MÜHRÜ (SHA-256), zaman damgası durumu, işlem kimliği ve süper yönetici
//    imza bloğu, teslim şerhi
//  • Alt bilgi (her sayfa): "Bu belge Juzzio Sistemleri tarafından resmi makamların talebi üzerine
//    otomatik olarak oluşturulmuştur." + sayfa no + özetin ilk 16 hanesi
//  Yazı tipi: Liberation Sans (SIL OFL 1.1) — Türkçe karakterler için PDF'e gömülür.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../screens/admin_legal_report.dart';
import 'juzzio_legal_package.dart';

const String kJuzzioPdfLogoAsset = 'assets/images/pdf_logo.png';
const String kJuzzioPdfFontRegular = 'assets/fonts/pdf/LiberationSans-Regular.ttf';
const String kJuzzioPdfFontBold = 'assets/fonts/pdf/LiberationSans-Bold.ttf';

const String kJuzzioPdfFooterNote =
    'Bu belge Trawave Sistemleri tarafından resmi makamların talebi üzerine otomatik olarak oluşturulmuştur.';

/// PDF'teki resmî beyan paragrafı (kısa biçim; uzun açıklama bölümde ayrıca yer alır)
const String kJuzzioPdfE2eeStatement =
    'Uçtan uca şifreleme sebebiyle birebir sohbet içerikleri sunucuda barındırılmamakta ve okunamamaktadır. '
    'Bu raporda yer alan birebir sohbet ve sesli/görüntülü arama içerikleri, Trawave protokolü gereği uçtan uca '
    'şifrelendiğinden sunucularda açık metin olarak bulunmaz; sistem yöneticileri dahil hiç kimse tarafından '
    'okunamaz veya çözülemez. Sunucuda yalnız bağlantı üst verileri (zaman, IP, cihaz, oda kimliği) yer alır.';

const String kJuzzioPdfDeviceStatement =
    'Android/iOS işletim sistemi güvenlik politikaları gereği üçüncü taraf uygulamaların IMEI numarasına erişimi '
    'kısıtlanmıştır; bu raporda IMEI yerine uygulamaya özgü cihaz kimliği (device_id), cihaz modeli ve ağ IP '
    'bilgileri sunulmuştur. Şehir/GPS konumu toplanmaz; IP adresinin abonesi ve yaklaşık konumu, raporda adı geçen '
    'internet servis sağlayıcısından resmî yazıyla istenebilir.';

/// Teslim şerhi. (5651: internet yayınları; 5271: Ceza Muhakemesi Kanunu; 6698: KVKK)
const String kJuzzioPdfDeliveryNote =
    'İşbu dijital rapor, 5651 sayılı Kanun, 5271 sayılı Ceza Muhakemesi Kanunu ve 6698 sayılı Kişisel Verilerin '
    'Korunması Kanunu çerçevesinde, talep eden yetkili makama sunulmak üzere Trawave sunucu altyapısındaki '
    'kayıtlardan otomatik olarak derlenmiştir. Belge ve ekindeki ham veri dosyasının bütünlüğü SHA-256 özetiyle '
    'korunmaktadır; tek bir karakterin değişmesi hâlinde özet değeri tutmaz.';

// v2.1: İngilizce sürümler (yönetici uygulaması İngilizce ise PDF İngilizce üretilir)
const String kJuzzioPdfFooterNoteEn =
    'This document was generated automatically by Trawave Systems at the request of the competent authorities.';
const String kJuzzioPdfE2eeStatementEn =
    'Because of end-to-end encryption, one-to-one chat contents are not stored on the server and cannot be read. '
    'One-to-one chat and voice/video call contents in this report are end-to-end encrypted under the Trawave protocol; '
    'they do not exist in plain text on the servers and cannot be read or decrypted by anyone, including system '
    'administrators. The server holds only connection metadata (time, IP, device, room ID).';
const String kJuzzioPdfDeviceStatementEn =
    'Under Android/iOS security policies, third-party apps cannot access the IMEI; this report therefore provides an '
    'app-specific device ID (device_id), the device model and network IP information instead. City/GPS location is not '
    'collected; the subscriber and approximate location of an IP address can be requested from the internet service '
    'provider named in this report by official letter.';
const String kJuzzioPdfDeliveryNoteEn =
    'This digital report was compiled automatically from records in the Trawave server infrastructure for submission to '
    'the requesting competent authority, within the framework of applicable law (in Türkiye: Law No. 5651, Code of '
    'Criminal Procedure No. 5271 and Personal Data Protection Law No. 6698). The integrity of this document and the '
    'attached raw data file is protected by a SHA-256 digest; changing a single character invalidates the digest.';

const PdfColor _ink = PdfColor.fromInt(0xFF0B0F24);
const PdfColor _muted = PdfColor.fromInt(0xFF5B6275);
const PdfColor _line = PdfColor.fromInt(0xFFCBD0DC);
const PdfColor _soft = PdfColor.fromInt(0xFFF3F5FA);
const PdfColor _accent = PdfColor.fromInt(0xFF6D4AE6);

String _v(Object? v) {
  final t = (v ?? '').toString().trim();
  return t.isEmpty ? '-' : t;
}

/// PDF'te satır kırılabilsin diye çok uzun, boşluksuz parçaları (belirteç, özet, URL) böler. Saf; test edilir.
String juzzioPdfBreakable(String text, {int every = 48}) {
  return text.split(' ').map((word) {
    if (word.length <= every) return word;
    final b = StringBuffer();
    final runes = word.runes.toList();
    for (var i = 0; i < runes.length; i += every) {
      if (i > 0) b.write(' ');
      b.write(String.fromCharCodes(runes.sublist(i, i + every > runes.length ? runes.length : i + every)));
    }
    return b.toString();
  }).join(' ');
}

/// Gömülü yazı tipinde olmayan karakterleri (emoji vb.) "?" yapar; Türkçe ve Latin karakterler kalır. Saf.
String juzzioPdfSafeText(String text) {
  final b = StringBuffer();
  for (final r in text.runes) {
    final ok = r == 0x0A ||
        (r >= 0x20 && r <= 0x7E) ||
        (r >= 0xA0 && r <= 0x17F) || // Latin-1 + Latin Extended-A (ş ğ ı İ ç ö ü)
        (r >= 0x2010 && r <= 0x2026) || // tire, tırnak, üç nokta, madde imi
        r == 0x2192 || // →
        r == 0x20AC;
    b.write(ok ? String.fromCharCode(r) : '?');
  }
  return b.toString();
}

String _t(String s) => juzzioPdfBreakable(juzzioPdfSafeText(s));

class JuzzioLegalPdfInput {
  const JuzzioLegalPdfInput({
    required this.bundle,
    required this.info,
    required this.jsonSha256,
    this.isp = const <String, String>{},
    this.timestamp,
    this.ispLookupTried = false,
  });
  final Map<String, dynamic> bundle;
  final JuzzioLegalRequestInfo info;
  final String jsonSha256; // juzzio_veri.json dosyasının SHA-256 özeti
  final Map<String, String> isp;
  final JuzzioTimestamp? timestamp;
  final bool ispLookupTried;
}

/// PDF'i üretir (bayt). Varlıklar (logo, yazı tipi) verilmezse uygulama paketinden okunur.
Future<Uint8List> juzzioBuildLegalPdf(
  JuzzioLegalPdfInput input, {
  Uint8List? logoBytes,
  ByteData? fontRegular,
  ByteData? fontBold,
  bool english = false,
}) async {
  String L(String tr, String en) => english ? en : tr;
  final regular = pw.Font.ttf(fontRegular ?? await rootBundle.load(kJuzzioPdfFontRegular));
  final bold = pw.Font.ttf(fontBold ?? await rootBundle.load(kJuzzioPdfFontBold));
  Uint8List? logo = logoBytes;
  if (logo == null) {
    try {
      logo = (await rootBundle.load(kJuzzioPdfLogoAsset)).buffer.asUint8List();
    } catch (_) {
      logo = null; // logo dosyası yoksa antet yazıyla çizilir
    }
  }
  final logoImage = logo == null ? null : pw.MemoryImage(logo);

  final b = input.bundle;
  final info = input.info;
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  final archiveId = _v(b['archive_id']);
  final generated = _v(b['server_time_utc']) == '-' ? _v(b['generated_at']) : _v(b['server_time_utc']);
  final shortHash = input.jsonSha256.length >= 16 ? input.jsonSha256.substring(0, 16) : input.jsonSha256;

  pw.TextStyle st({double size = 9, bool isBold = false, PdfColor color = _ink}) =>
      pw.TextStyle(fontSize: size, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color, lineSpacing: 1.5);

  pw.Widget kvTable(List<MapEntry<String, String>> rows, {double keyWidth = 150}) => pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.6),
        columnWidths: {0: pw.FixedColumnWidth(keyWidth), 1: const pw.FlexColumnWidth()},
        children: [
          for (final r in rows)
            pw.TableRow(children: [
              pw.Container(color: _soft, padding: const pw.EdgeInsets.all(5), child: pw.Text(_t(r.key), style: st(isBold: true))),
              pw.Container(padding: const pw.EdgeInsets.all(5), child: pw.Text(_t(r.value), style: st())),
            ]),
        ],
      );

  pw.Widget title(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.2))),
        child: pw.Text(_t(text), style: st(size: 11, isBold: true)),
      );

  pw.Widget boxed(String heading, String body) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: _soft, border: pw.Border.all(color: _line, width: 0.8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(_t(heading), style: st(size: 9.5, isBold: true)),
          pw.SizedBox(height: 3),
          pw.Text(_t(body), style: st(size: 8.5)),
        ]),
      );

  // ---- antet (her sayfa) ----
  pw.Widget header(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          if (logoImage != null)
            pw.Image(logoImage, height: 44)
          else
            pw.Text('Trawave.', style: st(size: 22, isBold: true)),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(L('YASAL BİLGİ TALEBİ RAPORU', 'LEGAL DATA REQUEST REPORT'), style: st(size: 11, isBold: true)),
              pw.SizedBox(height: 2),
              pw.Text(_t('${L('Talep Eden Kurum / Makam', 'Requesting Authority')}: ${info.authority.trim()}'), style: st(size: 8.5)),
              pw.Text(_t('${L('Dosya / Esas No', 'Case / File No')}: ${info.caseNo.trim()}'), style: st(size: 8.5)),
              pw.Text(_t('${L('Talep Sebebi', 'Purpose of Request')}: ${info.purpose.trim()}'), style: st(size: 8.5)),
            ]),
          ),
        ]),
      );

  pw.Widget footer(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(english ? kJuzzioPdfFooterNoteEn : kJuzzioPdfFooterNote, style: st(size: 7.5, color: _muted)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(
              child: pw.Text(_t('$archiveId · SHA-256 $shortHash… · ${L('GİZLİ — yalnız talep eden makam içindir', 'CONFIDENTIAL — for the requesting authority only')}'), style: st(size: 7, color: _muted)),
            ),
            pw.SizedBox(width: 8),
            pw.Text('${L('Sayfa', 'Page')} ${ctx.pageNumber} / ${ctx.pagesCount}', style: st(size: 7, color: _muted)),
          ]),
        ]),
      );

  final sections = juzzioLegalSections(b, isp: input.isp, english: english);
  final ts = input.timestamp;
  final ipCount = juzzioCollectIps(b).length;

  final content = <pw.Widget>[
    title(L('1. TALEP VE RAPOR BİLGİLERİ', '1. REQUEST AND REPORT DETAILS')),
    kvTable([
      MapEntry(L('Talep eden kurum / makam', 'Requesting authority'), info.authority.trim()),
      MapEntry(L('Dosya / esas numarası', 'Case / file number'), info.caseNo.trim()),
      MapEntry(L('Talep sebebi', 'Purpose of request'), info.purpose.trim()),
      MapEntry(L('Arşiv / işlem no', 'Archive / transaction no'), '$archiveId (${L('kayıt', 'record')} ${_v(b['request_id'])})'),
      MapEntry(L('Rapor zamanı (sunucu, UTC)', 'Report time (server, UTC)'), generated),
      MapEntry(L('Veri biçimi', 'Data format'), _v(b['format'])),
      MapEntry(L('Ham veri dosyası', 'Raw data file'), L('juzzio_veri.json (bu PDF ile aynı şifreli pakette)', 'juzzio_veri.json (in the same encrypted package as this PDF)')),
    ]),
    title(L('2. DELİL ÖZET TABLOSU', '2. EVIDENCE SUMMARY')),
    kvTable(juzzioLegalSummary(b, english: english), keyWidth: 170),
    title(L('3. TEKNİK İMKÂNSIZLIK BEYANI VE SINIRLAR', '3. STATEMENT OF TECHNICAL IMPOSSIBILITY AND LIMITATIONS')),
    boxed(L('Uçtan uca şifreleme (E2EE) beyanı', 'End-to-end encryption (E2EE) statement'), english ? kJuzzioPdfE2eeStatementEn : kJuzzioPdfE2eeStatement),
    boxed(L('Donanım ve yazılım kısıtları beyanı', 'Hardware and software limitations'), english ? kJuzzioPdfDeviceStatementEn : kJuzzioPdfDeviceStatement),
    boxed(L('Ayrıntılı açıklama', 'Detailed explanation'), english ? juzzioTechnicalImpossibilityStatementEn : juzzioTechnicalImpossibilityStatement),
    pw.SizedBox(height: 4),
    pw.Text(
      _t(input.isp.isNotEmpty
          ? L(
              'IP adreslerinin yanındaki servis sağlayıcı (AS numarası ve kurum adı) bilgisi, rapor üretilirken RIPE NCC '
                  'RIPEstat açık kayıtlarından alınmıştır ($ipCount adresten ${input.isp.length} tanesi eşleşti). Abone bilgisi '
                  'ilgili sağlayıcıdan resmî yazıyla istenmelidir.',
              'The service provider (AS number and organisation) shown next to IP addresses was taken from RIPE NCC '
                  'RIPEstat public records when the report was generated (${input.isp.length} of $ipCount addresses matched). '
                  'Subscriber details must be requested from the provider by official letter.')
          : input.ispLookupTried
              ? L('Servis sağlayıcı (AS numarası) sorgusu yapılamadı veya eşleşme bulunamadı; IP adresleri sağlayıcı bilgisi olmadan listelenmiştir.',
                  'The service provider (AS number) lookup failed or found no match; IP addresses are listed without provider details.')
              : L('Bu raporda servis sağlayıcı (AS numarası) sorgusu yapılmamıştır.', 'No service provider (AS number) lookup was made for this report.')),
      style: st(size: 8, color: _muted),
    ),
    title(L('4. AYRINTILI KAYITLAR', '4. DETAILED RECORDS')),
  ];

  for (final s in sections) {
    if (s.title.isEmpty) continue; // genel başlık bilgileri zaten 1. bölümde
    if (s.title.startsWith('TEKNİK İMKÂNSIZLIK') || s.title.startsWith('ÖNEMLİ TEKNİK') ||
        s.title.startsWith('STATEMENT OF TECHNICAL') || s.title.startsWith('IMPORTANT TECHNICAL')) {
      continue; // 3. bölümde
    }
    content.add(pw.Container(
      margin: const pw.EdgeInsets.only(top: 9, bottom: 3),
      child: pw.Text(_t(s.title), style: st(size: 9.5, isBold: true, color: _accent)),
    ));
    if (s.lines.isEmpty) content.add(pw.Text(L('Kayıt yok.', 'No records.'), style: st(size: 8, color: _muted)));
    for (final l in s.lines) {
      // her satır ayrı ve doğrudan Text: sayfa sonunda bölünebilir (çok uzun satır 6000 karakterde kesilir)
      content.add(pw.Text(_t(l.length > 6000 ? '${l.substring(0, 6000)} …[${L('kısaltıldı; tamamı juzzio_veri.json içinde', 'truncated; full text in juzzio_veri.json')}]' : l), style: st(size: 8)));
    }
  }

  content.addAll([
    title(L('5. BÜTÜNLÜK MÜHRÜ VE YÖNETİCİ İMZA BLOĞU', '5. INTEGRITY SEAL AND ADMINISTRATOR SIGNATURE BLOCK')),
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(L('BÜTÜNLÜK MÜHRÜ — SHA-256', 'INTEGRITY SEAL — SHA-256'), style: st(size: 10.5, isBold: true)),
          pw.Text('TRAWAVE · $archiveId', style: st(size: 8.5, isBold: true, color: _accent)),
        ]),
        pw.SizedBox(height: 6),
        kvTable([
          MapEntry(L('Ham veri (juzzio_veri.json) SHA-256', 'Raw data (juzzio_veri.json) SHA-256'), input.jsonSha256),
          MapEntry(L('Sunucu paket özeti (integrity_sha256)', 'Server package digest (integrity_sha256)'), _v(b['integrity_sha256'])),
          MapEntry(
              L('Zaman damgası (RFC 3161)', 'Timestamp (RFC 3161)'),
              ts == null
                  ? L('Alınamadı (zaman damgası sunucularına ulaşılamadı). Rapor zamanı sunucu saatidir (UTC): $generated',
                      'Not obtained (timestamp servers unreachable). Report time is server time (UTC): $generated')
                  : L('ALINDI · sağlayıcı: ${ts.authority} · istek zamanı (UTC): ${ts.requestedAtUtc.toIso8601String()} · '
                          'belirteç pakette: zaman_damgasi.tsr (${ts.token.length} bayt, ham verinin SHA-256 özeti üzerine)',
                      'OBTAINED · authority: ${ts.authority} · request time (UTC): ${ts.requestedAtUtc.toIso8601String()} · '
                          'token in package: zaman_damgasi.tsr (${ts.token.length} bytes, over the SHA-256 of the raw data)')),
          MapEntry(L('İşlem kimliği', 'Transaction ID'), '$archiveId · ${L('yasal talep kaydı no', 'legal request record no')} ${_v(b['request_id'])}'),
          MapEntry(L('Dışa aktaran', 'Exported by'), '@${_v(b['exported_by'])} · ${L('Süper Yönetici', 'Super Administrator')} · ${L('kullanıcı kimliği', 'user ID')} ${_v(b['exported_by_id'])}'),
          MapEntry(L('Aktarım', 'Transfer'), L('Yönetici oturumu doğrulanarak, TLS ile şifreli bağlantı üzerinden; işlem değiştirilemez denetim kaydına yazılmıştır.',
              'Over a TLS-encrypted connection after verifying the administrator session; the action is written to the immutable audit log.')),
          MapEntry(L('Paket', 'Package'), L('Bu PDF ve ham veri, her talebe özel rastgele şifreyle AES-256 şifreli ZIP içinde teslim edilir. '
              'PDF dosyasının kendi özeti paketteki SHA256SUMS.txt dosyasındadır.',
              'This PDF and the raw data are delivered in an AES-256 encrypted ZIP with a random password unique to each request. '
              'The digest of the PDF itself is in SHA256SUMS.txt in the package.')),
        ], keyWidth: 170),
      ]),
    ),
    pw.SizedBox(height: 8),
    pw.Text(_t(english ? kJuzzioPdfDeliveryNoteEn : kJuzzioPdfDeliveryNote), style: st(size: 8.5)),
    pw.SizedBox(height: 6),
    pw.Text(
      _t(L('Bu rapor, Trawave sistem kuralları gereği yalnız Süper Yönetici yetkisine sahip @${_v(b['exported_by'])} kullanıcısının '
              'doğrulanmış oturumu üzerinden dışa aktarılmıştır. İşlem kimliği: $archiveId.',
          'Under Trawave system rules, this report was exported only through the verified session of @${_v(b['exported_by'])}, '
              'who holds Super Administrator rights. Transaction ID: $archiveId.')),
      style: st(size: 8.5, isBold: true),
    ),
  ]);

  final doc = pw.Document(
    theme: theme,
    title: L('Trawave Yasal Bilgi Talebi Raporu — $archiveId', 'Trawave Legal Data Request Report — $archiveId'),
    author: L('Trawave Sistemleri', 'Trawave Systems'),
    creator: 'Trawave',
    subject: juzzioPdfSafeText('${info.authority.trim()} · ${info.caseNo.trim()}'),
  );
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        theme: theme,
      ),
      maxPages: 2000,
      header: header,
      footer: footer,
      build: (ctx) => content,
    ),
  );
  return doc.save();
}
