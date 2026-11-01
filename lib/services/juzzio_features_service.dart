// =============================================================================
// JUZZIO v0.3.0 — Yeni özellik servisleri
//  • Profil ekstraları (web sitesi, YouTube müziği), rozetler ve mavi tik
//  • Grup yönetimi (yönetici / moderatör / üye), susturma, moderasyon
//  • Civciv oyunu
//  • Yönetici paneli (hash'li şifre + cihazda güvenli saklanan oturum belirteci)
//  • Cihaz kimliği ve cihaz engeli kontrolü
// Tüm hata mesajları SupabaseService.friendlyError ile kullanıcının dilindedir.
// =============================================================================

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/app_theme_and_locale.dart';
import 'supabase_service.dart';

class JuzzioBadgeInfo {
  final int voiceMinutes;
  final int videoMinutes;
  final bool verified;
  final List<String> badges;

  const JuzzioBadgeInfo({
    this.voiceMinutes = 0,
    this.videoMinutes = 0,
    this.verified = false,
    this.badges = const [],
  });

  factory JuzzioBadgeInfo.fromMap(Map<String, dynamic> map) {
    final raw = map['badges'];
    return JuzzioBadgeInfo(
      voiceMinutes: (map['voice_minutes'] as num?)?.toInt() ?? 0,
      videoMinutes: (map['video_minutes'] as num?)?.toInt() ?? 0,
      verified: map['verified'] == true,
      badges: raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
  }
}

class JuzzioGroupMember {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String role; // owner | moderator | member
  final DateTime? mutedUntil;
  final bool isVerified;

  const JuzzioGroupMember({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.role = 'member',
    this.mutedUntil,
    this.isVerified = false,
  });

  bool get isOwner => role == 'owner';
  bool get isModerator => role == 'moderator';
  bool get isMuted => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());

  factory JuzzioGroupMember.fromMap(Map<String, dynamic> map) {
    return JuzzioGroupMember(
      userId: (map['user_id'] ?? '').toString(),
      username: (map['username'] ?? '').toString(),
      displayName: (map['display_name'] ?? map['username'] ?? '').toString(),
      avatarUrl: (map['avatar_url']?.toString().trim().isNotEmpty ?? false) ? map['avatar_url'].toString() : null,
      role: (map['role'] ?? 'member').toString(),
      mutedUntil: DateTime.tryParse(map['muted_until']?.toString() ?? ''),
      isVerified: map['is_verified'] == true,
    );
  }
}

class JuzzioChickInvite {
  final String id;
  final bool incoming;
  final String chickName;
  final String otherName;
  final String? otherAvatar;

  const JuzzioChickInvite({
    required this.id,
    required this.incoming,
    required this.chickName,
    required this.otherName,
    this.otherAvatar,
  });

  factory JuzzioChickInvite.fromMap(Map<String, dynamic> map) => JuzzioChickInvite(
        id: (map['id'] ?? '').toString(),
        incoming: map['incoming'] == true,
        chickName: (map['chick_name'] ?? '').toString(),
        otherName: (map['other_name'] ?? '').toString(),
        otherAvatar: map['other_avatar']?.toString(),
      );
}

class JuzzioChickState {
  final bool hasChick;
  final String id;
  final String name;
  final int xp;
  final int stage; // 0 yumurta · 1 civciv · 2 genç · 3 tavuk
  final int? nextStageXp;
  final double hoursSinceFed;
  final String mood; // happy | hungry | dying
  final DateTime? myNextFeedAt;
  final String partnerName;
  final String? partnerAvatar;
  final List<JuzzioChickInvite> invites;
  final String? lastChickName;
  final String? lastChickStatus; // dead | released

  const JuzzioChickState({
    this.hasChick = false,
    this.id = '',
    this.name = '',
    this.xp = 0,
    this.stage = 0,
    this.nextStageXp,
    this.hoursSinceFed = 0,
    this.mood = 'happy',
    this.myNextFeedAt,
    this.partnerName = '',
    this.partnerAvatar,
    this.invites = const [],
    this.lastChickName,
    this.lastChickStatus,
  });

  bool get canFeedNow => myNextFeedAt == null || !myNextFeedAt!.isAfter(DateTime.now());

  factory JuzzioChickState.fromMap(Map<String, dynamic> map) {
    final partner = map['partner'] is Map ? Map<String, dynamic>.from(map['partner'] as Map) : const <String, dynamic>{};
    final invitesRaw = map['invites'];
    final last = map['last_chick'] is Map ? Map<String, dynamic>.from(map['last_chick'] as Map) : null;
    return JuzzioChickState(
      hasChick: map['has_chick'] == true,
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      xp: (map['xp'] as num?)?.toInt() ?? 0,
      stage: (map['stage'] as num?)?.toInt() ?? 0,
      nextStageXp: (map['next_stage_xp'] as num?)?.toInt(),
      hoursSinceFed: (map['hours_since_fed'] as num?)?.toDouble() ?? 0,
      mood: (map['mood'] ?? 'happy').toString(),
      myNextFeedAt: DateTime.tryParse(map['my_next_feed_at']?.toString() ?? '')?.toLocal(),
      partnerName: (partner['display_name'] ?? partner['username'] ?? '').toString(),
      partnerAvatar: partner['avatar_url']?.toString(),
      invites: invitesRaw is List
          ? invitesRaw.whereType<Map>().map((m) => JuzzioChickInvite.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
      lastChickName: last?['name']?.toString(),
      lastChickStatus: last?['status']?.toString(),
    );
  }
}

class JuzzioRelationship {
  final String friendStatus; // friends | outgoing | incoming | none
  final bool isPrivate;
  final bool blocked;
  final int friendCount;

  const JuzzioRelationship({
    this.friendStatus = 'none',
    this.isPrivate = false,
    this.blocked = false,
    this.friendCount = 0,
  });

  bool get isFriend => friendStatus == 'friends';

  factory JuzzioRelationship.fromMap(Map<String, dynamic> map) => JuzzioRelationship(
        friendStatus: (map['friend_status'] ?? 'none').toString(),
        isPrivate: map['is_private'] == true,
        blocked: map['blocked'] == true,
        friendCount: (map['friend_count'] as num?)?.toInt() ?? 0,
      );
}

class JuzzioAppConfig {
  final bool maintenanceMode;
  final String maintenanceMessage;
  final bool signupsEnabled;
  final bool liveTranslationEnabled;
  final bool chickGameEnabled;
  final bool storiesEnabled;
  final bool beautyFilterEnabled;
  // v0.6: cam teması, içerik denetimi ve genişletilmiş özellik bayrakları
  final String defaultGlassPalette;
  final bool callModerationEnabled;
  final bool speechModerationEnabled;
  final bool avatarModerationEnabled;
  final int callModerationIntervalSec;
  final bool postsEnabled;
  final bool callsEnabled;
  final bool groupCreationEnabled;
  final bool globalFeedEnabled;
  final String announcementBanner;

  const JuzzioAppConfig({
    this.maintenanceMode = false,
    this.maintenanceMessage = '',
    this.signupsEnabled = true,
    this.liveTranslationEnabled = true,
    this.chickGameEnabled = true,
    this.storiesEnabled = true,
    this.beautyFilterEnabled = true,
    this.defaultGlassPalette = 'juzzio_liquid',
    this.callModerationEnabled = true,
    this.speechModerationEnabled = true,
    this.avatarModerationEnabled = true,
    this.callModerationIntervalSec = 6,
    this.postsEnabled = true,
    this.callsEnabled = true,
    this.groupCreationEnabled = true,
    this.globalFeedEnabled = true,
    this.announcementBanner = '',
  });

  factory JuzzioAppConfig.fromMap(Map<String, dynamic> map) {
    bool b(String k, bool d) => map[k] is bool ? map[k] as bool : d;
    return JuzzioAppConfig(
      maintenanceMode: b('maintenance_mode', false),
      maintenanceMessage: (map['maintenance_message'] ?? '').toString(),
      signupsEnabled: b('signups_enabled', true),
      liveTranslationEnabled: b('live_translation_enabled', true),
      chickGameEnabled: b('chick_game_enabled', true),
      storiesEnabled: b('stories_enabled', true),
      beautyFilterEnabled: b('beauty_filter_enabled', true),
      defaultGlassPalette: (map['default_glass_palette'] ?? 'juzzio_liquid').toString(),
      callModerationEnabled: b('call_moderation_enabled', true),
      speechModerationEnabled: b('speech_moderation_enabled', true),
      avatarModerationEnabled: b('avatar_moderation_enabled', true),
      callModerationIntervalSec: ((map['call_moderation_interval_sec'] is num)
              ? (map['call_moderation_interval_sec'] as num).toInt()
              : 6)
          .clamp(3, 60),
      postsEnabled: b('posts_enabled', true),
      callsEnabled: b('calls_enabled', true),
      groupCreationEnabled: b('group_creation_enabled', true),
      globalFeedEnabled: b('global_feed_enabled', true),
      announcementBanner: (map['announcement_banner'] ?? '').toString(),
    );
  }
}

class JuzzioFeaturesService {
  JuzzioFeaturesService._();
  static final JuzzioFeaturesService instance = JuzzioFeaturesService._();

  SupabaseService get _svc => SupabaseService.instance;

  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _deviceIdKey = 'juzzio_device_id_v1';
  static const String _adminTokenKey = 'juzzio_admin_token_v1';

  Never _fail(Object e) => throw JuzzioServiceException(_svc.friendlyError(e));

  Map<String, dynamic> _asMap(dynamic res) => res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};

  // ---------------------------------------------------------------------------
  // CİHAZ KİMLİĞİ & ENGEL
  // ---------------------------------------------------------------------------
  String? _cachedDeviceId;

  /// Kurulum başına rastgele ve kalıcı cihaz kimliği (güvenli depoda saklanır).
  Future<String> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    // Android: uygulama yeniden kurulsa da değişmeyen cihaz kimliği (kalıcı engel yeni hesap
    // açmayı da engeller). Alınamazsa kuruluma özgü rastgele kimliğe düşülür.
    try {
      final hw = await const MethodChannel('juzzio/notifications').invokeMethod<String>('getHardwareDeviceId');
      if (hw != null && hw.length >= 16 && hw.length <= 128) {
        _cachedDeviceId = hw;
        return hw;
      }
    } catch (_) {}
    String? stored;
    try {
      stored = await _secure.read(key: _deviceIdKey);
    } catch (_) {}
    if (stored == null || stored.length < 16) {
      final rnd = Random.secure();
      stored = List<int>.generate(24, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        await _secure.write(key: _deviceIdKey, value: stored);
      } catch (_) {}
    }
    _cachedDeviceId = stored;
    return stored;
  }

  /// true → bu cihaz/hesap engellenmiş. Ağ hatasında false döner (çevrimdışı kullanım engellenmez).
  /// [until] doluysa süreli uzaklaştırmadır (süre dolunca erişim kendiliğinden açılır).
  Future<({bool banned, String reason, DateTime? until, bool moderation})> checkDeviceAccess({bool register = false}) async {
    try {
      final id = await deviceId();
      final res = register && _svc.currentUserId != null
          ? await _svc.client.rpc('register_my_device', params: {'p_device_id': id, 'p_platform': 'android'})
          : await _svc.client.rpc('check_device_access', params: {'p_device_id': id});
      final map = _asMap(res);
      return (
        banned: map['banned'] == true,
        reason: (map['reason'] ?? '').toString(),
        until: DateTime.tryParse((map['until'] ?? '').toString())?.toLocal(),
        moderation: map['moderation'] == true,
      );
    } catch (_) {
      return (banned: false, reason: '', until: null, moderation: false);
    }
  }

  /// Kayıt öncesi kontrol: kalıcı engelli e-posta/cihaz veya uygunsuz ad → hata kodu, uygunsa null.
  Future<String?> checkSignupAllowed({required String email, required String username, required String displayName}) async {
    try {
      final id = await deviceId();
      final map = _asMap(await _svc.client.rpc('juzzio_check_signup', params: {
        'p_email': email,
        'p_username': username,
        'p_display_name': displayName,
        'p_device_id': id,
      }));
      if (map['allowed'] == false) return (map['reason'] ?? 'signup_blocked').toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PROFİL: web sitesi, müzik, gizli cinsiyet, rozetler
  // ---------------------------------------------------------------------------
  Future<void> updateProfileExtras({
    required String websiteUrl,
    required String musicUrl,
    required int musicStartSec,
    required String musicTitle,
  }) async {
    final uid = _svc.currentUserId;
    if (uid == null) _fail('not_authenticated');
    try {
      await _svc.client.from('profiles').update({
        'website_url': websiteUrl.trim(),
        'music_url': musicUrl.trim(),
        'music_start_sec': musicStartSec < 0 ? 0 : musicStartSec,
        'music_title': musicTitle.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      _fail(e);
    }
  }

  /// Son okunan cinsiyet (yalnızca Civciv bildirim metinleri için; profilde gösterilmez).
  String cachedGender = 'unspecified';

  Future<String> fetchMyGender() async {
    try {
      final res = _asMap(await _svc.client.rpc('get_my_private_profile'));
      cachedGender = (res['gender'] ?? 'unspecified').toString();
      return cachedGender;
    } catch (_) {
      return 'unspecified';
    }
  }

  Future<void> setMyGender(String gender) async {
    try {
      await _svc.client.rpc('set_my_gender', params: {'p_gender': gender});
    } catch (e) {
      _fail(e);
    }
  }

  Future<JuzzioBadgeInfo> fetchBadges(String userId) async {
    try {
      final res = await _svc.client.rpc('get_profile_badges', params: {'p_user': userId});
      return JuzzioBadgeInfo.fromMap(_asMap(res));
    } catch (_) {
      return const JuzzioBadgeInfo();
    }
  }

  // ---------------------------------------------------------------------------
  // GRUP YÖNETİMİ
  // ---------------------------------------------------------------------------
  Future<List<JuzzioGroupMember>> fetchGroupMembers(String roomId) async {
    try {
      final res = await _svc.client.rpc('get_group_members', params: {'p_room': roomId});
      if (res is! List) return const [];
      return res.whereType<Map>().map((m) => JuzzioGroupMember.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> setMemberRole({required String roomId, required String userId, required String role}) async {
    try {
      await _svc.client.rpc('set_group_member_role', params: {'p_room': roomId, 'p_user': userId, 'p_role': role});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> removeMember({required String roomId, required String userId}) async {
    try {
      await _svc.client.rpc('remove_group_member', params: {'p_room': roomId, 'p_user': userId});
    } catch (e) {
      _fail(e);
    }
  }

  /// minutes <= 0 → susturmayı kaldırır
  Future<void> muteMember({required String roomId, required String userId, required int minutes}) async {
    try {
      await _svc.client.rpc('mute_group_member', params: {'p_room': roomId, 'p_user': userId, 'p_minutes': minutes});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> moderateDeleteMessage(String messageId) async {
    try {
      await _svc.client.rpc('moderate_delete_message', params: {'p_message': messageId});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> updateGroupInfo({
    required String roomId,
    String? title,
    String? groupType,
    String? groupPurpose,
    String? description,
  }) async {
    try {
      await _svc.client.rpc('update_group_info', params: {
        'p_room': roomId,
        'p_title': title,
        'p_group_type': groupType,
        'p_group_purpose': groupPurpose,
        'p_description': description,
      });
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // CİVCİV OYUNU
  // ---------------------------------------------------------------------------
  Future<JuzzioChickState> fetchMyChick() async {
    try {
      // Sunucuda pg_cron yoksa açılışta açlık/ölüm kontrolünü tetikler (zararsız, idempotent)
      try {
        await _svc.client.rpc('chick_tick');
      } catch (_) {}
      final res = await _svc.client.rpc('get_my_chick');
      return JuzzioChickState.fromMap(_asMap(res));
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> inviteChickPartner({required String friendId, required String chickName}) async {
    try {
      await _svc.client.rpc('invite_chick_partner', params: {'p_friend': friendId, 'p_name': chickName});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> respondChickInvite({required String inviteId, required bool accept}) async {
    try {
      await _svc.client.rpc('respond_chick_invite', params: {'p_invite': inviteId, 'p_accept': accept});
    } catch (e) {
      _fail(e);
    }
  }

  /// Dönüş: (beslendi mi, bir sonraki besleme zamanı)
  Future<({bool fed, DateTime? nextFeedAt})> feedChick() async {
    try {
      final res = _asMap(await _svc.client.rpc('feed_my_chick'));
      return (
        fed: res['ok'] == true,
        nextFeedAt: DateTime.tryParse(res['next_feed_at']?.toString() ?? '')?.toLocal(),
      );
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> releaseChick() async {
    try {
      await _svc.client.rpc('release_my_chick');
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // YÖNETİCİ PANELİ
  // ---------------------------------------------------------------------------
  Future<bool> isAdmin() async {
    try {
      final res = await _svc.client.rpc('am_i_juzzio_admin');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> storedAdminToken() async {
    try {
      final token = await _secure.read(key: _adminTokenKey);
      if (token == null || token.isEmpty) return null;
      final ok = await _svc.client.rpc('admin_check_token', params: {'p_token': token});
      if (ok == true) return token;
      await _secure.delete(key: _adminTokenKey);
    } catch (_) {}
    return null;
  }

  /// Başarılıysa belirteç döner; yanlış şifrede null (kalan deneme hakkı ile).
  Future<({String? token, int remaining})> adminUnlock({required String password, required bool remember}) async {
    try {
      final res = _asMap(await _svc.client.rpc('admin_unlock', params: {
        'p_password': password,
        'p_device_id': await deviceId(),
        'p_remember': remember,
      }));
      if (res['ok'] != true) {
        return (token: null, remaining: (res['remaining'] as num?)?.toInt() ?? 0);
      }
      final token = (res['token'] ?? '').toString();
      if (remember) {
        try {
          await _secure.write(key: _adminTokenKey, value: token);
        } catch (_) {}
      }
      return (token: token, remaining: 5);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminLogout(String token) async {
    try {
      await _svc.client.rpc('admin_logout', params: {'p_token': token});
    } catch (_) {}
    try {
      await _secure.delete(key: _adminTokenKey);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> adminDashboard(String token) async {
    try {
      return _asMap(await _svc.client.rpc('admin_dashboard', params: {'p_token': token}));
    } catch (e) {
      _fail(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminListReports(String token, {String status = 'open'}) async {
    try {
      final res = await _svc.client.rpc('admin_list_reports', params: {'p_token': token, 'p_status': status});
      return res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminSetReportStatus(String token, String reportId, String status, {String note = ''}) async {
    try {
      await _svc.client.rpc('admin_set_report_status',
          params: {'p_token': token, 'p_report': reportId, 'p_status': status, 'p_note': note});
    } catch (e) {
      _fail(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminSearchUsers(String token, String query) async {
    try {
      final res = await _svc.client.rpc('admin_search_users', params: {'p_token': token, 'p_query': query});
      return res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    } catch (e) {
      _fail(e);
    }
  }

  Future<int> adminBanUser(String token, String userId, String reason, {String note = '', bool banDevices = true}) async {
    try {
      final res = _asMap(await _svc.client.rpc('admin_ban_user', params: {
        'p_token': token,
        'p_user': userId,
        'p_reason': reason,
        'p_note': note,
        'p_ban_devices': banDevices,
      }));
      return (res['devices_banned'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminUnbanUser(String token, String userId) async {
    try {
      await _svc.client.rpc('admin_unban_user', params: {'p_token': token, 'p_user': userId});
    } catch (e) {
      _fail(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminListBans(String token) async {
    try {
      final res = await _svc.client.rpc('admin_list_bans', params: {'p_token': token});
      return res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — ARKADAŞLIK, MESAJ İSTEKLERİ, UYGULAMA AYARLARI
  // ---------------------------------------------------------------------------

  /// "Arkadaş Ekle": 'friends' (karşılıklı arkadaş oldunuz) veya 'requested'.
  Future<String> addFriend(String userId) async {
    try {
      final res = await _svc.client.rpc('add_friend', params: {'p_target': userId});
      return (res ?? 'requested').toString();
    } catch (e) {
      _fail(e);
    }
  }

  /// friend_status: friends | outgoing | incoming | none
  Future<JuzzioRelationship> fetchRelationship(String userId) async {
    try {
      final res = _asMap(await _svc.client.rpc('get_relationship', params: {'p_target': userId}));
      return JuzzioRelationship.fromMap(res);
    } catch (_) {
      return const JuzzioRelationship();
    }
  }

  Future<void> respondMessageRequest(String roomId, bool accept) async {
    try {
      await _svc.client.rpc('respond_message_request', params: {'p_room': roomId, 'p_accept': accept});
    } catch (e) {
      _fail(e);
    }
  }

  /// Bakım modu ve özellik bayrakları (giriş yapmadan da okunabilir).
  Future<JuzzioAppConfig> fetchAppConfig() async {
    try {
      final res = _asMap(await _svc.client.rpc('get_app_config'));
      final cfg = JuzzioAppConfig.fromMap(res);
      lastAppConfig = cfg;
      // Yöneticinin seçtiği varsayılan cam teması (kullanıcı kendi temasını seçmediyse)
      JuzzioAppController.instance.applyDefaultGlassPalette(cfg.defaultGlassPalette);
      return cfg;
    } catch (_) {
      return lastAppConfig;
    }
  }

  JuzzioAppConfig lastAppConfig = const JuzzioAppConfig();

  Future<void> updateProfileCard({String? cardBgColor, String? cardBgUrl}) async {
    final uid = _svc.currentUserId;
    if (uid == null) _fail('not_authenticated');
    try {
      await _svc.client.from('profiles').update({
        if (cardBgColor != null) 'card_bg_color': cardBgColor,
        if (cardBgUrl != null) 'card_bg_url': cardBgUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> updateProfileMusic({
    required String musicUrl,
    required int startSec,
    required String title,
    required String artist,
    String coverUrl = '',
  }) async {
    final uid = _svc.currentUserId;
    if (uid == null) _fail('not_authenticated');
    try {
      await _svc.client.from('profiles').update({
        'music_url': musicUrl.trim(),
        'music_start_sec': startSec < 0 ? 0 : startSec,
        'music_title': title.trim(),
        'music_artist': artist.trim(),
        'music_cover_url': coverUrl.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> setProfileZoomEnabled(bool enabled) async {
    final uid = _svc.currentUserId;
    if (uid == null) return;
    try {
      await _svc.client.from('profiles').update({'profile_zoom_enabled': enabled}).eq('id', uid);
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — GENİŞLETİLMİŞ YÖNETİCİ PANELİ
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> adminStats(String token) async {
    try {
      return _asMap(await _svc.client.rpc('admin_stats', params: {'p_token': token}));
    } catch (e) {
      _fail(e);
    }
  }

  /// v0.5: gerçek verilerle sistem durumu (aktif aramalar, push, çeviri ölçümleri)
  Future<Map<String, dynamic>> adminSystemHealth(String token) async {
    try {
      return _asMap(await _svc.client.rpc('admin_system_health', params: {'p_token': token}));
    } catch (e) {
      _fail(e);
    }
  }

  Future<Map<String, dynamic>> adminUserDetail(String token, String userId) async {
    try {
      return _asMap(await _svc.client.rpc('admin_user_detail', params: {'p_token': token, 'p_user': userId}));
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminSetVerified(String token, String userId, bool verified) async {
    try {
      await _svc.client.rpc('admin_set_verified', params: {'p_token': token, 'p_user': userId, 'p_verified': verified});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminSetAppRole(String token, String userId, String role) async {
    try {
      await _svc.client.rpc('admin_set_app_role', params: {'p_token': token, 'p_user': userId, 'p_role': role});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminSuspendUser(String token, String userId, int hours, String reason, {String note = ''}) async {
    try {
      await _svc.client.rpc('admin_suspend_user', params: {
        'p_token': token,
        'p_user': userId,
        'p_hours': hours,
        'p_reason': reason,
        'p_note': note,
      });
    } catch (e) {
      _fail(e);
    }
  }

  /// Kullanıcıya şifre sıfırlama e-postası gönderir (Supabase'in kendi e-postası).
  Future<void> adminSendPasswordReset(String token, String userId) async {
    try {
      final email = await _svc.client.rpc('admin_get_user_email', params: {'p_token': token, 'p_user': userId});
      final clean = (email ?? '').toString().trim();
      if (clean.isEmpty) _fail('not_found');
      await _svc.client.auth.resetPasswordForEmail(clean);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminWarnUser(String token, String userId, String message) async {
    try {
      await _svc.client.rpc('admin_warn_user', params: {'p_token': token, 'p_user': userId, 'p_message': message});
    } catch (e) {
      _fail(e);
    }
  }

  Future<int> adminBroadcast(String token, {required String title, required String body, String imageUrl = '', String audience = 'all'}) async {
    try {
      final res = await _svc.client.rpc('admin_broadcast', params: {
        'p_token': token,
        'p_title': title,
        'p_body': body,
        'p_image_url': imageUrl,
        'p_audience': audience,
      });
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      _fail(e);
    }
  }

  Future<bool> adminDeleteContent(String token, String targetType, String targetId) async {
    try {
      final res = await _svc.client.rpc('admin_delete_content', params: {
        'p_token': token,
        'p_target_type': targetType,
        'p_target_id': targetId,
      });
      return res == true;
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminPublishRelease(
    String token, {
    required String versionName,
    required int versionCode,
    required String apkUrl,
    required String notesTr,
    String notesEn = '',
    String notesDe = '',
    bool mandatory = false,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    try {
      await _svc.client.rpc('admin_publish_release', params: {
        'p_token': token,
        'p_version_name': versionName,
        'p_version_code': versionCode,
        'p_apk_url': apkUrl,
        'p_notes_tr': notesTr,
        'p_notes_en': notesEn,
        'p_notes_de': notesDe,
        'p_mandatory': mandatory,
        'p_details': details,
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminListReleases(String token) async {
    try {
      final res = await _svc.client.rpc('admin_list_releases', params: {'p_token': token});
      return res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminDeleteRelease(String token, String versionName) async {
    try {
      await _svc.client.rpc('admin_delete_release', params: {'p_token': token, 'p_version_name': versionName});
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> adminSetSetting(String token, String key, Object value) async {
    try {
      await _svc.client.rpc('admin_set_setting', params: {'p_token': token, 'p_key': key, 'p_value': value});
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // v0.6 — DENETİM MERKEZİ, GRUPLAR, CANLI ARAMALAR, İÇERİK, KULLANICI GÜÇ ARAÇLARI
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _list(dynamic res) =>
      res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

  Future<dynamic> _adminRpc(String fn, Map<String, dynamic> params) async {
    try {
      return await _svc.client.rpc(fn, params: params);
    } catch (e) {
      _fail(e);
    }
  }

  // ---------------------------------------------------------------------------
  // v0.8.3 RBAC + KÜRESEL TEMA STÜDYOSU
  // ---------------------------------------------------------------------------
  /// {role: super_admin|admin|...|null, permissions: [...]}
  Future<Map<String, dynamic>> myPermissions() async {
    try {
      return _asMap(await _svc.client.rpc('juzzio_my_permissions'));
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<List<Map<String, dynamic>>> adminListStaff(String token) async =>
      _list(await _adminRpc('admin_list_staff', {'p_token': token}));
  Future<void> adminGrantRole(String token, String userId, String role) async =>
      _adminRpc('admin_grant_role', {'p_token': token, 'p_user': userId, 'p_role': role});
  Future<void> adminRevokeRole(String token, String userId) async =>
      _adminRpc('admin_revoke_role', {'p_token': token, 'p_user': userId});

  Future<List<Map<String, dynamic>>> adminThemeList(String token) async =>
      _list(await _adminRpc('admin_theme_list', {'p_token': token}));
  Future<int> adminThemeSaveDraft(String token, String name, Map<String, dynamic> payload, {String note = ''}) async {
    final r = await _adminRpc('admin_theme_save_draft', {'p_token': token, 'p_name': name, 'p_payload': payload, 'p_note': note});
    return r is num ? r.toInt() : 0;
  }

  Future<void> adminThemePublish(String token, int version, {DateTime? at}) async =>
      _adminRpc('admin_theme_publish', {'p_token': token, 'p_version': version, 'p_publish_at': at?.toUtc().toIso8601String()});
  Future<int> adminThemeRollback(String token, int version) async {
    final r = await _adminRpc('admin_theme_rollback', {'p_token': token, 'p_version': version});
    return r is num ? r.toInt() : 0;
  }

  Future<void> adminThemeArchive(String token, int version) async =>
      _adminRpc('admin_theme_archive', {'p_token': token, 'p_version': version});

  /// Herkes: şu an geçerli küresel tema (yoksa null)
  Future<Map<String, dynamic>?> activeGlobalTheme() async {
    try {
      final r = await _svc.client.rpc('get_active_global_theme');
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> adminModerationOverview(String token) async =>
      _asMap(await _adminRpc('admin_moderation_overview', {'p_token': token}));

  Future<List<Map<String, dynamic>>> adminListStrikes(String token, {String? userId}) async =>
      _list(await _adminRpc('admin_list_strikes', {'p_token': token, 'p_user': userId}));

  Future<void> adminRevokeStrike(String token, int strikeId, {bool liftBan = true}) async {
    await _adminRpc('admin_revoke_strike', {'p_token': token, 'p_strike': strikeId, 'p_lift_ban': liftBan});
  }

  Future<Map<String, dynamic>> adminAddStrike(String token, String userId, String detail) async =>
      _asMap(await _adminRpc('admin_add_strike', {'p_token': token, 'p_user': userId, 'p_detail': detail}));

  Future<List<Map<String, dynamic>>> adminMediaQueue(String token, {String status = 'all'}) async =>
      _list(await _adminRpc('admin_media_queue', {'p_token': token, 'p_status': status}));

  Future<void> adminReviewMedia(String token, int id, {required bool approve, bool strike = false}) async {
    await _adminRpc('admin_review_media', {'p_token': token, 'p_id': id, 'p_approve': approve, 'p_strike': strike});
  }

  Future<List<Map<String, dynamic>>> adminListBannedTerms(String token) async =>
      _list(await _adminRpc('admin_list_banned_terms', {'p_token': token}));

  Future<void> adminUpsertBannedTerm(String token, String term, {String mode = 'contains', bool speech = false}) async {
    await _adminRpc('admin_upsert_banned_term',
          {'p_token': token, 'p_term': term, 'p_match_mode': mode, 'p_speech_strike': speech});
  }

  Future<void> adminDeleteBannedTerm(String token, String term) async {
    await _adminRpc('admin_delete_banned_term', {'p_token': token, 'p_term': term});
  }

  Future<Map<String, dynamic>> adminScanNames(String token) async =>
      _asMap(await _adminRpc('admin_scan_names', {'p_token': token}));

  Future<void> adminUpdateUserProfile(
    String token,
    String userId, {
    String? displayName,
    String? username,
    String? bio,
    bool clearAvatar = false,
  }) async {
    await _adminRpc('admin_update_user_profile', {
        'p_token': token,
        'p_user': userId,
        'p_display_name': displayName,
        'p_username': username,
        'p_bio': bio,
        'p_clear_avatar': clearAvatar,
      });
  }

  Future<int> adminSignOutUser(String token, String userId) async {
    final res = await _adminRpc('admin_sign_out_user', {'p_token': token, 'p_user': userId});
    return res is num ? res.toInt() : 0;
  }

  Future<void> adminDeleteUser(String token, String userId, String confirmUsername) async {
    await _adminRpc('admin_delete_user', {'p_token': token, 'p_user': userId, 'p_confirm': confirmUsername});
  }

  Future<List<Map<String, dynamic>>> adminListGroups(String token, {String query = ''}) async =>
      _list(await _adminRpc('admin_list_groups', {'p_token': token, 'p_query': query}));

  Future<List<Map<String, dynamic>>> adminGroupMembers(String token, String roomId) async =>
      _list(await _adminRpc('admin_group_members', {'p_token': token, 'p_room': roomId}));

  Future<void> adminUpdateGroup(String token, String roomId, {String? title, String? description}) async {
    await _adminRpc('admin_update_group', {'p_token': token, 'p_room': roomId, 'p_title': title, 'p_description': description});
  }

  Future<void> adminRemoveGroupMember(String token, String roomId, String userId) async {
    await _adminRpc('admin_remove_group_member', {'p_token': token, 'p_room': roomId, 'p_user': userId});
  }

  Future<void> adminDeleteGroup(String token, String roomId) async {
    await _adminRpc('admin_delete_group', {'p_token': token, 'p_room': roomId});
  }

  Future<List<Map<String, dynamic>>> adminActiveCalls(String token) async =>
      _list(await _adminRpc('admin_active_calls', {'p_token': token}));

  Future<int> adminEndCall(String token, String sessionKey) async {
    final res = await _adminRpc('admin_end_call', {'p_token': token, 'p_session_key': sessionKey});
    return res is num ? res.toInt() : 0;
  }

  Future<List<Map<String, dynamic>>> adminRecentContent(String token, String kind, {String query = ''}) async =>
      _list(await _adminRpc('admin_recent_content', {'p_token': token, 'p_kind': kind, 'p_query': query}));

  Future<List<Map<String, dynamic>>> adminAudit(String token) async {
    try {
      final res = await _svc.client.rpc('admin_audit', params: {'p_token': token, 'p_limit': 150});
      return res is List ? res.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    } catch (e) {
      _fail(e);
    }
  }
}
