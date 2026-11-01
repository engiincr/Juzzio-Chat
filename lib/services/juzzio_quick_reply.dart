// =============================================================================
// JUZZIO v0.8.3 — Bildirimden hızlı yanıt (uygulamayı açmadan)
// Android bildirimindeki yanıt alanına yazılan metin, uygulamanın normal mesaj
// gönderme yolundan (SupabaseService.sendTextMessage) gönderilir. Böylece 1'e 1
// sohbetlerde uçtan uca şifreleme (X25519 + ML-KEM-768) aynen uygulanır; metin
// sunucuya düz yazı olarak gitmez. Oturum, cihazdaki kayıtlı Supabase oturumudur.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import 'supabase_service.dart';

class JuzzioQuickReply {
  JuzzioQuickReply._();

  static const int maxLength = 4000;

  /// Yanıtı gönderir. Başarılıysa true. Oturum yoksa / oda geçersizse false.
  static Future<bool> send({required String roomId, required String text}) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > maxLength) return false;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(roomId)) return false;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      // kullanıcının dil/çeviri tercihleri (giden çeviri hedefi için)
      await JuzzioAppController.instance.loadUserPreferences(uid);
      await SupabaseService.instance.sendTextMessage(text: clean, targetRoomId: roomId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
