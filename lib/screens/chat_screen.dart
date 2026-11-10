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

import '../services/juzzio_call_session.dart';
import '../services/juzzio_notification_preview.dart';
import '../services/juzzio_media_cache.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart' show FilePicker, FileType, PlatformFile;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/juzzio_media_url.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/native_bridge.dart';
import '../models/social_models.dart';
import '../services/fcm_push_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_attach_menu.dart';
import '../widgets/juzzio_space_kit.dart';
import '../widgets/juzzio_rich_text.dart';
import '../widgets/juzzio_event_widgets.dart';
import '../widgets/juzzio_poll_widgets.dart';
import '../widgets/juzzio_safety_number.dart';
import '../widgets/juzzio_view_once.dart';
import '../widgets/juzzio_message_cards.dart';
import 'channel_create_screen.dart';
import 'locked_chats_page.dart';
import '../main.dart' show JuzzioRootFlow;
import '../widgets/juzzio_consent.dart';
import '../services/juzzio_weather_service.dart';
import '../services/juzzio_net.dart';
import '../services/juzzio_gallery_saver.dart';
import '../core/juzzio_community.dart';
import '../widgets/juzzio_shift_card.dart';
import '../widgets/juzzio_encrypted_image.dart';
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
import '../core/juzzio_back_navigation.dart';
import '../core/juzzio_chat_activity.dart';
import '../services/juzzio_life_service.dart';
import 'life_center_page.dart';
import 'message_search_page.dart';
import '../services/juzzio_chat_lock.dart';
import '../widgets/chat_lock_ui.dart';
import '../services/juzzio_chat_activity_service.dart';
import '../services/juzzio_features_service.dart';
import '../services/juzzio_e2ee.dart';
import '../widgets/group_management_sheet.dart';
import '../widgets/profile_extras.dart';
import '../widgets/juzzio_emoji_picker.dart';
import '../widgets/juzzio_story_stickers.dart';
import 'profile/juzzio_profile_view.dart';
import 'chick_game_screen.dart';
import 'qa_box_screen.dart';
import 'safety_walk_screen.dart';
import 'watch_party_screen.dart';
import '../widgets/juzzio_chick_art.dart';
import 'banned_screen.dart';
import 'maintenance_screen.dart';
import 'social/juzzio_creator_studio.dart';
import 'social/juzzio_global_feed.dart';
import '../widgets/juzzio_video_kit.dart';
import '../widgets/juzzio_swipe_reply.dart';
import '../widgets/juzzio_quote_preview.dart';
import '../widgets/juzzio_cloth_refresh.dart';
import '../widgets/juzzio_ui_kit.dart';
import '../widgets/juzzio_notification_stack.dart';
import 'backup_page.dart';
import '../services/juzzio_story_seen.dart';
import '../widgets/juzzio_motion.dart';

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
  // v0.9.3: sohbet listesinde son mesajın GERÇEK metni (şifreli mesajlar cihazda çözülür)
  final Map<String, String> _lastPreviews = {};
  final Map<String, String> _lastPreviewKeys = {};
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

  // v1.1.0: alıntıya dokununca alıntılanan mesaja git (ters listede tahmini kaydırma + görünür olunca hizalama)
  final Map<String, GlobalKey> _bubbleKeys = {};
  List<JuzzioMessage> _listedMessages = const [];
  String? _flashMessageId;
  Timer? _flashTimer;
  bool _jumping = false;

  // v1.1.0 hareket kiti: ikon dönüşümleri ve gönderim uçuşu
  final GlobalKey _composerFieldKey = GlobalKey();
  bool _attachMenuOpen = false;
  String? _justStarredId;
  final Set<String> _reactionPopKeys = <String>{};
  bool _kebabOpen = false;
  bool _inboxMenuOpen = false;
  // 0 = Sohbetler (Hey Joseph), 1 = Aramalar, 2 = Durum (Foto/Video), 3 = Arkadaşlar, 4 = Ayarlar
  // 0 = Message (Home & Mesajlar), 1 = Calls (Arama), 2 = Add / Arkadaşlar, 3 = Küresel akış, 4 = Profile (Profil & Ayarlar)
  // v0.9.0 son talimat §3.1: 5=Ana Sayfa (kök), 0=Sohbetler, 3=Keşfet, 6=Bildirimler, 4=Profil;
  // 1=Aramalar ve 2=Arkadaşlar ana sayfa kısayollarından açılır.
  int _selectedBottomTab = JuzzioBackNavigator.homeTab;
  bool _isInsideConversation = false;
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

  /// v1.2.0: açık sohbet Juzzio Topluluğu kanalı mı?
  bool get _inCommunity => _activeGroupRoom != null && juzzioIsCommunityTitle(_activeGroupRoom!.title);

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
  // v0.9.6: yönetici panelinden gelen medya sınırları (Ayarlar → Ses/Medya)
  int _voiceMaxSeconds = 300;
  int _audioBitrateKbps = 96;
  int _videoMaxSeconds = 180;
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

  // v0.9.0 Faz 2: geri tuşu durum makinesi + engellemeyen çıkış ipucu
  final JuzzioBackNavigator _backNav = JuzzioBackNavigator();
  bool _exitHintVisible = false;
  Timer? _exitHintTimer;
  // v1.2.4: kaydırma sırasında tüm ekranı yeniden kurmamak için ValueNotifier
  final ValueNotifier<bool> _showJumpDown = ValueNotifier<bool>(false);
  final FocusNode _composerFocus = FocusNode();

  // Sohbet başlığında gerçek çevrimiçi / son görülme bilgisi
  String? _presenceUserId;
  ({bool isOnline, DateTime? lastSeen})? _activePresence;
  Timer? _presenceTimer;

  // Sohbet penceresindeki sürüklenebilir çatlak yumurta (Civciv oyunu)
  Offset? _eggOffset;
  // v0.9.3: sohbetteki civciv yumurtası yalnızca ortak civciv ACIKTIĞINDA (veya bu kişiden davet varken) görünür
  JuzzioChickState? _chickState;
  DateTime? _chickFetchedAt;
  bool _chickFetching = false;

  void _refreshChickStateIfStale() {
    if (_chickFetching) return;
    final at = _chickFetchedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) return;
    _chickFetching = true;
    JuzzioFeaturesService.instance.fetchMyChick().then((st) {
      if (mounted) setState(() => _chickState = st);
    }).catchError((_) {}).whenComplete(() {
      _chickFetching = false;
      _chickFetchedAt = DateTime.now();
    });
  }

  void _openChickGame(JuzzioUserProfile partner) {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => JuzzioChickGameScreen(
              friends: _acceptedFriendProfiles,
              myDisplayName: _myProfile?.displayName ?? widget.myDisplayName,
              inviteFriend: partner,
            ),
          ),
        )
        .then((_) {
      _chickFetchedAt = null;
      if (mounted) _refreshChickStateIfStale();
    });
  }
  String? _playingMessageId;

  late TextEditingController _profileNameCtrl;
  late TextEditingController _profileBioCtrl;
  File? _pendingAvatarFile;

  StreamSubscription<List<JuzzioFriendship>>? _friendSub;
  StreamSubscription<List<JuzzioStory>>? _storySub;
  StreamSubscription<List<JuzzioCallLog>>? _callLogSub;

  bool get _incomingCallBannerVisible => _incomingCall != null;

  JuzzioFriendship? _headsUpFriendRequest;
  final Set<String> _seenFriendReqIds = {};
  bool _friendshipsLoadedOnce = false;
  int _lastRenderedMessageCount = 0;
  String _callsFilter = 'all';
  Stream<List<JuzzioMessage>>? _activeMessagesStream;
  String? _activeMessagesStreamRoomId;

  /// Her yeniden çizimde yeni Realtime kanalı açılmasını önlemek için oda başına tek akış
  Stream<List<JuzzioMessage>> _messagesStreamFor(String roomId) {
    if (_activeMessagesStream == null || _activeMessagesStreamRoomId != roomId || _activeMessagesWindow != _messageWindow) {
      // v1.2.4: aynı odada pencere büyüyorsa (eski sayfa) önbellek yeniden yayınlanmaz
      final growing = _activeMessagesStreamRoomId == roomId && _activeMessagesStream != null;
      if (_activeMessagesStreamRoomId != roomId) _messageWindow = _messagePageSize;
      _activeMessagesStreamRoomId = roomId;
      _activeMessagesWindow = _messageWindow;
      _activeMessagesStream = SupabaseService.instance.watchRoomMessages(roomId, limit: _messageWindow, skipCache: growing);
      unawaited(_loadPinnedMessages(roomId));
    }
    return _activeMessagesStream!;
  }

  // v0.9.6 sayfalama: sohbet açılınca en yeni 50 mesaj; "Daha eski mesajlar" ile 50'şer artar
  static const int _messagePageSize = 50;
  int _messageWindow = _messagePageSize;
  int _activeMessagesWindow = 0;

  // v0.9.6: sabitlenen mesajlar (sohbetin üstündeki şerit)
  List<JuzzioMessage> _pinnedMessages = const [];
  int _pinnedIndex = 0;
  String _lastPinnedSig = '';

  Future<void> _loadPinnedMessages(String roomId) async {
    final list = await SupabaseService.instance.fetchPinnedMessages(roomId);
    if (!mounted || _activeMessagesStreamRoomId != roomId) return;
    setState(() {
      _pinnedMessages = list;
      if (_pinnedIndex >= list.length) _pinnedIndex = 0;
    });
  }

  Future<void> _togglePin(JuzzioMessage msg) async {
    final app = JuzzioAppController.instance;
    final pin = !_pinnedMessages.any((m) => m.id == msg.id);
    try {
      await SupabaseService.instance.pinMessage(msg.id, pin);
      HapticFeedback.selectionClick();
      _showSnack(pin ? app.trEn('Mesaj sabitlendi', 'Message pinned', 'Nachricht angeheftet') : app.trEn('Sabitleme kaldırıldı', 'Unpinned', 'Losgelöst'));
      await _loadPinnedMessages(msg.roomId);
    } catch (e) {
      final t = e.toString();
      _showSnack(
        t.contains('pin_not_allowed')
            ? app.trEn('Grupta yalnız mesajın sahibi veya yöneticiler sabitleyebilir.', 'In groups only the sender or admins can pin.', 'In Gruppen dürfen nur Absender oder Admins anheften.')
            : SupabaseService.instance.friendlyError(e),
        isError: true,
      );
    }
  }

  Widget _buildPinnedBar(JuzzioPalette p) {
    if (_pinnedMessages.isEmpty) return const SizedBox.shrink();
    final app = JuzzioAppController.instance;
    final i = _pinnedIndex.clamp(0, _pinnedMessages.length - 1);
    final m = _pinnedMessages[i];
    final txt = m.originalText.trim().isNotEmpty
        ? m.originalText.trim()
        : (m.messageType == 'voice'
            ? '🎤 ${app.trEn('Sesli mesaj', 'Voice message', 'Sprachnachricht')}'
            : (m.messageType == 'image' ? '📷 ${app.trEn('Fotoğraf', 'Photo', 'Foto')}' : '📎 ${app.trEn('Medya', 'Media', 'Medien')}'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: JuzzioGlass(
        radius: 16,
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: InkWell(
          onTap: () => setState(() => _pinnedIndex = (i + 1) % _pinnedMessages.length),
          child: Row(children: [
            Icon(Icons.push_pin_rounded, size: 18, color: p.amberPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _pinnedMessages.length > 1
                      ? '${app.trEn('Sabit mesaj', 'Pinned message', 'Angeheftet')} ${i + 1}/${_pinnedMessages.length}'
                      : app.trEn('Sabit mesaj', 'Pinned message', 'Angeheftet'),
                  style: TextStyle(color: p.amberPrimary, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textPrimary, fontSize: 13)),
              ]),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: app.trEn('Sabitlemeyi kaldır', 'Unpin', 'Lösen'),
              icon: Icon(Icons.close_rounded, size: 18, color: p.textSecondary),
              onPressed: () => _togglePin(m),
            ),
          ]),
        ),
      ),
    );
  }

  static const List<String> _reactionEmojis = ['❤️‍🔥', '🥹', '🌸', '🫣', '🤩'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    JuzzioAppController.instance.ensureBackgroundNotificationReady();
    unawaited(SupabaseService.instance.touchDailyStreak());
    // v0.9.0 §4.1/§4.3: Ana Sayfa görev özeti ve kayıtlı mesaj işaretleri (hata sessiz; ekranlar kendi hata durumunu gösterir)
    JuzzioLifeService.instance.refresh().catchError((_) => const <JuzzioLifeTask>[]);
    JuzzioLifeService.instance.loadSavedIds();
    JuzzioChatLock.instance.load();
    JuzzioChatLock.instance.addListener(_onChatLockChanged);
    // v1.2.1: hava durumu teması (ayar kapalıysa hiçbir şey yapmaz; konum izni yalnız bir kez sorulur)
    JuzzioWeatherService.instance.start();
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
      // v1.2.1: aydınlatma / açık rıza / 15 yaş onayı yoksa veya metin güncellendiyse devam etmeden önce alınır
      if (!mounted) return;
      await juzzioEnsureConsent(context, onDecline: () async {
        await SupabaseService.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const JuzzioRootFlow()),
          (route) => false,
        );
      });
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
    // v0.9.0 N-A: yazıyor / boş durumu (yayın sıklığını JuzzioActivitySender sınırlar)
    if (_isInsideConversation) {
      JuzzioChatActivityService.instance.setLocal(has ? JuzzioActivityState.typing : JuzzioActivityState.idle);
    }
    if (has != _composerHasText && mounted) setState(() => _composerHasText = has);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    // v0.9.3: öne gelince çevrimdışıyken yapılan ayar değişiklikleri sunucuya yazılır
    if (state == AppLifecycleState.resumed) unawaited(SupabaseService.instance.flushPendingOps());
    // v0.9.5: günlük seri (gün, sunucu saatine göre)
    if (state == AppLifecycleState.resumed) unawaited(SupabaseService.instance.touchDailyStreak());
    if (state != AppLifecycleState.resumed) {
      JuzzioChatActivityService.instance.setLocal(JuzzioActivityState.idle);
      // v0.9.0 §4.6: arka plana geçince kilitli sohbetler yeniden kilitlenir
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
        final lock = JuzzioChatLock.instance;
        final room = _activeConversationRoomId;
        if (_isInsideConversation && room != null && lock.isLocked(room)) _leaveConversation();
        lock.relock();
        if (_showLockedChats) setState(() => _showLockedChats = false);
      }
      // Ana ekrana dönerken widget'lar güncel tema/dil/verilerle yenilenir
      _syncHomeWidget();
      JuzzioAppController.instance.ensureBackgroundNotificationReady();
      if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
        // v0.9.0 (G14): gecikmeli tercih kaydı süreç sonlanmadan diske yazılır
        JuzzioAppController.instance.flushPreferences();
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

  /// v0.9.7: kumaş yenileme — sohbet listesini ve önizlemeleri sunucudan tazeler.
  Future<void> _refreshConversationsNow() async {
    try {
      final list = await SupabaseService.instance.fetchMyConversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _conversationsLoaded = true;
        _groupRooms = list.where((c) => c.isGroup).map((c) => c.toGroupRoom()).toList();
      });
      await _refreshLastPreviews(list);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _initializeWorkspace() async {
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    try {
      await JuzzioAppController.instance.loadUserPreferences(uid);
    } catch (_) {}
    // v0.9.2: çevrimdışı medya önbelleği (hesaba özel klasör)
    await JuzzioMediaDiskCache.instance.init(uid);
    // v1.2.4: bağlantı izleyici — bağlantı gelince bekleyen değişiklikler gönderilir ve
    // tüm canlı veriler (sohbetler, mesaj akışı, profil) kendiliğinden tazelenir
    JuzzioNet.instance.start();
    JuzzioNet.instance.addRegainHook(SupabaseService.instance.flushPendingOps);
    JuzzioNet.instance.addRegainHook(JuzzioConsentService.instance.flushPending);
    _netRegainSub?.cancel();
    _netRegainSub = JuzzioNet.instance.onRegained.listen((_) => _onNetworkRegained());
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
          unawaited(_refreshLastPreviews(cachedConvs));
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
        unawaited(_refreshLastPreviews(list));
        if (_activeGroupRoom != null) {
          for (final g in _groupRooms) {
            if (g.id == _activeGroupRoom!.id) _activeGroupRoom = g;
          }
        }
      });
      _syncHomeWidget();
    }, onError: (_) async {
      // v0.9.3: ağ hatasında (çevrimdışı) boş liste yerine önbellekteki sohbetler + son mesajlar gösterilir
      if (_conversations.isEmpty) {
        final cachedConvs = await svc.loadCachedConversations();
        if (!mounted) return;
        if (cachedConvs.isNotEmpty) {
          setState(() {
            _conversations = cachedConvs;
            _groupRooms = cachedConvs.where((c) => c.isGroup).map((c) => c.toGroupRoom()).toList();
          });
          unawaited(_refreshLastPreviews(cachedConvs));
        }
      }
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
    // v1.2.4: internet varken çevrimdışı önbellekler arka planda doldurulur
    Future<void>.delayed(const Duration(seconds: 4), _warmOfflineCaches);
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

    // 7. Arama geçmişi (yalnızca benim aramalarım) — v1.2.4: çevrimdışı öncelikli, kopmada boşalmaz
    _subscribeCallLogs();

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

  StreamSubscription<void>? _netRegainSub;

  /// v1.2.4: bağlantı geri geldi — kopan akışlar yeniden kurulur, liste ve profil tazelenir.
  Future<void> _onNetworkRegained() async {
    if (!mounted) return;
    final svc = SupabaseService.instance;
    _incomingMsgSub?.cancel();
    _incomingMsgSub = svc.watchIncomingMessages().listen(_handleIncomingMessage, onError: (_) {});
    _incomingCallSub?.cancel();
    _incomingCallSub = svc.watchIncomingCalls().listen(_handleIncomingCalls, onError: (_) {});
    unawaited(_refreshConversationsNow());
    final uid = svc.currentUserId;
    if (uid != null) {
      final prof = await svc.fetchUserProfile(uid);
      if (prof != null && mounted) setState(() => _myProfile = prof);
    }
    svc.setPresence(true);
    unawaited(_warmOfflineCaches());
  }

  bool _warming = false;

  /// v1.2.4: Profil (gönderiler, kaydedilenler, sayaçlar), bildirimler, görev/hatırlatıcılar ve
  /// Keşfet'in ilk sayfası internet varken arka planda indirilip cihaza yazılır. Her biri
  /// bağımsızdır; biri başarısız olsa diğerleri sürer. Ekranı bekletmez.
  Future<void> _warmOfflineCaches() async {
    if (_warming || !mounted) return;
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    _warming = true;
    final social = JuzzioSocialService.instance;
    Future<void> go(Future<Object?> f) async {
      try {
        await f;
      } catch (_) {}
    }

    try {
      await Future.wait<void>([
        go(social.fetchFeedPosts(authorId: uid, limit: 30)),
        go(social.fetchMySavedPosts()),
        go(social.fetchProfileSocialCounts(uid)),
        go(social.fetchNotifications()),
        go(social.fetchFeedPosts(filter: 'all', limit: 25)),
        go(JuzzioLifeService.instance.refresh()),
        go(SupabaseService.instance.fetchAllProfiles()),
      ]);
    } finally {
      _warming = false;
    }
  }

  void _subscribeCallLogs() {
    _callLogSub?.cancel();
    _callLogSub = SupabaseService.instance.watchCallLogs().listen((logs) {
      if (!mounted) return;
      setState(() => _callLogs = logs);
      _syncHomeWidget();
    }, onError: (_) {});
  }

  /// v1.2.4: Aramalar sekmesinde aşağı çekerek yenileme — akış yeniden bağlanır ve
  /// ilk güncel liste (en fazla 6 sn) beklenir; çevrimdışıysa önbellekteki liste kalır.
  Future<void> _refreshCallLogs() async {
    final done = Completer<void>();
    _callLogSub?.cancel();
    _callLogSub = SupabaseService.instance.watchCallLogs().listen((logs) {
      if (!mounted) return;
      setState(() => _callLogs = logs);
      _syncHomeWidget();
      if (!done.isCompleted) done.complete();
    }, onError: (_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 6), onTimeout: () {});
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
    // v1.2.4: gelen fotoğraf/video/belge galeriye ve çevrimdışı önbelleğe (ayar açıksa)
    JuzzioGallerySaver.instance.handleIncoming(msg);
    final viewingThisRoom = _isInsideConversation && _activeConversationRoomId == msg.roomId && !_isAppInBackground;
    if (viewingThisRoom) {
      SupabaseService.instance.markRoomRead(msg.roomId);
      return;
    }
    // v0.9.0 (ek paket N-G): Sohbetler ana ekranındaki uygulama içi "hızlı yanıt" bandı
    // kaldırıldı. Sistem bildirimi FCM'den gelir (_handleForegroundPush); okunmamış sayaçları
    // sohbet listesi akışından güncellenir. Mesaj metni artık bant için çevrilmez/çözülmez.
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
    unawaited(_showForegroundPush(payload));
  }

  /// v0.9.3: uygulama açıkken (başka ekrandayken) gelen mesaj bildirimi de içeriği UYGULAMA
  /// DİLİNE çevrilmiş olarak gösterir; dokununca sohbete gider, bildirimden yanıtlanabilir.
  Future<void> _showForegroundPush(JuzzioPushEventPayload payload) async {
    final et = payload.eventType;
    final app = JuzzioAppController.instance;
    var body = payload.body;
    String? lockBody;
    const messageEvents = {'message', 'group_activity', 'story_reply'};
    if (messageEvents.contains(et) && payload.targetId.isNotEmpty && payload.targetSecondaryId.isNotEmpty) {
      final mode = juzzioPreviewModeFrom(app.notificationPreviewMode);
      lockBody = app.trEn('Yeni mesaj', 'New message', 'Neue Nachricht');
      if (mode == JuzzioNotificationPreviewMode.full) {
        final clear = await JuzzioNotificationPreview.resolve(roomId: payload.targetId, messageId: payload.targetSecondaryId);
        if (clear != null && clear.isNotEmpty) body = clear;
      } else if (mode == JuzzioNotificationPreviewMode.hidden) {
        body = lockBody;
      }
    }
    if (!mounted) return;
    // Bu arada kullanıcı o sohbete girdiyse gösterme
    if (_isInsideConversation && _activeConversationRoomId == payload.targetId && !_isAppInBackground) return;
    // v0.9.7: uygulama ön plandayken sistem bildirimi yerine uygulama içi cam bildirim yığını
    if (!_isAppInBackground && et != 'missed_call' && et != 'system') {
      JuzzioNotificationStack.instance.show(
        context,
        JuzzioStackItem(
          title: payload.title.isNotEmpty ? payload.title : 'Juzzio',
          body: body,
          icon: switch (et) {
            'message' || 'group_activity' => Icons.chat_bubble_rounded,
            'story_reply' => Icons.auto_stories_rounded,
            'like' || 'comment_like' => Icons.favorite_rounded,
            'comment' || 'reply' || 'mention' => Icons.mode_comment_rounded,
            'follow' || 'follow_request' || 'friend_request' => Icons.person_add_alt_1_rounded,
            'sos' => Icons.sos_rounded,
            _ => Icons.notifications_rounded,
          },
          onTap: () {
            if (mounted) _handlePushDeepLink(payload);
          },
        ),
      );
      return;
    }
    await app.triggerSystemNotification(
      title: payload.title,
      body: body,
      isUpdate: et == 'system',
      isCall: et == 'missed_call',
      channelId: payload.channelId.startsWith('juzzio_') ? payload.channelId : null,
      eventType: et,
      notificationId: payload.notificationId,
      targetId: payload.targetId,
      targetSecondaryId: payload.targetSecondaryId,
      actorId: payload.actorId,
      lockScreenBody: lockBody,
    );
  }

  String? _pendingAcceptCallId;
  DateTime? _pendingAcceptAt;

  /// Bildirimden "Kabul" bekleyen çağrı bu mu? (tek kullanımlık, 30 sn geçerli)
  bool _takePendingAccept(String callId) {
    final id = _pendingAcceptCallId;
    final at = _pendingAcceptAt;
    if (id == null || at == null) return false;
    if (DateTime.now().difference(at) > const Duration(seconds: 30)) {
      _pendingAcceptCallId = null;
      return false;
    }
    if (id != callId) return false;
    _pendingAcceptCallId = null;
    return true;
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
    // v0.9.0 N-F: kullanıcı bildirimden "Kabul"e bastıysa sessiz kip aramayı düşürmez
    if (_takePendingAccept(call.id)) {
      setState(() => _incomingCall = call);
      _acceptIncomingCall();
      return;
    }
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

  void _onChatLockChanged() {
    if (mounted) setState(() {});
  }

  void _onStorySeenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    JuzzioIsland.instance.clear('voice_rec');
    WidgetsBinding.instance.removeObserver(this);
    _profilesSub?.cancel();
    _convSub?.cancel();
    _incomingMsgSub?.cancel();
    _incomingCallSub?.cancel();
    _friendSub?.cancel();
    _storySub?.cancel();
    _callLogSub?.cancel();
    _netRegainSub?.cancel();
    _showJumpDown.dispose();
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
    _flashTimer?.cancel();
    _profileNameCtrl.dispose();
    _profileBioCtrl.dispose();
    _voiceRecorder.dispose();
    _audioPlayer.dispose();
    JuzzioStorySeen.instance.removeListener(_onStorySeenChanged);
    _exitHintTimer?.cancel();
    JuzzioChatLock.instance.removeListener(_onChatLockChanged);
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
    // v0.9.0 (denetim D): Uçtan uca şifreli mesajın çözülmüş metni, kullanıcı açıkça izin
    // vermedikçe üçüncü taraf çeviri servisine GÖNDERİLMEZ.
    if (msg.metadata['e2ee'] is Map && !JuzzioAppController.instance.e2eeTranslationOptIn) {
      return msg.translatedText.trim().isNotEmpty ? msg.translatedText : msg.originalText;
    }
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

  bool _showLockedChats = false;

  /// v1.0.0: gönderilmekte olan metin mesajları — gönder'e basıldığı an balon görünür,
  /// sunucu kaydı (aynı client_msg_id) akışa düşünce yerel kopya kaldırılır.
  final Map<String, JuzzioMessage> _outbox = {};

  void _enterConversation({required String roomId, JuzzioUserProfile? partner, JuzzioGroupRoom? group}) {
    // v0.9.0 §4.6: kilitli sohbet (bildirim, arama, kısayol dahil her yoldan) PIN ister
    final lock = JuzzioChatLock.instance;
    if (lock.isLocked(roomId) && !lock.isUnlocked) {
      juzzioRequireChatPin(context, allowCreate: false).then((ok) {
        if (ok && mounted) _enterConversation(roomId: roomId, partner: partner, group: group);
      });
      return;
    }
    _lastRenderedMessageCount = 0;
    _newestRenderedId = null;
    _newestRenderedAt = null;
    _loadingOlder = false;
    _showJumpDown.value = false;
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _activeMessagesStream = null;
    _activeMessagesStreamRoomId = null;
    _messageWindow = _messagePageSize;
    _pinnedMessages = const [];
    _pinnedIndex = 0;
    setState(() {
      _activeGroupRoom = group;
      _activeFriendPartner = group == null ? partner : null;
      _activeConversationRoomId = roomId;
      _selectedBottomTab = 0;
      _isInsideConversation = true;
    });
    JuzzioChatActivityService.instance.watchRoom(
      roomId,
      memberIds: group != null ? group.groupMemberIds.toSet() : (partner != null ? {partner.id} : null),
    );
    SupabaseService.instance.markRoomRead(roomId);
    SupabaseService.instance.setActiveRoom(roomId);
  }

  void _leaveConversation() {
    final roomId = _activeConversationRoomId;
    // v1.2.4: kilitli sohbetten çıkınca kilit hemen kapanır (tekrar girişte PIN sorulur)
    if (roomId != null && JuzzioChatLock.instance.isLocked(roomId)) JuzzioChatLock.instance.relock();
    if (_isRecordingVoice) _cancelVoiceRecording();
    _ensurePresenceWatch(null);
    JuzzioChatActivityService.instance.watchRoom(null);
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

  /// Sohbete girişte her zaman en son mesaj görünür (v0.9.7: ters liste sayesinde ilk karede).
  /// Yeni mesajda yumuşak kaydırılır; kullanıcı yukarıda eski mesajları okuyorsa ve mesaj
  /// başkasındansa zorla kaydırılmaz. Klavye/emoji paneli açılınca son mesaj altta kalmaz.
  double _lastKeyboardInset = 0;
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final inset = views.first.viewInsets.bottom;
    if (inset > _lastKeyboardInset + 1 && _scrollCtrl.hasClients) {
      final pos = _scrollCtrl.position;
      // v0.9.7: ters liste — 0 = en alttaki (en yeni) mesaj
      if (pos.pixels < 600) {
        Future.delayed(const Duration(milliseconds: 120), () => _scrollMessagesToBottom(force: true));
      }
    }
    _lastKeyboardInset = inset;
  }

  /// v0.9.7: mesaj listesi TERS (reverse: true) çizilir — kaydırma konumu 0 her zaman en
  /// son mesajdır. Böylece sohbet ilk karede en alttan açılır, eski mesajlar üste eklenince
  /// görünüm kaymaz ve "maxScrollExtent'e tekrar tekrar atla" döngüsünden doğan titreme biter.
  void _scrollMessagesToBottom({bool instant = false, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (pos.pixels <= 0.5) return;
      if (!force && pos.pixels > 420) return; // kullanıcı yukarıda okuyor: zorla indirme
      if (instant || pos.pixels > 4000) {
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
    });
  }

  /// Ters listede üste yaklaşınca eski mesajlar kendiliğinden yüklenir (tek seferde 50).
  bool _loadingOlder = false;
  String? _newestRenderedId;
  DateTime? _newestRenderedAt;

  /// Cihazı kaydeder; hesap/cihaz engelliyse oturumu kapatıp engel ekranını gösterir.
  /// Bakım modu: yönetici dışındaki kullanıcılar bilgilendirme ekranında bekler.
  Future<void> _checkMaintenanceMode() async {
    final cfg = await JuzzioFeaturesService.instance.fetchAppConfig();
    _voiceMaxSeconds = cfg.voiceMaxSeconds;
    _audioBitrateKbps = cfg.audioBitrateKbps;
    _videoMaxSeconds = cfg.videoMaxSeconds;
    // v0.9.6: yönetici minimum sürümü yükselttiyse eski istemci "güncelleme gerekli" ekranında bekler
    final updateRequired = cfg.minSupportedBuild > JuzzioConfig.appVersionCode;
    if ((!cfg.maintenanceMode && !updateRequired) || !mounted) return;
    final admin = await JuzzioFeaturesService.instance.isAdmin();
    if (admin || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JuzzioMaintenanceScreen(message: cfg.maintenanceMessage, updateRequired: updateRequired)),
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

  /// v0.9.0: Karşı tarafın şifreleme anahtarı yoksa düz metin gönderimi için AÇIK ve
  /// bilgilendirilmiş onay ister. Onay verilmezse mesaj gönderilmez.
  Future<bool> _confirmPlaintextSend() async {
    final app = JuzzioAppController.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.trEn('Şifresiz gönderilsin mi?', 'Send without encryption?', 'Ohne Verschlüsselung senden?')),
        content: Text(app.trEn(
          'Bu kişinin uygulaması uçtan uca şifrelemeyi henüz desteklemiyor. Mesajınız ŞİFRELENMEDEN gönderilir ve sohbette "şifresiz" olarak işaretlenir. Juzzio sunucusu bu mesajın içeriğini görebilir.',
          'This person\'s app does not support end-to-end encryption yet. Your message will be sent WITHOUT encryption and marked as "unencrypted" in the chat. The Juzzio server can see its content.',
          'Die App dieser Person unterstützt noch keine Ende-zu-Ende-Verschlüsselung. Deine Nachricht wird OHNE Verschlüsselung gesendet und im Chat als „unverschlüsselt“ markiert. Der Juzzio-Server kann den Inhalt sehen.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.trEn('Şifresiz gönder', 'Send unencrypted', 'Unverschlüsselt senden'))),
        ],
      ),
    );
    return ok == true;
  }

  /// v1.2.2: giden metin balonunun yazı stili — balon ve uçuş AYNI stili kullanır (font değişimi olmaz)
  TextStyle _outgoingBubbleTextStyle(JuzzioPalette p) => TextStyle(
        fontFamily: JuzzioConfig.fontRegularBold,
        color: Colors.white,
        fontSize: 14.5 * JuzzioAppController.instance.messageFontScale,
        fontWeight: FontWeight.w700,
        height: 1.35,
      );

  /// v1.2.2 (#06 Input morph + #07 Droplet): yazma kutusundaki metin gerçek balona uçar.
  /// Büyük emoji (kendi "Pop" girişi), yanıt alıntısı ve kart biçimli mesajlarda uçuş yok.
  void _launchSendFlight(String txt, String clientMsgId, {required bool hasReply}) {
    if (hasReply || juzzioBigEmojiCount(txt) > 0) return;
    if (juzzioParseContactCard(txt) != null || juzzioParseLocation(txt) != null) return;
    final ctx = _composerFieldKey.currentContext;
    if (ctx == null) return;
    final from = juzzioGlobalRect(ctx);
    if (from == null) return;
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    JuzzioSendFlight.launch(
      context,
      key: clientMsgId,
      from: from,
      text: txt,
      style: JuzzioSendFlightStyle(
        textStyle: _outgoingBubbleTextStyle(p),
        bubbleColor: p.outgoingBubble,
        composerColor: p.inputBg,
        composerTextColor: p.textPrimary,
      ),
    );
  }

  Future<void> _sendText() async {
    final txt = _msgCtrl.text.trim();
    final roomId = _activeConversationRoomId;
    if (txt.isEmpty || roomId == null) return;
    final replyTarget = _replyingTo;
    _msgCtrl.clear();
    // Aynı gönderimin yeniden denemeleri aynı kimliği taşır (çift mesaj oluşmaz)
    final clientMsgId = SupabaseService.newClientMsgId();
    // v1.0.0: bekleme yok — balon anında görünür (saat simgesiyle), çeviri sonra gelir
    setState(() {
      _replyingTo = null;
      _outbox[clientMsgId] = JuzzioMessage(
        id: 'local_$clientMsgId',
        roomId: roomId,
        senderId: SupabaseService.instance.currentUserId ?? '',
        senderName: _myProfile?.displayName ?? widget.myDisplayName,
        messageType: 'text',
        sourceLang: JuzzioAppController.instance.subtitleLang,
        targetLang: '',
        originalText: txt,
        translatedText: '',
        replyToId: replyTarget?.id,
        metadata: const {'local_pending': true},
        createdAt: DateTime.now(),
        clientMsgId: clientMsgId,
      );
    });
    // v1.2.2: yazma kutusundan balona uçuş geri geldi (balonla aynı yazı tipi/renk, gerçek balona iner)
    _launchSendFlight(txt, clientMsgId, hasReply: replyTarget != null);
    _scrollMessagesToBottom(force: true);
    void dropLocal() {
      if (mounted && _outbox.remove(clientMsgId) != null) setState(() {});
    }
    Future<void> send({bool allowPlaintext = false}) => SupabaseService.instance.sendTextMessage(
          text: txt,
          sourceLang: JuzzioAppController.instance.subtitleLang,
          senderName: _myProfile?.displayName ?? widget.myDisplayName,
          targetRoomId: roomId,
          replyToId: replyTarget?.id,
          clientMsgId: clientMsgId,
          allowPlaintextFallback: allowPlaintext,
        );
    try {
      try {
        await send();
      } on JuzzioE2eeRequiredException catch (e) {
        if (e.status != JuzzioE2eeStatus.peerKeyMissing || !mounted) rethrow;
        if (!await _confirmPlaintextSend()) {
          dropLocal();
          _msgCtrl.text = txt;
          if (mounted && replyTarget != null) setState(() => _replyingTo = replyTarget);
          return;
        }
        await send(allowPlaintext: true);
      }
      // Akış kaydı getirmezse (bağlantı kopması) yerel kopya kalıcı olmasın
      Timer(const Duration(seconds: 20), dropLocal);
    } catch (e) {
      dropLocal();
      _msgCtrl.text = txt;
      if (mounted && replyTarget != null) setState(() => _replyingTo = replyTarget);
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  bool _isGroupRoomId(String roomId) =>
      _groupRooms.any((g) => g.id == roomId) || (_activeGroupRoom != null && _activeGroupRoom!.id == roomId);

  /// v0.9.4: ataş (eklenti) menüsü — belge, galeri, video, konum, kişi kartı, anket, etkinlik, zamanlama
  Future<void> _openAttachMenu() async {
    final roomId = _activeConversationRoomId;
    if (roomId == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _attachMenuOpen = true);
    final choice = await showJuzzioAttachMenu(context, isGroup: _isGroupRoomId(roomId));
    if (mounted) setState(() => _attachMenuOpen = false);
    if (choice == null || !mounted) return;
    await _handleAttachChoice(roomId, choice);
  }

  /// v0.9.4: kamera düğmesi yalnız doğrudan çekim yapar (dokun: fotoğraf · basılı tut: video)
  Future<void> _captureFromCamera({required bool video}) async {
    final roomId = _activeConversationRoomId;
    if (roomId == null) return;
    await _handleAttachChoice(roomId, video ? 'camera_video' : 'camera_photo');
  }

  Future<void> _handleAttachChoice(String roomId, String choice) async {
    final app = JuzzioAppController.instance;
    switch (choice) {
      case 'poll':
        await showJuzzioCreatePollSheet(context, roomId: roomId);
        return;
      case 'event':
        final made = await showJuzzioCreateEventSheet(context, roomId: roomId);
        if (made) _scrollMessagesToBottom(force: true);
        return;
      case 'schedule':
        final done = await showJuzzioScheduleSheet(context, roomId: roomId, text: _msgCtrl.text);
        if (done) {
          _msgCtrl.clear();
          _showSnack(app.trEn('Mesaj zamanlandı', 'Message scheduled', 'Nachricht geplant'));
        }
        return;
      case 'document':
        await _sendDocument(roomId);
        return;
      case 'location':
        await _sendLocation(roomId);
        return;
      case 'contact':
        await _sendContactCard(roomId);
        return;
      case 'view_once':
        // v0.9.5: tek seferlik fotoğraf (galeriden); alıcı bir kez açar, sonra kalıcı silinir
        try {
          final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2048);
          if (picked == null) return;
          await _withUploadIsland(app.trEn('Fotoğraf gönderiliyor', 'Sending photo', 'Foto wird gesendet'), Icons.photo_rounded,
              () => SupabaseService.instance.sendMediaMessage(roomId: roomId, file: File(picked.path), isVideo: false, viewOnce: true));
          _scrollMessagesToBottom(force: true);
        } catch (e) {
          _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
        }
        return;
    }
    try {
      XFile? picked;
      final isVideo = choice.endsWith('video');
      final source = choice.startsWith('camera') ? ImageSource.camera : ImageSource.gallery;
      if (isVideo) {
        picked = await _imagePicker.pickVideo(source: source, maxDuration: Duration(seconds: _videoMaxSeconds));
      } else {
        // v0.9.5: düşük veri modunda fotoğraf küçültülür
        final saver = app.dataSaverEnabled;
        picked = await _imagePicker.pickImage(source: source, imageQuality: saver ? 70 : 85, maxWidth: saver ? 1280 : 2048);
      }
      if (picked == null) return;
      final caption = _msgCtrl.text.trim();
      final file = File(picked.path);
      _msgCtrl.clear();
      // v1.2.4: bekletme yok — fotoğraf/video ANINDA sohbette görünür, yükleme arka planda sürer
      final cid = _queueLocalMedia(roomId, kind: isVideo ? 'video' : 'image', path: file.path, caption: caption);
      unawaited(_uploadInBackground(
        cid,
        isVideo ? app.trEn('Video gönderiliyor', 'Sending video', 'Video wird gesendet') : app.trEn('Fotoğraf gönderiliyor', 'Sending photo', 'Foto wird gesendet'),
        isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
        () => SupabaseService.instance.sendMediaMessage(roomId: roomId, file: file, isVideo: isVideo, caption: caption, clientMsgId: cid),
      ));
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  /// v1.2.4: gönderilen medya için anında görünen yerel balon (saat simgesiyle). Sunucu kaydı aynı
  /// client_msg_id ile gelince yerel kopya kendiliğinden kalkar.
  String _queueLocalMedia(String roomId, {required String kind, required String path, String caption = '', String? name, int size = 0}) {
    final cid = SupabaseService.newClientMsgId();
    setState(() {
      _outbox[cid] = JuzzioMessage(
        id: 'local_$cid',
        roomId: roomId,
        senderId: SupabaseService.instance.currentUserId ?? '',
        senderName: _myProfile?.displayName ?? widget.myDisplayName,
        messageType: kind,
        sourceLang: JuzzioAppController.instance.subtitleLang,
        targetLang: '',
        originalText: caption,
        translatedText: '',
        imageUrl: kind == 'image' ? path : null,
        videoUrl: kind == 'video' ? path : null,
        documentUrl: kind == 'document' ? path : null,
        documentName: name,
        documentSize: size,
        metadata: const {'local_pending': true},
        createdAt: DateTime.now(),
        clientMsgId: cid,
      );
    });
    _scrollMessagesToBottom(force: true);
    return cid;
  }

  /// Yüklemeyi arka planda yapar; hata olursa yerel balon kaldırılır ve kullanıcıya söylenir.
  Future<void> _uploadInBackground(String cid, String label, IconData icon, Future<void> Function() job, {VoidCallback? onDone}) async {
    try {
      await _withUploadIsland(label, icon, job);
    } catch (e) {
      if (mounted && _outbox.remove(cid) != null) setState(() {});
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    } finally {
      onDone?.call();
    }
  }

  /// v1.1.0 Live Activity: yükleme sürerken üstte canlı durum kapsülü (sayfadan çıkılsa da görünür)
  Future<T> _withUploadIsland<T>(String label, IconData icon, Future<T> Function() job) async {
    final id = 'upload_${DateTime.now().microsecondsSinceEpoch}';
    JuzzioIsland.instance.set(JuzzioIslandActivity(id: id, icon: icon, label: label));
    try {
      final r = await job();
      JuzzioHaptics.success();
      return r;
    } finally {
      JuzzioIsland.instance.clear(id);
    }
  }

  Future<void> _sendDocument(String roomId) async {
    final app = JuzzioAppController.instance;
    try {
      // file_picker 13: statik API; iptalde null döner
      final PlatformFile? f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return;
      final size = f.lengthSync() ?? await f.length() ?? 0;
      if (size > juzzioDocumentMaxBytes) {
        _showSnack(app.trEn('Dosya en fazla 25 MB olabilir.', 'Files must be under 25 MB.', 'Dateien dürfen höchstens 25 MB groß sein.'), isError: true);
        return;
      }
      // Android SAF bazen content:// URI döndürür (yerel yol yok) → baytları geçici dosyaya yaz
      File file;
      File? temp;
      final localPath = f.path;
      if (localPath != null) {
        file = File(localPath);
      } else {
        final safeName = f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        temp = File('${Directory.systemTemp.path}/juzzio_doc_${DateTime.now().microsecondsSinceEpoch}_$safeName');
        await temp.writeAsBytes(await f.readAsBytes(), flush: true);
        file = temp;
      }
      // v1.2.4: belge anında sohbette görünür; yükleme arka planda
      final cid = _queueLocalMedia(roomId, kind: 'document', path: file.path, name: f.name, size: size);
      final tmp = temp;
      unawaited(_uploadInBackground(
        cid,
        app.trEn('Belge gönderiliyor', 'Sending document', 'Dokument wird gesendet'),
        Icons.description_rounded,
        () => SupabaseService.instance.sendDocumentMessage(roomId: roomId, file: file, fileName: f.name, clientMsgId: cid),
        onDone: () {
          if (tmp != null) unawaited(tmp.delete().then((_) {}, onError: (_) {}));
        },
      ));
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _sendLocation(String roomId) async {
    final app = JuzzioAppController.instance;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack(app.trEn('Konum servisi kapalı. Lütfen açın.', 'Location services are off. Please turn them on.', 'Standortdienste sind aus. Bitte einschalten.'), isError: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showSnack(app.trEn('Konum izni verilmedi.', 'Location permission was not granted.', 'Standortberechtigung wurde nicht erteilt.'), isError: true);
        return;
      }
      _showSnack(app.trEn('Konum alınıyor...', 'Getting location...', 'Standort wird ermittelt...'));
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      // Metin olarak gönderilir → birebir sohbette uçtan uca şifrelenir (sunucu konumu görmez)
      await SupabaseService.instance.sendTextMessage(text: juzzioLocationMessageText(pos.latitude, pos.longitude, app), targetRoomId: roomId);
      _scrollMessagesToBottom(force: true);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _sendContactCard(String roomId) async {
    final app = JuzzioAppController.instance;
    final friends = _acceptedFriendProfiles;
    if (friends.isEmpty) {
      _showSnack(app.trEn('Paylaşılacak arkadaş yok.', 'No friends to share.', 'Keine Freunde zum Teilen.'));
      return;
    }
    final picked = await showJuzzioSheet<JuzzioUserProfile>(
      context: context,
      backgroundColor: JuzzioPalette(app.isDark).sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(app.trEn('Kişi kartı paylaş', 'Share a contact', 'Kontakt teilen'), style: const TextStyle(fontWeight: FontWeight.w800))),
            for (final f in friends)
              ListTile(
                leading: JuzzioUserAvatar(imageUrl: f.avatarUrl, displayName: f.displayName, radius: 20),
                title: Text(f.displayName.isNotEmpty ? f.displayName : f.username),
                subtitle: Text('@${f.username}'),
                onTap: () => Navigator.pop(ctx, f),
              ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await SupabaseService.instance.sendTextMessage(text: juzzioContactCardText(picked, app), targetRoomId: roomId);
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
        RecordConfig(encoder: AudioEncoder.aacLc, bitRate: _audioBitrateKbps * 1000, sampleRate: 44100),
        path: outPath,
      );
      _voiceUiTimer?.cancel();
      _voiceUiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _isRecordingVoice) setState(() {});
        // Azami süre dolunca kayıt otomatik bitip gönderilir
        if (_isRecordingVoice && _voiceElapsed.inSeconds >= _voiceMaxSeconds) {
          _voiceUiTimer?.cancel();
          unawaited(_stopAndSendVoiceRecording());
        }
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
      JuzzioChatActivityService.instance.setLocal(JuzzioActivityState.recording);
      // v1.1.0 Live Activity: üstte süre sayan kayıt kapsülü
      JuzzioIsland.instance.set(JuzzioIslandActivity(
        id: 'voice_rec',
        icon: Icons.mic_rounded,
        label: JuzzioAppController.instance.trEn('Ses kaydediliyor', 'Recording', 'Aufnahme'),
        color: JuzzioColors.red500,
        startedAt: DateTime.now(),
      ));
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
    JuzzioIsland.instance.clear('voice_rec');
    if (!_isRecordingVoice) return;
    HapticFeedback.lightImpact();
    JuzzioChatActivityService.instance.setLocal(JuzzioActivityState.idle);
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
    JuzzioIsland.instance.clear('voice_rec');
    JuzzioChatActivityService.instance.setLocal(JuzzioActivityState.idle);
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

      await _withUploadIsland(
        JuzzioAppController.instance.trEn('Sesli mesaj gönderiliyor', 'Sending voice message', 'Sprachnachricht wird gesendet'),
        Icons.graphic_eq_rounded,
        () => SupabaseService.instance.sendVoiceNote(
          audioFile: file,
          durationMs: durationMs,
          sourceLang: JuzzioAppController.instance.subtitleLang,
          waveformPeaks: peaks,
          targetRoomId: _activeConversationRoomId,
        ),
      );
      _scrollMessagesToBottom(force: true);
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  static const List<double> _voiceSpeeds = [1.0, 1.5, 2.0];
  double _voiceSpeed = 1.0;

  Future<void> _cycleVoiceSpeed() async {
    final i = _voiceSpeeds.indexOf(_voiceSpeed);
    setState(() => _voiceSpeed = _voiceSpeeds[(i + 1) % _voiceSpeeds.length]);
    try {
      await _audioPlayer.setSpeed(_voiceSpeed);
    } catch (_) {}
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
      // v0.9.0: sesli mesajlar özel bucket'ta — kısa ömürlü imzalı adresle oynatılır
      // v0.9.2: dinlenen sesli mesaj diske alınır → internet yokken de çalar
      // v0.9.6: şifreli sesli mesaj cihazda çözülür, geçici dosyadan çalınır
      final encrypted = JuzzioEncryptedMedia.isEncrypted(msg.metadata);
      final local = encrypted ? null : await JuzzioMediaDiskCache.instance.loadFile(msg.audioUrl!);
      if (encrypted) {
        final bytes = await JuzzioEncryptedMedia.load(msg.id, msg.audioUrl!, keepInMemory: false);
        if (bytes == null) throw Exception('decrypt_failed');
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/jvn_${msg.id}.m4a');
        if (!f.existsSync()) await f.writeAsBytes(bytes, flush: true);
        await _audioPlayer.setFilePath(f.path);
      } else if (local != null) {
        await _audioPlayer.setFilePath(local.path);
      } else {
        await _audioPlayer.setUrl(await JuzzioMediaUrl.resolve(msg.audioUrl!));
      }
      await _audioPlayer.setSpeed(_voiceSpeed);
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
    if (_isInCall && JuzzioActiveCall.instance.isActive) {
      // v0.9.3: zaten bir görüşmedeyken yeni arama yerine süren arama büyütülür
      JuzzioActiveCall.instance.expand();
      return;
    }
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
      // v0.9.3: arama katmanda yaşar (küçültülebilir, PiP); arama bitince tamamlanır
      await JuzzioActiveCall.instance.start(
        context,
        title: partnerName,
        avatarUrl: targetPartnerAvatar ?? _resolveAvatar(partnerId),
        isVideo: enableVideo,
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
    if (juzzioIsCommunityTitle(group.title)) return; // v1.2.6: resmî duyuru kanalında arama yok
    if (_isInCall && JuzzioActiveCall.instance.isActive) {
      // v0.9.3: zaten bir görüşmedeyken yeni arama yerine süren arama büyütülür
      JuzzioActiveCall.instance.expand();
      return;
    }
    if (uid == null || _isInCall) return;
    final myName = _myProfile?.displayName ?? widget.myDisplayName;
    try {
      final session = await SupabaseService.instance.startCall(roomId: group.id, isVideo: isVideo);
      if (!mounted) return;
      final memberProfiles = _allProfiles.where((p) => group.groupMemberIds.contains(p.id)).toList();
      _isInCall = true;
      await JuzzioActiveCall.instance.start(
        context,
        title: group.title,
        avatarUrl: null,
        isVideo: isVideo,
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
      await JuzzioActiveCall.instance.start(
        context,
        title: call.isGroup ? (call.groupTitle.isNotEmpty ? call.groupTitle : (group?.title ?? call.callerName)) : call.callerName,
        avatarUrl: call.isGroup ? null : call.callerAvatar,
        isVideo: call.isVideo,
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
    final sameUser = _visibleFriendStories24h
        .where((s) => story.isOfficial ? s.isOfficial : (s.userId == story.userId && !s.isOfficial))
        .toList()
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
          // v0.9.3: hikâye başlığındaki isme/fotoğrafa dokununca paylaşanın profili
          onOpenProfile: (uid) => _openUserProfilePage(uid),
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
    await showJuzzioSheet(
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
                        color: p.textMuted.withValues(alpha: 0.4),
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

  /// v0.9.0 Faz 2: sistem geri hareketi. Kararı saf durum makinesi verir.
  void _handleSystemBack() {
    final action = _backNav.decide(
      insideConversation: _isInsideConversation,
      emojiPanelOpen: _showEmojiPanel,
      selectedTab: _selectedBottomTab,
      chatFilter: _selectedFilterIndex,
    );
    switch (action) {
      case JuzzioBackAction.closeEmojiPanel:
        setState(() => _showEmojiPanel = false);
        break;
      case JuzzioBackAction.leaveConversation:
        _leaveConversation();
        break;
      case JuzzioBackAction.goToHomeTab:
        setState(() => _selectedBottomTab = JuzzioBackNavigator.homeTab);
        break;
      case JuzzioBackAction.resetChatFilter:
        setState(() => _selectedFilterIndex = JuzzioBackNavigator.defaultFilter);
        break;
      case JuzzioBackAction.showExitHint:
        _exitHintTimer?.cancel();
        setState(() => _exitHintVisible = true);
        _exitHintTimer = Timer(_backNav.exitWindow, () {
          if (mounted) setState(() => _exitHintVisible = false);
        });
        break;
      case JuzzioBackAction.exitApp:
        _exitHintTimer?.cancel();
        _exitHintVisible = false;
        SystemNavigator.pop();
        break;
    }
  }

  /// Engellemeyen (IgnorePointer) "çıkmak için tekrar basın" ipucu; ekran okuyucuya canlı bölge.
  Widget _buildExitHint(JuzzioPalette p, JuzzioAppController appCtrl) {
    final text = appCtrl.trEn('Çıkmak için tekrar geri basın', 'Press back again to exit', 'Zum Beenden erneut zurück drücken');
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _exitHintVisible ? 1 : 0,
        duration: Duration(milliseconds: appCtrl.reduceMotion ? 0 : 180),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Semantics(
              liveRegion: true,
              label: _exitHintVisible ? text : null,
              child: ExcludeSemantics(
                child: JuzzioGlass(
                  radius: 999,
                  blur: !appCtrl.reduceMotion,
                  blurSigma: JuzzioGlassTokens.blurNavigation,
                  color: appCtrl.isDark ? JuzzioColors.surface.withValues(alpha: 0.92) : const Color(0xF2FFFFFF),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final s = JuzzioStrings(appCtrl.uiLang);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
      backgroundColor: p.headerDarkForest,
      bottomNavigationBar: _isInsideConversation
          ? null
          : _buildFloatingGlassBottomDock(p, s),
      body: Stack(
        children: [
          Positioned.fill(child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (appCtrl.otaUpdateAvailable) _buildOtaUpdateTopBanner(p, appCtrl),
            if (!_isInsideConversation && JuzzioFeaturesService.instance.lastAppConfig.announcementBanner.trim().isNotEmpty)
              _buildAnnouncementBanner(JuzzioFeaturesService.instance.lastAppConfig.announcementBanner.trim()),
            if (_incomingCallBannerVisible) _buildIncomingCallBanner(p, s),
            if (_headsUpFriendRequest != null) _buildIncomingFriendRequestBanner(p, s),
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: appCtrl.reduceMotion ? 0 : 220),
                child: _isInsideConversation
                    ? _buildActiveConversationView(p, s, appCtrl)
                    : _selectedBottomTab == 6
                        ? JuzzioNotificationsFeedPage(
                            key: const ValueKey('juzzio_notifications_tab'),
                            currentUser: _effectiveCurrentUserProfile,
                            embedded: true,
                            onOpenItem: _openNotificationItemFromTab,
                          )
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
      )),
          if (!_isInsideConversation) Positioned.fill(child: _buildExitHint(p, appCtrl)),
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

  /// v1.2.0: Kilitli sohbetler sayfası
  void _openLockedChats() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JuzzioLockedChatsPage(
        conversations: _conversations.where((c) => !_deletedConversationIds.contains(c.roomId)).toList(),
        onOpen: (c) => _openRoomById(c.roomId),
      ),
    ));
  }

  /// v1.2.0: bir sohbetin içindeyken arama YALNIZ o sohbette yapılır; sonuca dokununca
  /// sohbet açılır ve mesaja kaydırılıp vurgulanır.
  void _openMessageSearch({String? inRoomId}) {
    final rooms = <(String, String)>[
      for (final c in _conversations) (c.roomId, c.isGroup ? c.title : (c.partnerDisplayName ?? c.partnerUsername ?? c.title)),
    ];
    final scope = inRoomId ?? (_isInsideConversation ? _activeConversationRoomId : null);
    if (scope != null && !rooms.any((r) => r.$1 == scope)) {
      rooms.insert(0, (scope, _activeGroupRoom?.title ?? _activeFriendPartner?.displayName ?? JuzzioAppController.instance.trEn('Bu sohbet', 'This chat', 'Dieser Chat')));
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JuzzioMessageSearchPage(
        rooms: rooms,
        initialRoomId: scope,
        onOpenRoom: _openRoomById,
        onOpenMessage: (roomId, messageId) async {
          if (!_isInsideConversation || _activeConversationRoomId != roomId) await _openRoomById(roomId);
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (mounted) await _jumpToMessage(messageId);
        },
      ),
    ));
  }

  /// v0.9.0 N-B: etiket bildirimi → gönderi görünürse gönderi (RLS), değilse etiketleyenin profili.
  Future<void> _openMentionTarget(String targetId, String actorId) async {
    final post = targetId.isEmpty ? null : await JuzzioSocialService.instance.fetchPostById(targetId);
    if (!mounted) return;
    if (post != null) {
      await _openPostDetail(post, focusComments: true);
    } else if (actorId.isNotEmpty) {
      await _openUserProfilePage(actorId);
    } else {
      _openNotificationsScreen();
    }
  }

  /// v1.2.4: sohbete iletilen gönderi/hikâye bağlantısını açar
  Future<void> _openSharedRef((String, String) ref) async {
    final app = JuzzioAppController.instance;
    if (ref.$1 == 'post') {
      final post = await JuzzioSocialService.instance.fetchPostById(ref.$2).catchError((_) => null);
      if (!mounted) return;
      if (post == null) {
        _showSnack(app.trEn('Gönderi bulunamadı ya da kaldırılmış.', 'Post not found or removed.', 'Beitrag nicht gefunden.'), isError: true);
        return;
      }
      await _openPostDetail(post);
      return;
    }
    final story = _activeStories.where((st) => st.id == ref.$2 && !st.isExpired).firstOrNull;
    if (story == null) {
      _showSnack(app.trEn('Bu hikâyenin süresi dolmuş.', 'This story has expired.', 'Diese Story ist abgelaufen.'), isError: true);
      return;
    }
    _openStoryViewer(story);
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
    // v0.9.3: görüşme sırasında bildirime dokunuldu → arama küçülür (kesilmez), sohbet açılır
    if (JuzzioActiveCall.instance.isActive && payload.eventType != 'incoming_call') {
      JuzzioActiveCall.instance.minimize();
    }
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
    // v0.9.0 N-B: gönderi/yorum etiketi → gönderi (hikâye etiketi → etiketleyen profil)
    if (et == 'mention') {
      _openMentionTarget(payload.targetId, payload.actorId);
      return;
    }
    // v0.9.0 §4.1/§4.2: hatırlatma → mesaj hatırlatıcısıysa sohbet (hedef = oda, ikincil = mesaj), görevse Yaşam Merkezi
    if (et == 'reminder') {
      if (payload.targetId.isNotEmpty && payload.targetSecondaryId.isNotEmpty && payload.targetId != payload.targetSecondaryId) {
        _openRoomById(payload.targetId);
      } else {
        JuzzioLifeCenterPage.open(context);
      }
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
      // v0.9.0 N-F: bildirimdeki "Kabul" → bu çağrı kimliği çalıyorsa hemen cevapla; akış henüz
      // gelmediyse (soğuk açılış) 30 sn içinde gelince cevaplanır. Sunucu yine doğrular.
      if (payload.callAction == 'accept' && payload.targetSecondaryId.isNotEmpty) {
        _pendingAcceptCallId = payload.targetSecondaryId;
        _pendingAcceptAt = DateTime.now();
        final current = _incomingCall;
        if (current != null && _takePendingAccept(current.id)) _acceptIncomingCall();
      }
      // Aksi hâlde çalan arama başlığı call_logs akışından otomatik gösterilir.
      return;
    }
    if ((et == 'message' || et == 'group_activity' || et == 'story_reply' || et == 'reaction') && payload.targetId.isNotEmpty) {
      _openRoomById(payload.targetId);
      return;
    }
    _openNotificationsScreen();
  }

  /// v0.9.0: Bildirimler sekmesinde yerinde açılamayan öğe (mesaj, arama) → ilgili sohbet/sekme.
  void _openNotificationItemFromTab(JuzzioNotificationItem item) {
    final type = item.eventType;
    // v0.9.5
    if (type == 'watch_party' && item.targetId.isNotEmpty) {
      JuzzioWatchPartyScreen.open(context, item.targetId);
      return;
    }
    if ((type == 'sos' || type == 'poll_closed') && item.targetId.isNotEmpty) {
      _openRoomById(item.targetId);
      return;
    }
    if (type == 'qa_question') {
      JuzzioQaInboxScreen.open(context);
      return;
    }
    if (type == 'qa_answer' && item.targetId.isNotEmpty) {
      _openUserProfilePage(item.targetId);
      return;
    }
    if (type == 'reminder' && item.previewText.startsWith('event|') && item.targetId.isNotEmpty) {
      _openRoomById(item.targetId);
      return;
    }
    if (type == 'reminder') {
      if (item.previewText.startsWith('message|') && item.targetId.isNotEmpty) {
        _openRoomById(item.targetId);
      } else {
        JuzzioLifeCenterPage.open(context);
      }
      return;
    }
    if (type.contains('call')) {
      setState(() => _selectedBottomTab = 1);
      return;
    }
    if (type.contains('message') && item.targetId.isNotEmpty) {
      _openRoomById(item.targetId);
      return;
    }
    setState(() => _selectedBottomTab = 0);
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
              child: JuzzioSparklerBar(
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
            color: Colors.black.withValues(alpha: 0.14),
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
                  color: p.accentDeep,
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
                      backgroundColor: JuzzioColors.emerald500,
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
            backgroundColor: p.accentDeep,
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
              backgroundColor: p.coolButtonBg,
              foregroundColor: p.coolButtonFg,
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

  Widget _buildChatsHomeTab(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    final stories24h = _visibleFriendStories24h;
    final myDisplay = _myProfile?.displayName ?? widget.myDisplayName;
    final myUid = SupabaseService.instance.currentUserId;
    final realFriends = _acceptedFriendProfiles;

    // v0.5.0: halka yalnızca aktif (24 saat) hikâyesi olan kişide görünür
    final myHasStory = myUid != null && stories24h.any((st) => st.userId == myUid && !st.isOfficial);
    // v0.9.3: "Juzzio Official" hikâyeleri herkeste ilk sırada, ayrı halkada
    final officialStories = stories24h.where((st) => st.isOfficial).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final officialSeen = officialStories.isNotEmpty && JuzzioStorySeen.instance.allSeen(officialStories.map((e) => e.id).toList());
    final storyOwners = <String, JuzzioStory>{};
    final storyIdsByOwner = <String, List<String>>{};
    for (final st in stories24h) {
      if (st.userId == myUid || st.isOfficial) continue;
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

    final totalUnread = _conversations.fold<int>(0, (sum, c) => sum + (c.isMuted ? 0 : c.unreadCount));
    final anyFriendOnline = realFriends.any((f) => f.isEffectivelyOnline);
    final filters = <(String, IconData?, int)>[
      (appCtrl.trEn('Tümü', 'All', 'Alle'), null, 0),
      (appCtrl.trEn('Kişiler', 'Contacts', 'Kontakte'), null, 1),
      (appCtrl.trEn('Gruplar', 'Groups', 'Gruppen'), Icons.group_outlined, 2),
    ];
    Widget storyPhoto(String? url, String name) => JuzzioSpacePhoto(url: url, name: name, size: JuzzioSpaceMetrics.storyAvatar);

    // v1.0.0 Juzzio Space (Figma): sabit başlık + arama, altında kayan hikâyeler, INBOX ve kartlar.
    // Kumaş "aşağı çek-yenile" tüm sekmeyi sarar: başlık da aşağı kayar, el boş alanda sallanır.
    return JuzzioClothRefresh(
      onRefresh: _refreshConversationsNow,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JuzzioSpaceHeader(
          eyebrow: appCtrl.trEn('Senin alanın', 'Your space', 'Dein Bereich'),
          title: const JuzzioSpaceBrand(),
          actions: [
            JuzzioSpaceIconButton(
              icon: Icons.person_outline_rounded,
              dotColor: anyFriendOnline ? JuzzioGlassTokens.glow : null,
              badgeCount: _pendingIncomingRequests.length,
              tooltip: appCtrl.trEn('Arkadaşlar ve istekler', 'Friends and requests', 'Freunde und Anfragen'),
              onTap: _showFriendSearchAndRequestsSheet,
            ),
            JuzzioSpaceIconButton(
              icon: Icons.notifications_none_rounded,
              badgeCount: bellCount,
              tooltip: appCtrl.trEn('Bildirimler', 'Notifications', 'Benachrichtigungen'),
              onTap: _openNotificationsScreen,
            ),
            JuzzioSpaceComposeButton(
              tooltip: appCtrl.trEn('Yeni mesaj', 'New message', 'Neue Nachricht'),
              onTap: _openNewMessageScreen,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(JuzzioSpaceMetrics.gutter, 0, JuzzioSpaceMetrics.gutter, 16),
          child: JuzzioSpaceSearchBar(
            hint: appCtrl.trEn('Sohbetlerde ara', 'Search conversations', 'Unterhaltungen durchsuchen'),
            onChanged: (v) => setState(() => _searchQuery = v),
            // ⌘K: gelişmiş mesaj araması (filtreler, şifreli içerik cihazda aranır)
            onShortcutTap: _openMessageSearch,
          ),
        ),
        const JuzzioSpaceDivider(),
        Expanded(
          child: !_conversationsLoaded
              ? const JuzzioConversationListSkeleton()
              : Builder(
                  builder: (context) {
                              final showPeople = _selectedFilterIndex == 0 || _selectedFilterIndex == 1;
                              final showGroups = _selectedFilterIndex == 0 || _selectedFilterIndex == 2;
                              // v0.9.0 §4.6: kilitli sohbetler listede gizli; "Kilitli sohbetler" görünümünde yalnız onlar
                              final lockSvc = JuzzioChatLock.instance;
                              final lockedCount = _conversations.where((c) => lockSvc.isLocked(c.roomId)).length;
                              final convs = _conversations
                                  .where((c) => c.isGroup ? showGroups : showPeople)
                                  .where((c) => !_deletedConversationIds.contains(c.roomId))
                                  .where((c) => _showLockedChats ? lockSvc.isLocked(c.roomId) : !lockSvc.isLocked(c.roomId))
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
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 28),
                        children: [
                          SizedBox(
                            height: JuzzioSpaceMetrics.storyAvatar + 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: [
                                JuzzioSpaceStoryAvatar(
                                  label: appCtrl.trEn('Durumum', 'My status', 'Mein Status'),
                                  avatar: storyPhoto(_myProfile?.avatarUrl, myDisplay),
                                  ring: myHasStory ? JuzzioSpaceRing.story : JuzzioSpaceRing.mine,
                                  plus: true,
                                  onPlusTap: _showCreateStorySheet,
                                  onTap: () {
                                    final myStories = stories24h.where((st) => st.userId == myUid && !st.isOfficial).toList();
                                    if (myStories.isNotEmpty) {
                                      _openStoryViewer(myStories.first);
                                    } else {
                                      _showCreateStorySheet();
                                    }
                                  },
                                  onLongPress: _showCreateStorySheet,
                                ),
                                if (officialStories.isNotEmpty)
                                  JuzzioSpaceStoryAvatar(
                                    label: 'Juzzio',
                                    avatar: const JuzzioOfficialAvatar(radius: 31),
                                    ring: officialSeen ? JuzzioSpaceRing.seen : JuzzioSpaceRing.story,
                                    badge: const CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Icon(Icons.verified_rounded, color: Color(0xFF1D9BF0), size: 18)),
                                    onTap: () => _openStoryViewer(
                                      officialStories.firstWhere((st) => !JuzzioStorySeen.instance.isSeen(st.id), orElse: () => officialStories.first),
                                    ),
                                  ),
                                ...([...storyOwners.values]..sort((a, b) => (seenOwners.contains(a.userId) ? 1 : 0) - (seenOwners.contains(b.userId) ? 1 : 0))).map((st) {
                                  JuzzioUserProfile? owner;
                                  for (final f in _allProfiles) {
                                    if (f.id == st.userId) owner = f;
                                  }
                                  final name = owner?.displayName ?? st.displayName;
                                  return JuzzioSpaceStoryAvatar(
                                    label: name.split(' ').first,
                                    avatar: storyPhoto(owner?.avatarUrl ?? st.userAvatar, name),
                                    ring: seenOwners.contains(st.userId) ? JuzzioSpaceRing.seen : JuzzioSpaceRing.story,
                                    online: owner?.isEffectivelyOnline ?? false,
                                    onTap: () => _openStoryViewer(st),
                                  );
                                }),
                                // v1.2.4: durum paylaşmayan arkadaşlar durum şeridinde GÖSTERİLMEZ;
                                // yalnız aktif (24 saatlik) durumu olanlar görünür.
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          JuzzioSpaceSectionHeader(
                            eyebrow: appCtrl.trEn('Gelen kutusu', 'Inbox', 'Posteingang'),
                            title: appCtrl.trEn('Mesajlar', 'Messages', 'Nachrichten'),
                            moreTooltip: appCtrl.trEn('Diğer seçenekler', 'More options', 'Weitere Optionen'),
                            onMore: () => _showInboxMoreMenu(p, s, appCtrl, lockedCount),
                            moreOpen: _inboxMenuOpen,
                          ),
                          SizedBox(
                            height: JuzzioSpaceMetrics.pillHeight + 6,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filters.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final f = filters[i];
                                return Center(
                                  child: JuzzioSpaceFilterPill(
                                    label: f.$1,
                                    icon: f.$2,
                                    count: f.$3 == 0 ? totalUnread : 0,
                                    selected: _selectedFilterIndex == f.$3,
                                    onTap: () => setState(() => _selectedFilterIndex = f.$3),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (lockedCount > 0 || _showLockedChats)
                            ListTile(
                              leading: Icon(_showLockedChats ? Icons.lock_open_rounded : Icons.lock_rounded, color: p.textPrimary),
                              title: Text(
                                _showLockedChats
                                    ? appCtrl.trEn('Kilitli sohbetler — kapat', 'Locked chats — close', 'Gesperrte Chats — schließen')
                                    : appCtrl.trEn('Kilitli sohbetler ($lockedCount)', 'Locked chats ($lockedCount)', 'Gesperrte Chats ($lockedCount)'),
                                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
                              ),
                              onTap: () {
                                if (_showLockedChats) {
                                  setState(() => _showLockedChats = false);
                                  return;
                                }
                                _openLockedChats();
                              },
                            ),
                          if (requestConvs.isNotEmpty && !_showLockedChats) _buildMessageRequestsTile(p, appCtrl, requestConvs),
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
                              // v1.2.6: Juzzio Community resmî kanal → onay rozeti
                              isVerified: (!c.isGroup && c.partnerIsVerified) || c.isCommunity,
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
                        ],
                      );
                  },
                ),
        ),
      ],
      ),
    );
  }

  /// v1.0.0: INBOX "⋯" menüsü — mesaj araması, arkadaşlar, yeni grup/kanal, kilitli sohbetler
  Future<void> _showInboxMoreMenu(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl, int lockedCount) async {
    setState(() => _inboxMenuOpen = true);
    final choice = await showJuzzioSheet<String>(
      context: context,
      backgroundColor: JuzzioGlassTokens.sheet,
      builder: (ctx) {
        Widget tile(String id, IconData icon, String label) => ListTile(
              leading: Icon(icon, color: JuzzioGlassTokens.glowText),
              title: Text(label, style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.of(ctx).pop(id),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile('search', Icons.manage_search_rounded, appCtrl.trEn('Mesajlarda ara', 'Search messages', 'Nachrichten durchsuchen')),
                tile('friends', Icons.people_alt_outlined, appCtrl.trEn('Arkadaşlar', 'Friends', 'Freunde')),
                tile('group', Icons.group_add_outlined, appCtrl.trEn('Yeni grup', 'New group', 'Neue Gruppe')),
                tile('channel', Icons.campaign_outlined, appCtrl.trEn('Yeni kanal', 'New channel', 'Neuer Kanal')),
                tile('locked', Icons.lock_outline_rounded,
                    lockedCount > 0 ? appCtrl.trEn('Kilitli sohbetler ($lockedCount)', 'Locked chats ($lockedCount)', 'Gesperrte Chats ($lockedCount)') : appCtrl.trEn('Kilitli sohbetler', 'Locked chats', 'Gesperrte Chats')),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) setState(() => _inboxMenuOpen = false);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'search':
        _openMessageSearch();
      case 'friends':
        setState(() => _selectedFilterIndex = 3);
      case 'group':
        _showCreateGroupModal(p, s, isChannel: false);
      case 'channel':
        // v1.2.0: kanal artık grup formunu değil, kendi oluşturma akışını açar
        {
        final ch = await Navigator.of(context).push<JuzzioGroupRoom>(
          MaterialPageRoute(
            builder: (_) => JuzzioCreateChannelPage(
              friends: _acceptedFriendProfiles,
              myName: _myProfile?.displayName ?? widget.myDisplayName,
            ),
          ),
        );
        if (ch != null && mounted) _enterConversation(roomId: ch.id, group: ch);
        }
      case 'locked':
        // v1.2.0: ayrı sayfa — PIN yoksa oluşturur, varsa açar; boşken nasıl kilitleneceğini gösterir
        _openLockedChats();
    }
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
              // v0.9.0: sabit beyaz yerine tema metin rengi (açık temalarda okunur)
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, height: 1.4),
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

    // v1.2.4: yön kilitli — sohbet listesinde dikey kaydırmayı kilitlemez
    return JuzzioHorizontalSwipeDetector(
      onTap: () {
        if (isSwipedLeft) {
          setState(() => _swipedConversationKey = null);
        } else {
          onTap();
        }
      },
      onUpdate: (details) {
        if (details.primaryDelta != null) {
          if (details.primaryDelta! < -6 && _swipedConversationKey != convKey) {
            JuzzioHaptics.threshold(); // v1.1.0: kaydırma eşiği geçildi
            setState(() => _swipedConversationKey = convKey);
          } else if (details.primaryDelta! > 6 && _swipedConversationKey == convKey) {
            setState(() => _swipedConversationKey = null);
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: kJuzzioSpring,
        // v0.7.0: tüm temalarda aynı cam kart dili — eşit radius, ince kristal kenar, eşit aralık
        // v1.0.0 Juzzio Space: buzlu cam kart, vurgu tonlu ince kenar, büyük köşe
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(
          color: isSwipedLeft ? JuzzioGlassTokens.surfaceStrong : JuzzioGlassTokens.spaceCard,
          borderRadius: BorderRadius.circular(JuzzioSpaceMetrics.cardRadius),
          border: Border.all(color: JuzzioGlassTokens.spaceCardBorder, width: 1.2),
        ),
        child: Row(
          children: [
            if (!isSwipedLeft) ...[
              JuzzioSpaceSquircleAvatar(
                online: isOnline && !isGroup2x2,
                badgeIcon: isGroup2x2 ? Icons.group_outlined : null,
                child: JuzzioSpacePhoto(url: avatarUrl, name: title),
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
                            color: JuzzioGlassTokens.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
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
                  const SizedBox(height: 7),
                  if (subtitle == kJuzzioPreviewPending)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 3.5), child: JuzzioSkeletonLine())
                  else
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: JuzzioGlassTokens.textSecondary,
                      fontSize: 14.5,
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
                  const SizedBox(height: 9),
                  // v1.0.0: parlayan vurgu renkli okunmamış sayacı
                  JuzzioSpaceCountBadge(count: unreadCount, muted: isMuted),
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
    // v0.9.7: gri/sabit renkler yerine etkin temanın vurgu ailesi
    final pair = juzzioAvatarGradient(name, JuzzioGlassTokens.accentPair, dark: JuzzioAppController.instance.isDark);
    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.6),
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
    final chickEnabled = activeGroup == null &&
        partnerProfile != null &&
        JuzzioFeaturesService.instance.lastAppConfig.chickGameEnabled;
    if (chickEnabled) _refreshChickStateIfStale();
    final cs = _chickState;
    final eggPartner = partnerProfile;
    final showEgg = chickEnabled &&
        cs != null &&
        eggPartner != null &&
        juzzioChickEggVisible(
          hasChick: cs.hasChick,
          mood: cs.mood,
          chickPartnerId: cs.partnerId,
          chatPartnerId: eggPartner.id,
          hasIncomingInviteFromPartner: cs.invites.any((i) => i.incoming && i.otherName == eggPartner.displayName),
        );

    return Stack(
      children: [
        Positioned.fill(child: _buildConversationBody(p, s, appCtrl, partnerProfile, activeGroup, partnerName, myUid, targetStreamRoomId)),
        if (showEgg) _buildChickEgg(eggPartner),
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
        onTap: () => _openChickGame(partner),
        child: Tooltip(
          message: JuzzioAppController.instance.t('chick_invite_friend'),
          // v1.0.0: emoji yerine prenses dönüşü + cilve yapan vektör civciv
          child: JuzzioChickBadge(
            stage: (_chickState?.stage ?? 1).clamp(1, 3),
            mood: _chickState?.mood ?? 'happy',
            reduceMotion: JuzzioAppController.instance.reduceMotion,
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
        avatarUrl: conv?.avatarUrl,
        isCommunity: (conv?.isCommunity ?? false) || _inCommunity,
        isChannel: conv?.isChannel ?? false,
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
                  icon: JuzzioMorphIcon(kind: JuzzioMorph.menuBack, open: true, animateIn: true, size: 22, color: p.textPrimary),
                ),
                // v0.7.0: fotoğrafa dokun → profil sayfası; ada dokun → kişi bilgisi ve ayarları
                GestureDetector(
                  onTap: () => _onChatHeaderTap(partnerProfile, activeGroup, partnerName, avatar: true),
                  child: Stack(
                  children: [
                    if (activeGroup != null && _inCommunity)
                      _buildUserAvatar(avatarUrl: kJuzzioLogoAvatar, fallbackName: kJuzzioOfficialName, radius: 20, p: p)
                    // v1.2.6: grup/kanal logosu varsa logo, yoksa üye ızgarası
                    else if (activeGroup != null && juzzioHasRoomLogo(_activeConversationData?.avatarUrl))
                      _buildUserAvatar(avatarUrl: _activeConversationData!.avatarUrl, fallbackName: activeGroup.title, radius: 21, p: p)
                    else if (activeGroup != null)
                      _buildGroup2x2AvatarGrid(activeGroup.groupMembers, activeGroup.title)
                    else
                      // v1.1.0 (#09 Shared element): profil sayfasındaki fotoğrafa büyüyerek dönüşür
                      Hero(
                        tag: 'juzzio_avatar_${partnerProfile?.id ?? 'none'}',
                        child: _buildUserAvatar(
                          avatarUrl: partnerProfile?.avatarUrl,
                          fallbackName: partnerName,
                          radius: 21,
                          p: p,
                        ),
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
                          if ((activeGroup != null && _inCommunity) ||
                              (activeGroup == null &&
                              ((partnerProfile?.isVerified ?? false) || (_activeConversationData?.partnerIsVerified ?? false)))) ...[
                            const SizedBox(width: 4),
                            const JuzzioVerifiedTick(size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      ListenableBuilder(
                        listenable: JuzzioChatActivityService.instance,
                        builder: (context, fallback) {
                          final st = JuzzioChatActivityService.instance.resolver.resolve();
                          if (st.kind == JuzzioHeaderStatusKind.recording || st.kind == JuzzioHeaderStatusKind.typing) {
                            return _buildActivityStatusLine(appCtrl, st, activeGroup);
                          }
                          return fallback!;
                        },
                        child: Text(
                        activeGroup != null && _inCommunity
                            // v1.2.6: resmî kanal — üyeler birbirini görmez, üye sayısı gösterilmez
                            ? appCtrl.trEn('Resmî kanal · Yalnız güncelleme duyuruları', 'Official channel · Update announcements only',
                                'Offizieller Kanal · Nur Update-Ankündigungen')
                            : activeGroup != null
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
                      ),
                    ],
                  ),
                  ),
                ),
                // v1.2.6: Juzzio Community resmî kanalında arama yok (sunucu da kapatır)
                if (!(activeGroup != null && _inCommunity))
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
                if (!(activeGroup != null && _inCommunity))
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
                  _buildPinnedBar(p),
                  Expanded(
                    child: targetStreamRoomId == null
                        ? Center(child: JuzzioOrbitLoader(color: p.amberPrimary))
                        : StreamBuilder<List<JuzzioMessage>>(
                            stream: _messagesStreamFor(targetStreamRoomId),
                            builder: (context, snapshot) {
                              final messages = (snapshot.data ?? [])
                                  .where((m) => !_deletedMessageIds.contains(m.id))
                                  .toList();
                              // v1.0.0: henüz sunucudan dönmemiş yerel mesajlar listenin sonunda
                              if (_outbox.isNotEmpty) {
                                final arrived = {for (final m in messages) if (m.clientMsgId != null) m.clientMsgId!};
                                final stale = _outbox.keys.where(arrived.contains).toList();
                                if (stale.isNotEmpty) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    setState(() => stale.forEach(_outbox.remove));
                                  });
                                }
                                messages.addAll(_outbox.values.where((m) => m.roomId == targetStreamRoomId && !arrived.contains(m.clientMsgId)));
                              }
                              // v0.9.6: başka üye sabitleme yaptıysa şeridi tazele
                              final pinnedSig = messages.where((m) => m.isPinned).map((m) => m.id).join(',');
                              if (snapshot.hasData && pinnedSig != _lastPinnedSig) {
                                _lastPinnedSig = pinnedSig;
                                final rid = targetStreamRoomId;
                                WidgetsBinding.instance.addPostFrameCallback((_) => _loadPinnedMessages(rid));
                              }
                              if (messages.length != _lastRenderedMessageCount) {
                                _lastRenderedMessageCount = messages.length;
                                _loadingOlder = false; // eski sayfa geldi (veya akış güncellendi)
                              }
                              // Yalnız EN YENİ mesaj değiştiğinde aşağı inilir; eski sayfa yüklenmesi
                              // (üste ekleme) görünümü hiç oynatmaz.
                              final newestId = messages.isEmpty ? null : messages.last.id;
                              if (newestId != _newestRenderedId) {
                                final firstLoad = _newestRenderedId == null;
                                // v1.2.4: yalnız GERÇEKTEN daha yeni bir mesaj geldiyse aşağı inilir.
                                // Eski sayfa yüklenirken önbellekten gelen bir anlık eski liste "yeni
                                // mesaj" sanılıp kullanıcıyı zorla aşağı çekiyordu (yukarı çıkamama/titreme).
                                final newestAt = messages.last.createdAt;
                                final isNewer = _newestRenderedAt == null || newestAt.isAfter(_newestRenderedAt!);
                                _newestRenderedId = newestId;
                                if (isNewer) _newestRenderedAt = newestAt;
                                if (!firstLoad && newestId != null && isNewer) {
                                  _scrollMessagesToBottom(force: messages.last.senderId == myUid);
                                }
                                if (newestId != null && !_isAppInBackground) {
                                  SupabaseService.instance.markRoomRead(targetStreamRoomId);
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
                                      if (n.depth != 0) return false;
                                      // Ters liste: pixels = en alttan uzaklık
                                      final far = n.metrics.pixels > 500;
                                      if (far != _showJumpDown.value) _showJumpDown.value = far;
                                      // Üste 400 px kala eski sayfayı kendiliğinden getir
                                      final hasMore = messages.length >= _messageWindow;
                                      if (hasMore && !_loadingOlder && n.metrics.extentAfter < 400 && n is ScrollUpdateNotification) {
                                        _loadingOlder = true;
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (mounted) setState(() => _messageWindow += _messagePageSize);
                                        });
                                      }
                                      return false;
                                    },
                                    child: ListView.builder(
                                      controller: _scrollCtrl,
                                      reverse: true,
                                      // Klavye açılınca/kapanınca liste dipten hizalı kalır
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                                      // +1: en altta (ters liste indeks 0) "yazıyor…" balonu yuvası
                                      itemCount: messages.length + 1 + (messages.length >= _messageWindow ? 1 : 0),
                                      // Kaydırma sırasında balonlar yeniden çizilmesin
                                      addRepaintBoundaries: true,
                                      itemBuilder: (context, i) {
                                        if (i == 0) return _buildTypingRow();
                                        i -= 1;
                                        final hasMore = messages.length >= _messageWindow;
                                        if (hasMore && i == messages.length) {
                                          // En üstteki öğe (ters listede son indeks): eski mesajlar
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            child: Center(
                                              child: _loadingOlder
                                                  ? const SizedBox(width: 160, child: JuzzioSkeletonLine(widthFactor: 1, height: 10))
                                                  : TextButton.icon(
                                                      onPressed: () => setState(() {
                                                        _loadingOlder = true;
                                                        _messageWindow += _messagePageSize;
                                                      }),
                                                      icon: Icon(Icons.history_rounded, size: 18, color: p.amberPrimary),
                                                      label: Text(appCtrl.trEn('Daha eski mesajlar', 'Older messages', 'Ältere Nachrichten'),
                                                          style: TextStyle(color: p.amberPrimary, fontWeight: FontWeight.w700)),
                                                    ),
                                            ),
                                          );
                                        }
                                        final msg = messages[messages.length - 1 - i];
                                        final isMe = msg.senderId == myUid;
                                        _listedMessages = messages;
                                        return KeyedSubtree(
                                          key: _bubbleKeys.putIfAbsent(msg.id, () => GlobalKey(debugLabel: 'm${msg.id}')),
                                          child: JuzzioFlashHighlight(
                                            active: _flashMessageId == msg.id,
                                            child: _buildMessageBubble(p, s, msg, isMe, appCtrl.subtitleLang),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    right: 14,
                                    bottom: 12,
                                    child: ValueListenableBuilder<bool>(
                                      valueListenable: _showJumpDown,
                                      builder: (context, show, child) => AnimatedScale(
                                        scale: show ? 1 : 0,
                                        duration: const Duration(milliseconds: 180),
                                        child: child,
                                      ),
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
                  // v1.2.0: kanalda yalnız sahip/yöneticiler yazar; üyeler okur ve tepki verir
                  else if ((_activeConversationData?.isChannel ?? false) && !(_activeConversationData?.isGroupStaff ?? false))
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom > 0 ? 22 : 16),
                      decoration: BoxDecoration(color: p.cardBg, border: Border(top: BorderSide(color: p.glassBorder))),
                      child: Row(
                        children: [
                          Icon(Icons.campaign_rounded, color: JuzzioGlassTokens.glowText),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (_activeConversationData?.isCommunity ?? false)
                                  ? appCtrl.trEn('Resmî kanal: yalnız güncelleme duyuruları düşer. Mesaj gönderilemez.',
                                      'Official channel: only update announcements are posted. Messages cannot be sent.',
                                      'Offizieller Kanal: nur Update-Ankündigungen. Nachrichten sind nicht möglich.')
                                  : appCtrl.trEn('Bu bir kanal: yalnız yöneticiler paylaşım yapar', 'This is a channel: only admins can post',
                                      'Kanal: nur Admins können posten'),
                              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    )
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
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: JuzzioQuotePreview(
                                compact: true,
                                quoted: _replyingTo,
                                isMe: false,
                                senderLabel: appCtrl.t('reply_to_name').replaceAll(
                                    '{name}',
                                    _replyingTo!.senderName.isNotEmpty
                                        ? _replyingTo!.senderName
                                        : _resolveSenderName(_replyingTo!.senderId)),
                                onTap: () => _jumpToMessage(_replyingTo!.id),
                              ),
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
                  key: _composerFieldKey,
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
                            // v0.9.4: ataş = eklenti menüsü; kamera = yalnız doğrudan çekim
                            IconButton(
                              tooltip: appCtrl.trEn('Ekle: belge, galeri, konum, anket…', 'Attach: file, gallery, location, poll…', 'Anhängen: Datei, Galerie, Standort, Umfrage…'),
                              onPressed: _openAttachMenu,
                              // v1.1.0 (#04 Plus morph): menü açıkken + dönerek × olur
                              icon: JuzzioMorphIcon(kind: JuzzioMorph.plusX, open: _attachMenuOpen, color: p.textSecondary, size: 24),
                            ),
                            GestureDetector(
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                _captureFromCamera(video: true);
                              },
                              child: IconButton(
                                tooltip: appCtrl.trEn('Fotoğraf çek (video için basılı tut)', 'Take photo (hold for video)', 'Foto aufnehmen (für Video halten)'),
                                onPressed: () => _captureFromCamera(video: false),
                                icon: Icon(Icons.photo_camera_outlined, color: p.textSecondary, size: 24),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // v1.1.0: gönder ↔ mikrofon geçişi ölçeklenip zıplar (Symbol Effect);
              // gönder = kağıt uçak + swoosh (#02 / #05)
              JuzzioSymbolSwap(
                child: _composerHasText
                ? JuzzioPaperPlaneButton(
                    key: const ValueKey('composer_send'),
                    onPressed: _sendText,
                    tooltip: appCtrl.trEn('Gönder', 'Send', 'Senden'),
                  )
                : GestureDetector(
                  key: const ValueKey('composer_mic'),
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

  /// v1.1.0 (#06 3 nokta zıplama): karşı taraf yazarken sohbetin dibinde ışıklı nokta balonu
  Widget _buildTypingRow() {
    return ListenableBuilder(
      listenable: JuzzioChatActivityService.instance,
      builder: (context, _) {
        final st = JuzzioChatActivityService.instance.resolver.resolve();
        final typing = st.kind == JuzzioHeaderStatusKind.typing;
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: kJuzzioSpring,
          alignment: Alignment.bottomLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(alignment: Alignment.bottomLeft, scale: anim, child: child),
            ),
            child: typing
                ? const Align(
                    key: ValueKey('typing_on'),
                    alignment: Alignment.centerLeft,
                    child: Padding(padding: EdgeInsets.only(left: 38, bottom: 10), child: JuzzioTypingBubble()),
                  )
                : const SizedBox(key: ValueKey('typing_off'), width: double.infinity),
          ),
        );
      },
    );
  }

  /// v0.9.0 N-A: "Yazıyor..." (animasyonlu nokta) / "Ses kaydediliyor.." (statik).
  /// Grupta kimin yazdığı isimle gösterilir. Azaltılmış harekette animasyon yok.
  Widget _buildActivityStatusLine(JuzzioAppController app, JuzzioHeaderStatus st, JuzzioGroupRoom? group) {
    String? who;
    if (group != null && st.userIds.isNotEmpty) {
      final idx = group.groupMemberIds.indexOf(st.userIds.first);
      final name = idx >= 0 && idx < group.groupMembers.length ? group.groupMembers[idx] : _resolveSenderName(st.userIds.first);
      who = st.userIds.length > 1 ? '$name +${st.userIds.length - 1}' : name;
    }
    final recording = st.kind == JuzzioHeaderStatusKind.recording;
    final base = recording
        ? app.trEn('Ses kaydediliyor..', 'Recording audio..', 'Nimmt Audio auf..')
        : app.trEn('Yazıyor', 'Typing', 'Schreibt');
    final label = who == null ? base : '$who: $base';
    const style = TextStyle(color: JuzzioColors.emerald400, fontSize: 12, height: 1.25, fontWeight: FontWeight.w700);
    return Semantics(
      liveRegion: true,
      label: recording ? label : '$label...',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(recording ? Icons.mic_rounded : Icons.edit_rounded, size: 13, color: JuzzioColors.emerald400),
            const SizedBox(width: 4),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
            if (!recording) _JuzzioTypingDots(style: style, animate: !app.reduceMotion),
          ],
        ),
      ),
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
    showJuzzioSheet<void>(
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
    // v1.0.0: menü artık opak (okunur), emojisiz; her seçenek ikonlu, tehlikeli işlemler
    // ayırıcıdan sonra kırmızı.
    PopupMenuEntry<String> item(String value, IconData icon, String label, {bool danger = false}) => PopupMenuItem<String>(
          value: value,
          height: 46,
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? JuzzioColors.red500 : JuzzioGlassTokens.glowText),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: danger ? JuzzioColors.red500 : JuzzioGlassTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
        );
    return PopupMenuButton<String>(
      // v1.1.0 (#05 Kebab morph): açıkken ⋮ → ×
      icon: JuzzioMorphIcon(kind: JuzzioMorph.kebab, open: _kebabOpen, color: p.textPrimary),
      onOpened: () {
        JuzzioHaptics.toggle();
        setState(() => _kebabOpen = true);
      },
      onCanceled: () => setState(() => _kebabOpen = false),
      color: JuzzioGlassTokens.sheet,
      elevation: 12,
      shadowColor: Colors.black54,
      surfaceTintColor: Colors.transparent,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: JuzzioGlassTokens.spaceCardBorder),
      ),
      onSelected: (value) async {
        setState(() => _kebabOpen = false);
        if (roomId == null) return;
        switch (value) {
          case 'search_here':
            _openMessageSearch(inRoomId: roomId);
            break;
          case 'members':
            final conv = _activeConversationData;
            await showJuzzioGroupManagementSheet(
              context,
              roomId: roomId,
              groupTitle: conv?.title ?? group?.title ?? '',
              groupType: conv?.groupType ?? 'general',
              groupPurpose: conv?.groupPurpose ?? '',
              avatarUrl: conv?.avatarUrl,
              isCommunity: (conv?.isCommunity ?? false) || _inCommunity,
              isChannel: conv?.isChannel ?? false,
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
            // v1.1.0: kritik işlem → alttan açılan eylem sayfasıyla onay
            final pick = await showJuzzioActionSheet(
              context,
              title: appCtrl.trEn('Sohbet geçmişi temizlensin mi?', 'Clear chat history?', 'Chatverlauf löschen?'),
              message: appCtrl.trEn('Mesajlar yalnız senin için silinir; karşı taraf etkilenmez.',
                  'Messages are removed only for you; the other person is not affected.', 'Nachrichten werden nur für dich entfernt.'),
              actions: [
                JuzzioSheetAction(appCtrl.trEn('Geçmişi temizle', 'Clear history', 'Verlauf löschen'),
                    icon: Icons.cleaning_services_outlined, destructive: true),
              ],
            );
            if (pick != 0 || !mounted) break;
            await SupabaseService.instance.clearRoomHistoryForMe(roomId);
            _showSnack(appCtrl.trEn('Sohbet geçmişi sizin için temizlendi.', 'Chat history cleared for you.', 'Chatverlauf für dich gelöscht.'));
            break;
          case 'profile':
            if (partner != null) _openUserProfilePage(partner.id);
            break;
          case 'chick':
            if (partner != null) _openChickGame(partner);
            break;
          // v0.9.5
          case 'watch_party':
            final rid = _activeConversationRoomId;
            if (rid != null) JuzzioWatchPartyScreen.open(context, rid);
            break;
          case 'safety':
            final rid2 = _activeConversationRoomId;
            if (rid2 != null) {
              JuzzioSafetyWalkScreen.open(context, roomId: rid2, roomTitle: group?.title ?? partner?.displayName ?? 'Juzzio');
            }
            break;
          case 'safety_number':
            if (partner != null) showJuzzioSafetyNumberSheet(context, peerUid: partner.id, peerName: partner.displayName);
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
          if (_inCommunity)
            item('members', Icons.info_outline_rounded, appCtrl.trEn('Kanal bilgisi', 'Channel info', 'Kanalinfo'))
          else
            item('members', Icons.manage_accounts_outlined, appCtrl.t('group_members_and_roles')),
          if ((_activeConversationData?.isGroupStaff ?? false) && !_inCommunity)
            item('add_members', Icons.person_add_alt_outlined, appCtrl.trEn('Üye ekle', 'Add members', 'Mitglieder hinzufügen')),
        ] else
          item('profile', Icons.person_outline_rounded, appCtrl.trEn('Profili gör', 'View profile', 'Profil ansehen')),
        // v1.2.0: yalnız bu sohbette ara
        item('search_here', Icons.manage_search_rounded, appCtrl.trEn('Sohbette ara', 'Search in chat', 'Im Chat suchen')),
        if (!_inCommunity) ...[
          item('watch_party', Icons.live_tv_outlined, appCtrl.trEn('İzleme partisi', 'Watch party', 'Watch-Party')),
          item('safety', Icons.shield_outlined, appCtrl.trEn('Güvenli takip', 'Safety check', 'Sicherheitscheck')),
        ],
        if (group == null) ...[
          item('safety_number', Icons.verified_user_outlined, appCtrl.trEn('Güvenlik numarası', 'Safety number', 'Sicherheitsnummer')),
          if (JuzzioFeaturesService.instance.lastAppConfig.chickGameEnabled)
            item('chick', Icons.egg_outlined, appCtrl.trEn('Civciv oyunu', 'Chick game', 'Küken-Spiel')),
        ],
        const PopupMenuDivider(height: 10),
        item('clear', Icons.cleaning_services_outlined, appCtrl.trEn('Geçmişi temizle', 'Clear history', 'Verlauf löschen'), danger: true),
        if (group != null)
          item('leave_group', Icons.logout_rounded, appCtrl.trEn('Gruptan ayrıl', 'Leave group', 'Gruppe verlassen'), danger: true)
        else
          item('block', Icons.block_rounded, appCtrl.trEn('Engelle', 'Block', 'Blockieren'), danger: true),
      ],
    );
  }

  Future<void> _showAddGroupMembersSheet(JuzzioGroupRoom group) async {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final candidates = _acceptedFriendProfiles.where((f) => !group.groupMemberIds.contains(f.id)).toList();
    final selected = <String>{};
    await showJuzzioSheet<void>(
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

  /// v1.2.0: hikâyeye yalnız emoji ile verilen yanıt (tepki) mi?
  bool _isStoryReactionMessage(JuzzioMessage msg) {
    if (msg.isDeleted || msg.storyReplyMeta == null) return false;
    final kind = (msg.storyReplyMeta!['replyKind'] ?? '').toString();
    if (kind == 'reaction') return true;
    if (kind == 'comment') return false;
    final t = msg.originalText.trim();
    return t.isNotEmpty && juzzioBigEmojiCount(t) == 1;
  }

  /// v1.2.0: modern hikâye yanıt kartı — tam küçük görsel, cam başlık, tepki için sağ üstte büyük emoji.
  /// Karta dokunmak hikâyeyi açar (eski çerçeve ve "İzle" düğmesi kaldırıldı).
  Widget _buildEmbeddedStoryReplyCard(
    JuzzioPalette p,
    JuzzioMessage msg,
    bool isMe,
  ) {
    final app = JuzzioAppController.instance;
    final meta = msg.storyReplyMeta!;
    final storyOwnerHandle = '@${(meta['storyUsername'] ?? 'user').toString().replaceAll('@', '')}';
    final mediaUrl = meta['storyMediaUrl']?.toString();
    final mediaType = (meta['storyMediaType'] ?? 'image').toString();
    final storyCaption = (meta['storyCaptionOriginal'] ?? '').toString();
    final isVideo = mediaType == 'video';
    final hasLocalFile = mediaUrl != null && !mediaUrl.startsWith('http') && File(mediaUrl).existsSync();
    final reaction = _isStoryReactionMessage(msg)
        ? ((meta['reaction'] ?? '').toString().trim().isNotEmpty ? meta['reaction'].toString().trim() : msg.originalText.trim())
        : null;
    final myStory = (meta['storyUserId'] ?? '').toString() == (SupabaseService.instance.currentUserId ?? '-');
    final label = reaction != null
        ? (isMe
            ? app.trEn('$storyOwnerHandle hikâyesine tepki verdin', 'You reacted to $storyOwnerHandle\'s story', 'Du hast auf die Story von $storyOwnerHandle reagiert')
            : (myStory
                ? app.trEn('Hikâyene tepki verdi', 'Reacted to your story', 'Hat auf deine Story reagiert')
                : app.trEn('$storyOwnerHandle hikâyesine tepki', 'Reaction to $storyOwnerHandle\'s story', 'Reaktion auf Story von $storyOwnerHandle')))
        : (isMe
            ? app.trEn('$storyOwnerHandle hikâyesine yanıt verdin', 'You replied to $storyOwnerHandle\'s story', 'Du hast auf die Story von $storyOwnerHandle geantwortet')
            : (myStory
                ? app.trEn('Hikâyene yorum yaptı', 'Commented on your story', 'Hat deine Story kommentiert')
                : app.trEn('$storyOwnerHandle hikâyesine yanıt', 'Reply to $storyOwnerHandle\'s story', 'Antwort auf Story von $storyOwnerHandle')));
    final w = reaction != null ? 132.0 : 156.0;
    final h = w * 16 / 10.5;

    Widget media;
    if (mediaUrl != null && mediaUrl.startsWith('http') && !isVideo) {
      media = JuzzioStorageImage(mediaUrl, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _storyPlaceholder(storyCaption, isVideo));
    } else if (hasLocalFile && !isVideo) {
      media = Image.file(File(mediaUrl), width: w, height: h, fit: BoxFit.cover);
    } else {
      media = _storyPlaceholder(storyCaption, isVideo);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_stories_rounded, size: 13, color: isMe ? Colors.white70 : p.textSecondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isMe ? Colors.white70 : p.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => _openStoryFromReplyMeta(meta),
            child: SizedBox(
              width: w + (reaction != null ? 14 : 0),
              height: h + (reaction != null ? 14 : 0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(fit: StackFit.expand, children: [
                          media,
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x00000000), Color(0x99000000)],
                                stops: [0, 0.55, 1],
                              ),
                            ),
                          ),
                          if (isVideo)
                            const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 38)),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Row(children: [
                              const Icon(Icons.motion_photos_on_rounded, color: Colors.white, size: 13),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(storyOwnerHandle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  if (reaction != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: JuzzioPopIn(
                        play: JuzzioBubbleEntrance.isFresh(msg.createdAt),
                        child: Text(reaction, style: juzzioEmojiStyle(44), textScaler: TextScaler.noScaling),
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

  Widget _storyPlaceholder(String caption, bool isVideo) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [JuzzioColors.deepForest, JuzzioColors.royalNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: Text(
          caption.isNotEmpty ? caption : '✨',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      );

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

  /// v1.1.0: alıntılanan mesaja kaydırır ve kısa süre parlatır. Mesaj yüklü pencerede
  /// değilse eski sayfalar getirilir; ters ve değişken yükseklikli listede önce tahmini
  /// konuma atlanır, öğe çizilince tam hizalanır.
  Future<void> _jumpToMessage(String id) async {
    if (_jumping) return;
    _jumping = true;
    final app = JuzzioAppController.instance;
    try {
      for (var attempt = 0; attempt < 14 && mounted; attempt++) {
        final ctx = _bubbleKeys[id]?.currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(
            ctx,
            alignment: 0.35,
            duration: const Duration(milliseconds: 420),
            curve: const Cubic(0.22, 1, 0.36, 1),
          );
          if (!mounted) return;
          HapticFeedback.lightImpact();
          _flashTimer?.cancel();
          setState(() => _flashMessageId = id);
          _flashTimer = Timer(const Duration(milliseconds: 1600), () {
            if (mounted) setState(() => _flashMessageId = null);
          });
          return;
        }
        final list = _listedMessages;
        final idx = list.indexWhere((m) => m.id == id);
        if (idx < 0) {
          if (list.length < _messageWindow) break; // tüm geçmiş yüklü, mesaj yok
          setState(() {
            _loadingOlder = true;
            _messageWindow += _messagePageSize;
          });
          await Future<void>.delayed(const Duration(milliseconds: 450));
          continue;
        }
        if (!_scrollCtrl.hasClients) break;
        final pos = _scrollCtrl.position;
        // ters liste: dipten sıra; ortalama öğe yüksekliği kaydırılabilir alandan kestirilir
        final fromBottom = list.length - 1 - idx;
        final total = pos.maxScrollExtent + pos.viewportDimension;
        final avg = list.isEmpty ? 96.0 : (total / list.length).clamp(48.0, 420.0);
        final target = (fromBottom * avg - pos.viewportDimension * 0.35).clamp(0.0, pos.maxScrollExtent);
        _scrollCtrl.jumpTo(target);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(app.trEn('Alıntılanan mesaj bulunamadı (silinmiş olabilir).',
              'Quoted message not found (it may have been deleted).', 'Zitierte Nachricht nicht gefunden.')),
        ));
      }
    } finally {
      _jumping = false;
    }
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
    // v0.9.0 §4.3: sunucudaki kayıtlı mesajlar (+ eski sürümün yerel yıldızları)
    final isBookmarked = JuzzioLifeService.instance.isMessageSaved(msg.id) || JuzzioAppController.instance.isMessageStarred(msg.id);
    final isSwiped = _swipedMessageId == msg.id;
    final currentRoomKey = _activeConversationRoomId ?? 'no_room';
    final isRoomMuted = _mutedConversationIds.contains(currentRoomKey);
    // v1.2.0: Juzzio Topluluğu kanalında paylaşımlar "Juzzio Official" adı ve logosuyla görünür
    final official = _inCommunity;
    final senderLabel = official ? kJuzzioOfficialName : (msg.senderName.isNotEmpty ? msg.senderName : _resolveSenderName(msg.senderId));
    _messageCache[msg.id] = msg;
    final quoted = msg.replyToId != null ? _messageCache[msg.replyToId!] : null;
    // v1.1.0 (#08 Big Emoji): yalnız 1–3 emojiden oluşan metin balonsuz ve büyük gösterilir
    final bigEmojiCount = !msg.isDeleted && msg.messageType == 'text' && msg.replyToId == null && (msg.imageUrl ?? '').isEmpty
        ? juzzioBigEmojiCount(msg.originalText)
        : 0;
    final bigEmoji = bigEmojiCount > 0;

    // v1.2.0: doğum günü mesajı → 4 sn kutlama (eller + konfeti + yükselen emojiler + elektrik dalgası)
    final birthday = !msg.isDeleted && msg.messageType == 'text' && juzzioIsBirthdayMessage(msg.originalText);
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
        // v0.9.3: sola yaylı kaydırma → arkadan sessize al / sil belirir
        open: isSwiped,
        trailingWidth: 96,
        onOpenChanged: (open) {
          if (open && _swipedMessageId != msg.id) setState(() => _swipedMessageId = msg.id);
          if (!open && _swipedMessageId == msg.id) setState(() => _swipedMessageId = null);
        },
        trailing: msg.isDeleted ? null : Row(mainAxisSize: MainAxisSize.min, children: [
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
              // v1.2.4: silme mantığı tek yerde (uzun basma menüsünden de çağrılır)
              onTap: () => _confirmDeleteMessage(msg, isMe),
              child: Container(
                width: 38,
                height: 38,
                
                decoration: const BoxDecoration(
                  color: JuzzioColors.red500,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 19),
              ),
            ),
]),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 16),
              child: _buildUserAvatar(
                avatarUrl: official ? kJuzzioLogoAvatar : _resolveAvatar(msg.senderId),
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
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            senderLabel,
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: official ? JuzzioGlassTokens.glowText : p.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (official) ...[
                            const SizedBox(width: 3),
                            Icon(Icons.verified_rounded, size: 13, color: JuzzioGlassTokens.glowText),
                          ],
                        ]),
                      ),
                    JuzzioFlightTarget(
                      // sunucu kaydı uçuş bitmeden gelirse de aynı clientMsgId ile gizli kalır (çift görüntü yok)
                      flightKey: isMe ? msg.clientMsgId : null,
                      child: JuzzioBirthdayFxGate(
                      enabled: birthday,
                      playKey: msg.clientMsgId ?? msg.id,
                      createdAt: msg.createdAt,
                      child: Container(
                      padding: bigEmoji ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: bigEmoji ? null : BoxDecoration(
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
                      foregroundDecoration: bigEmoji ? null : BoxDecoration(
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
                            JuzzioQuotePreview(
                              quoted: quoted,
                              isMe: isMe,
                              senderLabel: quoted == null
                                  ? ''
                                  : (quoted.senderName.isNotEmpty ? quoted.senderName : _resolveSenderName(quoted.senderId)),
                              onTap: () => _jumpToMessage(msg.replyToId!),
                            ),
                          if (!msg.isDeleted && msg.storyReplyMeta != null)
                            _buildEmbeddedStoryReplyCard(p, msg, isMe),

                          // v0.9.5: tek seferlik medya önizlemesiz balonla gösterilir
                          if (!msg.isDeleted && msg.isViewOnce) ...[
                            JuzzioViewOnceBubble(message: msg, isMe: isMe),
                            const SizedBox(height: 6),
                          ] else if (!msg.isDeleted && msg.imageUrl != null && msg.imageUrl!.isNotEmpty && JuzzioEncryptedMedia.isEncrypted(msg.metadata)) ...[
                            // v1.1.0: çift dokun → kalp (#03), dokun → yakınlaşarak tam ekran (#03 Zoom + #09 Hero)
                            Builder(builder: (imgCtx) => JuzzioDoubleTapHeart(
                              onTap: () => JuzzioEncryptedImage.openFullScreen(context,
                                  messageId: msg.id, url: msg.imageUrl!, heroTag: 'jz_media_${msg.id}', origin: juzzioGlobalRect(imgCtx)),
                              onDoubleTap: msg.isLocalPending ? null : () => _quickReact(msg, '❤️'),
                              child: Hero(
                                tag: 'jz_media_${msg.id}',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: JuzzioEncryptedImage(messageId: msg.id, url: msg.imageUrl!, height: 190),
                                ),
                              ),
                            )),
                            const SizedBox(height: 8),
                          ] else if (!msg.isDeleted && msg.imageUrl != null && msg.imageUrl!.isNotEmpty) ...[
                            Builder(builder: (imgCtx) => JuzzioDoubleTapHeart(
                              onTap: () => JuzzioMediaViewerPage.open(context,
                                  url: msg.imageUrl!, isVideo: false, heroTag: 'jz_media_${msg.id}', origin: juzzioGlobalRect(imgCtx)),
                              onDoubleTap: msg.isLocalPending ? null : () => _quickReact(msg, '❤️'),
                              child: Hero(
                                tag: 'jz_media_${msg.id}',
                                child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: JuzzioStorageImage(
                                  msg.imageUrl!,
                                  height: 190,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, progress) => progress == null
                                      ? child
                                      : SizedBox(
                                          height: 190,
                                          child: Center(child: JuzzioOrbitLoader(color: p.amberPrimary)),
                                        ),
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                              ),
                            )),
                            const SizedBox(height: 8),
                          ],
                          // v0.9.6: uçtan uca şifreli video
                          if (!msg.isDeleted && !msg.isViewOnce && (msg.videoUrl ?? '').isNotEmpty && JuzzioEncryptedMedia.isEncrypted(msg.metadata)) ...[
                            JuzzioEncryptedVideoTile(messageId: msg.id, url: msg.videoUrl!, isMe: isMe),
                            const SizedBox(height: 8),
                          ] else if (!msg.isDeleted && !msg.isViewOnce && msg.videoUrl != null && msg.videoUrl!.isNotEmpty) ...[
                            Builder(builder: (vidCtx) => GestureDetector(
                              onTap: () => JuzzioMediaViewerPage.open(context, url: msg.videoUrl!, isVideo: true, origin: juzzioGlobalRect(vidCtx)),
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
                            )),
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
                                // v0.9.3: toplam süre; çalarken geçen / toplam
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: isPlaying
                                      ? StreamBuilder<Duration>(
                                          stream: _audioPlayer.positionStream,
                                          builder: (_, snap) => Text(
                                            msg.audioDurationMs > 0
                                                ? '${juzzioFormatVoiceDuration(snap.data?.inMilliseconds ?? 0)} / ${juzzioFormatVoiceDuration(msg.audioDurationMs)}'
                                                : juzzioFormatVoiceDuration(snap.data?.inMilliseconds ?? 0),
                                            style: TextStyle(
                                              color: isMe ? Colors.white : p.textSecondary,
                                              fontSize: 11.5,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        )
                                      : msg.audioDurationMs <= 0
                                      ? const SizedBox.shrink()
                                      : Text(
                                          juzzioFormatVoiceDuration(msg.audioDurationMs),
                                          semanticsLabel: JuzzioAppController.instance.trEn('Süre', 'Duration', 'Dauer'),
                                          style: TextStyle(
                                            color: isMe ? Colors.white : p.textSecondary,
                                            fontSize: 11.5,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                ),
                                // G28: oynatma hızı 1x → 1.5x → 2x (çalan sese de anında uygulanır)
                                Semantics(
                                  button: true,
                                  label: JuzzioAppController.instance.trEn('Oynatma hızı', 'Playback speed', 'Wiedergabegeschwindigkeit'),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: _cycleVoiceSpeed,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Text(
                                        '${_voiceSpeed == _voiceSpeed.roundToDouble() ? _voiceSpeed.toInt() : _voiceSpeed}x',
                                        style: TextStyle(
                                          color: isMe ? Colors.white : p.amberPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (!msg.isDeleted && msg.metadata['poll_id'] != null)
                            JuzzioPollCard(pollId: msg.metadata['poll_id'].toString(), isMe: isMe),
                          // v0.9.4: grup etkinliği kartı ve belge balonu
                          if (!msg.isDeleted && msg.metadata['event_id'] != null)
                            JuzzioEventCard(eventId: msg.metadata['event_id'].toString(), isMe: isMe),
                          if (!msg.isDeleted && msg.messageType == 'document' && (msg.documentUrl ?? '').isNotEmpty)
                            JuzzioDocumentBubble(message: msg, isMe: isMe),
                          // v1.2.0: kişi kartı → dokunulabilir, profil fotoğraflı, "Profili Görüntüle"
                          if (!msg.isDeleted && msg.messageType == 'text' && juzzioParseContactCard(msg.originalText) != null)
                            JuzzioContactCard(
                              isMe: isMe,
                              name: juzzioParseContactCard(msg.originalText)!.$1,
                              username: juzzioParseContactCard(msg.originalText)!.$2,
                              onOpenProfile: _openUserProfilePage,
                            )
                          // v1.2.0: paylaşılan vardiya planı → dokununca gün gün ayrıntı
                          else if (!msg.isDeleted && msg.messageType == 'text' && juzzioParseSharedShift(msg.originalText, msg.createdAt) != null)
                            JuzzioShiftPlanCard(
                              isMe: isMe,
                              plan: juzzioParseSharedShift(msg.originalText, msg.createdAt)!,
                              ownerId: msg.senderId,
                              ownerName: isMe ? null : msg.senderName,
                              roomId: msg.roomId,
                            )
                          // v1.2.0: hikâyeye emoji tepkisi → metin yerine kartın köşesindeki büyük emoji gösterilir
                          else if (_isStoryReactionMessage(msg))
                            const SizedBox.shrink()
                          // v1.0.0: paylaşılan konum → harita önizlemeli kart (Haritalar / Google Maps'te açılır)
                          else if (!msg.isDeleted && msg.messageType == 'text' && juzzioParseLocation(msg.originalText) != null)
                            JuzzioLocationCard(point: juzzioParseLocation(msg.originalText)!, isMe: isMe)
                          else if (!msg.isDeleted && msg.originalText.trim().isNotEmpty && msg.metadata['poll_id'] == null &&
                              msg.metadata['event_id'] == null && msg.messageType != 'document')
                          FutureBuilder<String>(
                            // v1.0.0: mesaj yazıldığı gibi gösterilir; çeviri hazır olunca ALTINDA belirir
                            future: isMe || msg.isLocalPending
                                ? Future.value(msg.translatedText)
                                : _resolveTranslatedMessageText(msg, mySubtitleLang),
                            initialData: msg.translatedText,
                            builder: (context, snap) {
                              // v1.2.0: Juzzio Topluluğu sürüm duyurusu → uygulama dilindeki metin (TR / EN)
                              final release = msg.metadata['release'] is Map;
                              final useEn = release && !JuzzioAppController.instance.uiLang.startsWith('tr') && msg.translatedText.trim().isNotEmpty;
                              final mainText = useEn ? msg.translatedText : msg.originalText;
                              final secondaryText = release ? '' : (snap.data ?? '').trim();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // v1.0.0: bağlantılar/e-posta/telefon tıklanabilir (varsayılan uygulamada açılır)
                                  JuzzioLinkText(
                                    mainText,
                                    linkColor: isMe ? Colors.white : null,
                                    style: bigEmoji
                                        ? TextStyle(
                                            fontFamily: JuzzioConfig.fontRegularBold,
                                            color: p.textPrimary,
                                            fontSize: bigEmojiCount == 1 ? 54.0 : 40.0,
                                            fontWeight: FontWeight.w700,
                                            height: 1.1,
                                            fontFamilyFallback: kJuzzioEmojiFallback,
                                          )
                                        // v1.2.2: uçuşla aynı stil (tek kaynak)
                                        : _outgoingBubbleTextStyle(p).copyWith(color: isMe ? Colors.white : p.textPrimary),
                                  ),
                                  // v1.2.4: iletilen küresel gönderi / hikâye → tek dokunuşla aç
                                  if (juzzioSharedRef(mainText) case final ref?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: isMe ? Colors.white : p.textPrimary,
                                          side: BorderSide(color: isMe ? Colors.white54 : p.glassBorder),
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                        ),
                                        onPressed: () => _openSharedRef(ref),
                                        icon: Icon(ref.$1 == 'post' ? Icons.public_rounded : Icons.auto_stories_rounded, size: 16),
                                        label: Text(ref.$1 == 'post'
                                            ? JuzzioAppController.instance.trEn('Gönderiyi aç', 'Open post', 'Beitrag öffnen')
                                            : JuzzioAppController.instance.trEn('Hikâyeyi aç', 'Open story', 'Story öffnen')),
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
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  // v1.1.0 (#10 Star save): kaydedilince dönerek ışıltı saçar
                                  child: JuzzioStarSave(
                                    saved: true,
                                    size: 13,
                                    playOnMount: _justStarredId == msg.id,
                                    color: isMe && !bigEmoji ? Colors.white : const Color(0xFFFFC83D),
                                  ),
                                ),
                              // v0.7.0: uçtan uca şifreli mesaj göstergesi
                              if (msg.isEncrypted)
                                Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: Icon(Icons.lock_rounded, size: 11, color: isMe ? Colors.white70 : p.textMuted),
                                ),
                              Text(
                                // v0.9.0 §4.5: düzenlenen mesaj işaretlenir
                                msg.editedAt != null && !msg.isDeleted
                                    ? '${JuzzioAppController.instance.trEn('Düzeltildi', 'Edited', 'Bearbeitet')} · ${_formatTime(msg.createdAt)}'
                                    : _formatTime(msg.createdAt),
                                style: TextStyle(
                                  color: isMe && !bigEmoji ? Colors.white70 : p.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                              // v1.1.0 (#04 Read receipts): saat → ✓ → ✓✓ → parlayan ✓✓ (çizim animasyonu)
                              if (isMe && msg.isLocalPending) ...[
                                const SizedBox(width: 4),
                                JuzzioReceiptTicks(state: JuzzioReceipt.sending, size: 13, idleColor: bigEmoji ? p.textMuted : Colors.white54),
                              ] else if (isMe && _activeGroupRoom == null) ...[
                                const SizedBox(width: 4),
                                Builder(builder: (_) {
                                  final conv = _conversationById(msg.roomId);
                                  final readAt = conv?.partnerLastReadAt;
                                  final isRead = readAt != null && !msg.createdAt.isAfter(readAt);
                                  final state = isRead
                                      ? JuzzioReceipt.read
                                      : ((conv?.partnerIsOnline ?? false) ? JuzzioReceipt.delivered : JuzzioReceipt.sent);
                                  return JuzzioReceiptTicks(
                                    state: state,
                                    size: 13,
                                    fresh: DateTime.now().difference(msg.createdAt).inSeconds.abs() < 10,
                                    idleColor: bigEmoji ? p.textMuted : Colors.white54,
                                    readColor: bigEmoji ? JuzzioGlassTokens.glowText : JuzzioColors.sky300,
                                  );
                                }),
                              ] else if (isMe) ...[
                                const SizedBox(width: 4),
                                JuzzioReceiptTicks(state: JuzzioReceipt.sent, size: 13, idleColor: bigEmoji ? p.textMuted : Colors.white54),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    ),
                    ),
                    if (reactionCounts.isNotEmpty)
                      // v1.2.0: tepki rozeti — büyük, renkli emoji yazı tipi, kırpılmaz (altta pay bırakılır)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Transform.translate(
                          offset: const Offset(0, -8),
                          child: GestureDetector(
                            // v1.2.4: rozete dokununca kimin hangi tepkiyi verdiği; basılı tutunca işlemler
                            // v1.2.6: toplulukta kimin tepki verdiği gösterilmez (üyeler birbirini görmez)
                            onTap: _inCommunity ? null : () => _showReactionsWho(p, msg),
                            onLongPress: () => _showMessageActionMenu(p, s, msg, isMe),
                            child: JuzzioReactionBadge(
                              messageId: msg.id,
                              counts: reactionCounts,
                              popKeys: _reactionPopKeys,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
    // v1.1.0: yeni balon yaylı kayarak gelir; büyük emoji zıplar (Pop); kutlama → konfeti
    final entered = JuzzioBubbleEntrance(
      entranceKey: msg.clientMsgId ?? msg.id,
      isMe: isMe,
      createdAt: msg.createdAt,
      pop: bigEmoji,
      celebrate: !birthday && !msg.isDeleted && msg.messageType == 'text' && juzzioIsCelebration(msg.originalText),
      // v1.2.2: uçuş iniyorsa balon kendi girişini oynatmaz (JuzzioSendFlight.isPending); gecikme yok
      delay: Duration.zero,
      child: bubbleRow,
    );
    if (_burstMessageId != msg.id) return entered;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        entered,
        // v1.1.0 (#02 Burst ring + #06 Draw-on): kalp çizilerek dolar, halka ve parçacık patlaması
        IgnorePointer(
          child: JuzzioReactionBurst(
            key: ValueKey('burst_${msg.id}_$_burstEmoji'),
            emoji: _burstEmoji,
            size: 54,
            emojiStyle: juzzioEmojiStyle(44),
          ),
        ),
      ],
    );
  }

  /// Tepkiyi anında uygular (iyimser), sunucu sonucuyla eşitler.
  Future<void> _quickReact(JuzzioMessage msg, String emoji, {bool burst = false}) async {
    final myUid = SupabaseService.instance.currentUserId;
    if (myUid == null || msg.isDeleted) return;
    // v1.2.6: Juzzio Community resmî duyuru kanalıdır — tepki kapalı (sunucu da reddeder)
    if (_inCommunity || (_activeConversationData?.isCommunity ?? false)) {
      _showSnack(JuzzioAppController.instance.trEn('Juzzio Topluluğu bir duyuru kanalıdır: tepki gönderilemez.',
          'Juzzio Community is an announcement channel: reactions cannot be sent.',
          'Die Juzzio Community ist ein Ankündigungskanal: Reaktionen sind nicht möglich.'));
      return;
    }
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
      if (!removing) {
        final k = '${msg.id}|$emoji';
        _reactionPopKeys.add(k);
        Future.delayed(const Duration(milliseconds: 1500), () => _reactionPopKeys.remove(k));
      }
      if (burst && !removing) {
        _burstMessageId = msg.id;
        _burstEmoji = emoji;
      }
    });
    if (burst && !removing) {
      Future.delayed(const Duration(milliseconds: 950), () {
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

  /// v0.9.0 §4.5: mesajı düzenle (yeni metin yeniden şifrelenir; şifrelenemezse değişmez).
  Future<void> _editMessage(JuzzioMessage msg) async {
    final app = JuzzioAppController.instance;
    final ctrl = TextEditingController(text: msg.originalText);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.trEn('Mesajı düzenle', 'Edit message', 'Nachricht bearbeiten')),
        content: TextField(controller: ctrl, autofocus: true, minLines: 1, maxLines: 6, maxLength: 4000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(app.trEn('Kaydet', 'Save', 'Speichern'))),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null || next.trim().isEmpty || next.trim() == msg.originalText.trim()) return;
    try {
      await SupabaseService.instance.editTextMessage(message: msg, newText: next);
      _showSnack(app.trEn('Mesaj düzenlendi', 'Message edited', 'Nachricht bearbeitet'));
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  Future<void> _showEditHistory(JuzzioMessage msg) async {
    final app = JuzzioAppController.instance;
    await showJuzzioSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: FutureBuilder<List<({String text, DateTime editedAt})>>(
          future: SupabaseService.instance.fetchEditHistory(msg),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: JuzzioOrbitLoader()));
            }
            if (snap.hasError) {
              return Padding(padding: const EdgeInsets.all(24), child: Text(SupabaseService.instance.friendlyError(snap.error!)));
            }
            final items = snap.data ?? const [];
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(app.trEn('Düzenleme Geçmişi', 'Edit history', 'Bearbeitungsverlauf'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(app.trEn('Önceki sürümler 30 gün saklanır ve yalnızca bu sohbetin üyelerine görünür.',
                      'Previous versions are kept for 30 days and are visible only to members of this chat.',
                      'Frühere Versionen werden 30 Tage gespeichert und sind nur für Mitglieder dieses Chats sichtbar.'),
                      style: const TextStyle(fontSize: 12)),
                  const Divider(),
                  ListTile(
                    dense: true,
                    title: Text(msg.originalText),
                    subtitle: Text(app.trEn('Güncel', 'Current', 'Aktuell')),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(app.trEn('Önceki sürüm bulunamadı (30 günden eski olabilir).', 'No previous versions (may be older than 30 days).',
                          'Keine früheren Versionen (evtl. älter als 30 Tage).')),
                    ),
                  for (final e in items)
                    ListTile(
                      dense: true,
                      title: Text(e.text),
                      subtitle: Text(
                          '${e.editedAt.day}.${e.editedAt.month}.${e.editedAt.year} ${_formatTime(e.editedAt)} ${app.trEn('öncesi', 'before', 'vorher')}'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// v0.9.0 §4.3: kayıtlı mesaj aç/kapa (eski yerel yıldız varsa o da kaldırılır).
  Future<void> _toggleSavedMessage(JuzzioMessage msg) async {
    final app = JuzzioAppController.instance;
    final legacy = app.isMessageStarred(msg.id);
    try {
      if (legacy && !JuzzioLifeService.instance.isMessageSaved(msg.id)) {
        app.toggleStarredMessage(msg.id); // eski yerel işaret → kaldır (kayıt yok sayılır)
        _showSnack(app.trEn('Kayıt kaldırıldı', 'Unsaved', 'Nicht mehr gespeichert'));
      } else {
        if (legacy) app.toggleStarredMessage(msg.id);
        final saved = await JuzzioLifeService.instance.toggleSaved(roomId: msg.roomId, messageId: msg.id);
        if (saved) {
          _justStarredId = msg.id;
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_justStarredId == msg.id) _justStarredId = null;
          });
        }
        if (mounted) {
          JuzzioHud.show(context,
              icon: saved ? Icons.star_rounded : Icons.star_outline_rounded,
              text: saved
                  ? app.trEn('Yıldızlı mesajlara eklendi', 'Added to starred', 'Zu Favoriten hinzugefügt')
                  : app.trEn('Kayıt kaldırıldı', 'Unsaved', 'Nicht mehr gespeichert'));
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  /// v0.9.0 §4.2: mesaja hatırlatıcı — hazır seçenekler veya özel tarih/saat; iptal/düzenle.
  Future<void> _pickMessageReminder(JuzzioMessage msg, JuzzioLifeTask? existing) async {
    final app = JuzzioAppController.instance;
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final choice = await showJuzzioSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.timer_outlined), title: Text(app.trEn('1 saat sonra', 'In 1 hour', 'In 1 Stunde')),
              onTap: () => Navigator.pop(ctx, '1h')),
          if (tonight.isAfter(now.add(const Duration(minutes: 5))))
            ListTile(leading: const Icon(Icons.nights_stay_outlined), title: Text(app.trEn('Bu akşam 20:00', 'Tonight 20:00', 'Heute 20:00')),
                onTap: () => Navigator.pop(ctx, 'tonight')),
          ListTile(leading: const Icon(Icons.wb_sunny_outlined), title: Text(app.trEn('Yarın 09:00', 'Tomorrow 09:00', 'Morgen 09:00')),
              onTap: () => Navigator.pop(ctx, 'tomorrow')),
          ListTile(leading: const Icon(Icons.edit_calendar_rounded), title: Text(app.trEn('Tarih ve saat seç', 'Pick date & time', 'Datum & Uhrzeit')),
              onTap: () => Navigator.pop(ctx, 'custom')),
          if (existing != null)
            ListTile(
              leading: Icon(Icons.alarm_off_rounded, color: JuzzioColors.red500),
              title: Text(app.trEn('Hatırlatmayı iptal et', 'Cancel reminder', 'Erinnerung löschen'), style: const TextStyle(color: JuzzioColors.red500)),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    DateTime? at;
    switch (choice) {
      case '1h':
        at = now.add(const Duration(hours: 1));
        break;
      case 'tonight':
        at = tonight;
        break;
      case 'tomorrow':
        at = tomorrow;
        break;
      case 'custom':
        final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 5));
        if (d == null || !mounted) return;
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
        if (t == null) return;
        at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        if (at.isBefore(now)) {
          _showSnack(app.trEn('Geçmiş bir zaman seçilemez', 'Pick a future time', 'Bitte eine zukünftige Zeit wählen'), isError: true);
          return;
        }
        break;
    }
    try {
      final life = JuzzioLifeService.instance;
      if (choice == 'cancel' && existing != null) {
        await life.deleteTask(existing.id);
        _showSnack(app.trEn('Hatırlatma iptal edildi', 'Reminder cancelled', 'Erinnerung gelöscht'));
      } else if (at != null) {
        if (existing != null) {
          await life.updateTask(existing.id, remindAt: at);
        } else {
          await life.remindMessage(roomId: msg.roomId, messageId: msg.id, at: at);
        }
        final hh = at.hour.toString().padLeft(2, '0');
        final mm = at.minute.toString().padLeft(2, '0');
        _showSnack(app.trEn('Hatırlatma: ${at.day}.${at.month} $hh:$mm', 'Reminder: ${at.day}.${at.month} $hh:$mm',
            'Erinnerung: ${at.day}.${at.month} $hh:$mm'));
      }
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack(SupabaseService.instance.friendlyError(e), isError: true);
    }
  }

  /// Uzun basma menüsü: hızlı tepkiler (❤️‍🔥🥹🌸🫣🤩 +), yanıtla, kopyala, yıldızla
  /// v1.2.4: mesaja kimin hangi tepkiyi verdiği (grup ve birebir). Herkesin TEK tepkisi vardır;
  /// kendi tepkine dokunursan kaldırılır.
  Future<void> _showReactionsWho(JuzzioPalette p, JuzzioMessage msg) async {
    final app = JuzzioAppController.instance;
    final myUid = SupabaseService.instance.currentUserId;
    final reactions = Map<String, String>.from(_localReactions[msg.id] ?? msg.reactions)..removeWhere((_, e) => e.isEmpty);
    if (reactions.isEmpty) return;
    final groups = juzzioGroupReactions(reactions);
    String nameOf(String uid) {
      if (uid == myUid) return app.trEn('Sen', 'You', 'Du');
      for (final f in _allProfiles) {
        if (f.id == uid) return f.displayName.isNotEmpty ? f.displayName : '@${f.username}';
      }
      return _resolveSenderName(uid);
    }

    String? avatarOf(String uid) {
      if (uid == myUid) return _myProfile?.avatarUrl;
      for (final f in _allProfiles) {
        if (f.id == uid) return f.avatarUrl;
      }
      return null;
    }

    var tab = 'all';
    await showJuzzioSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final rows = <MapEntry<String, String>>[
            for (final g in groups.entries)
              if (tab == 'all' || tab == g.key)
                for (final uid in g.value) MapEntry(uid, g.key),
          ];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Text(app.trEn('Tepkiler', 'Reactions', 'Reaktionen'),
                      style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final t in ['all', ...groups.keys])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(t == 'all' ? '${app.trEn('Tümü', 'All', 'Alle')} ${reactions.length}' : '$t ${groups[t]!.length}'),
                            selected: tab == t,
                            onSelected: (_) => setS(() => tab = t),
                          ),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final uid = rows[i].key;
                      final emoji = rows[i].value;
                      final mine = uid == myUid;
                      return ListTile(
                        leading: _buildUserAvatar(avatarUrl: avatarOf(uid), fallbackName: nameOf(uid), radius: 18, p: p),
                        title: Text(nameOf(uid), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                        subtitle: mine
                            ? Text(app.trEn('Kaldırmak için dokun', 'Tap to remove', 'Zum Entfernen tippen'),
                                style: TextStyle(color: p.textSecondary, fontSize: 12))
                            : null,
                        trailing: Text(emoji, style: const TextStyle(fontSize: 24)),
                        onTap: mine
                            ? () {
                                Navigator.pop(ctx);
                                _quickReact(msg, emoji);
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// v1.2.4: her mesaj türü (metin, fotoğraf, video, belge, ses, tek görüntülemelik, kişi kartı,
  /// konum, anket, etkinlik) için ortak silme. Kendi mesajım herkes için, başkasınınki yalnız bende.
  Future<void> _confirmDeleteMessage(JuzzioMessage msg, bool isMe) async {
    // v0.9.3: silme onaylı (geri alınamaz) — v1.1.0: alttan açılan eylem sayfası
    final pick = await showJuzzioActionSheet(
      context,
      title: JuzzioAppController.instance.trEn('Mesaj silinsin mi?', 'Delete message?', 'Nachricht löschen?'),
      message: isMe
          ? JuzzioAppController.instance.trEn('Mesaj herkes için silinecek.', 'The message will be deleted for everyone.', 'Die Nachricht wird für alle gelöscht.')
          : JuzzioAppController.instance.trEn('Mesaj yalnız senin için gizlenecek.', 'The message will be hidden only for you.', 'Die Nachricht wird nur für dich ausgeblendet.'),
      actions: [
        JuzzioSheetAction(JuzzioAppController.instance.trEn('Sil', 'Delete', 'Löschen'), icon: Icons.delete_outline_rounded, destructive: true),
      ],
    );
    final ok = pick == 0;
    if (ok != true || !mounted) {
      if (mounted) setState(() => _swipedMessageId = null);
      return;
    }
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
  }

  void _showMessageActionMenu(JuzzioPalette p, JuzzioStrings s, JuzzioMessage msg, bool isMe) {
    if (msg.isLocalPending) return; // v1.0.0: gönderilmekte olan mesajda işlem yok
    final app = JuzzioAppController.instance;
    final myUid = SupabaseService.instance.currentUserId;
    final myCurrentEmoji = myUid != null ? (_localReactions[msg.id] ?? msg.reactions)[myUid] : null;
    final isStarred = JuzzioLifeService.instance.isMessageSaved(msg.id) || app.isMessageStarred(msg.id);
    final hasReminder = JuzzioLifeService.instance.reminderForMessage(msg.id);
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
              // v1.2.6: Juzzio Community'de tepki yok (resmî duyuru kanalı)
              if (!msg.isDeleted && !_inCommunity)
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
                  JuzzioHaptics.success();
                  JuzzioHud.show(context, icon: Icons.copy_rounded, text: app.trEn('Mesaj kopyalandı', 'Message copied', 'Nachricht kopiert'));
                }),
              // v0.9.0 §4.5: Düzenle (kendi metin mesajım, 15 dk) ve Düzenleme Geçmişi
              if (isMe && !msg.isDeleted && msg.messageType == 'text' &&
                  DateTime.now().difference(msg.createdAt.toLocal()) < const Duration(minutes: 15))
                action(Icons.edit_rounded, app.trEn('Düzenle', 'Edit', 'Bearbeiten'), () => _editMessage(msg)),
              if (msg.editedAt != null && !msg.isDeleted)
                action(Icons.history_rounded, app.trEn('Düzenleme Geçmişi', 'Edit history', 'Bearbeitungsverlauf'),
                    () => _showEditHistory(msg)),
              // v0.9.6: Sabitle / Sabitlemeyi kaldır (birebir: iki taraf; grup: gönderen veya yönetici)
              if (!msg.isDeleted)
                action(
                  _pinnedMessages.any((m) => m.id == msg.id) ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  _pinnedMessages.any((m) => m.id == msg.id)
                      ? app.trEn('Sabitlemeyi kaldır', 'Unpin', 'Lösen')
                      : app.trEn('Sabitle', 'Pin', 'Anheften'),
                  () => _togglePin(msg),
                ),
              // v0.9.0 §4.3: Kaydet (sunucuda, yalnız ben görürüm; karşı tarafa bildirilmez)
              if (!msg.isDeleted)
                action(
                  isStarred ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  isStarred
                      ? app.trEn('Kaydı Kaldır', 'Unsave', 'Nicht mehr speichern')
                      : app.trEn('Kaydet', 'Save', 'Speichern'),
                  () => _toggleSavedMessage(msg),
                  color: isStarred ? const Color(0xFFFFD60A) : null,
                ),
              // v1.2.4: her türde paylaşım (tek görüntülemelik, kişi kartı, konum, video, görsel,
              // anket, etkinlik, belge) uzun basma menüsünden de silinebilir
              if (!msg.isDeleted)
                action(Icons.delete_outline_rounded, app.trEn('Sil', 'Delete', 'Löschen'), () => _confirmDeleteMessage(msg, isMe),
                    color: JuzzioColors.red500),
              // v0.9.0 §4.2: Hatırlat (daha sonra yanıtla)
              if (!msg.isDeleted)
                action(
                  hasReminder != null ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
                  hasReminder != null
                      ? app.trEn('Hatırlatmayı düzenle', 'Edit reminder', 'Erinnerung bearbeiten')
                      : app.trEn('Hatırlat', 'Remind me', 'Erinnern'),
                  () => _pickMessageReminder(msg, hasReminder),
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
          JuzzioSpaceHeader(
            eyebrow: appCtrl.trEn('Sesli ve görüntülü', 'Voice & video', 'Sprache & Video'),
            title: JuzzioSpaceBrand(text: appCtrl.trEn('Aramalar', 'Calls', 'Anrufe'), size: 32),
            actions: [
              JuzzioSpaceComposeButton(
                icon: Icons.add_ic_call_outlined,
                tooltip: appCtrl.trEn('Yeni arama başlat', 'Start new call', 'Neuen Anruf starten'),
                onTap: () => _showSelectFriendToCallSheet(p, s),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(JuzzioSpaceMetrics.gutter, 0, JuzzioSpaceMetrics.gutter, 16),
            child: JuzzioSpaceSearchBar(
              hint: appCtrl.trEn('Kişi veya grup ara', 'Search people or groups', 'Personen oder Gruppen suchen'),
              shortcutLabel: null,
              onChanged: (v) => setState(() => _callsSearchQuery = v),
            ),
          ),
          const JuzzioSpaceDivider(),
          Expanded(
            child: Container(
              width: double.infinity,
              // v1.0.0: ayrı "çekmece" yerine zeminle bütünleşik liste (Juzzio Space)
              // v1.2.4: aşağı çekerek yenileme (bebek eli) + çevrimdışı önbellek
              child: JuzzioClothRefresh(
               onRefresh: _refreshCallLogs,
               child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
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
                            child: JuzzioSpaceFilterPill(
                              label: f[1],
                              selected: _callsFilter == f[0],
                              onTap: () => setState(() => _callsFilter = f[0]),
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
                            // v1.2.1: yön oku satırın simgesinde zaten var — metinde ikinci ok yazılmaz ("↗ ↗ Sesli" hatası)
                            '${log.isVideo ? appCtrl.trEn("Görüntülü", "Video", "Video") : appCtrl.trEn("Sesli", "Voice", "Sprache")} • $statusLabel • $when',
                        isVideo: log.isVideo,
                        outgoing: isOutgoing,
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
    bool outgoing = true,
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
                      isVideo ? Icons.videocam_outlined : (outgoing ? Icons.call_made_rounded : Icons.call_received_rounded),
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
    showJuzzioSheet(
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
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
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
                              backgroundColor: p.accentDeep,
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
                                backgroundColor: p.coolButtonBg,
                                foregroundColor: p.coolButtonFg,
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
                                        color: f.isEffectivelyOnline ? p.onlineGreen : JuzzioGlassTokens.textMuted,
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
    return Column(children: [
      _buildLifeCenterEntryBar(p, appCtrl),
      Expanded(child: JuzzioProfileView(
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
    )),
    ]);
  }

  /// Ana Sayfa kaldırıldığı için Yaşam Merkezi (görevler, takvim, hatırlatıcılar) profilden açılır.
  Widget _buildLifeCenterEntryBar(JuzzioPalette p, JuzzioAppController appCtrl) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: JuzzioGlass(
          radius: 18,
          child: ListTile(
            leading: Icon(Icons.checklist_rounded, color: p.amberGlow),
            title: Text(appCtrl.trEn('Görevlerim ve hatırlatıcılar', 'My tasks & reminders', 'Aufgaben & Erinnerungen'),
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
            trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
            onTap: () => JuzzioLifeCenterPage.open(context),
          ),
        ),
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

    showJuzzioSheet(
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
                                          ? p.activeNavIndigo.withValues(alpha: 0.15)
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
                        backgroundColor: p.coolButtonBg,
                        foregroundColor: p.coolButtonFg,
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
    // v1.0.0 Juzzio Space (Figma): Sohbetler · Keşfet · Aramalar · Bildirimler · Profil.
    // Sekme indeksleri geriye uyum için korunur (0, 3, 1, 6, 4).
    final unreadChats = _conversations.fold<int>(0, (sum, c) => sum + (c.isMuted ? 0 : c.unreadCount));
    const tabIndex = [0, 3, 1, 6, 4];
    final items = [
      JuzzioSpaceNavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: app.trEn('Sohbetler', 'Chats', 'Chats'), badge: unreadChats),
      JuzzioSpaceNavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: app.trEn('Keşfet', 'Explore', 'Entdecken')),
      JuzzioSpaceNavItem(icon: Icons.call_outlined, activeIcon: Icons.call_rounded, label: app.trEn('Aramalar', 'Calls', 'Anrufe')),
      JuzzioSpaceNavItem(icon: Icons.notifications_none_rounded, activeIcon: Icons.notifications_rounded, label: app.trEn('Bildirimler', 'Alerts', 'Hinweise')),
      JuzzioSpaceNavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: app.trEn('Profil', 'Profile', 'Profil')),
    ];
    final sel = tabIndex.indexOf(_selectedBottomTab == 2 ? 0 : _selectedBottomTab);
    return JuzzioSpaceBottomNav(
      items: items,
      selected: sel < 0 ? 0 : sel,
      onTap: (i) => setState(() {
        _selectedBottomTab = tabIndex[i];
        if (_selectedBottomTab == 0 && _selectedFilterIndex == 3) _selectedFilterIndex = 0;
      }),
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

  /// v0.9.3: son mesajın gerçek önizlemesi. Sunucu şifreli mesajın içeriğini bilmez ("🔒 Şifreli
  /// mesaj") — son mesaj önce cihazdaki önbellekten, yoksa ağdan alınıp CİHAZDA çözülür.
  Future<void> _refreshLastPreviews(List<JuzzioConversation> list) async {
    final svc = SupabaseService.instance;
    final jobs = <Future<void>>[];
    for (final c in list.take(60)) {
      if (c.lastMessageAt == null) continue;
      final key = '${c.lastMessageAt!.toIso8601String()}|${c.lastMessagePreview ?? ''}';
      if (_lastPreviewKeys[c.roomId] == key) continue;
      final serverPreview = (c.lastMessagePreview ?? '').trim();
      final needsLocal = serverPreview.isEmpty || serverPreview.startsWith('🔒');
      if (!needsLocal) {
        _lastPreviewKeys[c.roomId] = key;
        _lastPreviews.remove(c.roomId);
        continue;
      }
      jobs.add(() async {
        try {
          final m = await svc.lastMessageForPreview(c.roomId, lastMessageAt: c.lastMessageAt);
          if (m == null) return;
          final text = juzzioMessagePreviewText(m, JuzzioAppController.instance);
          if (text.isEmpty) return;
          _lastPreviewKeys[c.roomId] = key;
          _lastPreviews[c.roomId] = text;
        } catch (_) {}
      }());
    }
    if (jobs.isEmpty) return;
    await Future.wait(jobs);
    if (mounted) setState(() {});
  }

  String _conversationSubtitle(JuzzioConversation c, JuzzioAppController appCtrl) {
    final preview = (_lastPreviews[c.roomId] ?? c.lastMessagePreview ?? '').trim();
    if (preview.isEmpty) {
      // v0.9.7: mesajı olan sohbette önizleme hazırlanırken "dokun" yazısı yerine iskelet gösterilir
      if (c.lastMessageAt != null && !c.isGroup) return kJuzzioPreviewPending;
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
                                        backgroundColor: p.accentDeep,
                                        backgroundImage: user.avatarUrl != null &&
                                                user.avatarUrl!.isNotEmpty
                                            ? JuzzioCachedImageProvider(user.avatarUrl!)
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
                                  child: JuzzioOrbitLoader(color: Colors.white, strokeWidth: 2),
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
  final void Function(String userId)? onOpenProfile;

  const JuzzioStoryViewerModal({
    super.key,
    required this.story,
    this.playlist = const [],
    this.initialIndex = 0,
    this.viewerProfile,
    required this.onOpenChatAfterReply,
    this.onOpenProfile,
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
  // v0.9.5: hikâyeye sesli / görüntülü yanıt
  final AudioRecorder _storyRecorder = AudioRecorder();
  bool _storyRecording = false;
  DateTime? _storyRecStart;

  Future<void> _toggleStoryVoiceReply() async {
    if (_isMine || _isSending) return;
    if (!_storyRecording) {
      if (!await _storyRecorder.hasPermission()) return;
      _setPaused(true);
      final dir = await getTemporaryDirectory();
      await _storyRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 44100),
          path: '${dir.path}/story_reply_${DateTime.now().millisecondsSinceEpoch}.m4a');
      HapticFeedback.mediumImpact();
      setState(() {
        _storyRecording = true;
        _storyRecStart = DateTime.now();
      });
      return;
    }
    final path = await _storyRecorder.stop();
    final ms = DateTime.now().difference(_storyRecStart ?? DateTime.now()).inMilliseconds;
    setState(() => _storyRecording = false);
    if (path == null || ms < 700) {
      _setPaused(false);
      return;
    }
    await _sendStoryMediaReply(voice: File(path), voiceMs: ms);
  }

  Future<void> _sendStoryVideoReply() async {
    if (_isMine || _isSending) return;
    _setPaused(true);
    final picked = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
    if (picked == null || !mounted) {
      _setPaused(false);
      return;
    }
    await _sendStoryMediaReply(video: File(picked.path));
  }

  /// Hikâye bağlamı (kart) + ardından ses/video aynı birebir sohbete gider.
  Future<void> _sendStoryMediaReply({File? voice, int voiceMs = 0, File? video}) async {
    final app = JuzzioAppController.instance;
    setState(() => _isSending = true);
    try {
      final roomId = await SupabaseService.instance.replyToStory(
        story: _current,
        replyText: voice != null ? '🎤 ${app.trEn('Sesli yanıt', 'Voice reply', 'Sprachantwort')}' : '🎬 ${app.trEn('Görüntülü yanıt', 'Video reply', 'Videoantwort')}',
      );
      if (roomId == null) throw Exception('no_room');
      if (voice != null) {
        await SupabaseService.instance.sendVoiceNote(
          audioFile: voice,
          durationMs: voiceMs,
          sourceLang: app.subtitleLang,
          waveformPeaks: const [],
          targetRoomId: roomId,
        );
      } else if (video != null) {
        await SupabaseService.instance.sendMediaMessage(roomId: roomId, file: video, isVideo: true);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onOpenChatAfterReply(roomId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.redAccent, content: Text(SupabaseService.instance.friendlyError(e))));
      _setPaused(false);
    }
  }

  static const List<String> _storyQuickEmojis = ['❤️', '🔥', '😍', '👏', '😂', '😮'];

  JuzzioStory get _current => _items[_index];
  bool get _isMine => _current.userId == SupabaseService.instance.currentUserId;

  /// v0.9.3: sol üstteki paylaşan bilgisine dokunma → profil (Juzzio Official → @tugkancr)
  void _openPosterProfile(JuzzioStory st) {
    final cb = widget.onOpenProfile;
    if (cb == null || st.userId.isEmpty) return;
    HapticFeedback.selectionClick();
    _setPaused(true);
    Navigator.of(context).pop();
    cb(st.userId);
  }

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
    // v0.9.3: fotoğraf/metin durumları 30 sn gösterilir (önce 7 sn); dokunarak geçilebilir
    return JuzzioConfig.storyImageDisplayMs;
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
    _storyRecorder.dispose();
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
    await showJuzzioSheet<void>(
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
                const Center(child: JuzzioOrbitLoader(color: Colors.white))
              else if (st.mediaType == 'image' && hasRemoteMedia)
                JuzzioMediaFilters.apply(
                  st.filterPreset,
                  JuzzioStorageImage(
                    st.mediaUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null ? child : const Center(child: JuzzioOrbitLoader(color: Colors.white)),
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
                              child: JuzzioSparklerBar(
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
                        Expanded(
                          child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openPosterProfile(st),
                          child: Row(
                          children: [
                        if (st.isOfficial)
                          const JuzzioOfficialAvatar(radius: 20)
                        else
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
                                      st.isOfficial ? 'Juzzio Official' : st.displayName,
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
                                  if (st.isOfficial) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified_rounded, color: Color(0xFF1D9BF0), size: 16),
                                  ],
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
                          ],
                          ),
                          ),
                        ),
                        // v1.2.4: hikâyeyi birebir sohbete veya gruba ilet
                        if (widget.viewerProfile != null && st.visibility != 'private')
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: appCtrl.trEn('Sohbete ilet', 'Forward to chat', 'An Chat senden'),
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            onPressed: () async {
                              _setPaused(true);
                              final name = st.displayName.isNotEmpty ? st.displayName : '@${st.username}';
                              final cap = (st.captionTranslated.isNotEmpty ? st.captionTranslated : st.captionOriginal).trim();
                              await showJuzzioShareToChatsSheet(
                                context: context,
                                currentUser: widget.viewerProfile!,
                                title: appCtrl.trEn('Hikâyeyi ilet', 'Forward story', 'Story weiterleiten'),
                                link: 'juzzio://story/${st.id}',
                                shareText: '📖 ${appCtrl.trEn('$name hikâyesi', "$name's story", 'Story von $name')}'
                                    '${cap.isEmpty ? '' : ': $cap'} (juzzio://story/${st.id})',
                              );
                              if (mounted) _setPaused(false);
                            },
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
                          color: Colors.black.withValues(alpha: 0.62),
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
                          color: Colors.white.withValues(alpha: 0.12),
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
                          color: Colors.white.withValues(alpha: 0.12),
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
                            tooltip: JuzzioAppController.instance.trEn('Sesli yanıt (dokun: başlat / bitir)', 'Voice reply (tap to start / stop)', 'Sprachantwort'),
                            onPressed: _toggleStoryVoiceReply,
                            icon: Icon(_storyRecording ? Icons.stop_circle_rounded : Icons.mic_rounded, color: _storyRecording ? Colors.redAccent : Colors.white),
                          ),
                          IconButton(
                            tooltip: JuzzioAppController.instance.trEn('Görüntülü yanıt', 'Video reply', 'Videoantwort'),
                            onPressed: _sendStoryVideoReply,
                            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                          ),
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
                                fillColor: Colors.white.withValues(alpha: 0.14),
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
                                color: Colors.white.withValues(alpha: 0.14),
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
                                      child: JuzzioOrbitLoader(strokeWidth: 2, color: Colors.white),
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


/// "Yazıyor" sonrası animasyonlu üç nokta. Azaltılmış harekette sabit "...".
class _JuzzioTypingDots extends StatefulWidget {
  const _JuzzioTypingDots({required this.style, required this.animate});
  final TextStyle style;
  final bool animate;

  @override
  State<_JuzzioTypingDots> createState() => _JuzzioTypingDotsState();
}

class _JuzzioTypingDotsState extends State<_JuzzioTypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _JuzzioTypingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return Text('...', style: widget.style);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final n = (_c.value * 4).floor().clamp(0, 3);
        // Genişlik sabit kalsın diye görünmeyen noktalar şeffaf çizilir (başlık titremez)
        return Text.rich(TextSpan(children: [
          TextSpan(text: '.' * n, style: widget.style),
          TextSpan(text: '.' * (3 - n), style: widget.style.copyWith(color: Colors.transparent)),
        ]));
      },
    );
  }
}

/// v0.9.3: sesli mesaj süresi (m:ss; 1 saat üstü h:mm:ss). Süre bilinmiyorsa "0:00".
String juzzioFormatVoiceDuration(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// v0.9.3: sohbet listesi için mesaj önizlemesi (türüne göre simge + metin; tek satır).
String juzzioMessagePreviewText(JuzzioMessage m, JuzzioAppController app) {
  if (m.isDeleted) return app.trEn('Bu mesaj silindi', 'This message was deleted', 'Diese Nachricht wurde gelöscht');
  final text = m.originalText.trim().replaceAll(RegExp(r'\s+'), ' ');
  switch (m.messageType) {
    case 'voice':
      return '🎤 ${app.trEn('Sesli mesaj', 'Voice message', 'Sprachnachricht')}';
    case 'image':
      if (m.isViewOnce) return '1️⃣ ${app.trEn('Tek seferlik fotoğraf', 'View-once photo', 'Einmal-Foto')}';
      return text.isNotEmpty ? '📷 $text' : '📷 ${app.trEn('Fotoğraf', 'Photo', 'Foto')}';
    case 'video':
      return text.isNotEmpty ? '🎬 $text' : '🎬 Video';
    case 'document':
      return '📄 ${m.documentName ?? app.trEn('Belge', 'Document', 'Dokument')}';
    case 'location':
      return '📍 ${app.trEn('Konum', 'Location', 'Standort')}';
    case 'call':
      return '📞 ${app.trEn('Arama', 'Call', 'Anruf')}';
  }
  if (text.isEmpty || text == '🔒') return '';
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

/// v0.9.3: "Juzzio Official" hesabının logolu yuvarlak avatarı
class JuzzioOfficialAvatar extends StatelessWidget {
  final double radius;
  const JuzzioOfficialAvatar({super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B1220), Color(0xFF1D2B4F)]),
      ),
      padding: EdgeInsets.all(radius * 0.28),
      child: Image.asset(
        'assets/logo/juzzio_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(
          child: Text('J', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: radius * 0.95)),
        ),
      ),
    );
  }
}
