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
    'Bu belge Juzzio Sistemleri tarafından resmi makamların talebi üzerine otomatik olarak oluşturulmuştur.';

/// PDF'teki resmî beyan paragrafı (kısa biçim; uzun açıklama bölümde ayrıca yer alır)
const String kJuzzioPdfE2eeStatement =
    'Uçtan uca şifreleme sebebiyle birebir sohbet içerikleri sunucuda barındırılmamakta ve okunamamaktadır. '
    'Bu raporda yer alan birebir sohbet ve sesli/görüntülü arama içerikleri, Juzzio protokolü gereği uçtan uca '
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
    'Korunması Kanunu çerçevesinde, talep eden yetkili makama sunulmak üzere Juzzio sunucu altyapısındaki '
    'kayıtlardan otomatik olarak derlenmiştir. Belge ve ekindeki ham veri dosyasının bütünlüğü SHA-256 özetiyle '
    'korunmaktadır; tek bir karakterin değişmesi hâlinde özet değeri tutmaz.';

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
}) async {
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
            pw.Text('Juzzio.', style: st(size: 22, isBold: true)),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('YASAL BİLGİ TALEBİ RAPORU', style: st(size: 11, isBold: true)),
              pw.SizedBox(height: 2),
              pw.Text(_t('Talep Eden Kurum / Makam: ${info.authority.trim()}'), style: st(size: 8.5)),
              pw.Text(_t('Dosya / Esas No: ${info.caseNo.trim()}'), style: st(size: 8.5)),
              pw.Text(_t('Talep Sebebi: ${info.purpose.trim()}'), style: st(size: 8.5)),
            ]),
          ),
        ]),
      );

  pw.Widget footer(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(kJuzzioPdfFooterNote, style: st(size: 7.5, color: _muted)),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(
              child: pw.Text(_t('$archiveId · SHA-256 $shortHash… · GİZLİ — yalnız talep eden makam içindir'), style: st(size: 7, color: _muted)),
            ),
            pw.SizedBox(width: 8),
            pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}', style: st(size: 7, color: _muted)),
          ]),
        ]),
      );

  final sections = juzzioLegalSections(b, isp: input.isp);
  final ts = input.timestamp;
  final ipCount = juzzioCollectIps(b).length;

  final content = <pw.Widget>[
    title('1. TALEP VE RAPOR BİLGİLERİ'),
    kvTable([
      MapEntry('Talep eden kurum / makam', info.authority.trim()),
      MapEntry('Dosya / esas numarası', info.caseNo.trim()),
      MapEntry('Talep sebebi', info.purpose.trim()),
      MapEntry('Arşiv / işlem no', '$archiveId (kayıt ${_v(b['request_id'])})'),
      MapEntry('Rapor zamanı (sunucu, UTC)', generated),
      MapEntry('Veri biçimi', _v(b['format'])),
      MapEntry('Ham veri dosyası', 'juzzio_veri.json (bu PDF ile aynı şifreli pakette)'),
    ]),
    title('2. DELİL ÖZET TABLOSU'),
    kvTable(juzzioLegalSummary(b), keyWidth: 170),
    title('3. TEKNİK İMKÂNSIZLIK BEYANI VE SINIRLAR'),
    boxed('Uçtan uca şifreleme (E2EE) beyanı', kJuzzioPdfE2eeStatement),
    boxed('Donanım ve yazılım kısıtları beyanı', kJuzzioPdfDeviceStatement),
    boxed('Ayrıntılı açıklama', juzzioTechnicalImpossibilityStatement),
    pw.SizedBox(height: 4),
    pw.Text(
      _t(input.isp.isNotEmpty
          ? 'IP adreslerinin yanındaki servis sağlayıcı (AS numarası ve kurum adı) bilgisi, rapor üretilirken RIPE NCC '
              'RIPEstat açık kayıtlarından alınmıştır ($ipCount adresten ${input.isp.length} tanesi eşleşti). Abone bilgisi '
              'ilgili sağlayıcıdan resmî yazıyla istenmelidir.'
          : input.ispLookupTried
              ? 'Servis sağlayıcı (AS numarası) sorgusu yapılamadı veya eşleşme bulunamadı; IP adresleri sağlayıcı bilgisi olmadan listelenmiştir.'
              : 'Bu raporda servis sağlayıcı (AS numarası) sorgusu yapılmamıştır.'),
      style: st(size: 8, color: _muted),
    ),
    title('4. AYRINTILI KAYITLAR'),
  ];

  for (final s in sections) {
    if (s.title.isEmpty) continue; // genel başlık bilgileri zaten 1. bölümde
    if (s.title.startsWith('TEKNİK İMKÂNSIZLIK') || s.title.startsWith('ÖNEMLİ TEKNİK')) continue; // 3. bölümde
    content.add(pw.Container(
      margin: const pw.EdgeInsets.only(top: 9, bottom: 3),
      child: pw.Text(_t(s.title), style: st(size: 9.5, isBold: true, color: _accent)),
    ));
    if (s.lines.isEmpty) content.add(pw.Text('Kayıt yok.', style: st(size: 8, color: _muted)));
    for (final l in s.lines) {
      // her satır ayrı ve doğrudan Text: sayfa sonunda bölünebilir (çok uzun satır 6000 karakterde kesilir)
      content.add(pw.Text(_t(l.length > 6000 ? '${l.substring(0, 6000)} …[kısaltıldı; tamamı juzzio_veri.json içinde]' : l), style: st(size: 8)));
    }
  }

  content.addAll([
    title('5. BÜTÜNLÜK MÜHRÜ VE YÖNETİCİ İMZA BLOĞU'),
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('BÜTÜNLÜK MÜHRÜ — SHA-256', style: st(size: 10.5, isBold: true)),
          pw.Text('JUZZIO · $archiveId', style: st(size: 8.5, isBold: true, color: _accent)),
        ]),
        pw.SizedBox(height: 6),
        kvTable([
          MapEntry('Ham veri (juzzio_veri.json) SHA-256', input.jsonSha256),
          MapEntry('Sunucu paket özeti (integrity_sha256)', _v(b['integrity_sha256'])),
          MapEntry(
              'Zaman damgası (RFC 3161)',
              ts == null
                  ? 'Alınamadı (zaman damgası sunucularına ulaşılamadı). Rapor zamanı sunucu saatidir (UTC): $generated'
                  : 'ALINDI · sağlayıcı: ${ts.authority} · istek zamanı (UTC): ${ts.requestedAtUtc.toIso8601String()} · '
                      'belirteç pakette: zaman_damgasi.tsr (${ts.token.length} bayt, ham verinin SHA-256 özeti üzerine)'),
          MapEntry('İşlem kimliği', '$archiveId · yasal talep kaydı no ${_v(b['request_id'])}'),
          MapEntry('Dışa aktaran', '@${_v(b['exported_by'])} · Süper Yönetici (kurucu) · kullanıcı kimliği ${_v(b['exported_by_id'])}'),
          const MapEntry('Aktarım', 'Yönetici oturumu doğrulanarak, TLS ile şifreli bağlantı üzerinden; işlem değiştirilemez denetim kaydına yazılmıştır.'),
          const MapEntry('Paket', 'Bu PDF ve ham veri, her talebe özel rastgele şifreyle AES-256 şifreli ZIP içinde teslim edilir. '
              'PDF dosyasının kendi özeti paketteki SHA256SUMS.txt dosyasındadır.'),
        ], keyWidth: 170),
      ]),
    ),
    pw.SizedBox(height: 8),
    pw.Text(_t(kJuzzioPdfDeliveryNote), style: st(size: 8.5)),
    pw.SizedBox(height: 6),
    pw.Text(
      _t('Bu rapor, Juzzio sistem kuralları gereği yalnız Süper Yönetici yetkisine sahip @${_v(b['exported_by'])} kullanıcısının '
          'doğrulanmış oturumu üzerinden dışa aktarılmıştır. İşlem kimliği: $archiveId.'),
      style: st(size: 8.5, isBold: true),
    ),
  ]);

  final doc = pw.Document(
    theme: theme,
    title: 'Juzzio Yasal Bilgi Talebi Raporu — $archiveId',
    author: 'Juzzio Sistemleri',
    creator: 'Juzzio',
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
