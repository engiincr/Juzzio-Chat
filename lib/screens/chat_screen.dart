// =============================================================================
// JUZZIO v0.1.0 - Ana Ekran (Hey Joseph Arayüz Düzeni + Instagram.jpg Beyaz
// "Cool!" Tema ve Geniş Siyah Hap Butonları):
// 1. Üst Başlık: "Hey" (RBold-İtalic.otf) + "Joseph" / Kullanıcı Adı (R-RegularBold.otf)
//    + "You have X new messages" + Yuvarlak Arama Butonu
// 2. Dikey Uzun Hikaye/Durum Kartları (Gerçek Topluluk Üyeleri Yuvarlak Hikaye Düzeni:
//    Sol üstte sayı rozeti, altta halkalı yuvarlak avatar ve R-RegularBold isim)
// 3. Kategori Filtre Kapsülleri (All, Favorites 5, Work, Design 8, Groups, Friends)
// 4. Sohbet Kartları: Bireysel sohbetlerde yuvarlak avatar + sağ altta Pin & Turuncu
//    okunmamış rozeti; Grup sohbetlerinde (Thailand Trip tarzı) 2x2 4'lü üye avatar
//    ızgarası ve R-RegularBold kişi/grup başlıkları!
// 5. Büyütülmüş Bildirim Kartları: R-RegularBold fontu, mesaj bildiriminden anında
//    yukarıdan yanıt verme ve arama bildirimlerinin hemen altında "Aramaya Katıl"
//    ve "Reddet" butonları!
// 6. Arkadaşlar Sekmesi & Kişi Seçmeli Grup Oluşturma (Sahte Fikret/Ari/Engin grubu
//    kaldırıldı; sadece seçtiğiniz arkadaşlar gruba eklenir ve grup aramasına katılır)
// 7. Modern Fotoğraf & Video Durum Paylaşımı ve Duruma Yanıt Verme Stüdyosu
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/native_bridge.dart';
import '../models/social_models.dart';
import '../services/fcm_push_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/social_common_widgets.dart';
import '../widgets/media_viewer.dart';
import 'social/social_screens.dart';
import 'call_screen.dart';
import 'call_detail_page.dart';
import 'contact_settings_page.dart';
import 'settings_suite_screens.dart';
import 'release_notes_screen.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../core/content_filter.dart';
import '../core/juzzio_sounds.dart';
import '../services/juzzio_features_service.dart';
import '../services/juzzio_e2ee.dart';
import '../widgets/group_management_sheet.dart';
import '../widgets/profile_extras.dart';
import '../widgets/juzzio_emoji_picker.dart';
import '../widgets/juzzio_story_stickers.dart';
import 'profile/juzzio_profile_view.dart';
import 'chick_game_screen.dart';
import 'banned_screen.dart';
import 'maintenance_screen.dart';
import 'social/juzzio_creator_studio.dart';
import 'social/juzzio_global_feed.dart';
import '../widgets/juzzio_video_kit.dart';
import '../widgets/juzzio_swipe_reply.dart';
import 'backup_page.dart';
import '../services/juzzio_story_seen.dart';

class ChatScreen extends StatefulWidget {
  final String myDisplayName;
  final String myLanguage;

  const ChatScreen({
    super.key,
    required this.myDisplayName,
    required this.myLanguage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool get _isAppInBackground => _appLifecycleState != AppLifecycleState.resumed;

  StreamSubscription<List<JuzzioUserProfile>>? _profilesSub;
  StreamSubscription<List<JuzzioConversation>>? _convSub;
  StreamSubscription<JuzzioMessage>? _incomingMsgSub;
  StreamSubscription<List<JuzzioCallLog>>? _incomingCallSub;
  List<JuzzioConversation> _conversations = [];
  bool _conversationsLoaded = false;
  JuzzioCallLog? _incomingCall;
  final Set<String> _handledIncomingCallIds = {};
  bool _isInCall = false;
  final Set<String> _mutedConversationIds = {};
  final Set<String> _deletedConversationIds = {};
  final Set<String> _deletedMessageIds = {};
  String? _swipedConversationKey;
  String? _swipedMessageId;
  // Kaydırarak yanıt (swipe to reply)
  JuzzioMessage? _replyingTo;
  final Map<String, JuzzioMessage> _messageCache = {};
  // 0 = Sohbetler (Hey Joseph), 1 = Aramalar, 2 = Durum (Foto/Video), 3 = Arkadaşlar, 4 = Ayarlar
  // 0 = Message (Home & Mesajlar), 1 = Calls (Arama), 2 = Add / Arkadaşlar, 3 = Küresel akış, 4 = Profile (Profil & Ayarlar)
  int _selectedBottomTab = 0;
  bool _isInsideConversation = false;
  bool _isMesajlarFilterMode = false;
  int _selectedFilterIndex = 0; // 0 = Tümü, 1 = Kişiler, 2 = Gruplar, 3 = Arkadaşlar
  int _friendsFilterIndex = 0; // 0 = Tümü, 1 = Çevrimiçi, 2 = Önerilen
  int _globalFeedEpoch = 0;
  int _unreadNotificationsCount = 0;
  StreamSubscription<List<JuzzioNotificationItem>>? _socialNotifSub;
  StreamSubscription<JuzzioPushEventPayload>? _fcmTapSub;
  StreamSubscription<JuzzioPushEventPayload>? _fcmForegroundSub;
  StreamSubscription<String>? _widgetActionSub;
  final Set<String> _shownForegroundPushIds = <String>{};
  String _searchQuery = '';
  String _callsSearchQuery = '';

  String? _activeConversationRoomId;
  JuzzioUserProfile? _myProfile;
  JuzzioUserProfile? _activeFriendPartner;
  List<JuzzioUserProfile> _allProfiles = [];
  List<JuzzioFriendship> _friendships = [];
  List<JuzzioStory> _activeStories = [];
  List<JuzzioCallLog> _callLogs = [];
  List<JuzzioGroupRoom> _groupRooms = [];
  JuzzioGroupRoom? _activeGroupRoom;

  StreamSubscription<List<JuzzioGroupRoom>>? _groupSub;
  StreamSubscription<List<Map<String, dynamic>>>? _releaseSub;
  // Tepki: sunucu cevabı gelene kadar yerel (iyimser) tepki haritası
  final Map<String, Map<String, String>> _localReactions = {};
  String? _burstMessageId;
  String _burstEmoji = '❤️‍🔥';

  final Map<String, String> _localRetranslatedText = {};

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isRecordingVoice = false;
  DateTime? _recordStartTime;
  Timer? _recordAmplitudeTimer;
  final List<double> _livePeaks = [];

  // v0.4.0 — WhatsApp tarzı ses kaydı (yukarı kaydır: kilitle, sola kaydır: iptal)
  bool _voiceLocked = false;
  bool _voicePaused = false;
  Offset _voiceDrag = Offset.zero;
  Timer? _voiceUiTimer;
  Duration _voicePausedTotal = Duration.zero;
  DateTime? _voicePauseStartedAt;
  String? _voiceRecordingPath;

  // Emoji paneli
  bool _showEmojiPanel = false;
  bool _showJumpDown = false;
  final FocusNode _composerFocus = FocusNode();

  // Sohbet başlığında gerçek çevrimiçi / son görülme bilgisi
  String? _presenceUserId;
  ({bool isOnline, DateTime? lastSeen})? _activePresence;
  Timer? _presenceTimer;

  // Sohbet penceresindeki sürüklenebilir çatlak yumurta (Civciv oyunu)
  Offset? _eggOffset;
  String? _playingMessageId;

  late TextEditingController _profileNameCtrl;
  late TextEditingController _profileBioCtrl;
  File? _pendingAvatarFile;

  StreamSubscription<List<JuzzioFriendship>>? _friendSub;
  StreamSubscription<List<JuzzioStory>>? _storySub;
  StreamSubscription<List<JuzzioCallLog>>? _callLogSub;

  bool get _incomingCallBannerVisible => _incomingCall != null;

  JuzzioMessage? _headsUpMessage;
  final TextEditingController _quickReplyCtrl = TextEditingController();
  bool _isSendingQuickReply = false;

  JuzzioFriendship? _headsUpFriendRequest;
  final Set<String> _seenFriendReqIds = {};
  bool _friendshipsLoadedOnce = false;
  int _lastRenderedMessageCount = 0;
  String _callsFilter = 'all';
  Stream<List<JuzzioMessage>>? _activeMessagesStream;
  String? _activeMessagesStreamRoomId;

  /// Her yeniden çizimde yeni Realtime kanalı açılmasını önlemek için oda başına tek akış
  Stream<List<JuzzioMessage>> _messagesStreamFor(String roomId) {
    if (_activeMessagesStream == null || _activeMessagesStreamRoomId != roomId) {
      _activeMessagesStreamRoomId = roomId;
      _activeMessagesStream = SupabaseService.instance.watchRoomMessages(roomId);
    }
    return _activeMessagesStream!;
  }

  static const List<String> _reactionEmojis = ['❤️‍🔥', '🥹', '🌸', '🫣', '🤩'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    JuzzioAppController.instance.ensureBackgroundNotificationReady();
    _profileNameCtrl = TextEditingController(text: widget.myDisplayName);
    _profileBioCtrl = TextEditingController();
    _msgCtrl.addListener(_onComposerTextChanged);
    _composerFocus.addListener(() {
      if (_composerFocus.hasFocus && _showEmojiPanel && mounted) setState(() => _showEmojiPanel = false);
    });
    _initializeWorkspace();
    // v0.6: ana ekran widget'ındaki hızlı eylemler
    _widgetActionSub = JuzzioNative.widgetActions.listen(_handleWidgetAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await JuzzioNative.takePendingWidgetAction();
      if (pending != null && mounted) _handleWidgetAction(pending);
    });
  }

  void _handleWidgetAction(String action) {
    if (!mounted) return;
    if (action == 'camera') {
      _openCreatorStudio(JuzzioStudioMode.story);
      return;
    }
    if (_isInsideConversation) _leaveConversation();
    setState(() {
      switch (action) {
        case 'calls':
          _selectedBottomTab = 1;
          break;
        case 'new_message':
          _selectedBottomTab = 0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openNewMessageScreen();
          });
          break;
        default:
          _selectedBottomTab = 0;
          _selectedFilterIndex = 0;
      }
    });
  }

  /// Ana ekran widget'ına okunmamış sayısı ve son sohbeti yazar (değişmediyse çağrı yapılmaz).
  void _syncHomeWidget() {
    final app = JuzzioAppController.instance;
    var unread = 0;
    for (final c in _conversations) {
      if (!c.isMuted) unread += c.unreadCount;
    }
    final sorted = _conversations.where((c) => c.lastMessageAt != null).toList()
      ..sort((a, b) => b.lastMessageAt!.compareTo(a.lastMessageAt!));
    final myUid = SupabaseService.instance.currentUserId;
    String nameOf(JuzzioConversation c) => c.isGroup ? c.title : (c.partnerDisplayName ?? c.title);
    String textOf(JuzzioConversation c) {
      final preview = (c.lastMessagePreview ?? '').trim();
      final sender = c.lastMessageSender ?? '';
      if (sender.isNotEmpty && sender == myUid) return '${app.trEn("Sen", "You", "Du")}: $preview';
      // v0.7.0: grup önizlemesinde kullanıcı kimliği (uuid) yerine gönderenin adı
      if (c.isGroup && sender.isNotEmpty) return '${_resolveSenderName(sender)}: $preview';
      return preview;
    }

    final latest = sorted.isEmpty ? null : sorted.first;
    final recent = [
      for (final c in sorted.take(3)) {'name': nameOf(c), 'text': textOf(c), 'unread': c.isMuted ? 0 : c.unreadCount},
    ];
    var lastCall = '';
    if (_callLogs.isNotEmpty) {
      final log = _callLogs.first;
      final out = log.callerId == myUid;
      final missed = !out && log.isMissedLike;
      final t = log.createdAt.toLocal();
      lastCall = jsonEncode({
        'name': log.isGroup && log.groupTitle.isNotEmpty ? log.groupTitle : (out ? log.receiverName : log.callerName),
        'missed': missed,
        'status': missed
            ? app.trEn('Cevapsız', 'Missed', 'Verpasst')
            : (log.wasAnswered
                ? '${out ? "↗" : "↙"} ${_formatCallDuration(log.durationSec)}'
                : app.trEn('Cevap yok', 'No answer', 'Keine Antwort')),
        'time': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      });
    }
    final me = _myProfile?.displayName ?? widget.myDisplayName;
    final firstName = me.trim().split(RegExp(r'\s+')).first;
    unawaited(JuzzioNative.updateHomeWidget(
      unread: unread,
      lastName: latest == null ? '' : nameOf(latest),
      lastText: latest == null ? '' : textOf(latest),
      userName: firstName,
      palette: app.glassPaletteId,
      lang: app.uiLang,
      dark: app.isDark,
      recentJson: jsonEncode(recent),
      lastCallJson: lastCall,
    ));
  }

  bool _composerHasText = false;
  void _onComposerTextChanged() {
    final has = _msgCtrl.text.trim().isNotEmpty;
    if (has != _composerHasText && mounted) setState(() => _composerHasText = has);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state != AppLifecycleState.resumed) {
      // Ana ekrana dönerken widget'lar güncel tema/dil/verilerle yenilenir
      _syncHomeWidget();
      JuzzioAppController.instance.ensureBackgroundNotificationReady();
      if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
        SupabaseService.instance.setPresence(false);
        SupabaseService.instance.setActiveRoom(null);
      }
    } else {
      SupabaseService.instance.setPresence(true);
      JuzzioFcmPushService.instance.checkInitialLaunchPushPayload();
      if (_isInsideConversation && _activeConversationRoomId != null) {
        SupabaseService.instance.markRoomRead(_activeConversationRoomId!);
        SupabaseService.instance.setActiveRoom(_activeConversationRoomId);
      }
    }
  }

  Future<void> _initializeWorkspace() async {
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    try {
      await JuzzioAppController.instance.loadUserPreferences(uid);
    } catch (_) {}
    // v0.5.0: önce yerel önbellekten anında çiz, ağdan gelen veri arka planda günceller
    final cached = await Future.wait<Object?>([
      svc.loadCachedConversations(),
      svc.loadCachedMyProfile(),
      svc.loadCachedProfiles(),
    ]);
    if (mounted) {
      final cachedConvs = cached[0] as List<JuzzioConversation>;
      final cachedMe = cached[1] as JuzzioUserProfile?;
      final cachedProfiles = cached[2] as List<JuzzioUserProfile>;
      setState(() {
        if (cachedConvs.isNotEmpty && !_conversationsLoaded) {
          _conversations = cachedConvs;
          _conversationsLoaded = true;
          _groupRooms = cachedConvs.where((c) => c.isGroup).map((c) => c.toGroupRoom()).toList();
        }
        if (cachedMe != null && _myProfile == null) _myProfile = cachedMe;
        if (cachedProfiles.isNotEmpty && _allProfiles.isEmpty) _allProfiles = cachedProfiles;
      });
    }
    // 2. Yalnızca benim sohbetlerim (1'e 1 + gruplar)
    _convSub = svc.watchMyConversations().listen((list) {
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _conversationsLoaded = true;
        _groupRooms = list.where((c) => c.isGroup).map((c) => c.toGroupRoom()).toList();
        if (_activeGroupRoom != null) {
          for (final g in _groupRooms) {
            if (g.id == _activeGroupRoom!.id) _activeGroupRoom = g;
          }
        }
      });
      _syncHomeWidget();
    }, onError: (_) {
      if (mounted) setState(() => _conversationsLoaded = true);
    });

    if (uid != null) {
      final prof = await svc.fetchUserProfile(uid);
      if (prof != null && mounted) {
        setState(() {
          _myProfile = prof;
          _profileNameCtrl.text = prof.displayName;
          _profileBioCtrl.text = prof.bio;
        });
        // v0.8.3: hesap dili yeni cihaza taşınır (cihazda seçim yoksa)
        unawaited(JuzzioAppController.instance.adoptAccountUiLanguage(prof.appLang));
      }
    }
    svc.setPresence(true);
    // v0.8.3: yöneticinin yayınladığı küresel tema (tema seçmemiş kullanıcılar için)
    unawaited(JuzzioFeaturesService.instance.activeGlobalTheme().then(JuzzioAppController.instance.setGlobalThemeFromServer));
    svc.attachPreferenceSync();
    _refreshSocialFeedAndProfile();
    _enforceDeviceAccess();
    _checkMaintenanceMode();

    try {
      await JuzzioFcmPushService.instance.initializeAndSync();
    } catch (_) {}
    _fcmTapSub?.cancel();
    _fcmForegroundSub?.cancel();
    _fcmTapSub = JuzzioFcmPushService.instance.onNotificationTap.listen((payload) {
      if (!mounted) return;
      _handlePushDeepLink(payload);
    });
    // v0.5.0: Tek push kanalı FCM. Uygulama ön plandayken de bildirim içeriği
    // FCM'den gelir (sunucuda alıcının dilinde hazırlanır); yerel ikinci bir
    // bildirim üretilmez.
    _fcmForegroundSub?.cancel();
    _fcmForegroundSub = JuzzioFcmPushService.instance.onForegroundMessage.listen(_handleForegroundPush);

    _socialNotifSub?.cancel();
    _socialNotifSub = JuzzioSocialService.instance.watchMyNotifications().listen((notifs) {
      if (!mounted) return;
      setState(() => _unreadNotificationsCount = notifs.where((n) => !n.isRead).length);
    }, onError: (_) {});

    final others = await svc.fetchAllProfiles();
    if (mounted) setState(() => _allProfiles = others);

    // 1. Kullanıcı profilleri (yalnızca isim/avatar çözümlemesi ve öneriler için; arkadaş listesi DEĞİL)
    _profilesSub = svc.watchAllProfiles().listen((profiles) {
      if (!mounted) return;
      setState(() => _allProfiles = profiles);
    }, onError: (_) {});

    // 3. Yeni mesaj bildirimleri (RLS: yalnızca üyesi olduğum odalardan)
    _incomingMsgSub = svc.watchIncomingMessages().listen(_handleIncomingMessage, onError: (_) {});

    // 4. Bana gelen aramalar (yalnızca alıcıya özel; başkalarının araması çalmaz)
    _incomingCallSub = svc.watchIncomingCalls().listen(_handleIncomingCalls, onError: (_) {});

    // 5. Arkadaşlık istekleri
    _friendSub = svc.watchFriendships().listen((list) {
      if (!mounted) return;
      final myUid = svc.currentUserId;
      setState(() => _friendships = list);
      final firstLoad = !_friendshipsLoadedOnce;
      _friendshipsLoadedOnce = true;
      for (final f in list) {
        if (f.receiverId == myUid && f.status == 'pending' && !_seenFriendReqIds.contains(f.id)) {
          _seenFriendReqIds.add(f.id);
          if (firstLoad) continue;
          // Sistem bildirimi FCM ile gelir; burada yalnızca uygulama içi şerit
          setState(() => _headsUpFriendRequest = f);
          break;
        }
      }
    }, onError: (_) {});

    // 6. 24 saatlik hikâyeler (RLS: görünürlük ayarına göre)
    _storySub = svc.watchActiveStories().listen((stories) {
      if (!mounted) return;
      setState(() => _activeStories = stories.where((s) => !s.isExpired).toList());
    }, onError: (_) {});

    // 7. Arama geçmişi (yalnızca benim aramalarım)
    _callLogSub = svc.watchCallLogs().listen((logs) {
      if (!mounted) return;
      setState(() => _callLogs = logs);
      _syncHomeWidget();
    }, onError: (_) {});

    JuzzioSounds.instance.load();
    JuzzioStorySeen.instance.load();
    JuzzioStorySeen.instance.addListener(_onStorySeenChanged);
    // v0.7.0: uçtan uca şifreleme anahtarı (yoksa üretilir, açık anahtar yayınlanır)
    JuzzioE2ee.instance.ensureReady().then((_) {
      if (mounted) maybeOfferJuzzioRestore(context);
    });
    // 8. OTA sürüm güncelleme (kalıcı erteleme durumu önce yüklenir)
    JuzzioAppController.instance.ensureOtaStateLoaded().then((_) {
      JuzzioAppController.instance.checkForOtaUpdate();
      if (mounted) JuzzioWhatsNewSheet.showIfPending(context);
    });
    _releaseSub = svc.watchAppReleases().listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final latest = rows.first;
      final ver = (latest['version_name'] ?? JuzzioConfig.appVersion).toString();
      final code = (latest['version_code'] as num?)?.toInt() ?? JuzzioConfig.appVersionCode;
      JuzzioAppController.instance.applyDetectedRemoteRelease(
        versionName: ver,
        versionCode: code,
        notesTr: (latest['notes_tr'] ?? 'Yeni sürüm v$ver hazır!').toString(),
        notesEn: (latest['notes_en'] ?? 'New version v$ver is ready!').toString(),
        notesDe: (latest['notes_de'] ?? '').toString(),
        apkUrl: latest['apk_url']?.toString(),
        mandatory: latest['is_mandatory'] == true,
        details: latest['details'] is Map ? Map<String, dynamic>.from(latest['details'] as Map) : const <String, dynamic>{},
      );
    }, onError: (_) {});
  }

  JuzzioConversation? _conversationById(String? roomId) {
    if (roomId == null) return null;
    for (final c in _conversations) {
      if (c.roomId == roomId) return c;
    }
    return null;
  }

  Future<void> _handleIncomingMessage(JuzzioMessage msg) async {
    if (!mounted) return;
    final viewingThisRoom = _isInsideConversation && _activeConversationRoomId == msg.roomId && !_isAppInBackground;
    if (viewingThisRoom) {
      SupabaseService.instance.markRoomRead(msg.roomId);
      return;
    }
    final conv = _conversationById(msg.roomId);
    final isMuted = (conv?.isMuted ?? false) || _mutedConversationIds.contains(msg.roomId);
    if (isMuted) return;
    final subLang = JuzzioAppController.instance.subtitleLang;
    final displayBody = msg.isDeleted ? '' : await _resolveTranslatedMessageText(msg, subLang);
    final senderLabel = msg.senderName.isNotEmpty ? msg.senderName : _resolveSenderName(msg.senderId);
    final body = msg.storyReplyMeta != null
        ? '📸 ${JuzzioAppController.instance.trEn("Hikâyene yanıt", "Replied to your story", "Hat auf deine Story geantwortet")}: $displayBody'
        : _messagePreviewLabel(msg, displayBody);
    // Sistem bildirimi FCM'den gelir (_handleForegroundPush); burada yalnızca
    // uygulama içi üst şerit gösterilir.
    if (mounted && !_isInsideConversation && body.isNotEmpty && senderLabel.isNotEmpty) {
      setState(() => _headsUpMessage = msg);
    }
  }

  void _handleForegroundPush(JuzzioPushEventPayload payload) {
    if (!mounted) return;
    final key = payload.notificationId.isNotEmpty
        ? payload.notificationId
        : '${payload.eventType}_${payload.targetId}_${payload.targetSecondaryId}';
    if (!_shownForegroundPushIds.add(key)) return;
    if (_shownForegroundPushIds.length > 300) _shownForegroundPushIds.clear();
    final et = payload.eventType;
    // Gelen arama tam ekran arama arayüzüyle gösterilir
    if (et == 'incoming_call') return;
    const roomEvents = {'message', 'group_activity', 'story_reply', 'reaction'};
    if (roomEvents.contains(et) && payload.targetId.isNotEmpty) {
      final viewing = _isInsideConversation && _activeConversationRoomId == payload.targetId && !_isAppInBackground;
      if (viewing) return;
      final conv = _conversationById(payload.targetId);
      if ((conv?.isMuted ?? false) || _mutedConversationIds.contains(payload.targetId)) return;
    }
    if (payload.title.isEmpty && payload.body.isEmpty) return;
    JuzzioAppController.instance.triggerSystemNotification(
      title: payload.title,
      body: payload.body,
      isUpdate: et == 'system',
      isCall: et == 'missed_call',
      channelId: payload.channelId.startsWith('juzzio_') ? payload.channelId : null,
    );
  }

  String _messagePreviewLabel(JuzzioMessage msg, String text) {
    final app = JuzzioAppController.instance;
    switch (msg.messageType) {
      case 'voice':
        return '🎤 ${app.trEn("Sesli mesaj", "Voice message", "Sprachnachricht")}${text.isNotEmpty && !text.startsWith("🎤") ? ": $text" : ""}';
      case 'image':
        return '📷 ${text.isNotEmpty ? text : app.trEn("Fotoğraf", "Photo", "Foto")}';
      case 'video':
        return '🎬 ${text.isNotEmpty ? text : app.trEn("Video", "Video", "Video")}';
      default:
        return text;
    }
  }

  void _handleIncomingCalls(List<JuzzioCallLog> ringing) {
    if (!mounted) return;
    final current = _incomingCall;
    if (current != null && !ringing.any((c) => c.id == current.id)) {
      // Arayan iptal etti veya başka cihazdan cevaplandı
      JuzzioSounds.instance.stopRinging();
      setState(() => _incomingCall = null);
    }
    if (_incomingCall != null || _isInCall) return;
    final fresh = ringing.where((c) => !_handledIncomingCallIds.contains(c.id)).toList();
    if (fresh.isEmpty) return;
    final call = fresh.first;
    _handledIncomingCallIds.add(call.id);

    final app = JuzzioAppController.instance;
    if (app.isSilentMode) {
      SupabaseService.instance.updateCallStatus(callId: call.id, status: 'busy_silent');
      return;
    }
    app.triggerSystemNotification(
      title: call.isGroup
          ? app.trEn(
              '${call.callerName}, ${call.groupTitle} grubunda ${call.isVideo ? "görüntülü" : "sesli"} konferans başlattı',
              '${call.callerName} started a ${call.isVideo ? "video" : "voice"} conference in ${call.groupTitle}', '${call.callerName} hat in ${call.groupTitle} eine ${call.isVideo ? "Video" : "Sprach"}konferenz gestartet',
            )
          : app.trEn('${call.callerName} seni arıyor...', '${call.callerName} is calling you...', '${call.callerName} ruft dich an...'),
      body: app.trEn('Aramaya katılmak veya reddetmek için dokunun.', 'Tap to join or decline.', 'Tippe zum Beitreten oder Ablehnen.'),
      isCall: true,
      channelId: JuzzioSounds.instance.callChannelFor(call.callerId),
    );
    // v0.7.0: uygulama açıkken seçilen (kişiye özel veya varsayılan) zil sesi döngüde çalar
    JuzzioSounds.instance.startRinging(call.callerId);
    setState(() => _incomingCall = call);
  }

  bool appCtrlIsDark() => JuzzioAppController.instance.isDark;

  void _onStorySeenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profilesSub?.cancel();
    _convSub?.cancel();
    _incomingMsgSub?.cancel();
    _incomingCallSub?.cancel();
    _friendSub?.cancel();
    _storySub?.cancel();
    _callLogSub?.cancel();
    _groupSub?.cancel();
    _releaseSub?.cancel();
    JuzzioSounds.instance.stopRinging();
    _socialNotifSub?.cancel();
    _fcmTapSub?.cancel();
    _fcmForegroundSub?.cancel();
    _widgetActionSub?.cancel();
    _recordAmplitudeTimer?.cancel();
    _voiceUiTimer?.cancel();
    _presenceTimer?.cancel();
    _composerFocus.dispose();
    _msgCtrl.removeListener(_onComposerTextChanged);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _profileNameCtrl.dispose();
    _profileBioCtrl.dispose();
    _quickReplyCtrl.dispose();
    _voiceRecorder.dispose();
    _audioPlayer.dispose();
    JuzzioStorySeen.instance.removeListener(_onStorySeenChanged);
    super.dispose();
  }

  Set<String> get _acceptedFriendIds {
    final myUid = SupabaseService.instance.currentUserId ?? '';
    final ids = <String>{};
    for (final f in _friendships) {
      if (f.status == 'accepted') {
        if (f.requesterId == myUid) ids.add(f.receiverId);
        if (f.receiverId == myUid) ids.add(f.requesterId);
      }
    }
    return ids;
  }

  /// YALNIZCA kabul edilmiş arkadaşlar. (Eski sürüm arkadaş yoksa TÜM kayıtlı
  /// kullanıcıları arkadaş gibi gösteriyordu — bu hata giderildi.)
  List<JuzzioUserProfile> get _acceptedFriendProfiles {
    final friendIds = _acceptedFriendIds;
    final myUid = SupabaseService.instance.currentUserId;
    final byId = <String, JuzzioUserProfile>{
      for (final u in _allProfiles)
        if (u.id != myUid && friendIds.contains(u.id)) u.id: u,
    };
    // Profil listesinde (ilk 200) olmayan arkadaşlar için arkadaşlık kaydındaki bilgiyi kullan
    for (final f in _friendships.where((f) => f.status == 'accepted')) {
      final otherId = f.otherUserId(myUid ?? '');
      if (otherId.isEmpty || byId.containsKey(otherId)) continue;
      final isRequesterOther = f.requesterId == otherId;
      byId[otherId] = JuzzioUserProfile(
        id: otherId,
        username: isRequesterOther ? f.requesterUsername : f.receiverUsername,
        displayName: isRequesterOther ? f.requesterName : f.receiverName,
        email: '',
        bio: '',
        preferredLang: 'tr',
        avatarUrl: isRequesterOther ? f.requesterAvatar : f.receiverAvatar,
      );
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return list;
  }

  /// Arkadaş olmayan, engellenmemiş kullanıcı önerileri
  List<JuzzioUserProfile> get _suggestedPeople {
    final myUid = SupabaseService.instance.currentUserId;
    final related = <String>{
      for (final f in _friendships) ...[f.requesterId, f.receiverId],
    };
    final blocked = JuzzioSocialService.instance.blockedUserIds;
    return _allProfiles
        .where((u) => u.id != myUid && !related.contains(u.id) && !blocked.contains(u.id))
        .take(30)
        .toList();
  }

  List<JuzzioFriendship> get _pendingIncomingRequests {
    final myUid = SupabaseService.instance.currentUserId;
    return _friendships.where((f) => f.receiverId == myUid && f.status == 'pending').toList();
  }

  /// RLS zaten görünürlüğü uygular; burada ek olarak sessize alınanlar ve süre kontrolü yapılır.
  List<JuzzioStory> get _visibleFriendStories24h {
    final muted = JuzzioSocialService.instance.mutedUserIds;
    final myUid = SupabaseService.instance.currentUserId;
    return _activeStories.where((s) {
      if (s.isExpired) return false;
      if (s.userId == myUid) return true;
      return !muted.contains(s.userId);
    }).toList();
  }

  String _resolveSenderName(String senderId) {
    for (final p in _allProfiles) {
      if (p.id == senderId) return p.displayName;
    }
    for (final c in _conversations) {
      if (c.partnerId == senderId) return c.partnerDisplayName ?? c.title;
    }
    return JuzzioAppController.instance.trEn('Juzzio Kullanıcısı', 'Juzzio User', 'Juzzio-Nutzer');
  }

  String? _resolveAvatar(String userId) {
    for (final p in _allProfiles) {
      if (p.id == userId) return p.avatarUrl;
    }
    return null;
  }

  String _resolvePartnerLanguage(String? partnerId, String? partnerName) {
    for (final p in _allProfiles) {
      if ((partnerId != null && p.id == partnerId) ||
          (partnerName != null && p.displayName.toLowerCase() == partnerName.toLowerCase())) {
        return p.preferredLang;
      }
    }
    return JuzzioAppController.instance.subtitleLang;
  }

  List<String> _resolveGroupMemberLanguages(List<String> memberNames) {
    final langs = <String>[];
    for (final name in memberNames) {
      String found = JuzzioAppController.instance.subtitleLang;
      for (final p in _allProfiles) {
        if (p.displayName.toLowerCase() == name.toLowerCase() || p.username.toLowerCase() == name.toLowerCase()) {
          found = p.preferredLang;
          break;
        }
      }
      langs.add(found);
    }
    return langs;
  }

  Future<String> _resolveTranslatedMessageText(JuzzioMessage msg, String desiredLang) async {
    final cleanDesired = desiredLang.toLowerCase();
    if (msg.originalText.trim().isEmpty) return '';
    if (msg.targetLang.toLowerCase() == cleanDesired && msg.translatedText.trim().isNotEmpty) {
      return msg.translatedText;
    }
    if (msg.sourceLang.toLowerCase() == cleanDesired) {
      return msg.originalText;
    }
    final cacheKey = '${msg.id}_$cleanDesired';
    if (_localRetranslatedText.containsKey(cacheKey)) {
      return _localRetranslatedText[cacheKey]!;
    }
    final retranslated = await SupabaseService.instance.translateText(
      text: msg.originalText,
      sourceLang: 'auto',
      targetLang: cleanDesired,
    );
    _localRetranslatedText[cacheKey] = retranslated;
    return retranslated;
  }

  void _showSnack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? JuzzioColors.red500 : JuzzioColors.ink,
        content: Text(text),
      ),
    );
  }

  void _enterConversation({required String roomId, JuzzioUserProfile? partner, JuzzioGroupRoom? group}) {
    _lastRenderedMessageCount = 0;
    _activeMessagesStream = null;
    _activeMessagesStreamRoomId = null;
    setState(() {
      _activeGroupRoom = group;
      _activeFriendPartner = group == null ? partner : null;
      _activeConversationRoomId = roomId;
      _selectedBottomTab = 0;
      _isInsideConversation = true;
      _headsUpMessage = null;
    });
    SupabaseService.instance.markRoomRead(roomId);
    SupabaseService.instance.setActiveRoom(roomId);
  }

  void _leaveConversation() {
    final roomId = _activeConversationRoomId;
    if (_isRecordingVoice) _cancelVoiceRecording();
    _ensurePresenceWatch(null);
    setState(() {
      _isInsideConversation = false;
      _showEmojiPanel = false;
    });
    if (roomId != null) SupabaseService.instance.markRoomRead(roomId);
    SupabaseService.instance.setActiveRoom(null);
  }

  void _openConversation(JuzzioConversation conv) {
    if (conv.isGroup) {
      _enterConversation(roomId: conv.roomId, group: conv.toGroupRoom());
    } else {
      final partner = conv.toPartnerProfile();
      JuzzioUserProfile? richer;
      for (final p in _allProfiles) {
        if (p.id == conv.partnerId) richer = p;
      }
      _enterConversation(roomId: conv.roomId, partner: richer ?? partner);
    }
  }

  Future<void> _openDirectChatWithFriend(JuzzioUserProfile friend) async {
    try {
      final dmRoomId = await SupabaseService.instance.ensureDirectRoomWithFriend(
        friendId: friend.id,
        friendName: friend.displayName,
      );
      if (!mounted) return;
      _enterConversation(roomId: dmRoomId, partner: friend);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _openRoomById(String roomId) async {
    final conv = _conversationById(roomId) ??
        (await SupabaseService.instance.fetchMyConversations()).where((c) => c.roomId == roomId).firstOrNull;
    if (conv != null && mounted) _openConversation(conv);
  }

  /// v0.7.0: Sohbete girişte her zaman en son mesaj görünür. ListView.builder öğeleri
  /// tembel ölçtüğü için ilk açılışta maxScrollExtent birkaç kare boyunca büyür; bu yüzden
  /// değer sabitlenene kadar en alta atlanır. Sonraki yeni mesajlarda yumuşak kaydırılır
  /// (kullanıcı yukarıda eski mesajları okuyorsa ve mesaj başkasındansa zorla kaydırılmaz).
  /// v0.8.0: klavye/emoji paneli açılınca son mesaj klavyenin altında kalmaz
  double _lastKeyboardInset = 0;
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final inset = views.first.viewInsets.bottom;
    if (inset > _lastKeyboardInset + 1 && _scrollCtrl.hasClients) {
      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent - pos.pixels < 600) {
        Future.delayed(const Duration(milliseconds: 120), () => _scrollMessagesToBottom(force: true));
      }
    }
    _lastKeyboardInset = inset;
  }

  void _scrollMessagesToBottom({bool instant = false, bool force = false}) {
    if (instant) {
      int frames = 0;
      double last = -1;
      void settle(Duration _) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final max = _scrollCtrl.position.maxScrollExtent;
        _scrollCtrl.jumpTo(max);
        frames++;
        if ((max - last).abs() > 0.5 && frames < 12) {
          last = max;
          WidgetsBinding.instance.addPostFrameCallback(settle);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback(settle);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      final nearBottom = pos.maxScrollExtent - pos.pixels < 420;
      if (!force && !nearBottom) return;
      _scrollCtrl.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Cihazı kaydeder; hesap/cihaz engelliyse oturumu kapatıp engel ekranını gösterir.
  /// Bakım modu: yönetici dışındaki kullanıcılar bilgilendirme ekranında bekler.
  Future<void> _checkMaintenanceMode() async {
    final cfg = await JuzzioFeaturesService.instance.fetchAppConfig();
    if (!cfg.maintenanceMode || !mounted) return;
    final admin = await JuzzioFeaturesService.instance.isAdmin();
    if (admin || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JuzzioMaintenanceScreen(message: cfg.maintenanceMessage)),
    );
  }

  Future<void> _enforceDeviceAccess() async {
    final res = await JuzzioFeaturesService.instance.checkDeviceAccess(register: true);
    if (!res.banned) {
      // Civciv bildirim metinleri (Kız/Erkek/Belirtilmemiş) için önbelleğe alınır.
      unawaited(JuzzioFeaturesService.instance.fetchMyGender());
      return;
    }
    if (!mounted) return;
    try {
      await SupabaseService.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => JuzzioBannedScreen(reasonCode: res.reason, until: res.until, moderation: res.moderation),
      ),
      (route) => false,
    );
  }

  JuzzioConversation? get _activeConversationData {
    final id = _activeConversationRoomId;
    if (id == null) return null;
    for (final c in _conversations) {
      if (c.roomId == id) return c;
    }
    return null;
  }

  Future<void> _sendText() async {
    final txt = _msgCtrl.text.trim();
    final roomId = _activeConversationRoomId;
    if (txt.isEmpty || roomId == null) return;
    final replyTarget = _replyingTo;
    _msgCtrl.clear();
    if (replyTarget != null) setState(() => _replyingTo = null);
    try {
      await SupabaseService.instance.sendTextMessage(
        text: txt,
        sourceLang: JuzzioAppController.instance.subtitleLang,
        senderName: _myProfile?.displayName ?? widget.myDisplayName,
        targetRoomId: roomId,
        replyToId: replyTarget?.id,
      );
      _scrollMessagesToBottom(force: true);
    } catch (e) {
      _msgCtrl.text = txt;
      if (mounted && replyTarget != null) setState(() => _replyingTo = replyTarget);
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _sendQuickReplyFromBanner() async {
    final txt = _quickReplyCtrl.text.trim();
    final target = _headsUpMessage;
    if (txt.isEmpty || _isSendingQuickReply || target == null) return;

    setState(() => _isSendingQuickReply = true);
    try {
      await SupabaseService.instance.sendTextMessage(
        text: txt,
        sourceLang: JuzzioAppController.instance.subtitleLang,
        senderName: _myProfile?.displayName ?? widget.myDisplayName,
        targetRoomId: target.roomId,
      );
      _quickReplyCtrl.clear();
      if (mounted) setState(() => _headsUpMessage = null);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSendingQuickReply = false);
    }
  }

  Future<void> _pickAndSendChatMedia() async {
    final roomId = _activeConversationRoomId;
    if (roomId == null) return;
    final app = JuzzioAppController.instance;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: JuzzioPalette(app.isDark).sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(app.trEn('Galeriden Fotoğraf', 'Photo from Gallery', 'Foto aus der Galerie')),
              onTap: () => Navigator.pop(ctx, 'gallery_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(app.trEn('Fotoğraf Çek', 'Take Photo', 'Foto aufnehmen')),
              onTap: () => Navigator.pop(ctx, 'camera_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(app.trEn('Galeriden Video', 'Video from Gallery', 'Video aus der Galerie')),
              onTap: () => Navigator.pop(ctx, 'gallery_video'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(app.trEn('Video Çek', 'Record Video', 'Video aufnehmen')),
              onTap: () => Navigator.pop(ctx, 'camera_video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      XFile? picked;
      final isVideo = choice.endsWith('video');
      final source = choice.startsWith('camera') ? ImageSource.camera : ImageSource.gallery;
      if (isVideo) {
        picked = await _imagePicker.pickVideo(source: source, maxDuration: const Duration(minutes: 3));
      } else {
        picked = await _imagePicker.pickImage(source: source, imageQuality: 85, maxWidth: 2048);
      }
      if (picked == null) return;
      _showSnack(app.trEn('Gönderiliyor...', 'Sending...', 'Wird gesendet...'));
      await SupabaseService.instance.sendMediaMessage(
        roomId: roomId,
        file: File(picked.path),
        isVideo: isVideo,
        caption: _msgCtrl.text.trim(),
      );
      _msgCtrl.clear();
      _scrollMessagesToBottom(force: true);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      final hasPerm = await _voiceRecorder.hasPermission();
      if (!hasPerm) {
        _showSnack(JuzzioAppController.instance.trEn('Mikrofon izni gerekli.', 'Microphone permission required.', 'Mikrofonberechtigung erforderlich.'),
            isError: true);
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/juzzio_vn_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _livePeaks.clear();
      _recordStartTime = DateTime.now();
      _voiceLocked = false;
      _voicePaused = false;
      _voiceDrag = Offset.zero;
      _voicePausedTotal = Duration.zero;
      _voicePauseStartedAt = null;
      _voiceRecordingPath = outPath;
      HapticFeedback.mediumImpact();

      await _voiceRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: outPath,
      );
      _voiceUiTimer?.cancel();
      _voiceUiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _isRecordingVoice) setState(() {});
      });

      _recordAmplitudeTimer?.cancel();
      _recordAmplitudeTimer = Timer.periodic(const Duration(milliseconds: 110), (_) async {
        try {
          final amp = await _voiceRecorder.getAmplitude();
          final norm = ((amp.current + 45.0) / 45.0).clamp(0.12, 1.0);
          _livePeaks.add(double.parse(norm.toStringAsFixed(2)));
        } catch (_) {}
      });

      if (mounted) setState(() => _isRecordingVoice = true);
    } catch (_) {}
  }

  /// Kayıt süresi (duraklatılan süreler hariç)
  Duration get _voiceElapsed {
    if (_recordStartTime == null) return Duration.zero;
    var total = DateTime.now().difference(_recordStartTime!) - _voicePausedTotal;
    if (_voicePauseStartedAt != null) total -= DateTime.now().difference(_voicePauseStartedAt!);
    return total.isNegative ? Duration.zero : total;
  }

  Future<void> _toggleVoicePause() async {
    if (!_isRecordingVoice) return;
    try {
      if (_voicePaused) {
        await _voiceRecorder.resume();
        if (_voicePauseStartedAt != null) {
          _voicePausedTotal += DateTime.now().difference(_voicePauseStartedAt!);
        }
        _voicePauseStartedAt = null;
      } else {
        await _voiceRecorder.pause();
        _voicePauseStartedAt = DateTime.now();
      }
      if (mounted) setState(() => _voicePaused = !_voicePaused);
    } catch (_) {}
  }

  Future<void> _cancelVoiceRecording() async {
    _recordAmplitudeTimer?.cancel();
    _voiceUiTimer?.cancel();
    if (!_isRecordingVoice) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isRecordingVoice = false;
      _voiceLocked = false;
      _voicePaused = false;
      _voiceDrag = Offset.zero;
    });
    try {
      final path = await _voiceRecorder.stop();
      final f = File(path ?? _voiceRecordingPath ?? '');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _onMicDragUpdate(Offset offset) {
    if (!_isRecordingVoice || _voiceLocked) return;
    setState(() => _voiceDrag = offset);
    if (offset.dy < -70) {
      HapticFeedback.mediumImpact();
      setState(() {
        _voiceLocked = true;
        _voiceDrag = Offset.zero;
      });
    } else if (offset.dx < -110) {
      _cancelVoiceRecording();
    }
  }

  void _onMicPressEnd() {
    if (!_isRecordingVoice) return;
    if (_voiceLocked) return; // kilitliyken parmağı kaldırmak kaydı durdurmaz
    _stopAndSendVoiceRecording();
  }

  Future<void> _stopAndSendVoiceRecording() async {
    _recordAmplitudeTimer?.cancel();
    _voiceUiTimer?.cancel();
    if (!_isRecordingVoice) return;

    final elapsed = _voiceElapsed;
    setState(() {
      _isRecordingVoice = false;
      _voiceLocked = false;
      _voicePaused = false;
      _voiceDrag = Offset.zero;
    });
    try {
      final recordedPath = await _voiceRecorder.stop();
      if (recordedPath == null || recordedPath.isEmpty) return;
      final file = File(recordedPath);
      if (!file.existsSync()) return;

      final durationMs = elapsed.inMilliseconds.clamp(600, 300000);
      if (durationMs < 700) return; // yanlışlıkla basılı tutma

      final peaks = _livePeaks.isNotEmpty
          ? List<double>.from(_livePeaks)
          : [0.25, 0.55, 0.82, 0.45, 0.90, 0.62, 0.35, 0.72, 0.48, 0.30];

      await SupabaseService.instance.sendVoiceNote(
        audioFile: file,
        durationMs: durationMs,
        sourceLang: JuzzioAppController.instance.subtitleLang,
        waveformPeaks: peaks,
        targetRoomId: _activeConversationRoomId,
      );
      _scrollMessagesToBottom(force: true);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _togglePlayVoiceNote(JuzzioMessage msg) async {
    if (msg.audioUrl == null || msg.audioUrl!.isEmpty) return;

    if (_playingMessageId == msg.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }

    try {
      setState(() => _playingMessageId = msg.id);
      await _audioPlayer.setUrl(msg.audioUrl!);
      _audioPlayer.play();
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      if (mounted && _playingMessageId == msg.id) setState(() => _playingMessageId = null);
    } catch (_) {
      if (mounted) setState(() => _playingMessageId = null);
    }
  }

  // ---------------------------------------------------------------------------
  // ARAMALAR — her sohbet kendi LiveKit odasını kullanır; yalnızca karşı taraf çalar.
  // ---------------------------------------------------------------------------
  List<JuzzioUserProfile> get _callInvitableUsers => _acceptedFriendProfiles;

  Future<void> _launchCall({
    required bool enableVideo,
    String? targetPartnerName,
    String? targetPartnerId,
    String? targetPartnerAvatar,
    String? targetPartnerLang,
  }) async {
    final app = JuzzioAppController.instance;
    final partnerId = targetPartnerId ?? _activeFriendPartner?.id;
    if (partnerId == null || partnerId.isEmpty) {
      _showSnack(app.trEn('Aranacak kişi seçilmedi.', 'No one selected to call.', 'Niemand zum Anrufen ausgewählt.'), isError: true);
      return;
    }
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null || _isInCall) return;

    final myName = _myProfile?.displayName ?? widget.myDisplayName;
    final partnerName = targetPartnerName ?? _activeFriendPartner?.displayName ?? _resolveSenderName(partnerId);
    final partnerLang = targetPartnerLang ?? _resolvePartnerLanguage(partnerId, partnerName);

    try {
      final roomId = (_activeGroupRoom == null && _activeFriendPartner?.id == partnerId && _activeConversationRoomId != null)
          ? _activeConversationRoomId!
          : await SupabaseService.instance.ensureDirectRoomWithFriend(friendId: partnerId, friendName: partnerName);
      final session = await SupabaseService.instance.startCall(roomId: roomId, isVideo: enableVideo);
      if (!mounted) return;
      _isInCall = true;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            roomId: roomId,
            livekitRoomName: session.livekitRoomName,
            sessionId: session.sessionId,
            isCaller: true,
            isGroupCall: false,
            identity: uid,
            displayName: myName,
            myLanguage: app.subtitleLang,
            partnerLanguage: partnerLang,
            partnerName: partnerName,
            partnerAvatarUrl: targetPartnerAvatar ?? _resolveAvatar(partnerId),
            enableVideo: enableVideo,
            invitableUsers: _callInvitableUsers,
          ),
        ),
      );
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    } finally {
      _isInCall = false;
      // v0.6: arama içerik denetimiyle kapandıysa uzaklaştırma ekranı hemen gösterilir
      unawaited(_enforceDeviceAccess());
    }
  }

  Future<void> _launchGroupConferenceCall({required JuzzioGroupRoom group, required bool isVideo}) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null || _isInCall) return;
    final myName = _myProfile?.displayName ?? widget.myDisplayName;
    try {
      final session = await SupabaseService.instance.startCall(roomId: group.id, isVideo: isVideo);
      if (!mounted) return;
      final memberProfiles = _allProfiles.where((p) => group.groupMemberIds.contains(p.id)).toList();
      _isInCall = true;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            roomId: group.id,
            livekitRoomName: session.livekitRoomName,
            sessionId: session.sessionId,
            isCaller: !session.joinedExisting,
            isGroupCall: true,
            identity: uid,
            displayName: myName,
            myLanguage: JuzzioAppController.instance.subtitleLang,
            enableVideo: isVideo,
            groupTitle: group.title,
            groupMembers: group.groupMembers,
            groupMemberLanguages: _resolveGroupMemberLanguages(group.groupMembers),
            invitableUsers: {
              for (final u in [..._callInvitableUsers, ...memberProfiles]) u.id: u,
            }.values.toList(),
          ),
        ),
      );
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    } finally {
      _isInCall = false;
      // v0.6: arama içerik denetimiyle kapandıysa uzaklaştırma ekranı hemen gösterilir
      unawaited(_enforceDeviceAccess());
    }
  }

  Future<void> _acceptIncomingCall() async {
    final call = _incomingCall;
    final uid = SupabaseService.instance.currentUserId;
    JuzzioSounds.instance.stopRinging();
    if (call == null || uid == null) return;
    setState(() => _incomingCall = null);
    final answerError = await SupabaseService.instance.answerCall(call.id);
    if (!mounted) return;
    if (answerError != null) {
      _showSnack(answerError, isError: true);
      return;
    }
    final app = JuzzioAppController.instance;
    final group = call.isGroup ? _groupRooms.where((g) => g.id == call.roomId).firstOrNull : null;
    _isInCall = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            roomId: call.roomId,
            livekitRoomName: call.livekitRoomName,
            sessionId: call.sessionId,
            callLogId: call.id,
            isCaller: false,
            isGroupCall: call.isGroup,
            identity: uid,
            displayName: _myProfile?.displayName ?? widget.myDisplayName,
            myLanguage: app.subtitleLang,
            partnerLanguage: _resolvePartnerLanguage(call.callerId, call.callerName),
            partnerName: call.callerName,
            partnerAvatarUrl: call.callerAvatar,
            enableVideo: call.isVideo,
            groupTitle: call.isGroup ? (call.groupTitle.isNotEmpty ? call.groupTitle : group?.title) : null,
            groupMembers: group?.groupMembers ?? const [],
            groupMemberLanguages: group != null ? _resolveGroupMemberLanguages(group.groupMembers) : const [],
            invitableUsers: _callInvitableUsers,
          ),
        ),
      );
    } finally {
      _isInCall = false;
      // v0.6: arama içerik denetimiyle kapandıysa uzaklaştırma ekranı hemen gösterilir
      unawaited(_enforceDeviceAccess());
    }
  }

  Future<void> _declineIncomingCall() async {
    final call = _incomingCall;
    JuzzioSounds.instance.stopRinging();
    if (call == null) return;
    setState(() => _incomingCall = null);
    await SupabaseService.instance.updateCallStatus(callId: call.id, status: 'rejected');
  }

  Future<void> _pickAndCropAvatarImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1400,
      );
      if (picked == null || !mounted) return;

      final croppedFile = await JuzzioImageCropperModal.show(
        context,
        sourceFile: File(picked.path),
        isCircular: true,
        aspectRatio: 1.0,
      );
      if (croppedFile == null || !mounted) return;

      setState(() => _pendingAvatarFile = croppedFile);
      await _saveProfileChanges();
    } catch (_) {}
  }

  Future<void> _saveProfileChanges() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;

    try {
      final updated = await SupabaseService.instance.uploadAvatarAndSaveProfile(
        userId: uid,
        displayName: _profileNameCtrl.text.trim().isEmpty
            ? widget.myDisplayName
            : _profileNameCtrl.text.trim(),
        bio: (_myProfile?.bio ?? _profileBioCtrl.text).trim(),
        preferredLang: JuzzioAppController.instance.subtitleLang,
        newAvatarFile: _pendingAvatarFile,
        existingAvatarUrl: _myProfile?.avatarUrl,
      );

      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _myProfile = updated;
          _pendingAvatarFile = null;
        });
      }
      final appCtrl = JuzzioAppController.instance;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: JuzzioColors.ink,
          content: Text(
            appCtrl.trEn(
              'Profil fotoğrafınız, biyografiniz ve dil tercihleriniz güncellendi!',
              'Profile photo, bio, and language preferences updated!', 'Profilbild, Bio und Spracheinstellungen aktualisiert!',
            ),
          ),
        ),
      );
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _showCreateStorySheet() async {
    await _openCreatorStudio(JuzzioStudioMode.story);
  }

  /// İçerik Stüdyosu: gönderi ve hikâye tek tam ekran deneyimde (v0.5: Reels kaldırıldı).
  Future<void> _openCreatorStudio(JuzzioStudioMode mode) async {
    if (mode == JuzzioStudioMode.story && !JuzzioFeaturesService.instance.lastAppConfig.storiesEnabled) {
      _showSnack(
        JuzzioAppController.instance.trEn(
          'Hikâye paylaşımı şu an geçici olarak kapalı.',
          'Story sharing is temporarily disabled.',
          'Das Teilen von Storys ist vorübergehend deaktiviert.',
        ),
        isError: true,
      );
      return;
    }
    final result = await JuzzioCreatorStudioPage.open(
      context,
      currentUser: _effectiveCurrentUserProfile,
      mode: mode,
    );
    if (!mounted || result == null) return;
    final appCtrl = JuzzioAppController.instance;
    if (result is List<JuzzioStory>) {
      if (result.isEmpty) return;
      setState(() {
        for (final created in result) {
          _activeStories.removeWhere((x) => x.id == created.id);
          _activeStories.insert(0, created);
        }
      });
      _showSnack(
        result.length > 1
            ? appCtrl.trEn('${result.length} hikâye paylaşıldı.', '${result.length} stories shared.',
                '${result.length} Storys geteilt.')
            : appCtrl.trEn('Hikâyen paylaşıldı.', 'Your story was shared.', 'Deine Story wurde geteilt.'),
      );
    } else if (result is JuzzioPost) {
      _showSnack(
        appCtrl.trEn('Gönderi paylaşıldı!', 'Post published!', 'Beitrag veröffentlicht!'),
      );
      await _refreshSocialFeedAndProfile();
    }
  }

  void _openStoryViewer(JuzzioStory story) {
    final myUid = SupabaseService.instance.currentUserId;
    // Aynı kişinin tüm aktif hikâyeleri sırayla oynatılır
    final sameUser = _visibleFriendStories24h.where((s) => s.userId == story.userId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final startIndex = sameUser.indexWhere((s) => s.id == story.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JuzzioStoryViewerModal(
          story: story,
          playlist: sameUser.isEmpty ? [story] : sameUser,
          initialIndex: startIndex < 0 ? 0 : startIndex,
          viewerProfile: _myProfile,
          onOpenChatAfterReply: (roomId) {
            if (roomId == null || story.userId == myUid) return;
            _openRoomById(roomId);
          },
        ),
      ),
    );
  }

  Future<void> _showFriendSearchAndRequestsSheet() async {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final s = JuzzioStrings(appCtrl.uiLang);
    final searchCtrl = TextEditingController();
    List<JuzzioUserProfile> results = await SupabaseService.instance.searchUsersByUsername('');

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final pendingReqs = _pendingIncomingRequests;
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.86,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: p.sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: p.glassBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.textMuted.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.t('friend_search_title'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: p.textPrimary, fontFamily: JuzzioConfig.fontRegularBold),
                    onChanged: (val) async {
                      final found = await SupabaseService.instance.searchUsersByUsername(val);
                      setModalState(() => results = found);
                    },
                    decoration: InputDecoration(
                      hintText: s.t('friend_search_hint'),
                      hintStyle: TextStyle(color: p.textMuted),
                      prefixIcon: Icon(Icons.alternate_email_rounded, color: p.textPrimary),
                      filled: true,
                      fillColor: p.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                    ),
                  ),
                  if (pendingReqs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      s.t('incoming_friend_reqs'),
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.badgeOrange,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...pendingReqs.map(
                      (req) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: p.cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: p.glassBorder),
                          boxShadow: p.softCardShadow,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: JuzzioColors.ink,
                              child: Text(
                                (req.requesterName.isNotEmpty ? req.requesterName.substring(0, 1).toUpperCase() : '?'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${req.requesterName} (@${req.requesterUsername})',
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    appCtrl.trEn('Size arkadaşlık isteği gönderdi.', 'Sent you a friend request.', 'Hat dir eine Freundschaftsanfrage gesendet.'),
                                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: JuzzioColors.ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              onPressed: () async {
                                await _respondFriendRequest(req, true);
                                setModalState(() {});
                              },
                              child: Text(s.t('accept_req'), style: const TextStyle(fontSize: 12)),
                            ),
                            IconButton(
                              onPressed: () async {
                                await _respondFriendRequest(req, false);
                                setModalState(() {});
                              },
                              icon: Icon(Icons.close_rounded, color: p.dangerRed),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final user = results[idx];
                        final isAccepted = _acceptedFriendIds.contains(user.id);
                        final myId = SupabaseService.instance.currentUserId;
                        final isPending = _locallySentRequestIds.contains(user.id) ||
                            _friendships.any(
                              (f) =>
                                  ((f.requesterId == myId && f.receiverId == user.id) ||
                                      (f.receiverId == myId && f.requesterId == user.id)) &&
                                  f.status == 'pending',
                            );
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: p.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: p.glassBorder),
                            boxShadow: p.softCardShadow,
                          ),
                          child: Row(
                            children: [
                              _buildUserAvatar(
                                avatarUrl: user.avatarUrl,
                                fallbackName: user.displayName,
                                radius: 22,
                                p: p,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName,
                                      style: TextStyle(
                                        fontFamily: JuzzioConfig.fontRegularBold,
                                        color: p.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '@${user.username} • ${user.preferredLang.toUpperCase()}',
                                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (isAccepted)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: JuzzioColors.ink,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _openDirectChatWithFriend(user);
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                                  label: Text(
                                    s.t('message_friend'),
                                    style: const TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else if (isPending)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: p.pillBg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    s.t('friend_req_sent'),
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: JuzzioColors.ink,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  ),
                                  onPressed: () async {
                                    await _sendFriendRequestTo(user);
                                    setModalState(() {});
                                  },
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                                  label: Text(
                                    s.t('send_friend_req'),
                                    style: const TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final s = JuzzioStrings(appCtrl.uiLang);

    return Scaffold(
      backgroundColor: p.headerDarkForest,
      bottomNavigationBar: _isInsideConversation ? null : _buildFloatingGlassBottomDock(p, s),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (appCtrl.otaUpdateAvailable) _buildOtaUpdateTopBanner(p, appCtrl),
            if (!_isInsideConversation && JuzzioFeaturesService.instance.lastAppConfig.announcementBanner.trim().isNotEmpty)
              _buildAnnouncementBanner(JuzzioFeaturesService.instance.lastAppConfig.announcementBanner.trim()),
            if (_incomingCallBannerVisible) _buildIncomingCallBanner(p, s),
            if (_headsUpFriendRequest != null) _buildIncomingFriendRequestBanner(p, s),
            if (_headsUpMessage != null && !_isInsideConversation)
              _buildQuickReplyMessageBanner(p, s),
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: appCtrl.reduceMotion ? 0 : 220),
                child: _isInsideConversation
                    ? _buildActiveConversationView(p, s, appCtrl)
                    : _selectedBottomTab == 0
                        ? (_selectedFilterIndex == 3
                            ? _buildFriendsAndGroupsTab(p, s, appCtrl)
                            : _buildChatsHomeTab(p, s, appCtrl))
                        : _selectedBottomTab == 1
                            ? _buildCallsTab(p, s)
                            : _selectedBottomTab == 2
                                ? _buildFriendsAndGroupsTab(p, s, appCtrl)
                                : _selectedBottomTab == 3
                                    ? _buildExploreTab(p, s, appCtrl)
                                    : _buildProfileSettingsTab(p, s, appCtrl),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Yönetici panelinden yayınlanan duyuru bandı (cam kapsül)
  Widget _buildAnnouncementBanner(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: JuzzioGlass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNewMessageScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JuzzioNewMessagePage(
          friends: _acceptedFriendProfiles,
          myProfile: _myProfile,
          fallbackMyName: widget.myDisplayName,
          onStartDirectChat: (friend) {
            _openDirectChatWithFriend(friend);
          },
          onStartGroupChat: (createdGrp) {
            _enterConversation(roomId: createdGrp.id, group: createdGrp);
          },
        ),
      ),
    );
  }

  JuzzioUserProfile get _effectiveCurrentUserProfile {
    if (_myProfile != null) return _myProfile!;
    final uid = SupabaseService.instance.currentUserId ?? 'local_user';
    final cleanName = widget.myDisplayName.trim().isEmpty ? JuzzioAppController.instance.trEn('Kullanıcı', 'User', 'Nutzer') : widget.myDisplayName.trim();
    return JuzzioUserProfile(
      id: uid,
      username: cleanName.toLowerCase().replaceAll(' ', '_'),
      displayName: cleanName,
      email: '',
      bio: _profileBioCtrl.text,
      preferredLang: widget.myLanguage,
    );
  }

  /// Küresel akışı yeniden yükletir (akış kendi verisini kendisi çeker).
  Future<void> _refreshSocialFeedAndProfile() async {
    if (mounted) setState(() => _globalFeedEpoch++);
  }

  Future<void> _openCreatePost() async {
    await _openCreatorStudio(JuzzioStudioMode.post);
  }

  Future<void> _openPlusCreateMenu() async {
    final choice = await showJuzzioCreateContentBottomSheet(context);
    if (!mounted || choice == null) return;
    if (choice == 'post') {
      await _openCreatePost();
    } else if (choice == 'story') {
      _showCreateStorySheet();
    }
  }

  Future<void> _openUnifiedSearch({String initialQuery = '', String initialTab = 'all'}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JuzzioUnifiedSearchPage(
          currentUser: _effectiveCurrentUserProfile,
          initialQuery: initialQuery,
          initialTab: initialTab,
          onOpenProfile: (uid) => _openUserProfilePage(uid),
          onOpenPost: (post) => _openPostDetail(post),
        ),
      ),
    );
    _refreshSocialFeedAndProfile();
  }

  Future<void> _openUserProfilePage(String targetUserId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JuzzioUserProfilePage(
          userId: targetUserId,
          currentUser: _effectiveCurrentUserProfile,
          onOpenSettings: _openFullSettingsSuite,
          onOpenEditProfile: () async {
            final updated = await Navigator.of(context).push<JuzzioUserProfile>(
              MaterialPageRoute(
                builder: (_) => JuzzioEditProfilePage(
                  initialProfile: _myProfile,
                  fallbackDisplayName: widget.myDisplayName,
                ),
              ),
            );
            if (updated != null && mounted) {
              setState(() => _myProfile = updated);
              _refreshSocialFeedAndProfile();
            }
          },
          onStartDirectChat: (targetUser) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            _openDirectChatWithFriend(targetUser);
          },
          onStartCall: (targetUser, isVideo) {
            Navigator.of(context).popUntil((r) => r.isFirst);
            _launchCall(
              enableVideo: isVideo,
              targetPartnerName: targetUser.displayName,
              targetPartnerId: targetUser.id,
              targetPartnerAvatar: targetUser.avatarUrl,
              targetPartnerLang: targetUser.preferredLang,
            );
          },
        ),
      ),
    );
    _refreshSocialFeedAndProfile();
  }

  Future<void> _openPostDetail(JuzzioPost post, {bool focusComments = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JuzzioPostDetailAndCommentsPage(
          postId: post.id,
          initialPost: post,
          currentUser: _effectiveCurrentUserProfile,
          focusCommentInput: focusComments,
          onOpenProfile: (uid) => _openUserProfilePage(uid),
        ),
      ),
    );
    _refreshSocialFeedAndProfile();
  }

  void _handlePushDeepLink(JuzzioPushEventPayload payload) {
    final et = payload.eventType;
    if (et == 'system') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JuzzioOtaUpdateSettingsPage()),
      );
      return;
    }
    if ((et == 'like' || et == 'comment' || et == 'reply' || et == 'save') && payload.targetId.isNotEmpty) {
      _openPostDetail(
        JuzzioPost(
          id: payload.targetId,
          authorId: payload.actorId,
          authorUsername: 'kullanici',
          authorDisplayName: payload.title,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        focusComments: et != 'like',
      );
      return;
    }
    if ((et.contains('follow') || et.contains('friend')) && payload.actorId.isNotEmpty) {
      _openUserProfilePage(payload.actorId);
      return;
    }
    if (et == 'missed_call') {
      setState(() {
        _isInsideConversation = false;
        _selectedBottomTab = 1;
      });
      return;
    }
    if (et == 'incoming_call') {
      // Çalan arama başlığı call_logs akışından otomatik gösterilir.
      return;
    }
    if ((et == 'message' || et == 'group_activity' || et == 'story_reply' || et == 'reaction') && payload.targetId.isNotEmpty) {
      _openRoomById(payload.targetId);
      return;
    }
    _openNotificationsScreen();
  }

  void _openNotificationsScreen() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => JuzzioNotificationsFeedPage(
              currentUser: _effectiveCurrentUserProfile,
            ),
          ),
        )
        .then((_) => _refreshSocialFeedAndProfile());
  }

  Widget _buildOtaUpdateTopBanner(JuzzioPalette p, JuzzioAppController appCtrl) {
    final downloading = appCtrl.isDownloadingOta;
    final downloaded = appCtrl.hasDownloadedOta;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111113).withValues(alpha: 0.62),
        border: Border.all(
          color: appCtrl.otaMandatory ? JuzzioColors.red500.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.28),
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: p.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appCtrl.trEn(
                        'Güncelleme geldi • v${appCtrl.otaRemoteVersion}',
                        'Update available • v${appCtrl.otaRemoteVersion}',
                        'Update verfügbar • v${appCtrl.otaRemoteVersion}',
                      ),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appCtrl.otaReason.trim().isNotEmpty
                          ? appCtrl.otaReason
                          : appCtrl.otaReleaseNotes.trim().isNotEmpty
                          ? appCtrl.otaReleaseNotes
                          : appCtrl.trEn(
                              'Uygulamayı silmeden, uygulama içinden güncelleyin.',
                              'Update inside the app without uninstalling.',
                              'Aktualisiere in der App, ohne zu deinstallieren.',
                            ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (appCtrl.otaMandatory)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: JuzzioColors.red500.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(appCtrl.trEn('Zorunlu güncelleme', 'Mandatory update', 'Pflichtupdate'),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        InkWell(
                          onTap: () => JuzzioReleaseNotesPage.open(context, focusVersion: appCtrl.otaRemoteVersion),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              appCtrl.trEn('Ayrıntılar: neler değişti? ›', 'Details: what changed? ›', 'Details: was ist neu? ›'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: appCtrl.otaDownloadProgress <= 0 ? null : appCtrl.otaDownloadProgress,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              appCtrl.trEn(
                'İndiriliyor... %${(appCtrl.otaDownloadProgress * 100).round()}',
                'Downloading... ${(appCtrl.otaDownloadProgress * 100).round()}%',
                'Wird geladen... ${(appCtrl.otaDownloadProgress * 100).round()} %',
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: () => JuzzioOtaSnoozeDialog.show(context),
                    child: Text(
                      appCtrl.trEn('Sonra', 'Later', 'Später'),
                      style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: JuzzioColors.brandIndigo,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    onPressed: () async {
                      final msg = downloaded
                          ? await appCtrl.installDownloadedOta()
                          : await appCtrl.startOtaDownloadAndInstall();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    },
                    icon: Icon(downloaded ? Icons.install_mobile_rounded : Icons.download_rounded, size: 18),
                    label: Text(
                      downloaded
                          ? appCtrl.trEn('Kur', 'Install', 'Installieren')
                          : appCtrl.trEn('Şimdi güncelle', 'Update now', 'Jetzt aktualisieren'),
                      style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIncomingCallBanner(JuzzioPalette p, JuzzioStrings s) {
    final appCtrl = JuzzioAppController.instance;
    final call = _incomingCall!;
    final incomingCallIsGroup = call.isGroup;
    final incomingCallIsVideo = call.isVideo;
    final incomingCallerName = call.callerName;
    final incomingGroupTitle = call.groupTitle.isNotEmpty ? call.groupTitle : appCtrl.trEn('Grup', 'Group', 'Gruppe');
    final incomingGroupMembers = _groupRooms.where((g) => g.id == call.roomId).firstOrNull?.groupMembers ?? const <String>[];
    final headline = incomingCallIsGroup
        ? appCtrl.trEn(
            '$incomingCallerName • $incomingGroupTitle (${incomingCallIsVideo ? "Görüntülü" : "Sesli"} Konferans)',
            '$incomingCallerName • $incomingGroupTitle (${incomingCallIsVideo ? "Video" : "Voice"} Conference)', '$incomingCallerName • $incomingGroupTitle (${incomingCallIsVideo ? "Video" : "Sprach"}konferenz)',
          )
        : appCtrl.trEn('$incomingCallerName seni arıyor...', '$incomingCallerName is calling you...', '$incomingCallerName ruft dich an...');
    final subline = incomingCallIsGroup
        ? appCtrl.trEn(
            'Katılımcılar: ${incomingGroupMembers.join(", ")}',
            'Participants: ${incomingGroupMembers.join(", ")}', 'Teilnehmer: ${incomingGroupMembers.join(", ")}',
          )
        : (incomingCallIsVideo
            ? appCtrl.trEn('Gelen HD Görüntülü Arama', 'Incoming HD Video Call', 'Eingehender HD-Videoanruf')
            : appCtrl.trEn('Gelen HD Sesli Arama', 'Incoming HD Voice Call', 'Eingehender HD-Sprachanruf'));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.glassBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: p.amberPrimary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  incomingCallIsGroup
                      ? Icons.groups_rounded
                      : (incomingCallIsVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded),
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subline,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JuzzioColors.red500,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _declineIncomingCall,
                    icon: const Icon(Icons.call_end_rounded, size: 18),
                    label: Text(
                      s.t('decline_call'),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.onlineGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _acceptIncomingCall,
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(
                      s.t('accept_call'),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingFriendRequestBanner(JuzzioPalette p, JuzzioStrings s) {
    final req = _headsUpFriendRequest!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.glassBorder, width: 1.4),
        boxShadow: p.softCardShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: p.amberPrimary,
            child: Text(
              (req.requesterName.isNotEmpty ? req.requesterName.substring(0, 1).toUpperCase() : '?'),
              style: const TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req.requesterName,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '@${req.requesterUsername}',
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.amberPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            onPressed: () => _respondFriendRequest(req, true),
            child: Text(
              s.t('accept_req'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _respondFriendRequest(req, false),
            child: Text(
              s.t('reject_req'),
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: p.dangerRed,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplyMessageBanner(JuzzioPalette p, JuzzioStrings s) {
    final msg = _headsUpMessage!;
    final senderName = msg.senderName.isNotEmpty ? msg.senderName : _resolveSenderName(msg.senderId);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.glassBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: p.amberPrimary,
                child: Text(
                  senderName.isNotEmpty ? senderName[0].toUpperCase() : 'J',
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      msg.translatedText.isNotEmpty ? msg.translatedText : msg.originalText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: p.textMuted, size: 20),
                onPressed: () => setState(() => _headsUpMessage = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _quickReplyCtrl,
                    onSubmitted: (_) => _sendQuickReplyFromBanner(),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      hintText: s.t('quick_reply_hint'),
                      hintStyle: TextStyle(color: p.textMuted, fontSize: 12.5),
                      filled: true,
                      fillColor: p.inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.amberPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: _sendQuickReplyFromBanner,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text(
                    s.t('send'),
                    style: const TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatsHomeTab(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    final stories24h = _visibleFriendStories24h;
    final myDisplay = _myProfile?.displayName ?? widget.myDisplayName;
    final myUid = SupabaseService.instance.currentUserId;
    final realFriends = _acceptedFriendProfiles;

    final filterLabels = [
      appCtrl.trEn('Tümü', 'All', 'Alle'),
      appCtrl.trEn('Kişiler', 'Contacts', 'Kontakte'),
      appCtrl.trEn('Gruplar', 'Groups', 'Gruppen'),
      appCtrl.trEn('Arkadaşlar', 'Friends', 'Freunde'),
    ];
    // v0.5.0: halka yalnızca aktif (24 saat) hikâyesi olan kişide görünür
    final myHasStory = myUid != null && stories24h.any((st) => st.userId == myUid);
    final storyOwners = <String, JuzzioStory>{};
    final storyIdsByOwner = <String, List<String>>{};
    for (final st in stories24h) {
      if (st.userId == myUid) continue;
      storyIdsByOwner.putIfAbsent(st.userId, () => []).add(st.id);
      // v0.8.0: görülmemiş hikâyeden başla
      final cur = storyOwners[st.userId];
      if (cur == null || (JuzzioStorySeen.instance.isSeen(cur.id) && !JuzzioStorySeen.instance.isSeen(st.id))) {
        storyOwners[st.userId] = st;
      }
    }
    final seenOwners = <String>{
      for (final e in storyIdsByOwner.entries)
        if (JuzzioStorySeen.instance.allSeen(e.value)) e.key,
    };
    // Bildirim çanı yalnızca sosyal etkileşimleri sayar (mesajlar sohbet rozetlerinde)
    final bellCount = _unreadNotificationsCount > _pendingIncomingRequests.length
        ? _unreadNotificationsCount
        : _pendingIncomingRequests.length;

    return Container(
      decoration: JuzzioGlassTokens.backdrop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isMesajlarFilterMode = !_isMesajlarFilterMode),
                    child: Text(
                      _isMesajlarFilterMode ? appCtrl.trEn('Mesajlar', 'Messages', 'Nachrichten') : 'Juzzio',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioGlassTokens.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                ),
                JuzzioGlassIconButton(
                  icon: Icons.person_add_alt_1_rounded,
                  size: 40,
                  tooltip: appCtrl.trEn('Arkadaş ekle', 'Add friend', 'Freund hinzufügen'),
                  onTap: _showFriendSearchAndRequestsSheet,
                ),
                const SizedBox(width: 8),
                JuzzioGlassIconButton(
                  icon: Icons.notifications_none_rounded,
                  size: 40,
                  badgeCount: bellCount,
                  tooltip: appCtrl.trEn('Bildirimler', 'Notifications', 'Benachrichtigungen'),
                  onTap: _openNotificationsScreen,
                ),
                const SizedBox(width: 8),
                JuzzioGlassIconButton(
                  icon: Icons.edit_square,
                  size: 40,
                  tooltip: appCtrl.trEn('Yeni mesaj', 'New message', 'Neue Nachricht'),
                  onTap: _openNewMessageScreen,
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _selectedBottomTab = 4),
                  child: JuzzioGlassAvatar(imageUrl: _myProfile?.avatarUrl, name: myDisplay, radius: 20),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: JuzzioGlassTextField(
              hint: s.t('search_placeholder'),
              icon: Icons.search_rounded,
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildCircularStatusItem(
                  p: p,
                  label: appCtrl.trEn('Durumun', 'Your status', 'Dein Status'),
                  avatarUrl: _myProfile?.avatarUrl,
                  fallbackName: myDisplay,
                  hasStory: myHasStory,
                  showPlusBadge: true,
                  onTap: () {
                    final myStories = stories24h.where((st) => st.userId == myUid).toList();
                    if (myStories.isNotEmpty) {
                      _openStoryViewer(myStories.first);
                    } else {
                      _showCreateStorySheet();
                    }
                  },
                  onLongPress: _showCreateStorySheet,
                ),
                ...([...storyOwners.values]..sort((a, b) => (seenOwners.contains(a.userId) ? 1 : 0) - (seenOwners.contains(b.userId) ? 1 : 0))).map((st) {
                  JuzzioUserProfile? owner;
                  for (final f in _allProfiles) {
                    if (f.id == st.userId) owner = f;
                  }
                  return _buildCircularStatusItem(
                    p: p,
                    label: owner?.displayName ?? st.displayName,
                    avatarUrl: owner?.avatarUrl ?? st.userAvatar,
                    fallbackName: owner?.displayName ?? st.displayName,
                    hasStory: true,
                    storySeen: seenOwners.contains(st.userId),
                    showPlusBadge: false,
                    onTap: () => _openStoryViewer(st),
                  );
                }),
                ...realFriends.where((f) => !storyOwners.containsKey(f.id)).map(
                      (f) => _buildCircularStatusItem(
                        p: p,
                        label: f.displayName,
                        avatarUrl: f.avatarUrl,
                        fallbackName: f.displayName,
                        hasStory: false,
                        showPlusBadge: false,
                        onTap: () => _openDirectChatWithFriend(f),
                      ),
                    ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filterLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final selected = _selectedFilterIndex == idx;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilterIndex = idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      // v0.8.0: seçili çip düz beyaz blok değil, yoğun cam
                      color: selected ? JuzzioGlassTokens.surfaceStrong : JuzzioGlassTokens.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: selected ? JuzzioGlassTokens.borderStrong : JuzzioGlassTokens.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filterLabels[idx],
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: selected ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: Container(
              width: double.infinity,
              // v0.7.0: "çekmece" görünümü kaldırıldı — liste zeminle bütünleşik, kenar/radius yok
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Expanded(
                    child: !_conversationsLoaded
                        ? Center(child: CircularProgressIndicator(color: p.amberPrimary))
                        : Builder(
                            builder: (context) {
                              final showPeople = _selectedFilterIndex == 0 || _selectedFilterIndex == 1;
                              final showGroups = _selectedFilterIndex == 0 || _selectedFilterIndex == 2;
                              final convs = _conversations
                                  .where((c) => c.isGroup ? showGroups : showPeople)
                                  .where((c) => !_deletedConversationIds.contains(c.roomId))
                                  .toList();
                              final dmPartnerIds = _conversations
                                  .where((c) => !c.isGroup && c.lastMessageAt != null)
                                  .map((c) => c.partnerId)
                                  .toSet();
                              final friendsWithoutChat = showPeople
                                  ? realFriends.where((f) => !dmPartnerIds.contains(f.id)).toList()
                                  : <JuzzioUserProfile>[];
                              final requestConvs = convs.where((c) => c.isMessageRequest).toList();
                              final visibleConvs = convs
                                  .where((c) => !c.isMessageRequest && (c.isGroup || c.lastMessageAt != null))
                                  .toList();

                              return ListView(
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                                children: [
                                  if (requestConvs.isNotEmpty) _buildMessageRequestsTile(p, appCtrl, requestConvs),
                                  ...visibleConvs.map(
                                    (c) => _buildConversationListCard(
                                      convKey: c.roomId,
                                      roomIdForDelete: c.roomId,
                                      p: p,
                                      title: c.title,
                                      avatarUrl: c.isGroup ? c.avatarUrl : c.partnerAvatarUrl,
                                      subtitle: _conversationSubtitle(c, appCtrl),
                                      timeText: c.lastMessageAt != null ? _formatRelativeMinutes(c.lastMessageAt!) : '',
                                      unreadCount: c.unreadCount.clamp(0, 99),
                                      isPinned: c.isPinned,
                                      isOnline: c.isGroup ? c.isCallActive : c.partnerIsOnline,
                                      isGroup2x2: c.isGroup,
                                      groupMemberNames: c.memberNames,
                                      isMutedRemote: c.isMuted,
                                      isVerified: !c.isGroup && c.partnerIsVerified,
                                      onVoiceCallTap: () => c.isGroup
                                          ? _launchGroupConferenceCall(group: c.toGroupRoom(), isVideo: false)
                                          : _launchCall(
                                              enableVideo: false,
                                              targetPartnerName: c.title,
                                              targetPartnerId: c.partnerId,
                                              targetPartnerAvatar: c.partnerAvatarUrl,
                                              targetPartnerLang: c.partnerLang,
                                            ),
                                      onVideoCallTap: () => c.isGroup
                                          ? _launchGroupConferenceCall(group: c.toGroupRoom(), isVideo: true)
                                          : _launchCall(
                                              enableVideo: true,
                                              targetPartnerName: c.title,
                                              targetPartnerId: c.partnerId,
                                              targetPartnerAvatar: c.partnerAvatarUrl,
                                              targetPartnerLang: c.partnerLang,
                                            ),
                                      onTap: () => _openConversation(c),
                                    ),
                                  ),
                                  if (friendsWithoutChat.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                                      child: Text(
                                        appCtrl.trEn('Arkadaşların', 'Your friends', 'Deine Freunde'),
                                        style: TextStyle(
                                          fontFamily: JuzzioConfig.fontRegularBold,
                                          color: p.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    ...friendsWithoutChat.map(
                                      (f) => _buildConversationListCard(
                                        convKey: 'friend_${f.id}',
                                        roomIdForDelete: null,
                                        p: p,
                                        title: f.displayName,
                                        avatarUrl: f.avatarUrl,
                                        subtitle: appCtrl.trEn('Sohbet başlatmak için dokun', 'Tap to start chatting', 'Tippe, um zu chatten'),
                                        timeText: f.formattedPresence(isTr: s.isTr),
                                        unreadCount: 0,
                                        isPinned: false,
                                        isOnline: f.isEffectivelyOnline,
                                        isGroup2x2: false,
                                        groupMemberNames: const [],
                                        onVoiceCallTap: () => _launchCall(
                                          enableVideo: false,
                                          targetPartnerName: f.displayName,
                                          targetPartnerId: f.id,
                                          targetPartnerAvatar: f.avatarUrl,
                                          targetPartnerLang: f.preferredLang,
                                        ),
                                        onVideoCallTap: () => _launchCall(
                                          enableVideo: true,
                                          targetPartnerName: f.displayName,
                                          targetPartnerId: f.id,
                                          targetPartnerAvatar: f.avatarUrl,
                                          targetPartnerLang: f.preferredLang,
                                        ),
                                        onTap: () => _openDirectChatWithFriend(f),
                                      ),
                                    ),
                                  ],
                                  if (visibleConvs.isEmpty && friendsWithoutChat.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                                      child: Column(
                                        children: [
                                          Icon(Icons.forum_outlined, color: p.textMuted, size: 46),
                                          const SizedBox(height: 10),
                                          Text(
                                            appCtrl.trEn(
                                              'Henüz sohbetin yok. Arkadaş ekle, istek kabul edilince buradan özel olarak yazışabilirsin.',
                                              'No chats yet. Add friends; once they accept you can chat privately here.', 'Noch keine Chats. Füge Freunde hinzu; sobald sie annehmen, könnt ihr hier privat chatten.',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: p.textSecondary, fontSize: 13.5),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            onPressed: _showFriendSearchAndRequestsSheet,
                                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                            label: Text(s.t('send_friend_req')),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: JuzzioGlassButton(
                                            label: appCtrl.trEn('Yeni Mesaj', 'New Message', 'Neue Nachricht'),
                                            icon: Icons.edit_square,
                                            primary: false,
                                            expand: true,
                                            height: 48,
                                            onTap: _openNewMessageScreen,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: JuzzioGlassButton(
                                            label: appCtrl.trEn('Yeni Grup', 'New Group', 'Neue Gruppe'),
                                            icon: Icons.group_add_rounded,
                                            expand: true,
                                            height: 48,
                                            onTap: () => _showCreateGroupModal(p, s, isChannel: false),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// v0.5.0: Keşfet yerine otomatik çevirili Küresel akış (X / Reddit tarzı)
  Widget _buildExploreTab(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    if (!JuzzioFeaturesService.instance.lastAppConfig.globalFeedEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: JuzzioGlass(
            radius: 24,
            padding: const EdgeInsets.all(22),
            child: Text(
              appCtrl.trEn('Küresel akış şu an bakımda. Kısa süre sonra yeniden açılacak.',
                  'The global feed is under maintenance and will be back shortly.',
                  'Der globale Feed wird gewartet und ist bald wieder verfügbar.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.4),
            ),
          ),
        ),
      );
    }
    return JuzzioGlobalFeedView(
      key: ValueKey('juzzio_global_feed_$_globalFeedEpoch'),
      currentUser: _effectiveCurrentUserProfile,
      onOpenProfile: _openUserProfilePage,
      onOpenPost: (post, {bool focusComments = false}) => _openPostDetail(post, focusComments: focusComments),
      onOpenSearch: () => _openUnifiedSearch(),
      onCreateMedia: () => _openCreatePost(),
      onAddFriend: _showFriendSearchAndRequestsSheet,
    );
  }

  Widget _buildCircularStatusItem({
    required JuzzioPalette p,
    required String label,
    required String? avatarUrl,
    required String fallbackName,
    required bool hasStory,
    required bool showPlusBadge,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool storySeen = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Center(
                    child: JuzzioGlassAvatar(
                      imageUrl: avatarUrl,
                      name: fallbackName,
                      radius: hasStory ? 25 : 28,
                      // v0.8.1 şartname §12.6: yeni hikâye cyan-mor halka, izlenen soluk halka
                      ringGradient: hasStory ? (storySeen ? kJuzzioStorySeenRing : kJuzzioStoryRing) : null,
                    ),
                  ),
                ),
                if (showPlusBadge)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _showCreateStorySheet,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: JuzzioGlassTokens.accentFill,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.isDark ? JuzzioColors.obsidian : Colors.white, width: 2),
                        ),
                        child: Icon(Icons.add_rounded, color: JuzzioGlassTokens.onAccent, size: 15),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: hasStory ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary,
                fontSize: 12,
                fontWeight: hasStory ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationListCard({
    String convKey = 'default_conv',
    String? roomIdForDelete,
    required JuzzioPalette p,
    required String title,
    String? avatarUrl,
    required String subtitle,
    required String timeText,
    required int unreadCount,
    required bool isPinned,
    required bool isOnline,
    required bool isGroup2x2,
    required List<String> groupMemberNames,
    bool isMutedRemote = false,
    bool isVerified = false,
    VoidCallback? onVoiceCallTap,
    VoidCallback? onVideoCallTap,
    required VoidCallback onTap,
  }) {
    if (_searchQuery.trim().isNotEmpty &&
        !title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
        !subtitle.toLowerCase().contains(_searchQuery.toLowerCase())) {
      return const SizedBox.shrink();
    }

    final bool isSwipedLeft = _swipedConversationKey == convKey;
    final bool isMuted = isMutedRemote ||
        _mutedConversationIds.contains(convKey) ||
        (roomIdForDelete != null && _mutedConversationIds.contains(roomIdForDelete));

    return GestureDetector(
      onTap: () {
        if (isSwipedLeft) {
          setState(() => _swipedConversationKey = null);
        } else {
          onTap();
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.primaryDelta != null) {
          if (details.primaryDelta! < -6 && _swipedConversationKey != convKey) {
            setState(() => _swipedConversationKey = convKey);
          } else if (details.primaryDelta! > 6 && _swipedConversationKey == convKey) {
            setState(() => _swipedConversationKey = null);
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        // v0.7.0: tüm temalarda aynı cam kart dili — eşit radius, ince kristal kenar, eşit aralık
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSwipedLeft
              ? (p.isDark ? JuzzioColors.surface1E2430 : JuzzioColors.slate100)
              : p.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.glassBorder),
        ),
        child: Row(
          children: [
            if (!isSwipedLeft) ...[
              if (isGroup2x2)
                Stack(
                  children: [
                    _buildGroup2x2AvatarGrid(groupMemberNames, title),
                    if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: p.onlineGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.cardBg, width: 2.2),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Stack(
                  children: [
                    _buildUserAvatar(
                      avatarUrl: avatarUrl,
                      fallbackName: title,
                      radius: 27,
                      p: p,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: isOnline ? p.onlineGreen : JuzzioColors.slate400,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.cardBg, width: 2.2),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const JuzzioVerifiedTick(size: 15),
                      ],
                      if (isMuted) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.notifications_off_rounded, color: p.textMuted, size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isSwipedLeft) ...[
              Text(
                timeText,
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: p.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isMuted) {
                      _mutedConversationIds.remove(convKey);
                      if (roomIdForDelete != null) _mutedConversationIds.remove(roomIdForDelete);
                    } else {
                      _mutedConversationIds.add(convKey);
                      if (roomIdForDelete != null) _mutedConversationIds.add(roomIdForDelete);
                    }
                    _swipedConversationKey = null;
                  });
                  if (roomIdForDelete != null) {
                    SupabaseService.instance.setRoomPreferences(roomIdForDelete, muted: !isMuted);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: JuzzioColors.deepForest,
                      content: Text(
                        !isMuted
                            ? JuzzioAppController.instance.trEn(
                                '$title sohbet bildirimleri sessize alındı.',
                                '$title notifications muted.', 'Benachrichtigungen für $title stummgeschaltet.',
                              )
                            : JuzzioAppController.instance.trEn(
                                '$title sohbet bildirimleri yeniden açıldı.',
                                '$title notifications unmuted.', 'Benachrichtigungen für $title wieder aktiviert.',
                              ),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: JuzzioColors.deepForest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMuted ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  setState(() {
                    _deletedConversationIds.add(convKey);
                    _swipedConversationKey = null;
                  });
                  if (roomIdForDelete != null) {
                    await SupabaseService.instance.deleteRoomMessages(roomIdForDelete);
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: JuzzioColors.red500,
                      content: Text(
                        JuzzioAppController.instance.trEn(
                          '$title sohbeti yalnızca sizin için silindi.',
                          '$title conversation deleted for you.', 'Unterhaltung $title wurde für dich gelöscht.',
                        ),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: JuzzioColors.red500,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeText,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (unreadCount > 0)
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _isMesajlarFilterMode ? p.badgeBlue : p.badgeOrange,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 22),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup2x2AvatarGrid(List<String> members, String fallbackTitle) {
    final labels = members.isNotEmpty
        ? members
        : [fallbackTitle, 'J', 'U', 'Z'];
    const colors = [
      JuzzioColors.blue600,
      JuzzioColors.gray600,
      JuzzioColors.sky500,
      JuzzioColors.emerald500,
    ];

    return SizedBox(
      width: 54,
      height: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniGridCircle(labels[0], colors[0]),
              _miniGridCircle(labels.length > 1 ? labels[1] : '2', colors[1]),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniGridCircle(labels.length > 2 ? labels[2] : '3', colors[2]),
              _miniGridCircle(labels.length > 3 ? labels[3] : '+', colors[3]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniGridCircle(String name, Color bg) {
    final ch = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'G';
    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        ch,
        style: const TextStyle(
          fontFamily: JuzzioConfig.fontRegularBold,
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActiveConversationView(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioAppController appCtrl,
  ) {
    final partnerProfile = _activeFriendPartner;
    final activeGroup = _activeGroupRoom;
    final partnerName = activeGroup != null
        ? activeGroup.title
        : (partnerProfile?.displayName ?? appCtrl.trEn('Sohbet', 'Chat', 'Chat'));
    final myUid = SupabaseService.instance.currentUserId;
    final targetStreamRoomId = _activeConversationRoomId;
    _ensurePresenceWatch(activeGroup == null ? partnerProfile?.id : null);
    final showEgg = activeGroup == null &&
        partnerProfile != null &&
        JuzzioFeaturesService.instance.lastAppConfig.chickGameEnabled;

    return Stack(
      children: [
        Positioned.fill(child: _buildConversationBody(p, s, appCtrl, partnerProfile, activeGroup, partnerName, myUid, targetStreamRoomId)),
        if (showEgg) _buildChickEgg(partnerProfile),
      ],
    );
  }

  /// Sohbet penceresinde sürüklenebilir çatlak yumurta: dokununca bu arkadaşla Civciv oyunu.
  Widget _buildChickEgg(JuzzioUserProfile partner) {
    final size = MediaQuery.of(context).size;
    final pos = _eggOffset ?? Offset(size.width - 70, 92);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            final next = (_eggOffset ?? pos) + d.delta;
            _eggOffset = Offset(
              next.dx.clamp(6.0, size.width - 62.0),
              next.dy.clamp(60.0, size.height - 220.0),
            );
          });
        },
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => JuzzioChickGameScreen(
                friends: _acceptedFriendProfiles,
                myDisplayName: _myProfile?.displayName ?? widget.myDisplayName,
                inviteFriend: partner,
              ),
            ),
          );
        },
        child: Tooltip(
          message: JuzzioAppController.instance.t('chick_invite_friend'),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [JuzzioColors.amber100, JuzzioColors.amber500]),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))],
            ),
            alignment: Alignment.center,
            child: const Text('🐣', style: TextStyle(fontSize: 27)),
          ),
        ),
      ),
    );
  }

  /// v0.7.0: sohbet başlığına dokunma
  Future<void> _onChatHeaderTap(JuzzioUserProfile? partner, JuzzioGroupRoom? group, String partnerName, {required bool avatar}) async {
    final roomId = _activeConversationRoomId;
    if (group != null) {
      if (roomId == null) return;
      final conv = _activeConversationData;
      await showJuzzioGroupManagementSheet(
        context,
        roomId: roomId,
        groupTitle: conv?.title ?? group.title,
        groupType: conv?.groupType ?? 'general',
        groupPurpose: conv?.groupPurpose ?? '',
        onChanged: () => SupabaseService.instance.fetchMyConversations().then((list) {
          if (mounted) setState(() => _conversations = list);
        }),
      );
      return;
    }
    final partnerId = partner?.id ?? _activeConversationData?.partnerId;
    if (partnerId == null || partnerId.isEmpty) return;
    if (avatar || roomId == null) {
      await _openUserProfilePage(partnerId);
      return;
    }
    final conv = _activeConversationData;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JuzzioContactSettingsPage(
        roomId: roomId,
        partnerId: partnerId,
        partnerName: partnerName,
        partnerUsername: partner?.username ?? '',
        partnerAvatarUrl: partner?.avatarUrl,
        initialTimer: conv?.disappearingTimer ?? 'off',
        initialMuted: (conv?.isMuted ?? false) || _mutedConversationIds.contains(roomId),
        onOpenProfile: () => _openUserProfilePage(partnerId),
        onCall: (video) => _launchCall(
          enableVideo: video,
          targetPartnerName: partnerName,
          targetPartnerId: partnerId,
          targetPartnerAvatar: partner?.avatarUrl,
          targetPartnerLang: partner?.preferredLang,
        ),
        onMutedChanged: (v) => setState(() => v ? _mutedConversationIds.add(roomId) : _mutedConversationIds.remove(roomId)),
        onBlock: () async {
          if (partner == null) return;
          final app = JuzzioAppController.instance;
          try {
            await JuzzioSocialService.instance.blockUser(targetUser: partner);
            if (mounted) setState(() => _isInsideConversation = false);
            _showSnack(app.trEn('${partner.displayName} engellendi.', '${partner.displayName} blocked.', '${partner.displayName} wurde blockiert.'));
          } catch (e) {
            _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
          }
        },
      ),
    ));
  }

  Widget _buildConversationBody(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioAppController appCtrl,
    JuzzioUserProfile? partnerProfile,
    JuzzioGroupRoom? activeGroup,
    String partnerName,
    String? myUid,
    String? targetStreamRoomId,
  ) {
    return Container(
      decoration: JuzzioGlassTokens.backdrop,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: _leaveConversation,
                  icon: Icon(Icons.arrow_back_rounded, color: p.textPrimary, size: 22),
                ),
                // v0.7.0: fotoğrafa dokun → profil sayfası; ada dokun → kişi bilgisi ve ayarları
                GestureDetector(
                  onTap: () => _onChatHeaderTap(partnerProfile, activeGroup, partnerName, avatar: true),
                  child: Stack(
                  children: [
                    if (activeGroup != null)
                      _buildGroup2x2AvatarGrid(activeGroup.groupMembers, activeGroup.title)
                    else
                      _buildUserAvatar(
                        avatarUrl: partnerProfile?.avatarUrl,
                        fallbackName: partnerName,
                        radius: 21,
                        p: p,
                      ),
                    if (activeGroup == null && (_activePresence?.isOnline ?? false))
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: p.onlineGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.headerDarkForest, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onChatHeaderTap(partnerProfile, activeGroup, partnerName, avatar: false),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              partnerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: p.textPrimary,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (activeGroup == null &&
                              ((partnerProfile?.isVerified ?? false) || (_activeConversationData?.partnerIsVerified ?? false))) ...[
                            const SizedBox(width: 4),
                            const JuzzioVerifiedTick(size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeGroup != null
                            ? appCtrl.trEn(
                                '${activeGroup.groupMembers.length} Üye${activeGroup.isCallActive ? " • 📞 Arama sürüyor" : ""}',
                                '${activeGroup.groupMembers.length} Members${activeGroup.isCallActive ? " • 📞 Call in progress" : ""}', '${activeGroup.groupMembers.length} Mitglieder${activeGroup.isCallActive ? " • 📞 Anruf läuft" : ""}',
                              )
                            : _presenceLabel(appCtrl, partnerProfile),
                        // Son görülme bilgisi kelime kaybı olmadan gösterilir (gerekirse 2 satır)
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: (activeGroup == null && (_activePresence?.isOnline ?? false))
                              ? JuzzioColors.emerald400
                              : JuzzioGlassTokens.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    if (activeGroup != null) {
                      _launchGroupConferenceCall(group: activeGroup, isVideo: false);
                    } else {
                      _launchCall(
                        enableVideo: false,
                        targetPartnerName: partnerName,
                        targetPartnerId: partnerProfile?.id,
                        targetPartnerAvatar: partnerProfile?.avatarUrl,
                        targetPartnerLang: partnerProfile?.preferredLang,
                      );
                    }
                  },
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.call_rounded, color: p.textPrimary, size: 22),
                ),
                IconButton(
                  onPressed: () {
                    if (activeGroup != null) {
                      _launchGroupConferenceCall(group: activeGroup, isVideo: true);
                    } else {
                      _launchCall(
                        enableVideo: true,
                        targetPartnerName: partnerName,
                        targetPartnerId: partnerProfile?.id,
                        targetPartnerAvatar: partnerProfile?.avatarUrl,
                        targetPartnerLang: partnerProfile?.preferredLang,
                      );
                    }
                  },
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.videocam_rounded, color: p.textPrimary, size: 24),
                ),
                _buildConversationMenu(p, appCtrl, activeGroup, partnerProfile),
              ],
            ),
          ),

          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: targetStreamRoomId == null
                        ? Center(child: CircularProgressIndicator(color: p.amberPrimary))
                        : StreamBuilder<List<JuzzioMessage>>(
                            stream: _messagesStreamFor(targetStreamRoomId),
                            builder: (context, snapshot) {
                              final messages = (snapshot.data ?? [])
                                  .where((m) => !_deletedMessageIds.contains(m.id))
                                  .toList();
                              if (messages.length != _lastRenderedMessageCount) {
                                final grew = messages.length > _lastRenderedMessageCount;
                                final firstLoad = _lastRenderedMessageCount == 0;
                                _lastRenderedMessageCount = messages.length;
                                if (grew) {
                                  _scrollMessagesToBottom(
                                    instant: firstLoad,
                                    force: messages.isNotEmpty && messages.last.senderId == myUid,
                                  );
                                  if (!_isAppInBackground) {
                                    SupabaseService.instance.markRoomRead(targetStreamRoomId);
                                  }
                                }
                              }
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    appCtrl.trEn('Mesajlar yüklenemedi.', 'Could not load messages.', 'Nachrichten konnten nicht geladen werden.'),
                                    style: TextStyle(color: p.textSecondary),
                                  ),
                                );
                              }
                              if (messages.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Text(
                                      appCtrl.trEn(
                                        'Henüz mesaj yok. Yazdığınız veya konuştuğunuz her şey otomatik çevrilir.',
                                        'No messages yet. Everything you type or speak translates automatically.', 'Noch keine Nachrichten. Alles, was du schreibst oder sagst, wird automatisch übersetzt.',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: p.textSecondary, fontSize: 13.5),
                                    ),
                                  ),
                                );
                              }
                              // v0.8.0: en alta atla düğmesi (yukarıda okurken tek dokunuşla son mesaja)
                              return Stack(
                                children: [
                                  NotificationListener<ScrollNotification>(
                                    onNotification: (n) {
                                      final far = n.metrics.maxScrollExtent - n.metrics.pixels > 500;
                                      if (far != _showJumpDown) setState(() => _showJumpDown = far);
                                      return false;
                                    },
                                    child: ListView.builder(
                                      controller: _scrollCtrl,
                                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                                      itemCount: messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = messages[index];
                                        final isMe = msg.senderId == myUid;
                                        return _buildMessageBubble(p, s, msg, isMe, appCtrl.subtitleLang);
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    right: 14,
                                    bottom: 12,
                                    child: AnimatedScale(
                                      scale: _showJumpDown ? 1 : 0,
                                      duration: const Duration(milliseconds: 180),
                                      child: JuzzioGlassIconButton(
                                        icon: Icons.keyboard_double_arrow_down_rounded,
                                        tooltip: appCtrl.trEn('Son mesaja git', 'Jump to latest', 'Zur neuesten'),
                                        onTap: () => _scrollMessagesToBottom(force: true),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),

                  if (_activeConversationData?.isMessageRequest ?? false)
                    _buildMessageRequestBar(p, appCtrl, partnerName)
                  else if (_activeConversationData?.isMutedByModerator ?? false)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom > 0 ? 22 : 16),
                      color: p.cardBg,
                      child: Row(
                        children: [
                          Icon(Icons.volume_off_rounded, color: p.dangerRed),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              appCtrl.t('group_you_are_muted'),
                              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                  if (_replyingTo != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                      color: p.cardBg,
                      child: Row(
                        children: [
                          Container(width: 3, height: 34, color: p.amberPrimary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  appCtrl.t('reply_to_name').replaceAll(
                                      '{name}',
                                      _replyingTo!.senderName.isNotEmpty
                                          ? _replyingTo!.senderName
                                          : _resolveSenderName(_replyingTo!.senderId)),
                                  style: TextStyle(color: p.amberPrimary, fontWeight: FontWeight.w800, fontSize: 12.5),
                                ),
                                Text(
                                  _replyingTo!.originalText.isNotEmpty ? _replyingTo!.originalText : appCtrl.t('reply_media'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: appCtrl.t('common_cancel'),
                            icon: Icon(Icons.close_rounded, color: p.textSecondary),
                            onPressed: () => setState(() => _replyingTo = null),
                          ),
                        ],
                      ),
                    ),
                  _buildComposer(p, s, appCtrl),
                  if (_showEmojiPanel)
                    JuzzioEmojiPicker(controller: _msgCtrl, isDark: appCtrl.isDark, height: 290),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtVoice(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _buildVoiceWave(JuzzioPalette p, {int bars = 26}) {
    final peaks = _livePeaks.length > bars ? _livePeaks.sublist(_livePeaks.length - bars) : _livePeaks;
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final v in peaks)
            Container(
              width: 3,
              height: 4 + 22 * v,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _voicePaused ? p.textMuted : p.dangerRed,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
        ],
      ),
    );
  }

  /// Mesaj yazma alanı: emoji paneli, kamera, WhatsApp tarzı ses kaydı (kilitleme dahil).
  Widget _buildComposer(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    final bottomPad = MediaQuery.of(context).padding.bottom > 0 && !_showEmojiPanel ? 16.0 : 10.0;

    // Kilitli kayıt çubuğu
    if (_isRecordingVoice && _voiceLocked) {
      return Container(
        padding: EdgeInsets.fromLTRB(10, 10, 10, bottomPad),
        decoration: BoxDecoration(color: p.cardBg, border: Border(top: BorderSide(color: p.glassBorder))),
        child: Row(
          children: [
            IconButton(
              tooltip: appCtrl.trEn('Kaydı sil', 'Delete recording', 'Aufnahme löschen'),
              onPressed: _cancelVoiceRecording,
              icon: Icon(Icons.delete_outline_rounded, color: p.dangerRed, size: 26),
            ),
            Icon(Icons.fiber_manual_record_rounded, size: 12, color: _voicePaused ? p.textMuted : p.dangerRed),
            const SizedBox(width: 6),
            Text(
              _fmtVoice(_voiceElapsed),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(child: ClipRect(child: _buildVoiceWave(p))),
            IconButton(
              tooltip: _voicePaused
                  ? appCtrl.trEn('Devam et', 'Resume', 'Fortsetzen')
                  : appCtrl.trEn('Duraklat', 'Pause', 'Pausieren'),
              onPressed: _toggleVoicePause,
              icon: Icon(_voicePaused ? Icons.mic_rounded : Icons.pause_circle_outline_rounded, color: p.textPrimary, size: 28),
            ),
            GestureDetector(
              onTap: _stopAndSendVoiceRecording,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [JuzzioColors.blue600, JuzzioColors.violet500]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 21),
              ),
            ),
          ],
        ),
      );
    }

    final recordingHeld = _isRecordingVoice && !_voiceLocked;
    // v0.8.1 şartname §12.2: sıvı cam yazma alanı (blur 14, yalnızca kendi alanında)
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (!JuzzioGlassTokens.reducedEffects)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurComposer, sigmaY: JuzzioGlassTokens.blurComposer),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        Container(
      padding: EdgeInsets.fromLTRB(8, 8, 10, bottomPad),
      decoration: BoxDecoration(color: p.cardBg, border: Border(top: BorderSide(color: p.glassBorder))),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  decoration: BoxDecoration(
                    color: p.inputBg,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: recordingHeld ? p.dangerRed : p.glassBorder),
                  ),
                  child: recordingHeld
                      ? SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              Icon(Icons.fiber_manual_record_rounded, color: p.dangerRed, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                _fmtVoice(_voiceElapsed),
                                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Opacity(
                                  opacity: (1 + _voiceDrag.dx / 110).clamp(0.25, 1.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.chevron_left_rounded, color: p.textMuted, size: 20),
                                      Flexible(
                                        child: Text(
                                          appCtrl.trEn('İptal için kaydır', 'Slide to cancel', 'Zum Abbrechen wischen'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: p.textMuted, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: _showEmojiPanel
                                  ? appCtrl.trEn('Klavye', 'Keyboard', 'Tastatur')
                                  : appCtrl.trEn('Emojiler', 'Emoji', 'Emojis'),
                              onPressed: () {
                                if (_showEmojiPanel) {
                                  setState(() => _showEmojiPanel = false);
                                  _composerFocus.requestFocus();
                                } else {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _showEmojiPanel = true);
                                  // v0.8.0: emoji paneli açılınca son mesaj görünür kalır
                                  Future.delayed(const Duration(milliseconds: 260), () => _scrollMessagesToBottom(force: true));
                                }
                              },
                              icon: Icon(
                                _showEmojiPanel ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                                color: p.textSecondary,
                                size: 24,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _msgCtrl,
                                focusNode: _composerFocus,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                style: TextStyle(color: p.textPrimary, fontFamily: JuzzioConfig.fontRegularBold, fontSize: 15),
                                onSubmitted: (_) => _sendText(),
                                decoration: InputDecoration(
                                  hintText: appCtrl.trEn('Mesaj yaz...', 'Type a message...', 'Nachricht schreiben...'),
                                  hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: appCtrl.trEn('Fotoğraf / Video Gönder', 'Send Photo / Video', 'Foto / Video senden'),
                              onPressed: _pickAndSendChatMedia,
                              icon: Icon(Icons.photo_camera_outlined, color: p.textSecondary, size: 24),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              if (_composerHasText)
                GestureDetector(
                  onTap: _sendText,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [JuzzioColors.blue600, JuzzioColors.violet500]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 21),
                  ),
                )
              else
                GestureDetector(
                  onLongPressStart: (_) => _startVoiceRecording(),
                  onLongPressMoveUpdate: (d) => _onMicDragUpdate(d.offsetFromOrigin),
                  onLongPressEnd: (_) => _onMicPressEnd(),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      content: Text(appCtrl.trEn(
                        'Kaydetmek için basılı tutun, kilitlemek için yukarı kaydırın.',
                        'Hold to record, slide up to lock.',
                        'Gedrückt halten zum Aufnehmen, nach oben wischen zum Sperren.',
                      )),
                    ),
                  ),
                  child: Transform.translate(
                    offset: recordingHeld ? Offset(_voiceDrag.dx.clamp(-110.0, 0.0), _voiceDrag.dy.clamp(-70.0, 0.0)) : Offset.zero,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: recordingHeld ? 64 : 48,
                      height: recordingHeld ? 64 : 48,
                      decoration: BoxDecoration(
                        gradient: recordingHeld
                            ? const LinearGradient(colors: [JuzzioColors.red500, JuzzioColors.redAlert])
                            : const LinearGradient(colors: [Color(0xFF636366), Color(0xFF3A3A3C)]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
            ],
          ),
          // Basılı tutarken: yukarıda kilit göstergesi
          if (recordingHeld)
            Positioned(
              right: 4,
              bottom: 74,
              child: Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: p.cardBgElevated,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: p.softCardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _voiceDrag.dy < -40 ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: p.textPrimary,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Icon(Icons.keyboard_arrow_up_rounded, color: p.textMuted, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
      ],
    );
  }

  /// Sohbet açıkken karşı tarafın çevrimiçi / son görülme bilgisini dakikada bir yeniler.
  void _ensurePresenceWatch(String? userId) {
    if (userId == _presenceUserId) return;
    _presenceUserId = userId;
    _presenceTimer?.cancel();
    _activePresence = null;
    if (userId == null) return;
    Future<void> tick() async {
      final res = await SupabaseService.instance.fetchUserPresence(userId);
      if (!mounted || _presenceUserId != userId) return;
      setState(() => _activePresence = res);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tick());
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) => tick());
  }

  String _presenceLabel(JuzzioAppController app, JuzzioUserProfile? partner) {
    final pres = _activePresence;
    if (pres == null) return partner == null ? '' : '@${partner.username}';
    if (pres.isOnline) return app.trEn('Çevrimiçi', 'Online', 'Online');
    final seen = pres.lastSeen?.toLocal();
    if (seen == null) return app.trEn('Son görülme gizli', 'Last seen hidden', 'Zuletzt online verborgen');
    final now = DateTime.now();
    final diff = now.difference(seen);
    final hh = seen.hour.toString().padLeft(2, '0');
    final mm = seen.minute.toString().padLeft(2, '0');
    if (diff.inMinutes < 1) return app.trEn('Son görülme az önce', 'Last seen just now', 'Zuletzt online gerade eben');
    if (diff.inMinutes < 60) {
      return app.trEn('Son görülme ${diff.inMinutes} dakika önce', 'Last seen ${diff.inMinutes} min ago', 'Zuletzt online vor ${diff.inMinutes} Min.');
    }
    if (diff.inHours < 6) {
      return app.trEn('Son görülme ${diff.inHours} saat önce', 'Last seen ${diff.inHours} h ago', 'Zuletzt online vor ${diff.inHours} Std.');
    }
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(seen.year, seen.month, seen.day);
    final days = today.difference(seenDay).inDays;
    if (days == 0) return app.trEn('Son görülme bugün $hh:$mm', 'Last seen today at $hh:$mm', 'Zuletzt online heute um $hh:$mm');
    if (days == 1) return app.trEn('Son görülme dün $hh:$mm', 'Last seen yesterday at $hh:$mm', 'Zuletzt online gestern um $hh:$mm');
    final dd = seen.day.toString().padLeft(2, '0');
    final mo = seen.month.toString().padLeft(2, '0');
    return app.trEn('Son görülme $dd.$mo.${seen.year} $hh:$mm', 'Last seen $dd/$mo/${seen.year} $hh:$mm',
        'Zuletzt online am $dd.$mo.${seen.year} um $hh:$mm');
  }

  /// "Mesaj istekleri": gizli hesaba arkadaş olmayan kişilerden gelen sohbetler.
  Widget _buildMessageRequestsTile(JuzzioPalette p, JuzzioAppController appCtrl, List<JuzzioConversation> requests) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Material(
        color: p.inputBg,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [JuzzioColors.blue600, JuzzioColors.violet500]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_chat_unread_rounded, color: Colors.white, size: 22),
          ),
          title: Text(
            appCtrl.trEn('Mesaj istekleri', 'Message requests', 'Nachrichtenanfragen'),
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800, color: p.textPrimary),
          ),
          subtitle: Text(
            appCtrl.trEn('${requests.length} kişi size yazmak istiyor', '${requests.length} people want to message you',
                '${requests.length} Personen möchten dir schreiben'),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: p.dangerRed, borderRadius: BorderRadius.circular(999)),
            child: Text('${requests.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          onTap: () => _openMessageRequestsSheet(p, appCtrl, requests),
        ),
      ),
    );
  }

  void _openMessageRequestsSheet(JuzzioPalette p, JuzzioAppController appCtrl, List<JuzzioConversation> requests) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Text(
                appCtrl.trEn('Mesaj istekleri', 'Message requests', 'Nachrichtenanfragen'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.textPrimary),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
                child: Text(
                  appCtrl.trEn(
                    'Hesabınız gizli olduğu için arkadaşınız olmayan kişilerin mesajları burada bekler. Kabul ederseniz sohbetlerinize taşınır.',
                    'Because your account is private, messages from people who are not your friends wait here. Accept to move them to your chats.',
                    'Da dein Konto privat ist, warten Nachrichten von Nicht-Freunden hier. Nimm sie an, um sie in deine Chats zu verschieben.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.35),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in requests)
                      ListTile(
                        leading: _buildUserAvatar(avatarUrl: c.partnerAvatarUrl, fallbackName: c.title, radius: 22, p: p),
                        title: Text(c.title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          _conversationSubtitle(c, appCtrl),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.textSecondary),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openConversation(c);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _respondToActiveRequest(bool accept) async {
    final roomId = _activeConversationRoomId;
    if (roomId == null) return;
    try {
      await JuzzioFeaturesService.instance.respondMessageRequest(roomId, accept);
      final list = await SupabaseService.instance.fetchMyConversations();
      if (!mounted) return;
      setState(() => _conversations = list);
      if (!accept) _leaveConversation();
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Widget _buildMessageRequestBar(JuzzioPalette p, JuzzioAppController appCtrl, String partnerName) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom > 0 ? 22 : 14),
      decoration: BoxDecoration(color: p.cardBg, border: Border(top: BorderSide(color: p.glassBorder))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            appCtrl.trEn('$partnerName size mesaj göndermek istiyor', '$partnerName wants to send you a message',
                '$partnerName möchte dir eine Nachricht senden'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            appCtrl.trEn('Kabul edene kadar mesajı okuduğunuzu bilmez.', 'They will not know you have read it until you accept.',
                'Die Person sieht erst nach deiner Annahme, dass du sie gelesen hast.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.dangerRed,
                    side: BorderSide(color: p.dangerRed.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _respondToActiveRequest(false),
                  child: Text(appCtrl.trEn('Sil', 'Delete', 'Löschen'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuzzioColors.blue600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _respondToActiveRequest(true),
                  child: Text(appCtrl.trEn('Kabul et', 'Accept', 'Annehmen'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConversationMenu(
    JuzzioPalette p,
    JuzzioAppController appCtrl,
    JuzzioGroupRoom? group,
    JuzzioUserProfile? partner,
  ) {
    final roomId = _activeConversationRoomId;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textPrimary),
      color: p.cardBg,
      onSelected: (value) async {
        if (roomId == null) return;
        switch (value) {
          case 'members':
            final conv = _activeConversationData;
            await showJuzzioGroupManagementSheet(
              context,
              roomId: roomId,
              groupTitle: conv?.title ?? group?.title ?? '',
              groupType: conv?.groupType ?? 'general',
              groupPurpose: conv?.groupPurpose ?? '',
              onChanged: () => SupabaseService.instance.fetchMyConversations().then((list) {
                if (mounted) setState(() => _conversations = list);
              }),
            );
            break;
          case 'add_members':
            if (group != null) await _showAddGroupMembersSheet(group);
            break;
          case 'leave_group':
            await SupabaseService.instance.leaveRoom(roomId);
            if (mounted) setState(() => _isInsideConversation = false);
            _showSnack(appCtrl.trEn('Gruptan ayrıldınız.', 'You left the group.', 'Du hast die Gruppe verlassen.'));
            break;
          case 'clear':
            await SupabaseService.instance.clearRoomHistoryForMe(roomId);
            _showSnack(appCtrl.trEn('Sohbet geçmişi sizin için temizlendi.', 'Chat history cleared for you.', 'Chatverlauf für dich gelöscht.'));
            break;
          case 'profile':
            if (partner != null) _openUserProfilePage(partner.id);
            break;
          case 'block':
            if (partner == null) break;
            try {
              await JuzzioSocialService.instance.blockUser(targetUser: partner);
              if (mounted) setState(() => _isInsideConversation = false);
              _showSnack(appCtrl.trEn('${partner.displayName} engellendi.', '${partner.displayName} blocked.', '${partner.displayName} wurde blockiert.'));
            } catch (e) {
              _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
            }
            break;
        }
      },
      itemBuilder: (_) => [
        if (group != null) ...[
          PopupMenuItem(value: 'members', child: Text(appCtrl.t('group_members_and_roles'))),
          if (_activeConversationData?.isGroupStaff ?? false)
            PopupMenuItem(value: 'add_members', child: Text(appCtrl.trEn('Üye ekle', 'Add members', 'Mitglieder hinzufügen'))),
          PopupMenuItem(value: 'clear', child: Text(appCtrl.trEn('Geçmişi temizle', 'Clear history', 'Verlauf löschen'))),
          PopupMenuItem(value: 'leave_group', child: Text(appCtrl.trEn('Gruptan ayrıl', 'Leave group', 'Gruppe verlassen'))),
        ] else ...[
          PopupMenuItem(value: 'profile', child: Text(appCtrl.trEn('Profili gör', 'View profile', 'Profil ansehen'))),
          PopupMenuItem(value: 'clear', child: Text(appCtrl.trEn('Geçmişi temizle', 'Clear history', 'Verlauf löschen'))),
          PopupMenuItem(value: 'block', child: Text(appCtrl.trEn('Engelle', 'Block', 'Blockieren'))),
        ],
      ],
    );
  }

  Future<void> _showAddGroupMembersSheet(JuzzioGroupRoom group) async {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final candidates = _acceptedFriendProfiles.where((f) => !group.groupMemberIds.contains(f.id)).toList();
    final selected = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Text(
                  appCtrl.trEn('${group.title} grubuna üye ekle', 'Add members to ${group.title}', 'Mitglieder zu ${group.title} hinzufügen'),
                  style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: candidates.isEmpty
                      ? Center(
                          child: Text(
                            appCtrl.trEn('Eklenebilecek arkadaş yok.', 'No friends left to add.', 'Keine weiteren Freunde zum Hinzufügen.'),
                            style: TextStyle(color: p.textSecondary),
                          ),
                        )
                      : ListView(
                          children: candidates
                              .map((f) => CheckboxListTile(
                                    value: selected.contains(f.id),
                                    onChanged: (v) => setSheet(() {
                                      if (v == true) {
                                        selected.add(f.id);
                                      } else {
                                        selected.remove(f.id);
                                      }
                                    }),
                                    title: Text(f.displayName, style: TextStyle(color: p.textPrimary)),
                                    subtitle: Text('@${f.username}', style: TextStyle(color: p.textSecondary)),
                                  ))
                              .toList(),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              Navigator.of(ctx).pop();
                              try {
                                await SupabaseService.instance.addGroupMembers(
                                  roomId: group.id,
                                  memberIds: selected.toList(),
                                );
                                _showSnack(appCtrl.trEn('Üyeler eklendi.', 'Members added.', 'Mitglieder hinzugefügt.'));
                              } catch (e) {
                                _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
                              }
                            },
                      child: Text(appCtrl.trEn('Ekle', 'Add', 'Hinzufügen')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStoryFromReplyMeta(Map<String, dynamic> meta) {
    final storyId = (meta['storyId'] ?? '').toString();
    for (final existing in _activeStories) {
      if (existing.id == storyId) {
        _openStoryViewer(existing);
        return;
      }
    }
    final reconstructed = JuzzioStory(
      id: storyId.isNotEmpty ? storyId : 'reconstructed_${DateTime.now().millisecondsSinceEpoch}',
      userId: (meta['storyUserId'] ?? '').toString(),
      username: (meta['storyUsername'] ?? 'user').toString(),
      displayName: (meta['storyDisplayName'] ?? meta['storyUsername'] ?? 'User').toString(),
      userAvatar: meta['storyUserAvatar']?.toString(),
      mediaUrl: meta['storyMediaUrl']?.toString(),
      mediaType: (meta['storyMediaType'] ?? 'image').toString(),
      videoDurationSec: (meta['storyVideoDurationSec'] as num?)?.toInt() ?? 10,
      captionOriginal: (meta['storyCaptionOriginal'] ?? '').toString(),
      captionTranslated: (meta['storyCaptionTranslated'] ?? '').toString(),
      overlayTextOriginal: (meta['storyOverlayOriginal'] ?? '').toString(),
      overlayTextTranslated: (meta['storyOverlayTranslated'] ?? '').toString(),
      sourceLang: 'tr',
      likes: const [],
      createdAt: DateTime.tryParse(meta['createdAt']?.toString() ?? '') ?? DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    _openStoryViewer(reconstructed);
  }

  Widget _buildEmbeddedStoryReplyCard(
    JuzzioPalette p,
    JuzzioMessage msg,
    bool isMe,
  ) {
    final meta = msg.storyReplyMeta!;
    final storyOwnerHandle = '@${(meta['storyUsername'] ?? 'user').toString().replaceAll('@', '')}';
    final replierHandle = '@${(meta['replierUsername'] ?? msg.senderName).toString().replaceAll('@', '')}';
    final mediaUrl = meta['storyMediaUrl']?.toString();
    final mediaType = (meta['storyMediaType'] ?? 'image').toString();
    final storyCaption = (meta['storyCaptionOriginal'] ?? '').toString();
    final isVideo = mediaType == 'video';
    final hasLocalFile = mediaUrl != null && !mediaUrl.startsWith('http') && File(mediaUrl).existsSync();

    return GestureDetector(
      onTap: () => _openStoryFromReplyMeta(meta),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.14) : JuzzioColors.slate200.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe ? Colors.white24 : JuzzioColors.slate300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVideo ? Icons.videocam_rounded : Icons.amp_stories_rounded,
                          color: isMe ? Colors.white : JuzzioColors.royalNavy,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            JuzzioAppController.instance.trEn('$storyOwnerHandle durumu • $replierHandle yanıtladı', '$replierHandle replied to $storyOwnerHandle\'s status', '$replierHandle hat auf den Status von $storyOwnerHandle geantwortet'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: isMe ? Colors.white : JuzzioColors.midnight,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: JuzzioColors.deepForest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      JuzzioAppController.instance.trEn('İzle ▶', 'Watch ▶', 'Ansehen ▶'),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (mediaUrl != null && mediaUrl.startsWith('http') && !isVideo)
                    Image.network(
                      mediaUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 110,
                        width: double.infinity,
                        color: JuzzioColors.deepForest,
                        alignment: Alignment.center,
                        child: Text(
                          storyCaption.isNotEmpty ? storyCaption : storyOwnerHandle,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else if (hasLocalFile && !isVideo)
                    Image.file(
                      File(mediaUrl),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [JuzzioColors.deepForest, JuzzioColors.royalNavy],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isVideo ? Icons.play_circle_fill_rounded : Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          if (storyCaption.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              storyCaption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// v0.7.0: Sohbet içinde arama kaydı (yapılan / cevaplanan / cevapsız)
  Widget _buildCallEventPill(JuzzioPalette p, JuzzioMessage msg, bool isMe) {
    final app = JuzzioAppController.instance;
    final call = msg.metadata['call'] is Map ? Map<String, dynamic>.from(msg.metadata['call'] as Map) : const <String, dynamic>{};
    final status = (call['status'] ?? '').toString();
    final isVideo = call['is_video'] == true;
    final sec = (call['duration_sec'] as num?)?.toInt() ?? 0;
    final answered = status == 'answered';
    final missedForMe = !answered && !isMe;
    String label;
    if (answered) {
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final ss = (sec % 60).toString().padLeft(2, '0');
      label = '${isVideo ? app.trEn('Görüntülü arama', 'Video call', 'Videoanruf') : app.trEn('Sesli arama', 'Voice call', 'Sprachanruf')} • $m:$ss';
    } else if (status == 'rejected') {
      label = app.trEn('Arama reddedildi', 'Call declined', 'Anruf abgelehnt');
    } else if (isMe) {
      label = app.trEn('Cevap verilmedi', 'No answer', 'Keine Antwort');
    } else {
      label = isVideo
          ? app.trEn('Cevapsız görüntülü arama', 'Missed video call', 'Verpasster Videoanruf')
          : app.trEn('Cevapsız sesli arama', 'Missed voice call', 'Verpasster Sprachanruf');
    }
    final t = msg.createdAt.toLocal();
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final color = missedForMe ? p.dangerRed : p.textPrimary;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: p.pillBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: missedForMe ? p.dangerRed.withValues(alpha: 0.5) : p.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              answered
                  ? (isVideo ? Icons.videocam_rounded : (isMe ? Icons.call_made_rounded : Icons.call_received_rounded))
                  : Icons.phone_missed_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$label · $hhmm',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioMessage msg,
    bool isMe,
    String mySubtitleLang,
  ) {
    if (_deletedMessageIds.contains(msg.id)) {
      return const SizedBox.shrink();
    }
    if (msg.messageType == 'call') return _buildCallEventPill(p, msg, isMe);
    final isVoice = msg.messageType == 'voice';
    final isPlaying = _playingMessageId == msg.id;
    final effectiveReactions = _localReactions[msg.id] ?? msg.reactions;
    final reactionCounts = <String, int>{};
    for (final e in effectiveReactions.values) {
      if (e.isNotEmpty) reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
    }
    final isBookmarked = JuzzioAppController.instance.isMessageStarred(msg.id);
    final isSwiped = _swipedMessageId == msg.id;
    final currentRoomKey = _activeConversationRoomId ?? 'no_room';
    final isRoomMuted = _mutedConversationIds.contains(currentRoomKey);
    final senderLabel = msg.senderName.isNotEmpty ? msg.senderName : _resolveSenderName(msg.senderId);
    _messageCache[msg.id] = msg;
    final quoted = msg.replyToId != null ? _messageCache[msg.replyToId!] : null;

    final bubbleRow = GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showMessageActionMenu(p, s, msg, isMe);
      },
      onDoubleTap: msg.isDeleted ? null : () => _quickReact(msg, JuzzioAppController.instance.doubleTapReaction, burst: true),
      // v0.7.0: sağa kaydır → yanıtla, artık yaylı/dirençli fizik animasyonuyla
      child: JuzzioSwipeToReply(
        enabled: !msg.isDeleted,
        iconColor: p.textPrimary,
        iconBackground: p.pillBg,
        onSwipeLeft: () {
          if (_swipedMessageId != msg.id) setState(() => _swipedMessageId = msg.id);
        },
        onSwipeRightSmall: () {
          if (_swipedMessageId == msg.id) setState(() => _swipedMessageId = null);
        },
        onReply: () {
          if (_swipedMessageId == msg.id) {
            setState(() => _swipedMessageId = null);
          } else if (_replyingTo?.id != msg.id) {
            setState(() => _replyingTo = msg);
          }
        },
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 16),
              child: _buildUserAvatar(
                avatarUrl: _resolveAvatar(msg.senderId),
                fallbackName: senderLabel,
                radius: 15,
                p: p,
              ),
            ),
          ],
          Flexible(
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!isMe && _activeGroupRoom != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 4),
                        child: Text(
                          senderLabel,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe ? p.outgoingBubble : p.incomingBubble,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(isMe ? 20 : 6),
                          bottomRight: Radius.circular(isMe ? 6 : 20),
                        ),
                        // v0.8.1 sıvı cam balon: kristal kenar
                        border: Border.all(
                          color: Colors.white.withValues(alpha: isMe ? 0.22 : (appCtrlIsDark() ? 0.14 : 0.7)),
                        ),
                      ),
                      // üstten vuran ışık (sıvı cam parlaması)
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(isMe ? 20 : 6),
                          bottomRight: Radius.circular(isMe ? 6 : 20),
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0x26FFFFFF), Color(0x05FFFFFF), Color(0x00FFFFFF)],
                          stops: [0.0, 0.45, 1.0],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.isDeleted)
                            Text(
                              JuzzioAppController.instance.trEn('🚫 Bu mesaj silindi', '🚫 This message was deleted', '🚫 Diese Nachricht wurde gelöscht'),
                              style: TextStyle(
                                color: isMe ? Colors.white70 : p.textMuted,
                                fontStyle: FontStyle.italic,
                                fontSize: 13.5,
                              ),
                            ),
                          if (!msg.isDeleted && msg.replyToId != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                              decoration: BoxDecoration(
                                color: (isMe ? Colors.white : p.textPrimary).withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border(left: BorderSide(color: isMe ? Colors.white70 : p.amberPrimary, width: 3)),
                              ),
                              child: Text(
                                quoted == null
                                    ? JuzzioAppController.instance.t('reply_original_unavailable')
                                    : '${quoted.senderName.isNotEmpty ? quoted.senderName : _resolveSenderName(quoted.senderId)}: '
                                        '${quoted.isDeleted ? JuzzioAppController.instance.t('reply_original_deleted') : (quoted.originalText.isNotEmpty ? quoted.originalText : JuzzioAppController.instance.t('reply_media'))}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: isMe ? Colors.white : p.textSecondary, fontSize: 12.5),
                              ),
                            ),
                          if (!msg.isDeleted && msg.storyReplyMeta != null)
                            _buildEmbeddedStoryReplyCard(p, msg, isMe),

                          if (!msg.isDeleted && msg.imageUrl != null && msg.imageUrl!.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => JuzzioMediaViewerPage.open(context, url: msg.imageUrl!, isVideo: false),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  msg.imageUrl!,
                                  height: 190,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, progress) => progress == null
                                      ? child
                                      : SizedBox(
                                          height: 190,
                                          child: Center(child: CircularProgressIndicator(color: p.amberPrimary)),
                                        ),
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (!msg.isDeleted && msg.videoUrl != null && msg.videoUrl!.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => JuzzioMediaViewerPage.open(context, url: msg.videoUrl!, isVideo: true),
                              child: Container(
                                height: 170,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: JuzzioColors.darkBackground,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (isVoice && !msg.isDeleted) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _togglePlayVoiceNote(msg),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isMe ? Colors.white24 : p.amberPrimary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 24,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: List.generate(
                                        msg.waveformPeaks.isNotEmpty
                                            ? min(18, msg.waveformPeaks.length)
                                            : 16,
                                        (i) {
                                          final peak = msg.waveformPeaks.isNotEmpty
                                              ? msg.waveformPeaks[i % msg.waveformPeaks.length]
                                              : 0.45;
                                          return Container(
                                            width: 3,
                                            height: (peak * 22).clamp(4.0, 22.0),
                                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                            decoration: BoxDecoration(
                                              color: isMe ? Colors.white : p.amberPrimary,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (!msg.isDeleted && msg.originalText.trim().isNotEmpty)
                          FutureBuilder<String>(
                            future: isMe
                                ? Future.value(msg.originalText)
                                : _resolveTranslatedMessageText(msg, mySubtitleLang),
                            initialData: isMe ? msg.originalText : msg.translatedText,
                            builder: (context, snap) {
                              final mainText = snap.data ?? msg.translatedText;
                              final secondaryText = isMe ? msg.translatedText : msg.originalText;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mainText,
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: isMe ? Colors.white : p.textPrimary,
                                      fontSize: 14.5 * JuzzioAppController.instance.messageFontScale,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                  if (secondaryText.trim().isNotEmpty && secondaryText != mainText) ...[
                                    const SizedBox(height: 5),
                                    Container(
                                      padding: const EdgeInsets.only(top: 5),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: isMe ? Colors.white24 : p.glassBorder,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '🌐 $secondaryText',
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : p.textSecondary,
                                          fontSize: 12.5,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isBookmarked)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.star_rounded, color: Colors.white, size: 13),
                                ),
                              // v0.7.0: uçtan uca şifreli mesaj göstergesi
                              if (msg.isEncrypted)
                                Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: Icon(Icons.lock_rounded, size: 11, color: isMe ? Colors.white70 : p.textMuted),
                                ),
                              Text(
                                _formatTime(msg.createdAt),
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : p.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                              if (isMe && _activeGroupRoom == null) ...[
                                const SizedBox(width: 4),
                                Builder(builder: (_) {
                                  final readAt = _conversationById(msg.roomId)?.partnerLastReadAt;
                                  final isRead = readAt != null && !msg.createdAt.isAfter(readAt);
                                  return Icon(
                                    isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                    color: isRead ? JuzzioColors.sky300 : Colors.white38,
                                    size: 14,
                                  );
                                }),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (reactionCounts.isNotEmpty)
                      Transform.translate(
                        offset: const Offset(0, -6),
                        child: GestureDetector(
                          onTap: () => _showMessageActionMenu(p, s, msg, isMe),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xF2242427),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: JuzzioGlassTokens.borderStrong),
                            ),
                            child: Wrap(
                              spacing: 6,
                              children: reactionCounts.entries
                                  .map((e) => Text(
                                        e.value > 1 ? '${e.key} ${e.value}' : e.key,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontFamilyFallback: kJuzzioEmojiFallback,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isSwiped) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (isRoomMuted) {
                    _mutedConversationIds.remove(currentRoomKey);
                  } else {
                    _mutedConversationIds.add(currentRoomKey);
                  }
                  _swipedMessageId = null;
                });
              },
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: const BoxDecoration(
                  color: JuzzioColors.deepForest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRoomMuted ? Icons.notifications_off_outlined : Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                final conv = _activeConversationData;
                final myUid = SupabaseService.instance.currentUserId;
                final moderate = conv != null && conv.isGroupStaff && msg.senderId != myUid;
                setState(() {
                  if (!moderate) _deletedMessageIds.add(msg.id);
                  _swipedMessageId = null;
                });
                if (moderate) {
                  // Yönetici/moderatör: gruptaki mesajı herkes için siler
                  try {
                    await JuzzioFeaturesService.instance.moderateDeleteMessage(msg.id);
                    _showSnack(JuzzioAppController.instance.t('group_message_deleted'));
                  } catch (e) {
                    _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
                  }
                  return;
                }
                // Kendi mesajım herkes için silinir; başkasının mesajı yalnızca bende gizlenir.
                await SupabaseService.instance.deleteMessageById(msg.id, senderId: msg.senderId);
              },
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: const BoxDecoration(
                  color: JuzzioColors.red500,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 19),
              ),
            ),
          ],
        ],
      ),
      ),
    );
    if (_burstMessageId != msg.id) return bubbleRow;
    return Stack(
      alignment: Alignment.center,
      children: [
        bubbleRow,
        IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('burst_${msg.id}_$_burstEmoji'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutBack,
            builder: (_, v, __) => Opacity(
              opacity: v < 0.75 ? 1 : (1 - (v - 0.75) * 4).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.4 + v * 1.0, child: Text(_burstEmoji, style: juzzioEmojiStyle(54))),
            ),
          ),
        ),
      ],
    );
  }

  /// Tepkiyi anında uygular (iyimser), sunucu sonucuyla eşitler.
  Future<void> _quickReact(JuzzioMessage msg, String emoji, {bool burst = false}) async {
    final myUid = SupabaseService.instance.currentUserId;
    if (myUid == null || msg.isDeleted) return;
    HapticFeedback.lightImpact();
    final current = Map<String, String>.from(_localReactions[msg.id] ?? msg.reactions);
    final removing = current[myUid] == emoji;
    if (removing) {
      current.remove(myUid);
    } else {
      current[myUid] = emoji;
    }
    setState(() {
      _localReactions[msg.id] = current;
      if (burst && !removing) {
        _burstMessageId = msg.id;
        _burstEmoji = emoji;
      }
    });
    if (burst && !removing) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _burstMessageId == msg.id) setState(() => _burstMessageId = null);
      });
    }
    final server = await SupabaseService.instance.toggleSingleMessageReaction(message: msg, emoji: emoji);
    if (!mounted) return;
    setState(() {
      if (server != null) {
        _localReactions[msg.id] = server;
      } else {
        _localReactions.remove(msg.id); // hata: sunucudaki hâle dön
      }
    });
    // Canlı akış güncel haritayı getirdikten sonra yerel kopya bırakılır
    // (başkalarının sonraki tepkileri böylece görünür).
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && identical(_localReactions[msg.id], server)) {
        setState(() => _localReactions.remove(msg.id));
      }
    });
  }

  /// Uzun basma menüsü: hızlı tepkiler (❤️‍🔥🥹🌸🫣🤩 +), yanıtla, kopyala, yıldızla
  void _showMessageActionMenu(JuzzioPalette p, JuzzioStrings s, JuzzioMessage msg, bool isMe) {
    final app = JuzzioAppController.instance;
    final myUid = SupabaseService.instance.currentUserId;
    final myCurrentEmoji = myUid != null ? (_localReactions[msg.id] ?? msg.reactions)[myUid] : null;
    final isStarred = app.isMessageStarred(msg.id);
    final text = (msg.originalText).trim();

    showJuzzioGlassSheet<void>(
      context: context,
      builder: (ctx) {
          Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) {
            return ListTile(
              leading: Icon(icon, color: color ?? JuzzioGlassTokens.textPrimary),
              title: Text(label,
                  style: TextStyle(color: color ?? JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.of(ctx).pop();
                onTap();
              },
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!msg.isDeleted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: JuzzioGlass(
                    radius: 999,
                    blur: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final emoji in _reactionEmojis)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _quickReact(msg, emoji, burst: true);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: myCurrentEmoji == emoji ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                              ),
                              child: Text(emoji, style: juzzioEmojiStyle(30)),
                            ),
                          ),
                        GestureDetector(
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final picked = await _pickAnyEmoji();
                            if (picked != null && picked.isNotEmpty) _quickReact(msg, picked, burst: true);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.10),
                              border: Border.all(color: JuzzioGlassTokens.border),
                            ),
                            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!msg.isDeleted)
                action(Icons.reply_rounded, app.trEn('Yanıtla', 'Reply', 'Antworten'), () {
                  setState(() => _replyingTo = msg);
                }),
              if (text.isNotEmpty && !msg.isDeleted)
                action(Icons.copy_rounded, app.trEn('Kopyala', 'Copy', 'Kopieren'), () {
                  Clipboard.setData(ClipboardData(text: text));
                  _showSnack(app.trEn('Mesaj kopyalandı', 'Message copied', 'Nachricht kopiert'));
                }),
              action(
                isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                isStarred
                    ? app.trEn('Yıldızı Kaldır', 'Remove Star', 'Stern entfernen')
                    : app.trEn('Mesajı Yıldızla', 'Star Message', 'Nachricht markieren'),
                () {
                  app.toggleStarredMessage(msg.id);
                  setState(() {});
                },
                color: isStarred ? const Color(0xFFFFD60A) : null,
              ),
              const SizedBox(height: 6),
            ],
          );
      },
    );
  }

  /// "+" ile tüm emojiler arasından seçim
  Future<String?> _pickAnyEmoji() async {
    final ctrl = TextEditingController();
    String? picked;
    await showJuzzioGlassSheet<void>(
      context: context,
      builder: (ctx) {
        void onChange() {
          final v = ctrl.text.trim();
          if (v.isNotEmpty && picked == null) {
            picked = v;
            Navigator.of(ctx).pop();
          }
        }

        ctrl.addListener(onChange);
        return JuzzioEmojiPicker(controller: ctrl, height: 340, isDark: true);
      },
    );
    ctrl.dispose();
    return picked;
  }

  Widget _buildCallsTab(JuzzioPalette p, JuzzioStrings s) {
    final appCtrl = JuzzioAppController.instance;
    final myUid = SupabaseService.instance.currentUserId;
    final friends = _acceptedFriendProfiles;
    final filteredLogs = _callLogs.where((log) {
      final out = log.callerId == myUid;
      switch (_callsFilter) {
        case 'missed':
          if (out || !log.isMissedLike) return false;
          break;
        case 'out':
          if (!out) return false;
          break;
        case 'in':
          if (out) return false;
          break;
        case 'video':
          if (!log.isVideo) return false;
          break;
      }
      if (_callsSearchQuery.trim().isEmpty) return true;
      final q = _callsSearchQuery.toLowerCase();
      return log.callerName.toLowerCase().contains(q) || log.receiverName.toLowerCase().contains(q);
    }).toList();

    return Container(
      color: p.headerDarkForest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      appCtrl.trEn('Arama', 'Calls', 'Anrufe'),
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      tooltip: appCtrl.trEn('Yeni Arama Başlat', 'Start New Call', 'Neuen Anruf starten'),
                      onPressed: () => _showSelectFriendToCallSheet(p, s),
                      icon: Icon(Icons.add_ic_call_rounded, color: p.textPrimary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: p.inputBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: p.glassBorder),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _callsSearchQuery = v),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: appCtrl.trEn(
                        'Kişi, grup veya mesaj ara...',
                        'Search contacts, groups, or messages...', 'Kontakte, Gruppen oder Nachrichten suchen...',
                      ),
                      hintStyle: TextStyle(color: p.textMuted, fontSize: 13.5),
                      prefixIcon: Icon(Icons.search_rounded, color: p.textMuted, size: 20),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 96),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        appCtrl.trEn('Son Aramalar', 'Recent Calls', 'Letzte Anrufe'),
                        style: TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: p.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final ids = _callLogs.map((l) => l.id).toList();
                          setState(() => _callLogs = []);
                          await SupabaseService.instance.deleteCallLogs(ids);
                        },
                        child: Text(
                          appCtrl.trEn('Temizle', 'Clear', 'Löschen'),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.amberGlow,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in <List<String>>[
                          ['all', appCtrl.trEn('Tümü', 'All', 'Alle')],
                          ['missed', appCtrl.trEn('Cevapsız', 'Missed', 'Verpasst')],
                          ['in', appCtrl.trEn('Gelen', 'Incoming', 'Eingehend')],
                          ['out', appCtrl.trEn('Giden', 'Outgoing', 'Ausgehend')],
                          ['video', appCtrl.trEn('Görüntülü', 'Video', 'Video')],
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f[1]),
                              selected: _callsFilter == f[0],
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                color: _callsFilter == f[0] ? p.coolButtonFg : p.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                              selectedColor: p.coolButtonBg,
                              backgroundColor: p.pillBg,
                              side: BorderSide(color: p.glassBorder),
                              shape: const StadiumBorder(),
                              onSelected: (_) => setState(() => _callsFilter = f[0]),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (filteredLogs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        appCtrl.trEn('Henüz arama geçmişin yok.', 'No calls yet.', 'Noch keine Anrufe.'),
                        style: TextStyle(color: p.textSecondary, fontSize: 13.5),
                      ),
                    )
                  else
                    ...filteredLogs.map((log) {
                      final isOutgoing = log.callerId == myUid;
                      final partnerId = isOutgoing ? log.receiverId : log.callerId;
                      final partnerName = log.isGroup && log.groupTitle.isNotEmpty
                          ? log.groupTitle
                          : (isOutgoing ? log.receiverName : log.callerName);
                      final partnerAvatar = isOutgoing ? log.receiverAvatar : log.callerAvatar;
                      final isMissed = !isOutgoing && log.isMissedLike;
                      final statusLabel = log.status == 'rejected'
                          ? appCtrl.trEn('Reddedildi', 'Declined', 'Abgelehnt')
                          : log.status == 'missed' || log.status == 'cancelled'
                              ? (isOutgoing ? appCtrl.trEn('Cevap yok', 'No answer', 'Keine Antwort') : appCtrl.trEn('Cevapsız', 'Missed', 'Verpasst'))
                              : log.status == 'busy_silent'
                                  ? appCtrl.trEn('Meşgul', 'Busy', 'Beschäftigt')
                                  : _formatCallDuration(log.durationSec);
                      final when = _formatRelativeMinutes(log.createdAt);
                      final group = log.isGroup ? _groupRooms.where((g) => g.id == log.roomId).firstOrNull : null;
                      return _buildCallHistoryRow(
                        p: p,
                        name: partnerName,
                        avatarUrl: partnerAvatar,
                        isGroup: log.isGroup,
                        groupMembers: group?.groupMembers ?? const [],
                        subText:
                            '${isOutgoing ? "↗" : "↙"} ${log.isVideo ? appCtrl.trEn("Görüntülü", "Video", "Video") : appCtrl.trEn("Sesli", "Voice", "Sprache")} • $statusLabel • $when',
                        isVideo: log.isVideo,
                        isMissed: isMissed,
                        isOnline: !log.isGroup &&
                            (friends.where((f) => f.id == partnerId).firstOrNull?.isEffectivelyOnline ?? false),
                        onTap: () => JuzzioCallDetailPage.open(context, log, onCallBack: () {
                          if (group != null) {
                            _launchGroupConferenceCall(group: group, isVideo: log.isVideo);
                          } else if (!log.isGroup && partnerId != null) {
                            _launchCall(
                              enableVideo: log.isVideo,
                              targetPartnerName: partnerName,
                              targetPartnerId: partnerId,
                              targetPartnerAvatar: partnerAvatar,
                            );
                          }
                        }),
                        onCallTap: () {
                          if (group != null) {
                            _launchGroupConferenceCall(group: group, isVideo: log.isVideo);
                          } else if (!log.isGroup && partnerId != null) {
                            _launchCall(
                              enableVideo: log.isVideo,
                              targetPartnerName: partnerName,
                              targetPartnerId: partnerId,
                              targetPartnerAvatar: partnerAvatar,
                            );
                          }
                        },
                      );
                    }),

                  const SizedBox(height: 22),
                  Text(
                    appCtrl.trEn('Arkadaşların', 'Your Friends', 'Deine Freunde'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (friends.isNotEmpty)
                    ...friends.asMap().entries.map((entry) {
                      final f = entry.value;
                      final presence = f.formattedPresence(isTr: s.isTr);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            _buildUserAvatar(
                              avatarUrl: f.avatarUrl,
                              fallbackName: f.displayName,
                              radius: 24,
                              p: p,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.displayName,
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textPrimary,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    presence,
                                    style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _launchCall(
                                enableVideo: false,
                                targetPartnerName: f.displayName,
                                targetPartnerId: f.id,
                                targetPartnerAvatar: f.avatarUrl,
                                targetPartnerLang: f.preferredLang,
                              ),
                              icon: Icon(Icons.call_outlined, color: p.textPrimary, size: 22),
                            ),
                          ],
                        ),
                      );
                    })
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.textPrimary,
                          side: BorderSide(color: p.glassBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: _showFriendSearchAndRequestsSheet,
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: Text(s.t('send_friend_req')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryRow({
    required JuzzioPalette p,
    required String name,
    required String? avatarUrl,
    required String subText,
    required bool isVideo,
    required bool isMissed,
    required VoidCallback onCallTap,
    bool isGroup = false,
    List<String> groupMembers = const [],
    bool isOnline = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Stack(
            children: [
              if (isGroup)
                _buildGroup2x2AvatarGrid(groupMembers, name)
              else
                _buildUserAvatar(
                  avatarUrl: avatarUrl,
                  fallbackName: name,
                  radius: 25,
                  p: p,
                ),
              // v0.7.0: yeşil nokta yalnızca kişi gerçekten çevrimiçiyse
              if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.onlineGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.cardBg, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: isMissed ? p.dangerRed : p.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      isVideo ? Icons.videocam_outlined : Icons.call_made_rounded,
                      size: 14,
                      color: isMissed ? p.dangerRed : p.onlineGreen,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        subText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCallTap,
            icon: Icon(
              isVideo ? Icons.videocam_outlined : Icons.call_outlined,
              color: p.textPrimary,
              size: 22,
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showSelectFriendToCallSheet(JuzzioPalette p, JuzzioStrings s) {
    final friends = _acceptedFriendProfiles;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
          decoration: BoxDecoration(
            color: p.sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: p.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('select_friend_to_call'),
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (_groupRooms.isNotEmpty) ...[
                ..._groupRooms.map(
                  (grp) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.glassBorder),
                    ),
                    child: Row(
                      children: [
                        _buildGroup2x2AvatarGrid(grp.groupMembers, grp.title),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                grp.title,
                                style: TextStyle(
                                  fontFamily: JuzzioConfig.fontRegularBold,
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                grp.groupMembers.join(', '),
                                style: TextStyle(color: p.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _launchGroupConferenceCall(group: grp, isVideo: false);
                          },
                          icon: Icon(Icons.call_rounded, color: p.textPrimary),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _launchGroupConferenceCall(group: grp, isVideo: true);
                          },
                          icon: Icon(Icons.videocam_rounded, color: p.amberGlow),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    s.t('no_friends_yet'),
                    style: TextStyle(color: p.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final f = friends[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: p.cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: p.glassBorder),
                        ),
                        child: Row(
                          children: [
                            _buildUserAvatar(
                              avatarUrl: f.avatarUrl,
                              fallbackName: f.displayName,
                              radius: 22,
                              p: p,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.displayName,
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '@${f.username} • ${f.preferredLang.toUpperCase()}',
                                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _launchCall(
                                  enableVideo: false,
                                  targetPartnerName: f.displayName,
                                  targetPartnerId: f.id,
                                  targetPartnerAvatar: f.avatarUrl,
                                  targetPartnerLang: f.preferredLang,
                                );
                              },
                              icon: Icon(Icons.call_rounded, color: p.textPrimary),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _launchCall(
                                  enableVideo: true,
                                  targetPartnerName: f.displayName,
                                  targetPartnerId: f.id,
                                  targetPartnerAvatar: f.avatarUrl,
                                  targetPartnerLang: f.preferredLang,
                                );
                              },
                              icon: Icon(Icons.videocam_rounded, color: p.amberGlow),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFriendsAndGroupsTab(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioAppController appCtrl,
  ) {
    final allFriends = _acceptedFriendProfiles;
    final pendingReqs = _pendingIncomingRequests;
    final filterLabels = [
      appCtrl.trEn('Tümü', 'All', 'Alle'),
      appCtrl.trEn('Çevrimiçi', 'Online', 'Online'),
      appCtrl.trEn('Önerilen', 'Suggested', 'Vorgeschlagen'),
    ];

    final showSuggestions = _friendsFilterIndex == 2;
    final filteredFriends = _friendsFilterIndex == 1
        ? allFriends.where((f) => f.isEffectivelyOnline).toList()
        : (showSuggestions ? <JuzzioUserProfile>[] : allFriends);
    final suggestions = showSuggestions ? _suggestedPeople : <JuzzioUserProfile>[];

    return Container(
      color: p.headerDarkForest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  appCtrl.trEn('Arkadaşlar', 'Friends', 'Freunde'),
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  tooltip: s.t('send_friend_req'),
                  onPressed: _showFriendSearchAndRequestsSheet,
                  icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: filterLabels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final selected = _friendsFilterIndex == idx;
                return GestureDetector(
                  onTap: () => setState(() => _friendsFilterIndex = idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filterLabels[idx],
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: selected ? JuzzioColors.deepForest : Colors.white70,
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 96),
                children: [
                  if (pendingReqs.isNotEmpty) ...[
                    Text(
                      s.t('incoming_friend_reqs'),
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.badgeOrange,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...pendingReqs.map(
                      (req) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.inputBg,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: p.glassBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: p.amberPrimary,
                              child: Text(
                                (req.requesterName.isNotEmpty ? req.requesterName[0].toUpperCase() : '?'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${req.requesterName} (@${req.requesterUsername})',
                                style: TextStyle(
                                  fontFamily: JuzzioConfig.fontRegularBold,
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: p.amberPrimary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              onPressed: () => _respondFriendRequest(req, true),
                              child: Text(s.t('accept_req')),
                            ),
                            IconButton(
                              onPressed: () => _respondFriendRequest(req, false),
                              icon: Icon(Icons.close_rounded, color: p.dangerRed),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (showSuggestions) ...[
                    if (suggestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          appCtrl.trEn('Şu an önerilecek yeni kişi yok.', 'No new people to suggest right now.', 'Gerade keine neuen Personenvorschläge.'),
                          style: TextStyle(color: p.textSecondary),
                        ),
                      ),
                    ...suggestions.map(
                      (u) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => _openUserProfilePage(u.id),
                              child: _buildUserAvatar(avatarUrl: u.avatarUrl, fallbackName: u.displayName, radius: 24, p: p),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.displayName,
                                    style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text('@${u.username}', style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: JuzzioColors.ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                              onPressed: () => _sendFriendRequestTo(u),
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                              label: Text(s.t('send_friend_req'), style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (filteredFriends.isEmpty && _groupRooms.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: p.inputBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: p.glassBorder),
                      ),
                      child: Column(
                        children: [
                          Text(
                            s.t('no_friends_yet'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          JuzzioCoolPillButton(
                            label: s.t('send_friend_req'),
                            icon: Icons.person_add_alt_1_rounded,
                            height: 48,
                            onTap: _showFriendSearchAndRequestsSheet,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    ...filteredFriends.map(
                      (f) => InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _openDirectChatWithFriend(f),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  _buildUserAvatar(
                                    avatarUrl: f.avatarUrl,
                                    fallbackName: f.displayName,
                                    radius: 25,
                                    p: p,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: f.isEffectivelyOnline ? p.onlineGreen : JuzzioColors.slate400,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: p.cardBg, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.displayName,
                                      style: TextStyle(
                                        fontFamily: JuzzioConfig.fontRegularBold,
                                        color: p.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      f.isEffectivelyOnline
                                          ? appCtrl.trEn('Çevrimiçi', 'Online', 'Online')
                                          : f.formattedPresence(isTr: s.isTr),
                                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                color: p.cardBg,
                                icon: Icon(Icons.more_horiz_rounded, color: p.textSecondary),
                                onSelected: (val) {
                                  if (val == 'msg') {
                                    _openDirectChatWithFriend(f);
                                  } else if (val == 'voice') {
                                    _launchCall(
                                      enableVideo: false,
                                      targetPartnerName: f.displayName,
                                      targetPartnerId: f.id,
                                      targetPartnerAvatar: f.avatarUrl,
                                      targetPartnerLang: f.preferredLang,
                                    );
                                  } else if (val == 'video') {
                                    _launchCall(
                                      enableVideo: true,
                                      targetPartnerName: f.displayName,
                                      targetPartnerId: f.id,
                                      targetPartnerAvatar: f.avatarUrl,
                                      targetPartnerLang: f.preferredLang,
                                    );
                                  } else if (val == 'profile') {
                                    _openUserProfilePage(f.id);
                                  } else if (val == 'remove') {
                                    _confirmRemoveFriend(f);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'msg',
                                    child: Text(s.t('message_friend')),
                                  ),
                                  PopupMenuItem(
                                    value: 'voice',
                                    child: Text(appCtrl.trEn('Sesli Ara', 'Voice Call', 'Sprachanruf')),
                                  ),
                                  PopupMenuItem(
                                    value: 'video',
                                    child: Text(appCtrl.trEn('Görüntülü Ara', 'Video Call', 'Videoanruf')),
                                  ),
                                  PopupMenuItem(
                                    value: 'profile',
                                    child: Text(appCtrl.trEn('Profili Gör', 'View Profile', 'Profil ansehen')),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text(appCtrl.trEn('Arkadaşlıktan Çıkar', 'Remove Friend', 'Freund entfernen')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ..._groupRooms.map(
                      (grp) => InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _enterConversation(roomId: grp.id, group: grp),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              _buildGroup2x2AvatarGrid(grp.groupMembers, grp.title),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      grp.title,
                                      style: TextStyle(
                                        fontFamily: JuzzioConfig.fontRegularBold,
                                        color: p.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      appCtrl.trEn('Grup', 'Group', 'Gruppe'),
                                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: appCtrl.trEn('Görüntülü konferans', 'Video conference', 'Videokonferenz'),
                                onPressed: () => _launchGroupConferenceCall(group: grp, isVideo: true),
                                icon: Icon(Icons.videocam_outlined, color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _respondFriendRequest(JuzzioFriendship req, bool accept) async {
    try {
      await SupabaseService.instance.respondToFriendRequest(friendshipId: req.id, accept: accept);
      if (!mounted) return;
      setState(() {
        if (_headsUpFriendRequest?.id == req.id) _headsUpFriendRequest = null;
        _friendships = _friendships
            .where((f) => accept || f.id != req.id)
            .map((f) => f.id == req.id && accept
                ? JuzzioFriendship(
                    id: f.id,
                    requesterId: f.requesterId,
                    requesterUsername: f.requesterUsername,
                    requesterName: f.requesterName,
                    requesterAvatar: f.requesterAvatar,
                    receiverId: f.receiverId,
                    receiverUsername: f.receiverUsername,
                    receiverName: f.receiverName,
                    receiverAvatar: f.receiverAvatar,
                    status: 'accepted',
                    createdAt: f.createdAt,
                  )
                : f)
            .toList();
      });
      if (accept) {
        _showSnack(JuzzioAppController.instance.trEn(
          '${req.requesterName} artık arkadaşın!',
          '${req.requesterName} is now your friend!', '${req.requesterName} ist jetzt dein Freund!',
        ));
      }
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  final Set<String> _locallySentRequestIds = {};

  Future<String?> _sendFriendRequestTo(JuzzioUserProfile user) async {
    final app = JuzzioAppController.instance;
    try {
      final status = await SupabaseService.instance.sendFriendRequest(
        myProfile: _effectiveCurrentUserProfile,
        targetUser: user,
      );
      if (!mounted) return status;
      setState(() => _locallySentRequestIds.add(user.id));
      _showSnack(status == 'accepted'
          ? app.trEn('${user.displayName} ile artık arkadaşsınız!', 'You and ${user.displayName} are now friends!', 'Du und ${user.displayName} seid jetzt Freunde!')
          : app.trEn('Arkadaşlık isteği gönderildi.', 'Friend request sent.', 'Freundschaftsanfrage gesendet.'));
      return status;
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
      return null;
    }
  }

  Future<void> _confirmRemoveFriend(JuzzioUserProfile friend) async {
    final app = JuzzioAppController.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.trEn('Arkadaşlıktan çıkar', 'Remove friend', 'Freund entfernen')),
        content: Text(app.trEn(
          '${friend.displayName} arkadaş listenden çıkarılsın mı?',
          'Remove ${friend.displayName} from your friends?', '${friend.displayName} aus deinen Freunden entfernen?',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.trEn('Çıkar', 'Remove', 'Entfernen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.removeFriend(friend.id);
      if (mounted) {
        final myUid = SupabaseService.instance.currentUserId ?? '';
        setState(() => _friendships.removeWhere((f) => f.otherUserId(myUid) == friend.id));
      }
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  /// Alt "Profil" sekmesi: Instagram tarzı profil (mavi tik, web sitesi, müzik, profil kartı).
  int _profileRefreshToken = 0;

  Future<JuzzioUserProfile?> _openEditProfilePage() async {
    final updated = await Navigator.of(context).push<JuzzioUserProfile>(
      MaterialPageRoute(
        builder: (_) => JuzzioEditProfilePage(
          initialProfile: _myProfile,
          fallbackDisplayName: widget.myDisplayName,
        ),
      ),
    );
    if (!mounted) return updated;
    final fresh = await SupabaseService.instance.fetchUserProfile(_effectiveCurrentUserProfile.id);
    if (!mounted) return updated ?? fresh;
    setState(() {
      if (fresh != null) {
        _myProfile = fresh;
      } else if (updated != null) {
        _myProfile = updated;
      }
      _profileRefreshToken++;
    });
    _refreshSocialFeedAndProfile();
    return updated ?? fresh;
  }

  Widget _buildProfileSettingsTab(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioAppController appCtrl,
  ) {
    final me = _effectiveCurrentUserProfile;
    return JuzzioProfileView(
      key: const ValueKey('juzzio_my_profile_tab'),
      userId: me.id,
      currentUser: me,
      asHomeTab: true,
      refreshToken: _profileRefreshToken,
      onCreate: _openPlusCreateMenu,
      onOpenNotifications: _openNotificationsScreen,
      onOpenSettings: _openFullSettingsSuite,
      onEditProfile: _openEditProfilePage,
      onChangeAvatar: () async {
        await _pickAndCropAvatarImage();
        if (mounted) setState(() => _profileRefreshToken++);
      },
      onStartChat: _openDirectChatWithFriend,
      onStartCall: (target, isVid) => _launchCall(
        enableVideo: isVid,
        targetPartnerName: target.displayName,
        targetPartnerId: target.id,
        targetPartnerAvatar: target.avatarUrl,
        targetPartnerLang: target.preferredLang,
      ),
    );
  }

  void _openFullSettingsSuite() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JuzzioSettingsMainPage(
          myProfile: _myProfile,
          fallbackDisplayName: widget.myDisplayName,
        ),
      ),
    );
  }

  void _showCreateGroupModal(JuzzioPalette p, JuzzioStrings s, {bool isChannel = false}) {
    final appCtrl = JuzzioAppController.instance;
    final titleCtrl = TextEditingController();
    String timer = appCtrl.defaultMessageTimer;
    // Grup türü: hazır seçenekler + "Özel" (kullanıcı kendi amacını yazar)
    String selectedTag = 'group_work';
    final purposeCtrl = TextEditingController();
    final friends = _acceptedFriendProfiles;
    final selectedFriendIds = <String>{};
    final selectedFriendNames = <String>{};
    bool isCreating = false;
    final myName = _myProfile?.displayName ?? widget.myDisplayName;

    // Nötr cam: avatar halkaları gümüş tonlarında
    const ringColors = [
      Color(0xFFF2F2F7),
      Color(0xFFD1D1D6),
      Color(0xFFAEAEB2),
      Color(0xFF8E8E93),
      Color(0xFFE5E5EA),
      Color(0xFFC7C7CC),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(ctx).size.height * 0.90,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: p.textPrimary,
                          size: 22,
                        ),
                      ),
                      Text(
                        isChannel
                            ? s.t('menu_new_channel')
                            : appCtrl.trEn('Yeni Grup Oluştur', 'Create Group', 'Gruppe erstellen'),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appCtrl.t('group_name_label'),
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // v0.7.0: modern cam grup adı alanı (simge, sayaç, net kenar)
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                            decoration: BoxDecoration(
                              color: p.inputBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: p.glassBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(isChannel ? Icons.campaign_rounded : Icons.groups_rounded, color: p.textSecondary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: titleCtrl,
                                    maxLines: 2,
                                    minLines: 1,
                                    maxLength: 60,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: isChannel
                                          ? appCtrl.trEn('Kanal Başlığı', 'Channel Title', 'Kanaltitel')
                                          : appCtrl.trEn('Grup adı', 'Group name', 'Gruppenname'),
                                      hintStyle: TextStyle(color: p.textMuted, fontSize: 19, fontWeight: FontWeight.w700),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      counterStyle: TextStyle(color: p.textMuted, fontSize: 11),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            appCtrl.t('group_type_label'),
                            style: TextStyle(color: p.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              for (final tag in kJuzzioGroupTypes)
                                GestureDetector(
                                  onTap: () => setModalState(() => selectedTag = tag),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selectedTag == tag
                                          ? p.activeNavIndigo.withOpacity(0.15)
                                          : p.inputBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      appCtrl.t('group_type_$tag'),
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (selectedTag == 'custom') ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: purposeCtrl,
                              maxLength: 60,
                              style: TextStyle(color: p.textPrimary, fontSize: 15),
                              decoration: InputDecoration(
                                labelText: appCtrl.t('group_custom_purpose'),
                                hintText: appCtrl.t('group_custom_purpose_hint'),
                                filled: true,
                                fillColor: p.inputBg,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 26),
                          Text(
                            appCtrl.trEn('Grup Yöneticisi', 'Group Admin', 'Gruppenadmin'),
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _buildUserAvatar(
                                avatarUrl: _myProfile?.avatarUrl,
                                fallbackName: myName,
                                radius: 26,
                                p: p,
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    myName,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    appCtrl.trEn('Grup Yöneticisi', 'Group Admin', 'Gruppenadmin'),
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          Text(
                            appCtrl.trEn('Davet Edilen Üyeler', 'Invited Members', 'Eingeladene Mitglieder'),
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              ...friends.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final f = entry.value;
                                final isSelected = selectedFriendIds.contains(f.id);
                                final bgCol = ringColors[idx % ringColors.length];
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      if (isSelected) {
                                        selectedFriendIds.remove(f.id);
                                        selectedFriendNames.remove(f.displayName);
                                      } else {
                                        selectedFriendIds.add(f.id);
                                        selectedFriendNames.add(f.displayName);
                                      }
                                    });
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 62,
                                            height: 62,
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: bgCol,
                                              shape: BoxShape.circle,
                                              border: isSelected
                                                  ? Border.all(
                                                      color: p.activeNavIndigo,
                                                      width: 2.2,
                                                    )
                                                  : null,
                                            ),
                                            child: _buildUserAvatar(
                                              avatarUrl: f.avatarUrl,
                                              fallbackName: f.displayName,
                                              radius: 28,
                                              p: p,
                                            ),
                                          ),
                                          Positioned(
                                            right: -1,
                                            bottom: -1,
                                            child: Container(
                                              width: 21,
                                              height: 21,
                                              decoration: BoxDecoration(
                                                color: p.cardBg,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isSelected ? Icons.check_circle_rounded : Icons.add_rounded,
                                                size: 16,
                                                color: isSelected ? p.activeNavIndigo : p.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        width: 64,
                                        child: Text(
                                          f.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isSelected ? p.textPrimary : p.textSecondary,
                                            fontSize: 11.5,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _showFriendSearchAndRequestsSheet();
                                },
                                child: Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: p.glassBorder,
                                      width: 1.4,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.add_rounded,
                                    color: p.textSecondary,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.activeNavIndigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(27),
                        ),
                      ),
                      onPressed: isCreating
                          ? null
                          : () async {
                              final rawTitle = titleCtrl.text.trim();
                              if (rawTitle.isEmpty) {
                                _showSnack(appCtrl.t('err_group_title'), isError: true);
                                return;
                              }
                              final purpose = purposeCtrl.text.trim();
                              if (selectedTag == 'custom' && purpose.isEmpty) {
                                _showSnack(appCtrl.t('err_group_purpose'), isError: true);
                                return;
                              }
                              if (!JuzzioContentFilter.isClean(rawTitle, requireLetters: true) ||
                                  !JuzzioContentFilter.isClean(purpose)) {
                                _showSnack(appCtrl.t('err_inappropriate'), isError: true);
                                return;
                              }
                              if (selectedFriendIds.isEmpty) {
                                _showSnack(
                                  appCtrl.trEn('En az bir arkadaş seçin.', 'Select at least one friend.', 'Wähle mindestens einen Freund aus.'),
                                  isError: true,
                                );
                                return;
                              }
                              setModalState(() => isCreating = true);
                              try {
                                final createdGrp = await SupabaseService.instance.createGroupOrChannelRoom(
                                  title: rawTitle,
                                  isChannel: isChannel,
                                  disappearingTimer: timer,
                                  members: [...selectedFriendNames, myName],
                                  memberIds: selectedFriendIds.toList(),
                                  groupType: selectedTag,
                                  groupPurpose: selectedTag == 'custom' ? purpose : '',
                                );
                                if (!ctx.mounted) return;
                                Navigator.of(ctx).pop();
                                if (createdGrp != null && mounted) {
                                  _enterConversation(roomId: createdGrp.id, group: createdGrp);
                                }
                              } catch (e) {
                                if (ctx.mounted) setModalState(() => isCreating = false);
                                _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
                              }
                            },
                      child: Text(
                        appCtrl.trEn('Grubu Oluştur', 'Create', 'Erstellen'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingGlassBottomDock(JuzzioPalette p, JuzzioStrings s) {
    final app = JuzzioAppController.instance;
    // v0.7.0: Küresel akış kaldırıldı. (ikon, aktif ikon, etiket, sekme indeksi)
    final items = [
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, app.trEn('Mesajlar', 'Chats', 'Chats'), 0),
      (Icons.call_outlined, Icons.call_rounded, app.trEn('Aramalar', 'Calls', 'Anrufe'), 1),
      (Icons.add_rounded, Icons.add_rounded, app.trEn('Paylaş', 'Share', 'Teilen'), 2),
      (Icons.person_outline_rounded, Icons.person_rounded, app.trEn('Profil', 'Profile', 'Profil'), 4),
    ];
    // Seçili: cyan (açık modda okunur electric blue), seçili değil: ikincil metin
    final fgActive = app.isDark ? JuzzioColors.cyan : JuzzioColors.blue;
    final fgMuted = app.isDark ? JuzzioColors.textSecondary : p.textSecondary;
    final unreadChats = _conversations.fold<int>(0, (sum, c) => sum + (c.isMuted ? 0 : c.unreadCount));
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // HyperOS / iOS 18 tarzı yüzen cam kapsül; mor parıltı ve renkli gölge yok
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset : 12),
      // v0.8.1 şartname §13: yüzen cam navigasyon — blur 18, radius 26, koyu yarı saydam yüzey
      child: JuzzioGlass(
        radius: JuzzioGlassTokens.radiusLarge,
        blurSigma: JuzzioGlassTokens.blurNavigation,
        color: app.isDark ? JuzzioColors.surface.withValues(alpha: JuzzioGlassTokens.opacityStandard + 0.2) : const Color(0x99FFFFFF),
        shadow: JuzzioGlassTokens.shadow,
        child: SizedBox(
          height: 70,
          child: Row(
            children: List.generate(items.length, (pos) {
              final item = items[pos];
              final idx = item.$4;
              final active = _selectedBottomTab == idx;
              final isCreate = idx == 2;
              final iconColor = active ? fgActive : fgMuted;
              Widget icon = isCreate
                  ? Container(
                      width: 46,
                      height: 34,
                      // v0.7.0: + düğmesi temaya göre (koyu: beyaz/siyah ikon, açık: siyah/beyaz ikon)
                      decoration: BoxDecoration(
                        // v0.8.0: beyaz blok yerine yumuşak cam
                        color: JuzzioGlassTokens.surfaceStrong,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: JuzzioGlassTokens.borderStrong),
                      ),
                      child: Icon(Icons.add_rounded, color: p.textPrimary, size: 24),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: active ? fgActive.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: active
                            ? [BoxShadow(color: fgActive.withValues(alpha: JuzzioGlassTokens.glowOpacity + 0.04), blurRadius: 14)]
                            : null,
                      ),
                      child: Icon(active ? item.$2 : item.$1, color: iconColor, size: 23),
                    );
              if (idx == 0 && unreadChats > 0) {
                icon = Stack(
                  clipBehavior: Clip.none,
                  children: [
                    icon,
                    Positioned(top: -6, right: 2, child: JuzzioGlassBadge(count: unreadChats)),
                  ],
                );
              }
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: active,
                  label: item.$3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (isCreate) {
                        _openPlusCreateMenu();
                      } else {
                        setState(() {
                          _selectedBottomTab = idx;
                          if (idx == 0 && _selectedFilterIndex == 3) {
                            _selectedFilterIndex = 0;
                          }
                        });
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        icon,
                        if (!isCreate) ...[
                          const SizedBox(height: 3),
                          Text(
                            item.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: active ? fgActive : fgMuted,
                              fontSize: 11,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar({
    required String? avatarUrl,
    required String fallbackName,
    required double radius,
    required JuzzioPalette p,
  }) {
    return JuzzioGlassAvatar(imageUrl: avatarUrl, name: fallbackName, radius: radius);
  }

  String _conversationSubtitle(JuzzioConversation c, JuzzioAppController appCtrl) {
    final preview = (c.lastMessagePreview ?? '').trim();
    if (preview.isEmpty) {
      return c.isGroup
          ? (c.memberNames.isNotEmpty ? c.memberNames.join(', ') : appCtrl.trEn('Grup sohbeti', 'Group chat', 'Gruppenchat'))
          : appCtrl.trEn('Sohbet başlatmak için dokun', 'Tap to start chatting', 'Tippe, um zu chatten');
    }
    final myUid = SupabaseService.instance.currentUserId;
    if (c.lastMessageSender == myUid) {
      return '${appCtrl.trEn("Sen", "You", "Du")}: $preview';
    }
    if (c.isGroup && c.lastMessageSender != null) {
      return '${_resolveSenderName(c.lastMessageSender!)}: $preview';
    }
    return preview;
  }

  String _formatCallDuration(int seconds) {
    if (seconds <= 0) return JuzzioAppController.instance.trEn('Cevaplandı', 'Answered', 'Angenommen');
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return m > 0 ? '$m dk ${sec.toString().padLeft(2, '0')} sn' : '$sec sn';
  }

  String _formatRelativeMinutes(DateTime dt) {
    final app = JuzzioAppController.instance;
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return app.trEn('şimdi', 'now', 'jetzt');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${app.trEn('dk', 'min', 'Min.')}';
    if (diff.inHours < 24) return '${diff.inHours} ${app.trEn('sa', 'h', 'Std.')}';
    if (diff.inDays < 7) return '${diff.inDays} ${app.trEn('g', 'd', 'T.')}';
    final l = dt.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

}

class JuzzioNewMessagePage extends StatefulWidget {
  final List<JuzzioUserProfile> friends;
  final JuzzioUserProfile? myProfile;
  final String fallbackMyName;
  final ValueChanged<JuzzioUserProfile> onStartDirectChat;
  final ValueChanged<JuzzioGroupRoom> onStartGroupChat;

  const JuzzioNewMessagePage({
    super.key,
    required this.friends,
    required this.myProfile,
    required this.fallbackMyName,
    required this.onStartDirectChat,
    required this.onStartGroupChat,
  });

  @override
  State<JuzzioNewMessagePage> createState() => _JuzzioNewMessagePageState();
}

class _JuzzioNewMessagePageState extends State<JuzzioNewMessagePage> {
  String _query = '';
  final Set<String> _selectedUserIds = {};
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final filtered = widget.friends.where((u) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return u.displayName.toLowerCase().contains(q) || u.username.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: p.headerDarkForest,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 18),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    appCtrl.trEn('Yeni Mesaj', 'New Message', 'Neue Nachricht'),
                    style: const TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: p.inputBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.glassBorder),
                        ),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: appCtrl.trEn('Kişi ara...', 'Search contacts...', 'Kontakte suchen...'),
                            hintStyle: TextStyle(color: p.textMuted, fontSize: 13.5),
                            prefixIcon: Icon(Icons.search_rounded, color: p.textMuted, size: 20),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                appCtrl.trEn(
                                  'Arkadaş bulunamadı. Önce arkadaş ekleyin; istek kabul edilince burada görünür.',
                                  'No friends found. Add friends first; they appear here once they accept.', 'Keine Freunde gefunden. Füge zuerst Freunde hinzu; sie erscheinen hier, sobald sie annehmen.',
                                ),
                                style: TextStyle(color: p.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 14),
                              itemBuilder: (context, idx) {
                                final user = filtered[idx];
                                final selected = _selectedUserIds.contains(user.id);
                                return InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    setState(() {
                                      if (selected) {
                                        _selectedUserIds.remove(user.id);
                                      } else {
                                        _selectedUserIds.add(user.id);
                                      }
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 25,
                                        backgroundColor: p.amberPrimary,
                                        backgroundImage: user.avatarUrl != null &&
                                                user.avatarUrl!.isNotEmpty
                                            ? NetworkImage(user.avatarUrl!)
                                            : null,
                                        child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                                            ? Text(
                                                user.displayName.isNotEmpty
                                                    ? user.displayName[0].toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  fontFamily: JuzzioConfig.fontRegularBold,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              user.displayName,
                                              style: TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: p.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              user.formattedPresence(isTr: appCtrl.uiLang == 'tr'),
                                              style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: selected ? p.activeNavIndigo : Colors.transparent,
                                          border: Border.all(
                                            color: selected ? p.activeNavIndigo : p.glassBorder,
                                            width: 1.8,
                                          ),
                                        ),
                                        child: selected
                                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                                            : null,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        10,
                        20,
                        MediaQuery.of(context).padding.bottom > 0 ? 24 : 18,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JuzzioColors.brandIndigo,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: _isCreating
                              ? null
                              : () async {
                                  if (_selectedUserIds.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(appCtrl.trEn(
                                          'Lütfen en az bir kişi seçin.',
                                          'Please select at least one person.', 'Bitte wähle mindestens eine Person aus.',
                                        )),
                                      ),
                                    );
                                    return;
                                  }
                                  if (_selectedUserIds.length == 1) {
                                    final target = widget.friends.firstWhere(
                                      (u) => u.id == _selectedUserIds.first,
                                      orElse: () => filtered.first,
                                    );
                                    Navigator.of(context).pop();
                                    widget.onStartDirectChat(target);
                                    return;
                                  }
                                  setState(() => _isCreating = true);
                                  final selectedProfiles = widget.friends
                                      .where((u) => _selectedUserIds.contains(u.id))
                                      .toList();
                                  final myName = widget.myProfile?.displayName ?? widget.fallbackMyName;
                                  try {
                                    final grp = await SupabaseService.instance.createGroupOrChannelRoom(
                                      title: [myName, ...selectedProfiles.map((e) => e.displayName)].take(3).join(', '),
                                      isChannel: false,
                                      disappearingTimer: appCtrl.defaultMessageTimer,
                                      members: [
                                        ...selectedProfiles.map((e) => e.displayName),
                                        myName,
                                      ],
                                      memberIds: selectedProfiles.map((e) => e.id).toList(),
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    if (grp != null) {
                                      widget.onStartGroupChat(grp);
                                    }
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    setState(() => _isCreating = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(backgroundColor: Colors.redAccent, content: Text(SupabaseService.instance.friendlyError(e))),
                                    );
                                  }
                                },
                          child: _isCreating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  appCtrl.trEn('Sohbet Başlat', 'Start Chat', 'Chat starten'),
                                  style: const TextStyle(
                                    fontFamily: JuzzioConfig.fontRegularBold,
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JuzzioStoryViewerModal extends StatefulWidget {
  final JuzzioStory story;
  final List<JuzzioStory> playlist;
  final int initialIndex;
  final JuzzioUserProfile? viewerProfile;
  final void Function(String? roomId) onOpenChatAfterReply;

  const JuzzioStoryViewerModal({
    super.key,
    required this.story,
    this.playlist = const [],
    this.initialIndex = 0,
    this.viewerProfile,
    required this.onOpenChatAfterReply,
  });

  @override
  State<JuzzioStoryViewerModal> createState() => _JuzzioStoryViewerModalState();
}

class _JuzzioStoryViewerModalState extends State<JuzzioStoryViewerModal> {
  Timer? _progressTimer;
  double _progress = 0.0;
  bool _isPaused = false;
  bool _isLiked = false;
  bool _isSending = false;
  late List<JuzzioStory> _items;
  late int _index;
  final TextEditingController _replyCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  JuzzioVideoController? _video;

  static const List<String> _storyQuickEmojis = ['❤️', '🔥', '😍', '👏', '😂', '😮'];

  JuzzioStory get _current => _items[_index];
  bool get _isMine => _current.userId == SupabaseService.instance.currentUserId;

  @override
  void initState() {
    super.initState();
    _items = widget.playlist.isNotEmpty ? widget.playlist : [widget.story];
    _index = widget.initialIndex.clamp(0, _items.length - 1);
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    _progressTimer?.cancel();
    final old = _video;
    _video = null;
    old?.dispose();
    setState(() {
      _progress = 0.0;
      _isLiked = false;
    });
    final st = _current;
    final myUid = SupabaseService.instance.currentUserId;
    if (myUid != null && !_isMine) {
      final viewer = widget.viewerProfile ??
          JuzzioUserProfile(
            id: myUid,
            username: '',
            displayName: '',
            email: '',
            bio: '',
            preferredLang: JuzzioAppController.instance.subtitleLang,
          );
      JuzzioSocialService.instance.recordStoryView(story: st, viewer: viewer);
      JuzzioStorySeen.instance.markSeen(st.id);
      SupabaseService.instance.fetchMyStoryLike(st.id).then((liked) {
        if (mounted && _current.id == st.id) setState(() => _isLiked = liked);
      });
    }
    if (st.mediaType == 'video' && (st.mediaUrl?.startsWith('http') ?? false)) {
      final controller = JuzzioVideoController(
        st.mediaUrl!,
        trimStartMs: st.trimStartMs,
        trimEndMs: st.hasTrim ? st.trimEndMs : 0,
        speed: st.playbackSpeed,
        muted: st.isMuted,
      );
      _video = controller;
      await controller.initialize();
      if (!mounted || _video != controller) return;
      controller.play();
      setState(() {});
    }
    _startProgressTimer();
  }

  int get _durationMs {
    final st = _current;
    if (st.mediaType == 'video') {
      final real = _video?.durationMs ?? 0;
      if (real > 0) return real.clamp(3000, 60000);
      return (st.videoDurationSec.clamp(3, 60)) * 1000;
    }
    return 7000;
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    const tickMs = 50;
    _progressTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (_isPaused || !mounted) return;
      final videoPos = _video?.positionMs;
      setState(() {
        if (videoPos != null && (_video?.durationMs ?? 0) > 0) {
          _progress = videoPos / _video!.durationMs;
        } else {
          _progress += tickMs / _durationMs;
        }
      });
      if (_progress >= 1.0) {
        timer.cancel();
        _next();
      }
    });
  }

  void _setPaused(bool paused) {
    setState(() => _isPaused = paused);
    if (paused) {
      _video?.pause();
    } else {
      _video?.play();
    }
  }

  void _next() {
    if (_index < _items.length - 1) {
      _index++;
      _loadCurrent();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _previous() {
    if (_index > 0) {
      _index--;
    }
    _loadCurrent();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _video?.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendStoryReply(String textOrEmoji, {File? imageFile}) async {
    if ((textOrEmoji.trim().isEmpty && imageFile == null) || _isSending || _isMine) return;
    _setPaused(true);
    setState(() => _isSending = true);
    try {
      final roomId = await SupabaseService.instance.replyToStory(
        story: _current,
        replyText: textOrEmoji.trim(),
        replyImageFile: imageFile,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      Navigator.of(context).pop();
      widget.onOpenChatAfterReply(roomId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.redAccent, content: Text(SupabaseService.instance.friendlyError(e))),
      );
      _setPaused(false);
    }
  }

  Future<void> _showStoryViewersSheet() async {
    _setPaused(true);
    final viewers = await JuzzioSocialService.instance.fetchStoryViewers(_current.id);
    if (!mounted) return;
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuzzioSocialTokens.cardBg(isDark),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${app.loc("Görüntüleyenler", "Viewers", "Zuschauer")} (${viewers.length})',
                style: TextStyle(
                  color: JuzzioSocialTokens.textPrimary(isDark),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (viewers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    app.loc('Henüz görüntüleyen yok.', 'No viewers yet.', 'Noch keine Zuschauer.'),
                    style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: viewers.length,
                    itemBuilder: (_, idx) {
                      final v = viewers[idx];
                      return ListTile(
                        leading: JuzzioUserAvatar(
                          imageUrl: v.viewerAvatarUrl,
                          displayName: v.viewerDisplayName,
                          radius: 20,
                        ),
                        title: Text(v.viewerDisplayName),
                        subtitle: Text('@${v.viewerUsername}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (v.hasLiked) const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              JuzzioSocialTokens.formatRelativeTime(v.viewedAt, app),
                              style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark), fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _setPaused(false);
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    final value = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
    return value == null ? JuzzioColors.ink : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final st = _current;
    final appCtrl = JuzzioAppController.instance;
    final s = JuzzioStrings(appCtrl.uiLang);
    final isVideo = st.mediaType == 'video';
    final hasRemoteMedia = st.mediaUrl != null && st.mediaUrl!.startsWith('http');
    final video = _video;

    return Scaffold(
      backgroundColor: JuzzioColors.darkBackground,
      body: GestureDetector(
        onLongPressStart: (_) => _setPaused(true),
        onLongPressEnd: (_) => _setPaused(false),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < width * 0.3) {
            _previous();
          } else if (details.localPosition.dx > width * 0.7) {
            _next();
          }
        },
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (st.musicUrl.isNotEmpty)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: JuzzioBackgroundMusic(
                    musicUrl: st.musicUrl,
                    startSec: st.musicStartSec,
                    playing: !_isPaused,
                  ),
                ),
              if (isVideo && video != null && video.isInitialized)
                Center(child: JuzzioMediaFilters.apply(st.filterPreset, video.buildView()))
              else if (isVideo && video != null && video.hasError)
                const Center(
                  child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
                )
              else if (isVideo)
                const Center(child: CircularProgressIndicator(color: Colors.white))
              else if (st.mediaType == 'image' && hasRemoteMedia)
                JuzzioMediaFilters.apply(
                  st.filterPreset,
                  Image.network(
                    st.mediaUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _parseHex(st.bgColorHex),
                        Color.lerp(_parseHex(st.bgColorHex), Colors.black, 0.55) ?? JuzzioColors.ink,
                      ],
                    ),
                  ),
                  alignment: st.overlayTextOriginal.isNotEmpty ? Alignment.bottomCenter : Alignment.center,
                  padding: st.overlayTextOriginal.isNotEmpty
                      ? const EdgeInsets.fromLTRB(28, 32, 28, 120)
                      : const EdgeInsets.all(32),
                  child: Text(
                    st.captionTranslated.isNotEmpty && st.captionTranslated != st.captionOriginal
                        ? '${st.captionOriginal}\n\n🌐 ${st.captionTranslated}'
                        : st.captionOriginal,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: st.overlayTextOriginal.isNotEmpty ? 16 : 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

              if (st.overlayTextOriginal.isNotEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * kJuzzioStoryTextPadRatio),
                    child: JuzzioOverlayText(
                      text: st.overlayTextOriginal,
                      secondaryText: st.overlayTextTranslated,
                      styleId: st.overlayStyle,
                      colorHex: st.overlayColor,
                      fontSize: MediaQuery.of(context).size.width * kJuzzioStoryTextSizeRatio,
                    ),
                  ),
                ),
              if (st.stickers.isNotEmpty)
                Positioned.fill(child: IgnorePointer(child: JuzzioStickerLayer(stickers: st.stickers))),
              if (juzzioIsPlayableMusic(st.musicUrl))
                Positioned(
                  top: 82,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: JuzzioMusicPill(
                      interactive: false,
                      title: st.musicTitle,
                      artist: '',
                      coverUrl: '',
                      musicUrl: st.musicUrl,
                      isDark: true,
                      maxWidth: 240,
                      playing: !_isPaused,
                    ),
                  ),
                ),

              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    Row(
                      children: List.generate(_items.length, (i) {
                        final value = i < _index ? 1.0 : (i == _index ? _progress.clamp(0.0, 1.0) : 0.0);
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: value,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 3.5,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        JuzzioUserAvatar(imageUrl: st.userAvatar, displayName: st.displayName, radius: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // İsim tek başına (kesilmeden önce önceliklidir); zaman küçük ve sabit
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      st.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: JuzzioConfig.fontRegularBold,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    JuzzioSocialTokens.formatRelativeTime(st.createdAt, appCtrl),
                                    maxLines: 1,
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                ],
                              ),
                              Text(
                                _isPaused
                                    ? appCtrl.trEn('⏸ Duraklatıldı', '⏸ Paused', '⏸ Pausiert')
                                    : (st.username.isNotEmpty ? '@${st.username}' : s.t('story_hold_hint')),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (_isMine) ...[
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            onPressed: _showStoryViewersSheet,
                            icon: const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
                            label: Text('${st.viewsCount}', style: const TextStyle(color: Colors.white)),
                          ),
                          IconButton(
                          visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              _setPaused(true);
                              try {
                                await JuzzioSocialService.instance.deleteStory(st);
                                if (context.mounted) Navigator.of(context).pop();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
                                _setPaused(false);
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            tooltip: appCtrl.trEn('Hikâyeyi Sil', 'Delete Story', 'Story löschen'),
                          ),
                        ] else
                          IconButton(
                          visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              _setPaused(true);
                              await showJuzzioReportModalSheet(
                                context: context,
                                targetType: 'story',
                                targetId: st.id,
                                targetOwnerId: st.userId,
                              );
                              if (mounted) _setPaused(false);
                            },
                            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
                            tooltip: appCtrl.trEn('Şikâyet Et', 'Report', 'Melden'),
                          ),
                        if (isVideo && video != null)
                          IconButton(
                          visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => video.toggleMute()),
                            icon: Icon(
                              video.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (st.captionOriginal.isNotEmpty && st.mediaType != 'text')
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.62),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          st.captionTranslated.isNotEmpty && st.captionTranslated != st.captionOriginal
                              ? '${st.captionOriginal}\n🌐 ${st.captionTranslated}'
                              : st.captionOriginal,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    if (_isMine)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const Icon(Icons.visibility_outlined, color: Colors.white70, size: 18),
                            Text('${st.viewsCount}', style: const TextStyle(color: Colors.white)),
                            const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
                            Text('${st.likesCount}', style: const TextStyle(color: Colors.white)),
                            Text(
                              st.visibility == 'everyone'
                                  ? appCtrl.trEn('Herkese açık', 'Public', 'Öffentlich')
                                  : st.visibility == 'private'
                                      ? appCtrl.trEn('Sadece ben', 'Only me', 'Nur ich')
                                      : appCtrl.trEn('Arkadaşlar', 'Friends', 'Freunde'),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _storyQuickEmojis.map((emoji) {
                            return GestureDetector(
                              onTap: () => _sendStoryReply(emoji),
                              child: Text(emoji, style: const TextStyle(fontSize: 24)),
                            );
                          }).toList(),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () async {
                              _setPaused(true);
                              final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                              if (picked == null || !context.mounted) {
                                _setPaused(false);
                                return;
                              }
                              await _sendStoryReply(
                                _replyCtrl.text.trim().isEmpty ? '📷' : _replyCtrl.text.trim(),
                                imageFile: File(picked.path),
                              );
                            },
                            icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _replyCtrl,
                              onTap: () => _setPaused(true),
                              onSubmitted: (v) => _sendStoryReply(v),
                              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: Colors.white),
                              decoration: InputDecoration(
                                hintText: s.t('story_swipe_up_hint'),
                                hintStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.14),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final liked = await SupabaseService.instance.toggleStoryLike(st);
                              if (mounted) setState(() => _isLiked = liked);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: _isLiked ? Colors.redAccent : Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _sendStoryReply(_replyCtrl.text),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: const BoxDecoration(color: JuzzioColors.blue600, shape: BoxShape.circle),
                              child: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
