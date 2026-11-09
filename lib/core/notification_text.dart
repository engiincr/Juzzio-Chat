// =============================================================================
// JUZZIO v0.3.0 — Uygulama içi bildirim metinlerinin yerelleştirilmesi
// Veritabanı tetikleyicileri sabit (Türkçe) önizleme ya da "call:*" anahtarı yazar;
// burada olay türüne göre kullanıcının arayüz dilinde gösterilir. Kullanıcı
// içeriği (yorum, gönderi açıklaması, grup adı) olduğu gibi korunur.
// =============================================================================

import '../models/social_models.dart';
import '../services/juzzio_features_service.dart';
import 'app_theme_and_locale.dart';

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

String _callKind(String kind) {
  switch (kind) {
    case 'video':
      return _l('Görüntülü arama', 'Video call', 'Videoanruf');
    case 'group_video':
      return _l('Grup görüntülü araması', 'Group video call', 'Gruppen-Videoanruf');
    case 'group_voice':
      return _l('Grup sesli araması', 'Group voice call', 'Gruppen-Sprachanruf');
    default:
      return _l('Sesli arama', 'Voice call', 'Sprachanruf');
  }
}

/// "call:voice", "call:group_video:Başlık" gibi anahtarları ve eski Türkçe
/// arama önizlemelerini kullanıcının dilinde döndürür; değilse null.
String? juzzioLocalizedCallPreview(String preview) {
  final p = preview.trim();
  if (p.startsWith('call:')) {
    final parts = p.substring(5).split(':');
    final kind = parts.first;
    final title = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
    final label = _callKind(kind);
    return title.isEmpty ? label : '$title • $label';
  }
  if (p.endsWith('Görüntülü arama')) return p.replaceFirst(RegExp(r'Görüntülü arama$'), _callKind('video'));
  if (p.endsWith('Sesli arama')) return p.replaceFirst(RegExp(r'Sesli arama$'), _callKind('voice'));
  return null;
}

/// Bildirim listesinde gösterilecek metin.
String juzzioLocalizedNotificationText(JuzzioNotificationItem item) {
  final app = JuzzioAppController.instance;
  final preview = item.previewText.trim();
  final actor = item.actorDisplayName.isNotEmpty ? item.actorDisplayName : (item.actorUsername.isNotEmpty ? '@${item.actorUsername}' : 'Juzzio');
  final call = juzzioLocalizedCallPreview(preview);
  if (call != null) {
    if (item.eventType == 'missed_call') {
      return '${_l('Cevapsız', 'Missed', 'Verpasst')}: $call';
    }
    return call;
  }
  switch (item.eventType) {
    case 'follow':
      return _l('Seni takip etmeye başladı.', 'Started following you.', 'Folgt dir jetzt.');
    case 'follow_request':
      return _l('Seni takip etmek istiyor.', 'Wants to follow you.', 'Möchte dir folgen.');
    case 'follow_accepted':
      return _l('Takip isteğini kabul etti.', 'Accepted your follow request.', 'Hat deine Folgeanfrage angenommen.');
    case 'friend_request':
      return _l('Sana arkadaşlık isteği gönderdi.', 'Sent you a friend request.', 'Hat dir eine Freundschaftsanfrage gesendet.');
    case 'friend_accepted':
      return _l('Arkadaşlık isteğini kabul etti.', 'Accepted your friend request.', 'Hat deine Freundschaftsanfrage angenommen.');
    case 'story_like':
      return _l('Hikâyeni beğendi.', 'Liked your story.', 'Gefällt deine Story.');
    // v0.9.3: yorum yanıtı / beğenisi
    case 'reply':
      final r = juzzioParseReplyPreview(preview);
      if (r == null) {
        return preview.isEmpty
            ? _l('Yorumuna yanıt verdi.', 'Replied to your comment.', 'Hat auf deinen Kommentar geantwortet.')
            : '${_l('Yorumuna yanıt verdi', 'Replied to your comment', 'Hat geantwortet')}: $preview';
      }
      if (r.$1.isEmpty) {
        return _l('Yorumuna "${r.$2}" yanıtını verdi.', 'Replied "${r.$2}" to your comment.', 'Hat „${r.$2}“ auf deinen Kommentar geantwortet.');
      }
      return _l('"${r.$1}" yorumuna "${r.$2}" yanıtını verdi.', 'Replied "${r.$2}" to your comment "${r.$1}".',
          'Hat auf deinen Kommentar „${r.$1}“ mit „${r.$2}“ geantwortet.');
    case 'comment_like':
      return preview.isEmpty
          ? _l('Yorumunu beğendi.', 'Liked your comment.', 'Gefällt dein Kommentar.')
          : _l('"$preview" yorumunu beğendi.', 'Liked your comment "$preview".', 'Gefällt dein Kommentar „$preview“.');
    case 'comment':
      return preview.isEmpty
          ? _l('Gönderine yorum yaptı.', 'Commented on your post.', 'Hat deinen Beitrag kommentiert.')
          : '${_l('Gönderine yorum yaptı', 'Commented on your post', 'Hat kommentiert')}: $preview';
    case 'mention':
      if (preview.startsWith('comment|')) {
        final t = preview.substring(8);
        return t.isEmpty
            ? _l('Bir yorumda senden bahsetti.', 'Mentioned you in a comment.', 'Hat dich in einem Kommentar erwähnt.')
            : '${_l('Bir yorumda senden bahsetti', 'Mentioned you in a comment', 'Hat dich erwähnt')}: $t';
      }
      if (preview.startsWith('story|')) return _l('Hikâyesinde senden bahsetti.', 'Mentioned you in their story.', 'Hat dich in der Story erwähnt.');
      if (preview.startsWith('post|')) {
        final t = preview.substring(5);
        return t.isEmpty
            ? _l('Bir gönderide senden bahsetti.', 'Mentioned you in a post.', 'Hat dich in einem Beitrag erwähnt.')
            : '${_l('Bir gönderide senden bahsetti', 'Mentioned you in a post', 'Hat dich erwähnt')}: $t';
      }
      break;
    case 'like':
      if (preview.isEmpty || preview == 'Gönderini beğendi.') {
        return _l('Gönderini beğendi.', 'Liked your post.', 'Gefällt dein Beitrag.');
      }
      return '${_l('Gönderini beğendi', 'Liked your post', 'Gefällt dein Beitrag')}: $preview';
    case 'chick_invite':
      return app.t('chick_invite_incoming').replaceAll('{chick}', preview);
    case 'chick_hatched':
      return '${app.t('chick_hatched')} ($preview)';
    case 'chick_hungry':
      final g = JuzzioFeaturesService.instance.cachedGender;
      final base = g == 'female'
          ? app.t('chick_hungry_female')
          : g == 'male'
              ? app.t('chick_hungry_male')
              : app.t('chick_hungry_generic');
      return preview.isEmpty ? base : '$preview: $base';
    case 'chick_dying':
      return preview.isEmpty ? app.t('chick_mood_dying') : '$preview: ${app.t('chick_mood_dying')}';
    case 'chick_died':
      return app.t('chick_died_info').replaceAll('{name}', preview.isEmpty ? app.t('chick_title') : preview);
    // v0.9.5
    case 'poll_closed':
      final pp = juzzioPreviewParts(preview, 'poll');
      if (pp == null) return preview;
      return pp.length >= 4 && pp[1].isNotEmpty
          ? '📊 ${pp[0]} → ${pp[1]} (${pp[2]}/${pp[3]} ${app.trEn('oy', 'votes', 'Stimmen')})'
          : '📊 ${pp[0]} — ${app.trEn('anket kapandı', 'poll closed', 'Umfrage beendet')}';
    case 'memory':
      final mp = juzzioPreviewParts(preview, 'memory') ?? const ['1', ''];
      return '📸 ${app.trEn('Bugün ${mp[0]} yıl önce', '${mp[0]} year(s) ago today', 'Heute vor ${mp[0]} Jahr(en)')}${mp.length > 1 && mp[1].isNotEmpty ? ': ${mp[1]}' : ''}';
    case 'sos':
      final sp = juzzioPreviewParts(preview, 'sos') ?? const [''];
      final why = switch (sp.first) {
        'battery' => app.trEn('pili bitmek üzere', 'battery almost empty', 'Akku fast leer'),
        'inactive' => app.trEn('uzun süredir hareket yok', 'no movement for a while', 'keine Bewegung'),
        'overdue' => app.trEn('varış süresi doldu, haber yok', 'arrival time passed', 'Ankunftszeit überschritten'),
        _ => app.trEn('acil yardım istedi', 'asked for help', 'bittet um Hilfe'),
      };
      return '🆘 $actor: $why';
    case 'qa_question':
      return '❓ ${app.trEn('Yeni soru', 'New question', 'Neue Frage')}: $preview';
    case 'qa_answer':
      return '💬 $actor ${app.trEn('sorunu yanıtladı', 'answered your question', 'hat geantwortet')}: $preview';
    case 'watch_party':
      return '🎬 $actor ${app.trEn('izleme partisi başlattı', 'started a watch party', 'hat eine Watch-Party gestartet')}: ${preview.replaceFirst('watch|', '')}';
    case 'reminder':
      // v0.9.4: 'event|<başlık>' sohbet etkinliği, 'task|<başlık>' görev, 'message|' mesaj hatırlatıcısı
      if (preview.startsWith('event|')) {
        return '📅 ${app.trEn('Etkinlik yaklaşıyor', 'Event starting soon', 'Termin beginnt bald')}: ${preview.substring(6)}';
      }
      if (preview.startsWith('message|')) {
        return '⏰ ${app.trEn('Yanıtlamak için işaretlediğin mesajın zamanı geldi.', 'Time to reply to the message you marked.', 'Zeit, auf die markierte Nachricht zu antworten.')}';
      }
      return '⏰ ${preview.startsWith('task|') ? preview.substring(5) : preview}';
  }
  return preview;
}

/// v0.9.3: 'reply|<yanıtlanan yorum>|<yanıt>' → (yorum, yanıt); biçim değilse null.
(String, String)? juzzioParseReplyPreview(String preview) {
  if (!preview.startsWith('reply|')) return null;
  final rest = preview.substring(6);
  final i = rest.indexOf('|');
  if (i < 0) return null;
  return (rest.substring(0, i).trim(), rest.substring(i + 1).trim());
}

/// v0.9.5: '<önek>|a|b' → [a, b]; önek tutmuyorsa null.
List<String>? juzzioPreviewParts(String preview, String prefix) {
  if (!preview.startsWith('$prefix|')) return null;
  return preview.substring(prefix.length + 1).split('|');
}
