// =============================================================================
// JUZZIO v1.2.9 — Yasal paket: insan tarafından okunur TXT rapor (resmî makamlara teslim)
//  admin_legal_export (juzzio_legal_bundle_v2) JSON'undan düz metin rapor üretir.
//  JSON dosyası her zaman yanında verilir (bütünlük özeti sha256 JSON'a aittir).
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

/// Saf; test edilir
String juzzioLegalReportText(Map<String, dynamic> b) {
  final out = StringBuffer();
  void h(String t) => out
    ..writeln()
    ..writeln('== $t ==');
  final profile = b['profile'] is Map ? Map<String, dynamic>.from(b['profile'] as Map) : const <String, dynamic>{};
  final account = b['account'] is Map ? Map<String, dynamic>.from(b['account'] as Map) : const <String, dynamic>{};

  out.writeln('JUZZIO — YASAL BİLGİ TALEBİ RAPORU / LEGAL DATA REQUEST REPORT');
  out.writeln('Biçim: ${_s(b['format'])}');
  out.writeln('Oluşturulma (UTC): ${_s(b['generated_at'])}');
  out.writeln('Talep gerekçesi / resmî yazı: ${_s(b['reason'])}');
  out.writeln('Bütünlük özeti (JSON, SHA-256): ${_s(b['integrity_sha256'])}');

  h('KULLANICI');
  out.writeln('Kullanıcı adı: @${_s(profile['username'])}');
  out.writeln('Görünen ad: ${_s(profile['display_name'])}');
  out.writeln('Kullanıcı kimliği (UUID): ${_s(profile['id'])}');
  out.writeln('E-posta: ${_s(account['email'])}');
  out.writeln('Telefon: ${_s(account['phone'])}');
  out.writeln('Kayıt: ${_s(account['created_at'])}');
  out.writeln('Son giriş: ${_s(account['last_sign_in_at'])}');
  out.writeln('Ülke (profil): ${_s(profile['country'])}');

  h('CİHAZLAR');
  final devices = _list(b['devices']);
  if (devices.isEmpty) out.writeln('Kayıt yok.');
  for (final d in devices) {
    out.writeln('- Model: ${_s(d['model'])} · Platform: ${_s(d['platform'])} · İS: ${_s(d['os'])} · Uygulama: ${_s(d['app_version'])}');
    out.writeln('  Cihaz kimliği: ${_s(d['device_id'])} · Son IP: ${_s(d['last_ip'])} · Ülke: ${_s(d['last_country'])}');
    out.writeln('  İlk görülme: ${_s(d['first_seen'])} · Son görülme: ${_s(d['last_seen'])}');
  }

  h('GİRİŞ KAYITLARI (IP / ÜLKE / CİHAZ)');
  final logins = _list(b['login_events']);
  if (logins.isEmpty) out.writeln('Kayıt yok.');
  for (final l in logins) {
    out.writeln('- ${_s(l['at'])} · IP ${_s(l['ip'])} · ${_s(l['country'])} · ${_s(l['model'])} · v${_s(l['app_version'])}');
  }

  h('OTURUMLAR (kimlik doğrulama sunucusu)');
  final sessions = _list(b['auth_sessions']);
  if (sessions.isEmpty) out.writeln('Kayıt yok.');
  for (final s in sessions) {
    out.writeln('- ${_s(s['created_at'])} · IP ${_s(s['ip'])} · ${_s(s['user_agent'])}');
  }
  final audit = _list(b['auth_audit']);
  if (audit.isNotEmpty) {
    h('KİMLİK DENETİM KAYDI');
    for (final a in audit) {
      out.writeln('- ${_s(a['at'])} · ${_s(a['action'])} · IP ${_s(a['ip'])}');
    }
  }

  h('SOHBETLER');
  final rooms = _list(b['rooms']);
  if (rooms.isEmpty) out.writeln('Kayıt yok.');
  for (final r in rooms) {
    final members = r['members'] is List ? (r['members'] as List).map((e) => '@$e').join(', ') : '-';
    out.writeln('- ${r['is_group'] == true ? 'Grup' : 'Birebir'} · ${_s(r['title'])} · oda ${_s(r['room_id'])}');
    out.writeln('  Üyeler: $members · Katılma: ${_s(r['joined_at'])} · Ayrılma: ${_s(r['left_at'])}');
  }

  h('GÖNDERİLEN MESAJLAR');
  final msgs = _list(b['messages']);
  var enc = 0;
  for (final m in msgs) {
    final e = m['encrypted'] == true;
    if (e) enc++;
    final text = e ? '[uçtan uca şifreli — içerik sunucuda yok]' : _s(m['text']);
    out.writeln('- ${_s(m['at'])} · ${_s(m['type'])} · oda ${_s(m['room_id'])}${m['has_media'] == true ? ' · medya' : ''}: $text');
  }
  out.writeln('Toplam ${msgs.length} mesaj; $enc tanesi uçtan uca şifreli.');

  h('ARAMA KAYITLARI');
  final calls = _list(b['call_logs']);
  if (calls.isEmpty) out.writeln('Kayıt yok.');
  for (final c in calls) {
    out.writeln('- ${_s(c['created_at'])} · arayan ${_s(c['caller_id'])} → aranan ${_s(c['receiver_id'])} · ${c['is_video'] == true ? 'görüntülü' : 'sesli'} · ${_s(c['status'])} · ${_s(c['duration_sec'])} sn');
  }

  h('GÖNDERİLER VE YORUMLAR');
  for (final p in _list(b['posts'])) {
    out.writeln('- Gönderi ${_s(p['created_at'])}: ${_s(p['caption'])}${p['is_deleted'] == true ? ' (silinmiş)' : ''}');
  }
  for (final c in _list(b['comments'])) {
    out.writeln('- Yorum ${_s(c['at'])}: ${_s(c['content'])}');
  }

  h('ŞİKÂYETLER VE YAPTIRIMLAR');
  out.writeln('Bu kullanıcının yaptığı şikâyet: ${_list(b['reports_filed']).length}');
  for (final r in _list(b['reports_against'])) {
    out.writeln('- Hakkında şikâyet ${_s(r['created_at'])} · ${_s(r['reason_code'])} · ${_s(r['target_type'])} · ${_s(r['details'])}');
  }
  for (final s in _list(b['strikes'])) {
    out.writeln('- İhlal ${_s(s['created_at'])} · ${_s(s['reason'])}');
  }

  final hold = b['legal_hold'];
  h('VERİ DONDURMA (YASAL İNCELEME)');
  if (hold is Map) {
    out.writeln('Dondurma: ${_s(hold['since'])} → ${_s(hold['until'])} · ${_s(hold['reason'])}');
  } else {
    out.writeln('Etkin dondurma yok.');
  }
  final preserved = _list(b['preserved']);
  out.writeln('Arşivlenen (kullanıcının sildiği/değiştirdiği) kayıt: ${preserved.length}');
  for (final p in preserved) {
    final d = p['data'] is Map ? Map<String, dynamic>.from(p['data'] as Map) : const <String, dynamic>{};
    final text = d['encrypted'] == true
        ? '[uçtan uca şifreli — okunamaz]'
        : _s(d['original_text'] ?? d['caption'] ?? d['content'] ?? d['username'] ?? d['device_model']);
    out.writeln('- ${_s(p['at'])} · ${_s(p['kind'])} (${_s(p['op'])}) · ${_s(p['row_id'])}: $text');
  }

  h('GRUP ÜYELİKLERİ (SOSYAL BAĞLAR)');
  final groups = _list(b['groups']);
  if (groups.isEmpty) out.writeln('Kayıt yok.');
  for (final g in groups) {
    out.writeln('- ${_s(g['title'])} · oda ${_s(g['room_id'])} · kurucu @${_s(g['founder'])}${g['is_founder'] == true ? ' (bu kullanıcı)' : ''}'
        ' · rol ${_s(g['role'])} · üye ${_s(g['member_count'])} · katılma ${_s(g['joined_at'])} · ayrılma ${_s(g['left_at'])}');
  }

  h('BİLDİRİM BELİRTEÇLERİ (Google FCM)');
  final tokens = _list(b['push_tokens']);
  if (tokens.isEmpty) out.writeln('Kayıt yok.');
  for (final t in tokens) {
    out.writeln('- ${_s(t['platform'])} · cihaz ${_s(t['device_id'])} · proje ${_s(t['firebase_project'])} · v${_s(t['app_version'])}');
    out.writeln('  Belirteç: ${_s(t['token'])}');
  }
  out.writeln('Not: Belirtecin hangi Google hesabına/cihaza ait olduğu resmî yazıyla Google\'dan istenebilir.');

  h('HESAP YAŞAM DÖNGÜSÜ (çıkış, cihaz kaldırma, şifre, hesap silme)');
  final life = _list(b['lifecycle']);
  if (life.isEmpty) out.writeln('Kayıt yok.');
  for (final l in life) {
    out.writeln('- ${_s(l['at'])} · ${_s(l['event'])} ${_s(l['detail']) == '-' ? '' : '(${_s(l['detail'])}) '}· IP ${_s(l['ip'])} · ${_s(l['country'])} · ${_s(l['user_agent'])}');
  }

  h('ARAMA TRAFİK KAYDI (HTS benzeri)');
  final traffic = _list(b['call_traffic']);
  if (traffic.isEmpty) out.writeln('Kayıt yok.');
  for (final c in traffic) {
    out.writeln('- ${_s(c['at'])} · @${_s(c['caller'])} → @${_s(c['callee'])} · ${_s(c['type'])} · ${_s(c['status'])} · ${_s(c['duration_sec'])} sn');
  }

  h('ŞİKÂYET KANITLARI (şikâyet edenin cihazından, onayıyla)');
  final ev = _list(b['report_evidence']);
  if (ev.isEmpty) out.writeln('Kayıt yok.');
  for (final e in ev) {
    out.writeln('- Şikâyet ${_s(e['at'])} · @${_s(e['reporter'])} · ${_s(e['reason'])}');
    final evd = e['evidence'] is Map ? Map<String, dynamic>.from(e['evidence'] as Map) : const <String, dynamic>{};
    for (final m in _list(evd['messages'])) {
      out.writeln('    [${_s(m['at'])}] ${_s(m['sender'])}${m['reported'] == true ? ' (ŞİKÂYET EDİLEN)' : ''}: ${_s(m['text'])}');
    }
  }

  h('TEKNİK İMKÂNSIZLIK BEYANI');
  out.writeln(juzzioTechnicalImpossibilityStatement);

  h('ÖNEMLİ TEKNİK SINIRLAR');
  out.writeln('1) Birebir sohbet ve arama içerikleri uçtan uca şifrelidir; anahtarlar yalnız kullanıcıların cihazlarındadır.');
  out.writeln('   Juzzio dahil hiç kimse bu içerikleri sunucudan çözemez. İçerik, ancak cihazın kendisinden (adli bilişim) elde edilebilir.');
  out.writeln('2) IMEI toplanmaz: Android 10 ve sonrası uygulamaların IMEI okumasını işletim sistemi düzeyinde yasaklar.');
  out.writeln('   Cihaz kimliği olarak uygulamaya özgü cihaz kimliği ve model verilir; IMEI için operatör/üreticiye başvurulmalıdır.');
  out.writeln('3) Şehir/konum toplanmaz. Kayıtlı olan IP adresi ve ağ ülkesidir. IP\'nin abonesi ve yaklaşık konumu');
  out.writeln('   resmî yazıyla ilgili internet servis sağlayıcısından (ör. BTK kayıtları) istenebilir.');
  out.writeln(_s(b['notice']));
  return out.toString();
}
