// =============================================================================
// JUZZIO v0.8.3 — Bildirimden hızlı yanıt (uygulamayı açmadan)
// Android bildirimindeki yanıt alanına yazılan metin, uygulamanın normal mesaj
// gönderme yolundan (SupabaseService.sendTextMessage) gönderilir. Böylece 1'e 1
// sohbetlerde uçtan uca şifreleme (X25519 + ML-KEM-768) aynen uygulanır; metin
// sunucuya düz yazı olarak gitmez. Oturum, cihazdaki kayıtlı Supabase oturumudur.
//
// v0.9.0 (ek paket N-E):
//  • İdempotent: Android tarafı her yanıt için tek bir `client_msg_id` üretir; çalışan
//    motor başarısız olup ekransız motora düşülse bile AYNI kimlik kullanılır. Sunucudaki
//    (sender_id, client_msg_id) benzersiz indeksi çift mesajı engeller; çakışma başarıdır.
//  • Fail-closed: şifreleme yapılamazsa mesaj GÖNDERİLMEZ (düz metne düşüş yok; bildirimden
//    açık onay alınamaz). Durum ayrı kodla bildirilir, kullanıcı uygulamayı açıp dener.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import 'juzzio_e2ee.dart';
import 'supabase_service.dart';

/// Hızlı yanıt sonucu. Android bildirim metni bu koda göre seçilir.
enum JuzzioQuickReplyStatus { ok, invalid, signedOut, e2eeUnavailable, failed }

class JuzzioQuickReply {
  JuzzioQuickReply._();

  static const int maxLength = 4000;
  static final RegExp _roomRe =
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final RegExp _clientIdRe = RegExp(r'^[A-Za-z0-9_-]{8,80}$');

  /// Test için gönderici değiştirilebilir (varsayılan: SupabaseService.sendTextMessage).
  static Future<void> Function({required String roomId, required String text, required String clientMsgId})?
      senderOverride;

  /// Test için oturum sorgusu değiştirilebilir.
  static String? Function()? currentUserOverride;

  /// Girdiyi doğrular; geçersizse null değil hata kodu döner.
  static JuzzioQuickReplyStatus? validate({required String roomId, required String text, String? clientMsgId}) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > maxLength) return JuzzioQuickReplyStatus.invalid;
    if (!_roomRe.hasMatch(roomId)) return JuzzioQuickReplyStatus.invalid;
    if (clientMsgId != null && clientMsgId.isNotEmpty && !_clientIdRe.hasMatch(clientMsgId)) {
      return JuzzioQuickReplyStatus.invalid;
    }
    return null;
  }

  /// Yanıtı gönderir ve ayrıntılı durum döndürür.
  static Future<JuzzioQuickReplyStatus> sendWithStatus({
    required String roomId,
    required String text,
    String? clientMsgId,
  }) async {
    final bad = validate(roomId: roomId, text: text, clientMsgId: clientMsgId);
    if (bad != null) return bad;
    final clean = text.trim();
    final id = (clientMsgId == null || clientMsgId.isEmpty) ? SupabaseService.newClientMsgId('qr') : clientMsgId;
    final uidLookup = currentUserOverride;
    final uid = uidLookup != null ? uidLookup() : Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return JuzzioQuickReplyStatus.signedOut;
    try {
      final override = senderOverride;
      if (override != null) {
        await override(roomId: roomId, text: clean, clientMsgId: id);
      } else {
        // kullanıcının dil/çeviri tercihleri (giden çeviri hedefi için)
        await JuzzioAppController.instance.loadUserPreferences(uid);
        await SupabaseService.instance.sendTextMessage(
          text: clean,
          targetRoomId: roomId,
          clientMsgId: id,
          // Bildirimden açık onay alınamaz → asla düz metin yok
          allowPlaintextFallback: false,
        );
      }
      return JuzzioQuickReplyStatus.ok;
    } on JuzzioE2eeRequiredException {
      return JuzzioQuickReplyStatus.e2eeUnavailable;
    } catch (_) {
      return JuzzioQuickReplyStatus.failed;
    }
  }

  /// Geriye uyumlu: başarılıysa true.
  static Future<bool> send({required String roomId, required String text, String? clientMsgId}) async =>
      await sendWithStatus(roomId: roomId, text: text, clientMsgId: clientMsgId) == JuzzioQuickReplyStatus.ok;

  /// Yerel kanala dönülen yanıt: {ok, status}.
  static Future<Map<String, Object>> handleChannelArgs(Map<dynamic, dynamic> args) async {
    final status = await sendWithStatus(
      roomId: '${args['room_id'] ?? ''}',
      text: '${args['text'] ?? ''}',
      clientMsgId: args['client_msg_id']?.toString(),
    );
    return {'ok': status == JuzzioQuickReplyStatus.ok, 'status': status.name};
  }
}
