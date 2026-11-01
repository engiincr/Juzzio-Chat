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
  }
  return preview;
}
