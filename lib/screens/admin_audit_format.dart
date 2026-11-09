// =============================================================================
// JUZZIO v1.0.0 — Yönetici "Kayıtlar" ekranı: okunur, yöneticinin dilinde cümleler
//
//  Ham kayıt (ör. "ban_user • 3f2a…-uuid  {devices: 2, reason: spam}") yerine:
//    "@ayse, @mehmet kullanıcısını yasakladı"
//      Gerekçe: spam · 2 cihaz engellendi
//  Kim · ne yaptı · kime/neye · ne zaman — kodlar ve kimlikler gösterilmez (kimlik yalnız
//  ayrıntıya dokununca kopyalanabilir). Dil: yöneticinin uygulama dili (tr/en/de; diğer
//  dillerde İngilizce).
// =============================================================================

import 'package:flutter/material.dart';

/// Biçimlendirilmiş tek kayıt
class JuzzioAuditLine {
  const JuzzioAuditLine({required this.icon, required this.tone, required this.sentence, required this.details, required this.rawTarget});
  final IconData icon;

  /// 0 bilgi · 1 olumlu · 2 uyarı · 3 tehlikeli
  final int tone;
  final String sentence;
  final List<String> details;
  final String rawTarget;
}

typedef _T = String Function(String tr, String en, String de);

String _who(Map<String, dynamic> a) {
  final u = (a['admin_username'] ?? '').toString().trim();
  return u.isEmpty ? '?' : '@$u';
}

/// Hedefi okunur hâle getirir: kullanıcı adı varsa @ad, UUID ise kısaltılmış biçim, yoksa metin
String _target(Map<String, dynamic> a, _T t) {
  final tu = (a['target_username'] ?? '').toString().trim();
  if (tu.isNotEmpty) return '@$tu';
  final tn = (a['target_name'] ?? '').toString().trim();
  if (tn.isNotEmpty) return '“$tn”';
  final raw = (a['target'] ?? '').toString().trim();
  if (raw.isEmpty) return '';
  if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-').hasMatch(raw)) return '#${raw.substring(0, 8)}';
  return '“$raw”';
}

String _bool(dynamic v, _T t) => (v == true || v == 'true') ? t('evet', 'yes', 'ja') : t('hayır', 'no', 'nein');

String _role(String r, _T t) {
  switch (r) {
    case 'super_admin':
      return t('süper yönetici', 'super admin', 'Super-Admin');
    case 'admin':
      return t('yönetici', 'admin', 'Admin');
    case 'moderator':
      return t('moderatör', 'moderator', 'Moderator');
    case 'support':
      return t('destek', 'support', 'Support');
    case 'auditor':
      return t('denetçi', 'auditor', 'Prüfer');
    case 'user':
    case '':
      return t('kullanıcı', 'user', 'Nutzer');
    default:
      return r.replaceAll('_', ' ');
  }
}

String _status(String s, _T t) {
  switch (s) {
    case 'open':
      return t('açık', 'open', 'offen');
    case 'reviewed':
      return t('incelendi', 'reviewed', 'geprüft');
    case 'resolved':
      return t('çözüldü', 'resolved', 'gelöst');
    case 'dismissed':
      return t('reddedildi', 'dismissed', 'abgelehnt');
    case 'approved':
      return t('onaylandı', 'approved', 'genehmigt');
    case 'rejected':
      return t('reddedildi', 'rejected', 'abgelehnt');
    case 'pending':
      return t('beklemede', 'pending', 'ausstehend');
    case 'ignored':
      return t('yok sayıldı', 'ignored', 'ignoriert');
    default:
      return s;
  }
}

String _contentType(String s, _T t) {
  switch (s) {
    case 'post':
      return t('gönderi', 'post', 'Beitrag');
    case 'comment':
      return t('yorum', 'comment', 'Kommentar');
    case 'story':
      return t('hikâye', 'story', 'Story');
    case 'message':
      return t('mesaj', 'message', 'Nachricht');
    default:
      return s;
  }
}

/// Saf fonksiyon: kaydı yöneticinin dilinde cümleye çevirir (birim testli).
JuzzioAuditLine juzzioFormatAudit(Map<String, dynamic> a, String lang) {
  final l = lang.toLowerCase();
  String t(String tr, String en, String de) => l == 'tr' ? tr : (l == 'de' ? de : en);
  final who = _who(a);
  final target = _target(a, t);
  final d = a['details'] is Map ? Map<String, dynamic>.from(a['details'] as Map) : <String, dynamic>{};
  final action = (a['action'] ?? '').toString();
  final details = <String>[];
  void add(String label, dynamic v) {
    if (v == null) return;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return;
    details.add('$label: $s');
  }

  var icon = Icons.history_rounded;
  var tone = 0;
  late String sentence;
  switch (action) {
    case 'ban_user':
      icon = Icons.block_rounded;
      tone = 3;
      sentence = t('$who, $target kullanıcısını yasakladı', '$who banned $target', '$who hat $target gesperrt');
      add(t('Gerekçe', 'Reason', 'Grund'), d['reason']);
      if (d['devices'] != null) details.add(t('${d['devices']} cihaz engellendi', '${d['devices']} device(s) blocked', '${d['devices']} Gerät(e) gesperrt'));
    case 'unban_user':
      icon = Icons.lock_open_rounded;
      tone = 1;
      sentence = t('$who, $target kullanıcısının yasağını kaldırdı', '$who lifted the ban on $target', '$who hat die Sperre von $target aufgehoben');
    case 'suspend_user':
      icon = Icons.pause_circle_outline_rounded;
      tone = 2;
      sentence = t('$who, $target kullanıcısını ${d['hours'] ?? '?'} saat askıya aldı', '$who suspended $target for ${d['hours'] ?? '?'} hours',
          '$who hat $target für ${d['hours'] ?? '?'} Stunden gesperrt');
      add(t('Gerekçe', 'Reason', 'Grund'), d['reason']);
    case 'warn_user':
      icon = Icons.warning_amber_rounded;
      tone = 2;
      sentence = t('$who, $target kullanıcısına uyarı gönderdi', '$who warned $target', '$who hat $target verwarnt');
      add(t('Mesaj', 'Message', 'Nachricht'), d['message']);
    case 'view_user_detail':
      icon = Icons.visibility_outlined;
      sentence = t('$who, $target kullanıcısının ayrıntılarını görüntüledi', '$who viewed the details of $target', '$who hat die Details von $target angesehen');
      if (d['pii'] == true) details.add(t('Kişisel veriler dahil', 'Including personal data', 'Inklusive personenbezogener Daten'));
    case 'set_verified':
      icon = Icons.verified_rounded;
      tone = 1;
      sentence = d['verified'] == true
          ? t('$who, $target hesabına mavi tik verdi', '$who verified $target', '$who hat $target verifiziert')
          : t('$who, $target hesabının mavi tikini kaldırdı', '$who removed verification from $target', '$who hat die Verifizierung von $target entfernt');
    case 'set_app_role':
    case 'grant_role':
      icon = Icons.admin_panel_settings_outlined;
      tone = 2;
      sentence = t('$who, $target kullanıcısına “${_role('${d['role'] ?? ''}', t)}” yetkisi verdi', '$who gave $target the “${_role('${d['role'] ?? ''}', t)}” role',
          '$who hat $target die Rolle „${_role('${d['role'] ?? ''}', t)}“ gegeben');
    case 'revoke_role':
      icon = Icons.remove_moderator_outlined;
      tone = 2;
      sentence = t('$who, $target kullanıcısının “${_role('${d['role'] ?? ''}', t)}” yetkisini aldı', '$who removed the “${_role('${d['role'] ?? ''}', t)}” role from $target',
          '$who hat $target die Rolle „${_role('${d['role'] ?? ''}', t)}“ entzogen');
    case 'report_status':
      icon = Icons.flag_outlined;
      sentence = t('$who bir şikâyeti “${_status('${d['status'] ?? ''}', t)}” olarak işaretledi', '$who marked a report as “${_status('${d['status'] ?? ''}', t)}”',
          '$who hat eine Meldung als „${_status('${d['status'] ?? ''}', t)}“ markiert');
    case 'broadcast':
      icon = Icons.campaign_outlined;
      sentence = t('$who herkese duyuru gönderdi', '$who sent a broadcast', '$who hat eine Rundnachricht gesendet');
      add(t('Başlık', 'Title', 'Titel'), d['title']);
      if (d['count'] != null) details.add(t('${d['count']} kişiye ulaştı', 'Reached ${d['count']} people', 'An ${d['count']} Personen gesendet'));
    case 'delete_content':
      icon = Icons.delete_outline_rounded;
      tone = 3;
      sentence = t('$who bir ${_contentType('${d['type'] ?? ''}', t)} sildi', '$who deleted a ${_contentType('${d['type'] ?? ''}', t)}',
          '$who hat einen ${_contentType('${d['type'] ?? ''}', t)} gelöscht');
    case 'publish_release':
      icon = Icons.rocket_launch_outlined;
      tone = 1;
      sentence = t('$who yeni sürüm yayınladı', '$who published a release', '$who hat eine Version veröffentlicht');
      add(t('Sürüm kodu', 'Version code', 'Versionscode'), d['code']);
      if (d['mandatory'] == true) details.add(t('Zorunlu güncelleme', 'Mandatory update', 'Pflicht-Update'));
    case 'delete_release':
      icon = Icons.delete_sweep_outlined;
      tone = 2;
      sentence = t('$who bir sürüm kaydını sildi', '$who deleted a release', '$who hat eine Version gelöscht');
    case 'set_setting':
      icon = Icons.tune_rounded;
      sentence = t('$who $target ayarını değiştirdi', '$who changed the $target setting', '$who hat die Einstellung $target geändert');
      add(t('Yeni değer', 'New value', 'Neuer Wert'), d['value']);
    case 'moderation_strike':
      icon = Icons.gavel_rounded;
      tone = 3;
      sentence = t('$who, $target kullanıcısına ihlal cezası verdi', '$who issued a strike to $target', '$who hat $target eine Verwarnung erteilt');
      add(t('Tür', 'Kind', 'Art'), d['kind']);
      add(t('Ceza', 'Penalty', 'Strafe'), d['penalty']);
      add(t('Kaynak', 'Source', 'Quelle'), d['source']);
    case 'revoke_strike':
      icon = Icons.undo_rounded;
      tone = 1;
      sentence = t('$who bir ihlal cezasını geri aldı', '$who revoked a strike', '$who hat eine Verwarnung zurückgenommen');
      if (d['lift_ban'] == true) details.add(t('Yasak da kaldırıldı', 'The ban was lifted too', 'Sperre ebenfalls aufgehoben'));
    case 'review_media':
      icon = Icons.image_search_rounded;
      sentence = d['approve'] == true
          ? t('$who bir medyayı onayladı', '$who approved a media item', '$who hat ein Medium freigegeben')
          : t('$who bir medyayı reddetti', '$who rejected a media item', '$who hat ein Medium abgelehnt');
      tone = d['approve'] == true ? 1 : 2;
    case 'upsert_banned_term':
      icon = Icons.do_not_disturb_on_outlined;
      sentence = t('$who yasaklı kelime listesini güncelledi: $target', '$who updated the banned term $target', '$who hat den gesperrten Begriff $target aktualisiert');
      add(t('Kip', 'Mode', 'Modus'), d['mode']);
      if (d['speech'] != null) add(t('Konuşmada da', 'Also in speech', 'Auch in Sprache'), _bool(d['speech'], t));
    case 'delete_banned_term':
      icon = Icons.remove_circle_outline_rounded;
      sentence = t('$who yasaklı kelimeyi kaldırdı: $target', '$who removed the banned term $target', '$who hat den gesperrten Begriff $target entfernt');
    case 'update_user_profile':
      icon = Icons.manage_accounts_outlined;
      tone = 2;
      sentence = t('$who, $target profilini düzenledi', '$who edited the profile of $target', '$who hat das Profil von $target bearbeitet');
      add(t('Yeni ad', 'New name', 'Neuer Name'), d['display_name']);
      add(t('Yeni kullanıcı adı', 'New username', 'Neuer Benutzername'), d['username']);
      if (d['clear_avatar'] == true) details.add(t('Profil fotoğrafı kaldırıldı', 'Profile photo removed', 'Profilbild entfernt'));
    case 'sign_out_user':
      icon = Icons.logout_rounded;
      tone = 2;
      sentence = t('$who, $target kullanıcısının oturumlarını kapattı', '$who signed $target out', '$who hat $target abgemeldet');
      if (d['sessions'] != null) details.add(t('${d['sessions']} oturum', '${d['sessions']} session(s)', '${d['sessions']} Sitzung(en)'));
    case 'kill_all_sessions':
      icon = Icons.power_settings_new_rounded;
      tone = 3;
      sentence = t('$who TÜM kullanıcıların oturumlarını kapattı', '$who signed out ALL users', '$who hat ALLE Nutzer abgemeldet');
      if (d['sessions'] != null) details.add(t('${d['sessions']} oturum', '${d['sessions']} session(s)', '${d['sessions']} Sitzung(en)'));
    case 'delete_user':
      {
        icon = Icons.person_remove_outlined;
        tone = 3;
        final u = (d['username'] ?? '').toString();
        final who2 = u.isNotEmpty ? '@$u' : target;
        sentence = t('$who $who2 hesabını sildi', '$who deleted the account $who2', '$who hat das Konto $who2 gelöscht');
      }
    case 'update_group':
      icon = Icons.groups_outlined;
      sentence = t('$who bir grubu düzenledi', '$who edited a group', '$who hat eine Gruppe bearbeitet');
      add(t('Yeni ad', 'New title', 'Neuer Titel'), d['title']);
    case 'remove_group_member':
      icon = Icons.group_remove_outlined;
      tone = 2;
      sentence = t('$who bir grup üyesini çıkardı', '$who removed a group member', '$who hat ein Gruppenmitglied entfernt');
    case 'delete_group':
      icon = Icons.delete_forever_outlined;
      tone = 3;
      sentence = t('$who “${d['title'] ?? ''}” grubunu sildi', '$who deleted the group “${d['title'] ?? ''}”', '$who hat die Gruppe „${d['title'] ?? ''}“ gelöscht');
    case 'end_call':
      icon = Icons.call_end_rounded;
      tone = 2;
      sentence = t('$who bir aramayı sonlandırdı', '$who ended a call', '$who hat einen Anruf beendet');
    case 'theme_save_draft':
      icon = Icons.palette_outlined;
      sentence = t('$who tema taslağını kaydetti', '$who saved a theme draft', '$who hat einen Theme-Entwurf gespeichert');
      add(t('Ad', 'Name', 'Name'), d['name']);
    case 'theme_publish':
      icon = Icons.palette_rounded;
      tone = 1;
      sentence = t('$who bir temayı yayınladı', '$who published a theme', '$who hat ein Theme veröffentlicht');
    case 'theme_rollback':
      icon = Icons.history_rounded;
      tone = 2;
      sentence = t('$who temayı önceki sürüme döndürdü', '$who rolled a theme back', '$who hat ein Theme zurückgesetzt');
    case 'theme_archive':
      icon = Icons.archive_outlined;
      sentence = t('$who bir temayı arşivledi', '$who archived a theme', '$who hat ein Theme archiviert');
    case 'legal_publish':
      icon = Icons.policy_outlined;
      tone = 1;
      sentence = t('$who yasal metni yayınladı', '$who published a legal document', '$who hat ein Rechtsdokument veröffentlicht');
      add(t('Sürüm', 'Version', 'Version'), d['version']);
    case 'legal_export':
      icon = Icons.file_download_outlined;
      tone = 2;
      sentence = t('$who, $target için yasal veri dışa aktarımı yaptı', '$who exported legal data for $target', '$who hat Rechtsdaten für $target exportiert');
      add(t('Gerekçe', 'Reason', 'Grund'), d['reason']);
    case 'business_status':
      icon = Icons.storefront_outlined;
      sentence = t('$who bir işletme başvurusunu “${_status('${d['status'] ?? ''}', t)}” yaptı', '$who set a business application to “${_status('${d['status'] ?? ''}', t)}”',
          '$who hat einen Unternehmensantrag auf „${_status('${d['status'] ?? ''}', t)}“ gesetzt');
      add(t('Gerekçe', 'Reason', 'Grund'), d['reason']);
    case 'business_verify':
      icon = Icons.verified_outlined;
      tone = 1;
      sentence = t('$who bir işletmeyi doğruladı', '$who verified a business', '$who hat ein Unternehmen verifiziert');
    case 'qa_reveal_sender':
      icon = Icons.person_search_outlined;
      tone = 2;
      sentence = t('$who anonim bir sorunun göndericisini görüntüledi', '$who revealed the sender of an anonymous question', '$who hat den Absender einer anonymen Frage angezeigt');
    case 'app_error_status':
      icon = Icons.bug_report_outlined;
      sentence = t('$who bir uygulama hatasını “${_status('${d['status'] ?? ''}', t)}” yaptı', '$who set an app error to “${_status('${d['status'] ?? ''}', t)}”',
          '$who hat einen App-Fehler auf „${_status('${d['status'] ?? ''}', t)}“ gesetzt');
    case 'storage_queue_retry':
      icon = Icons.refresh_rounded;
      sentence = t('$who depolama temizlik kuyruğunu yeniden denedi', '$who retried the storage cleanup queue', '$who hat die Speicherbereinigung erneut versucht');
    case 'orphan_media_scan':
      icon = Icons.cleaning_services_outlined;
      sentence = t('$who sahipsiz medya taraması yaptı', '$who ran an orphan media scan', '$who hat verwaiste Medien gesucht');
      if (d['enqueued'] != null) details.add(t('${d['enqueued']} dosya silme kuyruğuna alındı', '${d['enqueued']} file(s) queued for deletion', '${d['enqueued']} Datei(en) zur Löschung vorgemerkt'));
    default:
      // Bilinmeyen eylem: kodu okunur kelimelere çevir (alt çizgi → boşluk)
      final words = action.replaceAll(RegExp(r'[_.]+'), ' ').trim();
      sentence = t('$who: $words${target.isNotEmpty ? ' → $target' : ''}', '$who: $words${target.isNotEmpty ? ' → $target' : ''}',
          '$who: $words${target.isNotEmpty ? ' → $target' : ''}');
      d.forEach((k, v) {
        if (v is Map || v is List) return;
        add(k.replaceAll('_', ' '), v);
      });
  }
  return JuzzioAuditLine(icon: icon, tone: tone, sentence: sentence, details: details, rawTarget: (a['target'] ?? '').toString());
}
