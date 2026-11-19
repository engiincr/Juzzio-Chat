// =============================================================================
// JUZZIO v0.5.0 - LiveKit SFU + Deepgram WebSocket canlı altyazı motoru
//  • Bölüt (segment) tabanlı: her konuşma bölütü kendi kimliğiyle tek kayıt olur.
//    Ara (interim) sonuçlar aynı bölütü yerinde günceller; kesinleşince kilitlenir.
//  • Önceki metinler yeni metinlere EKLENMEZ: uzun aramalarda (70+ dk) birikme,
//    "kaldığı yerden devam / araya girdi" birleştirmeleri tamamen kaldırıldı.
//  • Geçmiş üst sınırlıdır (bellek sabit kalır).
//  • Konuşan kişi bilgisi LiveKit ses etkinliğinden (isSpeaking) gelir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show EventChannel, MethodChannel;
import 'package:livekit_client/livekit_client.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import 'juzzio_features_service.dart';
import 'juzzio_speech_gate.dart';
import 'supabase_service.dart';

enum NetworkHealthLevel {
  excellent,
  good,
  fair,
  poor,
}

class LiveSubtitlePacket {
  final String id;
  final String speakerId;
  final String speakerName;
  final String speakerUsername;
  final String voiceFingerprint;
  final String gender;
  final String sourceLang;
  final String targetLang;
  final String originalText;
  final String translatedText;
  final bool isFinal;
  final DateTime timestamp;

  const LiveSubtitlePacket({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    String? speakerUsername,
    this.voiceFingerprint = 'VF-SYNC',
    required this.gender,
    required this.sourceLang,
    required this.targetLang,
    required this.originalText,
    required this.translatedText,
    required this.isFinal,
    required this.timestamp,
  }) : speakerUsername = speakerUsername ?? speakerName;

  String get formattedHandle {
    final raw = speakerUsername.trim().isNotEmpty ? speakerUsername.trim() : speakerName.trim();
    final clean = raw.replaceAll('@', '').replaceAll(' ', '').toLowerCase();
    return '@${clean.isEmpty ? "user" : clean}';
  }

  Map<String, dynamic> toJson() => {
        'type': 'juzzio_subtitle',
        'id': id,
        'speakerId': speakerId,
        'speakerName': speakerName,
        'speakerUsername': speakerUsername,
        'voiceFingerprint': voiceFingerprint,
        'gender': gender,
        'sourceLang': sourceLang,
        'targetLang': targetLang,
        'originalText': originalText,
        'translatedText': translatedText,
        'isFinal': isFinal,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LiveSubtitlePacket.fromJson(Map<String, dynamic> json) {
    final sName = (json['speakerName'] ?? 'Partner').toString();
    return LiveSubtitlePacket(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString(),
      speakerId: (json['speakerId'] ?? '').toString(),
      speakerName: sName,
      speakerUsername: (json['speakerUsername'] ?? sName).toString(),
      voiceFingerprint: (json['voiceFingerprint'] ?? 'VF-SYNC').toString(),
      gender: (json['gender'] ?? 'female').toString(),
      sourceLang: (json['sourceLang'] ?? 'auto').toString(),
      targetLang: (json['targetLang'] ?? 'tr').toString(),
      originalText: (json['originalText'] ?? '').toString(),
      translatedText: (json['translatedText'] ?? '').toString(),
      isFinal: json['isFinal'] == true,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Çeviri, metnin kendisinden anlamlı biçimde farklı mı? (büyük/küçük harf, noktalama ve
/// boşluk farkı "aynı dil" sayılır → çeviri gösterilmez)
bool juzzioInCallNeedsTranslation(String original, String translated) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), '');
  final a = norm(original), b = norm(translated);
  return b.isNotEmpty && a != b;
}

/// Arama içi tek mesaj
class JuzzioInCallMessage {
  JuzzioInCallMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.lang,
    this.mine = false,
  }) : at = DateTime.now();
  final String id, senderId, senderName, text, lang;
  final bool mine;
  final DateTime at;
  String? translated;
}

class DeepgramLiveKitController extends ChangeNotifier {
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  IOWebSocketChannel? _deepgramChannel;
  StreamSubscription? _deepgramSub;
  StreamSubscription<Uint8List>? _audioStreamSub;
  Timer? _keepAliveTimer;
  Timer? _networkProbeTimer;

  final AudioRecorder _sharedAudioTap = AudioRecorder();

  /// v1.1.0: yalnız gerçekten konuşurken tanıyıcıya gerçek ses gider (hayalet metin yok)
  final JuzzioSpeechGate _speechGate = JuzzioSpeechGate();

  /// Açık bölütün ara metni ekranda/karşıda gösterildi mi (reddedilirse geri çekilir)
  bool _myOpenSegmentShown = false;

  /// LiveKit'in (yankısı temizlenmiş izde) beni son konuşur gördüğü an
  DateTime _lastLocalSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool isConnected = false;
  bool isMicEnabled = true;

  /// v1.2.8: bağlantı koptu, yeniden bağlanılıyor (arayüzde "Yeniden bağlanıyor…")
  bool isReconnecting = false;
  int _rejoinAttempts = 0;
  String _lastAccessUrl = '';
  String _lastAccessToken = '';

  // ---------------------------------------------------------------------------
  // v1.2.9: YEDEK TURN + yeniden bağlanma
  //  • İlk bağlantı kurulamazsa aynı oda yedek TURN (ExpressTURN) üzerinden denenir.
  //  • Kopmada 5 kez yeniden katılma denenir; 2. denemeden itibaren yedek TURN kullanılır.
  //  • Ana sunucuya ulaşılamadığı görülürse 30 dk boyunca aramalar doğrudan yedekle başlar.
  // ---------------------------------------------------------------------------
  static const int maxRejoinAttempts = 5;
  int get rejoinAttempt => _rejoinAttempts;
  bool usingBackupTurn = false;
  List<JuzzioIceServer> _backupIce = const [];
  static DateTime? _preferBackupUntil;
  static bool get preferBackupTurn => _preferBackupUntil != null && DateTime.now().isBefore(_preferBackupUntil!);
  // v1.2.9 düzeltme: yedek aktarıcı LiveKit'in kendi sunucularının YERİNE geçer (istemci birleştirmez) ve
  // ücretsiz olduğundan yavaştır. Tercih süresi 30 dk → 3 dk: yalnız gerçek bir bağlantı hatasından hemen
  // sonraki denemeler yedekle başlar; kalıcı olarak yedekte kalıp gecikme/donma yaratmaz.
  static void markPrimaryUnreachable() => _preferBackupUntil = DateTime.now().add(const Duration(minutes: 3));
  static void clearBackupPreference() => _preferBackupUntil = null;

  ConnectOptions _connectOptions(bool backup) =>
      !backup || _backupIce.isEmpty ? const ConnectOptions() : juzzioBackupConnectOptions(_backupIce);

  /// Karşı tarafın bağlantısı koptu (açıkça kapatmadı): ad + ne zamandan beri
  String? peerReconnectingName;
  DateTime? peerDroppedAt;
  Timer? _peerGraceTimer;
  bool _remoteEndedExplicitly = false;
  static const Duration peerGrace = Duration(seconds: 30);

  /// Uzak görüntü kademesi (katılımcı sid → 'HIGH' | 'MEDIUM' | 'LOW')
  final Map<String, String> remoteVideoTier = {};
  bool localNetworkWeak = false;

  Future<void> _rejoin() async {
    await Future<void>.delayed(Duration(milliseconds: 1000 * _rejoinAttempts.clamp(1, 5)));
    final room = _room;
    if (room == null || _isDisconnecting || _isDisposed) return;
    final backup = _rejoinAttempts >= 3 && _backupIce.isNotEmpty; // önce ana yol 2 kez denenir
    if (backup && !usingBackupTurn) {
      usingBackupTurn = true;
      notifyListeners();
    }
    try {
      await room.connect(_lastAccessUrl, _lastAccessToken, connectOptions: _connectOptions(backup));
      await room.localParticipant?.setMicrophoneEnabled(isMicEnabled);
      if (isCameraEnabled) await room.localParticipant?.setCameraEnabled(true);
      isConnected = true;
      isReconnecting = false;
      if (backup) markPrimaryUnreachable();
      notifyListeners();
      unawaited(_broadcastNetState('reconnected'));
      _deepgramChannel = null;
      await ensureSubtitles();
    } catch (_) {
      if (_rejoinAttempts < maxRejoinAttempts && !_isDisconnecting && !_isDisposed) {
        _rejoinAttempts++;
        await _rejoin();
      } else {
        _releaseLocalMediaSilently();
        isConnected = false;
        isReconnecting = false;
        notifyListeners();
      }
    }
  }
  bool isCameraEnabled = true;
  bool isSpeakerphoneOn = true;

  VoidCallback? onRemoteCallEnded;
  /// Yönetici bu kişiyi konferanstan çıkardığında (LiveKit RemoveParticipant)
  VoidCallback? onRemovedFromCall;
  /// v0.6 içerik denetimi: bu kişinin görüntüsü/konuşması ihlal sayıldı (arama sunucuda kapatıldı)
  void Function(String message)? onModerationViolation;
  Timer? _moderationTimer;
  bool _moderationBusy = false;
  bool _moderationTripped = false;
  VoidCallback? onForeignParticipantDetected;

  /// Bir katılımcının bağlantı kalitesi değişti (ağ hızı uyarısı için).
  void Function(String identity, String displayName, ConnectionQuality quality, bool isLocal)? onParticipantQualityChanged;

  /// v1.1.0 (#04 Floating hearts): bir katılımcı anlık tepki gönderdi
  void Function(String identity, String emoji)? onCallReaction;

  /// Aramada gönderilebilen tepkiler (beyaz liste: rastgele metin yayınlanamaz)
  static const List<String> kCallReactions = ['❤️', '😂', '👏', '🔥', '😮', '👍', '🎉', '😢'];

  /// Anlık tepkiyi herkese yayınlar ve kendi ekranımda da gösterir
  Future<void> sendCallReaction(String emoji) async {
    if (!kCallReactions.contains(emoji)) return;
    onCallReaction?.call(_myIdentity, emoji);
    try {
      await _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'type': 'juzzio_reaction', 'emoji': emoji})),
        reliable: false,
        topic: 'juzzio_fx',
      );
    } catch (_) {}
  }

  /// Arama içi mesajlar (sesli + görüntülü). Gönderen dilini ekler; alıcı kendi dili farklıysa
  /// çevirir, aynı dili konuşuyorsa metin olduğu gibi gösterilir (çeviri yapılmaz).
  final List<JuzzioInCallMessage> inCallMessages = [];
  int inCallUnread = 0;
  bool inCallChatOpen = false;

  Future<void> sendInCallMessage(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final clipped = text.length > 500 ? text.substring(0, 500) : text;
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_myIdentity.hashCode}';
    inCallMessages.add(JuzzioInCallMessage(
        id: id, senderId: _myIdentity, senderName: _myName, text: clipped, lang: _myLang, mine: true));
    if (inCallMessages.length > 200) inCallMessages.removeAt(0);
    notifyListeners();
    try {
      await _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'type': 'juzzio_chat', 'id': id, 'text': clipped, 'lang': _myLang, 'name': _myName})),
        reliable: true,
        topic: 'juzzio_chat',
      );
    } catch (_) {}
  }

  Future<void> _onInCallMessage(Map<String, dynamic> map, Participant? sender) async {
    final text = (map['text']?.toString() ?? '').trim();
    if (text.isEmpty || text.length > 500) return;
    final lang = (map['lang']?.toString() ?? '').toLowerCase();
    final rawName = map['name']?.toString().trim() ?? '';
    final name = rawName.isNotEmpty ? (rawName.length > 40 ? rawName.substring(0, 40) : rawName) : (sender?.name ?? '');
    final msg = JuzzioInCallMessage(
        id: map['id']?.toString() ?? '${DateTime.now().microsecondsSinceEpoch}',
        senderId: sender?.identity ?? '',
        senderName: name,
        text: text,
        lang: lang);
    inCallMessages.add(msg);
    if (inCallMessages.length > 200) inCallMessages.removeAt(0);
    if (!inCallChatOpen) inCallUnread++;
    notifyListeners();
    // v1.3.0 düzeltme: çeviri kararı gönderenin PROFİL diline göre veriliyordu; profil dili
    // alıcınınkiyle aynı görünüp kişi başka dilde yazınca (ör. @ari) hiç çevrilmiyordu.
    // Artık altyazılar gibi kaynak dil metinden otomatik algılanır; sonuç metnin aynısıysa
    // (aynı dili konuşanlar) çeviri gösterilmez.
    var target = baseLang(JuzzioAppController.instance.subtitleLang);
    if (target.isEmpty) target = _myLang;
    try {
      final t = (await SupabaseService.instance
              .translateText(text: text, sourceLang: 'auto', targetLang: target)
              .timeout(const Duration(seconds: 10)))
          .trim();
      if (t.isNotEmpty && juzzioInCallNeedsTranslation(text, t)) {
        msg.translated = t;
        notifyListeners();
      }
    } catch (_) {}
  }

  void markInCallChatRead() {
    if (inCallUnread == 0) return;
    inCallUnread = 0;
    notifyListeners();
  }

  /// Başka bir katılımcının pil seviyesi kritik eşiğe indi (%10 / %5).
  void Function(String identity, String displayName, int level)? onRemoteBatteryLow;

  bool _isDisconnecting = false;

  int latencyMs = 26;
  ConnectionQuality liveKitQuality = ConnectionQuality.excellent;
  NetworkHealthLevel networkHealth = NetworkHealthLevel.excellent;

  final Map<String, String> participantLanguages = {};

  String _myVoiceFingerprint = 'VF-INIT';

  /// Geçmişte tutulan en fazla bölüt sayısı (uzun aramada bellek sabit kalır)
  static const int maxHistory = 120;

  /// Konuşmacıya göre o an süren (henüz kesinleşmemiş) bölüt
  final Map<String, LiveSubtitlePacket> interimBySpeaker = {};

  /// Kesinleşmiş bölüt kimlikleri: geç gelen ara çeviri sonuçları bunları ezemez
  final Set<String> _finalizedSegmentIds = <String>{};

  // Kendi konuşmam için bölüt sayacı ve ara çeviri sırası
  int _mySegmentSeq = 0;
  String? _myOpenSegmentId;
  int _interimTranslateTicket = 0;
  DateTime _lastInterimTranslateAt = DateTime.fromMillisecondsSinceEpoch(0);

  int get signalBars {
    switch (networkHealth) {
      case NetworkHealthLevel.excellent:
        return 4;
      case NetworkHealthLevel.good:
        return 3;
      case NetworkHealthLevel.fair:
        return 2;
      case NetworkHealthLevel.poor:
        return 1;
    }
  }

  String get networkStatusLabel {
    final app = JuzzioAppController.instance;
    switch (networkHealth) {
      case NetworkHealthLevel.excellent:
        return app.trEn('Mükemmel', 'Excellent', 'Ausgezeichnet');
      case NetworkHealthLevel.good:
        return app.trEn('İyi', 'Good', 'Gut');
      case NetworkHealthLevel.fair:
        return app.trEn('Orta', 'Fair', 'Mittel');
      case NetworkHealthLevel.poor:
        return app.trEn('Zayıf', 'Poor', 'Schwach');
    }
  }

  final List<LiveSubtitlePacket> subtitleHistory = [];
  String? myInterimText;
  String? remoteInterimText;
  String? activeInterimSpeakerHandle;
  LiveSubtitlePacket? myLatestSubtitle;
  LiveSubtitlePacket? remoteLatestSubtitle;

  String _myIdentity = '';
  String _myName = '';
  String _myLang = 'tr';
  String _activeRoomName = '';
  String get activeRoomName => _activeRoomName;

  String get myLang => _myLang;

  /// 'tr-TR', 'tr_tr', 'TR' → 'tr'
  static String baseLang(String l) {
    final v = l.trim().toLowerCase();
    if (v.isEmpty) return '';
    return v.split(RegExp(r'[-_]')).first;
  }

  bool _isForeign(String lang) {
    final b = baseLang(lang);
    return b.isNotEmpty && b != baseLang(_myLang);
  }
  String get targetLang {
    for (final rLang in participantLanguages.values) {
      if (_isForeign(rLang)) {
        return rLang;
      }
    }
    return _myLang == 'tr' ? 'en' : 'tr';
  }

  String get myGender => _myLang == 'tr' ? 'male' : 'female';

  /// v1.2.8: arama sırasında konuşulan dil (tanıyıcının dili)
  String get myLanguageCode => _myLang;

  Room? get room => _room;
  LocalParticipant? get localParticipant => _room?.localParticipant;
  List<RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values.toList() ?? [];

  bool get hasForeignParticipant {
    // Yalnızca şu an odada bulunan katılımcılar dikkate alınır
    for (final p in remoteParticipants) {
      if (_isForeign(extractParticipantLanguage(p))) return true;
    }
    return false;
  }

  String extractParticipantLanguage(Participant p) {
    final cached = participantLanguages[p.sid];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      if (p.metadata != null && p.metadata!.trim().isNotEmpty) {
        final meta = jsonDecode(p.metadata!);
        if (meta is Map && meta['preferred_lang'] != null) {
          final l = meta['preferred_lang'].toString().trim().toLowerCase();
          if (l.isNotEmpty) {
            participantLanguages[p.sid] = l;
            return l;
          }
        }
      }
    } catch (_) {}
    final id = p.identity.toLowerCase();
    if (id.contains('_')) {
      final suffix = id.split('_').last.trim();
      if (suffix.length >= 2 && suffix.length <= 5) {
        participantLanguages[p.sid] = suffix;
        return suffix;
      }
    }
    return 'tr';
  }

  /// LiveKit kimliği `<kullanıcıId>_<dil>` biçimindedir; kullanıcı kimliğini döndürür.
  static String userIdFromIdentity(String identity) {
    final i = identity.lastIndexOf('_');
    if (i <= 0) return identity;
    return identity.substring(0, i);
  }

  // Konuşma göstergesi histerezisi: kısa duraksamalarda halka titremez
  static const Duration speakingRelease = Duration(milliseconds: 450);
  final Map<String, DateTime> _speakingUntil = {};
  Timer? _speakingReleaseTimer;

  /// Katılımcı şu an konuşuyor mu? LiveKit sunucusunun ses etkinliği (VAD,
  /// eşik ve yumuşatma sunucuda) + istemcide 450 ms bırakma gecikmesi.
  bool isParticipantSpeaking(Participant? p) {
    if (p == null) return false;
    try {
      final now = DateTime.now();
      if (p.isSpeaking) {
        _speakingUntil[p.identity] = now.add(speakingRelease);
        return true;
      }
      final until = _speakingUntil[p.identity];
      return until != null && now.isBefore(until);
    } catch (_) {
      return false;
    }
  }

  void _onActiveSpeakersChanged() {
    // v1.1.0: yankı süzgeci için yerel konuşmanın son anı (sonuçlar gecikmeli gelir)
    try {
      if (localParticipant?.isSpeaking ?? false) _lastLocalSpeakAt = DateTime.now();
    } catch (_) {}
    notifyListeners();
    // Bırakma süresi dolunca halkanın kapanması için bir kez daha çiz
    _speakingReleaseTimer?.cancel();
    _speakingReleaseTimer = Timer(speakingRelease + const Duration(milliseconds: 60), notifyListeners);
  }

  /// O an konuşan katılımcıların kimlikleri (yerel dahil)
  Set<String> get speakingIdentities {
    final out = <String>{};
    final local = localParticipant;
    if (local != null && isMicEnabled && isParticipantSpeaking(local)) out.add(local.identity);
    for (final p in remoteParticipants) {
      if (isParticipantSpeaking(p)) out.add(p.identity);
    }
    return out;
  }

  /// PCM16 ses örneklerinden konuşmacının akustik ses izini (Voice Fingerprint) hesaplar
  void _updateVoiceFingerprintFromPcm(Uint8List pcmChunk) {
    if (pcmChunk.length < 4) return;
    double sumSq = 0;
    int zeroCrossings = 0;
    int prevSample = 0;
    final sampleCount = min(pcmChunk.length ~/ 2, 256);
    final bd = ByteData.sublistView(pcmChunk);
    for (int i = 0; i < sampleCount; i++) {
      final sample = bd.getInt16(i * 2, Endian.little);
      sumSq += sample * sample;
      if ((sample >= 0 && prevSample < 0) || (sample < 0 && prevSample >= 0)) {
        zeroCrossings++;
      }
      prevSample = sample;
    }
    final rms = sqrt(sumSq / sampleCount);
    if (rms > 320) {
      final zcrBand = ((zeroCrossings * 16) ~/ max(1, sampleCount)).clamp(1, 99);
      final nameHash = _myName.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFF);
      final sigHex = ((nameHash ^ (zcrBand * 257)) & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
      _myVoiceFingerprint = 'SES-$sigHex';
    }
  }

  void clearSubtitleHistory() {
    subtitleHistory.clear();
    interimBySpeaker.clear();
    _finalizedSegmentIds.clear();
    myLatestSubtitle = null;
    remoteLatestSubtitle = null;
    myInterimText = null;
    remoteInterimText = null;
    activeInterimSpeakerHandle = null;
    notifyListeners();
  }

  /// Bölüt tabanlı altyazı ekleme.
  ///  • Ara sonuç: o konuşmacının süren bölütünü yerinde günceller.
  ///  • Kesin sonuç: bölütü geçmişe tek kayıt olarak ekler (aynı kimlik varsa
  ///    yerinde değiştirir). Önceki metinlerle ASLA birleştirilmez.
  void addSubtitlePacket(LiveSubtitlePacket packet) {
    if (packet.originalText.trim().isEmpty && packet.translatedText.trim().isEmpty) return;
    final isMine = packet.speakerId == _myIdentity;
    if (packet.isFinal) {
      _finalizedSegmentIds.add(packet.id);
      if (_finalizedSegmentIds.length > maxHistory * 3) {
        _finalizedSegmentIds.remove(_finalizedSegmentIds.first);
      }
      final existing = subtitleHistory.indexWhere((e) => e.id == packet.id);
      if (existing >= 0) {
        subtitleHistory[existing] = packet;
      } else {
        subtitleHistory.add(packet);
        while (subtitleHistory.length > maxHistory) {
          subtitleHistory.removeAt(0);
        }
      }
      final cur = interimBySpeaker[packet.speakerId];
      if (cur == null || cur.id == packet.id) interimBySpeaker.remove(packet.speakerId);
      if (isMine) {
        myLatestSubtitle = packet;
        myInterimText = null;
      } else {
        remoteLatestSubtitle = packet;
        remoteInterimText = null;
      }
      activeInterimSpeakerHandle = interimBySpeaker.isEmpty ? null : interimBySpeaker.values.last.formattedHandle;
    } else {
      // Kesinleşmiş bir bölüte geç gelen ara sonuç yok sayılır
      if (_finalizedSegmentIds.contains(packet.id)) return;
      interimBySpeaker[packet.speakerId] = packet;
      activeInterimSpeakerHandle = packet.formattedHandle;
      if (isMine) {
        myInterimText = packet.translatedText;
      } else {
        remoteInterimText = packet.translatedText;
      }
    }
    notifyListeners();
  }

  /// Ekranda gösterilecek son bölütler (en yeni sonda): kesinleşmiş son [count]
  /// bölüt + süren ara bölütler. Her bölüt yalnızca kendi metnini taşır.
  List<LiveSubtitlePacket> recentSegments({int count = 3}) {
    final finals = subtitleHistory.length <= count
        ? List<LiveSubtitlePacket>.from(subtitleHistory)
        : subtitleHistory.sublist(subtitleHistory.length - count);
    final live = interimBySpeaker.values.where((p) => !_finalizedSegmentIds.contains(p.id)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final out = [...finals, ...live];
    return out.length <= count ? out : out.sublist(out.length - count);
  }

  Future<void> connectToCall({
    required String identity,
    required String displayName,
    required String myLanguage,
    required bool enableVideo,
    String? livekitRoomName,
  }) async {
    _myIdentity = identity;
    _myName = displayName;
    // Kimliğimizdeki dil (<uid>_<dil>) ile karşılaştırma tutarlı olsun
    final idLang = identity.contains('_') ? identity.split('_').last : '';
    _myLang = baseLang(idLang.length >= 2 && idLang.length <= 5 ? idLang : myLanguage);
    if (_myLang.isEmpty) _myLang = baseLang(JuzzioAppController.instance.subtitleLang);
    if (livekitRoomName == null || livekitRoomName.trim().isEmpty) {
      throw StateError(JuzzioAppController.instance.trEn(
        'Arama odası bulunamadı.',
        'Call room not found.', 'Anrufraum nicht gefunden.',
      ));
    }
    _activeRoomName = livekitRoomName.trim();
    isCameraEnabled = enableVideo;

    final nameHash = _myName.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFF);
    _myVoiceFingerprint = 'SES-${nameHash.toRadixString(16).toUpperCase().padLeft(4, '0')}';

    _rejoinAttempts = 0;
    final access = await SupabaseService.instance.fetchLiveKitToken(
      roomName: _activeRoomName,
      identity: identity,
      displayName: displayName,
      lang: _myLang,
    );

    // v0.9.5: düşük veri modu (≈360p, 15 fps, sessizlikte ses paketi gönderilmez) ve
    // ses izolasyonu (gürültü engelleme + alçak frekans filtresi; ayarlardan kapatılabilir)
    final app = JuzzioAppController.instance;
    final saver = app.dataSaverEnabled;
    final denoise = app.callNoiseFilterEnabled;
    _room = Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // v1.3.0 (kullanıcı isteği: en iyi kalite): kamera 720p / 30 fps yakalar
        defaultCameraCaptureOptions: saver
            ? const CameraCaptureOptions(params: VideoParametersPresets.h360_169)
            : const CameraCaptureOptions(params: VideoParametersPresets.h720_169),
        defaultAudioCaptureOptions: AudioCaptureOptions(
          autoGainControl: true,
          echoCancellation: true,
          noiseSuppression: denoise,
          voiceIsolation: denoise,
          highPassFilter: denoise,
          typingNoiseDetection: denoise,
        ),
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'juzzio_voice_track',
          dtx: saver,
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          name: 'juzzio_video_track',
          simulcast: !saver,
          // v1.3.0 (kullanıcı isteği: internet yavaşlasa da görüntü bozulmasın, en iyi kalite):
          //  • 720p / 30 fps, 2,5 Mbps üst sınır
          //  • kodlayıcı çözünürlüğü KORUR (bant daralırsa önce kare hızı düşer)
          //  • simulcast yedek katmanı 360p/180p yerine 540p → görüntü 540p'nin altına inmez
          //    (katman tamamen kapatılmaz: grup aramasında zayıf ağlı katılımcıda görüntü tümden durur)
          videoEncoding: saver
              ? const VideoEncoding(maxBitrate: 350 * 1000, maxFramerate: 15)
              : const VideoEncoding(maxBitrate: 2500 * 1000, maxFramerate: 30),
          videoSimulcastLayers: saver ? const [] : const [VideoParametersPresets.h540_169],
          degradationPreference: saver ? DegradationPreference.maintainFramerate : DegradationPreference.maintainResolution,
        ),
      ),
    );

    _room!.addListener(notifyListeners);
    _roomListener = _room!.createListener();
    _setupRoomListeners();

    _lastAccessUrl = access.url;
    _lastAccessToken = access.token;
    _backupIce = access.backupIceServers;
    final fast = FastConnectOptions(
      microphone: const TrackOption(enabled: true),
      camera: TrackOption(enabled: enableVideo),
    );
    usingBackupTurn = preferBackupTurn && _backupIce.isNotEmpty;
    try {
      await _room!.connect(access.url, access.token, connectOptions: _connectOptions(usingBackupTurn), fastConnectOptions: fast);
    } catch (e) {
      // v1.2.9: ana yol kurulamadı → önce ANA yol bir kez daha (anlık ağ hatası), sonra yedek TURN
      if (_isDisposed) rethrow;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        usingBackupTurn = false;
        await _room!.connect(access.url, access.token, connectOptions: _connectOptions(false), fastConnectOptions: fast);
      } catch (_) {
        if (_backupIce.isEmpty || _isDisposed) rethrow;
        usingBackupTurn = true;
        notifyListeners();
        await _room!.connect(access.url, access.token, connectOptions: _connectOptions(true), fastConnectOptions: fast);
        markPrimaryUnreachable();
      }
    }

    // v1.2.8: önceden burada gürültü engelleme/ses izolasyonu zorla KAPATILIYORDU (ayar yok
    // sayılıyordu); artık odanın kullanıcı ayarına göre kurulan ses seçenekleri korunur
    // v1.2.9 düzeltme: "TimeoutException: LiveKit Exception" — yayın (publisher) bağlantısı 10 sn'de
    // kurulamayınca mikrofon yayını hata verip aramayı düşürüyordu. Artık 3 kez (1 sn, 2 sn arayla)
    // denenir; yayın bağlantısı çoğu zaman ikinci denemede hazırdır.
    Future<void> publishMic() async {
      await _room!.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: AudioCaptureOptions(
          autoGainControl: true,
          echoCancellation: true,
          noiseSuppression: denoise,
          voiceIsolation: denoise,
          highPassFilter: denoise,
          typingNoiseDetection: denoise,
        ),
      );
    }

    for (var attempt = 1; ; attempt++) {
      try {
        await publishMic();
        break;
      } catch (_) {
        if (attempt >= 3 || _isDisposed || _isDisconnecting || _room == null) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }

    await Hardware.instance.setSpeakerphoneOn(true);
    isConnected = true;
    _syncParticipantLanguages();
    notifyListeners();

    _startNetworkHealthMonitor();
    _startCallModeration();
    await ensureSubtitles();
  }

  bool _subtitleStarting = false;

  /// v0.7.0: Altyazı/çeviri hattı (Deepgram) yalnızca odada farklı dilde biri varsa
  /// ya da kullanıcı çeviriyi elle açtıysa başlatılır. Aynı dili konuşanların sesi
  /// hiçbir üçüncü taraf hizmete gönderilmez.
  ///
  /// v1.2.8: dil bilgisi güvenilmez olabildiği için (ör. karşı tarafın sunucudaki varsayılan
  /// dili "tr" kalmış) odada BAŞKA biri varsa hat her zaman başlar; aynı dil gerçekten
  /// aynıysa alıcı tarafta çeviri zaten atlanır. Deepgram'a ulaşılamazsa cihazın kendi
  /// konuşma tanıyıcısı devreye girer (yedek motor).
  Future<void> ensureSubtitles({bool force = false}) async {
    if (!isConnected || _deepgramChannel != null || _deviceSpeechOn || _subtitleStarting) return;
    if (!force && remoteParticipants.isEmpty) return;
    _subtitleStarting = true;
    try {
      await _startDeepgramSubtitlePipeline();
    } finally {
      _subtitleStarting = false;
    }
  }

  // ---------------------------------------------------------------------------
  // v1.2.8 — altyazı motoru durumu + yeniden bağlanma + cihaz tanıyıcısı yedeği
  // ---------------------------------------------------------------------------
  /// 'off' | 'connecting' | 'deepgram' | 'device' | 'unavailable'
  String captionEngine = 'off';

  /// Son hata nedeni ('' | 'no_key' | 'no_active_call' | 'rate_limited' | 'network' | 'server' | 'device_failed')
  String captionError = '';

  int _deepgramFailures = 0;
  bool _deviceSpeechOn = false;
  StreamSubscription? _deviceSpeechSub;
  static const EventChannel _speechEvents = EventChannel('juzzio/speech_events');

  void _setEngine(String engine, [String error = '']) {
    captionEngine = engine;
    captionError = error;
    notifyListeners();
  }

  /// Deepgram soketi kapanırsa (ağ, token süresi) çağrı sürüyorsa yeniden bağlanır
  void _onDeepgramClosed() {
    _keepAliveTimer?.cancel();
    final sub = _audioStreamSub;
    _audioStreamSub = null;
    () async {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        if (await _sharedAudioTap.isRecording()) await _sharedAudioTap.stop();
      } catch (_) {}
    }();
    _deepgramSub = null;
    _deepgramChannel = null;
    if (!isConnected || _isDisconnecting || _isDisposed) return;
    _deepgramFailures++;
    if (_deepgramFailures >= 4) {
      _startDeviceSpeech('network');
      return;
    }
    _setEngine('connecting');
    Future<void>.delayed(Duration(seconds: 2 * _deepgramFailures), () {
      if (isConnected && !_isDisconnecting && !_isDisposed && _deepgramChannel == null && !_deviceSpeechOn) {
        ensureSubtitles(force: true);
      }
    });
  }

  Future<void> _startDeviceSpeech(String reason) async {
    if (_deviceSpeechOn || !isConnected) return;
    try {
      final ok = await _nativeChannel.invokeMethod('speechAvailable') == true;
      if (!ok) {
        _setEngine('unavailable', reason.isEmpty ? 'device_failed' : reason);
        return;
      }
      _deviceSpeechOn = true;
      _deviceSpeechSub = _speechEvents.receiveBroadcastStream().listen((dynamic e) async {
        if (e is! Map) return;
        final type = e['type']?.toString() ?? '';
        final text = (e['text'] ?? '').toString().trim();
        if (!isMicEnabled) return;
        if (type == 'partial' && text.isNotEmpty) {
          final id = _myOpenSegmentId ??= '${_myIdentity}_${DateTime.now().millisecondsSinceEpoch}_${_mySegmentSeq++}';
          _myOpenSegmentShown = true;
          await _emitOwnSegment(id, text, isFinal: false);
        } else if (type == 'final' && text.isNotEmpty) {
          final id = _myOpenSegmentId ?? '${_myIdentity}_${DateTime.now().millisecondsSinceEpoch}_${_mySegmentSeq++}';
          _myOpenSegmentId = null;
          _myOpenSegmentShown = false;
          await _emitOwnSegment(id, text, isFinal: true);
        }
      }, onError: (_) {});
      await _nativeChannel.invokeMethod('speechStart', {'lang': _myLang});
      _setEngine('device', reason);
    } catch (_) {
      _deviceSpeechOn = false;
      _setEngine('unavailable', 'device_failed');
    }
  }

  Future<void> _stopDeviceSpeech() async {
    if (!_deviceSpeechOn) return;
    _deviceSpeechOn = false;
    try {
      await _deviceSpeechSub?.cancel();
    } catch (_) {}
    _deviceSpeechSub = null;
    try {
      await _nativeChannel.invokeMethod('speechStop');
    } catch (_) {}
  }

  /// Arama sırasında konuşulan dili değiştirir: tanıyıcı yeni dille yeniden başlar
  Future<void> setSpokenLanguage(String lang) async {
    final next = baseLang(lang);
    if (next.isEmpty || next == _myLang) return;
    _myLang = next;
    try {
      await _deepgramSub?.cancel();
    } catch (_) {}
    try {
      await _deepgramChannel?.sink.close();
    } catch (_) {}
    _deepgramChannel = null;
    _deepgramSub = null;
    _keepAliveTimer?.cancel();
    try {
      await _audioStreamSub?.cancel();
      if (await _sharedAudioTap.isRecording()) await _sharedAudioTap.stop();
    } catch (_) {}
    _audioStreamSub = null;
    final wasDevice = _deviceSpeechOn;
    await _stopDeviceSpeech();
    _deepgramFailures = 0;
    if (wasDevice) {
      await _startDeviceSpeech(captionError);
    } else {
      await ensureSubtitles(force: true);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // v0.6 İÇERİK DENETİMİ: kamera açıkken belirli aralıklarla KENDİ görüntümüzden
  // küçük bir kare (360 px) sunucuya gönderilir. Müstehcen görüntüde sunucu cezayı
  // uygular ve aramayı kapatır; burada da arama hemen sonlandırılır.
  // ---------------------------------------------------------------------------
  void _startCallModeration() {
    _moderationTimer?.cancel();
    final cfg = JuzzioFeaturesService.instance.lastAppConfig;
    if (!cfg.callModerationEnabled) return;
    final seconds = cfg.callModerationIntervalSec.clamp(3, 60);
    _moderationTimer = Timer.periodic(Duration(seconds: seconds), (_) => _moderationTick());
  }

  LocalVideoTrack? get _localCameraTrack {
    final pubs = _room?.localParticipant?.videoTrackPublications ?? const <LocalTrackPublication<LocalVideoTrack>>[];
    for (final pub in pubs) {
      final track = pub.track;
      if (track != null && pub.source == TrackSource.camera && !pub.muted) return track;
    }
    return null;
  }

  Future<void> _moderationTick() async {
    if (_moderationBusy || _moderationTripped || !isConnected || !isCameraEnabled) return;
    final track = _localCameraTrack;
    if (track == null) return;
    _moderationBusy = true;
    try {
      final buffer = await track.mediaStreamTrack.captureFrame();
      final small = await _downscaleFrame(buffer.asUint8List(), 360);
      if (small == null || _moderationTripped) return;
      final res = await SupabaseService.instance.moderateCallFrame(
        roomName: _activeRoomName,
        imageBase64: base64Encode(small),
      );
      _handleModerationResult(res);
    } catch (_) {
      // Kare alınamazsa (ör. kamera değişiyor) bir sonraki turda yeniden denenir
    } finally {
      _moderationBusy = false;
    }
  }

  static Future<Uint8List?> _downscaleFrame(Uint8List bytes, int width) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Kendi konuşmamızın kesinleşmiş bölütü: yerel ön elemeden geçerse sunucu doğrular.
  // v0.7.0: Aramalarda küfür ve argo serbesttir; konuşma asla yasak/ceza sebebi değildir.
  // Yalnızca görüntülü aramadaki müstehcen görüntü denetimi (_moderationTick) sürer.
  void _moderateOwnSpeech(String text) {}

  void _handleModerationResult(Map<String, dynamic> res) {
    final violation = res['violation'];
    if (violation is! Map || _moderationTripped) return;
    _moderationTripped = true;
    _moderationTimer?.cancel();
    final app = JuzzioAppController.instance;
    final message = (violation['message'] ?? '').toString().trim();
    onModerationViolation?.call(message.isNotEmpty
        ? message
        : app.trEn('Uygunsuz içerik nedeniyle arama sonlandırıldı.', 'The call was ended due to inappropriate content.',
            'Der Anruf wurde wegen unangemessener Inhalte beendet.'));
  }

  void _syncParticipantLanguages() {
    bool foundForeign = false;
    for (final p in remoteParticipants) {
      if (_isForeign(extractParticipantLanguage(p))) {
        foundForeign = true;
      }
    }
    if (foundForeign) onForeignParticipantDetected?.call();
    if (remoteParticipants.isNotEmpty) ensureSubtitles(); // v1.2.8: dil bilgisine güvenme
  }

  void _setupRoomListeners() {
    _roomListener
      ?..on<RoomConnectedEvent>((_) {
        _syncParticipantLanguages();
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        isReconnecting = false;
        _syncParticipantLanguages();
        notifyListeners();
        unawaited(_broadcastNetState('reconnected'));
      })
      ..on<ParticipantConnectedEvent>((event) {
        // v1.2.9: kopan kişi geri geldi
        _peerGraceTimer?.cancel();
        peerReconnectingName = null;
        peerDroppedAt = null;
        if (_isForeign(extractParticipantLanguage(event.participant))) onForeignParticipantDetected?.call();
        ensureSubtitles(); // v1.2.8: karşı tarafın dil ayarı yanlış olsa da altyazı başlar
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        participantLanguages.remove(event.participant.sid);
        remoteVideoTier.remove(event.participant.sid);
        if (remoteParticipants.isEmpty) {
          if (_remoteEndedExplicitly) {
            onRemoteCallEnded?.call();
          } else {
            // v1.2.9: karşı taraf aramayı kapatmadı, bağlantısı koptu → 30 sn yeniden bağlanmasını bekle
            final n = event.participant.name.trim();
            peerReconnectingName = n.isNotEmpty ? n : event.participant.identity.split('_').first;
            peerDroppedAt = DateTime.now();
            _peerGraceTimer?.cancel();
            _peerGraceTimer = Timer(peerGrace, () {
              if (remoteParticipants.isEmpty) {
                peerReconnectingName = null;
                notifyListeners();
                onRemoteCallEnded?.call();
              }
            });
          }
        }
        notifyListeners();
      })
      ..on<TrackSubscribedEvent>((event) {
        // v1.2.9: yeni abone olunan görüntüye o kişinin güncel kalite kademesi uygulanır
        final tier = localNetworkWeak ? 'LOW' : (remoteVideoTier[event.participant.sid] ?? 'HIGH');
        unawaited(_applyTier(event.participant, tier));
        notifyListeners();
      })
      ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
      ..on<TrackPublishedEvent>((_) => notifyListeners())
      ..on<LocalTrackPublishedEvent>((_) {
        // Kamera yeniden yayınlanınca güzelleştirme yeni izine tekrar bağlanır
        _applyBeautyFilter();
        notifyListeners();
      })
      ..on<TrackUnpublishedEvent>((_) => notifyListeners())
      // v0.9.6: karşı tarafın mikrofon/kamera kapatması anında gösterilir
      ..on<TrackMutedEvent>((_) => notifyListeners())
      ..on<TrackUnmutedEvent>((_) => notifyListeners())
      ..on<ActiveSpeakersChangedEvent>((_) => _onActiveSpeakersChanged())
      ..on<ParticipantNameUpdatedEvent>((_) => notifyListeners())
      ..on<ParticipantMetadataUpdatedEvent>((event) {
        if (_isForeign(extractParticipantLanguage(event.participant))) {
          onForeignParticipantDetected?.call();
        }
        notifyListeners();
      })
      ..on<ParticipantConnectionQualityUpdatedEvent>((event) {
        final isLocal = event.participant.sid == _room?.localParticipant?.sid;
        if (isLocal) {
          // v0.9.7: zayıf ağda geçici düşük güç/bant profili
          localNetworkWeak = event.connectionQuality == ConnectionQuality.poor || event.connectionQuality == ConnectionQuality.lost;
          setLowPowerReason('network', localNetworkWeak);
        } else if (event.participant is RemoteParticipant) {
          // v1.2.9: karşı tarafın ağı zayıfsa yalnız onun görüntüsü 720p → 480p → 360p'ye iner
          final tier = juzzioVideoTierFor(event.connectionQuality, localWeak: localNetworkWeak);
          if (remoteVideoTier[event.participant.sid] != tier) {
            remoteVideoTier[event.participant.sid] = tier;
            unawaited(_applyTier(event.participant as RemoteParticipant, tier));
          }
        }
        if (isLocal || remoteParticipants.isEmpty) {
          liveKitQuality = event.connectionQuality;
          _recalculateHealthLevel();
          notifyListeners();
        }
        final pName = event.participant.name.trim().isNotEmpty
            ? event.participant.name.trim()
            : event.participant.identity;
        onParticipantQualityChanged?.call(event.participant.identity, pName, event.connectionQuality, isLocal);
      })
      ..on<RoomDisconnectedEvent>((event) {
        final reason = event.reason;
        // v1.2.8: beklenmedik kopmada (ağ değişimi, sinyal hatası, yeniden deneme bitti)
        // arama hemen bitmez: aynı odaya 2 kez otomatik yeniden katılmayı dener.
        final intentional = reason == DisconnectReason.participantRemoved ||
            reason == DisconnectReason.clientInitiated ||
            reason == DisconnectReason.duplicateIdentity ||
            reason == DisconnectReason.roomDeleted;
        if (!intentional && !_isDisconnecting && !_isDisposed && _rejoinAttempts < maxRejoinAttempts && _lastAccessUrl.isNotEmpty) {
          _rejoinAttempts++;
          isConnected = false;
          isReconnecting = true;
          notifyListeners();
          _rejoin();
          return;
        }
        // Oda bağlantısı koptuğunda mikrofon/kamera ve ses kaynakları kesin olarak bırakılır.
        _releaseLocalMediaSilently();
        isConnected = false;
        isReconnecting = false;
        notifyListeners();
        if (reason == DisconnectReason.participantRemoved) {
          onRemovedFromCall?.call();
        }
      })
      ..on<RoomReconnectingEvent>((_) {
        isReconnecting = true;
        notifyListeners();
      })
      ..on<DataReceivedEvent>((event) async {
        try {
          final rawText = utf8.decode(event.data);
          final map = jsonDecode(rawText) as Map<String, dynamic>;
          final packetType = map['type']?.toString();

          if (packetType == 'juzzio_call_ended') {
            _remoteEndedExplicitly = true;
            _peerGraceTimer?.cancel();
            peerReconnectingName = null;
            onRemoteCallEnded?.call();
            return;
          }

          if (packetType == 'juzzio_net') {
            // v1.2.9: karşı taraf yeniden bağlandığını bildirdi
            if (map['state'] == 'reconnected') {
              _peerGraceTimer?.cancel();
              peerReconnectingName = null;
              peerDroppedAt = null;
              notifyListeners();
            }
            return;
          }

          if (packetType == 'juzzio_battery') {
            final level = (map['level'] as num?)?.toInt() ?? -1;
            final sender = event.participant;
            final senderName = (map['name']?.toString().trim().isNotEmpty ?? false)
                ? map['name'].toString().trim()
                : (sender?.name.trim().isNotEmpty ?? false)
                    ? sender!.name.trim()
                    : (sender?.identity ?? '');
            if (level >= 0 && level <= 100) {
              onRemoteBatteryLow?.call(sender?.identity ?? '', senderName, level);
            }
            return;
          }

          if (packetType == 'juzzio_chat') {
            await _onInCallMessage(map, event.participant);
            return;
          }

          if (packetType == 'juzzio_reaction') {
            final emoji = map['emoji']?.toString() ?? '';
            if (kCallReactions.contains(emoji)) onCallReaction?.call(event.participant?.identity ?? '', emoji);
            return;
          }

          if (packetType == 'juzzio_subtitle_retract') {
            final id = map['id']?.toString() ?? '';
            final speaker = map['speakerId']?.toString() ?? '';
            // yalnız gönderen kendi bölütünü geri çekebilir
            if (id.isNotEmpty && speaker.isNotEmpty && speaker == event.participant?.identity) {
              retractSubtitleSegment(id, speaker);
            }
            return;
          }

          if (packetType == 'juzzio_subtitle') {
            final incoming = LiveSubtitlePacket.fromJson(map);
            if (incoming.sourceLang.toLowerCase() != _myLang) {
              onForeignParticipantDetected?.call();
            }
            final desiredLang = JuzzioAppController.instance.subtitleLang.toLowerCase();
            if (incoming.targetLang.toLowerCase() != desiredLang &&
                incoming.originalText.trim().isNotEmpty) {
              // v1.2.9 başarım: ara sonuçların her biri için çeviri isteği atılmaz (konuşmacı başına
              // ~0,6 sn'de bir); geç dönen eski çeviri yenisini ya da kesin sonucu ezemez.
              int? ticket;
              if (!incoming.isFinal) {
                final now = DateTime.now();
                final last = _remoteInterimAt[incoming.speakerId];
                if (last != null && now.difference(last).inMilliseconds < kRemoteInterimGapMs) return;
                _remoteInterimAt[incoming.speakerId] = now;
                ticket = (_remoteInterimTicket[incoming.speakerId] ?? 0) + 1;
                _remoteInterimTicket[incoming.speakerId] = ticket;
              }
              final retranslated = await SupabaseService.instance.translateText(
                text: incoming.originalText,
                sourceLang: 'auto',
                targetLang: desiredLang,
              );
              if (ticket != null &&
                  (ticket != _remoteInterimTicket[incoming.speakerId] || _finalizedSegmentIds.contains(incoming.id))) {
                return;
              }
              addSubtitlePacket(
                LiveSubtitlePacket(
                  id: incoming.id,
                  speakerId: incoming.speakerId,
                  speakerName: incoming.speakerName,
                  speakerUsername: incoming.speakerUsername,
                  voiceFingerprint: incoming.voiceFingerprint,
                  gender: incoming.gender,
                  sourceLang: incoming.sourceLang,
                  targetLang: desiredLang,
                  originalText: incoming.originalText,
                  translatedText: retranslated,
                  isFinal: incoming.isFinal,
                  timestamp: incoming.timestamp,
                ),
              );
            } else {
              addSubtitlePacket(incoming);
            }
          } else if (packetType == 'juzzio_ping') {
            final pong = jsonEncode({
              'type': 'juzzio_pong',
              'sentAt': map['sentAt'],
            });
            _room?.localParticipant?.publishData(
              utf8.encode(pong),
              reliable: false,
              topic: 'juzzio_net',
            );
          } else if (packetType == 'juzzio_pong') {
            final sentAt = (map['sentAt'] as num?)?.toInt();
            if (sentAt != null) {
              final rtt = DateTime.now().millisecondsSinceEpoch - sentAt;
              if (rtt > 0 && rtt < 5000) {
                final before = latencyMs;
                final beforeHealth = networkHealth;
                latencyMs = ((latencyMs * 0.3) + (rtt * 0.7)).round().clamp(14, 999);
                _recalculateHealthLevel();
                // v1.2.9 başarım: birkaç ms'lik oynama için ekran yeniden çizilmez
                if (networkHealth != beforeHealth || (latencyMs - before).abs() >= 8) notifyListeners();
              }
            }
          }
        } catch (_) {}
      });
  }

  /// Pil seviyemi diğer katılımcılara bildirir (yalnızca kritik eşiklerde çağrılır).
  Future<void> broadcastBatteryLevel(int level) async {
    try {
      final packet = jsonEncode({
        'type': 'juzzio_battery',
        'level': level.clamp(0, 100),
        'name': _myName,
        'senderId': _myIdentity,
      });
      await _room?.localParticipant?.publishData(
        utf8.encode(packet),
        reliable: true,
        topic: 'juzzio_status',
      );
    } catch (_) {}
  }

  void _releaseLocalMediaSilently() {
    _stopDeviceSpeech();
    _networkProbeTimer?.cancel();
    _keepAliveTimer?.cancel();
    () async {
      try {
        await _audioStreamSub?.cancel();
      } catch (_) {}
      _audioStreamSub = null;
      try {
        if (await _sharedAudioTap.isRecording()) {
          await _sharedAudioTap.stop();
        }
      } catch (_) {}
      try {
        await _deepgramSub?.cancel();
      } catch (_) {}
      _deepgramSub = null;
      try {
        await _deepgramChannel?.sink.close();
      } catch (_) {}
      _deepgramChannel = null;
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(false);
        await _room?.localParticipant?.setCameraEnabled(false);
      } catch (_) {}
    }();
  }

  Future<void> broadcastCallEnded() async {
    try {
      final packet = jsonEncode({
        'type': 'juzzio_call_ended',
        'senderId': _myIdentity,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _room?.localParticipant?.publishData(
        utf8.encode(packet),
        reliable: true,
        topic: 'juzzio_control',
      );
    } catch (_) {}
  }

  void _startNetworkHealthMonitor() {
    _networkProbeTimer?.cancel();
    _measureNetworkRtt();
    final intervalMs = JuzzioAppController.instance.callBatterySaverEnabled ? 4200 : 2000;
    _networkProbeTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _measureNetworkRtt();
    });
  }

  Future<void> _measureNetworkRtt() async {
    if (!isConnected) return;

    if (remoteParticipants.isNotEmpty) {
      try {
        final pingPacket = jsonEncode({
          'type': 'juzzio_ping',
          'sentAt': DateTime.now().millisecondsSinceEpoch,
        });
        await _room?.localParticipant?.publishData(
          utf8.encode(pingPacket),
          reliable: false,
          topic: 'juzzio_net',
        );
        return;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse(JuzzioConfig.liveKitUrl);
      final host = uri.host;
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(milliseconds: 1200),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      sw.stop();
      await socket.close();

      final measured = (sw.elapsedMilliseconds * 0.65).round().clamp(16, 999);
      latencyMs = ((latencyMs * 0.35) + (measured * 0.65)).round();
      _recalculateHealthLevel();
      notifyListeners();
    } catch (_) {
      latencyMs = 280;
      networkHealth = NetworkHealthLevel.poor;
      notifyListeners();
    }
  }

  void _recalculateHealthLevel() {
    if (liveKitQuality == ConnectionQuality.poor ||
        liveKitQuality == ConnectionQuality.lost ||
        latencyMs > 260) {
      networkHealth = NetworkHealthLevel.poor;
    } else if (latencyMs > 150) {
      networkHealth = NetworkHealthLevel.fair;
    } else if (latencyMs > 80 || liveKitQuality == ConnectionQuality.good) {
      networkHealth = NetworkHealthLevel.good;
    } else {
      networkHealth = NetworkHealthLevel.excellent;
    }
  }

  /// LiveKit yerel mikrofon izinden 16 kHz / mono / PCM16 kareler. Mikrofonu ikinci kez AÇMAZ.
  /// İz yoksa ya da 2,5 sn içinde hiç kare gelmezse null (çağıran eski kayıtçıya döner).
  Future<Stream<Uint8List>?> _localMicPcmStream() async {
    LocalAudioTrack? track;
    for (var i = 0; i < 12 && track == null; i++) {
      final pubs = _room?.localParticipant?.audioTrackPublications ?? const [];
      for (final p in pubs) {
        final t = p.track;
        if (t is LocalAudioTrack && p.source == TrackSource.microphone) track = t;
      }
      if (track == null) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (track == null) return null;
    final first = Completer<bool>();
    CancelListenFunc? cancelRenderer;
    late final StreamController<Uint8List> ctrl;
    ctrl = StreamController<Uint8List>(onCancel: () async {
      final c = cancelRenderer;
      cancelRenderer = null;
      if (c != null) await c();
    });
    try {
      cancelRenderer = track.addAudioRenderer(
        options: const AudioRendererOptions(sampleRate: 16000, channels: 1, format: AudioFormat.Int16),
        onFrame: (frame) {
          if (!first.isCompleted) first.complete(true);
          if (!ctrl.isClosed && frame.data.isNotEmpty) ctrl.add(frame.data);
        },
      );
    } catch (e) {
      debugPrint('Mic track renderer unavailable: $e');
      return null;
    }
    final ok = await first.future.timeout(const Duration(milliseconds: 2500), onTimeout: () => false);
    if (!ok) {
      final c = cancelRenderer;
      cancelRenderer = null;
      if (c != null) await c();
      await ctrl.close();
      return null;
    }
    return ctrl.stream;
  }

  Future<void> _startDeepgramSubtitlePipeline() async {
    try {
      _setEngine('connecting');
      String? authorization;
      // v1.2.8: geçici hatalarda 3 deneme; anahtar yoksa/izin yoksa beklemeden yedek motora
      for (var attempt = 0; attempt < 3 && authorization == null && isConnected; attempt++) {
        authorization = await SupabaseService.instance.fetchDeepgramAuthorization();
        final why = SupabaseService.instance.lastDeepgramError;
        if (authorization != null || why == 'no_key' || why == 'no_active_call') break;
        await Future<void>.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
      if (authorization == null || !isConnected) {
        debugPrint('Deepgram subtitles unavailable: ${SupabaseService.instance.lastDeepgramError}');
        if (isConnected) await _startDeviceSpeech(SupabaseService.instance.lastDeepgramError);
        return;
      }
      final wsUrl = JuzzioConfig.buildDeepgramWsUrl(
        _myLang,
        batterySaver: JuzzioAppController.instance.callBatterySaverEnabled,
      );
      _deepgramChannel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          'Authorization': authorization,
        },
      );

      _deepgramSub = _deepgramChannel!.stream.listen(
        (dynamic message) async {
          if (captionEngine != 'deepgram') {
            _deepgramFailures = 0;
            _setEngine('deepgram');
          }
          await _handleDeepgramTranscript(message.toString());
        },
        onError: (_) {},
        // v1.2.8: soket kapanırsa (ağ/token) arama sürüyorsa otomatik yeniden bağlan
        onDone: _onDeepgramClosed,
        cancelOnError: false,
      );
      _setEngine('deepgram');

      _keepAliveTimer = Timer.periodic(const Duration(seconds: 7), (_) {
        try {
          _deepgramChannel?.sink.add(jsonEncode({'type': 'KeepAlive'}));
        } catch (_) {}
      });

      // v1.3.0 HOPARLÖR DÜZELTMESİ: altyazı sesi artık LiveKit'in yayınladığı (yankısı donanımca
      // temizlenmiş) mikrofon izinden alınır. Önceden ikinci bir kayıtçı (record) mikrofonu AYRICA
      // açıyordu: hoparlörde Android iki "sesli iletişim" kaydından birine sessizlik veriyor, ikinci
      // kayıtçının yankı engelleyicisi LiveKit ses yönlendirmesini bozuyordu → karşı taraf (@ari)
      // konuşunca benim sesim kesiliyor, karşı sesi duyan kapı da kendi cümlelerimi reddediyordu
      // (kulaklıkta yankı olmadığı için sorun görünmüyordu). İz alınamazsa eski yola dönülür.
      final trackStream = await _localMicPcmStream();
      final hasPerm = trackStream != null || await _sharedAudioTap.hasPermission();
      if (!hasPerm) return;

      final pcmStream = trackStream ?? await _sharedAudioTap.startStream(
        // v1.1.0: yankı engelleme + gürültü bastırma AÇIK, otomatik kazanç KAPALI.
        // (Önceden kazanç sessizliği yükseltiyor, hoparlördeki karşı ses de mikrofona
        // geri giriyordu → kullanıcının söylemediği "Tamam aşkım" vb. satırlar.)
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

      _speechGate.reset();
      _audioStreamSub = pcmStream.listen((Uint8List pcmChunk) {
        final ch = _deepgramChannel;
        if (!isMicEnabled || ch == null) return;
        // Konuşma kapısı: konuşulmuyorsa gerçek ses yerine dijital sessizlik gider
        for (final out in _speechGate.process(pcmChunk, DateTime.now(), remoteActive: _anyRemoteSpeaking())) {
          ch.sink.add(out);
        }
        if (_speechGate.isOpen) _updateVoiceFingerprintFromPcm(pcmChunk);
      });
    } catch (e) {
      debugPrint('Deepgram pipeline warning: $e');
    }
  }

  Future<void> _handleDeepgramTranscript(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = decoded['type'];
      // v0.9.4: konuşma bitti (sessizlik) → bekleyen kesin parçalar tek cümle olarak kapatılır
      if (type == 'UtteranceEnd') {
        final pending = _mySegmentBuffer.trim();
        if (pending.isNotEmpty && _myOpenSegmentId != null) {
          _mySegmentBuffer = '';
          await _emitOwnSegment(_myOpenSegmentId!, pending, isFinal: true);
          _myOpenSegmentId = null;
          _myOpenSegmentShown = false;
        } else if (pending.isEmpty) {
          _retractMyOpenSegment();
        }
        return;
      }
      if (type != 'Results') return;

      final chunkFinal = decoded['is_final'] == true;
      final speechFinal = decoded['speech_final'] == true;
      final channel = decoded['channel'] as Map<String, dynamic>?;
      final alternatives = channel?['alternatives'] as List?;
      if (alternatives == null || alternatives.isEmpty) return;

      var piece = (alternatives.first['transcript'] ?? '').toString().trim();
      final confidence = (alternatives.first['confidence'] as num?)?.toDouble();
      // v1.1.0: hayalet/yankı süzgeci — gerçekten konuşmadıysam bu parça benim değil
      if (piece.isNotEmpty && !_acceptOwnPiece(piece, confidence)) {
        piece = '';
      }
      if (piece.isEmpty && !(chunkFinal && speechFinal && _mySegmentBuffer.trim().isNotEmpty)) {
        // Kesin sonuç reddedildi ve biriken metin yok → ekranda kalan ara satırı geri çek
        if (chunkFinal && _mySegmentBuffer.trim().isEmpty) _retractMyOpenSegment();
        return;
      }

      // v0.9.4: Deepgram "is_final" yalnız bir ses parçasını kesinleştirir; cümle bitmemiş olabilir.
      // Kesin parçalar biriktirilir, ara sonuçlar tek satırda güncellenir; bölüt yalnız
      // speech_final (konuşmacı durdu) veya UtteranceEnd ile kapanır → cümle ikiye bölünmez.
      final segmentId = _myOpenSegmentId ??= '${_myIdentity}_${DateTime.now().millisecondsSinceEpoch}_${_mySegmentSeq++}';
      final transcript = juzzioJoinTranscript(_mySegmentBuffer, piece);
      if (chunkFinal && !speechFinal) {
        _mySegmentBuffer = transcript;
      }
      final isFinal = chunkFinal && speechFinal;
      if (isFinal) {
        _mySegmentBuffer = '';
        _myOpenSegmentId = null;
        _myOpenSegmentShown = false;
      } else {
        _myOpenSegmentShown = true;
      }
      await _emitOwnSegment(segmentId, transcript, isFinal: isFinal);
    } catch (_) {}
  }

  bool _anyRemoteSpeaking() {
    for (final p in remoteParticipants) {
      if (isParticipantSpeaking(p)) return true;
    }
    return false;
  }

  /// v1.1.0: bu tanıma parçası gerçekten benim konuşmam mı?
  bool _acceptOwnPiece(String piece, double? confidence) {
    final now = DateTime.now();
    final local = localParticipant;
    var remoteSpeaking = false;
    for (final p in remoteParticipants) {
      if (isParticipantSpeaking(p)) {
        remoteSpeaking = true;
        break;
      }
    }
    // Kesin sonuçlar konuşma bittikten 1–2 sn sonra gelebilir → pencereler buna göre geniş
    return juzzioAcceptOwnTranscript(
      text: piece,
      confidence: confidence,
      localVoiceRecent: _speechGate.voicedWithin(const Duration(milliseconds: 3500), now),
      remoteSpeaking: remoteSpeaking,
      localSpeaking: local == null || isParticipantSpeaking(local) || now.difference(_lastLocalSpeakAt) < const Duration(seconds: 3),
    );
  }

  /// Ekranda görünmüş ama sonradan reddedilen ara satırı yerelde ve karşıda kaldırır.
  void _retractMyOpenSegment() {
    final id = _myOpenSegmentId;
    final wasShown = _myOpenSegmentShown;
    _myOpenSegmentId = null;
    _myOpenSegmentShown = false;
    _mySegmentBuffer = '';
    _interimTranslateTicket++;
    if (id == null || !wasShown) return;
    retractSubtitleSegment(id, _myIdentity);
    try {
      _room?.localParticipant?.publishData(
        utf8.encode(jsonEncode({'type': 'juzzio_subtitle_retract', 'id': id, 'speakerId': _myIdentity})),
        reliable: true,
        topic: 'juzzio_subtitles',
      );
    } catch (_) {}
  }

  /// Kesinleşmemiş bir bölütü ekrandan kaldırır (hayalet/yankı olduğu anlaşıldı).
  void retractSubtitleSegment(String id, String speakerId) {
    if (_finalizedSegmentIds.contains(id)) return;
    final cur = interimBySpeaker[speakerId];
    if (cur == null || cur.id != id) return;
    interimBySpeaker.remove(speakerId);
    if (speakerId == _myIdentity) {
      myInterimText = null;
    } else {
      remoteInterimText = null;
    }
    activeInterimSpeakerHandle = interimBySpeaker.isEmpty ? null : interimBySpeaker.values.last.formattedHandle;
    notifyListeners();
  }

  String _mySegmentBuffer = '';
  static const int kRemoteInterimGapMs = 600;
  final Map<String, DateTime> _remoteInterimAt = {};
  final Map<String, int> _remoteInterimTicket = {};

  Future<void> _emitOwnSegment(String segmentId, String transcript, {required bool isFinal}) async {
    try {

      final mySubLang = JuzzioAppController.instance.subtitleLang.toLowerCase();
      final partnerTarget = targetLang;

      String translated;
      if (isFinal) {
        translated = await SupabaseService.instance.translateText(
          text: transcript,
          sourceLang: 'auto',
          targetLang: partnerTarget,
        );
      } else {
        // Ara sonuçlar en fazla ~0,7 sn'de bir çevrilir; eski istek yeniyi ezemez.
        final now = DateTime.now();
        if (now.difference(_lastInterimTranslateAt).inMilliseconds < 700) return;
        _lastInterimTranslateAt = now;
        final ticket = ++_interimTranslateTicket;
        translated = await SupabaseService.instance.translateText(
          text: transcript,
          sourceLang: 'auto',
          targetLang: partnerTarget,
        );
        if (ticket != _interimTranslateTicket || _finalizedSegmentIds.contains(segmentId)) return;
      }

      final packet = LiveSubtitlePacket(
        id: segmentId,
        speakerId: _myIdentity,
        speakerName: _myName,
        speakerUsername: _myName,
        voiceFingerprint: _myVoiceFingerprint,
        gender: myGender,
        sourceLang: mySubLang,
        targetLang: partnerTarget,
        originalText: transcript,
        translatedText: translated,
        isFinal: isFinal,
        timestamp: DateTime.now(),
      );

      addSubtitlePacket(packet);

      final payloadBytes = utf8.encode(jsonEncode(packet.toJson()));
      await _room?.localParticipant?.publishData(
        payloadBytes,
        reliable: isFinal,
        topic: 'juzzio_subtitles',
      );
      if (isFinal) _moderateOwnSpeech(transcript);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // v0.9.7 Güç profili (şarj tüketimi ve ısınma karşıtı)
  //  Arka planda / PiP'te veya zayıf ağda: yerel kamera 360p·15 fps·350 kbps kodlanır,
  //  uzak videolar düşük katman + 15 fps istenir. Ön plana dönünce / ağ düzelince 8 sn
  //  kararlılık beklenip normal profile dönülür (sürekli gidip gelme → yeniden ısınma yok).
  //  Bu, kullanıcı ayarı olan Veri Koruma modundan bağımsız, geçici bir uyarlamadır.
  // ---------------------------------------------------------------------------
  static const VideoParameters kLowPowerVideo = VideoParameters(
    dimensions: VideoDimensionsPresets.h360_169,
    encoding: VideoEncoding(maxBitrate: 350 * 1000, maxFramerate: 15),
  );
  bool _lowPower = false;
  bool _cameraLowApplied = false;
  bool get lowPowerActive => _lowPower;

  /// v1.2.9: bir kişinin görüntü katmanını uygular (HIGH ≈720p, MEDIUM ≈480p, LOW ≈360p)
  // v1.2.9 düzeltme: kademe artık elle ZORLANMAZ. Oda "adaptiveStream + dynacast + simulcast" ile kurulu;
  // LiveKit çözünürlüğü (720p/480p/360p katmanları) ağa ve görüntü boyutuna göre kendisi seçer. Elle
  // setVideoQuality/setVideoFPS çağrıları bu otomatikle çakışıp katman değişimlerini ve donmayı artırıyordu.
  // Burada yalnız ekrandaki kalite rozeti güncellenir.
  Future<void> _applyTier(RemoteParticipant p, String tier) async {
    notifyListeners();
  }

  /// Arayüzde görüntünün üstündeki kalite rozeti ('' → tam kalite)
  String videoTierLabelFor(String sid) {
    final t = localNetworkWeak ? 'LOW' : (remoteVideoTier[sid] ?? 'HIGH');
    return t == 'LOW' ? '360p' : (t == 'MEDIUM' ? '480p' : '');
  }

  /// Karşı tarafa ağ durumu bildirimi (yeniden bağlandım)
  Future<void> _broadcastNetState(String state) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      await lp.publishData(utf8.encode(jsonEncode({'type': 'juzzio_net', 'state': state, 'name': _myName})), reliable: true);
    } catch (_) {}
  }
  final Set<String> _lowPowerReasons = {};
  Timer? _powerRestoreTimer;

  /// [reason]: 'background' | 'pip' | 'network'. Herhangi biri etkinse düşük profil.
  void setLowPowerReason(String reason, bool active) {
    if (active) {
      _lowPowerReasons.add(reason);
    } else {
      _lowPowerReasons.remove(reason);
    }
    _powerRestoreTimer?.cancel();
    if (_lowPowerReasons.isNotEmpty) {
      unawaited(_applyPowerProfile(true));
    } else {
      _powerRestoreTimer = Timer(const Duration(seconds: 8), () => unawaited(_applyPowerProfile(false)));
    }
  }

  Future<void> _applyPowerProfile(bool low) async {
    if (_lowPower == low) return;
    _lowPower = low;
    final room = _room;
    if (room == null) return;
    // v1.3.0 (kullanıcı isteği: görüntü kalitesi düşmesin): yalnız internet zayıf diye gelen
    // görüntü artık DÜŞÜK kaliteye çekilmez; yalnız uygulama arka plandayken / PiP'te düşer.
    final viewLow = low && _lowPowerReasons.any((r) => r != 'network');
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        try {
          await pub.setVideoQuality(viewLow ? VideoQuality.LOW : VideoQuality.HIGH);
          await pub.setVideoFPS(viewLow ? 15 : 30);
        } catch (_) {}
      }
    }
    final lp = room.localParticipant;
    // v1.2.9: yalnız ağ zayıfsa kamera yeniden başlatılmaz (görüntü donmaz) — simulcast/dynacast
    // gönderimi zaten düşürür, karşı taraf düşük katmanı alır. Kamera yalnız arka plan/PiP'te küçülür.
    final cameraReasons = _lowPowerReasons.where((r) => r != 'network').isNotEmpty;
    if (low && !cameraReasons && !_cameraLowApplied) {
      notifyListeners();
      return;
    }
    _cameraLowApplied = low;
    // Veri Koruma zaten 360p kodluyorsa kamerayı yeniden başlatmaya gerek yok
    if (lp != null && isCameraEnabled && !JuzzioAppController.instance.dataSaverEnabled) {
      try {
        await lp.setCameraEnabled(false);
        await lp.setCameraEnabled(true,
            cameraCaptureOptions: low ? const CameraCaptureOptions(params: kLowPowerVideo) : const CameraCaptureOptions(params: VideoParametersPresets.h720_169));
        // v1.2.9: kamera yeniden başlayınca yeni ize güzelleştirme yeniden bağlanır (yük koruması sıfırlanır)
        await _applyBeautyFilter();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// v0.9.6: arama sürerken Veri Koruma'yı uygular (kamera ≈360p'ye düşer; kullanıcı onayıyla).
  Future<void> applyDataSaverLive() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    if (isCameraEnabled) {
      try {
        await lp.setCameraEnabled(false);
        await lp.setCameraEnabled(true, cameraCaptureOptions: const CameraCaptureOptions(params: VideoParametersPresets.h360_169));
        await _applyBeautyFilter();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> toggleMicrophone() async {
    isMicEnabled = !isMicEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(isMicEnabled);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    isCameraEnabled = !isCameraEnabled;
    await _room?.localParticipant?.setCameraEnabled(isCameraEnabled);
    if (isCameraEnabled) await _applyBeautyFilter();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Görüntü güzelleştirme (Android'de karşı tarafa giden kameraya uygulanır)
  // ---------------------------------------------------------------------------
  static const MethodChannel _nativeChannel = MethodChannel('juzzio/notifications');

  /// v0.9.3: 0 = kapalı, 1..100 = yoğunluk (kullanıcı ayarı; kaydırıcıyla değişir)
  int beautyLevel = JuzzioAppController.instance.cameraBeautyEnabled ? JuzzioAppController.instance.beautyLevel : 0;

  bool get isBeautyOn => beautyLevel > 0;

  Future<bool> setBeautyLevel(int level) async {
    beautyLevel = level.clamp(0, 100);
    notifyListeners();
    return _applyBeautyFilter();
  }

  /// Tek dokunuşla güzelleştirmeyi aç/kapat (açılırken son seçilen yoğunluk kullanılır)
  Future<bool> toggleBeauty() => setBeautyLevel(isBeautyOn ? 0 : JuzzioAppController.instance.beautyLevel);

  Future<bool> _applyBeautyFilter() async {
    String? trackId;
    try {
      final pubs = _room?.localParticipant?.videoTrackPublications ?? const <LocalTrackPublication<LocalVideoTrack>>[];
      for (final pub in pubs) {
        final track = pub.track;
        if (track != null && pub.source == TrackSource.camera) {
          trackId = track.mediaStreamTrack.id;
          break;
        }
      }
    } catch (_) {}
    if (trackId == null || trackId.isEmpty) return false;
    try {
      final ok = await _nativeChannel.invokeMethod<bool>('setBeautyFilter', {'trackId': trackId, 'level': beautyLevel});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleSpeakerphone() async {
    isSpeakerphoneOn = !isSpeakerphoneOn;
    await Hardware.instance.setSpeakerphoneOn(isSpeakerphoneOn);
    notifyListeners();
  }

  /// Aramadan çıkış: her adım ayrı korunur; biri hata verse de diğer kaynaklar
  /// (mikrofon, kamera, Deepgram soketi, LiveKit odası) mutlaka serbest bırakılır.
  Future<void> disconnectCall() async {
    if (_isDisconnecting) return;
    _isDisconnecting = true;
    _peerGraceTimer?.cancel();
    peerReconnectingName = null;
    await _stopDeviceSpeech();
    captionEngine = 'off';
    _powerRestoreTimer?.cancel();
    _lowPowerReasons.clear();
    _lowPower = false;
    _moderationTimer?.cancel();
    _moderationTimer = null;
    try {
      await _nativeChannel.invokeMethod('clearBeautyFilter');
    } catch (_) {}
    _networkProbeTimer?.cancel();
    _keepAliveTimer?.cancel();
    _speakingReleaseTimer?.cancel();
    try {
      await _audioStreamSub?.cancel();
    } catch (_) {}
    _audioStreamSub = null;
    try {
      if (await _sharedAudioTap.isRecording()) {
        await _sharedAudioTap.stop();
      }
    } catch (_) {}
    try {
      await _deepgramSub?.cancel();
    } catch (_) {}
    _deepgramSub = null;
    try {
      await _deepgramChannel?.sink.close();
    } catch (_) {}
    _deepgramChannel = null;
    final room = _room;
    final listener = _roomListener;
    _room = null;
    _roomListener = null;
    try {
      await room?.localParticipant?.setMicrophoneEnabled(false);
      await room?.localParticipant?.setCameraEnabled(false);
    } catch (_) {}
    try {
      await listener?.dispose();
    } catch (_) {}
    try {
      room?.removeListener(notifyListeners);
      await room?.disconnect();
    } catch (_) {}
    try {
      await room?.dispose();
    } catch (_) {}
    isConnected = false;
    _isDisconnecting = false;
    notifyListeners();
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _peerGraceTimer?.cancel();
    _powerRestoreTimer?.cancel();
    _moderationTimer?.cancel();
    onModerationViolation = null;
    onRemoteCallEnded = null;
    onForeignParticipantDetected = null;
    onParticipantQualityChanged = null;
    onRemoteBatteryLow = null;
    () async {
      await disconnectCall();
      try {
        await _sharedAudioTap.dispose();
      } catch (_) {}
    }();
    super.dispose();
  }
}

/// v1.2.8: altyazı motoru durumunun kısa etiketi (saf; test edilir). [loc] = (tr, en, de) → metin
String juzzioCaptionEngineLabel(String engine, String error, String Function(String, String, String) loc) {
  switch (engine) {
    case 'connecting':
      return loc('Altyazı bağlanıyor…', 'Captions connecting…', 'Untertitel verbinden…');
    case 'deepgram':
      return loc('Deepgram canlı çeviri', 'Deepgram live translation', 'Deepgram Live-Übersetzung');
    case 'device':
      return error == 'no_key'
          ? loc('Cihaz tanıyıcısı (sunucu anahtarı eksik)', 'Device recognizer (server key missing)', 'Geräteerkennung (Serverschlüssel fehlt)')
          : loc('Cihaz tanıyıcısı (yedek)', 'Device recognizer (backup)', 'Geräteerkennung (Reserve)');
    case 'unavailable':
      return error == 'no_key'
          ? loc('Altyazı yok: Deepgram anahtarı eksik', 'No captions: Deepgram key missing', 'Keine Untertitel: Deepgram-Schlüssel fehlt')
          : loc('Altyazı şu an kullanılamıyor', 'Captions unavailable right now', 'Untertitel derzeit nicht verfügbar');
    default:
      return '';
  }
}

/// v0.9.4: biriken kesin parçaya yeni parçayı tek boşlukla ekler (canlı altyazı bölütü).
String juzzioJoinTranscript(String buffer, String piece) {
  final a = buffer.trim();
  final b = piece.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a $b';
}


/// v1.2.9: bağlantı kalitesine göre uzak görüntü kademesi (saf; test edilir)
/// excellent → HIGH (≈720p), good → MEDIUM (≈480p), poor/lost → LOW (≈360p). Benim ağım
/// zayıfsa herkes LOW (indirme bant genişliği korunur).
String juzzioVideoTierFor(ConnectionQuality q, {bool localWeak = false}) {
  if (localWeak) return 'LOW';
  switch (q) {
    case ConnectionQuality.excellent:
      return 'HIGH';
    case ConnectionQuality.good:
      return 'MEDIUM';
    case ConnectionQuality.poor:
    case ConnectionQuality.lost:
      return 'LOW';
    default:
      return 'HIGH';
  }
}


/// v1.2.9: yedek TURN ile bağlantı seçenekleri (arama ve Sinema Parti sesli odası ortak)
ConnectOptions juzzioBackupConnectOptions(List<JuzzioIceServer> servers) => ConnectOptions(
      rtcConfiguration: RTCConfiguration(
        iceServers: [
          const RTCIceServer(urls: ['stun:stun.l.google.com:19302']),
          for (final s in servers) RTCIceServer(urls: s.urls, username: s.username, credential: s.credential),
        ],
        iceTransportPolicy: RTCIceTransportPolicy.all,
      ),
    );
