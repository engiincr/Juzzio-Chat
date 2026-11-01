// =============================================================================
// JUZZIO v0.1.0 — Sosyal Ağ Veri Modelleri ve Açık Durum Makineleri (Bölüm 34)
// Post, Yorum, Takip İlişkisi, Bildirim, Hikâye Görüntüleme ve Şikâyet Modelleri
// =============================================================================

import 'dart:convert';

enum JuzzioPostLifecycleState {
  draft,
  uploading,
  publishing,
  published,
  failed,
  deleted,
}

enum JuzzioStoryLifecycleState {
  draft,
  uploading,
  active,
  expired,
  deleted,
}

enum JuzzioFollowRelationState {
  none,
  pending,
  following,
  blocked,
}

enum JuzzioReactionToggleState {
  inactive,
  pending,
  active,
  failed,
}

enum JuzzioDataLoadState {
  initialLoading,
  loaded,
  empty,
  error,
  partialError,
}

/// Türkçe İ/i/ı/I duyarlı arama ve kullanıcı adı/etiket normalizasyonu (Bölüm 10 & 23.2)
class JuzzioTurkishNormalizer {
  JuzzioTurkishNormalizer._();

  static String toLowerTurkish(String input) {
    if (input.isEmpty) return '';
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase();
  }

  static String toSearchFolded(String input) {
    final lower = toLowerTurkish(input.trim());
    return lower
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
  }

  static bool matchesQuery(String candidate, String query) {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return true;
    final trCand = toLowerTurkish(candidate);
    final trQ = toLowerTurkish(cleanQ);
    if (trCand.contains(trQ)) return true;
    return toSearchFolded(candidate).contains(toSearchFolded(cleanQ));
  }

  static List<String> extractHashtags(String text) {
    final regex = RegExp(r'#([a-zA-Z0-9_ğüşöçıİĞÜŞÖÇ]{2,40})');
    final matches = regex.allMatches(text);
    final result = <String>{};
    for (final m in matches) {
      final tag = m.group(1);
      if (tag != null && tag.trim().isNotEmpty) {
        result.add(toLowerTurkish(tag.trim()));
      }
    }
    return result.toList();
  }
}

class JuzzioPost {
  final String id;
  final String authorId;
  final String authorUsername;
  final String authorDisplayName;
  final String? authorAvatarUrl;
  final bool authorIsVerified;
  final String contentType; // 'image' | 'video' | 'carousel' | 'text' (eski: 'reel')
  final String caption;
  final List<String> hashtags;
  final String locationName;
  final String altText;
  final List<String> mediaUrls;
  final List<String> mediaStoragePaths;
  final String? coverUrl;
  final double aspectRatio;
  final int videoDurationSec;
  final int trimStartSec;
  final int trimEndSec;
  final String audioTitle;
  final String filterPreset;
  final String visibility; // 'public' | 'followers' | 'friends' | 'private'
  final bool commentsEnabled;
  final int likesCount;
  final int commentsCount;
  final int savesCount;
  final int sharesCount;
  final int viewsCount;
  final bool isLikedByMe;
  final bool isSavedByMe;
  final bool isDeleted;
  final JuzzioPostLifecycleState lifecycleState;
  final DateTime createdAt;
  final DateTime updatedAt;
  // v0.4.0 içerik stüdyosu
  final double playbackSpeed;
  final bool isMuted;
  final String musicUrl;
  final int musicStartSec;
  /// Video klipleri için kırpma aralıkları: [{"start_ms": 0, "end_ms": 4200}, ...]
  final List<Map<String, int>> clipMeta;
  /// Küresel akış konusu (posts.topic): general, news, technology, ...
  final String topic;

  const JuzzioPost({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.authorDisplayName,
    this.authorAvatarUrl,
    this.authorIsVerified = false,
    this.contentType = 'image',
    this.caption = '',
    this.hashtags = const [],
    this.locationName = '',
    this.altText = '',
    this.mediaUrls = const [],
    this.mediaStoragePaths = const [],
    this.coverUrl,
    this.aspectRatio = 1.0,
    this.videoDurationSec = 0,
    this.trimStartSec = 0,
    this.trimEndSec = 0,
    this.audioTitle = '',
    this.filterPreset = 'none',
    this.visibility = 'public',
    this.commentsEnabled = true,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.savesCount = 0,
    this.sharesCount = 0,
    this.viewsCount = 0,
    this.isLikedByMe = false,
    this.isSavedByMe = false,
    this.isDeleted = false,
    this.lifecycleState = JuzzioPostLifecycleState.published,
    required this.createdAt,
    required this.updatedAt,
    this.playbackSpeed = 1.0,
    this.isMuted = false,
    this.musicUrl = '',
    this.musicStartSec = 0,
    this.clipMeta = const [],
    this.topic = 'general',
  });

  /// [index]. medya için kırpma aralığı (ms). Bitiş 0 → videonun sonuna kadar.
  ({int startMs, int endMs}) trimForMedia(int index) {
    if (index >= 0 && index < clipMeta.length) {
      final m = clipMeta[index];
      return (startMs: m['start_ms'] ?? 0, endMs: m['end_ms'] ?? 0);
    }
    if (index == 0 && trimEndSec > trimStartSec) {
      return (startMs: trimStartSec * 1000, endMs: trimEndSec * 1000);
    }
    return (startMs: 0, endMs: 0);
  }

  static bool looksLikeVideoUrl(String url) {
    final clean = url.split('?').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.mkv') ||
        clean.endsWith('.m4v') ||
        clean.endsWith('.3gp');
  }

  static List<Map<String, int>> _parseClipMeta(dynamic raw) {
    dynamic data = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        data = jsonDecode(raw);
      } catch (_) {
        data = null;
      }
    }
    if (data is! List) return const [];
    final out = <Map<String, int>>[];
    for (final e in data) {
      if (e is Map) {
        out.add({
          'start_ms': (e['start_ms'] is num) ? (e['start_ms'] as num).toInt() : 0,
          'end_ms': (e['end_ms'] is num) ? (e['end_ms'] as num).toInt() : 0,
        });
      }
    }
    return out;
  }

  /// Eski (v0.5 öncesi) reel kayıtları artık normal video olarak gösterilir.
  bool get isReel => contentType == 'reel';
  /// Küresel akıştaki yalnızca yazı paylaşımı
  bool get isText => contentType == 'text';
  bool get isVideo => contentType == 'video' || contentType == 'reel';
  bool get isCarousel => contentType == 'carousel' || mediaUrls.length > 1;
  String? get primaryMediaUrl => mediaUrls.isNotEmpty ? mediaUrls.first : coverUrl;

  JuzzioPost copyWith({
    String? caption,
    List<String>? hashtags,
    String? locationName,
    String? altText,
    String? visibility,
    bool? commentsEnabled,
    int? likesCount,
    int? commentsCount,
    int? savesCount,
    int? sharesCount,
    int? viewsCount,
    bool? isLikedByMe,
    bool? isSavedByMe,
    bool? isDeleted,
    JuzzioPostLifecycleState? lifecycleState,
  }) {
    return JuzzioPost(
      id: id,
      authorId: authorId,
      authorUsername: authorUsername,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorIsVerified: authorIsVerified,
      contentType: contentType,
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
      locationName: locationName ?? this.locationName,
      altText: altText ?? this.altText,
      mediaUrls: mediaUrls,
      mediaStoragePaths: mediaStoragePaths,
      coverUrl: coverUrl,
      aspectRatio: aspectRatio,
      videoDurationSec: videoDurationSec,
      trimStartSec: trimStartSec,
      trimEndSec: trimEndSec,
      audioTitle: audioTitle,
      filterPreset: filterPreset,
      visibility: visibility ?? this.visibility,
      commentsEnabled: commentsEnabled ?? this.commentsEnabled,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      savesCount: savesCount ?? this.savesCount,
      sharesCount: sharesCount ?? this.sharesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
      isDeleted: isDeleted ?? this.isDeleted,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
      playbackSpeed: playbackSpeed,
      isMuted: isMuted,
      musicUrl: musicUrl,
      musicStartSec: musicStartSec,
      clipMeta: clipMeta,
      topic: topic,
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  factory JuzzioPost.fromMap(
    Map<String, dynamic> map, {
    bool isLikedByMe = false,
    bool isSavedByMe = false,
  }) {
    final created = DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? created;
    final cleanUsername = (map['author_username'] ?? map['author_display_name'] ?? 'kullanici')
        .toString()
        .trim()
        .replaceAll('@', '');
    final deleted = map['is_deleted'] == true;
    return JuzzioPost(
      id: (map['id'] ?? '').toString(),
      authorId: (map['author_id'] ?? '').toString(),
      authorUsername: cleanUsername,
      authorDisplayName: (map['author_display_name'] ?? cleanUsername).toString(),
      authorAvatarUrl: map['author_avatar_url']?.toString(),
      authorIsVerified: map['author_is_verified'] == true,
      contentType: (map['content_type'] ?? 'image').toString(),
      topic: (map['topic'] ?? 'general').toString(),
      caption: (map['caption'] ?? '').toString(),
      hashtags: _parseStringList(map['hashtags']),
      locationName: (map['location_name'] ?? '').toString(),
      altText: (map['alt_text'] ?? '').toString(),
      mediaUrls: _parseStringList(map['media_urls']),
      mediaStoragePaths: _parseStringList(map['media_storage_paths']),
      coverUrl: map['cover_url']?.toString(),
      aspectRatio: (map['aspect_ratio'] as num?)?.toDouble() ?? 1.0,
      videoDurationSec: (map['video_duration_sec'] as num?)?.toInt() ?? 0,
      trimStartSec: (map['trim_start_sec'] as num?)?.toInt() ?? 0,
      trimEndSec: (map['trim_end_sec'] as num?)?.toInt() ?? 0,
      audioTitle: (map['audio_title'] ?? '').toString(),
      filterPreset: (map['filter_preset'] ?? 'none').toString(),
      visibility: (map['visibility'] ?? 'public').toString(),
      commentsEnabled: map['comments_enabled'] != false,
      likesCount: ((map['likes_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      commentsCount: ((map['comments_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      savesCount: ((map['saves_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      sharesCount: ((map['shares_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      viewsCount: ((map['views_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      isLikedByMe: isLikedByMe,
      isSavedByMe: isSavedByMe,
      isDeleted: deleted,
      lifecycleState: deleted
          ? JuzzioPostLifecycleState.deleted
          : JuzzioPostLifecycleState.published,
      createdAt: created,
      updatedAt: updated,
      playbackSpeed: (map['playback_speed'] is num)
          ? (map['playback_speed'] as num).toDouble()
          : double.tryParse(map['playback_speed']?.toString() ?? '') ?? 1.0,
      isMuted: map['is_muted'] == true,
      musicUrl: (map['music_url'] ?? '').toString(),
      musicStartSec: (map['music_start_sec'] as num?)?.toInt() ?? 0,
      clipMeta: _parseClipMeta(map['clip_meta']),
    );
  }
}

class JuzzioComment {
  final String id;
  final String postId;
  final String authorId;
  final String authorUsername;
  final String authorDisplayName;
  final String? authorAvatarUrl;
  final String? parentCommentId;
  final String replyToUsername;
  final String content;
  final int likesCount;
  final bool isLikedByMe;
  final bool isEdited;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JuzzioComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorUsername,
    required this.authorDisplayName,
    this.authorAvatarUrl,
    this.parentCommentId,
    this.replyToUsername = '',
    required this.content,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.isEdited = false,
    required this.createdAt,
    required this.updatedAt,
  });

  JuzzioComment copyWith({
    String? content,
    int? likesCount,
    bool? isLikedByMe,
    bool? isEdited,
  }) {
    return JuzzioComment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorUsername: authorUsername,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      parentCommentId: parentCommentId,
      replyToUsername: replyToUsername,
      content: content ?? this.content,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isEdited: isEdited ?? this.isEdited,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  factory JuzzioComment.fromMap(Map<String, dynamic> map, {bool isLikedByMe = false}) {
    final created = DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? created;
    final cleanUname = (map['author_username'] ?? map['author_display_name'] ?? 'kullanici')
        .toString()
        .trim()
        .replaceAll('@', '');
    return JuzzioComment(
      id: (map['id'] ?? '').toString(),
      postId: (map['post_id'] ?? '').toString(),
      authorId: (map['author_id'] ?? '').toString(),
      authorUsername: cleanUname,
      authorDisplayName: (map['author_display_name'] ?? cleanUname).toString(),
      authorAvatarUrl: map['author_avatar_url']?.toString(),
      parentCommentId: map['parent_comment_id']?.toString(),
      replyToUsername: (map['reply_to_username'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      likesCount: ((map['likes_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      isLikedByMe: isLikedByMe,
      isEdited: map['is_edited'] == true,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class JuzzioFollowRecord {
  final String id;
  final String followerId;
  final String followerUsername;
  final String followerDisplayName;
  final String? followerAvatarUrl;
  final String followingId;
  final String followingUsername;
  final String followingDisplayName;
  final String? followingAvatarUrl;
  final String status; // 'pending' | 'following' | 'rejected'
  final DateTime createdAt;

  const JuzzioFollowRecord({
    required this.id,
    required this.followerId,
    required this.followerUsername,
    required this.followerDisplayName,
    this.followerAvatarUrl,
    required this.followingId,
    required this.followingUsername,
    required this.followingDisplayName,
    this.followingAvatarUrl,
    required this.status,
    required this.createdAt,
  });

  JuzzioFollowRelationState get relationState {
    if (status == 'following') return JuzzioFollowRelationState.following;
    if (status == 'pending') return JuzzioFollowRelationState.pending;
    return JuzzioFollowRelationState.none;
  }

  factory JuzzioFollowRecord.fromMap(Map<String, dynamic> map) {
    return JuzzioFollowRecord(
      id: (map['id'] ?? '').toString(),
      followerId: (map['follower_id'] ?? '').toString(),
      followerUsername: (map['follower_username'] ?? '').toString().replaceAll('@', ''),
      followerDisplayName: (map['follower_display_name'] ?? 'Kullanıcı').toString(),
      followerAvatarUrl: map['follower_avatar_url']?.toString(),
      followingId: (map['following_id'] ?? '').toString(),
      followingUsername: (map['following_username'] ?? '').toString().replaceAll('@', ''),
      followingDisplayName: (map['following_display_name'] ?? 'Kullanıcı').toString(),
      followingAvatarUrl: map['following_avatar_url']?.toString(),
      status: (map['status'] ?? 'following').toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// v0.5.0: Juzzio logosunun yanındaki bildirim çanına YALNIZCA sosyal etkileşimler
/// düşer. Sohbet mesajları ve aramalar ilgili sohbet satırındaki okunmamış
/// rozetinde gösterilir (push bildirimi yine FCM ile gider).
const Set<String> kJuzzioSocialEventTypes = {
  'friend_request',
  'friend_accepted',
  'follow',
  'follow_request',
  'follow_accepted',
  'like',
  'comment',
  'reply',
  'comment_like',
  'mention',
  'save',
  'story_like',
  'system',
};

class JuzzioNotificationItem {
  final String id;
  final String recipientId;
  final String? actorId;
  final String actorUsername;
  final String actorDisplayName;
  final String? actorAvatarUrl;
  final String eventType;
  final String targetId;
  final String targetSecondaryId;
  final String previewText;
  final String? mediaThumbUrl;
  final bool isRead;
  final DateTime createdAt;

  const JuzzioNotificationItem({
    required this.id,
    required this.recipientId,
    this.actorId,
    required this.actorUsername,
    required this.actorDisplayName,
    this.actorAvatarUrl,
    required this.eventType,
    this.targetId = '',
    this.targetSecondaryId = '',
    this.previewText = '',
    this.mediaThumbUrl,
    this.isRead = false,
    required this.createdAt,
  });

  JuzzioNotificationItem copyWith({bool? isRead}) {
    return JuzzioNotificationItem(
      id: id,
      recipientId: recipientId,
      actorId: actorId,
      actorUsername: actorUsername,
      actorDisplayName: actorDisplayName,
      actorAvatarUrl: actorAvatarUrl,
      eventType: eventType,
      targetId: targetId,
      targetSecondaryId: targetSecondaryId,
      previewText: previewText,
      mediaThumbUrl: mediaThumbUrl,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  factory JuzzioNotificationItem.fromMap(Map<String, dynamic> map) {
    final cleanUname = (map['actor_username'] ?? map['actor_display_name'] ?? 'juzzio')
        .toString()
        .trim()
        .replaceAll('@', '');
    return JuzzioNotificationItem(
      id: (map['id'] ?? '').toString(),
      recipientId: (map['recipient_id'] ?? '').toString(),
      actorId: map['actor_id']?.toString(),
      actorUsername: cleanUname,
      actorDisplayName: (map['actor_display_name'] ?? cleanUname).toString(),
      actorAvatarUrl: map['actor_avatar_url']?.toString(),
      eventType: (map['event_type'] ?? 'system').toString(),
      targetId: (map['target_id'] ?? '').toString(),
      targetSecondaryId: (map['target_secondary_id'] ?? '').toString(),
      previewText: (map['preview_text'] ?? '').toString(),
      mediaThumbUrl: map['media_thumb_url']?.toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class JuzzioStoryViewItem {
  final String id;
  final String storyId;
  final String viewerId;
  final String viewerUsername;
  final String viewerDisplayName;
  final String? viewerAvatarUrl;
  final bool hasLiked;
  final DateTime viewedAt;

  const JuzzioStoryViewItem({
    required this.id,
    required this.storyId,
    required this.viewerId,
    required this.viewerUsername,
    required this.viewerDisplayName,
    this.viewerAvatarUrl,
    this.hasLiked = false,
    required this.viewedAt,
  });

  factory JuzzioStoryViewItem.fromMap(Map<String, dynamic> map) {
    final cleanUname = (map['viewer_username'] ?? map['viewer_display_name'] ?? 'kullanici')
        .toString()
        .trim()
        .replaceAll('@', '');
    return JuzzioStoryViewItem(
      id: (map['id'] ?? '').toString(),
      storyId: (map['story_id'] ?? '').toString(),
      viewerId: (map['viewer_id'] ?? '').toString(),
      viewerUsername: cleanUname,
      viewerDisplayName: (map['viewer_display_name'] ?? cleanUname).toString(),
      viewerAvatarUrl: map['viewer_avatar_url']?.toString(),
      hasLiked: map['has_liked'] == true,
      viewedAt: DateTime.tryParse(map['viewed_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class JuzzioBlockedUserItem {
  final String id;
  final String blockerId;
  final String blockedId;
  final String blockedUsername;
  final String blockedDisplayName;
  final String? blockedAvatarUrl;
  final DateTime createdAt;

  const JuzzioBlockedUserItem({
    required this.id,
    required this.blockerId,
    required this.blockedId,
    required this.blockedUsername,
    required this.blockedDisplayName,
    this.blockedAvatarUrl,
    required this.createdAt,
  });

  factory JuzzioBlockedUserItem.fromMap(Map<String, dynamic> map) {
    final cleanUname = (map['blocked_username'] ?? map['blocked_display_name'] ?? 'kullanici')
        .toString()
        .trim()
        .replaceAll('@', '');
    return JuzzioBlockedUserItem(
      id: (map['id'] ?? '').toString(),
      blockerId: (map['blocker_id'] ?? '').toString(),
      blockedId: (map['blocked_id'] ?? '').toString(),
      blockedUsername: cleanUname,
      blockedDisplayName: (map['blocked_display_name'] ?? cleanUname).toString(),
      blockedAvatarUrl: map['blocked_avatar_url']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class JuzzioProfileSocialCounts {
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final JuzzioFollowRelationState myRelationToUser;
  final bool isBlockedBetween;
  final bool isMutedByMe;

  const JuzzioProfileSocialCounts({
    this.postsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.myRelationToUser = JuzzioFollowRelationState.none,
    this.isBlockedBetween = false,
    this.isMutedByMe = false,
  });
}
