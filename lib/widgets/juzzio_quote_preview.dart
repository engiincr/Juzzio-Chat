// =============================================================================
// JUZZIO v1.1.0 — Alıntı (yanıt) önizlemesi
//  • Görsel alıntılandığında "Medya"/resim yazısı yerine küçük resim gösterilir;
//    kullanıcı hangi fotoğrafa yanıt verildiğini görür.
//  • Video: küçük oynat kutusu; sesli mesaj: süre; belge: dosya adı.
//  • Dokununca [onTap] → sohbet alıntılanan mesaja kayar ve onu parlatır.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_media_url.dart';
import '../services/supabase_service.dart';
import 'juzzio_encrypted_image.dart';

enum JuzzioQuoteKind { text, image, video, voice, document, viewOnce, deleted, missing }

/// Alıntılanan mesajın türü (saf; test edilir)
JuzzioQuoteKind juzzioQuoteKind(JuzzioMessage? m) {
  if (m == null) return JuzzioQuoteKind.missing;
  if (m.isDeleted) return JuzzioQuoteKind.deleted;
  if (m.isViewOnce) return JuzzioQuoteKind.viewOnce;
  if ((m.imageUrl ?? '').isNotEmpty) return JuzzioQuoteKind.image;
  if ((m.videoUrl ?? '').isNotEmpty) return JuzzioQuoteKind.video;
  if ((m.audioUrl ?? '').isNotEmpty || m.messageType == 'voice' || m.messageType == 'audio') return JuzzioQuoteKind.voice;
  if (m.messageType == 'document' || (m.documentUrl ?? '').isNotEmpty) return JuzzioQuoteKind.document;
  return JuzzioQuoteKind.text;
}

/// Alıntı satırında gösterilecek kısa metin. Görsel/video için resim yazısı DEĞİL tür etiketi
/// döner (küçük resim zaten görünür); kullanıcı açıklama yazdıysa etiketin yanına eklenir.
String juzzioQuoteLabel(JuzzioMessage? m, String lang) {
  String t(String tr, String en, String de) => lang == 'tr' ? tr : (lang == 'de' ? de : en);
  final kind = juzzioQuoteKind(m);
  final caption = (m?.originalText ?? '').trim();
  bool placeholder(String s) =>
      s.isEmpty || RegExp(r'^[\u{1F4F7}\u{1F3AC}\u{1F3A4}\u{1F4CE}\u{1F5BC}\u{FE0F}\s]+$', unicode: true).hasMatch(s) || s.startsWith('🎤 ');
  switch (kind) {
    case JuzzioQuoteKind.missing:
      return t('Yanıtlanan mesaj', 'Replied message', 'Beantwortete Nachricht');
    case JuzzioQuoteKind.deleted:
      return t('Bu mesaj silindi', 'This message was deleted', 'Diese Nachricht wurde gelöscht');
    case JuzzioQuoteKind.viewOnce:
      return t('Tek seferlik medya', 'View-once media', 'Einmal-Medien');
    case JuzzioQuoteKind.image:
      final base = t('Fotoğraf', 'Photo', 'Foto');
      return placeholder(caption) ? base : caption;
    case JuzzioQuoteKind.video:
      final base = t('Video', 'Video', 'Video');
      return placeholder(caption) ? base : caption;
    case JuzzioQuoteKind.voice:
      final ms = m!.audioDurationMs;
      final base = t('Sesli mesaj', 'Voice message', 'Sprachnachricht');
      if (ms <= 0) return base;
      final s = (ms / 1000).round();
      return '$base · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    case JuzzioQuoteKind.document:
      final n = (m!.documentName ?? '').trim();
      return n.isEmpty ? t('Belge', 'Document', 'Dokument') : n;
    case JuzzioQuoteKind.text:
      return caption.isEmpty ? t('Mesaj', 'Message', 'Nachricht') : caption;
  }
}

class JuzzioQuotePreview extends StatelessWidget {
  const JuzzioQuotePreview({
    super.key,
    required this.quoted,
    required this.senderLabel,
    required this.isMe,
    this.onTap,
    this.compact = false,
  });

  final JuzzioMessage? quoted;
  final String senderLabel;
  final bool isMe;
  final VoidCallback? onTap;

  /// yazma çubuğunun üstündeki "yanıtlanıyor" şeridi için
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final kind = juzzioQuoteKind(quoted);
    final label = juzzioQuoteLabel(quoted, app.uiLang);
    // giden balon koyu tonlu cam + beyaz yazı; gelen balon tema metin rengi
    final accent = isMe ? Colors.white : JuzzioGlassTokens.glowText;
    final fg = isMe ? Colors.white : JuzzioGlassTokens.textPrimary;
    final sub = isMe ? Colors.white70 : JuzzioGlassTokens.textSecondary;
    final thumb = _thumb(kind);
    final icon = switch (kind) {
      JuzzioQuoteKind.voice => Icons.mic_rounded,
      JuzzioQuoteKind.document => Icons.description_rounded,
      JuzzioQuoteKind.viewOnce => Icons.filter_1_rounded,
      JuzzioQuoteKind.deleted => Icons.block_rounded,
      _ => null,
    };
    final body = Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: (isMe ? Colors.white : JuzzioGlassTokens.textPrimary).withValues(alpha: isMe ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (senderLabel.isNotEmpty)
                  Text(senderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: sub),
                      const SizedBox(width: 4),
                    ],
                    if (kind == JuzzioQuoteKind.image && thumb != null) ...[
                      Icon(Icons.photo_rounded, size: 14, color: sub),
                      const SizedBox(width: 4),
                    ],
                    if (kind == JuzzioQuoteKind.video) ...[
                      Icon(Icons.videocam_rounded, size: 14, color: sub),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: kind == JuzzioQuoteKind.text ? fg.withValues(alpha: 0.9) : sub,
                          fontSize: 12.5,
                          fontStyle: kind == JuzzioQuoteKind.deleted ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (thumb != null) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 44, height: 44, child: thumb),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: app.trEn('Alıntılanan mesaja git', 'Go to quoted message', 'Zur zitierten Nachricht'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: body,
      ),
    );
  }

  Widget? _thumb(JuzzioQuoteKind kind) {
    final m = quoted;
    if (m == null) return null;
    if (kind == JuzzioQuoteKind.image) {
      final url = m.imageUrl!;
      if (JuzzioEncryptedMedia.isEncrypted(m.metadata)) {
        return JuzzioEncryptedImage(messageId: m.id, url: url, height: 44);
      }
      return JuzzioStorageImage(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 132,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26, child: Icon(Icons.photo_rounded, size: 20)),
      );
    }
    if (kind == JuzzioQuoteKind.video) {
      return const ColoredBox(
        color: Colors.black54,
        child: Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24)),
      );
    }
    return null;
  }
}
