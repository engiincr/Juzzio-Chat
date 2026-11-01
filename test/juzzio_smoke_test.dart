import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/config.dart';
import 'package:juzzio/models/social_models.dart';
import 'package:juzzio/services/fcm_push_service.dart';
import 'package:juzzio/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Juzzio Core Smoke Test — Config, Security, Theme & Locale Pack', () {
    expect(JuzzioConfig.appVersion.isNotEmpty, isTrue);
    expect(JuzzioConfig.supabaseUrl.startsWith('https://'), isTrue);
    // Güvenlik: APK içine gömülü Deepgram/LiveKit gizli anahtarı bulunmamalıdır
    expect(JuzzioConfig.deepgramDevApiKey.isEmpty, isTrue);
    expect(JuzzioConfig.liveKitUrl.startsWith('wss://'), isTrue);
    expect(JuzzioConfig.chatMediaBucket, equals('chat-media'));
    expect(JuzzioConfig.postsBucket, equals('posts'));

    final ctrl = JuzzioAppController.instance;
    expect(JuzzioAppController.supportedLanguages.length, greaterThanOrEqualTo(100));
    expect(kJuzzioSupportedLanguages.length, greaterThanOrEqualTo(100));
    expect(ctrl.uiLang.isNotEmpty, isTrue);

    // Vurgu ve zemin renkleri: turuncu ton yok (v0.6 cam teması renklerini yalnız balon taşır)
    final lightPalette = JuzzioPalette(false);
    final darkPalette = JuzzioPalette(true);
    bool isNeutral(Color c) {
      final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
      return (r - g).abs() <= 12 && (g - b).abs() <= 12 && (r - b).abs() <= 12;
    }
    expect(isNeutral(lightPalette.amberPrimary), isTrue);
    expect(isNeutral(darkPalette.amberPrimary), isTrue);
    expect(isNeutral(darkPalette.headerDarkForest), isTrue);
    // v0.6 Glassmorphism: giden balon seçili cam temasının tonunu taşır; turuncu olamaz
    final bubble = HSLColor.fromColor(darkPalette.outgoingBubble.withValues(alpha: 1));
    expect(bubble.saturation > 0.35 && bubble.hue >= 12 && bubble.hue <= 48, isFalse);
    expect(isNeutral(darkPalette.bgPrimary), isTrue);
  });

  test('Juzzio Turkish Normalizer & Hashtag Extraction Test (Bölüm 10 & 23.2)', () {
    expect(JuzzioTurkishNormalizer.toLowerTurkish('İSTANBUL IŞIK'), equals('istanbul ışık'));
    expect(JuzzioTurkishNormalizer.matchesQuery('İstanbul Boğazı', 'istanbul'), isTrue);
    expect(JuzzioTurkishNormalizer.matchesQuery('Iğdır Doğa', 'ığdır'), isTrue);

    final tags = JuzzioTurkishNormalizer.extractHashtags(
      'Harika bir gün! #İstanbul #Doğa #Seyahat2026',
    );
    expect(tags, containsAll(<String>['istanbul', 'doğa', 'seyahat2026']));
  });

  test('Juzzio Social Models & State Machines Test (Bölüm 34)', () {
    final post = JuzzioPost.fromMap({
      'id': 'post_001',
      'author_id': 'user_001',
      'author_username': '@engincan',
      'author_display_name': 'Engin Can',
      'content_type': 'reel',
      'caption': 'Deniz ve güneş #seyahat',
      'hashtags': ['seyahat'],
      'media_urls': ['https://example.com/video.mp4'],
      'likes_count': 12,
      'comments_count': 3,
      'saves_count': 4,
      'comments_enabled': true,
      'is_deleted': false,
    }, isLikedByMe: true, isSavedByMe: false);

    expect(post.authorUsername, equals('engincan'));
    expect(post.isReel, isTrue);
    expect(post.isVideo, isTrue);
    expect(post.isLikedByMe, isTrue);
    expect(post.lifecycleState, equals(JuzzioPostLifecycleState.published));

    final follow = JuzzioFollowRecord.fromMap({
      'id': 'f_1',
      'follower_id': 'u_1',
      'follower_username': 'ali',
      'follower_display_name': 'Ali',
      'following_id': 'u_2',
      'following_username': 'veli',
      'following_display_name': 'Veli',
      'status': 'pending',
    });
    expect(follow.relationState, equals(JuzzioFollowRelationState.pending));
  });

  test('Juzzio Settings Controller Toggles & Accessibility Test (Bölüm 29)', () {
    final ctrl = JuzzioAppController.instance;
    ctrl.setReduceMotion(true);
    expect(ctrl.reduceMotion, isTrue);
    expect(ctrl.autoplayVideos, isFalse);

    ctrl.setReduceMotion(false);
    ctrl.setAutoplayVideos(true);
    expect(ctrl.autoplayVideos, isTrue);

    ctrl.setPrivateAccount(true);
    expect(ctrl.isPrivateAccount, isTrue);
    ctrl.setPrivateAccount(false);

    ctrl.setNotifySystem(false);
    expect(ctrl.notifySystem, isFalse);
    ctrl.setNotifySystem(true);
    expect(ctrl.notifySystem, isTrue);
  });

  test('Juzzio FCM & Push Webhook Payload & Application ID Test (com.juzzio.app)', () {
    final payload = JuzzioPushEventPayload.fromMap({
      'notification_id': 'notif_001',
      'event_type': 'like',
      'title': 'Engin Can',
      'body': 'Paylaşımınızı beğendi.',
      'target_id': 'post_123',
      'actor_id': 'user_456',
      'channel_id': 'juzzio_social_priority_v2',
    });
    expect(payload.notificationId, equals('notif_001'));
    expect(payload.eventType, equals('like'));
    expect(payload.targetId, equals('post_123'));
    expect(payload.channelId, equals('juzzio_social_priority_v2'));
    expect(JuzzioFcmPushService.instance.packageName, equals('com.juzzio.app'));
    expect(JuzzioFcmPushService.instance.firebaseProjectId, equals('juzzio'));
    expect(JuzzioFcmPushService.instance.firebaseSenderId, equals('252976064150'));
    // Firebase başlatılmadan sahte/temsili FCM token üretilmediğini doğrula
    expect(JuzzioFcmPushService.instance.hasRealFcmToken, isFalse);
  });

  test('Juzzio özel sohbet, hikâye yanıtı ve arama modelleri', () {
    final conv = JuzzioConversation.fromMap({
      'room_id': 'room_1',
      'title': 'Ali',
      'is_group': false,
      'livekit_room_name': 'lk_dm_abc',
      'partner_id': 'u_ali',
      'partner_display_name': 'Ali',
      'partner_username': 'ali',
      'member_ids': ['u_me', 'u_ali'],
      'member_names': ['Ben', 'Ali'],
      'unread_count': 3,
      'last_message_preview': 'Selam',
      'last_message_at': '2026-10-29T10:00:00Z',
    });
    expect(conv.isGroup, isFalse);
    expect(conv.unreadCount, equals(3));
    expect(conv.toPartnerProfile()?.id, equals('u_ali'));
    expect(conv.toGroupRoom().livekitRoomName, equals('lk_dm_abc'));

    final msg = JuzzioMessage.fromMap({
      'id': 'm1',
      'room_id': 'room_1',
      'sender_id': 'u_ali',
      'message_type': 'text',
      'original_text': 'Harika!',
      'translated_text': 'Great!',
      'story_id': 's1',
      'reactions': {'u_me': '🔥'},
      'metadata': {
        'story': {'storyId': 's1', 'storyUsername': 'me', 'replierName': 'Ali'},
      },
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(msg.storyId, equals('s1'));
    expect(msg.storyReplyMeta?['storyUsername'], equals('me'));
    expect(msg.reactions['u_me'], equals('🔥'));
    expect(msg.isDeleted, isFalse);

    final call = JuzzioCallLog.fromMap({
      'id': 'c1',
      'session_id': 'sess1',
      'livekit_room_name': 'lk_dm_abc',
      'caller_id': 'u_ali',
      'caller_name': 'Ali',
      'receiver_id': 'u_me',
      'is_video': true,
      'status': 'ringing',
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(call.isRinging, isTrue);
    expect(call.sessionId, equals('sess1'));

    // Grup üyeliği yalnızca kimlikle doğrulanır (isim eşleşmesiyle başkasının grubuna girilemez)
    const group = JuzzioGroupRoom(
      id: 'g1',
      roomCode: 'group_x',
      title: 'Ekip',
      livekitRoomName: 'lk_group_x',
      groupMembers: ['Ali', 'Veli'],
      groupMemberIds: ['u_ali', 'u_veli'],
    );
    expect(group.isUserMember('u_ali', null), isTrue);
    expect(group.isUserMember('u_baska', 'Ali'), isFalse);
  });
}
