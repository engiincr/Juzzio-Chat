// =============================================================================
// JUZZIO v1.2.9 — Yasal teslim paketi (yalnız kurucu süper yönetici)
//  Resmî makam talebinde çıktılar AÇIK HÂLDE diske yazılmaz. Bellekte üretilir ve tek bir
//  AES-256 şifreli ZIP (WinZip AE-2; 7-Zip, WinRAR, WinZip, macOS/Linux 7z ile açılır) olarak kaydedilir:
//    1) juzzio_rapor.pdf        — antetli PDF (kurum, dosya no, sebep, özet tablo, mühür)
//    2) juzzio_veri.json        — ham veri (sunucunun ürettiği paket, değiştirilmeden)
//    3) zaman_damgasi.tsr       — RFC 3161 zaman damgası (alınabildiyse; JSON'un SHA-256 özeti üzerine)
//    4) SHA256SUMS.txt          — dosyaların SHA-256 özetleri
//    5) DOGRULAMA.txt           — özet ve zaman damgasının nasıl doğrulanacağı
//  ZIP şifresi her talep için rastgele üretilir (12 hane), HİÇBİR YERE kaydedilmez/gönderilmez;
//  yalnız indirme bitince ekranda bir kez gösterilir.
//
//  Dış servisler (yalnız dışa aktarma anında, yöneticinin cihazından):
//   • RIPEstat (stat.ripe.net) — IP'nin servis sağlayıcısı (ASN / kurum adı). Yalnız IP adresi gider.
//   • Zaman damgası sunucusu (RFC 3161) — yalnız 32 baytlık SHA-256 özeti gider; kişisel veri gitmez.
//  İkisi de "en iyi çaba"dır: ulaşılamazsa rapor yine üretilir ve durum raporda açıkça yazılır.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Yöneticinin doldurduğu zorunlu adli başlık bilgileri
class JuzzioLegalRequestInfo {
  const JuzzioLegalRequestInfo({required this.authority, required this.caseNo, required this.purpose});
  final String authority; // Talep eden kurum / makam
  final String caseNo; // Dosya / esas numarası
  final String purpose; // Talep sebebi

  /// Üç alan da dolu mu? (en az 3 karakter) — saf; test edilir
  bool get isComplete => authority.trim().length >= 3 && caseNo.trim().length >= 3 && purpose.trim().length >= 3;

  /// Sunucu denetim kaydına yazılan tek satır gerekçe
  String toReason() => 'Makam: ${authority.trim()} | Dosya: ${caseNo.trim()} | Sebep: ${purpose.trim()}';
}

// Karışan karakterler yok (0/O, 1/l/I)
const String _pwAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

/// Her talebe özel rastgele ZIP şifresi (varsayılan 12 hane, kriptografik rastgele). Saf.
String juzzioLegalPassword({int length = 12, Random? random}) {
  final r = random ?? Random.secure();
  return List.generate(length, (_) => _pwAlphabet[r.nextInt(_pwAlphabet.length)]).join();
}

String juzzioSha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// Genel (internetten yönlendirilebilir) bir IPv4/IPv6 adresi mi? Özel/yerel adresler sorgulanmaz. Saf.
bool juzzioIsPublicIp(String ip) {
  final t = ip.trim();
  if (t.isEmpty || t == '-') return false;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(t);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!), b = int.parse(v4.group(2)!);
    if ([for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)].any((o) => o > 255)) return false;
    if (a == 10 || a == 127 || a == 0 || a >= 224) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a == 169 && b == 254) return false;
    if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
    return true;
  }
  if (!t.contains(':') || !RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(t)) return false;
  final l = t.toLowerCase();
  if (l == '::1' || l == '::' || l.startsWith('fe80') || l.startsWith('fc') || l.startsWith('fd')) return false;
  return true;
}

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const <Map<String, dynamic>>[];

/// Paketteki tüm benzersiz IP adresleri (giriş, cihaz, oturum, kimlik denetimi, yaşam döngüsü). Saf.
List<String> juzzioCollectIps(Map<String, dynamic> b) {
  final out = <String>{};
  void add(Object? v) {
    final t = (v ?? '').toString().trim();
    if (t.isNotEmpty && t != '-') out.add(t);
  }

  for (final e in _maps(b['login_events'])) {
    add(e['ip']);
  }
  for (final e in _maps(b['devices'])) {
    add(e['last_ip']);
  }
  for (final e in _maps(b['auth_sessions'])) {
    add(e['ip']);
  }
  for (final e in _maps(b['auth_audit'])) {
    add(e['ip']);
  }
  for (final e in _maps(b['lifecycle'])) {
    add(e['ip']);
  }
  return out.toList()..sort();
}

/// Özet tablo satırları (savcı/hâkim için tek bakışta). Saf; test edilir.
List<MapEntry<String, String>> juzzioLegalSummary(Map<String, dynamic> b, {DateTime? now, bool english = false}) {
  String L(String tr, String en) => english ? en : tr;
  String s(Object? v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? '-' : t;
  }

  final profile = b['profile'] is Map ? Map<String, dynamic>.from(b['profile'] as Map) : const <String, dynamic>{};
  final account = b['account'] is Map ? Map<String, dynamic>.from(b['account'] as Map) : const <String, dynamic>{};
  final msgs = _maps(b['messages']);
  final enc = msgs.where((m) => m['encrypted'] == true).length;
  final created = DateTime.tryParse(s(account['created_at']));
  final days = created == null ? '-' : '${(now ?? DateTime.now()).toUtc().difference(created.toUtc()).inDays} ${L('gün', 'days')}';
  final hold = b['legal_hold'];
  return <MapEntry<String, String>>[
    MapEntry(L('İncelenen hesap', 'Account examined'), '@${s(profile['username'])}'),
    MapEntry(L('Kullanıcı kimliği (UUID)', 'User ID (UUID)'), s(profile['id'])),
    MapEntry(L('E-posta / telefon', 'E-mail / phone'), '${s(account['email'])} / ${s(account['phone'])}'),
    MapEntry(L('Kayıt tarihi · hesap yaşı', 'Registered · account age'), '${s(account['created_at'])} · $days'),
    MapEntry(L('Son giriş', 'Last sign-in'), s(account['last_sign_in_at'])),
    MapEntry(L('Benzersiz IP adresi sayısı', 'Unique IP addresses'), '${juzzioCollectIps(b).length}'),
    MapEntry(L('Giriş kaydı sayısı', 'Sign-in records'), '${_maps(b['login_events']).length}'),
    MapEntry(L('Kayıtlı cihaz sayısı', 'Registered devices'), '${_maps(b['devices']).length}'),
    MapEntry(L('Sohbet / grup sayısı', 'Chats / groups'), '${_maps(b['rooms']).length} / ${_maps(b['groups']).length}'),
    MapEntry(L('Mesaj kaydı (üst veri)', 'Message records (metadata)'), L('${msgs.length} (bunların $enc tanesi uçtan uca şifreli)', '${msgs.length} ($enc of them end-to-end encrypted)')),
    MapEntry(L('Arama kaydı sayısı', 'Call records'), '${_maps(b['call_traffic']).isNotEmpty ? _maps(b['call_traffic']).length : _maps(b['call_logs']).length}'),
    MapEntry(L('Hesap hareketi (çıkış, silme vb.)', 'Account events (sign-out, deletion, etc.)'), '${_maps(b['lifecycle']).length}'),
    MapEntry(L('Veri dondurma', 'Legal hold'), hold is Map ? '${L('ETKİN', 'ACTIVE')} · ${s(hold['since'])} → ${s(hold['until'])}' : L('Yok', 'None')),
    MapEntry(
        L('Kritik uyarı', 'Critical notice'),
        L('Birebir sohbet ve arama İÇERİKLERİ uçtan uca şifrelidir ve sunucuda bulunmaz. '
                'Bağlantı/trafik kayıtları (zaman, IP, cihaz, oda) eksiksizdir.',
            'One-to-one chat and call CONTENTS are end-to-end encrypted and are not on the server. '
                'Connection/traffic records (time, IP, device, room) are complete.')),
  ];
}

// ---- RFC 3161 zaman damgası ---------------------------------------------------------

/// SHA-256 özeti için RFC 3161 TimeStampReq (DER). certReq = TRUE. Saf; test edilir.
Uint8List juzzioTsaRequest(List<int> sha256Digest) {
  if (sha256Digest.length != 32) throw ArgumentError('SHA-256 özeti 32 bayt olmalı');
  return Uint8List.fromList(<int>[
    0x30, 0x39, // TimeStampReq SEQUENCE (57)
    0x02, 0x01, 0x01, // version 1
    0x30, 0x31, // MessageImprint SEQUENCE (49)
    0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, // sha256 AlgorithmIdentifier
    0x04, 0x20, ...sha256Digest, // hashedMessage
    0x01, 0x01, 0xff, // certReq TRUE
  ]);
}

/// TimeStampResp "granted" (0) veya "grantedWithMods" (1) mi ve belirteç içeriyor mu? Saf; test edilir.
bool juzzioTsaGranted(List<int> resp) {
  try {
    var i = 0;
    int len() {
      final b = resp[i++];
      if (b < 0x80) return b;
      final n = b & 0x7f;
      var v = 0;
      for (var k = 0; k < n; k++) {
        v = (v << 8) | resp[i++];
      }
      return v;
    }

    if (resp[i++] != 0x30) return false; // TimeStampResp
    final total = len();
    final end = i + total;
    if (resp[i++] != 0x30) return false; // PKIStatusInfo
    final statusLen = len();
    final statusEnd = i + statusLen;
    if (resp[i++] != 0x02) return false; // status INTEGER
    final il = len();
    if (il < 1) return false;
    final status = resp[i + il - 1];
    if (status != 0 && status != 1) return false;
    return statusEnd < end && resp[statusEnd] == 0x30; // timeStampToken (ContentInfo) var
  } catch (_) {
    return false;
  }
}

class JuzzioTimestamp {
  const JuzzioTimestamp({required this.authority, required this.token, required this.requestedAtUtc});
  final String authority; // zaman damgası sunucusu
  final Uint8List token; // .tsr (TimeStampResp, DER)
  final DateTime requestedAtUtc;
}

/// HTTPS üzerinden ücretsiz, herkese açık RFC 3161 sunucuları (sırayla denenir)
const List<String> kJuzzioTsaServers = <String>[
  'https://freetsa.org/tsr',
  'https://timestamp.sectigo.com',
  'https://timestamp.digicert.com',
];

/// Özet için zaman damgası al (ulaşılamazsa null). Sunucuya yalnız özet gider.
Future<JuzzioTimestamp?> juzzioRequestTimestamp(List<int> sha256Digest, {http.Client? client, List<String> servers = kJuzzioTsaServers}) async {
  final c = client ?? http.Client();
  try {
    final req = juzzioTsaRequest(sha256Digest);
    for (final url in servers) {
      try {
        final res = await c
            .post(Uri.parse(url), headers: const {'Content-Type': 'application/timestamp-query', 'Accept': 'application/timestamp-reply'}, body: req)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && juzzioTsaGranted(res.bodyBytes)) {
          return JuzzioTimestamp(authority: Uri.parse(url).host, token: res.bodyBytes, requestedAtUtc: DateTime.now().toUtc());
        }
      } catch (_) {}
    }
    return null;
  } finally {
    if (client == null) c.close();
  }
}

// ---- Servis sağlayıcı (ASN / kurum) --------------------------------------------------

/// RIPEstat yanıtından "AS9121 — Turk Telekom" üret. Saf; test edilir.
String? juzzioIspFromRipe(Object? json) {
  if (json is! Map) return null;
  final data = json['data'];
  if (data is! Map) return null;
  final asns = data['asns'];
  if (asns is! List || asns.isEmpty || asns.first is! Map) return null;
  final a = Map<String, dynamic>.from(asns.first as Map);
  final asn = (a['asn'] ?? '').toString().trim();
  final holder = (a['holder'] ?? '').toString().trim();
  if (asn.isEmpty) return null;
  return holder.isEmpty ? 'AS$asn' : 'AS$asn — $holder';
}

/// Genel IP'lerin servis sağlayıcısı (en çok [max] adres, toplam ~25 sn). Bulunamayanlar haritada yer almaz.
Future<Map<String, String>> juzzioLookupIsps(Iterable<String> ips, {http.Client? client, int max = 40}) async {
  final c = client ?? http.Client();
  final out = <String, String>{};
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  try {
    for (final ip in ips.where(juzzioIsPublicIp).take(max)) {
      if (DateTime.now().isAfter(deadline)) break;
      try {
        final uri = Uri.https('stat.ripe.net', '/data/prefix-overview/data.json', {'resource': ip, 'sourceapp': 'juzzio-legal'});
        final res = await c.get(uri).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;
        final who = juzzioIspFromRipe(jsonDecode(utf8.decode(res.bodyBytes)));
        if (who != null) out[ip] = who;
      } catch (_) {}
    }
  } finally {
    if (client == null) c.close();
  }
  return out;
}

// ---- Şifreli ZIP -------------------------------------------------------------------

/// Dosyaları AES-256 şifreli tek bir ZIP'e koyar (ad → içerik). Şifre boş olamaz.
Uint8List juzzioBuildEncryptedZip(Map<String, List<int>> files, String password) {
  if (password.length < 8) throw ArgumentError('ZIP şifresi en az 8 karakter olmalı');
  final archive = Archive();
  files.forEach((name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)));
  // archive: şifre verildiğinde WinZip AES-256 (AE-2) ile şifreler
  return Uint8List.fromList(ZipEncoder(password: password).encode(archive));
}

/// SHA256SUMS.txt içeriği (sha256sum biçimi). Saf.
String juzzioSha256Sums(Map<String, List<int>> files) =>
    files.entries.map((e) => '${juzzioSha256Hex(e.value)}  ${e.key}').join('\n') + '\n';

/// DOGRULAMA.txt — özet ve zaman damgasının doğrulanması
String juzzioVerificationReadme({required bool hasTimestamp, required String tsaHost, bool english = false}) => english
    ? [
        'JUZZIO — LEGAL DELIVERY PACKAGE VERIFICATION GUIDE',
        '',
        '1) File integrity',
        '   sha256sum -c SHA256SUMS.txt        (Linux / macOS)',
        '   certutil -hashfile juzzio_veri.json SHA256    (Windows)',
        '   The digests must match SHA256SUMS.txt and the "Integrity Seal" in the PDF.',
        '',
        if (hasTimestamp) ...[
          '2) Timestamp (RFC 3161) — authority: $tsaHost',
          '   zaman_damgasi.tsr was obtained over the SHA-256 digest of juzzio_veri.json.',
          '   openssl ts -reply -in zaman_damgasi.tsr -text',
          '   openssl ts -verify -data juzzio_veri.json -in zaman_damgasi.tsr -CAfile <authority_root_certificate.pem>',
          '   The root certificate is downloaded from the authority\'s own website.',
          '   Note: this is an international timestamp service, not a "qualified" timestamp under Turkish Law No. 5070.',
        ] else ...[
          '2) Timestamp',
          '   Timestamp servers were unreachable when the report was generated; the package has no zaman_damgasi.tsr.',
          '   Times in the report are Juzzio server time (UTC).',
        ],
        '',
        '3) Server package digest',
        '   "integrity_sha256" inside juzzio_veri.json is the digest computed by the server when producing the data and',
        '   is stored with the same value in the legal request record (legal_requests) in the Juzzio database.',
        '',
      ].join('\n')
    : [

      'JUZZIO — YASAL TESLİM PAKETİ DOĞRULAMA KILAVUZU',
      '',
      '1) Dosya bütünlüğü',
      '   sha256sum -c SHA256SUMS.txt        (Linux / macOS)',
      '   certutil -hashfile juzzio_veri.json SHA256    (Windows)',
      '   Çıkan özetler SHA256SUMS.txt ve PDF içindeki "Bütünlük Mührü" ile aynı olmalıdır.',
      '',
      if (hasTimestamp) ...[
        '2) Zaman damgası (RFC 3161) — sağlayıcı: $tsaHost',
        '   zaman_damgasi.tsr, juzzio_veri.json dosyasının SHA-256 özeti üzerine alınmıştır.',
        '   openssl ts -reply -in zaman_damgasi.tsr -text',
        '   openssl ts -verify -data juzzio_veri.json -in zaman_damgasi.tsr -CAfile <saglayici_kok_sertifikasi.pem>',
        '   Kök sertifika, sağlayıcının kendi sitesinden indirilir.',
        '   Not: Bu, uluslararası bir zaman damgası hizmetidir; 5070 sayılı Kanun kapsamında "nitelikli" zaman',
        '   damgası (ör. Kamu SM / TÜBİTAK) değildir. Nitelikli zaman damgası gerekiyorsa ayrıca alınmalıdır.',
      ] else ...[
        '2) Zaman damgası',
        '   Rapor üretilirken zaman damgası sunucularına ulaşılamadı; pakette zaman_damgasi.tsr yoktur.',
        '   Rapordaki zaman, Juzzio sunucusunun (UTC) saatidir.',
      ],
      '',
      '3) Sunucu paket özeti',
      '   juzzio_veri.json içindeki "integrity_sha256", sunucunun veriyi üretirken hesapladığı özettir ve',
      '   Juzzio veritabanındaki yasal talep kaydında (legal_requests) aynı değerle saklanır.',
      '',
      ].join('\n');
