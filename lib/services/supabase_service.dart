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
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'juzzio_e2ee.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import 'juzzio_features_service.dart';

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
  final String? storyId;
  final String? replyToId;
  final Map<String, dynamic>? storyReplyMeta;
  final Map<String, dynamic> metadata;
  final int audioDurationMs;
  final List<double> waveformPeaks;
  final Map<String, String> reactions;
  final bool isPinned;
  final bool isDeleted;
  final DateTime? editedAt;
  final DateTime createdAt;

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
    this.storyId,
    this.replyToId,
    this.storyReplyMeta,
    this.metadata = const {},
    this.audioDurationMs = 0,
    this.waveformPeaks = const [],
    this.reactions = const {},
    this.isPinned = false,
    this.isDeleted = false,
    this.editedAt,
    required this.createdAt,
  });

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
        storyId: storyId,
        replyToId: replyToId,
        storyReplyMeta: storyReplyMeta,
        metadata: metadata,
        audioDurationMs: audioDurationMs,
        waveformPeaks: waveformPeaks,
        reactions: reactions,
        isPinned: isPinned,
        isDeleted: isDeleted,
        editedAt: editedAt,
        createdAt: createdAt,
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
      translatedText: (map['translated_text'] ?? '').toString(),
      audioUrl: nonEmpty(rawAudioUrl),
      imageUrl: nonEmpty(map['image_url']) ?? nonEmpty(storyMeta?['replyImageUrl']),
      videoUrl: nonEmpty(map['video_url']),
      documentUrl: nonEmpty(map['document_url']),
      documentName: nonEmpty(map['document_name']),
      storyId: nonEmpty(map['story_id']) ?? nonEmpty(storyMeta?['storyId']),
      replyToId: nonEmpty(map['reply_to_id']),
      storyReplyMeta: storyMeta,
      metadata: metadata,
      audioDurationMs: (map['audio_duration_ms'] as num?)?.toInt() ?? 0,
      waveformPeaks: parsedPeaks,
      reactions: parsedReactions,
      isPinned: map['is_pinned'] == true,
      isDeleted: map['is_deleted'] == true,
      editedAt: DateTime.tryParse(map['edited_at']?.toString() ?? ''),
      createdAt: _parseDate(map['created_at']),
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
  });

  bool get hasTrim => trimEndMs > trimStartMs && trimEndMs > 0;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

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

  void attachPreferenceSync() {
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
    changed['updated_at'] = DateTime.now().toUtc().toIso8601String();
    try {
      await client.from('profiles').update(changed).eq('id', uid);
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
        if (userId == currentUserId) unawaited(_writeCache('my_profile', row));
        return JuzzioUserProfile.fromMap(row);
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

  Future<void> _writeCache(String name, Object data) async {
    try {
      final f = await _cacheFile(name);
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<Object?> _readCache(String name) async {
    try {
      final f = await _cacheFile(name);
      if (f == null || !f.existsSync()) return null;
      return jsonDecode(await f.readAsString());
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

    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=auto&tl=${Uri.encodeComponent(tl)}&dt=t&q=${Uri.encodeComponent(clean)}',
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
          if (result.isNotEmpty) {
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
      if (translated != null && translated.isNotEmpty) {
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
    if (uid == null) return Stream.value(const []);
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
  Stream<List<JuzzioMessage>> watchRoomMessages(String roomId) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .map((rows) {
      final now = DateTime.now().toUtc();
      return rows
          .where((r) {
            final exp = DateTime.tryParse(r['expires_at']?.toString() ?? '');
            return exp == null || exp.toUtc().isAfter(now);
          })
          .map(JuzzioMessage.fromMap)
          .toList();
    }).asyncMap(JuzzioE2ee.instance.decryptAll);
  }

  Future<void> sendTextMessage({
    required String text,
    String sourceLang = 'auto',
    String? senderName,
    String? targetRoomId,
    String? receiverId,
    String? replyToId,
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
    final translated = await translateText(text: clean, sourceLang: 'auto', targetLang: targetLang);
    // v0.7.0: 1'e 1 sohbette karşı tarafın anahtarı varsa uçtan uca şifreli gönder
    final e2ee = await JuzzioE2ee.instance.encryptForRoom(roomId, text: clean, translated: translated);

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
        if (e2ee != null) 'metadata': {'e2ee': e2ee},
        if (replyToId != null) 'reply_to_id': replyToId,
      });
    } catch (e) {
      throw JuzzioServiceException(_friendlyError(e));
    }
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
    });
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
        'audioUrl': publicUrl,
        'sourceLang': mySubLang,
        'targetLang': targetLang,
      });
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is Map) {
        transcriptOriginal = (data['originalText'] ?? '').toString().trim();
        transcriptTranslated = (data['translatedText'] ?? '').toString().trim();
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
  Future<String> uploadPublicImage(File file, {String prefix = 'img'}) async {
    final uid = currentUserId;
    if (uid == null) throw JuzzioServiceException(_app.t('err_session'));
    if (!file.existsSync() || file.lengthSync() > 15 * 1024 * 1024) {
      throw JuzzioServiceException(_app.trEn('Görsel 15 MB\'tan küçük olmalı.', 'The image must be under 15 MB.', 'Das Bild muss kleiner als 15 MB sein.'));
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

    String? uploadedImgUrl;
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
