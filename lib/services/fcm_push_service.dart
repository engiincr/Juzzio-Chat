// =============================================================================
// JUZZIO v0.1.0 — Firebase Cloud Messaging (FCM) & Supabase Push Servisi
// Bölüm 1, 3, 5, 7, 8, 9, 10, 11 ve 15 Kurallarına Tam Uyumlu:
// - Yalnızca gerçek FirebaseMessaging.getInstance().token değerini kabul eder;
//   Firebase yapılandırması yokken sahte/temsili FCM token üretmez!
// - Tekil Gönderim Yolu: Push bildirimleri yalnızca Supabase `notifications` INSERT ->
//   `push-webhook` Edge Function -> FCM HTTP v1 üzerinden gönderilir; istemci Realtime
//   üzerinden ikinci kez işletim sistemi bildirimi üretmez (Çift gönderim önlendi).
// - Güvenlik: Token değerleri ve hassas veriler asla log'a veya ekrana yazdırılmaz.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/native_bridge.dart';
import 'juzzio_quick_reply.dart';

class JuzzioPushEventPayload {
  final String notificationId;
  final String eventType;
  final String title;
  final String body;
  final String targetId;
  final String targetSecondaryId;
  final String actorId;
  final String channelId;

  const JuzzioPushEventPayload({
    this.notificationId = '',
    required this.eventType,
    required this.title,
    required this.body,
    this.targetId = '',
    this.targetSecondaryId = '',
    this.actorId = '',
    this.channelId = 'juzzio_high_priority_v2',
  });

  factory JuzzioPushEventPayload.fromMap(Map<String, dynamic> map) {
    final data = map['data_payload'] is Map
        ? Map<String, dynamic>.from(map['data_payload'] as Map)
        : <String, dynamic>{};
    return JuzzioPushEventPayload(
      notificationId:
          (map['notification_id'] ?? data['notification_id'] ?? '').toString(),
      eventType:
          (map['event_type'] ?? map['type'] ?? data['event_type'] ?? 'system')
              .toString(),
      title: (map['title'] ?? 'Juzzio').toString(),
      body: (map['body'] ?? '').toString(),
      targetId: (map['target_id'] ?? data['target_id'] ?? '').toString(),
      targetSecondaryId:
          (map['target_secondary_id'] ?? data['target_secondary_id'] ?? '')
              .toString(),
      actorId: (map['actor_id'] ?? data['actor_id'] ?? '').toString(),
      channelId: (map['channel_id'] ??
              data['channel_id'] ??
              'juzzio_high_priority_v2')
          .toString(),
    );
  }
}

class JuzzioFcmServerTestResult {
  final bool fcmAccepted;
  final String status;
  final int registeredTokensCount;
  final int fcmAcceptedCount;
  final List<String> errorCodes;
  final String userFacingSummary;

  const JuzzioFcmServerTestResult({
    required this.fcmAccepted,
    required this.status,
    this.registeredTokensCount = 0,
    this.fcmAcceptedCount = 0,
    this.errorCodes = const [],
    required this.userFacingSummary,
  });
}

class JuzzioFcmPushService {
  JuzzioFcmPushService._();
  static final JuzzioFcmPushService instance = JuzzioFcmPushService._();

  static const MethodChannel _channel = MethodChannel('juzzio/notifications');

  SupabaseClient get _client => Supabase.instance.client;
  String? get _currentUserId => _client.auth.currentUser?.id;

  bool _fcmConfigured = false;
  String _fcmStatus = 'uninitialized'; // 'ready' | 'token_unavailable' | 'missing_google_services_json' | 'uninitialized'
  String _devicePushToken = '';
  String _deviceId = '';
  String _packageName = 'com.juzzio.app';
  String _firebaseProjectId = 'juzzio';
  String _firebaseAppId = '1:252976064150:android:d8f5216e6e87c023c604b7';
  String _firebaseSenderId = '252976064150';
  bool _notificationsEnabledOnOs = true;
  bool _isTokenSyncedToSupabase = false;
  bool _methodCallHandlerRegistered = false;
  DateTime? _lastSyncedAt;

  final Set<String> _consumedTapIds = <String>{};
  final StreamController<JuzzioPushEventPayload> _tapStreamCtrl =
      StreamController<JuzzioPushEventPayload>.broadcast();
  final StreamController<JuzzioPushEventPayload> _foregroundPushStreamCtrl =
      StreamController<JuzzioPushEventPayload>.broadcast();

  bool get isFcmConfigured => _fcmConfigured;
  String get fcmStatus => _fcmStatus;
  bool get hasRealFcmToken => _fcmConfigured && _devicePushToken.isNotEmpty;
  String get packageName => _packageName;
  String get firebaseProjectId => _firebaseProjectId;
  String get firebaseAppId => _firebaseAppId;
  String get firebaseSenderId => _firebaseSenderId;
  bool get notificationsEnabledOnOs => _notificationsEnabledOnOs;
  bool get isTokenSyncedToSupabase => _isTokenSyncedToSupabase;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Stream<JuzzioPushEventPayload> get onNotificationTap => _tapStreamCtrl.stream;
  Stream<JuzzioPushEventPayload> get onForegroundMessage =>
      _foregroundPushStreamCtrl.stream;

  void _ensureMethodCallHandler() {
    if (_methodCallHandlerRegistered) return;
    _methodCallHandlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onFcmTokenRefresh':
          final args = call.arguments;
          if (args is Map) {
            final newToken = (args['token'] ?? '').toString().trim();
            if (newToken.isNotEmpty) {
              _devicePushToken = newToken;
              _fcmConfigured = true;
              _fcmStatus = 'ready';
              await syncTokenAndPreferencesWithSupabase();
            }
          }
          break;
        case 'onPushNotificationTapped':
          final args = call.arguments;
          if (args is Map) {
            final map = Map<String, dynamic>.from(args);
            final eventId = (map['intent_event_id'] ??
                    map['notification_id'] ??
                    '${map["event_type"]}_${map["target_id"]}')
                .toString();
            if (!_consumedTapIds.contains(eventId)) {
              _consumedTapIds.add(eventId);
              _tapStreamCtrl.add(JuzzioPushEventPayload.fromMap(map));
            }
          }
          break;
        case 'onWidgetAction':
          final args = call.arguments;
          if (args is Map) JuzzioNative.emitWidgetAction((args['action'] ?? '').toString());
          break;
        // v0.8.3: uygulama arka plandayken bildirimden hızlı yanıt (çalışan motor)
        case 'onQuickReply':
          final args = call.arguments;
          if (args is Map) {
            return JuzzioQuickReply.send(roomId: '${args['room_id'] ?? ''}', text: '${args['text'] ?? ''}');
          }
          return false;
        case 'onForegroundFcmMessage':
          final args = call.arguments;
          if (args is Map) {
            final map = Map<String, dynamic>.from(args);
            _foregroundPushStreamCtrl.add(JuzzioPushEventPayload.fromMap(map));
          }
          break;
      }
    });
  }

  /// Uygulama açılışında ve kullanıcı oturumu başladığında gerçek Firebase durumunu okur
  Future<void> initializeAndSync() async {
    _ensureMethodCallHandler();
    ensureAuthStateListener();
    try {
      final configMap = await _channel.invokeMapMethod<String, dynamic>(
        'getFirebaseConfigSummary',
      );
      if (configMap != null) {
        _fcmConfigured = configMap['fcm_configured'] == true;
        _fcmStatus = (configMap['fcm_status'] ?? 'uninitialized').toString();
        _packageName =
            (configMap['package_name'] ?? 'com.juzzio.app').toString();
        final pId = (configMap['project_id'] ?? '').toString().trim();
        if (pId.isNotEmpty) _firebaseProjectId = pId;
        final appId = (configMap['mobilesdk_app_id'] ?? '').toString().trim();
        if (appId.isNotEmpty) _firebaseAppId = appId;
        final sender = (configMap['project_number'] ?? '').toString().trim();
        if (sender.isNotEmpty) _firebaseSenderId = sender;
        _deviceId = (configMap['device_id'] ?? '').toString().trim();
        _devicePushToken = (configMap['push_token'] ?? '').toString().trim();
        _notificationsEnabledOnOs =
            configMap['notifications_enabled_os'] != false;
      }
    } catch (_) {
      _fcmConfigured = false;
      _fcmStatus = 'missing_google_services_json';
      _devicePushToken = '';
    }

    await checkInitialLaunchPushPayload();

    if (hasRealFcmToken) {
      await syncTokenAndPreferencesWithSupabase();
    } else {
      _isTokenSyncedToSupabase = false;
      // Google Play Servisleri ilk açılışta token üretimini birkaç saniye geciktirebilir
      Future<void>.delayed(const Duration(seconds: 4), () async {
        if (!_isTokenSyncedToSupabase && _currentUserId != null) {
          await syncTokenAndPreferencesWithSupabase();
        }
      });
    }
  }

  /// Sistem bildirim izninin açık olup olmadığını kontrol eder (Android 13+ uyumlu)
  Future<bool> refreshOsNotificationPermissionStatus() async {
    try {
      final allowed =
          await _channel.invokeMethod<bool>('areNotificationsEnabledOnOs');
      if (allowed != null) {
        _notificationsEnabledOnOs = allowed;
      }
    } catch (_) {}
    return _notificationsEnabledOnOs;
  }

  /// Sistem ayarlarında uygulamanın bildirim yönetimi ekranını açar (Bölüm 9.8 & 10.4)
  Future<void> openSystemNotificationSettings() async {
    try {
      await _channel.invokeMethod('openAppNotificationSettings');
    } catch (_) {}
  }

  /// Soğuk açılışta (terminated -> tap) bekleyen bildirim intent'ini tek seferlik tüketir
  Future<JuzzioPushEventPayload?> checkInitialLaunchPushPayload() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialPushPayload',
      );
      if (raw != null && raw.isNotEmpty) {
        final eventId = (raw['intent_event_id'] ??
                raw['notification_id'] ??
                '${raw["event_type"]}_${raw["target_id"]}')
            .toString();
        if (_consumedTapIds.contains(eventId)) return null;
        _consumedTapIds.add(eventId);
        final payload = JuzzioPushEventPayload.fromMap(raw);
        if (payload.eventType.isNotEmpty) {
          _tapStreamCtrl.add(payload);
          return payload;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Gerçek FCM registration token mevcutsa kullanıcının bildirim tercihleriyle birlikte
  /// Supabase `user_push_tokens` tablosuna kaydeder. Token yoksa sahte kayıt oluşturmaz!
  StreamSubscription<AuthState>? _authSub;

  void ensureAuthStateListener() {
    if (_authSub != null) return;
    try {
      _authSub = _client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession ||
            event == AuthChangeEvent.tokenRefreshed) {
          initializeAndSync();
        }
      });
    } catch (_) {}
  }

  /// P2 DÜZELTMESİ:
  /// 14 parametreli `upsert_my_push_token` RPC'sini (`p_notify_system` dahil) çağırır,
  /// dönen satır UUID'sini doğrular ve RPC'yi bypass eden doğrudan tablo `.upsert(...)`
  /// fallback'ini kullanmaz.
  Future<bool> syncTokenAndPreferencesWithSupabase() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      _isTokenSyncedToSupabase = false;
      return false;
    }

    // Eğer soğuk açılışta token henüz boşsa Native katmandan bir kez daha sorgula
    if (!hasRealFcmToken) {
      try {
        final configMap = await _channel.invokeMapMethod<String, dynamic>(
          'getFirebaseConfigSummary',
        );
        if (configMap != null) {
          _fcmConfigured = configMap['fcm_configured'] == true;
          _fcmStatus = (configMap['fcm_status'] ?? _fcmStatus).toString();
          _deviceId = (configMap['device_id'] ?? _deviceId).toString().trim();
          _devicePushToken = (configMap['push_token'] ?? '').toString().trim();
        }
      } catch (_) {}
    }

    if (!hasRealFcmToken) {
      _isTokenSyncedToSupabase = false;
      return false;
    }

    final app = JuzzioAppController.instance;

    try {
      final rpcRes = await _client.rpc(
        'upsert_my_push_token',
        params: {
          'p_fcm_token': _devicePushToken,
          'p_device_id': _deviceId,
          'p_platform': 'android',
          'p_app_version': JuzzioConfig.appVersion,
          'p_firebase_project_id': _firebaseProjectId,
          'p_notify_enabled': app.notificationsEnabled,
          'p_notify_messages': app.notifyDirectMessages,
          'p_notify_groups': app.notifyGroupMessages,
          'p_notify_calls': app.notifyCalls,
          'p_notify_follows': app.notifyFollows,
          'p_notify_likes_comments': app.notifyLikesComments,
          'p_notify_stories': app.notifyStories,
          'p_notify_system': app.notifySystem,
          'p_is_silent_mode': app.isSilentMode,
        },
      );
      final returnedId = rpcRes?.toString().trim() ?? '';
      if (returnedId.isEmpty) {
        _isTokenSyncedToSupabase = false;
        return false;
      }
      _isTokenSyncedToSupabase = true;
      _lastSyncedAt = DateTime.now();
      return true;
    } catch (_) {
      _isTokenSyncedToSupabase = false;
      return false;
    }
  }

  /// Çıkış yapıldığında (Sign Out) yalnızca bu cihazın token ilişkisini pasifleştirir (Bölüm 7.5)
  Future<void> deactivateCurrentDeviceToken() async {
    try {
      await _client.rpc(
        'deactivate_my_push_token',
        params: {
          'p_fcm_token': _devicePushToken,
          'p_device_id': _deviceId,
        },
      );
    } catch (_) {}
    _isTokenSyncedToSupabase = false;
  }

  /// Normal kullanıcılar için YALNIZCA bu cihazdaki yerel Android bildirim kanalını test eder.
  /// Uzaktan FCM gönderimi yapmaz ve FCM testi gibi sunmaz (Bölüm 2 & 5.1).
  Future<bool> triggerLocalDeviceNotificationTest() async {
    final app = JuzzioAppController.instance;
    await refreshOsNotificationPermissionStatus();
    if (!_notificationsEnabledOnOs) {
      return false;
    }
    try {
      await _channel.invokeMethod('showRichSocialNotification', {
        'id': DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'title': app.trEn(
          'Juzzio Yerel Cihaz Bildirimi',
          'Juzzio Local Device Notification', 'Juzzio – lokale Gerätebenachrichtigung',
        ),
        'body': app.trEn(
          'Bu bildirim yalnızca cihazınızdaki yerel Android bildirim kanalını doğrulamak için gösterildi (Uzaktan FCM testi değildir).',
          'This notification verifies your local Android notification channel on this device (Not a remote FCM test).', 'Diese Benachrichtigung prüft den lokalen Android-Benachrichtigungskanal auf diesem Gerät (kein FCM-Servertest).',
        ),
        'channelId': 'juzzio_high_priority_v2',
        'eventType': 'system',
        'isCall': false,
        'isUpdate': false,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Geliştirici tanılama ekranı için doğrulanmış sunucu taraflı FCM HTTP v1 Self-Test.
  /// Yerel bildirim tetiklemez; yalnızca oturum açmış kullanıcının kendi aktif cihazlarına
  /// `push-webhook` Edge Function üzerinden gerçek FCM isteği gönderir ve dürüst sonucu döner.
  Future<JuzzioFcmServerTestResult> runAuthenticatedServerSelfTest() async {
    final app = JuzzioAppController.instance;
    final uid = _currentUserId;

    if (uid == null || uid.isEmpty) {
      return JuzzioFcmServerTestResult(
        fcmAccepted: false,
        status: 'not_authenticated',
        userFacingSummary: app.trEn(
          'Oturum açık değil. FCM sunucu testi için önce giriş yapmalısınız.',
          'Not signed in. Please sign in before running an FCM server test.', 'Nicht angemeldet. Bitte melde dich an, bevor du einen FCM-Servertest ausführst.',
        ),
      );
    }

    await initializeAndSync();

    if (!_fcmConfigured) {
      return JuzzioFcmServerTestResult(
        fcmAccepted: false,
        status: 'missing_google_services_json',
        userFacingSummary: app.trEn(
          'Bu derlemede com.juzzio.app için geçerli google-services.json / FirebaseApp başlatılmamış. Gerçek FCM token alınamadı.',
          'FirebaseApp is not initialized with a valid google-services.json for com.juzzio.app in this build.', 'FirebaseApp ist in diesem Build nicht mit einer gültigen google-services.json für com.juzzio.app initialisiert.',
        ),
      );
    }

    if (!hasRealFcmToken) {
      return JuzzioFcmServerTestResult(
        fcmAccepted: false,
        status: 'token_unavailable',
        userFacingSummary: app.trEn(
          'Cihazdan henüz gerçek FCM registration token alınamadı (Google Play Servisleri ve internet bağlantısını kontrol edin).',
          'Could not obtain a real FCM registration token from Google Play Services on this device.', 'Auf diesem Gerät konnte kein echtes FCM-Registrierungstoken von den Google Play-Diensten abgerufen werden.',
        ),
      );
    }

    try {
      final res = await _client.functions.invoke(
        'push-webhook',
        body: {
          'action': 'self_test',
          'recipient_id': uid,
        },
      );

      final data = res.data is String
          ? (jsonDecode(res.data as String) as Map<String, dynamic>)
          : (res.data is Map
              ? Map<String, dynamic>.from(res.data as Map)
              : <String, dynamic>{});

      final status = (data['status'] ?? data['error'] ?? 'unknown').toString();
      final regCount = (data['registeredTokensCount'] as num?)?.toInt() ?? 0;
      final accCount = (data['fcmAcceptedCount'] as num?)?.toInt() ?? 0;
      final errList = data['errorCodes'] is List
          ? (data['errorCodes'] as List).map((e) => e.toString()).toList()
          : const <String>[];

      if (res.status == 200 && accCount > 0) {
        return JuzzioFcmServerTestResult(
          fcmAccepted: true,
          status: status,
          registeredTokensCount: regCount,
          fcmAcceptedCount: accCount,
          errorCodes: errList,
          userFacingSummary: app.trEn(
            'Google FCM HTTP v1 sunucusu isteği kabul etti ($accCount/$regCount cihaz). Not: Bildirimin ekranda görünmesi cihazın işletim sistemi izinlerine ve güç tasarrufu durumuna bağlıdır.',
            'Google FCM HTTP v1 accepted the message ($accCount/$regCount devices). Note: On-screen display depends on device OS permissions and power state.', 'Google FCM HTTP v1 hat die Nachricht angenommen ($accCount/$regCount Geräte). Hinweis: Die Anzeige hängt von den Berechtigungen und dem Energiezustand des Geräts ab.',
          ),
        );
      }

      return JuzzioFcmServerTestResult(
        fcmAccepted: false,
        status: status,
        registeredTokensCount: regCount,
        fcmAcceptedCount: accCount,
        errorCodes: errList,
        userFacingSummary: app.trEn(
          'Sunucu yanıtı: $status (Kayıtlı token: $regCount, FCM kabul: $accCount${errList.isNotEmpty ? ", Hata: ${errList.join(", ")}" : ""}).',
          'Server response: $status (Registered tokens: $regCount, FCM accepted: $accCount${errList.isNotEmpty ? ", Error: ${errList.join(", ")}" : ""}).', 'Serverantwort: $status (registrierte Tokens: $regCount, von FCM angenommen: $accCount${errList.isNotEmpty ? ", Fehler: ${errList.join(", ")}" : ""}).',
        ),
      );
    } catch (e) {
      return JuzzioFcmServerTestResult(
        fcmAccepted: false,
        status: 'edge_function_unreachable',
        userFacingSummary: app.trEn(
          'push-webhook Edge Function çağrısı başarısız oldu. Fonksiyonun deploy edildiğini ve FCM_SERVICE_ACCOUNT_JSON secret değerinin tanımlandığını doğrulayın.',
          'Failed to invoke push-webhook Edge Function. Verify that push-webhook is deployed and FCM_SERVICE_ACCOUNT_JSON secret is configured.', 'Die Edge Function push-webhook konnte nicht aufgerufen werden. Prüfe, ob push-webhook bereitgestellt und das Secret FCM_SERVICE_ACCOUNT_JSON konfiguriert ist.',
        ),
      );
    }
  }
}
