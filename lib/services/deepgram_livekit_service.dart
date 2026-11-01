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
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:livekit_client/livekit_client.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import 'juzzio_features_service.dart';
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

class DeepgramLiveKitController extends ChangeNotifier {
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  IOWebSocketChannel? _deepgramChannel;
  StreamSubscription? _deepgramSub;
  StreamSubscription<Uint8List>? _audioStreamSub;
  Timer? _keepAliveTimer;
  Timer? _networkProbeTimer;

  final AudioRecorder _sharedAudioTap = AudioRecorder();

  bool isConnected = false;
  bool isMicEnabled = true;
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

    final access = await SupabaseService.instance.fetchLiveKitToken(
      roomName: _activeRoomName,
      identity: identity,
      displayName: displayName,
      lang: _myLang,
    );

    _room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: AudioCaptureOptions(
          autoGainControl: true,
          echoCancellation: true,
          noiseSuppression: false,
          voiceIsolation: false,
          highPassFilter: false,
          typingNoiseDetection: false,
        ),
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'juzzio_voice_track',
          dtx: false,
        ),
        defaultVideoPublishOptions: VideoPublishOptions(
          name: 'juzzio_video_track',
          simulcast: true,
        ),
      ),
    );

    _room!.addListener(notifyListeners);
    _roomListener = _room!.createListener();
    _setupRoomListeners();

    await _room!.connect(
      access.url,
      access.token,
      fastConnectOptions: FastConnectOptions(
        microphone: const TrackOption(enabled: true),
        camera: TrackOption(enabled: enableVideo),
      ),
    );

    await _room!.localParticipant?.setMicrophoneEnabled(
      true,
      audioCaptureOptions: const AudioCaptureOptions(
        autoGainControl: true,
        echoCancellation: true,
        noiseSuppression: false,
        voiceIsolation: false,
        highPassFilter: false,
        typingNoiseDetection: false,
      ),
    );

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
  Future<void> ensureSubtitles({bool force = false}) async {
    if (!isConnected || _deepgramChannel != null || _subtitleStarting) return;
    if (!force && !hasForeignParticipant) return;
    _subtitleStarting = true;
    try {
      await _startDeepgramSubtitlePipeline();
    } finally {
      _subtitleStarting = false;
    }
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
    if (foundForeign) {
      onForeignParticipantDetected?.call();
      ensureSubtitles();
    }
  }

  void _setupRoomListeners() {
    _roomListener
      ?..on<RoomConnectedEvent>((_) {
        _syncParticipantLanguages();
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        _syncParticipantLanguages();
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((event) {
        if (_isForeign(extractParticipantLanguage(event.participant))) {
          onForeignParticipantDetected?.call();
          ensureSubtitles();
        }
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        participantLanguages.remove(event.participant.sid);
        if (remoteParticipants.isEmpty) {
          onRemoteCallEnded?.call();
        }
        notifyListeners();
      })
      ..on<TrackSubscribedEvent>((_) => notifyListeners())
      ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
      ..on<TrackPublishedEvent>((_) => notifyListeners())
      ..on<LocalTrackPublishedEvent>((_) {
        // Kamera yeniden yayınlanınca güzelleştirme yeni izine tekrar bağlanır
        _applyBeautyFilter();
        notifyListeners();
      })
      ..on<TrackUnpublishedEvent>((_) => notifyListeners())
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
        // Oda bağlantısı koptuğunda mikrofon/kamera ve ses kaynakları kesin olarak bırakılır.
        _releaseLocalMediaSilently();
        isConnected = false;
        notifyListeners();
        if (event.reason == DisconnectReason.participantRemoved) {
          onRemovedFromCall?.call();
        }
      })
      ..on<DataReceivedEvent>((event) async {
        try {
          final rawText = utf8.decode(event.data);
          final map = jsonDecode(rawText) as Map<String, dynamic>;
          final packetType = map['type']?.toString();

          if (packetType == 'juzzio_call_ended') {
            onRemoteCallEnded?.call();
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

          if (packetType == 'juzzio_subtitle') {
            final incoming = LiveSubtitlePacket.fromJson(map);
            if (incoming.sourceLang.toLowerCase() != _myLang) {
              onForeignParticipantDetected?.call();
            }
            final desiredLang = JuzzioAppController.instance.subtitleLang.toLowerCase();
            if (incoming.targetLang.toLowerCase() != desiredLang &&
                incoming.originalText.trim().isNotEmpty) {
              final retranslated = await SupabaseService.instance.translateText(
                text: incoming.originalText,
                sourceLang: 'auto',
                targetLang: desiredLang,
              );
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
                latencyMs = ((latencyMs * 0.3) + (rtt * 0.7)).round().clamp(14, 999);
                _recalculateHealthLevel();
                notifyListeners();
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

  Future<void> _startDeepgramSubtitlePipeline() async {
    try {
      final authorization = await SupabaseService.instance.fetchDeepgramAuthorization();
      if (authorization == null || !isConnected) {
        debugPrint('Deepgram subtitles disabled: server returned no token.');
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
          await _handleDeepgramTranscript(message.toString());
        },
        onError: (_) {},
      );

      _keepAliveTimer = Timer.periodic(const Duration(seconds: 7), (_) {
        try {
          _deepgramChannel?.sink.add(jsonEncode({'type': 'KeepAlive'}));
        } catch (_) {}
      });

      final hasPerm = await _sharedAudioTap.hasPermission();
      if (!hasPerm) return;

      final pcmStream = await _sharedAudioTap.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      _audioStreamSub = pcmStream.listen((Uint8List pcmChunk) {
        if (isMicEnabled && _deepgramChannel != null) {
          _updateVoiceFingerprintFromPcm(pcmChunk);
          _deepgramChannel!.sink.add(pcmChunk);
        }
      });
    } catch (e) {
      debugPrint('Deepgram pipeline warning: $e');
    }
  }

  Future<void> _handleDeepgramTranscript(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      if (decoded['type'] != 'Results') return;

      final isFinal = decoded['is_final'] == true;
      final channel = decoded['channel'] as Map<String, dynamic>?;
      final alternatives = channel?['alternatives'] as List?;
      if (alternatives == null || alternatives.isEmpty) return;

      final transcript = (alternatives.first['transcript'] ?? '').toString().trim();
      if (transcript.isEmpty) return;

      // Her Deepgram "is_final" sonucu bir bölütü kapatır; sonraki sözler yeni bölüttür.
      final segmentId = _myOpenSegmentId ??= '${_myIdentity}_${DateTime.now().millisecondsSinceEpoch}_${_mySegmentSeq++}';
      if (isFinal) _myOpenSegmentId = null;

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

  /// 0 = kapalı, 1 = açık (doğal, bulanıklaştırmayan mod)
  int beautyLevel = JuzzioAppController.instance.cameraBeautyEnabled ? 1 : 0;

  bool get isBeautyOn => beautyLevel > 0;

  Future<bool> setBeautyLevel(int level) async {
    beautyLevel = level > 0 ? 1 : 0;
    notifyListeners();
    return _applyBeautyFilter();
  }

  /// Tek dokunuşla güzelleştirmeyi aç/kapat
  Future<bool> toggleBeauty() => setBeautyLevel(isBeautyOn ? 0 : 1);

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
