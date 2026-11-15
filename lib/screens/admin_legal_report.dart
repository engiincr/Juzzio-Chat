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
List<JuzzioLegalSection> juzzioLegalSections(Map<String, dynamic> b, {Map<String, String> isp = const {}}) {
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
  w('Biçim: ${_s(b['format'])}');
  w('Oluşturulma (UTC): ${_s(b['generated_at'])}');
  w('Talep gerekçesi / resmî yazı: ${_s(b['reason'])}');
  w('Bütünlük özeti (JSON, SHA-256): ${_s(b['integrity_sha256'])}');
  w('Arşiv / işlem no: ${_s(b['archive_id'])} (kayıt ${_s(b['request_id'])})');
  w('Dışa aktaran: @${_s(b['exported_by'])} (Süper Yönetici) · sunucu saati (UTC): ${_s(b['server_time_utc'])}');

  h('KULLANICI');
  w('Kullanıcı adı: @${_s(profile['username'])}');
  w('Görünen ad: ${_s(profile['display_name'])}');
  w('Kullanıcı kimliği (UUID): ${_s(profile['id'])}');
  w('E-posta: ${_s(account['email'])}');
  w('Telefon: ${_s(account['phone'])}');
  w('Kayıt: ${_s(account['created_at'])}');
  w('Son giriş: ${_s(account['last_sign_in_at'])}');
  w('Ülke (profil): ${_s(profile['country'])}');

  h('CİHAZLAR');
  final devices = _list(b['devices']);
  if (devices.isEmpty) w('Kayıt yok.');
  for (final d in devices) {
    w('- Model: ${_s(d['model'])} · Platform: ${_s(d['platform'])} · İS: ${_s(d['os'])} · Uygulama: ${_s(d['app_version'])}');
    w('  Cihaz kimliği: ${_s(d['device_id'])} · Son IP: ${ip(d['last_ip'])} · Ülke: ${_s(d['last_country'])}');
    w('  İlk görülme: ${_s(d['first_seen'])} · Son görülme: ${_s(d['last_seen'])}');
  }

  h('GİRİŞ KAYITLARI (IP / ÜLKE / CİHAZ)');
  final logins = _list(b['login_events']);
  if (logins.isEmpty) w('Kayıt yok.');
  for (final l in logins) {
    w('- ${_s(l['at'])} · IP ${ip(l['ip'])} · ${_s(l['country'])} · ${_s(l['model'])} · v${_s(l['app_version'])}');
  }

  h('OTURUMLAR (kimlik doğrulama sunucusu)');
  final sessions = _list(b['auth_sessions']);
  if (sessions.isEmpty) w('Kayıt yok.');
  for (final s in sessions) {
    w('- ${_s(s['created_at'])} · IP ${ip(s['ip'])} · ${_s(s['user_agent'])}');
  }
  final audit = _list(b['auth_audit']);
  if (audit.isNotEmpty) {
    h('KİMLİK DENETİM KAYDI');
    for (final a in audit) {
      w('- ${_s(a['at'])} · ${_s(a['action'])} · IP ${ip(a['ip'])}');
    }
  }

  h('SOHBETLER');
  final rooms = _list(b['rooms']);
  if (rooms.isEmpty) w('Kayıt yok.');
  for (final r in rooms) {
    final members = r['members'] is List ? (r['members'] as List).map((e) => '@$e').join(', ') : '-';
    w('- ${r['is_group'] == true ? 'Grup' : 'Birebir'} · ${_s(r['title'])} · oda ${_s(r['room_id'])}');
    w('  Üyeler: $members · Katılma: ${_s(r['joined_at'])} · Ayrılma: ${_s(r['left_at'])}');
  }

  h('GÖNDERİLEN MESAJLAR');
  final msgs = _list(b['messages']);
  var enc = 0;
  for (final m in msgs) {
    final e = m['encrypted'] == true;
    if (e) enc++;
    final text = e ? '[uçtan uca şifreli — içerik sunucuda yok]' : _s(m['text']);
    w('- ${_s(m['at'])} · ${_s(m['type'])} · oda ${_s(m['room_id'])}${m['has_media'] == true ? ' · medya' : ''}: $text');
  }
  w('Toplam ${msgs.length} mesaj; $enc tanesi uçtan uca şifreli.');

  h('ARAMA KAYITLARI');
  final calls = _list(b['call_logs']);
  if (calls.isEmpty) w('Kayıt yok.');
  for (final c in calls) {
    w('- ${_s(c['created_at'])} · arayan ${_s(c['caller_id'])} → aranan ${_s(c['receiver_id'])} · ${c['is_video'] == true ? 'görüntülü' : 'sesli'} · ${_s(c['status'])} · ${_s(c['duration_sec'])} sn');
  }

  h('GÖNDERİLER VE YORUMLAR');
  for (final p in _list(b['posts'])) {
    w('- Gönderi ${_s(p['created_at'])}: ${_s(p['caption'])}${p['is_deleted'] == true ? ' (silinmiş)' : ''}');
  }
  for (final c in _list(b['comments'])) {
    w('- Yorum ${_s(c['at'])}: ${_s(c['content'])}');
  }

  h('ŞİKÂYETLER VE YAPTIRIMLAR');
  w('Bu kullanıcının yaptığı şikâyet: ${_list(b['reports_filed']).length}');
  for (final r in _list(b['reports_against'])) {
    w('- Hakkında şikâyet ${_s(r['created_at'])} · ${_s(r['reason_code'])} · ${_s(r['target_type'])} · ${_s(r['details'])}');
  }
  for (final s in _list(b['strikes'])) {
    w('- İhlal ${_s(s['created_at'])} · ${_s(s['reason'])}');
  }

  final hold = b['legal_hold'];
  h('VERİ DONDURMA (YASAL İNCELEME)');
  if (hold is Map) {
    w('Dondurma: ${_s(hold['since'])} → ${_s(hold['until'])} · ${_s(hold['reason'])}');
  } else {
    w('Etkin dondurma yok.');
  }
  final preserved = _list(b['preserved']);
  w('Arşivlenen (kullanıcının sildiği/değiştirdiği) kayıt: ${preserved.length}');
  for (final p in preserved) {
    final d = p['data'] is Map ? Map<String, dynamic>.from(p['data'] as Map) : const <String, dynamic>{};
    final text = d['encrypted'] == true
        ? '[uçtan uca şifreli — okunamaz]'
        : _s(d['original_text'] ?? d['caption'] ?? d['content'] ?? d['username'] ?? d['device_model']);
    w('- ${_s(p['at'])} · ${_s(p['kind'])} (${_s(p['op'])}) · ${_s(p['row_id'])}: $text');
  }

  h('GRUP ÜYELİKLERİ (SOSYAL BAĞLAR)');
  final groups = _list(b['groups']);
  if (groups.isEmpty) w('Kayıt yok.');
  for (final g in groups) {
    w('- ${_s(g['title'])} · oda ${_s(g['room_id'])} · kurucu @${_s(g['founder'])}${g['is_founder'] == true ? ' (bu kullanıcı)' : ''}'
        ' · rol ${_s(g['role'])} · üye ${_s(g['member_count'])} · katılma ${_s(g['joined_at'])} · ayrılma ${_s(g['left_at'])}');
  }

  h('BİLDİRİM BELİRTEÇLERİ (Google FCM)');
  final tokens = _list(b['push_tokens']);
  if (tokens.isEmpty) w('Kayıt yok.');
  for (final t in tokens) {
    w('- ${_s(t['platform'])} · cihaz ${_s(t['device_id'])} · proje ${_s(t['firebase_project'])} · v${_s(t['app_version'])}');
    w('  Belirteç: ${_s(t['token'])}');
  }
  w('Not: Belirtecin hangi Google hesabına/cihaza ait olduğu resmî yazıyla Google\'dan istenebilir.');

  h('HESAP YAŞAM DÖNGÜSÜ (çıkış, cihaz kaldırma, şifre, hesap silme)');
  final life = _list(b['lifecycle']);
  if (life.isEmpty) w('Kayıt yok.');
  for (final l in life) {
    w('- ${_s(l['at'])} · ${_s(l['event'])} ${_s(l['detail']) == '-' ? '' : '(${_s(l['detail'])}) '}· IP ${ip(l['ip'])} · ${_s(l['country'])} · ${_s(l['user_agent'])}');
  }

  h('ARAMA TRAFİK KAYDI (HTS benzeri)');
  final traffic = _list(b['call_traffic']);
  if (traffic.isEmpty) w('Kayıt yok.');
  for (final c in traffic) {
    w('- ${_s(c['at'])} · @${_s(c['caller'])} → @${_s(c['callee'])} · ${_s(c['type'])} · ${_s(c['status'])} · ${_s(c['duration_sec'])} sn');
  }

  h('ŞİKÂYET KANITLARI (şikâyet edenin cihazından, onayıyla)');
  final ev = _list(b['report_evidence']);
  if (ev.isEmpty) w('Kayıt yok.');
  for (final e in ev) {
    w('- Şikâyet ${_s(e['at'])} · @${_s(e['reporter'])} · ${_s(e['reason'])}');
    final evd = e['evidence'] is Map ? Map<String, dynamic>.from(e['evidence'] as Map) : const <String, dynamic>{};
    for (final m in _list(evd['messages'])) {
      w('    [${_s(m['at'])}] ${_s(m['sender'])}${m['reported'] == true ? ' (ŞİKÂYET EDİLEN)' : ''}: ${_s(m['text'])}');
    }
  }

  h('TEKNİK İMKÂNSIZLIK BEYANI');
  w(juzzioTechnicalImpossibilityStatement);

  h('ÖNEMLİ TEKNİK SINIRLAR');
  w('1) Birebir sohbet ve arama içerikleri uçtan uca şifrelidir; anahtarlar yalnız kullanıcıların cihazlarındadır.');
  w('   Juzzio dahil hiç kimse bu içerikleri sunucudan çözemez. İçerik, ancak cihazın kendisinden (adli bilişim) elde edilebilir.');
  w('2) IMEI toplanmaz: Android 10 ve sonrası uygulamaların IMEI okumasını işletim sistemi düzeyinde yasaklar.');
  w('   Cihaz kimliği olarak uygulamaya özgü cihaz kimliği ve model verilir; IMEI için operatör/üreticiye başvurulmalıdır.');
  w('3) Şehir/konum toplanmaz. Kayıtlı olan IP adresi ve ağ ülkesidir. IP\'nin abonesi ve yaklaşık konumu');
  w('   resmî yazıyla ilgili internet servis sağlayıcısından (ör. BTK kayıtları) istenebilir.');
  w(_s(b['notice']));
  return sections;
}

/// Düz metin rapor. Saf; test edilir.
String juzzioLegalReportText(Map<String, dynamic> b, {Map<String, String> isp = const {}}) {
  final out = StringBuffer();
  for (final s in juzzioLegalSections(b, isp: isp)) {
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
