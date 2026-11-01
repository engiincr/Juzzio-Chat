// =============================================================================
// JUZZIO v0.1.0 — Sosyal Medya Backend Servis Katmanı (Bölüm 7.3, 17-34)
// Gerçek Supabase Sorguları, Cursor/Keyset Sayfalama, Storage Upload + Orphan Cleanup,
// Beğeni/Yorum/Kaydetme/Takip/Engelleme/Sessize Alma/Şikâyet/Bildirim Servisleri
// Sahte kullanıcı veya sabit demo verisi içermez!
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/social_models.dart';
import 'supabase_service.dart';
import '../core/app_theme_and_locale.dart';

String _tx(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);


/// Küresel akış konuları (veritabanındaki posts_topic_check ile aynı liste)
const List<String> kJuzzioFeedTopics = <String>[
  'general',
  'news',
  'technology',
  'science',
  'sports',
  'entertainment',
  'music',
  'gaming',
  'travel',
  'food',
  'art',
  'humor',
];

class JuzzioSocialService {
  JuzzioSocialService._();
  static final JuzzioSocialService instance = JuzzioSocialService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  final Set<String> _likedPostIdsCache = <String>{};
  final Set<String> _savedPostIdsCache = <String>{};
  final Set<String> _likedCommentIdsCache = <String>{};
  final Set<String> _blockedUserIdsCache = <String>{};
  final Set<String> _mutedUserIdsCache = <String>{};
  final Set<String> _hiddenRecommendationIds = <String>{};

  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIdsCache);
  Set<String> get mutedUserIds => Set.unmodifiable(_mutedUserIdsCache);

  /// Kullanıcının beğendiği, kaydettiği, engellediği ve sessize aldığı kimlikleri senkronize eder
  Future<void> refreshMyInteractionSets() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      _likedPostIdsCache.clear();
      _savedPostIdsCache.clear();
      _likedCommentIdsCache.clear();
      _blockedUserIdsCache.clear();
      _mutedUserIdsCache.clear();
      return;
    }

    try {
      final likesRows = await _client
          .from('post_likes')
          .select('post_id')
          .eq('user_id', uid)
          .limit(500);
      _likedPostIdsCache
        ..clear()
        ..addAll((likesRows as List).map((r) => (r['post_id'] ?? '').toString()).where((s) => s.isNotEmpty));
    } catch (_) {}

    try {
      final savedRows = await _client
          .from('saved_posts')
          .select('post_id')
          .eq('user_id', uid)
          .limit(500);
      _savedPostIdsCache
        ..clear()
        ..addAll((savedRows as List).map((r) => (r['post_id'] ?? '').toString()).where((s) => s.isNotEmpty));
    } catch (_) {}

    try {
      final blocksRows = await _client
          .from('blocked_users')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$uid,blocked_id.eq.$uid');
      _blockedUserIdsCache.clear();
      for (final r in (blocksRows as List)) {
        final blocker = (r['blocker_id'] ?? '').toString();
        final blocked = (r['blocked_id'] ?? '').toString();
        if (blocker == uid && blocked.isNotEmpty) _blockedUserIdsCache.add(blocked);
        if (blocked == uid && blocker.isNotEmpty) _blockedUserIdsCache.add(blocker);
      }
    } catch (_) {}

    try {
      final mutedRows = await _client
          .from('muted_users')
          .select('muted_id')
          .eq('muter_id', uid);
      _mutedUserIdsCache
        ..clear()
        ..addAll((mutedRows as List).map((r) => (r['muted_id'] ?? '').toString()).where((s) => s.isNotEmpty));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 1. SOSYAL AKIŞ VE KÜRESEL AKIŞ SAYFALAMA SORGULARI (Bölüm 6.1, 6.3, 22, 23, 33.2)
  // ---------------------------------------------------------------------------
  Future<List<JuzzioPost>> fetchFeedPosts({
    int limit = 20,
    DateTime? beforeCreatedAt,
    String filter = 'all', // 'all' | 'following' | 'for_you'
    String? authorId,
    String? hashtag,
    String? topic,
  }) async {
    await refreshMyInteractionSets();
    final uid = currentUserId;

    Set<String> followingIds = <String>{};
    if (uid != null && (filter == 'following' || authorId == null)) {
      try {
        final followRows = await _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', uid)
            .eq('status', 'following');
        followingIds = (followRows as List)
            .map((e) => (e['following_id'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();
      } catch (_) {}
    }

    var query = _client.from('posts').select().eq('is_deleted', false);
    if (authorId != null && authorId.isNotEmpty) {
      query = query.eq('author_id', authorId);
    }
    if (beforeCreatedAt != null) {
      query = query.lt('created_at', beforeCreatedAt.toUtc().toIso8601String());
    }
    // Konu filtresi sunucuda uygulanır (posts.topic + idx_posts_topic_created)
    if (topic != null && topic.isNotEmpty && topic != 'all') {
      query = query.eq('topic', topic);
    }

    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    final result = <JuzzioPost>[];
    final seenIds = <String>{};

    for (final raw in (rows as List)) {
      final map = raw as Map<String, dynamic>;
      final post = JuzzioPost.fromMap(
        map,
        isLikedByMe: _likedPostIdsCache.contains(map['id']?.toString()),
        isSavedByMe: _savedPostIdsCache.contains(map['id']?.toString()),
      );
      if (post.id.isEmpty || seenIds.contains(post.id)) continue;
      if (_blockedUserIdsCache.contains(post.authorId)) continue;
      if (authorId == null && _mutedUserIdsCache.contains(post.authorId)) continue;

      if (filter == 'following' && authorId == null) {
        if (post.authorId != uid && !followingIds.contains(post.authorId)) {
          continue;
        }
      }
      if (hashtag != null && hashtag.trim().isNotEmpty) {
        final cleanTag = JuzzioTurkishNormalizer.toLowerTurkish(hashtag.replaceAll('#', '').trim());
        final hasMatch = post.hashtags.any((t) => JuzzioTurkishNormalizer.toLowerTurkish(t) == cleanTag) ||
            JuzzioTurkishNormalizer.matchesQuery(post.caption, '#$cleanTag');
        if (!hasMatch) continue;
      }

      seenIds.add(post.id);
      result.add(post);
    }
    return result;
  }

  /// Tekil gönderiyi postId ile gerçek veritabanından doğrular (Bölüm 21.1)
  Future<JuzzioPost?> fetchPostById(String postId) async {
    if (postId.trim().isEmpty) return null;
    await refreshMyInteractionSets();
    final row = await _client
        .from('posts')
        .select()
        .eq('id', postId.trim())
        .maybeSingle();
    if (row == null) return null;
    final post = JuzzioPost.fromMap(
      row,
      isLikedByMe: _likedPostIdsCache.contains(postId.trim()),
      isSavedByMe: _savedPostIdsCache.contains(postId.trim()),
    );
    if (post.isDeleted || _blockedUserIdsCache.contains(post.authorId)) {
      return null;
    }
    return post;
  }

  /// Kullanıcının kaydettiği gönderileri getirir (Yalnızca kendi profilinde çağrılır - Bölüm 24.1)
  Future<List<JuzzioPost>> fetchMySavedPosts({int limit = 30}) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return const [];
    await refreshMyInteractionSets();

    final savedRows = await _client
        .from('saved_posts')
        .select('post_id, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);

    final postIds = (savedRows as List)
        .map((e) => (e['post_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (postIds.isEmpty) return const [];

    final postRows = await _client
        .from('posts')
        .select()
        .inFilter('id', postIds)
        .eq('is_deleted', false);

    final byId = <String, JuzzioPost>{};
    for (final raw in (postRows as List)) {
      final map = raw as Map<String, dynamic>;
      final p = JuzzioPost.fromMap(
        map,
        isLikedByMe: _likedPostIdsCache.contains(map['id']?.toString()),
        isSavedByMe: true,
      );
      if (!_blockedUserIdsCache.contains(p.authorId)) {
        byId[p.id] = p;
      }
    }
    return postIds.map((id) => byId[id]).whereType<JuzzioPost>().toList();
  }

  // ---------------------------------------------------------------------------
  // 2. GÖNDERİ / CAROUSEL OLUŞTURMA, UPLOAD + ORPHAN CLEANUP (Bölüm 17.4, 19, 22.2)
  // ---------------------------------------------------------------------------
  Future<JuzzioPost> uploadAndCreatePost({
    required JuzzioUserProfile author,
    required List<File> mediaFiles,
    required String contentType, // 'image' | 'video' | 'carousel'
    String caption = '',
    String locationName = '',
    String altText = '',
    String visibility = 'public',
    bool commentsEnabled = true,
    double aspectRatio = 1.0,
    int videoDurationSec = 0,
    int trimStartSec = 0,
    int trimEndSec = 0,
    String audioTitle = '',
    String filterPreset = 'none',
    double playbackSpeed = 1.0,
    bool isMuted = false,
    String musicUrl = '',
    int musicStartSec = 0,
    List<Map<String, int>> clipMeta = const [],
    File? customCoverFile,
    String? clientRequestId,
    void Function(double progress)? onProgress,
  }) async {
    final uid = currentUserId ?? author.id;
    if (uid.isEmpty) {
      throw Exception(_tx('Oturum açık değil. Lütfen tekrar giriş yapın.', 'Your session expired. Please sign in again.', 'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.'));
    }
    if (mediaFiles.isEmpty) {
      throw Exception(_tx('Lütfen paylaşmak için en az bir fotoğraf veya video seçin.', 'Please select at least one photo or video to share.', 'Bitte wähle mindestens ein Foto oder Video zum Teilen aus.'));
    }

    // Boyut ve okunabilirlik doğrulaması (Bölüm 17.1 & 6.10)
    const maxImageBytes = 25 * 1024 * 1024; // 25 MB
    const maxVideoBytes = 150 * 1024 * 1024; // 150 MB
    for (final file in mediaFiles) {
      if (!file.existsSync()) {
        throw Exception(_tx('Seçilen medya dosyası okunamadı.', 'The selected media file could not be read.', 'Die ausgewählte Mediendatei konnte nicht gelesen werden.'));
      }
      final len = file.lengthSync();
      if (len <= 0) {
        throw Exception(_tx('Seçilen medya dosyası boş veya bozuk.', 'The selected media file is empty or corrupted.', 'Die ausgewählte Mediendatei ist leer oder beschädigt.'));
      }
      final isVid = contentType == 'video' ||
          ['mp4', 'mov', 'webm', 'mkv'].contains(file.path.split('.').last.toLowerCase());
      if (isVid && len > maxVideoBytes) {
        throw Exception(_tx('Video dosyası çok büyük (Maksimum 150 MB).', 'The video file is too large (max. 150 MB).', 'Die Videodatei ist zu groß (max. 150 MB).'));
      }
      if (!isVid && len > maxImageBytes) {
        throw Exception(_tx('Görsel dosyası çok büyük (Maksimum 25 MB).', 'The image file is too large (max. 25 MB).', 'Die Bilddatei ist zu groß (max. 25 MB).'));
      }
    }

    onProgress?.call(0.10);
    const targetBucket = 'posts';
    final uploadedUrls = <String>[];
    final uploadedPaths = <String>[];
    String? uploadedCoverUrl;

    try {
      for (int i = 0; i < mediaFiles.length; i++) {
        final file = mediaFiles[i];
        final rawExt = file.path.split('.').last.toLowerCase();
        final isVideoFile = contentType == 'video' ||
            ['mp4', 'mov', 'webm', 'mkv'].contains(rawExt);
        final ext = isVideoFile
            ? (['mp4', 'mov', 'webm', 'mkv'].contains(rawExt) ? rawExt : 'mp4')
            : (['png', 'webp', 'jpg', 'jpeg'].contains(rawExt) ? rawExt : 'jpg');
        final mime = isVideoFile
            ? 'video/mp4'
            : (ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg'));
        final storagePath = '$uid/${contentType}_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';

        try {
          await _client.storage.from(targetBucket).upload(
                storagePath,
                file,
                fileOptions: FileOptions(contentType: mime, upsert: false),
              );
        } catch (_) {
          throw Exception(_tx('Medya buluta yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.', 'Media could not be uploaded. Check your connection and try again.', 'Medien konnten nicht hochgeladen werden. Prüfe deine Verbindung und versuche es erneut.'));
        }
        final publicUrl = _client.storage.from(targetBucket).getPublicUrl(storagePath);
        uploadedPaths.add('$targetBucket:$storagePath');
        uploadedUrls.add(publicUrl);
        onProgress?.call(0.15 + ((i + 1) / mediaFiles.length) * 0.60);
      }

      if (customCoverFile != null && customCoverFile.existsSync()) {
        final coverPath = '$uid/cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await _client.storage.from(targetBucket).upload(
                coverPath,
                customCoverFile,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          uploadedCoverUrl = _client.storage.from(targetBucket).getPublicUrl(coverPath);
          uploadedPaths.add('$targetBucket:$coverPath');
        } catch (_) {}
      }

      onProgress?.call(0.85);
      final tags = JuzzioTurkishNormalizer.extractHashtags(caption);
      final reqId = clientRequestId ?? '${uid}_${DateTime.now().millisecondsSinceEpoch}';

      final payload = <String, dynamic>{
        'author_id': uid,
        'author_username': author.username,
        'author_display_name': author.displayName,
        'author_avatar_url': author.avatarUrl,
        'content_type': mediaFiles.length > 1 && contentType == 'image' ? 'carousel' : contentType,
        'caption': caption.trim(),
        'hashtags': tags,
        'location_name': locationName.trim(),
        'alt_text': altText.trim(),
        'media_urls': uploadedUrls,
        'media_storage_paths': uploadedPaths,
        'cover_url': uploadedCoverUrl ?? uploadedUrls.first,
        'aspect_ratio': aspectRatio,
        'video_duration_sec': videoDurationSec,
        'trim_start_sec': trimStartSec,
        'trim_end_sec': trimEndSec,
        'audio_title': audioTitle.trim(),
        'filter_preset': filterPreset,
        'playback_speed': playbackSpeed.clamp(0.25, 3.0),
        'is_muted': isMuted,
        'music_url': musicUrl.trim(),
        'music_start_sec': musicStartSec < 0 ? 0 : musicStartSec,
        'clip_meta': clipMeta,
        'visibility': visibility,
        'comments_enabled': commentsEnabled,
        'client_request_id': reqId,
      };

      final inserted = await _client.from('posts').insert(payload).select().single();
      onProgress?.call(1.0);
      return JuzzioPost.fromMap(inserted);
    } catch (e) {
      // Orphan file cleanup (Bölüm 17.4 & 33.1: Storage upload başarılı ama DB insert başarısızsa temizle)
      for (final entry in uploadedPaths) {
        final idx = entry.indexOf(':');
        if (idx > 0) {
          final b = entry.substring(0, idx);
          final p = entry.substring(idx + 1);
          try {
            await _client.storage.from(b).remove([p]);
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  /// Küresel akış için yalnızca yazı paylaşımı (X / Reddit tarzı).
  /// Okuyan herkes kendi dilinde otomatik çeviriyle görür.
  Future<JuzzioPost> createTextPost({
    required JuzzioUserProfile author,
    required String text,
    String visibility = 'public',
    String topic = 'general',
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    final clean = text.trim();
    if (clean.isEmpty) throw Exception(_tx('Boş paylaşım yapılamaz.', 'Post cannot be empty.', 'Beitrag darf nicht leer sein.'));
    if (clean.length > 1000) {
      throw Exception(_tx('En fazla 1000 karakter.', 'Up to 1000 characters.', 'Höchstens 1000 Zeichen.'));
    }
    final payload = <String, dynamic>{
      'author_id': uid,
      'author_username': author.username,
      'author_display_name': author.displayName,
      'author_avatar_url': author.avatarUrl,
      'content_type': 'text',
      'caption': clean,
      'hashtags': JuzzioTurkishNormalizer.extractHashtags(clean),
      'media_urls': const <String>[],
      'media_storage_paths': const <String>[],
      'visibility': visibility,
      'comments_enabled': true,
      'client_request_id': '${uid}_${DateTime.now().millisecondsSinceEpoch}',
      'topic': kJuzzioFeedTopics.contains(topic) ? topic : 'general',
    };
    Map<String, dynamic> inserted;
    try {
      inserted = await _client.from('posts').insert(payload).select().single();
    } on PostgrestException catch (e) {
      // Veritabanı dosyası henüz uygulanmadıysa (topic sütunu yok) konu olmadan paylaş
      if (!e.message.contains('topic')) rethrow;
      payload.remove('topic');
      inserted = await _client.from('posts').insert(payload).select().single();
    }
    return JuzzioPost.fromMap(inserted);
  }

  /// Gönderi düzenleme (Yalnızca gönderi sahibi - Bölüm 20.3)
  Future<JuzzioPost> updatePost({
    required String postId,
    required String caption,
    required String locationName,
    required String visibility,
    required bool commentsEnabled,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    final tags = JuzzioTurkishNormalizer.extractHashtags(caption);

    final updated = await _client
        .from('posts')
        .update({
          'caption': caption.trim(),
          'hashtags': tags,
          'location_name': locationName.trim(),
          'visibility': visibility,
          'comments_enabled': commentsEnabled,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', postId)
        .eq('author_id', uid)
        .select()
        .single();

    return JuzzioPost.fromMap(
      updated,
      isLikedByMe: _likedPostIdsCache.contains(postId),
      isSavedByMe: _savedPostIdsCache.contains(postId),
    );
  }

  /// Gönderi silme ve ilişkili Storage dosyalarını temizleme (Bölüm 20.3)
  Future<void> deletePost(JuzzioPost post) async {
    final uid = currentUserId;
    if (uid == null || post.authorId != uid) {
      throw Exception(_tx('Bu gönderiyi silme yetkiniz yok.', 'You are not allowed to delete this post.', 'Du darfst diesen Beitrag nicht löschen.'));
    }

    await _client.from('posts').delete().eq('id', post.id).eq('author_id', uid);

    for (final entry in post.mediaStoragePaths) {
      final idx = entry.indexOf(':');
      if (idx > 0) {
        final b = entry.substring(0, idx);
        final p = entry.substring(idx + 1);
        try {
          await _client.storage.from(b).remove([p]);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 3. BEĞENİ, KAYDETME VE YORUM İŞLEMLERİ (Bölüm 20.1, 21.2, 32)
  // ---------------------------------------------------------------------------
  Future<JuzzioPost> togglePostLike({
    required JuzzioPost post,
    required JuzzioUserProfile currentUser,
    bool forceLikeOnly = false,
  }) async {
    final uid = currentUserId ?? currentUser.id;
    if (uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));

    final alreadyLiked = _likedPostIdsCache.contains(post.id) || post.isLikedByMe;
    if (forceLikeOnly && alreadyLiked) {
      return post;
    }

    if (alreadyLiked) {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', post.id)
          .eq('user_id', uid);
      _likedPostIdsCache.remove(post.id);
    } else {
      await _client.from('post_likes').upsert(
        {
          'post_id': post.id,
          'user_id': uid,
          'username': currentUser.username,
          'display_name': currentUser.displayName,
          'avatar_url': currentUser.avatarUrl,
        },
        onConflict: 'post_id,user_id',
      );
      _likedPostIdsCache.add(post.id);
      // Bildirim veritabanı tetikleyicisi (sync_post_likes_count) tarafından tek seferlik üretilir.
    }

    final refreshed = await fetchPostById(post.id);
    if (refreshed != null) return refreshed;

    final nextLikes = alreadyLiked ? (post.likesCount - 1).clamp(0, 1 << 30) : post.likesCount + 1;
    return post.copyWith(isLikedByMe: !alreadyLiked, likesCount: nextLikes);
  }

  Future<JuzzioPost> toggleSavePost(JuzzioPost post) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));

    final alreadySaved = _savedPostIdsCache.contains(post.id) || post.isSavedByMe;
    if (alreadySaved) {
      await _client
          .from('saved_posts')
          .delete()
          .eq('post_id', post.id)
          .eq('user_id', uid);
      _savedPostIdsCache.remove(post.id);
    } else {
      await _client.from('saved_posts').upsert(
        {
          'post_id': post.id,
          'user_id': uid,
        },
        onConflict: 'user_id,post_id',
      );
      _savedPostIdsCache.add(post.id);
    }

    final refreshed = await fetchPostById(post.id);
    if (refreshed != null) return refreshed;

    final nextSaves = alreadySaved ? (post.savesCount - 1).clamp(0, 1 << 30) : post.savesCount + 1;
    return post.copyWith(isSavedByMe: !alreadySaved, savesCount: nextSaves);
  }

  Future<List<JuzzioComment>> fetchPostComments({
    required String postId,
    int limit = 50,
    DateTime? afterCreatedAt,
    bool newestFirst = false,
  }) async {
    final uid = currentUserId;
    if (uid != null) {
      try {
        final myLikes = await _client
            .from('comment_likes')
            .select('comment_id')
            .eq('user_id', uid)
            .limit(500);
        _likedCommentIdsCache
          ..clear()
          ..addAll((myLikes as List).map((e) => (e['comment_id'] ?? '').toString()));
      } catch (_) {}
    }

    var query = _client.from('post_comments').select().eq('post_id', postId);
    if (afterCreatedAt != null) {
      query = query.gt('created_at', afterCreatedAt.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: !newestFirst)
        .order('id', ascending: !newestFirst)
        .limit(limit);

    final flat = (rows as List)
        .map((e) {
          final map = e as Map<String, dynamic>;
          final cid = (map['id'] ?? '').toString();
          return JuzzioComment.fromMap(map, isLikedByMe: _likedCommentIdsCache.contains(cid));
        })
        .where((c) => !_blockedUserIdsCache.contains(c.authorId))
        .toList();

    // Yanıtları ait oldukları kök yorumun hemen altına yerleştir (yanıtlar her zaman eskiden yeniye)
    final roots = flat.where((c) => c.parentCommentId == null).toList();
    final rootIds = roots.map((c) => c.id).toSet();
    final repliesByParent = <String, List<JuzzioComment>>{};
    for (final c in flat.where((c) => c.parentCommentId != null)) {
      repliesByParent.putIfAbsent(c.parentCommentId!, () => []).add(c);
    }
    for (final list in repliesByParent.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final ordered = <JuzzioComment>[];
    for (final r in roots) {
      ordered.add(r);
      ordered.addAll(repliesByParent[r.id] ?? const []);
    }
    // Kökü bu sayfada olmayan yanıtlar
    for (final entry in repliesByParent.entries) {
      if (!rootIds.contains(entry.key)) ordered.addAll(entry.value);
    }
    return ordered;
  }

  Future<JuzzioComment> addComment({
    required JuzzioPost post,
    required JuzzioUserProfile author,
    required String content,
    String? parentCommentId,
    String replyToUsername = '',
    String? clientRequestId,
  }) async {
    final uid = currentUserId ?? author.id;
    if (uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    if (!post.commentsEnabled) {
      throw Exception(_tx('Bu gönderi için yorumlar kapatılmış.', 'Comments are turned off for this post.', 'Kommentare sind für diesen Beitrag deaktiviert.'));
    }
    final clean = content.trim();
    if (clean.isEmpty) {
      throw Exception(_tx('Yorum metni boş olamaz.', 'The comment cannot be empty.', 'Der Kommentar darf nicht leer sein.'));
    }
    if (clean.length > 2000) {
      throw Exception(_tx('Yorum en fazla 2000 karakter olabilir.', 'A comment can be at most 2000 characters.', 'Ein Kommentar darf höchstens 2000 Zeichen lang sein.'));
    }

    final reqId = clientRequestId ?? '${uid}_${DateTime.now().millisecondsSinceEpoch}';
    final inserted = await _client
        .from('post_comments')
        .insert({
          'post_id': post.id,
          'author_id': uid,
          'author_username': author.username,
          'author_display_name': author.displayName,
          'author_avatar_url': author.avatarUrl,
          'parent_comment_id': parentCommentId,
          'reply_to_username': replyToUsername.trim().replaceAll('@', ''),
          'content': clean,
          'client_request_id': reqId,
        })
        .select()
        .single();

    // Yorum/yanıt bildirimleri veritabanı tetikleyicisi tarafından üretilir.
    return JuzzioComment.fromMap(inserted);
  }

  Future<void> deleteComment({
    required String commentId,
    required String postId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    await _client.from('post_comments').delete().eq('id', commentId);
  }

  Future<JuzzioComment> toggleCommentLike(JuzzioComment comment) async {
    final uid = currentUserId;
    if (uid == null) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));

    final liked = _likedCommentIdsCache.contains(comment.id) || comment.isLikedByMe;
    if (liked) {
      await _client
          .from('comment_likes')
          .delete()
          .eq('comment_id', comment.id)
          .eq('user_id', uid);
      _likedCommentIdsCache.remove(comment.id);
      return comment.copyWith(
        isLikedByMe: false,
        likesCount: (comment.likesCount - 1).clamp(0, 1 << 30),
      );
    } else {
      await _client.from('comment_likes').upsert(
        {
          'comment_id': comment.id,
          'user_id': uid,
        },
        onConflict: 'comment_id,user_id',
      );
      _likedCommentIdsCache.add(comment.id);
      return comment.copyWith(
        isLikedByMe: true,
        likesCount: comment.likesCount + 1,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4. TAKİP İLİŞKİLERİ VE PROFİL SAYAÇLARI (Arkadaşlık İsteğinden Ayrı - Bölüm 6.5, 24.3)
  // ---------------------------------------------------------------------------
  Future<JuzzioProfileSocialCounts> fetchProfileSocialCounts(String targetUserId) async {
    if (targetUserId.trim().isEmpty) {
      return const JuzzioProfileSocialCounts();
    }
    await refreshMyInteractionSets();
    final uid = currentUserId;

    int postsCount = 0;
    int followersCount = 0;
    int followingCount = 0;
    JuzzioFollowRelationState relation = JuzzioFollowRelationState.none;

    if (_blockedUserIdsCache.contains(targetUserId)) {
      return const JuzzioProfileSocialCounts(
        myRelationToUser: JuzzioFollowRelationState.blocked,
        isBlockedBetween: true,
      );
    }

    try {
      final postRows = await _client
          .from('posts')
          .select('id')
          .eq('author_id', targetUserId)
          .eq('is_deleted', false);
      postsCount = (postRows as List).length;
    } catch (_) {}

    try {
      final followerRows = await _client
          .from('follows')
          .select('id')
          .eq('following_id', targetUserId)
          .eq('status', 'following');
      followersCount = (followerRows as List).length;
    } catch (_) {}

    try {
      final followingRows = await _client
          .from('follows')
          .select('id')
          .eq('follower_id', targetUserId)
          .eq('status', 'following');
      followingCount = (followingRows as List).length;
    } catch (_) {}

    if (uid != null && uid.isNotEmpty && uid != targetUserId) {
      try {
        final myRow = await _client
            .from('follows')
            .select('status')
            .eq('follower_id', uid)
            .eq('following_id', targetUserId)
            .maybeSingle();
        if (myRow != null) {
          final st = (myRow['status'] ?? '').toString();
          if (st == 'following') {
            relation = JuzzioFollowRelationState.following;
          } else if (st == 'pending') {
            relation = JuzzioFollowRelationState.pending;
          }
        }
      } catch (_) {}
    }

    return JuzzioProfileSocialCounts(
      postsCount: postsCount,
      followersCount: followersCount,
      followingCount: followingCount,
      myRelationToUser: relation,
      isBlockedBetween: _blockedUserIdsCache.contains(targetUserId),
      isMutedByMe: _mutedUserIdsCache.contains(targetUserId),
    );
  }

  Future<JuzzioFollowRelationState> followOrRequestUser({
    required JuzzioUserProfile myProfile,
    required JuzzioUserProfile targetUser,
    bool isTargetPrivate = false,
  }) async {
    final uid = currentUserId ?? myProfile.id;
    if (uid.isEmpty || uid == targetUser.id) {
      throw Exception(_tx('Geçersiz takip işlemi.', 'Invalid follow action.', 'Ungültige Folgen-Aktion.'));
    }
    if (_blockedUserIdsCache.contains(targetUser.id)) {
      throw Exception(_tx('Bu kullanıcı ile etkileşim kurulamaz.', 'You cannot interact with this user.', 'Du kannst mit diesem Nutzer nicht interagieren.'));
    }

    bool targetPrivate = isTargetPrivate;
    try {
      final profRow = await _client
          .from('profiles')
          .select('is_private_account')
          .eq('id', targetUser.id)
          .maybeSingle();
      if (profRow != null) {
        targetPrivate = profRow['is_private_account'] == true;
      }
    } catch (_) {}

    final desiredStatus = targetPrivate ? 'pending' : 'following';

    await _client.from('follows').upsert(
      {
        'follower_id': uid,
        'follower_username': myProfile.username,
        'follower_display_name': myProfile.displayName,
        'follower_avatar_url': myProfile.avatarUrl,
        'following_id': targetUser.id,
        'following_username': targetUser.username,
        'following_display_name': targetUser.displayName,
        'following_avatar_url': targetUser.avatarUrl,
        'status': desiredStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'follower_id,following_id',
    );

    // Takip bildirimi veritabanı tetikleyicisi (notify_on_follow_change) tarafından üretilir.
    return targetPrivate
        ? JuzzioFollowRelationState.pending
        : JuzzioFollowRelationState.following;
  }

  Future<JuzzioFollowRelationState> unfollowOrCancelRequest({
    required String targetUserId,
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));

    await _client
        .from('follows')
        .delete()
        .eq('follower_id', uid)
        .eq('following_id', targetUserId);

    return JuzzioFollowRelationState.none;
  }

  Future<void> respondToFollowRequest({
    required JuzzioFollowRecord request,
    required JuzzioUserProfile myProfile,
    required bool accept,
  }) async {
    final uid = currentUserId ?? myProfile.id;
    if (uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));

    if (accept) {
      await _client
          .from('follows')
          .update({
            'status': 'following',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', request.id)
          .eq('following_id', uid);
    } else {
      await _client
          .from('follows')
          .delete()
          .eq('id', request.id)
          .eq('following_id', uid);
    }
  }

  Future<List<JuzzioFollowRecord>> fetchFollowers(String userId, {int limit = 60}) async {
    final rows = await _client
        .from('follows')
        .select()
        .eq('following_id', userId)
        .eq('status', 'following')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => JuzzioFollowRecord.fromMap(e as Map<String, dynamic>))
        .where((r) => !_blockedUserIdsCache.contains(r.followerId))
        .toList();
  }

  Future<List<JuzzioFollowRecord>> fetchFollowing(String userId, {int limit = 60}) async {
    final rows = await _client
        .from('follows')
        .select()
        .eq('follower_id', userId)
        .eq('status', 'following')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => JuzzioFollowRecord.fromMap(e as Map<String, dynamic>))
        .where((r) => !_blockedUserIdsCache.contains(r.followingId))
        .toList();
  }

  Future<List<JuzzioFollowRecord>> fetchPendingFollowRequests() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return const [];
    final rows = await _client
        .from('follows')
        .select()
        .eq('following_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => JuzzioFollowRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 5. HİKÂYE GÖRÜNTÜLEME, SİLME VE GÖRÜNTÜLEYENLER LİSTESİ (Bölüm 18.3, 18.4)
  // ---------------------------------------------------------------------------
  Future<void> recordStoryView({
    required JuzzioStory story,
    required JuzzioUserProfile viewer,
  }) async {
    final uid = currentUserId ?? viewer.id;
    if (uid.isEmpty || story.id.startsWith('local_') || story.isExpired) return;
    try {
      await _client.from('story_views').upsert(
        {
          'story_id': story.id,
          'viewer_id': uid,
          'viewer_username': viewer.username,
          'viewer_display_name': viewer.displayName,
          'viewer_avatar_url': viewer.avatarUrl,
          'viewed_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'story_id,viewer_id',
      );
    } catch (_) {}
  }

  Future<List<JuzzioStoryViewItem>> fetchStoryViewers(String storyId) async {
    if (storyId.isEmpty || storyId.startsWith('local_')) return const [];
    final rows = await _client
        .from('story_views')
        .select()
        .eq('story_id', storyId)
        .order('viewed_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((e) => JuzzioStoryViewItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteStory(JuzzioStory story) async {
    final uid = currentUserId;
    if (uid == null || story.userId != uid) {
      throw Exception(_tx('Bu hikâyeyi silme yetkiniz yok.', 'You are not allowed to delete this story.', 'Du darfst diese Story nicht löschen.'));
    }
    if (!story.id.startsWith('local_')) {
      await _client.from('stories').delete().eq('id', story.id).eq('user_id', uid);
    }
  }

  // ---------------------------------------------------------------------------
  // 6. BİLDİRİMLER: GERÇEK LİSTE, OKUNDU VE HEDEF YÖNLENDİRME (Bölüm 6.15, 28)
  // ---------------------------------------------------------------------------
  Future<void> createNotificationIfAllowed({
    required String recipientId,
    required JuzzioUserProfile actor,
    required String eventType,
    String targetId = '',
    String targetSecondaryId = '',
    String previewText = '',
    String? mediaThumbUrl,
    String? dedupeKey,
  }) async {
    if (recipientId.isEmpty || recipientId == actor.id) return;
    if (_blockedUserIdsCache.contains(recipientId)) return;

    try {
      await _client.from('notifications').upsert(
        {
          'recipient_id': recipientId,
          'actor_id': actor.id,
          'actor_username': actor.username,
          'actor_display_name': actor.displayName,
          'actor_avatar_url': actor.avatarUrl,
          'event_type': eventType,
          'target_id': targetId,
          'target_secondary_id': targetSecondaryId,
          'preview_text': previewText,
          'media_thumb_url': mediaThumbUrl,
          'dedupe_key': dedupeKey ?? '${eventType}_${actor.id}_${targetId}_${DateTime.now().millisecondsSinceEpoch}',
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'recipient_id,dedupe_key',
      );
    } catch (_) {}
  }

  Future<List<JuzzioNotificationItem>> fetchNotifications({
    bool unreadOnly = false,
    String? eventCategory, // 'all' | 'follow' | 'like' | 'comment' | 'message' | 'call'
    int limit = 60,
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return const [];

    var query = _client
        .from('notifications')
        .select()
        .eq('recipient_id', uid)
        .inFilter('event_type', kJuzzioSocialEventTypes.toList());
    if (unreadOnly) {
      query = query.eq('is_read', false);
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    final list = (rows as List)
        .map((e) => JuzzioNotificationItem.fromMap(e as Map<String, dynamic>))
        .where((n) => n.actorId == null || !_blockedUserIdsCache.contains(n.actorId!))
        .toList();

    if (eventCategory == null || eventCategory == 'all') return list;
    return list.where((n) {
      if (eventCategory == 'follow') {
        return n.eventType.contains('follow') || n.eventType.contains('friend');
      }
      if (eventCategory == 'like') {
        return n.eventType == 'like' || n.eventType == 'story_like';
      }
      if (eventCategory == 'comment') {
        return n.eventType == 'comment' || n.eventType == 'reply' || n.eventType == 'story_reply';
      }
      if (eventCategory == 'save') {
        return n.eventType == 'save';
      }
      return true;
    }).toList();
  }

  Stream<List<JuzzioNotificationItem>> watchMyNotifications() {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return Stream.value(const []);
    try {
      return _client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(200)
          .map((rows) => rows
              .map(JuzzioNotificationItem.fromMap)
              .where((n) => kJuzzioSocialEventTypes.contains(n.eventType))
              .where((n) => n.actorId == null || !_blockedUserIdsCache.contains(n.actorId!))
              .toList());
    } catch (_) {
      return Stream.fromFuture(fetchNotifications());
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final uid = currentUserId;
    if (uid == null || notificationId.isEmpty) return;
    await _client
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', notificationId)
        .eq('recipient_id', uid);
  }

  Future<void> markAllNotificationsRead() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return;
    await _client
        .from('notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('recipient_id', uid)
        .inFilter('event_type', kJuzzioSocialEventTypes.toList())
        .eq('is_read', false);
  }

  Future<void> deleteNotification(String notificationId) async {
    final uid = currentUserId;
    if (uid == null || notificationId.isEmpty) return;
    await _client
        .from('notifications')
        .delete()
        .eq('id', notificationId)
        .eq('recipient_id', uid);
  }

  // ---------------------------------------------------------------------------
  // 7. ENGELLEME, SESSİZE ALMA VE ŞİKÂYET (Bölüm 20.4, 29.4, 31)
  // ---------------------------------------------------------------------------
  Future<void> blockUser({
    required JuzzioUserProfile targetUser,
    String reason = '',
  }) async {
    final uid = currentUserId;
    if (uid == null || uid == targetUser.id) throw Exception(_tx('Geçersiz işlem.', 'Invalid action.', 'Ungültige Aktion.'));

    await _client.from('blocked_users').upsert(
      {
        'blocker_id': uid,
        'blocked_id': targetUser.id,
        'blocked_username': targetUser.username,
        'blocked_display_name': targetUser.displayName,
        'blocked_avatar_url': targetUser.avatarUrl,
        'reason': reason,
      },
      onConflict: 'blocker_id,blocked_id',
    );
    _blockedUserIdsCache.add(targetUser.id);

    // İki taraflı takip ve arkadaşlık ilişkilerini temizle
    try {
      await _client
          .from('follows')
          .delete()
          .or('and(follower_id.eq.$uid,following_id.eq.${targetUser.id}),and(follower_id.eq.${targetUser.id},following_id.eq.$uid)');
    } catch (_) {}
    try {
      await _client
          .from('friendships')
          .delete()
          .or('and(requester_id.eq.$uid,receiver_id.eq.${targetUser.id}),and(requester_id.eq.${targetUser.id},receiver_id.eq.$uid)');
    } catch (_) {}
  }

  Future<void> unblockUser(String blockedUserId) async {
    final uid = currentUserId;
    if (uid == null || blockedUserId.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', blockedUserId);
    _blockedUserIdsCache.remove(blockedUserId);
  }

  Future<List<JuzzioBlockedUserItem>> fetchBlockedUsers() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return const [];
    final rows = await _client
        .from('blocked_users')
        .select()
        .eq('blocker_id', uid)
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((e) => JuzzioBlockedUserItem.fromMap(e as Map<String, dynamic>))
        .toList();
    _blockedUserIdsCache
      ..clear()
      ..addAll(list.map((e) => e.blockedId));
    return list;
  }

  Future<void> toggleMuteUser(String targetUserId, {required bool mute}) async {
    final uid = currentUserId;
    if (uid == null || uid == targetUserId) throw Exception(_tx('Geçersiz işlem.', 'Invalid action.', 'Ungültige Aktion.'));
    if (mute) {
      await _client.from('muted_users').upsert(
        {
          'muter_id': uid,
          'muted_id': targetUserId,
          'mute_posts': true,
          'mute_stories': true,
        },
        onConflict: 'muter_id,muted_id',
      );
      _mutedUserIdsCache.add(targetUserId);
    } else {
      await _client
          .from('muted_users')
          .delete()
          .eq('muter_id', uid)
          .eq('muted_id', targetUserId);
      _mutedUserIdsCache.remove(targetUserId);
    }
  }

  Future<void> submitReport({
    required String targetType, // 'post' | 'comment' | 'story' | 'user' | 'message'
    required String targetId,
    String? targetOwnerId,
    required String reasonCode, // 'spam' | 'harassment' | 'inappropriate' | 'fake_account' | 'other'
    String details = '',
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) throw Exception(_tx('Oturum açık değil.', 'You are not signed in.', 'Du bist nicht angemeldet.'));
    if (targetId.trim().isEmpty) throw Exception(_tx('Hedef içerik bulunamadı.', 'The target content was not found.', 'Der Zielinhalt wurde nicht gefunden.'));

    await _client.from('reports').upsert(
      {
        'reporter_id': uid,
        'target_type': targetType,
        'target_id': targetId.trim(),
        'target_owner_id': targetOwnerId,
        'reason_code': reasonCode,
        'details': details.trim(),
        'status': 'open',
      },
      onConflict: 'reporter_id,target_type,target_id',
    );
  }

  // ---------------------------------------------------------------------------
  // 8. BİRLEŞİK ARAMA VE SON ARAMALAR (Türkçe İ/i/ı/I Uyumlu - Bölüm 6.4, 23.2)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> searchUnified(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty) {
      return {
        'users': <JuzzioUserProfile>[],
        'posts': <JuzzioPost>[],
        'hashtags': <Map<String, dynamic>>[],
      };
    }

    await refreshMyInteractionSets();
    final uid = currentUserId;

    // 1. Kişiler araması
    final allProfiles = await SupabaseService.instance.fetchAllProfiles();
    final matchedUsers = allProfiles.where((u) {
      if (u.id == uid || _blockedUserIdsCache.contains(u.id)) return false;
      return JuzzioTurkishNormalizer.matchesQuery(u.username, q) ||
          JuzzioTurkishNormalizer.matchesQuery(u.displayName, q) ||
          JuzzioTurkishNormalizer.matchesQuery(u.bio, q);
    }).toList();

    // 2. Gönderi araması
    final recentPosts = await fetchFeedPosts(limit: 80);
    final matchedPosts = <JuzzioPost>[];
    final tagCounter = <String, int>{};

    for (final p in recentPosts) {
      for (final t in p.hashtags) {
        final normTag = JuzzioTurkishNormalizer.toLowerTurkish(t);
        if (JuzzioTurkishNormalizer.matchesQuery(normTag, q.replaceAll('#', ''))) {
          tagCounter[normTag] = (tagCounter[normTag] ?? 0) + 1;
        }
      }
      final matches = JuzzioTurkishNormalizer.matchesQuery(p.caption, q) ||
          JuzzioTurkishNormalizer.matchesQuery(p.authorUsername, q) ||
          JuzzioTurkishNormalizer.matchesQuery(p.authorDisplayName, q) ||
          JuzzioTurkishNormalizer.matchesQuery(p.locationName, q) ||
          p.hashtags.any((t) => JuzzioTurkishNormalizer.matchesQuery(t, q.replaceAll('#', '')));
      if (matches) {
        matchedPosts.add(p);
      }
    }

    final matchedHashtags = tagCounter.entries
        .map((e) => {'tag': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return {
      'users': matchedUsers,
      'posts': matchedPosts,
      'hashtags': matchedHashtags,
    };
  }

  void hideRecommendationForSession(String userId) {
    if (userId.isNotEmpty) {
      _hiddenRecommendationIds.add(userId);
    }
  }

  bool isRecommendationHidden(String userId) => _hiddenRecommendationIds.contains(userId);

  // Kullanıcıya özel yerel son aramalar kalıcılığı (Bölüm 23.2)
  Future<File> _recentSearchFile() async {
    final dir = await getApplicationSupportDirectory();
    final uid = currentUserId ?? 'guest';
    return File('${dir.path}/juzzio_recent_searches_$uid.json');
  }

  Future<List<String>> loadRecentSearches() async {
    try {
      final f = await _recentSearchFile();
      if (!f.existsSync()) return const [];
      final list = jsonDecode(await f.readAsString());
      if (list is List) {
        return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<String>> addRecentSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return loadRecentSearches();
    final current = List<String>.from(await loadRecentSearches());
    current.removeWhere((item) => JuzzioTurkishNormalizer.toLowerTurkish(item) == JuzzioTurkishNormalizer.toLowerTurkish(clean));
    current.insert(0, clean);
    final trimmed = current.take(15).toList();
    try {
      final f = await _recentSearchFile();
      await f.writeAsString(jsonEncode(trimmed));
    } catch (_) {}
    return trimmed;
  }

  Future<List<String>> removeRecentSearch(String query) async {
    final current = List<String>.from(await loadRecentSearches());
    current.remove(query);
    try {
      final f = await _recentSearchFile();
      await f.writeAsString(jsonEncode(current));
    } catch (_) {}
    return current;
  }

  Future<void> clearRecentSearches() async {
    try {
      final f = await _recentSearchFile();
      if (f.existsSync()) {
        await f.writeAsString('[]');
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 9. GERÇEK DEPOLAMA & ÖNBELLEK ÖLÇÜMÜ VE GÜVENLİ TEMİZLİK (Bölüm 29.10)
  // ---------------------------------------------------------------------------
  Future<Map<String, int>> measureLocalStorageBytes() async {
    int tempBytes = 0;
    int supportBytes = 0;

    Future<int> folderBytes(Directory d) async {
      if (!d.existsSync()) return 0;
      int sum = 0;
      try {
        for (final entity in d.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              sum += entity.lengthSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
      return sum;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      tempBytes = await folderBytes(tempDir);
    } catch (_) {}

    try {
      final supDir = await getApplicationSupportDirectory();
      supportBytes = await folderBytes(supDir);
    } catch (_) {}

    return {
      'cacheBytes': tempBytes,
      'appDataBytes': supportBytes,
      'totalBytes': tempBytes + supportBytes,
    };
  }

  Future<int> clearSafeTemporaryCache() async {
    int freed = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(recursive: false, followLinks: false)) {
          try {
            if (entity is File) {
              freed += entity.lengthSync();
              await entity.delete();
            } else if (entity is Directory) {
              for (final sub in entity.listSync(recursive: true, followLinks: false)) {
                if (sub is File) freed += sub.lengthSync();
              }
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return freed;
  }
}
