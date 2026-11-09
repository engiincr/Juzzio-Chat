// =============================================================================
// JUZZIO v0.2.0 - Supabase Veri Katmanı
//  • Auth (kullanıcı adı / e-posta ile giriş, kayıt, şifre ve hesap işlemleri)
//  • Kişiye özel sohbetler: her 1'e 1 sohbet ve grup kendi odasında, yalnızca
//    katılımcılar görür (room_participants + RLS). Ortak "topluluk odası" YOKTUR.
//  • Arkadaşlık: yalnızca kabul edilmiş istekler arkadaş listesine girer.
//  • Hikâyeler: görünürlük (arkadaşlar / herkes), beğeni ve görüntüleme kaydı.
//  • Aramalar: call_logs tabanlı, yalnızca aranan kişinin telefonu çalar;
//    her sohbet kendi LiveKit odasını kullanır; konferansa kişi eklenebilir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'juzzio_e2ee.dart';
import 'juzzio_local_db.dart';
import '../core/app_theme_and_locale.dart';
import 'juzzio_beauty.dart';
import 'juzzio_time_sync.dart';
import '../core/config.dart';
import 'juzzio_features_service.dart';
import 'juzzio_media_crypto.dart';
import 'juzzio_media_cache.dart';
import 'juzzio_media_url.dart';

// -----------------------------------------------------------------------------
// MODELLER
// -----------------------------------------------------------------------------

DateTime _parseDate(dynamic raw, [DateTime? fallback]) {
  return DateTime.tryParse(raw?.toString() ?? '') ?? fallback ?? DateTime.now();
}

class JuzzioUserProfile {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String bio;
  final String preferredLang;
  final String subtitleLang;
  final String appLang;
  final bool isSilentMode;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool isPrivateAccount;
  final bool allowUnknownCalls;
  final bool isVerified;
  final String websiteUrl;
  final String musicUrl;
  final String musicVideoId;
  final int musicStartSec;
  final String musicTitle;
  final String musicArtist;
  final String musicCoverUrl;
  final bool profileZoomEnabled;
  final String cardBgColor;
  final String cardBgUrl;
  final String appRole;

  const JuzzioUserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.bio,
    required this.preferredLang,
    this.subtitleLang = 'tr',
    this.appLang = 'tr',
    this.isSilentMode = false,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.isPrivateAccount = false,
    this.allowUnknownCalls = true,
    this.isVerified = false,
    this.websiteUrl = '',
    this.musicUrl = '',
    this.musicVideoId = '',
    this.musicStartSec = 0,
    this.musicTitle = '',
    this.musicArtist = '',
    this.musicCoverUrl = '',
    this.profileZoomEnabled = true,
    this.cardBgColor = '',
    this.cardBgUrl = '',
    this.appRole = 'user',
  });

  // v0.7.0: isimle seçilen önizleme sesi (eski YouTube bağlantıları sayılmaz)
  bool get hasProfileMusic => musicUrl.trim().startsWith('https://') && !RegExp(r'youtu\.?be').hasMatch(musicUrl);

  /// Sunucu son 3 dakikada nabız aldıysa çevrimiçi (uygulama kapanınca takılı kalmaz).
  bool get isEffectivelyOnline =>
      isOnline && lastSeen != null && DateTime.now().toUtc().difference(lastSeen!.toUtc()).inMinutes < 3;

  JuzzioUserProfile copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    bool? isVerified,
    String? websiteUrl,
    String? musicUrl,
    String? musicVideoId,
    int? musicStartSec,
    String? musicTitle,
    String? musicArtist,
    String? musicCoverUrl,
    bool? profileZoomEnabled,
    String? cardBgColor,
    String? cardBgUrl,
    bool? isPrivateAccount,
  }) {
    return JuzzioUserProfile(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      email: email,
      bio: bio ?? this.bio,
      preferredLang: preferredLang,
      subtitleLang: subtitleLang,
      appLang: appLang,
      isSilentMode: isSilentMode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline,
      lastSeen: lastSeen,
      isPrivateAccount: isPrivateAccount ?? this.isPrivateAccount,
      allowUnknownCalls: allowUnknownCalls,
      isVerified: isVerified ?? this.isVerified,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      musicUrl: musicUrl ?? this.musicUrl,
      musicVideoId: musicVideoId ?? this.musicVideoId,
      musicStartSec: musicStartSec ?? this.musicStartSec,
      musicTitle: musicTitle ?? this.musicTitle,
      musicArtist: musicArtist ?? this.musicArtist,
      musicCoverUrl: musicCoverUrl ?? this.musicCoverUrl,
      profileZoomEnabled: profileZoomEnabled ?? this.profileZoomEnabled,
      cardBgColor: cardBgColor ?? this.cardBgColor,
      cardBgUrl: cardBgUrl ?? this.cardBgUrl,
      appRole: appRole,
    );
  }

  factory JuzzioUserProfile.fromMap(Map<String, dynamic> map) {
    final rawUname = (map['username'] ?? '').toString().trim();
    final cleanUname = rawUname.startsWith('@') ? rawUname.substring(1) : rawUname;
    final display = (map['display_name'] ?? '').toString().trim();
    return JuzzioUserProfile(
      id: (map['id'] ?? '').toString(),
      username: cleanUname.isNotEmpty ? cleanUname : (display.isNotEmpty ? display : 'user'),
      displayName: display.isNotEmpty ? display : (cleanUname.isNotEmpty ? cleanUname : 'Juzzio User'),
      email: (map['email'] ?? '').toString(),
      bio: (map['bio'] ?? '').toString(),
      preferredLang: (map['preferred_lang'] ?? 'tr').toString(),
      subtitleLang: (map['subtitle_lang'] ?? map['preferred_lang'] ?? 'tr').toString(),
      appLang: (map['app_lang'] ?? map['preferred_lang'] ?? 'tr').toString(),
      isSilentMode: map['is_silent_mode'] == true,
      avatarUrl: (map['avatar_url']?.toString().trim().isNotEmpty ?? false) ? map['avatar_url'].toString() : null,
      isOnline: map['is_online'] == true,
      lastSeen: DateTime.tryParse(map['last_seen']?.toString() ?? ''),
      isPrivateAccount: map['is_private_account'] == true,
      allowUnknownCalls: map['allow_unknown_calls'] != false,
      isVerified: map['is_verified'] == true,
      websiteUrl: (map['website_url'] ?? '').toString(),
      musicUrl: (map['music_url'] ?? '').toString(),
      musicVideoId: (map['music_video_id'] ?? '').toString(),
      musicStartSec: (map['music_start_sec'] as num?)?.toInt() ?? 0,
      musicTitle: (map['music_title'] ?? '').toString(),
      musicArtist: (map['music_artist'] ?? '').toString(),
      musicCoverUrl: (map['music_cover_url'] ?? '').toString(),
      profileZoomEnabled: map['profile_zoom_enabled'] != false,
      cardBgColor: (map['card_bg_color'] ?? '').toString(),
      cardBgUrl: (map['card_bg_url'] ?? '').toString(),
      appRole: (map['app_role'] ?? 'user').toString(),
    );
  }

  String formattedPresence({bool isTr = true}) {
    final app = JuzzioAppController.instance;
    if (!app.canViewOthersLastSeenAndOnline) {
      return app.trEn('Son görülme gizli', 'Last seen hidden', 'Zuletzt online verborgen');
    }
    if (lastSeen == null) return '';
    final seen = lastSeen!.toLocal();
    final diff = DateTime.now().difference(seen);
    if (isEffectivelyOnline) {
      return app.trEn('Çevrimiçi', 'Online', 'Online');
    }
    if (diff.inMinutes < 1) {
      return app.trEn('Az önce görüldü', 'Seen just now', 'Gerade eben gesehen');
    }
    if (diff.inMinutes < 60) {
      return app.trEn('${diff.inMinutes} dk önce görüldü', 'Seen ${diff.inMinutes} min ago', 'Vor ${diff.inMinutes} Min.');
    }
    if (diff.inHours < 24) {
      return app.trEn('${diff.inHours} sa önce görüldü', 'Seen ${diff.inHours} h ago', 'Vor ${diff.inHours} Std.');
    }
    return app.trEn('${diff.inDays} gün önce görüldü', 'Seen ${diff.inDays} d ago', 'Vor ${diff.inDays} T.');
  }
}

class JuzzioMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String? receiverId;
  final String messageType;
  final String sourceLang;
  final String targetLang;
  final String originalText;
  final String translatedText;
  final String? audioUrl;
  final String? imageUrl;
  final String? videoUrl;
  final String? documentUrl;
  final String? documentName;
  final int documentSize;
  final String? storyId;
  final String? replyToId;
  final Map<String, dynamic>? storyReplyMeta;
  final Map<String, dynamic> metadata;
  final int audioDurationMs;
  final List<double> waveformPeaks;
  final Map<String, String> reactions;
  final bool isPinned;
  final bool isDeleted;
  /// v0.9.5: tek seferlik medya
  final bool isViewOnce;
  final DateTime? viewOnceOpenedAt;
  final DateTime? editedAt;
  final DateTime createdAt;

  /// v1.0.0: istemci gönderim kimliği (anında görünen yerel balonu sunucu kaydıyla eşler)
  final String? clientMsgId;

  const JuzzioMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    this.senderName = '',
    this.receiverId,
    required this.messageType,
    required this.sourceLang,
    required this.targetLang,
    required this.originalText,
    required this.translatedText,
    this.audioUrl,
    this.imageUrl,
    this.videoUrl,
    this.documentUrl,
    this.documentName,
    this.documentSize = 0,
    this.storyId,
    this.replyToId,
    this.storyReplyMeta,
    this.metadata = const {},
    this.audioDurationMs = 0,
    this.waveformPeaks = const [],
    this.reactions = const {},
    this.isPinned = false,
    this.isDeleted = false,
    this.isViewOnce = false,
    this.viewOnceOpenedAt,
    this.editedAt,
    required this.createdAt,
    this.clientMsgId,
  });

  /// v1.0.0: henüz sunucuya ulaşmamış yerel (anında gösterilen) mesaj
  bool get isLocalPending => metadata['local_pending'] == true;

  /// v0.7.0: uçtan uca şifreli mesaj — cihazda çözülen metinle kopya
  bool get isEncrypted => metadata['e2ee'] is Map;

  JuzzioMessage withText(String original, String translated) => JuzzioMessage(
        id: id,
        roomId: roomId,
        senderId: senderId,
        senderName: senderName,
        receiverId: receiverId,
        messageType: messageType,
        sourceLang: sourceLang,
        targetLang: targetLang,
        originalText: original,
        translatedText: translated,
        audioUrl: audioUrl,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        documentUrl: documentUrl,
        documentName: documentName,
        documentSize: documentSize,
        storyId: storyId,
        replyToId: replyToId,
        storyReplyMeta: storyReplyMeta,
        metadata: metadata,
        audioDurationMs: audioDurationMs,
        waveformPeaks: waveformPeaks,
        reactions: reactions,
        isPinned: isPinned,
        isDeleted: isDeleted,
        isViewOnce: isViewOnce,
        viewOnceOpenedAt: viewOnceOpenedAt,
        editedAt: editedAt,
        createdAt: createdAt,
        clientMsgId: clientMsgId,
      );

  factory JuzzioMessage.fromMap(Map<String, dynamic> map) {
    final rawPeaks = map['waveform_peaks'];
    List<double> parsedPeaks = [];
    if (rawPeaks is List) {
      parsedPeaks = rawPeaks.whereType<num>().map((e) => e.toDouble()).toList();
    } else if (rawPeaks is String && rawPeaks.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPeaks);
        if (decoded is List) {
          parsedPeaks = decoded.whereType<num>().map((e) => e.toDouble()).toList();
        }
      } catch (_) {}
    }

    final Map<String, String> parsedReactions = {};
    dynamic rawReactions = map['reactions'];
    if (rawReactions is String && rawReactions.isNotEmpty) {
      try {
        rawReactions = jsonDecode(rawReactions);
      } catch (_) {}
    }
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          parsedReactions[key.toString()] = value.toString();
        }
      });
    }

    Map<String, dynamic> metadata = {};
    final rawMeta = map['metadata'];
    if (rawMeta is Map) {
      metadata = Map<String, dynamic>.from(rawMeta);
    }

    // Hikâye yanıtı meta verisi: yeni sürüm metadata['story'], eski sürüm audio_url içinde base64.
    String? rawAudioUrl = map['audio_url']?.toString();
    Map<String, dynamic>? storyMeta;
    if (metadata['story'] is Map) {
      storyMeta = Map<String, dynamic>.from(metadata['story'] as Map);
    }
    if (rawAudioUrl != null && rawAudioUrl.startsWith('juzzio-story://')) {
      try {
        final b64 = rawAudioUrl.substring('juzzio-story://'.length);
        final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(b64))));
        if (decoded is Map) {
          storyMeta ??= Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      rawAudioUrl = null;
    }

    String? nonEmpty(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return JuzzioMessage(
      id: map['id'].toString(),
      roomId: map['room_id'].toString(),
      senderId: map['sender_id'].toString(),
      senderName: (map['sender_name'] ?? storyMeta?['replierName'] ?? '').toString(),
      receiverId: nonEmpty(map['receiver_id']),
      messageType: (map['message_type'] ?? 'text').toString(),
      sourceLang: (map['source_lang'] ?? 'auto').toString(),
      targetLang: (map['target_lang'] ?? 'tr').toString(),
      originalText: (map['original_text'] ?? '').toString(),
      // v0.9.3: eski kayıtlarda çeviri yerine saklanmış servis hata metni gösterilmez (yeniden çevrilir)
      translatedText: isTranslationProviderError((map['translated_text'] ?? '').toString()) ? '' : (map['translated_text'] ?? '').toString(),
      audioUrl: nonEmpty(rawAudioUrl),
      imageUrl: nonEmpty(map['image_url']) ?? nonEmpty(storyMeta?['replyImageUrl']),
      videoUrl: nonEmpty(map['video_url']),
      documentUrl: nonEmpty(map['document_url']),
      documentName: nonEmpty(map['document_name']),
      documentSize: int.tryParse('${map['document_size'] ?? 0}') ?? 0,
      storyId: nonEmpty(map['story_id']) ?? nonEmpty(storyMeta?['storyId']),
      replyToId: nonEmpty(map['reply_to_id']),
      storyReplyMeta: storyMeta,
      metadata: metadata,
      audioDurationMs: (map['audio_duration_ms'] as num?)?.toInt() ?? 0,
      waveformPeaks: parsedPeaks,
      reactions: parsedReactions,
      isPinned: map['is_pinned'] == true,
      isDeleted: map['is_deleted'] == true,
      isViewOnce: map['is_view_once'] == true,
      viewOnceOpenedAt: DateTime.tryParse('${map['view_once_opened_at'] ?? ''}'),
      editedAt: DateTime.tryParse(map['edited_at']?.toString() ?? ''),
      createdAt: _parseDate(map['created_at']),
      clientMsgId: nonEmpty(map['client_msg_id']),
    );
  }
}

class JuzzioFriendship {
  final String id;
  final String requesterId;
  final String requesterUsername;
  final String requesterName;
  final String? requesterAvatar;
  final String receiverId;
  final String receiverUsername;
  final String receiverName;
  final String? receiverAvatar;
  final String status;
  final DateTime createdAt;

  const JuzzioFriendship({
    required this.id,
    required this.requesterId,
    required this.requesterUsername,
    required this.requesterName,
    this.requesterAvatar,
    required this.receiverId,
    required this.receiverUsername,
    required this.receiverName,
    this.receiverAvatar,
    required this.status,
    required this.createdAt,
  });

  String otherUserId(String myUid) => requesterId == myUid ? receiverId : requesterId;

  factory JuzzioFriendship.fromMap(Map<String, dynamic> map) {
    final reqName = (map['requester_name'] ?? '').toString();
    final recName = (map['receiver_name'] ?? '').toString();
    return JuzzioFriendship(
      id: (map['id'] ?? '').toString(),
      requesterId: (map['requester_id'] ?? '').toString(),
      requesterUsername: (map['requester_username'] ?? '').toString(),
      requesterName: reqName.isNotEmpty ? reqName : 'Juzzio',
      requesterAvatar: map['requester_avatar']?.toString(),
      receiverId: (map['receiver_id'] ?? '').toString(),
      receiverUsername: (map['receiver_username'] ?? '').toString(),
      receiverName: recName.isNotEmpty ? recName : 'Juzzio',
      receiverAvatar: map['receiver_avatar']?.toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: _parseDate(map['created_at']),
    );
  }
}

class JuzzioStory {
  final String id;
  final String userId;
  final String username;
  final String displayName;
  final String? userAvatar;
  final String mediaType; // 'image' | 'video' | 'text'
  final String? mediaUrl;
  final int videoDurationSec;
  final String filterPreset;
  final String bgColorHex;
  final String captionOriginal;
  final String captionTranslated;
  final String overlayTextOriginal;
  final String overlayTextTranslated;
  final String sourceLang;
  final String visibility; // 'friends' | 'everyone' | 'followers' | 'private'
  final int likesCount;
  final int viewsCount;
  /// Eski sürümle uyumluluk için tutulur (beğeniler artık story_views tablosundadır).
  final List<String> likes;
  final DateTime expiresAt;
  final DateTime createdAt;
  // v0.4.0 içerik stüdyosu: kırpma, hız, ses, müzik ve yazı stili
  final int trimStartMs;
  final int trimEndMs;
  final double playbackSpeed;
  final bool isMuted;
  final String musicUrl;
  final String musicTitle;
  final int musicStartSec;
  final String overlayStyle;
  final String overlayColor;
  // v0.5 hikâye stüdyosu: emoji çıkartmaları (x/y 0..1 oransal konum, scale çarpanı)
  final List<JuzzioStorySticker> stickers;
  /// v0.9.3: Admin → Juzzio Story panelinden paylaşılan "Juzzio Official" hikâyesi
  final bool isOfficial;

  const JuzzioStory({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    this.userAvatar,
    required this.mediaType,
    this.mediaUrl,
    this.videoDurationSec = 15,
    this.filterPreset = 'none',
    this.bgColorHex = '#161618',
    required this.captionOriginal,
    required this.captionTranslated,
    this.overlayTextOriginal = '',
    this.overlayTextTranslated = '',
    this.sourceLang = 'tr',
    this.visibility = 'friends',
    this.likesCount = 0,
    this.viewsCount = 0,
    this.likes = const [],
    required this.expiresAt,
    required this.createdAt,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.playbackSpeed = 1.0,
    this.isMuted = false,
    this.musicUrl = '',
    this.musicTitle = '',
    this.musicStartSec = 0,
    this.overlayStyle = 'classic',
    this.overlayColor = '#FFFFFF',
    this.stickers = const <JuzzioStorySticker>[],
    this.isOfficial = false,
  });

  bool get hasTrim => trimEndMs > trimStartMs && trimEndMs > 0;

  // v0.9.4: sunucu saatine göre (cihaz saati değiştirilse de doğru)
  bool get isExpired => JuzzioClock.nowUtc().isAfter(expiresAt.toUtc());

  factory JuzzioStory.fromMap(Map<String, dynamic> map) {
    final created = _parseDate(map['created_at']);
    final expires = DateTime.tryParse(map['expires_at']?.toString() ?? '') ?? created.add(const Duration(hours: 24));
    return JuzzioStory(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      displayName: (map['display_name'] ?? map['username'] ?? 'Juzzio').toString(),
      userAvatar: map['user_avatar']?.toString(),
      mediaType: (map['media_type'] ?? 'image').toString(),
      mediaUrl: map['media_url']?.toString(),
      videoDurationSec: (map['video_duration_sec'] as num?)?.toInt() ?? 15,
      filterPreset: (map['filter_preset'] ?? 'none').toString(),
      bgColorHex: (map['bg_color_hex'] ?? '#161618').toString(),
      captionOriginal: (map['caption_original'] ?? '').toString(),
      captionTranslated: (map['caption_translated'] ?? '').toString(),
      overlayTextOriginal: (map['overlay_text_original'] ?? '').toString(),
      overlayTextTranslated: (map['overlay_text_translated'] ?? '').toString(),
      sourceLang: (map['source_lang'] ?? 'tr').toString(),
      visibility: (map['visibility'] ?? 'friends').toString(),
      likesCount: (map['likes_count'] as num?)?.toInt() ?? 0,
      viewsCount: (map['views_count'] as num?)?.toInt() ?? 0,
      expiresAt: expires,
      createdAt: created,
      trimStartMs: (map['trim_start_ms'] as num?)?.toInt() ?? 0,
      trimEndMs: (map['trim_end_ms'] as num?)?.toInt() ?? 0,
      playbackSpeed: (map['playback_speed'] is num)
          ? (map['playback_speed'] as num).toDouble()
          : double.tryParse(map['playback_speed']?.toString() ?? '') ?? 1.0,
      isMuted: map['is_muted'] == true,
      musicUrl: (map['music_url'] ?? '').toString(),
      musicTitle: (map['music_title'] ?? '').toString(),
      musicStartSec: (map['music_start_sec'] as num?)?.toInt() ?? 0,
      overlayStyle: (map['overlay_style'] ?? 'classic').toString(),
      overlayColor: (map['overlay_color'] ?? '#FFFFFF').toString(),
      stickers: JuzzioStorySticker.listFrom(map['stickers_json']),
      isOfficial: map['is_official'] == true,
    );
  }
}

/// Hikâye üzerindeki emoji çıkartması (stories.stickers_json öğesi).
class JuzzioStorySticker {
  final String emoji;
  final double x;
  final double y;
  final double scale;

  const JuzzioStorySticker({required this.emoji, this.x = 0.5, this.y = 0.5, this.scale = 1.0});

  JuzzioStorySticker copyWith({double? x, double? y, double? scale}) =>
      JuzzioStorySticker(emoji: emoji, x: x ?? this.x, y: y ?? this.y, scale: scale ?? this.scale);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': 'emoji',
        'emoji': emoji,
        'x': double.parse(x.clamp(0.0, 1.0).toStringAsFixed(4)),
        'y': double.parse(y.clamp(0.0, 1.0).toStringAsFixed(4)),
        'scale': double.parse(scale.clamp(0.4, 4.0).toStringAsFixed(3)),
      };

  static double _num(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static List<JuzzioStorySticker> listFrom(Object? raw) {
    Object? data = raw;
    if (data is String && data.trim().isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return const <JuzzioStorySticker>[];
      }
    }
    if (data is! List) return const <JuzzioStorySticker>[];
    final out = <JuzzioStorySticker>[];
    for (final item in data) {
      if (item is! Map) continue;
      final emoji = (item['emoji'] ?? '').toString();
      if (emoji.isEmpty || emoji.length > 32) continue;
      out.add(JuzzioStorySticker(
        emoji: emoji,
        x: _num(item['x'], 0.5).clamp(0.0, 1.0),
        y: _num(item['y'], 0.5).clamp(0.0, 1.0),
        scale: _num(item['scale'], 1.0).clamp(0.4, 4.0),
      ));
      if (out.length >= 20) break;
    }
    return out;
  }
}

class JuzzioCallLog {
  final String id;
  final String? sessionId;
  final String? roomId;
  final String? livekitRoomName;
  final bool isGroup;
  final String groupTitle;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String? receiverId;
  final String receiverName;
  final String? receiverAvatar;
  final bool isVideo;
  final String status;
  final String statusReason;
  final int durationSec;
  final int dataKb;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final String? endedBy;

  const JuzzioCallLog({
    required this.id,
    this.sessionId,
    this.roomId,
    this.livekitRoomName,
    this.isGroup = false,
    this.groupTitle = '',
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    required this.isVideo,
    required this.status,
    required this.statusReason,
    required this.durationSec,
    required this.dataKb,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.endedBy,
  });

  bool get wasAnswered => status == 'answered' || answeredAt != null;
  bool get isRinging => status == 'ringing';
  bool get isMissedLike => status == 'missed' || status == 'busy_silent' || status == 'rejected' || status == 'cancelled';

  factory JuzzioCallLog.fromMap(Map<String, dynamic> map) {
    return JuzzioCallLog(
      id: (map['id'] ?? '').toString(),
      sessionId: map['session_id']?.toString(),
      roomId: map['room_id']?.toString(),
      livekitRoomName: map['livekit_room_name']?.toString(),
      isGroup: map['is_group'] == true,
      groupTitle: (map['group_title'] ?? '').toString(),
      callerId: (map['caller_id'] ?? '').toString(),
      callerName: (map['caller_name'] ?? 'Juzzio').toString(),
      callerAvatar: map['caller_avatar']?.toString(),
      receiverId: map['receiver_id']?.toString(),
      receiverName: (map['receiver_name'] ?? '').toString(),
      receiverAvatar: map['receiver_avatar']?.toString(),
      isVideo: map['is_video'] == true,
      status: (map['status'] ?? 'answered').toString(),
      statusReason: (map['status_reason'] ?? '').toString(),
      durationSec: (map['duration_sec'] as num?)?.toInt() ?? 0,
      dataKb: (map['data_kb'] as num?)?.toInt() ?? 0,
      createdAt: _parseDate(map['created_at']),
      answeredAt: map['answered_at'] == null ? null : DateTime.tryParse(map['answered_at'].toString()),
      endedAt: map['ended_at'] == null ? null : DateTime.tryParse(map['ended_at'].toString()),
      endedBy: map['ended_by']?.toString(),
    );
  }
}

class JuzzioGroupRoom {
  final String id;
  final String roomCode;
  final String title;
  final String livekitRoomName;
  final bool isGroup;
  final String disappearingTimer;
  final List<String> groupMembers;
  final List<String> groupMemberIds;
  final String? createdBy;
  final bool isCallActive;
  final Map<String, dynamic>? activeCall;

  const JuzzioGroupRoom({
    required this.id,
    required this.roomCode,
    required this.title,
    required this.livekitRoomName,
    this.isGroup = true,
    this.disappearingTimer = 'off',
    this.groupMembers = const [],
    this.groupMemberIds = const [],
    this.createdBy,
    this.isCallActive = false,
    this.activeCall,
  });

  bool isUserMember(String? userId, String? displayName) {
    if (userId == null || userId.isEmpty) return false;
    return createdBy == userId || groupMemberIds.contains(userId);
  }

  static List<String> _parseStringList(dynamic raw) {
    dynamic value = raw;
    if (value is String && value.isNotEmpty) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is List) {
      return value.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    return const [];
  }

  factory JuzzioGroupRoom.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parsedCall;
    if (map['active_call'] is Map) {
      parsedCall = Map<String, dynamic>.from(map['active_call'] as Map);
    }
    return JuzzioGroupRoom(
      id: (map['id'] ?? map['room_id'] ?? '').toString(),
      roomCode: (map['room_code'] ?? '').toString(),
      title: (map['title'] ?? JuzzioAppController.instance.trEn('Grup', 'Group', 'Gruppe')).toString(),
      livekitRoomName: (map['livekit_room_name'] ?? '').toString(),
      isGroup: map['is_group'] == true,
      disappearingTimer: (map['disappearing_timer'] ?? 'off').toString(),
      groupMembers: _parseStringList(map['group_members'] ?? map['member_names']),
      groupMemberIds: _parseStringList(map['group_member_ids'] ?? map['member_ids']),
      createdBy: map['created_by']?.toString(),
      isCallActive: map['is_call_active'] == true,
      activeCall: parsedCall,
    );
  }
}

/// get_my_conversations() RPC satırı: yalnızca kullanıcının üyesi olduğu sohbetler.
class JuzzioConversation {
  final String roomId;
  final String title;
  final bool isGroup;
  final String livekitRoomName;
  final String disappearingTimer;
  final String? avatarUrl;
  final String? partnerId;
  final String? partnerUsername;
  final String? partnerDisplayName;
  final String? partnerAvatarUrl;
  final String partnerLang;
  final bool partnerIsOnline;
  final DateTime? partnerLastSeen;
  final List<String> memberIds;
  final List<String> memberNames;
  final DateTime? lastMessageAt;
  final String? lastMessageSender;
  final String? lastMessageType;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isCallActive;
  final Map<String, dynamic>? activeCall;
  final String? createdBy;
  /// Karşı tarafın bu sohbeti en son okuduğu an (okundu bilgisi kapalıysa null)
  final DateTime? partnerLastReadAt;
  /// Gruptaki rolüm: owner (yönetici) | moderator | member
  final String myRole;
  final DateTime? myMutedUntil;
  final String groupType;
  final String groupPurpose;
  final String description;
  final bool partnerIsVerified;
  /// Gizli hesaba arkadaş olmayan birinden gelen sohbet (Mesaj istekleri)
  final bool isMessageRequest;

  bool get isGroupOwner => isGroup && myRole == 'owner';
  bool get isGroupStaff => isGroup && (myRole == 'owner' || myRole == 'moderator');
  bool get isMutedByModerator => myMutedUntil != null && myMutedUntil!.isAfter(DateTime.now());

  const JuzzioConversation({
    required this.roomId,
    required this.title,
    required this.isGroup,
    required this.livekitRoomName,
    this.disappearingTimer = 'off',
    this.avatarUrl,
    this.partnerId,
    this.partnerUsername,
    this.partnerDisplayName,
    this.partnerAvatarUrl,
    this.partnerLang = 'tr',
    this.partnerIsOnline = false,
    this.partnerLastSeen,
    this.memberIds = const [],
    this.memberNames = const [],
    this.lastMessageAt,
    this.lastMessageSender,
    this.lastMessageType,
    this.lastMessagePreview,
    this.unreadCount = 0,
    this.isMuted = false,
    this.isPinned = false,
    this.isCallActive = false,
    this.activeCall,
    this.createdBy,
    this.partnerLastReadAt,
    this.myRole = 'member',
    this.myMutedUntil,
    this.groupType = 'general',
    this.groupPurpose = '',
    this.description = '',
    this.partnerIsVerified = false,
    this.isMessageRequest = false,
  });

  factory JuzzioConversation.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? call;
    if (map['active_call'] is Map) call = Map<String, dynamic>.from(map['active_call'] as Map);
    return JuzzioConversation(
      roomId: (map['room_id'] ?? '').toString(),
      title: (map['title'] ?? 'Juzzio').toString(),
      isGroup: map['is_group'] == true,
      livekitRoomName: (map['livekit_room_name'] ?? '').toString(),
      disappearingTimer: (map['disappearing_timer'] ?? 'off').toString(),
      avatarUrl: map['avatar_url']?.toString(),
      partnerId: map['partner_id']?.toString(),
      partnerUsername: map['partner_username']?.toString(),
      partnerDisplayName: map['partner_display_name']?.toString(),
      partnerAvatarUrl: map['partner_avatar_url']?.toString(),
      partnerLang: (map['partner_lang'] ?? 'tr').toString(),
      partnerIsOnline: map['partner_is_online'] == true,
      partnerLastSeen: DateTime.tryParse(map['partner_last_seen']?.toString() ?? ''),
      memberIds: JuzzioGroupRoom._parseStringList(map['member_ids']),
      memberNames: JuzzioGroupRoom._parseStringList(map['member_names']),
      lastMessageAt: DateTime.tryParse(map['last_message_at']?.toString() ?? ''),
      lastMessageSender: map['last_message_sender']?.toString(),
      lastMessageType: map['last_message_type']?.toString(),
      lastMessagePreview: map['last_message_preview']?.toString(),
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
      isMuted: map['is_muted'] == true,
      isPinned: map['is_pinned'] == true,
      isCallActive: map['is_call_active'] == true,
      activeCall: call,
      createdBy: map['created_by']?.toString(),
      partnerLastReadAt: DateTime.tryParse(map['partner_last_read_at']?.toString() ?? ''),
      myRole: (map['my_role'] ?? 'member').toString(),
      myMutedUntil: DateTime.tryParse(map['my_muted_until']?.toString() ?? ''),
      groupType: (map['group_type'] ?? 'general').toString(),
      groupPurpose: (map['group_purpose'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      partnerIsVerified: map['partner_is_verified'] == true,
      isMessageRequest: map['is_message_request'] == true,
    );
  }

  JuzzioGroupRoom toGroupRoom() => JuzzioGroupRoom(
        id: roomId,
        roomCode: '',
        title: title,
        livekitRoomName: livekitRoomName,
        isGroup: isGroup,
        disappearingTimer: disappearingTimer,
        groupMembers: memberNames,
        groupMemberIds: memberIds,
        createdBy: createdBy,
        isCallActive: isCallActive,
        activeCall: activeCall,
      );

  JuzzioUserProfile? toPartnerProfile() {
    if (isGroup || partnerId == null) return null;
    return JuzzioUserProfile(
      id: partnerId!,
      username: partnerUsername ?? '',
      displayName: (partnerDisplayName?.isNotEmpty ?? false) ? partnerDisplayName! : (partnerUsername ?? title),
      email: '',
      bio: '',
      preferredLang: partnerLang,
      avatarUrl: partnerAvatarUrl,
      isOnline: partnerIsOnline,
      lastSeen: partnerLastSeen,
    );
  }
}

/// start_call() RPC sonucu
class JuzzioCallSession {
  final String sessionId;
  final String roomId;
  final String livekitRoomName;
  final bool isGroupCall;
  final bool joinedExisting;

  const JuzzioCallSession({
    required this.sessionId,
    required this.roomId,
    required this.livekitRoomName,
    required this.isGroupCall,
    this.joinedExisting = false,
  });

  factory JuzzioCallSession.fromMap(Map<String, dynamic> map, {String? fallbackRoomId}) {
    return JuzzioCallSession(
      sessionId: (map['session_id'] ?? '').toString(),
      roomId: (map['room_id'] ?? fallbackRoomId ?? '').toString(),
      livekitRoomName: (map['livekit_room'] ?? '').toString(),
      isGroupCall: map['is_group_call'] == true,
      joinedExisting: map['joined_existing'] == true,
    );
  }
}

class JuzzioLiveKitAccess {
  final String token;
  final String url;
  const JuzzioLiveKitAccess({required this.token, required this.url});
}

/// Kullanıcıya gösterilebilir, Türkçe/İngilizce hata
class JuzzioServiceException implements Exception {
  final String message;
  const JuzzioServiceException(this.message);
  @override
  String toString() => message;
}

// -----------------------------------------------------------------------------
// SERVİS
// -----------------------------------------------------------------------------

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  final http.Client _httpClient = http.Client();
  final Map<String, String> _translationCache = {};

  String? get currentUserId => client.auth.currentUser?.id;

  JuzzioAppController get _app => JuzzioAppController.instance;

  /// Sunucu hata kodlarını kullanıcının dilinde anlaşılır mesaja çevirir.
  /// (Ham İngilizce/Türkçe hata metni asla arayüze düşmez.)
  String friendlyError(Object e) {
    String raw;
    String code = '';
    if (e is PostgrestException) {
      raw = '${e.code ?? ''} ${e.message} ${e.details ?? ''}';
      code = e.code ?? '';
    } else if (e is AuthException) {
      raw = '${e.code ?? ''} ${e.message}';
      code = e.code ?? e.statusCode ?? '';
    } else if (e is JuzzioServiceException) {
      return e.message;
    } else if (e is JuzzioE2eeRequiredException) {
      // v0.9.0: şifreleme yapılamadı → mesaj GÖNDERİLMEDİ (düz metne düşülmez)
      if (e.status == JuzzioE2eeStatus.peerKeyMissing) {
        return _app.trEn('Bu kişinin uygulaması uçtan uca şifrelemeyi henüz desteklemiyor. Mesaj gönderilmedi.',
            'This person\'s app does not support end-to-end encryption yet. The message was not sent.',
            'Die App dieser Person unterstützt noch keine Ende-zu-Ende-Verschlüsselung. Die Nachricht wurde nicht gesendet.');
      }
      return _app.trEn('Mesaj uçtan uca şifrelenemedi ve güvenlik için gönderilmedi. Bağlantınızı kontrol edip tekrar deneyin.',
          'The message could not be end-to-end encrypted and was not sent for your security. Check your connection and try again.',
          'Die Nachricht konnte nicht Ende-zu-Ende-verschlüsselt werden und wurde zu deiner Sicherheit nicht gesendet. Prüfe deine Verbindung und versuche es erneut.');
    } else {
      raw = e.toString();
    }
    // v0.6 içerik denetimi hataları
    if (raw.contains('avatar_not_moderated') || raw.contains('inappropriate_image')) {
      return _app.trEn('Bu fotoğraf içerik denetiminden geçmedi. Lütfen başka bir fotoğraf seçin.',
          'This photo did not pass content review. Please choose another photo.',
          'Dieses Foto hat die Inhaltsprüfung nicht bestanden. Bitte wähle ein anderes Foto.');
    }
    if (raw.contains('release_reason_required')) {
      return _app.trEn('Güncellemenin neden getirildiğini (Türkçe gerekçe) yazmak zorunludur.',
          'A Turkish reason explaining why this update is released is required.',
          'Eine türkische Begründung für dieses Update ist erforderlich.');
    }
    if (raw.contains('feature_disabled')) {
      return _app.trEn('Bu özellik yönetici tarafından geçici olarak kapatıldı.',
          'This feature has been temporarily turned off by the administrator.',
          'Diese Funktion wurde vom Administrator vorübergehend deaktiviert.');
    }
    if (raw.contains('signup_blocked')) {
      return _app.trEn('Bu cihazdan veya bu e-posta adresiyle yeni hesap açılamaz (kalıcı engel).',
          'A new account cannot be created from this device or with this email (permanent ban).',
          'Von diesem Gerät oder mit dieser E-Mail kann kein neues Konto erstellt werden (dauerhafte Sperre).');
    }
    const codeToKey = <String, String>{
      'call_full': 'err_call_full',
      'account_banned': 'err_banned',
      'inappropriate_content': 'err_inappropriate',
      'group_purpose_required': 'err_group_purpose',
      'title_required': 'err_group_title',
      'username_reserved': 'err_username_reserved',
      'invalid_username': 'err_username_invalid',
      'invalid_website': 'err_website_invalid',
      'invalid_music_url': 'err_music_invalid',
      'not_friends': 'err_not_friends',
      'you_have_chick': 'err_you_have_chick',
      'friend_has_chick': 'err_friend_has_chick',
      'already_has_chick': 'err_friend_has_chick',
      'invite_pending': 'err_invite_pending',
      'invite_not_found': 'err_invite_gone',
      'no_chick': 'err_no_chick',
      'too_many_attempts': 'err_admin_locked',
      'admin_session_invalid': 'err_admin_session',
      'admin_password_not_set': 'err_admin_not_set',
      'call_not_ringing': 'err_call_ended',
      'not_in_call': 'err_call_ended',
      'cannot_change_self': 'err_not_allowed',
      'cannot_remove_self': 'err_not_allowed',
      'cannot_ban_admin': 'err_not_allowed',
      'no_callable_participants': 'err_no_callable',
      'blocked': 'err_blocked',
      'not_authenticated': 'err_session',
      'JWT': 'err_session',
      'invalid_credentials': 'err_login_failed',
      'Invalid login credentials': 'err_login_failed',
      'email_not_confirmed': 'err_email_not_confirmed',
      'Email not confirmed': 'err_email_not_confirmed',
      'rate_limited': 'err_rate_limited',
      'over_email_send_rate_limit': 'err_rate_limited',
      'over_request_rate_limit': 'err_rate_limited',
      'rate limit': 'err_rate_limited',
      'Invalid API key': 'err_api_key',
      'No API key found': 'err_api_key',
      'user_already_exists': 'err_email_taken',
      'email_exists': 'err_email_taken',
      'User already registered': 'err_email_taken',
      'weak_password': 'err_password_short',
      'Password should be': 'err_password_short',
      'signup_disabled': 'err_signup_disabled',
      'Signups not allowed': 'err_signup_disabled',
      'email_address_invalid': 'err_email_invalid',
      'Unable to validate email': 'err_email_invalid',
      'unexpected_failure': 'err_register_failed',
      'Database error saving new user': 'err_register_failed',
      'not_a_member': 'err_not_allowed',
      'not_allowed': 'err_not_allowed',
      'row-level security': 'err_not_allowed',
      'permission denied': 'err_not_allowed',
      'SocketException': 'err_offline',
      'Failed host lookup': 'err_offline',
      'ClientException': 'err_offline',
      'TimeoutException': 'err_offline',
    };
    // v0.9.4: anket / etkinlik / civciv gardırobu hata kodları anlaşılır metne çevrilir
    final featureMsg = <String, String>{
      'poll_group_only': _app.trEn('Anket yalnızca grup sohbetlerinde oluşturulabilir.', 'Polls can only be created in group chats.', 'Umfragen gibt es nur in Gruppenchats.'),
      'poll_options_invalid': _app.trEn('Anket 2 ile 10 arasında seçenek içermeli.', 'A poll needs 2 to 10 options.', 'Eine Umfrage braucht 2 bis 10 Optionen.'),
      'poll_options_duplicate': _app.trEn('Aynı seçenek iki kez yazılmış.', 'An option is duplicated.', 'Eine Option ist doppelt.'),
      'poll_closed': _app.trEn('Bu anket kapandı.', 'This poll is closed.', 'Diese Umfrage ist geschlossen.'),
      'poll_single_choice': _app.trEn('Bu ankette yalnız bir seçenek seçilebilir.', 'Only one option can be chosen.', 'Nur eine Option wählbar.'),
      'event_group_only': _app.trEn('Etkinlik yalnızca grup sohbetlerinde planlanabilir.', 'Events can only be planned in group chats.', 'Termine gibt es nur in Gruppenchats.'),
      'event_in_past': _app.trEn('Etkinlik zamanı geçmişte olamaz.', 'The event time cannot be in the past.', 'Der Termin darf nicht in der Vergangenheit liegen.'),
      'chick_not_enough_coins': _app.trEn('Yeterli jetonunuz yok. Civcivi besleyerek jeton kazanın.', 'Not enough coins. Feed your chick to earn coins.', 'Nicht genug Münzen. Füttere dein Küken.'),
      'chick_stage_too_low': _app.trEn('Bu aksesuar için civcivin biraz daha büyümesi gerekiyor.', 'Your chick needs to grow a bit more for this item.', 'Dein Küken muss dafür noch wachsen.'),
      'low_trust_limited': _app.trEn('Hesabın hakkında yakın zamanda şikâyet olduğu için bugün daha fazla gönderi paylaşamazsın.', 'Due to recent reports you cannot post more today.', 'Wegen Meldungen heute keine weiteren Beiträge.'),
      'view_once_already_opened': _app.trEn('Bu medya zaten açıldı.', 'This media was already opened.', 'Bereits geöffnet.'),
      'watch_party_invalid_url': _app.trEn('Geçerli bir https:// bağlantısı girin.', 'Enter a valid https:// link.', 'Gültigen https://-Link eingeben.'),
      'safety_invalid_duration': _app.trEn('Süre 5 dakika ile 12 saat arasında olmalı.', 'Duration must be between 5 minutes and 12 hours.', 'Dauer 5 Min.–12 Std.'),
      'poll_deadline_past': _app.trEn('Bitiş zamanı gelecekte olmalı.', 'The deadline must be in the future.', 'Frist muss in der Zukunft liegen.'),
      'qa_invalid_text': _app.trEn('Metin 1-500 karakter olmalı.', 'Text must be 1-500 characters.', 'Text 1–500 Zeichen.'),
      'accessory_not_owned': _app.trEn('Önce bu aksesuarı satın alın.', 'Buy this item first.', 'Kaufe diesen Artikel zuerst.'),
    };
    for (final entry in featureMsg.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }
    for (final entry in codeToKey.entries) {
      if (raw.contains(entry.key)) return _app.t(entry.value);
    }
    if (e is AuthException && e.statusCode == '401') return _app.t('err_api_key');
    // Tanınmayan hata: sorunun bulunabilmesi için kısa teknik kod eklenir.
    final tech = code.trim().isNotEmpty ? code.trim() : e.runtimeType.toString();
    return '${_app.t('err_generic')} ($tech)';
  }

  // Geriye dönük uyumluluk (eski çağrılar)
  String _friendlyError(Object e) => friendlyError(e);

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------
  // Kullanıcı adıyla giriş, e-postayı açığa çıkarmamak için sunucuda
  // (auth-username-login Edge Function) çözülür; istemci e-posta sorgulamaz.

  static final RegExp _usernamePattern = RegExp(r'^[a-zA-Z0-9_.]{3,30}$');

  Future<Map<String, dynamic>> registerAccount({
    required String username,
    required String email,
    required String password,
    String preferredLang = 'tr',
    String? displayName,
    String gender = 'unspecified',
  }) async {
    var cleanUsername = username.trim();
    if (cleanUsername.startsWith('@')) cleanUsername = cleanUsername.substring(1).trim();
    cleanUsername = cleanUsername.toLowerCase();
    final cleanEmail = email.trim().toLowerCase();

    if (!_usernamePattern.hasMatch(cleanUsername)) {
      throw AuthException(_app.t('err_username_invalid'));
    }
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw AuthException(_app.t('err_email_invalid'));
    }
    final status = await checkUsernameStatus(cleanUsername);
    if (status == 'reserved') throw AuthException(_app.t('err_username_reserved'));
    if (status == 'taken') throw AuthException(_app.t('err_username_taken'));
    if (status == 'inappropriate') throw AuthException(_app.t('err_inappropriate'));
    if (status == 'invalid') throw AuthException(_app.t('err_username_invalid'));

    final cleanDisplay = (displayName ?? '').trim().isEmpty ? cleanUsername : displayName!.trim();
    // v0.6: kalıcı engelli e-posta / cihaz ve uygunsuz adlar kayıttan önce reddedilir
    final blockReason = await JuzzioFeaturesService.instance
        .checkSignupAllowed(email: cleanEmail, username: cleanUsername, displayName: cleanDisplay);
    if (blockReason == 'inappropriate_content') throw AuthException(_app.t('err_inappropriate'));
    if (blockReason == 'signup_disabled') throw AuthException(_app.t('err_signup_disabled'));
    if (blockReason != null) {
      throw AuthException(_app.trEn('Bu cihazdan veya bu e-posta adresiyle yeni hesap açılamaz (kalıcı engel).',
          'A new account cannot be created from this device or with this email (permanent ban).',
          'Von diesem Gerät oder mit dieser E-Mail kann kein neues Konto erstellt werden (dauerhafte Sperre).'));
    }
    final safeGender = const ['female', 'male', 'unspecified'].contains(gender) ? gender : 'unspecified';

    late final AuthResponse signUpRes;
    try {
      signUpRes = await client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {
          'username': cleanUsername,
          'display_name': cleanDisplay,
          'preferred_lang': preferredLang,
          'app_lang': _app.uiLang,
          'gender': safeGender,
        },
      );
    } on AuthException catch (e) {
      throw AuthException(friendlyError(e));
    }

    final user = signUpRes.user;
    if (user == null) {
      throw AuthException(_app.t('err_register_failed'));
    }
    if (client.auth.currentSession == null) {
      // E-posta onayı açık: profil DB trigger'ı ile oluşturuldu, onaydan sonra giriş yapılmalı.
      throw AuthException(_app.t('info_confirm_email'));
    }

    // Profil, veritabanı tetikleyicisi tarafından kayıt anında oluşturulur. Buradaki
    // güncelleme yalnızca dil tercihlerini eşitler; başarısız olsa bile hesap açılmıştır.
    try {
      await upsertProfile(
        userId: user.id,
        username: cleanUsername,
        email: cleanEmail,
        displayName: cleanDisplay,
        preferredLang: preferredLang,
        subtitleLang: preferredLang,
        appLang: _app.uiLang,
      );
    } catch (e) {
      Map<String, dynamic>? exists;
      try {
        exists = await client.from('profiles').select('id').eq('id', user.id).maybeSingle();
      } catch (_) {
        exists = null;
      }
      if (exists == null) throw AuthException(friendlyError(e));
    }
    await setPresence(true);

    return {'user': user, 'username': cleanUsername, 'preferredLang': preferredLang};
  }

  Future<Map<String, dynamic>> signInWithUsernameOrEmail({
    required String usernameOrEmail,
    required String password,
    String fallbackLang = 'tr',
  }) async {
    final rawInput = usernameOrEmail.trim();
    if (rawInput.isEmpty) {
      throw AuthException(_app.t('err_login_empty'));
    }
    final input = rawInput.startsWith('@') ? rawInput.substring(1).trim() : rawInput;
    final targetEmail = input.contains('@') ? input.toLowerCase() : '';

    User? user;
    if (targetEmail.isNotEmpty) {
      try {
        final signInRes = await client.auth.signInWithPassword(email: targetEmail, password: password);
        user = signInRes.user;
      } on AuthException catch (e) {
        throw AuthException(friendlyError(e));
      }
    } else {
      // Kullanıcı adıyla giriş sunucuda yapılır; e-posta adresi istemciye hiç gelmez.
      try {
        final res = await client.functions.invoke(
          'auth-username-login',
          body: {'login': input, 'password': password},
        );
        final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
        final refresh = (data['refresh_token'] ?? '').toString();
        if (data['ok'] != true || refresh.isEmpty) {
          throw AuthException(friendlyError((data['error'] ?? 'invalid_credentials').toString()));
        }
        final session = await client.auth.setSession(refresh);
        user = session.user ?? client.auth.currentUser;
      } on FunctionException catch (e) {
        final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : <String, dynamic>{};
        throw AuthException(friendlyError((details['error'] ?? 'invalid_credentials').toString()));
      } on AuthException {
        rethrow;
      } catch (e) {
        throw AuthException(friendlyError(e));
      }
    }
    if (user == null) {
      throw AuthException(_app.t('err_login_failed'));
    }

    String resolvedUsername = (user.userMetadata?['username'] ?? input.split('@').first).toString();
    String resolvedLang = (user.userMetadata?['preferred_lang'] ?? fallbackLang).toString();

    var profile = await fetchUserProfile(user.id);
    if (profile == null) {
      // Profil satırı yoksa (eski kayıtlar) oluştur
      await upsertProfile(
        userId: user.id,
        username: resolvedUsername,
        email: user.email ?? targetEmail,
        displayName: resolvedUsername,
        preferredLang: resolvedLang,
      );
      profile = await fetchUserProfile(user.id);
    }
    if (profile != null) {
      resolvedUsername = profile.username;
      resolvedLang = profile.subtitleLang.isNotEmpty ? profile.subtitleLang : profile.preferredLang;
      _app.setSubtitleLanguage(resolvedLang);
      if (profile.isSilentMode) _app.setSilentMode(true);
    }
    await setPresence(true);

    return {'user': user, 'username': resolvedUsername, 'preferredLang': resolvedLang};
  }

  Future<void> signOut() async {
    try {
      await setPresence(false);
    } catch (_) {}
    await clearLocalCacheForCurrentUser();
    JuzzioMediaUrl.clearCache();
    await JuzzioMediaDiskCache.instance.init(null);
    await client.auth.signOut();
  }

  Future<void> verifyAndChangePassword({required String currentPassword, required String newPassword}) async {
    final email = client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw AuthException(_app.t('err_session'));
    }
    if (newPassword.length < 6) {
      throw AuthException(_app.t('err_password_short'));
    }
    try {
      final verifyRes = await client.auth.signInWithPassword(email: email, password: currentPassword);
      if (verifyRes.user == null) throw AuthException(_app.t('err_password_wrong'));
    } on AuthException {
      throw AuthException(_app.t('err_password_wrong'));
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Sunucu kontrolü: ok | taken | reserved | invalid | inappropriate | error
  Future<String> checkUsernameStatus(String candidateUsername) async {
    final clean = candidateUsername.trim().replaceAll('@', '').toLowerCase();
    if (!_usernamePattern.hasMatch(clean)) return 'invalid';
    try {
      final res = await client.rpc('check_username_available', params: {'p_username': clean});
      return (res ?? 'error').toString();
    } catch (_) {
      return 'error';
    }
  }

  Future<bool> checkUsernameAvailability(String candidateUsername) async {
    return (await checkUsernameStatus(candidateUsername)) == 'ok';
  }

  /// Yalnızca kullanıcı adını değiştirir (görünen ad korunur).
  Future<void> updateMyUsername(String newUsername) async {
    final uid = currentUserId;
    if (uid == null) return;
    final clean = newUsername.trim().replaceAll('@', '').toLowerCase();
    if (!_usernamePattern.hasMatch(clean)) {
      throw JuzzioServiceException(_app.trEn('Geçersiz kullanıcı adı.', 'Invalid username.', 'Ungültiger Benutzername.'));
    }
    await client.from('profiles').update({
      'username': clean,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
    try {
      await client.auth.updateUser(UserAttributes(data: {'username': clean}));
    } catch (_) {}
  }

  Future<void> deleteMyAccountCompletely({required String password}) async {
    final uid = currentUserId;
    final email = client.auth.currentUser?.email;
    if (uid == null || email == null) {
      throw AuthException(_app.t('err_session'));
    }
    try {
      final verifyRes = await client.auth.signInWithPassword(email: email, password: password);
      if (verifyRes.user == null) throw AuthException(_app.t('err_password_wrong'));
    } on AuthException {
      throw AuthException(_app.t('err_password_wrong'));
    }
    await client.rpc('delete_my_juzzio_account');
    // Hesap silinince bu cihazdaki önbellek (sohbetler, mesajlar, medya) de silinir
    await clearLocalCacheForCurrentUser();
    JuzzioMediaUrl.clearCache();
    await JuzzioMediaDiskCache.instance.init(null);
    await client.auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // PROFİL
  // ---------------------------------------------------------------------------
  Timer? _prefsSyncDebounce;

  /// Uygulamadaki gizlilik ayarlarını (eskiden yalnızca telefonda saklanıyordu)
  /// profiles tablosuna yansıtır; böylece gizli hesap, son görülme vb. sunucuda da geçerli olur.
  ///
  /// Yalnızca kullanıcının bu oturumda DEĞİŞTİRDİĞİ alanlar gönderilir. Böylece yeni
  /// cihazda/yeni kurulumda telefondaki varsayılan değerler (ör. dil değiştirilince)
  /// sunucudaki gizlilik ayarlarının üzerine yazılmaz.
  Map<String, dynamic>? _prefsSyncBaseline;

  /// v0.9.0 (G12): Arayüz dil paketi metinleri sunucu önbellekli `batch_ui` moduyla çevrilir
  /// (her metin tüm kullanıcılar için bir kez çevrilir; telefon doğrudan Google'a yüklenmez).
  Future<Map<String, String>> translateUiBatch(String lang, List<String> texts) async {
    if (currentUserId == null || texts.isEmpty) return const <String, String>{};
    try {
      final res = await client.functions
          .invoke('translate-bridge', body: {'mode': 'batch_ui', 'targetLang': lang, 'texts': texts})
          .timeout(const Duration(seconds: 25));
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is Map && data['translations'] is Map) {
        return (data['translations'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return const <String, String>{};
  }

  // ---------------------------------------------------------------------------
  // v0.9.3: ÇEVRİMDIŞI AYAR KUYRUĞU
  // İnternet yokken yapılan ayar değişiklikleri kaybolmaz: işlem cihazda (hesaba özel dosyada)
  // sıraya alınır ve bağlantı gelince (30 sn'de bir deneme + uygulama öne gelince) sunucuya
  // yazılır. Aynı anahtardaki yeni değer eskisinin yerine geçer (son yazan kazanır); profil
  // alanları birleştirilir. Sunucu işlemi REDDEDERSE (yetki/doğrulama) kuyruktan atılır.
  // ---------------------------------------------------------------------------
  Map<String, Map<String, dynamic>>? _pendingOps;
  Timer? _pendingFlushTimer;
  bool _flushingPending = false;

  /// Ağ kaynaklı (yeniden denenebilir) hata mı?
  static bool isNetworkError(Object e) {
    if (e is SocketException || e is TimeoutException || e is HttpException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception') ||
        s.contains('timed out') ||
        s.contains('timeoutexception');
  }

  Future<Map<String, Map<String, dynamic>>> _loadPendingOps() async {
    if (_pendingOps != null) return _pendingOps!;
    final out = <String, Map<String, dynamic>>{};
    try {
      final raw = await _readCache('pending_ops');
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) out[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
    } catch (_) {}
    return _pendingOps = out;
  }

  Future<void> _savePendingOps() async {
    final ops = _pendingOps ?? const {};
    try {
      await _writeCache('pending_ops', ops);
    } catch (_) {}
    if (ops.isEmpty) {
      _pendingFlushTimer?.cancel();
      _pendingFlushTimer = null;
    } else {
      _pendingFlushTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => flushPendingOps());
    }
  }

  /// Bekleyen ayar işlemi sayısı (arayüzde "bağlantı gelince kaydedilecek" bilgisi için).
  int get pendingOpCount => _pendingOps?.length ?? 0;

  Future<void> _runOp(Map<String, dynamic> op) async {
    final uid = currentUserId;
    if (uid == null) throw const JuzzioServiceException('not_authenticated');
    switch (op['t']) {
      case 'profile':
        final fields = Map<String, dynamic>.from(op['fields'] as Map);
        fields['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await client.from('profiles').update(fields).eq('id', uid);
        return;
      case 'rpc':
        await client.rpc(op['fn'].toString(), params: op['params'] is Map ? Map<String, dynamic>.from(op['params'] as Map) : null);
        return;
    }
  }

  /// İşlemi hemen dener; ağ yoksa sıraya alır ve false döner (değişiklik KAYBOLMAZ).
  /// Sunucu reddederse istisnayı aynen fırlatır.
  Future<bool> writeOrQueue(String key, Map<String, dynamic> op) async {
    final ops = await _loadPendingOps();
    // Profil alanları: bekleyen değerlerle birleştir (sıra dışı yazımda eski alan kaybolmasın)
    var effective = op;
    if (op['t'] == 'profile' && ops[key]?['t'] == 'profile') {
      effective = {
        't': 'profile',
        'fields': {...Map<String, dynamic>.from(ops[key]!['fields'] as Map), ...Map<String, dynamic>.from(op['fields'] as Map)},
      };
    }
    try {
      await _runOp(effective);
      if (ops.remove(key) != null) await _savePendingOps();
      return true;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      ops[key] = effective;
      await _savePendingOps();
      return false;
    }
  }

  /// Bekleyen ayarları sunucuya yazar (bağlantı yoksa sonraki denemeye bırakır).
  Future<void> flushPendingOps() async {
    if (_flushingPending || currentUserId == null) return;
    _flushingPending = true;
    try {
      final ops = await _loadPendingOps();
      for (final key in ops.keys.toList()) {
        try {
          await _runOp(ops[key]!);
          ops.remove(key);
        } catch (e) {
          if (isNetworkError(e)) break; // hâlâ çevrimdışı
          ops.remove(key); // sunucu reddetti: tekrar denemenin anlamı yok
        }
      }
      await _savePendingOps();
    } finally {
      _flushingPending = false;
    }
  }

  void attachPreferenceSync() {
    unawaited(flushPendingOps());
    JuzzioAppController.serverUiTranslator = translateUiBatch;
    _prefsSyncBaseline = _profileFieldsFromPrefs(_app.preferencesSnapshot());
    JuzzioAppController.remotePreferenceSync = (prefs) {
      _prefsSyncDebounce?.cancel();
      _prefsSyncDebounce = Timer(const Duration(milliseconds: 800), () => _pushPreferencesToProfile(prefs));
    };
  }

  String _privacyValue(dynamic raw, {String fallback = 'everyone'}) {
    final v = (raw ?? fallback).toString();
    if (v == 'contacts' || v == 'my_contacts' || v == 'friends') return 'friends';
    if (v == 'nobody' || v == 'none') return 'nobody';
    return 'everyone';
  }

  Future<void> _pushPreferencesToProfile(Map<String, dynamic> prefs) async {
    final uid = currentUserId;
    if (uid == null) return;
    final fields = _profileFieldsFromPrefs(prefs);
    final baseline = _prefsSyncBaseline ?? const <String, dynamic>{};
    final changed = <String, dynamic>{};
    fields.forEach((k, v) {
      if (baseline[k] != v) changed[k] = v;
    });
    if (changed.isEmpty) return;
    try {
      // v0.9.3: çevrimdışıysa sıraya alınır, bağlantı gelince yazılır
      await writeOrQueue('profile', {'t': 'profile', 'fields': changed});
      _prefsSyncBaseline = {...baseline, ...fields};
    } catch (_) {}
  }

  Map<String, dynamic> _profileFieldsFromPrefs(Map<String, dynamic> prefs) {
    final lastSeen = _privacyValue(prefs['lastSeenPrivacy']);
    final onlineRaw = prefs['onlinePrivacy']?.toString();
    final postsRaw = (prefs['postsPrivacy'] ?? 'public').toString();
    final timer = (prefs['defaultMessageTimer'] ?? 'off').toString();
    final update = <String, dynamic>{
      'privacy_last_seen': lastSeen,
      'privacy_online': onlineRaw == 'same_as_last_seen' ? lastSeen : _privacyValue(onlineRaw),
      'privacy_avatar': _privacyValue(prefs['profilePhotoPrivacy']),
      'privacy_bio': _privacyValue(prefs['aboutPrivacy']),
      'privacy_status': _privacyValue(prefs['statusPrivacy']),
      'privacy_groups': _privacyValue(prefs['whoCanAddMeToGroups']),
      'privacy_mentions': _privacyValue(prefs['whoCanMentionMe']),
      'privacy_posts': postsRaw == 'public'
          ? 'everyone'
          : (postsRaw == 'private' ? 'nobody' : (['followers', 'friends'].contains(postsRaw) ? postsRaw : 'everyone')),
      'is_private_account': prefs['isPrivateAccount'] == true,
      'read_receipts': prefs['readReceiptsEnabled'] != false,
      'default_message_timer': ['off', '24h', '7d', '30d'].contains(timer) ? timer : 'off',
      'strict_account_mode': prefs['strictAccountSettings'] == true,
      'is_silent_mode': prefs['isSilentMode'] == true,
      'allow_unknown_calls': prefs['silenceUnknownCallers'] != true,
      'subtitle_lang': (prefs['subtitleLang'] ?? _app.subtitleLang).toString(),
      'app_lang': (prefs['uiLang'] ?? _app.uiLang).toString(),
    };
    return update;
  }

  Timer? _presenceHeartbeat;

  /// Çevrimiçi durumu. Uygulama ön plandayken dakikada bir nabız gönderilir;
  /// sunucu son 3 dakikada nabız almadıysa kullanıcıyı çevrimdışı gösterir.
  Future<void> setPresence(bool online) async {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
    if (currentUserId == null) return;
    if (online) {
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 60), (_) async {
        if (currentUserId == null) {
          _presenceHeartbeat?.cancel();
          _presenceHeartbeat = null;
          return;
        }
        try {
          await client.rpc('set_my_presence', params: {'p_online': true});
        } catch (_) {}
      });
    }
    try {
      await client.rpc('set_my_presence', params: {'p_online': online});
    } catch (_) {}
  }

  /// Görüntülenen kişinin çevrimiçi / son görülme bilgisi (gizlilik sunucuda uygulanır).
  Future<({bool isOnline, DateTime? lastSeen})> fetchUserPresence(String userId) async {
    try {
      final res = await client.rpc('get_user_presence', params: {'p_user': userId});
      if (res is Map) {
        return (
          isOnline: res['is_online'] == true,
          lastSeen: DateTime.tryParse(res['last_seen']?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return (isOnline: false, lastSeen: null);
  }

  /// Profil yoksa oluşturur, varsa YALNIZCA verilen alanları günceller
  /// (eski sürüm her girişte görünen adı kullanıcı adıyla eziyordu).
  Future<void> upsertProfile({
    required String userId,
    String? username,
    required String email,
    required String displayName,
    required String preferredLang,
    String? subtitleLang,
    String? appLang,
    bool? isSilentMode,
    String? bio,
    String? avatarUrl,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final cleanUsername = (username ?? '').trim().replaceAll('@', '').toLowerCase();
    final safeLang = ['tr', 'en', 'de'].contains(preferredLang) ? preferredLang : 'en';

    final update = <String, dynamic>{
      'preferred_lang': safeLang,
      'updated_at': nowIso,
    };
    if (displayName.trim().isNotEmpty) update['display_name'] = displayName.trim().replaceAll('@', '');
    if (subtitleLang != null) update['subtitle_lang'] = subtitleLang;
    if (appLang != null) update['app_lang'] = appLang;
    if (isSilentMode != null) update['is_silent_mode'] = isSilentMode;
    if (bio != null) update['bio'] = bio.trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty) update['avatar_url'] = avatarUrl;

    final existing = await client.from('profiles').select('id').eq('id', userId).maybeSingle();
    if (existing != null) {
      await client.from('profiles').update(update).eq('id', userId);
      return;
    }
    await client.from('profiles').insert({
      'id': userId,
      'email': email.trim().toLowerCase(),
      if (cleanUsername.isNotEmpty) 'username': cleanUsername,
      'display_name': displayName.trim().isEmpty ? (cleanUsername.isEmpty ? 'Juzzio User' : cleanUsername) : displayName.trim(),
      ...update,
    });
  }

  Future<JuzzioUserProfile?> fetchUserProfile(String userId) async {
    try {
      final row = await client.from('profiles').select().eq('id', userId).maybeSingle();
      if (row != null) {
        unawaited(_writeCache(userId == currentUserId ? 'my_profile' : profileCacheName(userId), row));
        return JuzzioUserProfile.fromMap(row);
      }
      return null; // sunucu "yok" dedi: önbellek kullanılmaz (silinmiş/engelli hesap)
    } catch (_) {
      // v0.9.2: çevrimdışı → en son görülen profil
      return cachedUserProfile(userId);
    }
  }

  static String profileCacheName(String userId) => 'profile_${userId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}';

  /// Cihazda kayıtlı son profil (ağ kullanmaz). Yoksa toplu profil önbelleğine bakar.
  Future<JuzzioUserProfile?> cachedUserProfile(String userId) async {
    try {
      final raw = await _readCache(userId == currentUserId ? 'my_profile' : profileCacheName(userId));
      if (raw is Map) return JuzzioUserProfile.fromMap(Map<String, dynamic>.from(raw));
      for (final p in await loadCachedProfiles()) {
        if (p.id == userId) return p;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // v0.5.0 — Kullanıcıya özel yerel önbellek (açılışta anında çizim)
  //  Her hesap kendi klasörünü kullanır; çıkışta silinir. Ağdan gelen veri
  //  her zaman önbelleğin üzerine yazar (arka planda sessiz yenileme).
  // ---------------------------------------------------------------------------
  Future<File?> _cacheFile(String name) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory('${dir.path}/juzzio_cache/$uid');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      return File('${folder.path}/$name.json');
    } catch (_) {
      return null;
    }
  }

  /// v0.9.3: diğer servislerin hesaba özel çevrimdışı önbelleği (ad yalnız güvenli karakter).
  static String safeCacheName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  Future<void> writeLocalCache(String name, Object data) => _writeCache(safeCacheName(name), data);
  Future<Object?> readLocalCache(String name) => _readCache(safeCacheName(name));

  /// v0.9.7: hesaba özel Drift (SQLite) veritabanı; açılamazsa null (JSON dosyalara düşülür).
  Future<JuzzioLocalDb?> _localDb() async {
    final f = await _cacheFile('conversations');
    if (f == null) return null;
    return JuzzioLocalStore.instance.open(f.parent);
  }

  static bool _isMessageCache(String name) => name.startsWith('msgs_');
  static String _roomFromCacheName(String name) => name.substring(5);

  Future<void> _writeCache(String name, Object data) async {
    // v0.9.7: önce Drift (SQLite); başarılıysa JSON dosyası yazılmaz
    try {
      final db = await _localDb();
      if (db != null) {
        if (_isMessageCache(name) && data is List) {
          await db.upsertRoomWindow(_roomFromCacheName(name), data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
              keep: offlineMessageLimit);
        } else {
          await db.putJson(name, data);
        }
        return;
      }
    } catch (_) {}
    try {
      final f = await _cacheFile(name);
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<Object?> _readCache(String name, {int messageLimit = offlineMessageLimit}) async {
    JuzzioLocalDb? db;
    try {
      db = await _localDb();
      if (db != null) {
        final Object? v = _isMessageCache(name) ? await db.roomMessages(_roomFromCacheName(name), limit: messageLimit) : await db.getJson(name);
        if (v != null && !(v is List && v.isEmpty)) return v;
      }
    } catch (_) {}
    // JSON yedeği / eski sürümden geçiş: dosya varsa okunur, Drift'e taşınır ve silinir
    try {
      final f = await _cacheFile(name);
      if (f == null || !f.existsSync()) return null;
      final v = jsonDecode(await f.readAsString());
      if (db != null && v != null) {
        try {
          if (_isMessageCache(name) && v is List) {
            await db.upsertRoomWindow(_roomFromCacheName(name), v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
                keep: offlineMessageLimit);
          } else {
            await db.putJson(name, v as Object);
          }
          await f.delete();
        } catch (_) {}
      }
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<List<JuzzioConversation>> loadCachedConversations() async {
    final raw = await _readCache('conversations');
    if (raw is! List) return const [];
    try {
      return raw.whereType<Map>().map((e) => JuzzioConversation.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<JuzzioUserProfile?> loadCachedMyProfile() async {
    final raw = await _readCache('my_profile');
    if (raw is! Map) return null;
    try {
      return JuzzioUserProfile.fromMap(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<List<JuzzioUserProfile>> loadCachedProfiles() async {
    final raw = await _readCache('profiles');
    if (raw is! List) return const [];
    try {
      return raw.whereType<Map>().map((e) => JuzzioUserProfile.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Çıkışta bu hesaba ait yerel önbelleği siler (hesaplar arası veri sızmaz).
  Future<void> clearLocalCacheForCurrentUser() async {
    await JuzzioLocalStore.instance.closeAndDelete();
    try {
      final f = await _cacheFile('conversations');
      final dir = f?.parent;
      if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<List<JuzzioUserProfile>> fetchProfilesByIds(Iterable<String> ids) async {
    final list = ids.where((e) => e.isNotEmpty).toSet().toList();
    if (list.isEmpty) return const [];
    try {
      final rows = await client.from('profiles').select().inFilter('id', list);
      return (rows as List).map((e) => JuzzioUserProfile.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Arama/öneri için son aktif kullanıcılar (arkadaş listesi DEĞİLDİR).
  Future<List<JuzzioUserProfile>> fetchAllProfiles({int limit = 200}) async {
    try {
      final rows = await client.from('profiles').select().order('updated_at', ascending: false).limit(limit);
      unawaited(_writeCache('profiles', rows));
      return (rows as List).map((e) => JuzzioUserProfile.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Stream<List<JuzzioUserProfile>> watchAllProfiles({int limit = 200}) {
    return client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(JuzzioUserProfile.fromMap).toList())
        .handleError((_) {});
  }

  Future<List<JuzzioUserProfile>> searchUsersByUsername(String query) async {
    final clean = query.trim().replaceAll('@', '').replaceAll(RegExp(r'[%,()*\\]'), '');
    try {
      final List rows;
      if (clean.isEmpty) {
        rows = await client.from('profiles').select().order('updated_at', ascending: false).limit(40);
      } else {
        rows = await client
            .from('profiles')
            .select()
            .or('username.ilike.%$clean%,display_name.ilike.%$clean%')
            .limit(40);
      }
      final uid = currentUserId;
      return rows
          .map((e) => JuzzioUserProfile.fromMap(e as Map<String, dynamic>))
          .where((u) => u.id != uid)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // v0.6 İÇERİK DENETİMİ (content-moderation Edge Function)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _functionMap(dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  /// Yüklenen profil fotoğrafını denetletir. Uygunsuzsa (dosya sunucuda silinir) hata fırlatır.
  Future<void> moderateAvatar(String publicUrl) async {
    try {
      final res = await client.functions.invoke('content-moderation', body: {'action': 'avatar', 'url': publicUrl});
      final map = _functionMap(res.data);
      if (map['ok'] == true) return;
      throw JuzzioServiceException(_app.trEn(
        'Bu fotoğraf uygunsuz içerik barındırdığı için kullanılamaz.',
        'This photo cannot be used because it contains inappropriate content.',
        'Dieses Foto enthält unangemessene Inhalte und kann nicht verwendet werden.',
      ));
    } on FunctionException catch (_) {
      throw JuzzioServiceException(_app.trEn(
        'Fotoğraf şu an denetlenemedi. Lütfen biraz sonra tekrar deneyin.',
        'The photo could not be checked right now. Please try again shortly.',
        'Das Foto konnte gerade nicht geprüft werden. Bitte versuche es gleich erneut.',
      ));
    }
  }

  /// Görüntülü aramada kendi kameramızdan alınan küçük kareyi denetletir.
  /// Dönen haritada `violation` varsa ceza uygulanmış ve arama sunucuda kapatılmıştır.
  Future<Map<String, dynamic>> moderateCallFrame({required String roomName, required String imageBase64}) async {
    try {
      final res = await client.functions.invoke('content-moderation', body: {
        'action': 'call_frame',
        'roomName': roomName,
        'image': imageBase64,
      });
      return _functionMap(res.data);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// Kendi konuşmamızın metnini denetletir (aynı aramada 2. ağır ifade → ihlal).
  Future<Map<String, dynamic>> moderateCallSpeech({required String roomName, required String text}) async {
    try {
      final res = await client.functions.invoke('content-moderation', body: {
        'action': 'call_speech',
        'roomName': roomName,
        'text': text,
      });
      return _functionMap(res.data);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<JuzzioUserProfile?> uploadAvatarAndSaveProfile({
    required String userId,
    required String displayName,
    required String bio,
    required String preferredLang,
    File? newAvatarFile,
    String? existingAvatarUrl,
  }) async {
    String? finalAvatarUrl = existingAvatarUrl;

    if (newAvatarFile != null && newAvatarFile.existsSync()) {
      // v0.9.4: avatars kovası 5 MB — yüklemeden önce sıkıştır
      newAvatarFile = await juzzioCompressImageForUpload(newAvatarFile, maxSide: 1080);
      final ext = newAvatarFile.path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await client.storage.from(JuzzioConfig.avatarBucket).upload(
            path,
            newAvatarFile,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      finalAvatarUrl = client.storage.from(JuzzioConfig.avatarBucket).getPublicUrl(path);
      // v0.6: profil fotoğrafı müstehcenlik denetiminden geçmeden kaydedilmez
      await moderateAvatar(finalAvatarUrl);
    }

    await upsertProfile(
      userId: userId,
      email: client.auth.currentUser?.email ?? '',
      displayName: displayName,
      preferredLang: preferredLang,
      subtitleLang: _app.subtitleLang,
      appLang: _app.uiLang,
      isSilentMode: _app.isSilentMode,
      bio: bio,
      avatarUrl: finalAvatarUrl,
    );

    if (finalAvatarUrl == null || finalAvatarUrl.isEmpty) {
      // Profil fotoğrafı kaldırıldı
      try {
        await client.from('profiles').update({'avatar_url': null}).eq('id', userId);
      } catch (_) {}
    }

    try {
      await client.auth.updateUser(UserAttributes(data: {
        'display_name': displayName,
        'preferred_lang': preferredLang,
      }));
    } catch (_) {}

    return fetchUserProfile(userId);
  }

  Future<String> updatePersonalInformation({
    String? newEmail,
    String? newPassword,
    String? newUsername,
    String? newDisplayName,
    String? newBio,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      return _app.trEn('Oturum açık değil.', 'Not signed in.', 'Nicht angemeldet.');
    }
    try {
      final wantsEmail = newEmail != null && newEmail.trim().isNotEmpty;
      final wantsPassword = newPassword != null && newPassword.trim().isNotEmpty;
      if (wantsEmail || wantsPassword) {
        await client.auth.updateUser(UserAttributes(
          email: wantsEmail ? newEmail.trim() : null,
          password: wantsPassword ? newPassword.trim() : null,
        ));
      }

      final updateMap = <String, dynamic>{'updated_at': DateTime.now().toUtc().toIso8601String()};
      if (newUsername != null && newUsername.trim().isNotEmpty) {
        final u = newUsername.trim().replaceAll('@', '').toLowerCase();
        if (!_usernamePattern.hasMatch(u)) {
          return _app.trEn('Geçersiz kullanıcı adı.', 'Invalid username.', 'Ungültiger Benutzername.');
        }
        updateMap['username'] = u;
      }
      if (newDisplayName != null && newDisplayName.trim().isNotEmpty) {
        updateMap['display_name'] = newDisplayName.trim();
      }
      if (newBio != null) updateMap['bio'] = newBio.trim();

      await client.from('profiles').update(updateMap).eq('id', uid);
      return wantsEmail
          ? _app.trEn(
              'Bilgileriniz güncellendi. Yeni e-posta adresinize gönderilen onay bağlantısını açın.',
              'Saved. Please confirm the link sent to your new e-mail address.', 'Gespeichert. Bitte bestätige den Link, der an deine neue E-Mail-Adresse gesendet wurde.',
            )
          : _app.trEn('Kişisel bilgileriniz başarıyla güncellendi!', 'Your personal information has been updated!', 'Deine persönlichen Daten wurden aktualisiert!');
    } catch (e) {
      return _app.trEn('Güncelleme başarısız: ${_friendlyError(e)}', 'Update failed: ${_friendlyError(e)}', 'Aktualisierung fehlgeschlagen: ${_friendlyError(e)}');
    }
  }

  // ---------------------------------------------------------------------------
  // ÇEVİRİ
  // ---------------------------------------------------------------------------
  /// v0.5 Küresel akış: gönderi/yorum toplu çevirisi (sunucu önbellekli, RLS ile okunur).
  /// Dönen harita: içerik kimliği → (metin, başarılı mı). Çeviri başarısızsa orijinal metin
  /// `ok == false` ile döner; arayüz bunu "çevrilemedi" olarak gösterir.
  Future<Map<String, ({String text, bool ok})>> translateContentBatch({
    required String kind, // 'post' | 'comment'
    required List<String> ids,
    required String targetLang,
  }) async {
    final out = <String, ({String text, bool ok})>{};
    if (ids.isEmpty) return out;
    try {
      final res = await client.functions.invoke('translate-bridge', body: {
        'mode': 'content',
        'kind': kind,
        'ids': ids.take(40).toList(),
        'targetLang': targetLang.toLowerCase(),
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final tr = data is Map ? data['translations'] : null;
      if (tr is Map) {
        tr.forEach((k, v) {
          if (v is Map) {
            out[k.toString()] = (text: (v['text'] ?? '').toString(), ok: v['ok'] == true);
          }
        });
      }
    } catch (_) {
      // Sunucu fonksiyonu henüz dağıtılmadıysa arayan tek tek çeviriye düşer
    }
    return out;
  }

  Future<String> translateText({
    required String text,
    String sourceLang = 'auto',
    required String targetLang,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return clean;
    final tl = targetLang.trim().toLowerCase();
    final sl = sourceLang.trim().isEmpty ? 'auto' : sourceLang.trim().toLowerCase();
    if (sl == tl && sl != 'auto') return clean;

    final cacheKey = '$sl|$tl|$clean';
    final cached = _translationCache[cacheKey];
    if (cached != null && cached.isNotEmpty) return cached;

    // v0.9.3: uzun metin (sesli mesaj dökümü vb.) parçalara bölünür — tek uzun istek hem
    // adres sınırına takılıyor hem de yedek servisin "500 karakter" hata metnini döndürüyordu
    if (clean.length > translationChunkMax) {
      final parts = splitForTranslation(clean);
      final out = <String>[];
      for (final part in parts) {
        out.add(await translateText(text: part, sourceLang: sl, targetLang: tl));
      }
      final joined = out.join(' ').trim();
      if (_translationCache.length > 500) _translationCache.clear();
      _translationCache[cacheKey] = joined;
      return joined;
    }

    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=auto&tl=${Uri.encodeComponent(juzzioGoogleLangCode(tl))}&dt=t&q=${Uri.encodeComponent(clean)}',
      );
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final buffer = StringBuffer();
          for (final seg in decoded[0]) {
            if (seg is List && seg.isNotEmpty && seg[0] != null) buffer.write(seg[0].toString());
          }
          final result = buffer.toString().trim();
          if (result.isNotEmpty && !isTranslationProviderError(result)) {
            if (_translationCache.length > 500) _translationCache.clear();
            _translationCache[cacheKey] = result;
            return result;
          }
        }
      }
    } catch (_) {}

    try {
      final res = await client.functions.invoke('translate-bridge', body: {
        'mode': 'text',
        'text': clean,
        'sourceLang': sl,
        'targetLang': tl,
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final translated = (data is Map) ? data['translatedText']?.toString() : null;
      if (translated != null && translated.isNotEmpty && !isTranslationProviderError(translated)) {
        _translationCache[cacheKey] = translated;
        return translated;
      }
    } catch (_) {}

    return clean;
  }

  String get _defaultTargetLang => _app.subtitleLang == 'tr' ? 'en' : 'tr';

  // ---------------------------------------------------------------------------
  // SOHBETLER (ODALAR)
  // ---------------------------------------------------------------------------
  /// Arkadaşla 1'e 1 özel sohbet odasını getirir/oluşturur. Hata durumunda
  /// ASLA ortak bir odaya düşmez; istisna fırlatır.
  Future<String> ensureDirectRoomWithFriend({required String friendId, String friendName = ''}) async {
    if (currentUserId == null) {
      throw JuzzioServiceException(_app.trEn('Oturum açık değil.', 'Not signed in.', 'Nicht angemeldet.'));
    }
    try {
      final res = await client.rpc('get_or_create_dm_room', params: {'p_other': friendId});
      final id = res?.toString() ?? '';
      if (id.isEmpty) throw const JuzzioServiceException('room_not_created');
      return id;
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<List<JuzzioConversation>> fetchMyConversations() async {
    if (currentUserId == null) return const [];
    final rows = await client.rpc('get_my_conversations');
    if (rows is! List) return const [];
    unawaited(_writeCache('conversations', rows));
    return rows.map((e) => JuzzioConversation.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Sohbet listesini gerçek zamanlı izler: mesaj/oda/katılımcı değişikliklerinde
  /// (RLS sayesinde yalnızca kullanıcının kendi sohbetleri) listeyi yeniler.
  Stream<List<JuzzioConversation>> watchMyConversations() {
    final uid = currentUserId;
    // v0.9.3: ilk açılışta oturum henüz geri yüklenmemişse BOŞ liste yayınlanmaz (aksi hâlde tüm
    // arkadaşlar "Sohbet başlatmak için dokun" olarak görünüyordu); oturum gelince izleme başlar.
    if (uid == null) {
      return client.auth.onAuthStateChange
          .where((e) => e.session != null)
          .take(1)
          .asyncExpand((_) => watchMyConversations());
    }
    late StreamController<List<JuzzioConversation>> controller;
    RealtimeChannel? channel;
    Timer? debounce;
    Timer? poll;

    Future<void> refresh() async {
      try {
        final list = await fetchMyConversations();
        if (!controller.isClosed) controller.add(list);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), refresh);
    }

    controller = StreamController<List<JuzzioConversation>>.broadcast(
      onListen: () {
        refresh();
        channel = client
            .channel('juzzio-conversations-$uid-${DateTime.now().millisecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'messages',
              callback: (_) => schedule(),
            )
            .onPostgresChanges(
              // RLS: yalnızca üyesi olduğum odaların katılımcı satırları (okundu bilgisi dahil)
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'room_participants',
              callback: (_) => schedule(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'rooms',
              callback: (_) => schedule(),
            )
            .subscribe();
        // Realtime bağlantısı koparsa bile liste güncel kalsın
        poll = Timer.periodic(const Duration(seconds: 45), (_) => refresh());
      },
      onCancel: () async {
        debounce?.cancel();
        poll?.cancel();
        final ch = channel;
        channel = null;
        if (ch != null) {
          try {
            await client.removeChannel(ch);
          } catch (_) {}
        }
      },
    );
    return controller.stream;
  }

  /// Yeni gelen mesajları dinler (bildirim/heads-up için). RLS yalnızca
  /// kullanıcının üyesi olduğu odalardaki mesajları iletir.
  Stream<JuzzioMessage> watchIncomingMessages() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();
    late StreamController<JuzzioMessage> controller;
    RealtimeChannel? channel;
    controller = StreamController<JuzzioMessage>.broadcast(
      onListen: () {
        channel = client
            .channel('juzzio-incoming-$uid-${DateTime.now().millisecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'messages',
              callback: (payload) {
                try {
                  final msg = JuzzioMessage.fromMap(payload.newRecord);
                  if (msg.senderId != uid && !controller.isClosed) {
                    JuzzioE2ee.instance.decryptMessage(msg).then((m) {
                      if (!controller.isClosed) controller.add(m);
                    });
                  }
                } catch (_) {}
              },
            )
            .subscribe();
      },
      onCancel: () async {
        final ch = channel;
        channel = null;
        if (ch != null) {
          try {
            await client.removeChannel(ch);
          } catch (_) {}
        }
      },
    );
    return controller.stream;
  }

  Stream<List<JuzzioGroupRoom>> watchGroupRooms({String? myDisplayName}) {
    return watchMyConversations().map(
      (list) => list.where((c) => c.isGroup).map((c) => c.toGroupRoom()).toList(),
    );
  }

  Future<JuzzioGroupRoom?> fetchGroupRoom(String roomId) async {
    try {
      final row = await client.from('rooms').select().eq('id', roomId).maybeSingle();
      return row == null ? null : JuzzioGroupRoom.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// Kişi seçmeli grup/kanal oluşturur (yalnızca seçilenler eklenir).
  Future<JuzzioGroupRoom?> createGroupOrChannelRoom({
    required String title,
    required bool isChannel,
    required String disappearingTimer,
    List<String> members = const [],
    List<String> memberIds = const [],
    String groupType = 'general',
    String groupPurpose = '',
    String description = '',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw JuzzioServiceException(_app.t('err_group_title'));
    }
    try {
      final roomId = await client.rpc('create_group_room', params: {
        'p_title': cleanTitle,
        'p_member_ids': memberIds.where((e) => e.trim().isNotEmpty).toSet().toList(),
        'p_disappearing_timer': disappearingTimer,
        'p_is_channel': isChannel,
        'p_group_type': groupType,
        'p_group_purpose': groupPurpose.trim(),
        'p_description': description.trim(),
      });
      return await fetchGroupRoom(roomId.toString());
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<void> addGroupMembers({required String roomId, required List<String> memberIds}) async {
    try {
      await client.rpc('add_group_members', params: {'p_room': roomId, 'p_member_ids': memberIds});
    } catch (e) {
      throw JuzzioServiceException(friendlyError(e));
    }
  }

  Future<void> leaveRoom(String roomId) async {
    await client.rpc('leave_room', params: {'p_room': roomId});
  }

  Future<void> markRoomRead(String roomId) async {
    if (roomId.isEmpty || currentUserId == null) return;
    try {
      await client.rpc('mark_room_read', params: {'p_room': roomId});
    } catch (_) {}
    // v0.5.0: bu sohbete ait mesaj/tepki/arama bildirim kayıtları da okunur
    try {
      await client.rpc('mark_room_notifications_read', params: {'p_room': roomId});
    } catch (_) {}
  }

  /// v0.5.0: kullanıcının o an açık tuttuğu sohbet. Sunucu, sohbet açıkken
  /// mesaj tepkisi bildirimini göndermez. null → hiçbir sohbet açık değil.
  Future<void> setActiveRoom(String? roomId) async {
    if (currentUserId == null) return;
    try {
      await client.rpc('set_my_active_room', params: {'p_room': (roomId == null || roomId.isEmpty) ? null : roomId});
    } catch (_) {}
  }

  Future<void> setRoomPreferences(String roomId, {bool? muted, bool? pinned}) async {
    try {
      await client.rpc('set_room_preferences', params: {'p_room': roomId, 'p_muted': muted, 'p_pinned': pinned});
    } catch (_) {}
  }

  /// v0.9.0 N-B: etikete dokununca profil — kullanıcı adından kimlik (RLS: profiller okunabilir).
  Future<String?> fetchUserIdByUsername(String username) async {
    final u = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(u)) return null;
    try {
      final row = await client.from('profiles').select('id').ilike('username', u).limit(1).maybeSingle();
      return row?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// v0.9.0 N-C: "gönderimi kaydedenleri bildir" (varsayılan kapalı). null = okunamadı.
  Future<bool?> getSaveNotifications() async {
    try {
      final r = await client.rpc('get_my_save_notifications');
      return r == true;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setSaveNotifications(bool enabled) async {
    try {
      final r = await client.rpc('set_my_save_notifications', params: {'p_enabled': enabled});
      return r == true;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      // v0.9.3: çevrimdışı → bağlantı gelince uygulanır
      await writeOrQueue('rpc:set_my_save_notifications', {
        't': 'rpc',
        'fn': 'set_my_save_notifications',
        'params': {'p_enabled': enabled},
      });
      return true;
    }
  }

  /// v0.9.0 §6.4: sohbet bazlı bildirim ayarları (yalnız kendi katılım satırı; sunucu doğrular).
  Future<Map<String, dynamic>?> getRoomNotificationPrefs(String roomId) async {
    try {
      final res = await client.rpc('get_room_notification_prefs', params: {'p_room': roomId});
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (_) {
      return null;
    }
  }

  /// [muteMinutes]: null değiştirme, 0 kaldır, -1 süresiz. [preview]: null, 'inherit', full|sender|hidden.
  /// Başarısızsa istisna fırlatır (arayüz eski değere döner ve hata gösterir).
  Future<Map<String, dynamic>> setRoomNotificationPrefs(String roomId,
      {int? muteMinutes, String? preview, bool? vibrate}) async {
    final res = await client.rpc('set_room_notification_prefs', params: {
      'p_room': roomId,
      'p_mute_minutes': muteMinutes,
      'p_preview': preview,
      'p_vibrate': vibrate,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Stream<Map<String, dynamic>> watchRoom(String roomId) {
    return client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((rows) => rows.isNotEmpty ? rows.first : <String, dynamic>{});
  }

  // ---------------------------------------------------------------------------
  // MESAJLAR
  // ---------------------------------------------------------------------------
  /// v0.9.3: sohbet listesi önizlemesi için odanın son mesajı (çözülmüş). Önce cihazdaki
  /// önbellek (ağsız, anında), yoksa sunucudan tek satır (RLS) okunur.
  Future<JuzzioMessage?> lastMessageForPreview(String roomId, {DateTime? lastMessageAt}) async {
    Map<String, dynamic>? row;
    try {
      final cached = await _readCache(messageCacheName(roomId), messageLimit: 1);
      if (cached is List && cached.isNotEmpty && cached.last is Map) {
        final r = Map<String, dynamic>.from(cached.last as Map);
        final at = DateTime.tryParse((r['created_at'] ?? '').toString());
        // önbellek eskiyse (sonrasında yeni mesaj gelmişse) sunucudan oku
        final stale = lastMessageAt != null && (at == null || at.isBefore(lastMessageAt.subtract(const Duration(seconds: 1))));
        if (!stale) row = r;
      }
    } catch (_) {}
    if (row == null) {
      try {
        final r = await client.from('messages').select().eq('room_id', roomId).order('created_at', ascending: false).limit(1);
        if (r.isNotEmpty) row = Map<String, dynamic>.from(r.first);
      } catch (_) {}
    }
    if (row == null) return null;
    final list = await JuzzioE2ee.instance.decryptAll(visibleMessagesFromRows([row]));
    return list.isEmpty ? null : list.first;
  }

  /// v0.9.2: çevrimdışı okuma için oda başına saklanan son mesaj sayısı.
  static const int offlineMessageLimit = 300;

  /// Önbellek dosya adı (oda kimliği dışındaki karakterler atılır).
  static String messageCacheName(String roomId) => 'msgs_${roomId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}';

  /// Sunucu satırlarından ekrana uygun liste (süresi dolan mesajlar atılır).
  static List<JuzzioMessage> visibleMessagesFromRows(Iterable<Map<String, dynamic>> rows, {DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    return rows
        .where((r) {
          final exp = DateTime.tryParse(r['expires_at']?.toString() ?? '');
          return exp == null || exp.toUtc().isAfter(t);
        })
        .map(JuzzioMessage.fromMap)
        .toList();
  }

  /// v0.9.2 (WhatsApp benzeri çevrimdışı okuma): önce cihazdaki son mesajlar ANINDA gösterilir,
  /// sonra canlı akış bağlanır ve her güncellemede önbellek yenilenir. Bağlantı koparsa hata
  /// ekrana yansımaz; son liste kalır ve 5 sn arayla yeniden bağlanılır.
  /// Şifreli mesajlar diske SUNUCUDAKİ şifreli hâliyle yazılır; çözme her açılışta cihazda yapılır.
  ///
  /// v0.9.6 sayfalama: yalnız EN YENİ [limit] mesaj canlı izlenir (varsayılan 50). Kullanıcı
  /// "Daha eski mesajlar"a dokundukça pencere 50'şer büyür. Realtime yalnız açık sohbet için açılır.
  Stream<List<JuzzioMessage>> watchRoomMessages(String roomId, {int limit = 50}) {
    final cacheName = messageCacheName(roomId);
    return Stream<List<JuzzioMessage>>.multi((out) {
      StreamSubscription<List<Map<String, dynamic>>>? sub;
      Timer? retry;
      var closed = false;
      var gotNetwork = false;
      Future<void> chain = Future<void>.value();

      void emitRows(List<Map<String, dynamic>> rows) {
        chain = chain.then((_) async {
          final list = await JuzzioE2ee.instance.decryptAll(visibleMessagesFromRows(rows));
          if (!closed) out.add(list);
        }).catchError((_) {});
      }

      void connect() {
        if (closed) return;
        sub = client
            .from('messages')
            .stream(primaryKey: ['id'])
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(limit.clamp(20, 2000))
            .listen((desc) {
          gotNetwork = true;
          final rows = List<Map<String, dynamic>>.from(desc)
            ..sort((a, b) => '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}'));
          final tail = rows.length > offlineMessageLimit ? rows.sublist(rows.length - offlineMessageLimit) : rows;
          unawaited(_writeCache(cacheName, tail));
          emitRows(rows);
        }, onError: (Object _) {
          sub?.cancel();
          sub = null;
          if (closed) return;
          retry?.cancel();
          retry = Timer(const Duration(seconds: 5), connect);
        }, cancelOnError: true);
      }

      chain = chain.then((_) async {
        final cached = await _readCache(cacheName, messageLimit: limit);
        if (closed || gotNetwork || cached is! List) return;
        final rows = cached.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        if (rows.isEmpty) return;
        final list = await JuzzioE2ee.instance.decryptAll(visibleMessagesFromRows(rows));
        if (!closed && !gotNetwork) out.add(list);
      }).catchError((_) {});
      connect();

      out.onCancel = () {
        closed = true;
        retry?.cancel();
        sub?.cancel();
      };
    });
  }

  /// v0.9.0: Benzersiz istemci mesaj kimliği (idempotency anahtarı).
  static String newClientMsgId([String prefix = 'm']) {
    final r = math.Random.secure();
    final hex = List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '${prefix}_$hex';
  }

  /// Metin mesajı gönderir.
  ///
  /// v0.9.0 güvenlik kuralları (denetim D — fail-closed E2EE):
  ///  • Birebir sohbet uçtan uca şifrelenemezse (ağ hatası, anahtar hatası) mesaj
  ///    GÖNDERİLMEZ; [JuzzioE2eeRequiredException] fırlatılır. Düz metne sessiz düşüş yok.
  ///  • Karşı tarafın hiç şifreleme anahtarı yoksa (eski sürüm) düz metin YALNIZCA
  ///    [allowPlaintextFallback] = true (kullanıcının açık onayı) ile gönderilir ve
  ///    mesaj `metadata.security = plaintext_consented` olarak işaretlenir.
  ///  • Şifreli sohbette metin, şifrelemeden ÖNCE üçüncü taraf çeviriye gönderilmez;
  ///    yalnızca kullanıcı "E2EE mesajlarda çeviri" iznini açtıysa çevrilir.
  ///  • [clientMsgId] aynı gönderimin iki kez kaydedilmesini engeller (yeniden deneme,
  ///    bildirimden hızlı yanıt, çevrimdışı kuyruk). Yinelenen kayıt başarı sayılır.
  Future<void> sendTextMessage({
    required String text,
    String sourceLang = 'auto',
    String? senderName,
    String? targetRoomId,
    String? receiverId,
    String? replyToId,
    String? clientMsgId,
    bool allowPlaintextFallback = false,
  }) async {
    final uid = currentUserId;
    final clean = text.trim();
    if (uid == null || clean.isEmpty) return;
    final roomId = targetRoomId ??
        (receiverId != null && receiverId.isNotEmpty
            ? await ensureDirectRoomWithFriend(friendId: receiverId)
            : null);
    if (roomId == null || roomId.isEmpty) {
      throw JuzzioServiceException(_app.trEn('Sohbet bulunamadı.', 'Conversation not found.', 'Unterhaltung nicht gefunden.'));
    }

    final mySubLang = _app.subtitleLang;
    final targetLang = _defaultTargetLang;
    final isDirect = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (isDirect == null) {
      // Oda türü bilinmiyorsa şifresiz gönderim riski alınmaz
      throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
    }
    // Grup sohbetleri bu sürümde E2EE değildir (belgelenmiş); birebirde çeviri yalnız onayla
    final mayTranslate = !isDirect || _app.e2eeTranslationOptIn;
    // v1.0.0: çeviri gönderimi BEKLETMEZ — mesaj yazıldığı gibi hemen iletilir; çeviri
    // arka planda yapılır ve hazır olunca aynı mesajın altına eklenir (_translateAfterSend).
    const translated = '';

    Map<String, dynamic>? e2ee;
    var plaintextConsented = false;
    if (isDirect) {
      final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: clean, translated: translated);
      switch (outcome.status) {
        case JuzzioE2eeStatus.encrypted:
          e2ee = outcome.payload;
          break;
        case JuzzioE2eeStatus.peerKeyMissing:
          if (!allowPlaintextFallback) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.peerKeyMissing);
          plaintextConsented = true;
          break;
        case JuzzioE2eeStatus.group:
          break;
        case JuzzioE2eeStatus.unavailable:
          throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
      }
      if (e2ee == null && !plaintextConsented) {
        throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
      }
    }

    final msgId = (clientMsgId != null && RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(clientMsgId))
        ? clientMsgId
        : newClientMsgId();
    try {
      await client.from('messages').insert({
        'room_id': roomId,
        'sender_id': uid,
        if (senderName != null && senderName.isNotEmpty) 'sender_name': senderName,
        'message_type': 'text',
        'source_lang': sourceLang == 'auto' ? mySubLang : sourceLang,
        'target_lang': targetLang,
        'original_text': e2ee == null ? clean : '',
        'translated_text': e2ee == null ? translated : '',
        if (e2ee != null || plaintextConsented)
          'metadata': e2ee != null ? <String, dynamic>{'e2ee': e2ee} : <String, dynamic>{'security': 'plaintext_consented'},
        if (replyToId != null) 'reply_to_id': replyToId,
        'client_msg_id': msgId,
      });
    } on PostgrestException catch (e) {
      // Aynı istemci kimliğiyle daha önce kaydedilmiş → zaten gönderildi (idempotent)
      if (e.code == '23505' && (e.message.contains('client_msg') || (e.details?.toString() ?? '').contains('client_msg'))) {
        return;
      }
      throw JuzzioServiceException(_friendlyError(e));
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
    if (mayTranslate) {
      unawaited(_translateAfterSend(
        roomId: roomId,
        uid: uid,
        clientMsgId: msgId,
        text: clean,
        targetLang: targetLang,
        e2ee: e2ee,
      ));
    }
  }

  /// v1.0.0: gönderimden SONRA çeviri. Şifresiz (grup) mesajda `translated_text` güncellenir;
  /// uçtan uca şifreli mesajda çeviri AYRICA şifrelenip `metadata.e2ee_tr` olarak eklenir
  /// (sunucu düz metni hiç görmez; içerik/`e2ee` değişmediği için düzenleme sayılmaz).
  /// Hata sessizdir: alıcı cihaz gerekirse kendi çevirisini yapar.
  Future<void> _translateAfterSend({
    required String roomId,
    required String uid,
    required String clientMsgId,
    required String text,
    required String targetLang,
    Map<String, dynamic>? e2ee,
  }) async {
    try {
      final tr = (await translateText(text: text, sourceLang: 'auto', targetLang: targetLang)).trim();
      if (tr.isEmpty || tr == text) return;
      if (e2ee != null) {
        final o = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: tr, translated: '');
        if (o.status != JuzzioE2eeStatus.encrypted || o.payload == null) return;
        await client
            .from('messages')
            .update({'metadata': <String, dynamic>{'e2ee': e2ee, 'e2ee_tr': o.payload}})
            .eq('client_msg_id', clientMsgId)
            .eq('sender_id', uid);
      } else {
        await client.from('messages').update({'translated_text': tr}).eq('client_msg_id', clientMsgId).eq('sender_id', uid);
      }
    } catch (_) {}
  }

  /// v0.9.0 §4.5: kendi metin mesajını düzenler (sunucu kuralı: 15 dk, ≤10 kez, yalnız gönderen).
  /// Birebir sohbette yeni metin YENİDEN uçtan uca şifrelenir; şifrelenemezse düzenleme yapılmaz
  /// (fail-closed, düz metne düşüş yok). Eski sürüm sunucuda geçmişe olduğu gibi (şifreli) taşınır.
  /// v0.9.6: mesajı sabitle / kaldır (sunucu yetkiyi denetler; sohbet başına en fazla 5).
  Future<void> pinMessage(String messageId, bool pinned) async {
    await client.rpc('pin_message', params: {'p_message': messageId, 'p_pinned': pinned});
  }

  /// v0.9.6: sohbetin sabit mesajları (en yeni sabitlenen önce), cihazda çözülmüş.
  Future<List<JuzzioMessage>> fetchPinnedMessages(String roomId) async {
    try {
      final res = await client.rpc('room_pinned_messages', params: {'p_room': roomId});
      final rows = [for (final r in (res is List ? res : const [])) Map<String, dynamic>.from(r as Map)];
      return await JuzzioE2ee.instance.decryptAll(visibleMessagesFromRows(rows));
    } catch (_) {
      return const [];
    }
  }

  Future<void> editTextMessage({required JuzzioMessage message, required String newText}) async {
    final uid = currentUserId;
    final clean = newText.trim();
    if (uid == null || message.senderId != uid) throw JuzzioServiceException(JuzzioAppController.instance.trEn('Bu mesajı düzenleyemezsin.', 'You can\'t edit this message.', 'Du kannst diese Nachricht nicht bearbeiten.'));
    if (clean.isEmpty) throw JuzzioServiceException(JuzzioAppController.instance.trEn('Mesaj boş olamaz.', 'Message can\'t be empty.', 'Nachricht darf nicht leer sein.'));
    final wasEncrypted = message.metadata['e2ee'] is Map;
    final Map<String, dynamic> patch;
    if (wasEncrypted) {
      final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(message.roomId, text: clean, translated: '');
      if (outcome.status != JuzzioE2eeStatus.encrypted || outcome.payload == null) {
        throw JuzzioE2eeRequiredException(outcome.status);
      }
      patch = {
        'original_text': '',
        'translated_text': '',
        'metadata': {...message.metadata, 'e2ee': outcome.payload},
      };
    } else {
      // v0.9.6: grup mesajı düzenlenince eski çeviri geçersiz olur → yeni metin hemen yeniden çevrilir
      final tl = message.targetLang.isNotEmpty ? message.targetLang : _defaultTargetLang;
      var translated = '';
      try {
        translated = await translateText(text: clean, sourceLang: 'auto', targetLang: tl);
      } catch (_) {}
      patch = {'original_text': clean, 'translated_text': translated == clean ? '' : translated};
    }
    try {
      final rows = await client.from('messages').update(patch).eq('id', message.id).eq('sender_id', uid).select('id');
      if ((rows as List).isEmpty) throw JuzzioServiceException(JuzzioAppController.instance.trEn('Mesaj düzenlenemedi.', 'Message could not be edited.', 'Nachricht konnte nicht bearbeitet werden.'));
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('edit_window_expired')) throw JuzzioServiceException(JuzzioAppController.instance.trEn('Mesajlar yalnızca gönderimden sonraki 15 dakika içinde düzenlenebilir.', 'Messages can only be edited within 15 minutes of sending.', 'Nachrichten können nur innerhalb von 15 Minuten bearbeitet werden.'));
      if (m.contains('edit_limit_reached')) throw JuzzioServiceException(JuzzioAppController.instance.trEn('Bu mesaj en fazla 10 kez düzenlenebilir.', 'A message can be edited at most 10 times.', 'Eine Nachricht kann höchstens 10-mal bearbeitet werden.'));
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  /// v0.9.0 §4.5: düzenleme geçmişi (yeniden eskiye). Şifreli sürümler CİHAZDA çözülür.
  Future<List<({String text, DateTime editedAt})>> fetchEditHistory(JuzzioMessage message) async {
    final rows = await client
        .from('message_edits')
        .select('id, prev_text, prev_metadata, edited_at')
        .eq('message_id', message.id)
        .order('edited_at', ascending: false);
    final out = <({String text, DateTime editedAt})>[];
    for (final r in (rows as List).whereType<Map>()) {
      final meta = r['prev_metadata'] is Map ? Map<String, dynamic>.from(r['prev_metadata'] as Map) : <String, dynamic>{};
      final at = DateTime.tryParse(r['edited_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      var text = (r['prev_text'] ?? '').toString();
      if (meta['e2ee'] is Map) {
        final prev = JuzzioMessage(
          id: 'edit_${r['id']}',
          roomId: message.roomId,
          senderId: message.senderId,
          messageType: 'text',
          sourceLang: message.sourceLang,
          targetLang: message.targetLang,
          originalText: '',
          translatedText: '',
          metadata: meta,
          createdAt: message.createdAt,
        );
        text = await JuzzioE2ee.instance.decryptPreviewText(prev) ??
            '🔒 ${JuzzioAppController.instance.trEn('Bu sürüm bu cihazda çözülemedi', 'This version could not be decrypted on this device', 'Diese Version konnte auf diesem Gerät nicht entschlüsselt werden')}';
      }
      out.add((text: text, editedAt: at));
    }
    return out;
  }

  Future<void> sendGroupTextMessage({required String roomId, required String text, required String senderName}) {
    return sendTextMessage(text: text, senderName: senderName, targetRoomId: roomId);
  }

  String _storageExt(String path, {required bool isVideo}) {
    final raw = path.split('.').last.toLowerCase();
    if (isVideo) return ['mp4', 'mov', 'webm', 'mkv', '3gp'].contains(raw) ? raw : 'mp4';
    return ['png', 'webp', 'jpg', 'jpeg', 'gif', 'heic'].contains(raw) ? raw : 'jpg';
  }

  String _mimeFor(String ext, {required bool isVideo}) {
    if (isVideo) {
      if (ext == 'mov') return 'video/quicktime';
      if (ext == 'webm') return 'video/webm';
      return 'video/mp4';
    }
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Sohbete fotoğraf veya video gönderir (chat-media/<uid>/<oda>/...).
  Future<void> sendMediaMessage({
    required String roomId,
    required File file,
    required bool isVideo,
    String caption = '',
    bool viewOnce = false,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    if (!file.existsSync()) {
      throw JuzzioServiceException(_app.trEn('Dosya okunamadı.', 'File could not be read.', 'Datei konnte nicht gelesen werden.'));
    }
    final size = file.lengthSync();
    if (size > (isVideo ? 100 : 20) * 1024 * 1024) {
      throw JuzzioServiceException(_app.trEn(
        isVideo ? 'Video en fazla 100 MB olabilir.' : 'Fotoğraf en fazla 20 MB olabilir.',
        isVideo ? 'Video must be under 100 MB.' : 'Photo must be under 20 MB.',
        isVideo ? 'Das Video darf höchstens 100 MB groß sein.' : 'Das Foto darf höchstens 20 MB groß sein.',
      ));
    }
    final ext = _storageExt(file.path, isVideo: isVideo);
    // G23/G24: birebir sohbette fotoğraf uçtan uca şifrelenir (fail-closed). Grup sohbetleri metinle
    // aynı kuralı izler (E2EE yok). Video şimdilik bellek sınırı nedeniyle şifresiz kalır (belgelendi).
    final direct = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (direct == null) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
    if (!isVideo && direct) {
      await _sendEncryptedImage(uid: uid, roomId: roomId, file: file, ext: ext, caption: caption.trim(), viewOnce: viewOnce);
      return;
    }
    // v0.9.6: birebir sohbette video da uçtan uca şifrelenir (önceden şifresiz gidiyordu)
    if (isVideo && direct) {
      if (size > juzzioEncryptedVideoMaxBytes) {
        throw JuzzioServiceException(_app.trEn('Birebir sohbette video en fazla 40 MB olabilir (uçtan uca şifreleme için).',
            'In 1:1 chats videos must be under 40 MB (for end-to-end encryption).', 'In Einzelchats max. 40 MB (Verschlüsselung).'));
      }
      final (url, path, payload) = await _sealAndUpload(uid: uid, roomId: roomId, bytes: await file.readAsBytes(), mime: _mimeFor(ext, isVideo: true), text: caption.trim());
      try {
        await client.from('messages').insert({
          'room_id': roomId,
          'sender_id': uid,
          'message_type': 'video',
          'source_lang': _app.subtitleLang,
          'target_lang': _defaultTargetLang,
          'original_text': '',
          'translated_text': '',
          'video_url': url,
          'metadata': <String, dynamic>{'e2ee': payload, 'media_e2ee': 1},
          if (viewOnce) 'is_view_once': true,
        });
      } catch (e) {
        await _removeChatMedia(path);
        rethrow;
      }
      return;
    }
    final path = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await client.storage.from(JuzzioConfig.chatMediaBucket).upload(
            path,
            file,
            fileOptions: FileOptions(contentType: _mimeFor(ext, isVideo: isVideo), upsert: false),
          );
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Medya yüklenemedi: ${_friendlyError(e)}', 'Upload failed: ${_friendlyError(e)}', 'Hochladen fehlgeschlagen: ${_friendlyError(e)}'));
    }
    final url = client.storage.from(JuzzioConfig.chatMediaBucket).getPublicUrl(path);
    final cleanCaption = caption.trim();
    final translated = cleanCaption.isEmpty
        ? ''
        : await translateText(text: cleanCaption, sourceLang: 'auto', targetLang: _defaultTargetLang);
    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': uid,
      'message_type': isVideo ? 'video' : 'image',
      'source_lang': _app.subtitleLang,
      'target_lang': _defaultTargetLang,
      'original_text': cleanCaption,
      'translated_text': translated,
      if (isVideo) 'video_url': url else 'image_url': url,
      if (viewOnce) 'is_view_once': true,
    });
  }

  DateTime? _streakTouchedAt;

  /// v0.9.5: günlük seriyi günde bir kez işaretler (sunucu tarihi, kullanıcının saat dilimi).
  Future<void> touchDailyStreak() async {
    if (currentUserId == null) return;
    final last = _streakTouchedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 3)) return;
    _streakTouchedAt = DateTime.now();
    try {
      await client.rpc('touch_daily_streak', params: {'p_tz': DateTime.now().timeZoneName.contains('/') ? DateTime.now().timeZoneName : 'Europe/Istanbul'});
    } catch (_) {}
  }

  /// v0.9.4: sohbete belge/dosya gönderir (PDF, ZIP, DOCX …, en fazla 25 MB).
  ///  Birebir sohbette dosya ve DOSYA ADI uçtan uca şifrelenir (fail-closed; şifresiz yedek yok).
  ///  Grup sohbetlerinde dosya chat-media kovasına özel olarak yüklenir.
  Future<void> sendDocumentMessage({required String roomId, required File file, required String fileName}) async {
    final uid = currentUserId;
    if (uid == null) return;
    if (!file.existsSync()) {
      throw JuzzioServiceException(_app.trEn('Dosya okunamadı.', 'File could not be read.', 'Datei konnte nicht gelesen werden.'));
    }
    final size = file.lengthSync();
    if (size <= 0 || size > juzzioDocumentMaxBytes) {
      throw JuzzioServiceException(_app.trEn('Dosya en fazla 25 MB olabilir.', 'Files must be under 25 MB.', 'Dateien dürfen höchstens 25 MB groß sein.'));
    }
    final name = juzzioSafeFileName(fileName);
    final mime = juzzioDocumentMime(name);
    final isDirect = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (isDirect == null) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
    final bucket = client.storage.from(JuzzioConfig.chatMediaBucket);
    if (isDirect) {
      final sealed = await JuzzioMediaCrypto.seal(await file.readAsBytes(), mime: mime);
      final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: name, translated: '', media: sealed.key.toJson());
      if (outcome.status != JuzzioE2eeStatus.encrypted || outcome.payload == null) {
        throw JuzzioE2eeRequiredException(
            outcome.status == JuzzioE2eeStatus.peerKeyMissing ? JuzzioE2eeStatus.peerKeyMissing : JuzzioE2eeStatus.unavailable);
      }
      final path = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.jenc';
      try {
        await bucket.uploadBinary(path, sealed.cipher, fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: false));
      } catch (e) {
        throw JuzzioServiceException(_app.trEn('Dosya yüklenemedi: ${_friendlyError(e)}', 'Upload failed: ${_friendlyError(e)}', 'Hochladen fehlgeschlagen: ${_friendlyError(e)}'));
      }
      try {
        await client.from('messages').insert({
          'room_id': roomId,
          'sender_id': uid,
          'message_type': 'document',
          'source_lang': _app.subtitleLang,
          'target_lang': _defaultTargetLang,
          'original_text': '',
          'translated_text': '',
          'document_url': bucket.getPublicUrl(path),
          'document_name': '', // ad şifreli yükte; sunucuda düz metin tutulmaz
          'document_size': size,
          'metadata': <String, dynamic>{'e2ee': outcome.payload, 'media_e2ee': 1},
        });
      } catch (e) {
        try {
          await bucket.remove([path]);
        } catch (_) {}
        rethrow;
      }
      return;
    }
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'bin';
    final path = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await bucket.upload(path, file, fileOptions: FileOptions(contentType: mime, upsert: false));
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Dosya yüklenemedi: ${_friendlyError(e)}', 'Upload failed: ${_friendlyError(e)}', 'Hochladen fehlgeschlagen: ${_friendlyError(e)}'));
    }
    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': uid,
      'message_type': 'document',
      'source_lang': _app.subtitleLang,
      'target_lang': _defaultTargetLang,
      'original_text': '',
      'translated_text': '',
      'document_url': bucket.getPublicUrl(path),
      'document_name': name,
      'document_size': size,
    });
  }

  /// v0.9.6: birebir sohbet medyasını uçtan uca şifreleyip chat-media'ya .jenc olarak yükler.
  /// Dönen: (adres, yol, e2ee yükü). Şifreleme yapılamazsa JuzzioE2eeRequiredException (fail-closed).
  Future<(String, String, Map<String, dynamic>)> _sealAndUpload({
    required String uid,
    required String roomId,
    required List<int> bytes,
    required String mime,
    String text = '',
  }) async {
    final sealed = await JuzzioMediaCrypto.seal(bytes, mime: mime);
    final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: text, translated: '', media: sealed.key.toJson());
    if (outcome.status != JuzzioE2eeStatus.encrypted || outcome.payload == null) {
      throw JuzzioE2eeRequiredException(
          outcome.status == JuzzioE2eeStatus.peerKeyMissing ? JuzzioE2eeStatus.peerKeyMissing : JuzzioE2eeStatus.unavailable);
    }
    final path = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.jenc';
    final bucket = client.storage.from(JuzzioConfig.chatMediaBucket);
    try {
      await bucket.uploadBinary(path, sealed.cipher, fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: false));
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Medya yüklenemedi: ${_friendlyError(e)}', 'Upload failed: ${_friendlyError(e)}', 'Hochladen fehlgeschlagen: ${_friendlyError(e)}'));
    }
    return (bucket.getPublicUrl(path), path, Map<String, dynamic>.from(outcome.payload!));
  }

  Future<void> _removeChatMedia(String path) async {
    try {
      await client.storage.from(JuzzioConfig.chatMediaBucket).remove([path]);
    } catch (_) {}
  }

  Future<void> _sendEncryptedImage({
    required String uid,
    required String roomId,
    required File file,
    required String ext,
    required String caption,
    bool viewOnce = false,
  }) async {
    final sealed = await JuzzioMediaCrypto.seal(await file.readAsBytes(), mime: _mimeFor(ext, isVideo: false));
    final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: caption, translated: '', media: sealed.key.toJson());
    if (outcome.status != JuzzioE2eeStatus.encrypted || outcome.payload == null) {
      // Anahtar yoksa / şifreleme yapılamıyorsa fotoğraf GÖNDERİLMEZ (şifresiz yedek yok)
      throw JuzzioE2eeRequiredException(
          outcome.status == JuzzioE2eeStatus.peerKeyMissing ? JuzzioE2eeStatus.peerKeyMissing : JuzzioE2eeStatus.unavailable);
    }
    final path = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.jenc';
    final bucket = client.storage.from(JuzzioConfig.chatMediaBucket);
    try {
      await bucket.uploadBinary(path, sealed.cipher,
          fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: false));
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Medya yüklenemedi: ${_friendlyError(e)}', 'Upload failed: ${_friendlyError(e)}', 'Hochladen fehlgeschlagen: ${_friendlyError(e)}'));
    }
    try {
      await client.from('messages').insert({
        'room_id': roomId,
        'sender_id': uid,
        'message_type': 'image',
        'source_lang': _app.subtitleLang,
        'target_lang': _defaultTargetLang,
        'original_text': '',
        'translated_text': '',
        'image_url': bucket.getPublicUrl(path),
        'metadata': <String, dynamic>{'e2ee': outcome.payload, 'media_e2ee': 1},
        if (viewOnce) 'is_view_once': true,
      });
    } catch (e) {
      try {
        await bucket.remove([path]); // mesaj yazılamadıysa yetim şifreli dosya bırakılmaz
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> sendVoiceNote({
    required File audioFile,
    required int durationMs,
    required String sourceLang,
    required List<double> waveformPeaks,
    String? targetRoomId,
  }) async {
    final uid = currentUserId;
    final roomId = targetRoomId;
    if (uid == null || roomId == null || roomId.isEmpty) return;

    final mySubLang = _app.subtitleLang;
    final targetLang = _defaultTargetLang;
    final storagePath = '$uid/$roomId/${DateTime.now().millisecondsSinceEpoch}.m4a';

    // v0.9.6: birebir sohbette sesli mesaj uçtan uca şifrelenir (önceden ses ve döküm şifresizdi)
    final direct = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (direct == null) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
    if (direct) {
      await _sendEncryptedVoice(uid: uid, roomId: roomId, audioFile: audioFile, durationMs: durationMs,
          waveformPeaks: waveformPeaks, plainPath: storagePath, sourceLang: mySubLang, targetLang: targetLang);
      return;
    }

    await client.storage.from(JuzzioConfig.voiceNoteBucket).upload(
          storagePath,
          audioFile,
          fileOptions: const FileOptions(contentType: 'audio/mp4', upsert: false),
        );
    final publicUrl = client.storage.from(JuzzioConfig.voiceNoteBucket).getPublicUrl(storagePath);

    String transcriptOriginal = '';
    String transcriptTranslated = '';
    double confidence = 0.0;
    try {
      final res = await client.functions.invoke('translate-bridge', body: {
        'mode': 'voice_note',
        // v0.9.0: sunucu yolu veritabanından ve oda üyeliğinden doğrular; URL yetki değildir
        'storagePath': storagePath,
        'audioUrl': publicUrl,
        'sourceLang': mySubLang,
        'targetLang': targetLang,
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is Map) {
        transcriptOriginal = (data['originalText'] ?? '').toString().trim();
        transcriptTranslated = (data['translatedText'] ?? '').toString().trim();
        if (isTranslationProviderError(transcriptTranslated)) transcriptTranslated = '';
        confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    const voicePlaceholders = {'tr': '🎤 Sesli Mesaj', 'en': '🎤 Voice message', 'de': '🎤 Sprachnachricht'};
    final senderPlaceholder = voicePlaceholders[mySubLang] ?? voicePlaceholders['en']!;
    if (transcriptOriginal.isEmpty) transcriptOriginal = senderPlaceholder;
    if (transcriptTranslated.isEmpty) {
      transcriptTranslated = transcriptOriginal == senderPlaceholder
          ? (voicePlaceholders[targetLang] ?? await translateText(text: voicePlaceholders['en']!, targetLang: targetLang))
          : await translateText(text: transcriptOriginal, targetLang: targetLang);
    }

    final insertedMsg = await client
        .from('messages')
        .insert({
          'room_id': roomId,
          'sender_id': uid,
          'message_type': 'voice',
          'source_lang': mySubLang,
          'target_lang': targetLang,
          'original_text': transcriptOriginal,
          'translated_text': transcriptTranslated,
          'audio_url': publicUrl,
          'audio_duration_ms': durationMs,
          'waveform_peaks': waveformPeaks,
        })
        .select('id')
        .single();

    try {
      await client.from('voice_notes').insert({
        'message_id': insertedMsg['id'],
        'room_id': roomId,
        'sender_id': uid,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'mime_type': 'audio/mp4',
        'duration_ms': durationMs,
        'source_lang': mySubLang,
        'transcript_original': transcriptOriginal,
        'transcript_translated': transcriptTranslated,
        'waveform_data': waveformPeaks,
        'deepgram_confidence': confidence,
      });
    } catch (_) {}
  }

  Future<void> _sendEncryptedVoice({
    required String uid,
    required String roomId,
    required File audioFile,
    required int durationMs,
    required List<double> waveformPeaks,
    required String plainPath,
    required String sourceLang,
    required String targetLang,
  }) async {
    // Döküm (yazıya çevirme) yalnız kullanıcı birebir çeviriye izin verdiyse yapılır: ses GEÇİCİ
    // olarak yüklenir, döküm alınır ve geçici dosya hemen silinir. Döküm şifreli yükün içindedir.
    var transcript = '';
    if (_app.e2eeTranslationOptIn) {
      final voice = client.storage.from(JuzzioConfig.voiceNoteBucket);
      try {
        await voice.upload(plainPath, audioFile, fileOptions: const FileOptions(contentType: 'audio/mp4', upsert: false));
        final res = await client.functions.invoke('translate-bridge', body: {
          'mode': 'voice_note',
          'storagePath': plainPath,
          'audioUrl': voice.getPublicUrl(plainPath),
          'sourceLang': sourceLang,
          'targetLang': targetLang,
        });
        final data = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (data is Map) transcript = (data['originalText'] ?? '').toString().trim();
        if (isTranslationProviderError(transcript)) transcript = '';
      } catch (_) {
      } finally {
        try {
          await voice.remove([plainPath]);
        } catch (_) {}
      }
    }
    final (url, path, payload) = await _sealAndUpload(uid: uid, roomId: roomId, bytes: await audioFile.readAsBytes(), mime: 'audio/mp4', text: transcript);
    try {
      await client.from('messages').insert({
        'room_id': roomId,
        'sender_id': uid,
        'message_type': 'voice',
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'original_text': '',
        'translated_text': '',
        'audio_url': url,
        'audio_duration_ms': durationMs,
        'waveform_peaks': waveformPeaks,
        'metadata': <String, dynamic>{'e2ee': payload, 'media_e2ee': 1},
      });
    } catch (e) {
      await _removeChatMedia(path);
      rethrow;
    }
  }

  /// Tepki ekler/kaldırır; sunucudaki güncel tepki haritasını döndürür (hata: null).
  Future<Map<String, String>?> toggleSingleMessageReaction({required JuzzioMessage message, required String emoji}) async {
    try {
      final res = await client.rpc('toggle_message_reaction', params: {'p_message': message.id, 'p_emoji': emoji});
      final data = res is String ? jsonDecode(res) : res;
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    return null;
  }

  /// Kendi mesajını herkes için siler (yumuşak silme). Başkasının mesajı yalnızca
  /// yerelde gizlenir; false döner.
  Future<bool> deleteMessageById(String messageId, {String? senderId}) async {
    final uid = currentUserId;
    if (uid == null) return false;
    if (senderId != null && senderId != uid) return false;
    try {
      final rows = await client
          .from('messages')
          .update({
            'is_deleted': true,
            'original_text': '',
            'translated_text': '',
            'metadata': <String, dynamic>{},
            'image_url': null,
            'video_url': null,
            'audio_url': null,
            'edited_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', messageId)
          .eq('sender_id', uid)
          .select('id');
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sohbeti yalnızca kendi tarafında siler (karşı tarafın geçmişi korunur).
  Future<void> deleteRoomMessages(String roomId) async {
    try {
      await client.rpc('leave_room', params: {'p_room': roomId});
    } catch (_) {}
  }

  Future<void> clearRoomHistoryForMe(String roomId) async {
    try {
      await client.rpc('clear_room_history_for_me', params: {'p_room': roomId});
    } catch (_) {}
  }

  /// Ayarlar → "Tüm sohbet geçmişini temizle": tüm sohbetlerin geçmişini yalnızca benim için temizler.
  Future<void> clearAllMessagesInMainRoom() async {
    final convs = await fetchMyConversations();
    for (final c in convs) {
      await clearRoomHistoryForMe(c.roomId);
    }
  }

  // ---------------------------------------------------------------------------
  // ARKADAŞLIK
  // ---------------------------------------------------------------------------
  /// 'pending' veya (karşı taraf zaten istek attıysa) 'accepted' döner.
  Future<String> sendFriendRequest({required JuzzioUserProfile myProfile, required JuzzioUserProfile targetUser}) async {
    try {
      final res = await client.rpc('send_friend_request', params: {'p_target': targetUser.id});
      return res?.toString() ?? 'pending';
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<void> respondToFriendRequest({required String friendshipId, required bool accept}) async {
    try {
      await client.rpc('respond_friend_request', params: {'p_friendship': friendshipId, 'p_accept': accept});
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  /// Kabul edilmiş arkadaşların profilleri.
  Future<List<JuzzioUserProfile>> fetchAcceptedFriendProfiles() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    try {
      final rows = await client
          .from('friendships')
          .select('requester_id, receiver_id')
          .eq('status', 'accepted')
          .or('requester_id.eq.$uid,receiver_id.eq.$uid');
      final ids = <String>{};
      for (final r in (rows as List)) {
        final m = r as Map<String, dynamic>;
        final a = (m['requester_id'] ?? '').toString();
        final b = (m['receiver_id'] ?? '').toString();
        ids.add(a == uid ? b : a);
      }
      ids.removeWhere((e) => e.isEmpty);
      if (ids.isEmpty) return const [];
      final profiles = await fetchProfilesByIds(ids);
      profiles.sort((x, y) => x.displayName.toLowerCase().compareTo(y.displayName.toLowerCase()));
      return profiles;
    } catch (_) {
      return const [];
    }
  }

  /// Birebir sohbet odası (yoksa oluşturur).
  Future<String> getOrCreateDirectRoomId(String otherUserId) => ensureDirectRoomWithFriend(friendId: otherUserId);

  /// Profil kartı arka planı vb. herkese açık görseli yükler, adresini döndürür.
  /// v0.9.0: Geri bildirim ekran görüntüsü ÖZEL bucket'a (chat-media/<uid>/feedback/…)
  /// yüklenir; yalnızca sahibi ve 'feedback.manage' izinli personel görebilir. Önceden
  /// herkese açık avatars bucket'ına gidiyor ve kalıcı açık adres üretiyordu.
  Future<String> uploadFeedbackImage(File file) async {
    final uid = currentUserId;
    if (uid == null) throw JuzzioServiceException(_app.t('err_session'));
    if (file.existsSync()) file = await juzzioCompressImageForUpload(file);
    if (!file.existsSync() || file.lengthSync() > 5 * 1024 * 1024) {
      throw JuzzioServiceException(_app.trEn('Görsel 5 MB\'tan küçük olmalı.', 'The image must be under 5 MB.', 'Das Bild muss kleiner als 5 MB sein.'));
    }
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = const ['png', 'webp', 'jpg', 'jpeg'].contains(ext) ? ext : 'jpg';
    final mime = safeExt == 'png' ? 'image/png' : (safeExt == 'webp' ? 'image/webp' : 'image/jpeg');
    final path = '$uid/feedback/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    try {
      await client.storage.from(JuzzioConfig.chatMediaBucket).upload(
            path,
            file,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      // Kalıcı kimlik adresi; görüntülerken JuzzioMediaUrl ile imzalanır
      return client.storage.from(JuzzioConfig.chatMediaBucket).getPublicUrl(path);
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<String> uploadPublicImage(File file, {String prefix = 'img'}) async {
    final uid = currentUserId;
    if (uid == null) throw JuzzioServiceException(_app.t('err_session'));
    // v0.9.4: avatars kovası 5 MB — yüklemeden önce ≤1600 px JPEG'e sıkıştır
    if (file.existsSync()) file = await juzzioCompressImageForUpload(file);
    if (!file.existsSync() || file.lengthSync() > 5 * 1024 * 1024) {
      throw JuzzioServiceException(_app.trEn('Görsel 5 MB\'tan küçük olmalı.', 'The image must be under 5 MB.', 'Das Bild muss kleiner als 5 MB sein.'));
    }
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = const ['png', 'webp', 'jpg', 'jpeg'].contains(ext) ? ext : 'jpg';
    final mime = safeExt == 'png' ? 'image/png' : (safeExt == 'webp' ? 'image/webp' : 'image/jpeg');
    final path = '$uid/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    try {
      await client.storage.from(JuzzioConfig.avatarBucket).upload(
            path,
            file,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
      return client.storage.from(JuzzioConfig.avatarBucket).getPublicUrl(path);
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<void> removeFriend(String otherUserId) async {
    await client.rpc('remove_friend', params: {'p_other': otherUserId});
  }

  /// Yalnızca kullanıcının dahil olduğu arkadaşlık kayıtları (RLS).
  Stream<List<JuzzioFriendship>> watchFriendships() {
    final uid = currentUserId;
    return client
        .from('friendships')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map(JuzzioFriendship.fromMap)
            .where((f) => uid != null && (f.requesterId == uid || f.receiverId == uid))
            .toList());
  }

  // ---------------------------------------------------------------------------
  // HİKÂYELER
  // ---------------------------------------------------------------------------
  Future<JuzzioStory> uploadAndCreateStory({
    required JuzzioUserProfile author,
    required String mediaType,
    File? mediaFile,
    String caption = '',
    String overlayText = '',
    String bgColorHex = '#161618',
    int videoDurationSec = 15,
    String filterPreset = 'none',
    String visibility = 'friends',
    int trimStartMs = 0,
    int trimEndMs = 0,
    double playbackSpeed = 1.0,
    bool isMuted = false,
    String musicUrl = '',
    String musicTitle = '',
    int musicStartSec = 0,
    String overlayStyle = 'classic',
    String overlayColor = '#FFFFFF',
    List<JuzzioStorySticker> stickers = const <JuzzioStorySticker>[],
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw JuzzioServiceException(_app.trEn('Oturum açık değil.', 'Not signed in.', 'Nicht angemeldet.'));
    }
    String? publicMediaUrl;
    final effectiveType = mediaFile == null ? 'text' : mediaType;

    if (mediaFile != null) {
      if (!mediaFile.existsSync()) {
        throw JuzzioServiceException(_app.trEn('Seçilen dosya okunamadı.', 'Selected file could not be read.', 'Die ausgewählte Datei konnte nicht gelesen werden.'));
      }
      final isVideo = effectiveType == 'video';
      final size = mediaFile.lengthSync();
      if (size > (isVideo ? 100 : 20) * 1024 * 1024) {
        throw JuzzioServiceException(_app.trEn(
          isVideo ? 'Hikâye videosu en fazla 100 MB olabilir.' : 'Hikâye görseli en fazla 20 MB olabilir.',
          isVideo ? 'Story video must be under 100 MB.' : 'Story image must be under 20 MB.',
          isVideo ? 'Das Story-Video darf höchstens 100 MB groß sein.' : 'Das Story-Bild darf höchstens 20 MB groß sein.',
        ));
      }
      final ext = _storageExt(mediaFile.path, isVideo: isVideo);
      final path = '$uid/story_${DateTime.now().millisecondsSinceEpoch}.$ext';
      try {
        await client.storage.from(JuzzioConfig.storiesBucket).upload(
              path,
              mediaFile,
              fileOptions: FileOptions(contentType: _mimeFor(ext, isVideo: isVideo), upsert: false),
            );
      } catch (e) {
        throw JuzzioServiceException(
          _app.trEn('Hikâye medyası yüklenemedi: ${_friendlyError(e)}', 'Story upload failed: ${_friendlyError(e)}', 'Story-Upload fehlgeschlagen: ${_friendlyError(e)}'),
        );
      }
      publicMediaUrl = client.storage.from(JuzzioConfig.storiesBucket).getPublicUrl(path);
    }

    final targetLang = _defaultTargetLang;
    final translatedCaption =
        caption.trim().isEmpty ? '' : await translateText(text: caption.trim(), targetLang: targetLang);
    final translatedOverlay =
        overlayText.trim().isEmpty ? '' : await translateText(text: overlayText.trim(), targetLang: targetLang);

    try {
      final inserted = await client
          .from('stories')
          .insert({
            'user_id': uid,
            'username': author.username,
            'display_name': author.displayName,
            'user_avatar': author.avatarUrl,
            'media_type': effectiveType,
            'media_url': publicMediaUrl,
            'bg_color_hex': bgColorHex,
            'caption_original': caption.trim(),
            'caption_translated': translatedCaption,
            'overlay_text_original': overlayText.trim(),
            'overlay_text_translated': translatedOverlay,
            'video_duration_sec': videoDurationSec.clamp(3, 60),
            'filter_preset': filterPreset,
            'visibility': visibility,
            'source_lang': _app.subtitleLang,
            if (effectiveType == 'video') ...{
              'trim_start_ms': trimStartMs < 0 ? 0 : trimStartMs,
              'trim_end_ms': trimEndMs < 0 ? 0 : trimEndMs,
              'playback_speed': playbackSpeed.clamp(0.25, 3.0),
              'is_muted': isMuted,
            },
            if (musicUrl.trim().isNotEmpty) ...{
              'music_url': musicUrl.trim(),
              'music_title': musicTitle.trim(),
              'music_start_sec': musicStartSec < 0 ? 0 : musicStartSec,
            },
            if (overlayText.trim().isNotEmpty) ...{
              'overlay_style': overlayStyle,
              'overlay_color': overlayColor,
            },
            if (stickers.isNotEmpty) 'stickers_json': stickers.take(20).map((e) => e.toMap()).toList(),
          })
          .select()
          .single();
      return JuzzioStory.fromMap(inserted);
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Hikâye paylaşılamadı: ${_friendlyError(e)}', 'Could not share story: ${_friendlyError(e)}', 'Story konnte nicht geteilt werden: ${_friendlyError(e)}'));
    }
  }

  /// v0.9.3: Admin → Juzzio Story: "Juzzio Official" adına herkese görünen hikâye paylaşır.
  Future<String> postOfficialStory({required File mediaFile, required bool isVideo, String caption = '', int videoDurationSec = 15, int hours = 24}) async {
    final uid = currentUserId;
    if (uid == null) throw JuzzioServiceException(_app.trEn('Oturum açık değil.', 'Not signed in.', 'Nicht angemeldet.'));
    if (!mediaFile.existsSync()) {
      throw JuzzioServiceException(_app.trEn('Seçilen dosya okunamadı.', 'Selected file could not be read.', 'Die ausgewählte Datei konnte nicht gelesen werden.'));
    }
    final ext = _storageExt(mediaFile.path, isVideo: isVideo);
    final path = '$uid/official_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await client.storage.from(JuzzioConfig.storiesBucket).upload(
            path,
            mediaFile,
            fileOptions: FileOptions(contentType: _mimeFor(ext, isVideo: isVideo), upsert: false),
          );
      final url = client.storage.from(JuzzioConfig.storiesBucket).getPublicUrl(path);
      final id = await client.rpc('admin_post_official_story', params: {
        'p_media_type': isVideo ? 'video' : 'image',
        'p_media_url': url,
        'p_caption': caption.trim(),
        'p_video_duration_sec': videoDurationSec.clamp(3, 60),
        'p_hours': hours.clamp(1, 168),
      });
      return id.toString();
    } catch (e) {
      throw JuzzioServiceException(_app.trEn('Resmi hikâye paylaşılamadı: ${_friendlyError(e)}', 'Could not post official story: ${_friendlyError(e)}', 'Offizielle Story konnte nicht geteilt werden: ${_friendlyError(e)}'));
    }
  }

  Future<void> deleteOfficialStory(String storyId) async {
    try {
      await client.rpc('admin_delete_official_story', params: {'p_story': storyId});
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  /// Kullanıcının görebildiği (RLS: arkadaş / herkes / kendi) aktif hikâyeler
  Stream<List<JuzzioStory>> watchActiveStories() {
    return client
        .from('stories')
        .stream(primaryKey: ['id'])
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .map((rows) => rows.map(JuzzioStory.fromMap).where((s) => !s.isExpired).toList());
  }

  Future<bool> fetchMyStoryLike(String storyId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final row = await client
          .from('story_views')
          .select('has_liked')
          .eq('story_id', storyId)
          .eq('viewer_id', uid)
          .maybeSingle();
      return row?['has_liked'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Beğeni durumunu değiştirir; yeni durumu döndürür.
  Future<bool> toggleStoryLike(JuzzioStory story) async {
    try {
      final res = await client.rpc('toggle_story_like', params: {'p_story': story.id});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Hikâyeye yanıt: hikâye sahibiyle olan özel sohbete gider.
  Future<String?> replyToStory({
    required JuzzioStory story,
    required String replyText,
    File? replyImageFile,
    String? targetRoomId,
  }) async {
    final uid = currentUserId;
    if (uid == null || story.userId == uid) return null;

    final roomId = await ensureDirectRoomWithFriend(friendId: story.userId, friendName: story.displayName);
    // v0.9.6: hikâye yanıtı birebir sohbete gider → yazı ve görsel uçtan uca şifrelenir
    final directRoom = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (directRoom == null) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);

    String? uploadedImgUrl;
    if (directRoom) {
      return _replyToStoryEncrypted(uid: uid, roomId: roomId, story: story, replyText: replyText.trim(), replyImageFile: replyImageFile);
    }
    if (replyImageFile != null && replyImageFile.existsSync()) {
      final ext = _storageExt(replyImageFile.path, isVideo: false);
      final path = '$uid/$roomId/story_reply_${DateTime.now().millisecondsSinceEpoch}.$ext';
      try {
        await client.storage.from(JuzzioConfig.chatMediaBucket).upload(
              path,
              replyImageFile,
              fileOptions: FileOptions(contentType: _mimeFor(ext, isVideo: false)),
            );
        uploadedImgUrl = client.storage.from(JuzzioConfig.chatMediaBucket).getPublicUrl(path);
      } catch (_) {}
    }

    final me = await fetchUserProfile(uid);
    final cleanComment = replyText.trim();
    final targetLang = _defaultTargetLang;
    final translatedComment = cleanComment.isEmpty ? '' : await translateText(text: cleanComment, targetLang: targetLang);

    final storyMeta = <String, dynamic>{
      'storyId': story.id,
      'storyUserId': story.userId,
      'storyUsername': story.username,
      'storyDisplayName': story.displayName,
      'storyUserAvatar': story.userAvatar,
      'storyMediaUrl': story.mediaUrl,
      'storyMediaType': story.mediaType,
      'storyVideoDurationSec': story.videoDurationSec,
      'storyCaptionOriginal': story.captionOriginal,
      'storyCaptionTranslated': story.captionTranslated,
      'storyOverlayOriginal': story.overlayTextOriginal,
      'storyOverlayTranslated': story.overlayTextTranslated,
      'replierId': uid,
      'replierUsername': me?.username ?? '',
      'replierName': me?.displayName ?? '',
      'createdAt': story.createdAt.toIso8601String(),
    };

    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': uid,
      'message_type': uploadedImgUrl != null ? 'image' : 'text',
      'source_lang': _app.subtitleLang,
      'target_lang': targetLang,
      'original_text': cleanComment,
      'translated_text': translatedComment,
      'story_id': story.id,
      if (uploadedImgUrl != null) 'image_url': uploadedImgUrl,
      'metadata': {'story': storyMeta},
    });
    return roomId;
  }

  Map<String, dynamic> _storyMetaFor(JuzzioStory story, String uid, JuzzioUserProfile? me) => <String, dynamic>{
        'storyId': story.id,
        'storyUserId': story.userId,
        'storyUsername': story.username,
        'storyDisplayName': story.displayName,
        'storyUserAvatar': story.userAvatar,
        'storyMediaUrl': story.mediaUrl,
        'storyMediaType': story.mediaType,
        'storyVideoDurationSec': story.videoDurationSec,
        'replierId': uid,
        'replierUsername': me?.username ?? '',
        'replierName': me?.displayName ?? '',
        'createdAt': story.createdAt.toIso8601String(),
      };

  Future<String?> _replyToStoryEncrypted({
    required String uid,
    required String roomId,
    required JuzzioStory story,
    required String replyText,
    File? replyImageFile,
  }) async {
    final me = await fetchUserProfile(uid);
    // Hikâye kartı (kime ait, hangi medya) sunucuda zaten bilinen bilgidir; YANIT metni ve görseli şifrelidir.
    // Hikâye açıklaması gibi içerik metinleri karta konmaz.
    final meta = <String, dynamic>{'story': _storyMetaFor(story, uid, me)};
    if (replyImageFile != null && replyImageFile.existsSync()) {
      final ext = _storageExt(replyImageFile.path, isVideo: false);
      final (url, path, payload) = await _sealAndUpload(uid: uid, roomId: roomId, bytes: await replyImageFile.readAsBytes(), mime: _mimeFor(ext, isVideo: false), text: replyText);
      try {
        await client.from('messages').insert({
          'room_id': roomId,
          'sender_id': uid,
          'message_type': 'image',
          'source_lang': _app.subtitleLang,
          'target_lang': _defaultTargetLang,
          'original_text': '',
          'translated_text': '',
          'story_id': story.id,
          'image_url': url,
          'metadata': {...meta, 'e2ee': payload, 'media_e2ee': 1},
        });
      } catch (e) {
        await _removeChatMedia(path);
        rethrow;
      }
      return roomId;
    }
    final outcome = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: replyText, translated: '');
    if (outcome.status != JuzzioE2eeStatus.encrypted || outcome.payload == null) {
      throw JuzzioE2eeRequiredException(
          outcome.status == JuzzioE2eeStatus.peerKeyMissing ? JuzzioE2eeStatus.peerKeyMissing : JuzzioE2eeStatus.unavailable);
    }
    await client.from('messages').insert({
      'room_id': roomId,
      'sender_id': uid,
      'message_type': 'text',
      'source_lang': _app.subtitleLang,
      'target_lang': _defaultTargetLang,
      'original_text': '',
      'translated_text': '',
      'story_id': story.id,
      'metadata': {...meta, 'e2ee': outcome.payload},
    });
    return roomId;
  }

  // ---------------------------------------------------------------------------
  // ARAMALAR (1'e 1 + KONFERANS)
  // ---------------------------------------------------------------------------
  Future<JuzzioCallSession> startCall({
    required String roomId,
    required bool isVideo,
    List<String>? inviteeIds,
  }) async {
    try {
      final res = await client.rpc('start_call', params: {
        'p_room': roomId,
        'p_is_video': isVideo,
        'p_invitee_ids': inviteeIds,
      });
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final session = JuzzioCallSession.fromMap(map, fallbackRoomId: roomId);
      if (session.sessionId.isEmpty || session.livekitRoomName.isEmpty) {
        throw const JuzzioServiceException('call_not_started');
      }
      return session;
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  Future<int> inviteToCall({required String sessionId, required List<String> userIds}) async {
    try {
      final res = await client.rpc('invite_to_call', params: {'p_session': sessionId, 'p_user_ids': userIds});
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  /// Aramayı cevaplar. Başarılıysa null, değilse kullanıcının dilinde hata mesajı döner
  /// (ör. konferans 4 kişiyle dolu, arayan kapatmış).
  Future<String?> answerCall(String callId) async {
    try {
      await client.rpc('update_call_status', params: {'p_call': callId, 'p_status': 'answered'});
      return null;
    } catch (e) {
      return friendlyError(e);
    }
  }

  /// Başarılıysa true döner (cevaplama başarısızsa arama ekranı açılmamalı).
  Future<bool> updateCallStatus({required String callId, required String status, int? durationSec}) async {
    try {
      await client.rpc('update_call_status', params: {
        'p_call': callId,
        'p_status': status,
        'p_duration_sec': durationSec,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> endCallSession({required String sessionId, int? durationSec, bool force = false}) async {
    if (sessionId.isEmpty) return;
    try {
      await client.rpc('end_call_session', params: {
        'p_session': sessionId,
        'p_duration_sec': durationSec,
        'p_force': force,
      });
    } catch (_) {}
  }

  /// Bana gelen ve hâlâ çalan aramalar (yalnızca alıcıya özel).
  Stream<List<JuzzioCallLog>> watchIncomingCalls() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const []);
    return client
        .from('call_logs')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', uid)
        .order('created_at', ascending: false)
        .limit(20)
        .map((rows) {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 60));
      return rows
          .map(JuzzioCallLog.fromMap)
          .where((c) => c.isRinging && c.createdAt.toUtc().isAfter(cutoff))
          .toList();
    });
  }

  /// Bir arama oturumundaki tüm kayıtlar (arayan için: cevaplandı/reddedildi takibi).
  Stream<List<JuzzioCallLog>> watchCallSession(String sessionId) {
    return client
        .from('call_logs')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .map((rows) => rows.map(JuzzioCallLog.fromMap).toList());
  }

  /// Arama geçmişi (RLS: yalnızca arayan veya aranan olduğum kayıtlar)
  Stream<List<JuzzioCallLog>> watchCallLogs() {
    return client
        .from('call_logs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(80)
        .map((rows) {
      // Konferanslarda arayanın her davetli için ayrı satırı olur: oturum başına tek satır göster.
      final seen = <String>{};
      final out = <JuzzioCallLog>[];
      for (final log in rows.map(JuzzioCallLog.fromMap)) {
        final key = (log.sessionId != null && log.callerId == currentUserId) ? log.sessionId! : log.id;
        if (seen.add(key)) out.add(log);
      }
      return out;
    });
  }

  Future<void> deleteCallLogs(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await client.from('call_logs').delete().inFilter('id', ids);
    } catch (_) {}
  }

  /// Bu konferansı yönetebilir miyim? (host veya grup owner/admin)
  Future<bool> canManageCall(String livekitRoomName) async {
    if (livekitRoomName.trim().isEmpty) return false;
    try {
      final res = await client.rpc('can_manage_call', params: {'p_livekit_room': livekitRoomName.trim()});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Konferanstan katılımcı çıkarır. Yetki sunucuda (Edge Function + veritabanı) doğrulanır.
  Future<void> removeCallParticipant({required String livekitRoomName, required String targetIdentity}) async {
    try {
      final res = await client.functions.invoke('get-livekit-token', body: {
        'action': 'remove_participant',
        'roomName': livekitRoomName.trim(),
        'targetIdentity': targetIdentity,
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is Map && data['ok'] == true) return;
      throw JuzzioServiceException(_app.trEn('Katılımcı çıkarılamadı.', 'Could not remove participant.', 'Teilnehmer konnte nicht entfernt werden.'));
    } on FunctionException catch (e) {
      final details = e.details?.toString() ?? '';
      if (e.status == 403) {
        throw JuzzioServiceException(_app.trEn('Bu kişiyi çıkarma yetkin yok.', 'You are not allowed to remove this person.', 'Du darfst diese Person nicht entfernen.'));
      }
      if (details.contains('cannot_remove_host')) {
        throw JuzzioServiceException(_app.trEn('Aramayı başlatan kişi çıkarılamaz.', 'The call host cannot be removed.', 'Der Gastgeber kann nicht entfernt werden.'));
      }
      throw JuzzioServiceException(_app.trEn('Katılımcı çıkarılamadı.', 'Could not remove participant.', 'Teilnehmer konnte nicht entfernt werden.'));
    }
  }

  Future<JuzzioLiveKitAccess> fetchLiveKitToken({
    required String roomName,
    required String identity,
    required String displayName,
    required String lang,
  }) async {
    try {
      final res = await client.functions.invoke('get-livekit-token', body: {
        'roomName': roomName,
        'displayName': displayName,
        'lang': lang,
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final token = (data is Map) ? data['token']?.toString() : null;
      if (token == null || token.isEmpty) {
        throw const JuzzioServiceException('token_empty');
      }
      final url = (data['wsUrl']?.toString().trim().isNotEmpty ?? false)
          ? data['wsUrl'].toString()
          : JuzzioConfig.liveKitUrl;
      return JuzzioLiveKitAccess(token: token, url: url);
    } on FunctionException catch (e) {
      final details = e.details?.toString() ?? '';
      if (e.status == 403) {
        throw JuzzioServiceException(_app.trEn('Bu aramaya katılma yetkiniz yok.', 'You are not allowed to join this call.', 'Du darfst diesem Anruf nicht beitreten.'));
      }
      if (details.contains('missing_secret')) {
        throw JuzzioServiceException(_app.trEn(
          'Sunucu yapılandırması eksik (LiveKit Secrets). Yöneticiye bildirin.',
          'Server is missing LiveKit secrets. Please contact the admin.', 'Auf dem Server fehlen die LiveKit-Secrets. Bitte wende dich an den Administrator.',
        ));
      }
      throw JuzzioServiceException(_app.trEn('Arama bağlantısı kurulamadı (${e.status}).', 'Could not connect the call (${e.status}).', 'Der Anruf konnte nicht verbunden werden (${e.status}).'));
    } catch (e) {
      if (e is JuzzioServiceException) rethrow;
      throw JuzzioServiceException(_friendlyError(e));
    }
  }

  /// Canlı altyazı (Deepgram WebSocket) için Authorization başlık değeri.
  /// Önce Edge Function'dan kısa ömürlü token alınır; yerel geliştirmede
  /// --dart-define ile verilen anahtar kullanılabilir.
  Future<String?> fetchDeepgramAuthorization() async {
    try {
      final res = await client.functions.invoke('translate-bridge', body: {'mode': 'deepgram_token'});
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      final token = (data is Map) ? data['accessToken']?.toString() : null;
      if (token != null && token.isNotEmpty) return 'Bearer $token';
    } catch (_) {}
    final devKey = JuzzioConfig.deepgramDevApiKey;
    if (devKey.isNotEmpty) return 'Token $devKey';
    return null;
  }

  // ---------------------------------------------------------------------------
  // OTA
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> watchAppReleases() {
    return client
        .from('app_releases')
        .stream(primaryKey: ['id'])
        .order('version_code', ascending: false)
        .limit(1);
  }
}

/// v0.9.3: tek çeviri isteğinin en fazla karakter sayısı (sağlayıcı sınırlarının altında).
const int translationChunkMax = 450;

/// Metni cümle → kelime sınırlarından en fazla [max] karakterlik parçalara böler.
List<String> splitForTranslation(String text, {int max = translationChunkMax}) {
  final clean = text.trim();
  if (clean.isEmpty) return const [];
  if (clean.length <= max) return [clean];
  final out = <String>[];
  final sentences = RegExp(r'[^.!?。！？\n]+[.!?。！？]*[\s\n]*').allMatches(clean).map((m) => m.group(0)!).toList();
  if (sentences.isEmpty) sentences.add(clean);
  var buf = '';
  void flush() {
    if (buf.trim().isNotEmpty) out.add(buf.trim());
    buf = '';
  }

  for (final sentence in sentences) {
    if ((buf + sentence).length <= max) {
      buf += sentence;
      continue;
    }
    flush();
    if (sentence.length <= max) {
      buf = sentence;
      continue;
    }
    var rest = sentence;
    while (rest.length > max) {
      var cut = rest.lastIndexOf(' ', max);
      if (cut < max * 0.5) cut = max;
      out.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut);
    }
    buf = rest;
  }
  flush();
  return out.where((p) => p.isNotEmpty).toList();
}

/// Çeviri servislerinin çeviri yerine döndürdüğü hata/uyarı metinleri (asla gösterilmez).
bool isTranslationProviderError(String s) {
  final u = s.trim().toUpperCase();
  return u.startsWith('QUERY LENGTH LIMIT') ||
      u.contains('MAX ALLOWED QUERY') ||
      u.startsWith('MYMEMORY WARNING') ||
      u.contains('YOU USED ALL AVAILABLE FREE TRANSLATIONS') ||
      u.startsWith('INVALID LANGUAGE PAIR') ||
      u.startsWith('PLEASE SELECT TWO DISTINCT LANGUAGES') ||
      u.startsWith('NO QUERY SPECIFIED');
}

/// v0.9.4: belge sınırları ve yardımcıları
const int juzzioDocumentMaxBytes = 25 * 1024 * 1024;

/// Dosya adını güvenli hâle getirir (yol ayırıcıları ve denetim karakterleri atılır, en fazla 120 karakter).
String juzzioSafeFileName(String raw) {
  var n = raw.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_').trim();
  if (n.isEmpty || n == '.' || n == '..') n = 'dosya';
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 10 ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n;
}

String juzzioDocumentMime(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const m = {
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    'odt': 'application/vnd.oasis.opendocument.text',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'dwg': 'application/acad',
    'dxf': 'application/dxf',
    'nc': 'text/plain',
  };
  return m[ext] ?? 'application/octet-stream';
}

String juzzioFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// v0.9.6: birebir sohbette şifreli video sınırı (şifreleme bellekte yapılır)
const int juzzioEncryptedVideoMaxBytes = 40 * 1024 * 1024;
