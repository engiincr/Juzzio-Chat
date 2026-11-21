// =============================================================================
// JUZZIO v1.2.9 — Yasal paket: insan tarafından okunur TXT rapor (resmî makamlara teslim)
//  admin_legal_export (juzzio_legal_bundle_v3) JSON'undan rapor BÖLÜMLERİ üretir; aynı bölümler
//  hem düz metin hem de antetli PDF (lib/services/juzzio_legal_pdf.dart) için kullanılır.
//  DÜRÜST SINIRLAR (raporda da yazılır):
//   • Birebir sohbet/arama içerikleri uçtan uca şifrelidir; sunucuda yoktur, kimse çözemez.
//   • IMEI toplanmaz: Android 10+ uygulamaların IMEI okumasını yasaklar (yalnız üretici/operatör).
//   • Şehir/konum toplanmaz: yalnız ağ ülkesi (CDN başlığı) ve IP kaydedilir. IP'nin hangi
//     aboneye ait olduğu ve yaklaşık konumu, resmî yazıyla internet servis sağlayıcısından istenir.
// =============================================================================

/// Birebir şifreli içeriğin sunulamamasının teknik ve hukuki açıklaması (rapora eklenir)
const String juzzioTechnicalImpossibilityStatement =
    'Juzzio birebir sohbetlerde ve aramalarda uçtan uca şifreleme kullanır (X25519 + ML-KEM-768, AES-256-GCM). '
    'Şifre çözme anahtarları yalnız konuşmanın taraflarının cihazlarında üretilir ve saklanır; sunucuya hiçbir zaman '
    'gönderilmez. Bu nedenle Juzzio, kurucusu ve yöneticileri dahil hiç kimse, sunucudaki birebir mesaj içeriklerini '
    'okuyamaz veya resmî makamlara okunur hâlde sunamaz; bu, bilginin saklanması ya da talebin reddedilmesi değil, '
    'sistemin teknik yapısından doğan bir imkânsızlıktır. Juzzio elindeki tüm verileri (hesap, telefon, e-posta, IP, '
    'cihaz, giriş/çıkış ve hesap silme kayıtları, grup üyelikleri, bildirim belirteçleri, arama trafik kaydı, '
    'şifresiz grup içerikleri, şikâyet kanıtları ve dondurulmuş arşiv) eksiksiz sunar. Birebir içerik; konuşmanın '
    'taraflarından birinin cihazından (Sohbeti dışa aktar özelliği veya adli bilişim incelemesi) elde edilebilir.';

/// v2.1: İngilizce sürüm (yabancı uyruklu yönetici ve yabancı makamlar için)
const String juzzioTechnicalImpossibilityStatementEn =
    'Juzzio uses end-to-end encryption for one-to-one chats and calls (X25519 + ML-KEM-768, AES-256-GCM). '
    'Decryption keys are generated and stored only on the devices of the parties to the conversation and are never '
    'sent to the server. Therefore no one, including Juzzio, its founder and its administrators, can read one-to-one '
    'message contents on the server or provide them to authorities in readable form; this is not withholding of '
    'information or refusal of the request, but a technical impossibility arising from the design of the system. '
    'Juzzio provides all data it holds in full (account, phone, e-mail, IP, device, sign-in/sign-out and account '
    'deletion records, group memberships, notification tokens, call traffic records, unencrypted group content, '
    'report evidence and the preserved archive). One-to-one content can be obtained from the device of one of the '
    'parties (chat export or forensic examination).';

String _s(Object? v) {
  if (v == null) return '-';
  final t = v.toString().trim();
  return t.isEmpty ? '-' : t;
}

List<Map<String, dynamic>> _list(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const <Map<String, dynamic>>[];

/// Raporun bir bölümü (TXT ve PDF aynı bölümlerden üretilir)
class JuzzioLegalSection {
  JuzzioLegalSection(this.title, this.lines);
  final String title;
  final List<String> lines;
}

/// Bölümler. [isp]: IP → "AS9121 — Turk Telekom" (boşsa yalnız IP yazılır). Saf; test edilir.
/// v2.1: [english] true → tüm başlık ve etiketler İngilizce (veri değerleri değişmez).
List<JuzzioLegalSection> juzzioLegalSections(Map<String, dynamic> b, {Map<String, String> isp = const {}, bool english = false}) {
  String L(String tr, String en) => english ? en : tr;
  final sections = <JuzzioLegalSection>[JuzzioLegalSection('', <String>[])];
  void h(String t) => sections.add(JuzzioLegalSection(t, <String>[]));
  void w(String line) => sections.last.lines.add(line);
  // IP'nin yanına servis sağlayıcı (ASN / kurum) bilgisi
  String ip(Object? v) {
    final t = _s(v);
    final who = isp[t];
    return who == null || who.isEmpty ? t : '$t ($who)';
  }

  final profile = b['profile'] is Map ? Map<String, dynamic>.from(b['profile'] as Map) : const <String, dynamic>{};
  final account = b['account'] is Map ? Map<String, dynamic>.from(b['account'] as Map) : const <String, dynamic>{};

  w('JUZZIO — YASAL BİLGİ TALEBİ RAPORU / LEGAL DATA REQUEST REPORT');
  w('${L('Biçim', 'Format')}: ${_s(b['format'])}');
  w('${L('Oluşturulma (UTC)', 'Generated (UTC)')}: ${_s(b['generated_at'])}');
  w('${L('Talep gerekçesi / resmî yazı', 'Reason for request / official letter')}: ${_s(b['reason'])}');
  w('${L('Bütünlük özeti (JSON, SHA-256)', 'Integrity digest (JSON, SHA-256)')}: ${_s(b['integrity_sha256'])}');
  w('${L('Arşiv / işlem no', 'Archive / transaction no')}: ${_s(b['archive_id'])} (${L('kayıt', 'record')} ${_s(b['request_id'])})');
  w('${L('Dışa aktaran', 'Exported by')}: @${_s(b['exported_by'])} (${L('Süper Yönetici', 'Super Administrator')}) · ${L('sunucu saati (UTC)', 'server time (UTC)')}: ${_s(b['server_time_utc'])}');

  h(L('KULLANICI', 'USER'));
  w('${L('Kullanıcı adı', 'Username')}: @${_s(profile['username'])}');
  w('${L('Görünen ad', 'Display name')}: ${_s(profile['display_name'])}');
  w('${L('Kullanıcı kimliği (UUID)', 'User ID (UUID)')}: ${_s(profile['id'])}');
  w('${L('E-posta', 'E-mail')}: ${_s(account['email'])}');
  w('${L('Telefon', 'Phone')}: ${_s(account['phone'])}');
  w('${L('Kayıt', 'Registered')}: ${_s(account['created_at'])}');
  w('${L('Son giriş', 'Last sign-in')}: ${_s(account['last_sign_in_at'])}');
  w('${L('Ülke (profil)', 'Country (profile)')}: ${_s(profile['country'])}');

  h(L('CİHAZLAR', 'DEVICES'));
  final devices = _list(b['devices']);
  if (devices.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final d in devices) {
    w('- Model: ${_s(d['model'])} · Platform: ${_s(d['platform'])} · ${L('İS', 'OS')}: ${_s(d['os'])} · ${L('Uygulama', 'App')}: ${_s(d['app_version'])}');
    w('  ${L('Cihaz kimliği', 'Device ID')}: ${_s(d['device_id'])} · ${L('Son IP', 'Last IP')}: ${ip(d['last_ip'])} · ${L('Ülke', 'Country')}: ${_s(d['last_country'])}');
    w('  ${L('İlk görülme', 'First seen')}: ${_s(d['first_seen'])} · ${L('Son görülme', 'Last seen')}: ${_s(d['last_seen'])}');
  }

  h(L('GİRİŞ KAYITLARI (IP / ÜLKE / CİHAZ)', 'SIGN-IN RECORDS (IP / COUNTRY / DEVICE)'));
  final logins = _list(b['login_events']);
  if (logins.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final l in logins) {
    w('- ${_s(l['at'])} · IP ${ip(l['ip'])} · ${_s(l['country'])} · ${_s(l['model'])} · v${_s(l['app_version'])}');
  }

  h(L('OTURUMLAR (kimlik doğrulama sunucusu)', 'SESSIONS (authentication server)'));
  final sessions = _list(b['auth_sessions']);
  if (sessions.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final s in sessions) {
    w('- ${_s(s['created_at'])} · IP ${ip(s['ip'])} · ${_s(s['user_agent'])}');
  }
  final audit = _list(b['auth_audit']);
  if (audit.isNotEmpty) {
    h(L('KİMLİK DENETİM KAYDI', 'AUTHENTICATION AUDIT LOG'));
    for (final a in audit) {
      w('- ${_s(a['at'])} · ${_s(a['action'])} · IP ${ip(a['ip'])}');
    }
  }

  h(L('SOHBETLER', 'CHATS'));
  final rooms = _list(b['rooms']);
  if (rooms.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final r in rooms) {
    final members = r['members'] is List ? (r['members'] as List).map((e) => '@$e').join(', ') : '-';
    w('- ${r['is_group'] == true ? L('Grup', 'Group') : L('Birebir', 'One-to-one')} · ${_s(r['title'])} · ${L('oda', 'room')} ${_s(r['room_id'])}');
    w('  ${L('Üyeler', 'Members')}: $members · ${L('Katılma', 'Joined')}: ${_s(r['joined_at'])} · ${L('Ayrılma', 'Left')}: ${_s(r['left_at'])}');
  }

  h(L('GÖNDERİLEN MESAJLAR', 'SENT MESSAGES'));
  final msgs = _list(b['messages']);
  var enc = 0;
  for (final m in msgs) {
    final e = m['encrypted'] == true;
    if (e) enc++;
    final text = e ? L('[uçtan uca şifreli — içerik sunucuda yok]', '[end-to-end encrypted — content not on server]') : _s(m['text']);
    w('- ${_s(m['at'])} · ${_s(m['type'])} · ${L('oda', 'room')} ${_s(m['room_id'])}${m['has_media'] == true ? ' · ${L('medya', 'media')}' : ''}: $text');
  }
  w(L('Toplam ${msgs.length} mesaj; $enc tanesi uçtan uca şifreli.', 'Total ${msgs.length} messages; $enc end-to-end encrypted.'));

  h(L('ARAMA KAYITLARI', 'CALL RECORDS'));
  final calls = _list(b['call_logs']);
  if (calls.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final c in calls) {
    w('- ${_s(c['created_at'])} · ${L('arayan', 'caller')} ${_s(c['caller_id'])} → ${L('aranan', 'callee')} ${_s(c['receiver_id'])} · ${c['is_video'] == true ? L('görüntülü', 'video') : L('sesli', 'voice')} · ${_s(c['status'])} · ${_s(c['duration_sec'])} ${L('sn', 's')}');
  }

  h(L('GÖNDERİLER VE YORUMLAR', 'POSTS AND COMMENTS'));
  for (final p in _list(b['posts'])) {
    w('- ${L('Gönderi', 'Post')} ${_s(p['created_at'])}: ${_s(p['caption'])}${p['is_deleted'] == true ? ' (${L('silinmiş', 'deleted')})' : ''}');
  }
  for (final c in _list(b['comments'])) {
    w('- ${L('Yorum', 'Comment')} ${_s(c['at'])}: ${_s(c['content'])}');
  }

  h(L('ŞİKÂYETLER VE YAPTIRIMLAR', 'REPORTS AND SANCTIONS'));
  w('${L('Bu kullanıcının yaptığı şikâyet', 'Reports filed by this user')}: ${_list(b['reports_filed']).length}');
  for (final r in _list(b['reports_against'])) {
    w('- ${L('Hakkında şikâyet', 'Report against user')} ${_s(r['created_at'])} · ${_s(r['reason_code'])} · ${_s(r['target_type'])} · ${_s(r['details'])}');
  }
  for (final s in _list(b['strikes'])) {
    w('- ${L('İhlal', 'Strike')} ${_s(s['created_at'])} · ${_s(s['reason'])}');
  }

  final hold = b['legal_hold'];
  h(L('VERİ DONDURMA (YASAL İNCELEME)', 'DATA PRESERVATION (LEGAL HOLD)'));
  if (hold is Map) {
    w('${L('Dondurma', 'Hold')}: ${_s(hold['since'])} → ${_s(hold['until'])} · ${_s(hold['reason'])}');
  } else {
    w(L('Etkin dondurma yok.', 'No active hold.'));
  }
  final preserved = _list(b['preserved']);
  w('${L('Arşivlenen (kullanıcının sildiği/değiştirdiği) kayıt', 'Preserved records (deleted/edited by the user)')}: ${preserved.length}');
  for (final p in preserved) {
    final d = p['data'] is Map ? Map<String, dynamic>.from(p['data'] as Map) : const <String, dynamic>{};
    final text = d['encrypted'] == true
        ? L('[uçtan uca şifreli — okunamaz]', '[end-to-end encrypted — unreadable]')
        : _s(d['original_text'] ?? d['caption'] ?? d['content'] ?? d['username'] ?? d['device_model']);
    w('- ${_s(p['at'])} · ${_s(p['kind'])} (${_s(p['op'])}) · ${_s(p['row_id'])}: $text');
  }

  h(L('GRUP ÜYELİKLERİ (SOSYAL BAĞLAR)', 'GROUP MEMBERSHIPS (SOCIAL CONNECTIONS)'));
  final groups = _list(b['groups']);
  if (groups.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final g in groups) {
    w('- ${_s(g['title'])} · ${L('oda', 'room')} ${_s(g['room_id'])} · ${L('kurucu', 'founder')} @${_s(g['founder'])}${g['is_founder'] == true ? ' (${L('bu kullanıcı', 'this user')})' : ''}'
        ' · ${L('rol', 'role')} ${_s(g['role'])} · ${L('üye', 'members')} ${_s(g['member_count'])} · ${L('katılma', 'joined')} ${_s(g['joined_at'])} · ${L('ayrılma', 'left')} ${_s(g['left_at'])}');
  }

  h(L('BİLDİRİM BELİRTEÇLERİ (Google FCM)', 'NOTIFICATION TOKENS (Google FCM)'));
  final tokens = _list(b['push_tokens']);
  if (tokens.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final t in tokens) {
    w('- ${_s(t['platform'])} · ${L('cihaz', 'device')} ${_s(t['device_id'])} · ${L('proje', 'project')} ${_s(t['firebase_project'])} · v${_s(t['app_version'])}');
    w('  ${L('Belirteç', 'Token')}: ${_s(t['token'])}');
  }
  w(L('Not: Belirtecin hangi Google hesabına/cihaza ait olduğu resmî yazıyla Google\'dan istenebilir.',
      'Note: The Google account/device a token belongs to can be requested from Google by official letter.'));

  h(L('HESAP YAŞAM DÖNGÜSÜ (çıkış, cihaz kaldırma, şifre, hesap silme)', 'ACCOUNT LIFECYCLE (sign-out, device removal, password, account deletion)'));
  final life = _list(b['lifecycle']);
  if (life.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final l in life) {
    w('- ${_s(l['at'])} · ${_s(l['event'])} ${_s(l['detail']) == '-' ? '' : '(${_s(l['detail'])}) '}· IP ${ip(l['ip'])} · ${_s(l['country'])} · ${_s(l['user_agent'])}');
  }

  h(L('ARAMA TRAFİK KAYDI (HTS benzeri)', 'CALL TRAFFIC RECORD (CDR-like)'));
  final traffic = _list(b['call_traffic']);
  if (traffic.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final c in traffic) {
    w('- ${_s(c['at'])} · @${_s(c['caller'])} → @${_s(c['callee'])} · ${_s(c['type'])} · ${_s(c['status'])} · ${_s(c['duration_sec'])} ${L('sn', 's')}');
  }

  h(L('ŞİKÂYET KANITLARI (şikâyet edenin cihazından, onayıyla)', 'REPORT EVIDENCE (from the reporter\'s device, with consent)'));
  final ev = _list(b['report_evidence']);
  if (ev.isEmpty) w(L('Kayıt yok.', 'No records.'));
  for (final e in ev) {
    w('- ${L('Şikâyet', 'Report')} ${_s(e['at'])} · @${_s(e['reporter'])} · ${_s(e['reason'])}');
    final evd = e['evidence'] is Map ? Map<String, dynamic>.from(e['evidence'] as Map) : const <String, dynamic>{};
    for (final m in _list(evd['messages'])) {
      w('    [${_s(m['at'])}] ${_s(m['sender'])}${m['reported'] == true ? ' (${L('ŞİKÂYET EDİLEN', 'REPORTED')})' : ''}: ${_s(m['text'])}');
    }
  }

  h(L('TEKNİK İMKÂNSIZLIK BEYANI', 'STATEMENT OF TECHNICAL IMPOSSIBILITY'));
  w(english ? juzzioTechnicalImpossibilityStatementEn : juzzioTechnicalImpossibilityStatement);

  h(L('ÖNEMLİ TEKNİK SINIRLAR', 'IMPORTANT TECHNICAL LIMITATIONS'));
  w(L('1) Birebir sohbet ve arama içerikleri uçtan uca şifrelidir; anahtarlar yalnız kullanıcıların cihazlarındadır.',
      '1) One-to-one chat and call contents are end-to-end encrypted; keys exist only on the users\' devices.'));
  w(L('   Juzzio dahil hiç kimse bu içerikleri sunucudan çözemez. İçerik, ancak cihazın kendisinden (adli bilişim) elde edilebilir.',
      '   No one, including Juzzio, can decrypt this content from the server. It can only be obtained from the device itself (forensics).'));
  w(L('2) IMEI toplanmaz: Android 10 ve sonrası uygulamaların IMEI okumasını işletim sistemi düzeyinde yasaklar.',
      '2) IMEI is not collected: Android 10 and later block apps from reading the IMEI at the OS level.'));
  w(L('   Cihaz kimliği olarak uygulamaya özgü cihaz kimliği ve model verilir; IMEI için operatör/üreticiye başvurulmalıdır.',
      '   An app-specific device ID and model are provided instead; for the IMEI, contact the carrier/manufacturer.'));
  w(L('3) Şehir/konum toplanmaz. Kayıtlı olan IP adresi ve ağ ülkesidir. IP\'nin abonesi ve yaklaşık konumu',
      '3) City/location is not collected; only the IP address and network country are recorded. The subscriber and approximate'));
  w(L('   resmî yazıyla ilgili internet servis sağlayıcısından (ör. BTK kayıtları) istenebilir.',
      '   location of an IP can be requested from the relevant internet service provider by official letter.'));
  w(_s(b['notice']));
  return sections;
}

/// Düz metin rapor. Saf; test edilir.
String juzzioLegalReportText(Map<String, dynamic> b, {Map<String, String> isp = const {}, bool english = false}) {
  final out = StringBuffer();
  for (final s in juzzioLegalSections(b, isp: isp, english: english)) {
    if (s.title.isNotEmpty) {
      out
        ..writeln()
        ..writeln('== ${s.title} ==');
    }
    for (final l in s.lines) {
      out.writeln(l);
    }
  }
  return out.toString();
}
