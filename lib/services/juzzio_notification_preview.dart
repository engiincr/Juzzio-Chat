// =============================================================================
// JUZZIO v0.9.0 — Bildirimde mesaj içeriği (ek paket N-D)
//
// Sunucu FCM yüküne HİÇBİR ZAMAN mesaj metni koymaz (E2EE ve grup mesajları dahil).
// Kullanıcı önizleme kipi 'full' ise Android bildirimi çizmeden önce bu sınıfı çağırır:
// mesaj, cihazın kendi oturumuyla (RLS: yalnız oda üyesi) okunur ve E2EE ise cihazda
// çözülür. Çözülemezse null → bildirim genel metinle ("yeni mesaj") gösterilir.
// Çözülen metin hiçbir yere yazılmaz/loglanmaz; yalnızca yerel bildirime gider.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import 'juzzio_e2ee.dart';
import 'supabase_service.dart';

/// Kullanıcının bildirim önizleme kipi.
enum JuzzioNotificationPreviewMode { full, sender, hidden }

JuzzioNotificationPreviewMode juzzioPreviewModeFrom(Object? v) {
  switch (v?.toString()) {
    case 'sender':
      return JuzzioNotificationPreviewMode.sender;
    case 'hidden':
      return JuzzioNotificationPreviewMode.hidden;
    default:
      return JuzzioNotificationPreviewMode.full;
  }
}

class JuzzioNotificationPreview {
  JuzzioNotificationPreview._();

  static const int maxLength = 240;
  static final RegExp _uuidRe =
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Test için: mesaj satırını getiren fonksiyon (varsayılan: Supabase, RLS ile).
  static Future<Map<String, dynamic>?> Function(String roomId, String messageId)? fetchOverride;

  /// Test için: E2EE çözücü (varsayılan: JuzzioE2ee.decryptPreviewText).
  static Future<String?> Function(JuzzioMessage m)? decryptOverride;

  /// Tek satır, en fazla [maxLength] karakter.
  static String clip(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.length <= maxLength) return one;
    return '${one.substring(0, maxLength - 1)}…';
  }

  /// Bildirimde gösterilecek metin; gösterilemiyorsa null (çağıran genel metne düşer).
  static Future<String?> resolve({required String roomId, required String messageId}) async {
    if (!_uuidRe.hasMatch(roomId) || !_uuidRe.hasMatch(messageId)) return null;
    try {
      final fetch = fetchOverride;
      final Map<String, dynamic>? row;
      if (fetch != null) {
        row = await fetch(roomId, messageId);
      } else {
        final client = Supabase.instance.client;
        if (client.auth.currentUser == null) return null;
        row = await client
            .from('messages')
            .select()
            .eq('id', messageId)
            .eq('room_id', roomId)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));
      }
      if (row == null) return null;
      // Başka odanın mesajı (taklit edilmiş FCM verisi) gösterilmez
      if (row['room_id']?.toString() != roomId) return null;
      final exp = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (exp != null && exp.toUtc().isBefore(DateTime.now().toUtc())) return null;
      final msg = JuzzioMessage.fromMap(row);
      if (msg.isDeleted) return null;
      final label = _typeLabel(msg.messageType);
      if (label != null) return label;
      final dec = decryptOverride;
      final text = dec != null ? await dec(msg) : await JuzzioE2ee.instance.decryptPreviewText(msg);
      if (text == null || text.trim().isEmpty) return null;
      return clip(text);
    } catch (_) {
      return null;
    }
  }

  static String? _typeLabel(String type) {
    final app = JuzzioAppController.instance;
    switch (type) {
      case 'voice':
        return '🎤 ${app.trEn('Sesli mesaj', 'Voice message', 'Sprachnachricht')}';
      case 'image':
        return '📷 ${app.trEn('Fotoğraf', 'Photo', 'Foto')}';
      case 'video':
        return '🎬 ${app.trEn('Video', 'Video', 'Video')}';
      case 'document':
        return '📄 ${app.trEn('Belge', 'Document', 'Dokument')}';
      case 'location':
        return '📍 ${app.trEn('Konum', 'Location', 'Standort')}';
      case 'sticker':
        return app.trEn('Çıkartma', 'Sticker', 'Sticker');
      default:
        return null;
    }
  }

  /// Yerel kanal köprüsü: {room_id, message_id} → {text: String?}
  static Future<Map<String, Object?>> handleChannelArgs(Map<dynamic, dynamic> args) async {
    final text = await resolve(
      roomId: '${args['room_id'] ?? ''}',
      messageId: '${args['message_id'] ?? ''}',
    );
    return {'text': text};
  }
}
