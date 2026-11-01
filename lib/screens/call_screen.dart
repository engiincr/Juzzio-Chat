// =============================================================================
// JUZZIO v0.5.0 - Sesli & Görüntülü Konferans Arama Ekranı
//  • Sesli aramada çeviri ortada büyük "konuşma kartı" olarak, görüntülü aramada
//    yüzleri kapatmayan alt altyazı şeridi olarak gösterilir (ayrı arayüzler).
//  • Her katılımcının gerçek profil fotoğrafı kullanılır (yoksa baş harf).
//  • Yeşil halka yalnızca kişi o an konuşurken görünür (LiveKit ses etkinliği).
//  • Kişi ekle ve güzelleştirme (tek dokunuş) üst çubuktadır.
// Eski notlar:
// 1. Akıllı Çeviri Kuralı: İki Türk (veya aynı dili konuşan 2 kişi) görüntülü/sesli
//    görüşüyorsa canlı çeviri otomatik aktif edilmez. Yabancı birisiyle arama
//    yapılıyorsa veya aramaya katılan 3. kişi yabancıysa canlı altyazı çevirisi
//    OTOMATİK aktif olur!
// 2. 2 Kişilik Arama Düzeni: Karşı taraf tam ekran, benim görüntüm sağ yukarıda.
// 3. 3+ Kişilik Konferans Düzeni: Benim görüntüm sağ yukarıda kalır; diğer iki
//    kişinin görüntüsü ortadan ikiye bölünür (Üstte örn. FİKRET, Altta örn. ARİ)
//    ve Canlı Çeviri tam bu iki görüntünün kesişim ortasında açılır!
// 4. Kişiye Özgü Görüntü Büyütme / Yer Değiştirme: Sağ üstteki kendi görüntüme
//    (veya herhangi bir katılımcıya) tıkladığımda, SADECE BENİM EKRANIMDA FİKRET
//    yerine benim görüntüm büyür (diğer kişilerin ekranını etkilemez).
// 5. Karşılıklı Arama Sonlandırma: Birisi aramayı kapattığı an karşı tarafın
//    araması da anında kapanır (boş ekrana bakma sorunu çözüldü).
// =============================================================================

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:livekit_client/livekit_client.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../services/deepgram_livekit_service.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';

/// Arama sırasında üstte görünen kısa süreli uyarı (ağ yavaş, pil azaldı)
class _CallAlert {
  final String key;
  final String text;
  final IconData icon;
  final Color color;
  final DateTime createdAt;
  _CallAlert({required this.key, required this.text, required this.icon, required this.color})
      : createdAt = DateTime.now();
}

class _ParticipantSlotData {
  final String id;
  final String name;
  final String lang;
  final VideoTrack? videoTrack;
  final bool isLocal;
  final String? avatarUrl;
  final bool isSpeaking;

  const _ParticipantSlotData({
    required this.id,
    required this.name,
    required this.lang,
    required this.videoTrack,
    required this.isLocal,
    this.avatarUrl,
    this.isSpeaking = false,
  });
}

class CallScreen extends StatefulWidget {
  final String? roomId;
  final String? livekitRoomName;
  final String userIdentity;
  final String displayName;
  final String myLanguage;
  final String? partnerLanguage;
  final bool initialVideoEnabled;
  final String? partnerName;
  final String? partnerAvatarUrl;
  final String? groupTitle;
  final List<String> groupMembers;
  final List<String> groupMemberLanguages;

  /// call_logs.session_id — aramanın tüm katılımcı kayıtlarını birbirine bağlar.
  final String? sessionId;

  /// Gelen aramayı cevaplayan kişinin kendi call_logs satırı.
  final String? callLogId;

  /// Aramayı başlatan taraf mı? (1'e 1 aramada karşı taraf cevaplamazsa zaman aşımı uygular)
  final bool isCaller;

  /// Grup/konferans araması mı? (Bir kişi ayrılınca arama herkes için kapanmaz)
  final bool isGroupCall;

  /// Aramaya sonradan eklenebilecek kişiler (arkadaşlar / grup üyeleri)
  final List<JuzzioUserProfile> invitableUsers;

  const CallScreen({
    super.key,
    this.roomId,
    this.livekitRoomName,
    String? userIdentity,
    String? identity,
    required this.displayName,
    required this.myLanguage,
    this.partnerLanguage,
    bool? initialVideoEnabled,
    bool? enableVideo,
    this.partnerName,
    this.partnerAvatarUrl,
    this.groupTitle,
    this.groupMembers = const [],
    this.groupMemberLanguages = const [],
    this.sessionId,
    this.callLogId,
    this.isCaller = false,
    this.isGroupCall = false,
    this.invitableUsers = const [],
  })  : userIdentity = identity ?? userIdentity ?? 'juzzio_user',
        initialVideoEnabled = enableVideo ?? initialVideoEnabled ?? true;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final JuzzioAppController _app = JuzzioAppController.instance;
  late final DeepgramLiveKitController _controller;
  final ScrollController _inlineHistoryScrollController = ScrollController();

  StreamSubscription<List<JuzzioCallLog>>? _sessionWatchSub;
  Timer? _ringTimeoutTimer;
  bool _anyoneAnswered = false;
  bool _remoteEverJoined = false;
  late bool _isConference;
  // Konferans yönetimi (host / grup yöneticisi): katılımcı çıkarma
  bool _canManageCall = false;
  bool _canManageChecked = false;
  bool _isClosingCall = false;
  bool _isConnecting = true;
  String? _errorText;

  // Canlı Çeviri Penceresi Durumu (Başlangıçta dil kontrolüne göre belirlenir!)
  bool _isTranslatorVisible = false;
  bool _userManuallyToggledTranslator = false;
  bool _isTranslatorMinimized = false;
  double _subtitleFontScale = 1.0;
  Offset _translatorOffset = Offset.zero;
  CameraPosition _cameraPosition = CameraPosition.front;
  int _lastHistoryCount = 0;

  // KİŞİYE ÖZGÜ (SADECE BENİM EKRANIMDA) GÖRÜNTÜ YER DEĞİŞTİRME / BÜYÜTME DURUMU:
  // null = Varsayılan (Benim görüntüm sağ üst köşede PiP, diğerleri ana ekranda).
  // 0 = Benim görüntüm 1. ana slota (örn. FİKRET'in yerine) büyütüldü, FİKRET sağ üste geçti.
  // 1 = Benim görüntüm 2. ana slota (örn. ARİ'nin yerine) büyütüldü, ARİ sağ üste geçti.
  int? _localSwappedMainSlotIndex;

  Timer? _callDurationTimer;
  int _elapsedSeconds = 0;

  // Ağ / pil uyarıları
  final List<_CallAlert> _alerts = [];
  final Map<String, DateTime> _lastQualityAlertAt = {};
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSub;
  Timer? _batteryPollTimer;
  final Set<int> _batteryThresholdsSent = {};

  // Katılımcı profil fotoğrafları (kullanıcıId -> avatar URL)
  final Map<String, String?> _avatarByUid = {};
  final Set<String> _avatarRequested = {};

  @override
  void initState() {
    super.initState();
    _isConference = widget.isGroupCall;
    _controller = DeepgramLiveKitController();
    _controller.onRemoteCallEnded = _handleRemotePeerEndedCall;
    _controller.onRemovedFromCall = _handleRemovedFromCall;
    _controller.onModerationViolation = _handleModerationViolation;
    _controller.onForeignParticipantDetected = _handleForeignParticipantJoined;
    _controller.onParticipantQualityChanged = _handleParticipantQuality;
    _controller.onRemoteBatteryLow = _handleRemoteBatteryLow;
    _controller.addListener(_onControllerUpdate);
    _startBatteryMonitor();

    // v0.7.0: Aynı dili konuşanlar (ör. iki Türk) arasında çeviri paneli açılmaz;
    // yalnızca farklı dilde bir katılımcı odaya bağlandığında otomatik açılır.
    _isTranslatorVisible = false;

    _initCall();
    _listenForCallSession();

    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // AĞ HIZI ve PİL UYARILARI
  // ---------------------------------------------------------------------------
  void _pushAlert(_CallAlert alert) {
    if (!mounted) return;
    setState(() {
      _alerts.removeWhere((a) => a.key == alert.key);
      _alerts.add(alert);
      if (_alerts.length > 3) _alerts.removeAt(0);
    });
    Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() => _alerts.remove(alert));
    });
  }

  void _handleParticipantQuality(String identity, String name, ConnectionQuality quality, bool isLocal) {
    if (quality != ConnectionQuality.poor && quality != ConnectionQuality.lost) return;
    final key = 'net_$identity';
    final last = _lastQualityAlertAt[key];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    _lastQualityAlertAt[key] = DateTime.now();
    final text = isLocal
        ? _app.t('call_alert_my_network_slow')
        : _app.t('call_alert_network_slow').replaceAll('{name}', name);
    _pushAlert(_CallAlert(key: key, text: text, icon: Icons.network_check_rounded, color: JuzzioColors.amber500));
  }

  void _handleRemoteBatteryLow(String identity, String name, int level) {
    if (level > 10) return;
    final text = level <= 5
        ? _app.t('call_alert_battery_5').replaceAll('{name}', name).replaceAll('{level}', '$level')
        : _app.t('call_alert_battery_10').replaceAll('{name}', name).replaceAll('{level}', '$level');
    _pushAlert(_CallAlert(
      key: 'bat_$identity',
      text: text,
      icon: level <= 5 ? Icons.battery_alert_rounded : Icons.battery_2_bar_rounded,
      color: level <= 5 ? JuzzioColors.red500 : JuzzioColors.amber500,
    ));
  }

  void _startBatteryMonitor() {
    Future<void> check() async {
      try {
        final level = await _battery.batteryLevel;
        if (!mounted) return;
        if (level > 15) {
          _batteryThresholdsSent.clear(); // şarj edildi: eşikler sıfırlanır
          return;
        }
        if (level <= 5 && !_batteryThresholdsSent.contains(5)) {
          _batteryThresholdsSent.addAll(const [5, 10]);
          await _controller.broadcastBatteryLevel(level);
        } else if (level <= 10 && !_batteryThresholdsSent.contains(10)) {
          _batteryThresholdsSent.add(10);
          await _controller.broadcastBatteryLevel(level);
        }
      } catch (_) {
        // Pil bilgisi alınamayan cihazlarda (emülatör vb.) sessizce yok sayılır
      }
    }

    check();
    _batteryPollTimer = Timer.periodic(const Duration(seconds: 60), (_) => check());
    try {
      _batteryStateSub = _battery.onBatteryStateChanged.listen((_) => check(), onError: (_) {});
    } catch (_) {}
  }

  Widget _buildAlertsOverlay() {
    if (_alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in _alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _callGlassTint(0.72),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: a.color.withOpacity(0.7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, color: a.color, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        a.text,
                        style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// İki Türk görüşüyorsa false döner; yabancı birisiyle görüşülüyorsa veya
  /// aramaya katılan 3. kişi yabancıysa true döner.
  bool _checkInitialForeignPresence() {
    final myLang = widget.myLanguage.trim().toLowerCase();
    if (widget.partnerLanguage != null &&
        widget.partnerLanguage!.trim().isNotEmpty &&
        widget.partnerLanguage!.trim().toLowerCase() != myLang) {
      return true;
    }
    for (final lang in widget.groupMemberLanguages) {
      if (lang.trim().isNotEmpty && lang.trim().toLowerCase() != myLang) {
        return true;
      }
    }
    return false;
  }

  void _handleForeignParticipantJoined() {
    if (!mounted) return;
    if (!_isTranslatorVisible && !_userManuallyToggledTranslator) {
      setState(() {
        _isTranslatorVisible = true;
        _isTranslatorMinimized = false;
      });
    }
  }

  /// call_logs oturumunu izler:
  ///  • Arayan (1'e 1): karşı taraf reddederse / kimse 45 sn içinde cevaplamazsa arama kapanır.
  ///  • Aranan: arayan aramayı iptal ederse ekran kapanır.
  void _listenForCallSession() {
    final sessionId = widget.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;

    // Grup aramasında da kimse 45 sn içinde katılmazsa oturum kapatılır
    // (aksi hâlde grupta "süren arama" kaydı asılı kalırdı).
    if (widget.isCaller) {
      _ringTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!_anyoneAnswered && !_remoteEverJoined && mounted && !_isClosingCall) {
          _showEndReasonAndClose(_app.loc('Cevap yok', 'No answer', 'Keine Antwort'), forceEndSession: true);
        }
      });
    }

    _sessionWatchSub = SupabaseService.instance.watchCallSession(sessionId).listen((logs) {
      if (!mounted || _isClosingCall || logs.isEmpty) return;
      final myUid = SupabaseService.instance.currentUserId;
      if (logs.any((l) => l.wasAnswered)) {
        _anyoneAnswered = true;
        _ringTimeoutTimer?.cancel();
      }
      if (widget.isCaller) {
        final stillOpen = logs.any((l) => l.status == 'ringing' || (l.status == 'answered' && !_hasEnded(l)));
        if (!stillOpen && !_remoteEverJoined && !_anyoneAnswered && !widget.isGroupCall) {
          final rejected = logs.any((l) => l.status == 'rejected');
          final busy = logs.any((l) => l.status == 'busy_silent');
          _showEndReasonAndClose(
            rejected
                ? _app.loc('Arama reddedildi', 'Call declined', 'Anruf abgelehnt')
                : (busy ? _app.loc('Kişi şu an meşgul', 'User is busy', 'Nutzer ist beschäftigt') : _app.loc('Cevap yok', 'No answer', 'Keine Antwort')),
          );
        }
      } else {
        final mine = logs.where((l) => l.receiverId == myUid).toList();
        if (mine.isNotEmpty && (mine.first.status == 'cancelled' || mine.first.status == 'missed') && !_remoteEverJoined && !mine.first.wasAnswered) {
          _showEndReasonAndClose(_app.loc('Arama sonlandırıldı', 'Call ended', 'Anruf beendet'));
        }
      }
      // Konferansa yeni kişi eklendiyse düzen otomatik olarak çok kişili moda geçer
      if (logs.length > 1 && !_isConference) {
        setState(() => _isConference = true);
      }
    }, onError: (_) {});
  }

  bool _hasEnded(JuzzioCallLog log) => log.status != 'answered' && log.status != 'ringing';

  Future<void> _showEndReasonAndClose(String reason, {bool forceEndSession = false}) async {
    if (_isClosingCall || !mounted) return;
    _isClosingCall = true;
    _ringTimeoutTimer?.cancel();
    _sessionWatchSub?.cancel();
    if (forceEndSession && widget.sessionId != null) {
      await SupabaseService.instance.endCallSession(sessionId: widget.sessionId!, force: true);
    }
    await _controller.disconnectCall();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(reason), backgroundColor: JuzzioColors.deepForest),
    );
    Navigator.of(context).pop();
  }

  Future<void> _handleRemotePeerEndedCall() async {
    if (_isClosingCall || !mounted) return;
    // Konferansta biri ayrılınca arama herkes için kapanmaz; yalnızca kimse kalmadıysa kapanır.
    if (_isConference && _controller.remoteParticipants.isNotEmpty) return;
    if (!_remoteEverJoined && widget.isCaller) return; // henüz kimse katılmadı, çalmaya devam
    _isClosingCall = true;
    _ringTimeoutTimer?.cancel();
    _sessionWatchSub?.cancel();
    if (widget.sessionId != null) {
      await SupabaseService.instance.endCallSession(
        sessionId: widget.sessionId!,
        durationSec: _elapsedSeconds,
        force: true,
      );
    }
    await _controller.disconnectCall();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// v0.6: kendi görüntümüz/konuşmamız uygunsuz bulundu → arama herkes için kapatılır,
  /// ceza mesajı gösterilir (1. ihlal 1 saat, 2. ihlal 4 saat, 3. ihlal kalıcı engel).
  Future<void> _handleModerationViolation(String message) async {
    if (_isClosingCall || !mounted) return;
    try {
      await _controller.broadcastCallEnded();
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.gpp_bad_rounded, color: JuzzioColors.red500, size: 40),
        title: Text(_app.loc('Arama sonlandırıldı', 'Call ended', 'Anruf beendet')),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(_app.loc('Anladım', 'I understand', 'Verstanden')),
          ),
        ],
      ),
    );
    await _showEndReasonAndClose(message, forceEndSession: true);
  }

  Future<void> _handleRemovedFromCall() async {
    if (_isClosingCall || !mounted) return;
    if (widget.callLogId != null && !widget.isCaller) {
      try {
        await SupabaseService.instance.updateCallStatus(
          callId: widget.callLogId!,
          status: 'ended',
          durationSec: _elapsedSeconds,
        );
      } catch (_) {}
    }
    await _showEndReasonAndClose(
      _app.loc('Yönetici seni görüşmeden çıkardı.', 'The host removed you from the call.', 'Der Gastgeber hat dich aus dem Anruf entfernt.'),
    );
  }

  Future<void> _confirmAndRemove(BuildContext sheetCtx, StateSetter setSheet, Set<String> busy, String roomName,
      String identity, String name) async {
    final ok = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: Text(_app.loc('Görüşmeden çıkar?', 'Remove from call?', 'Aus dem Anruf entfernen?')),
        content: Text(name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(_app.loc('Vazgeç', 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(_app.loc('Çıkar', 'Remove', 'Entfernen')),
          ),
        ],
      ),
    );
    if (ok != true || !sheetCtx.mounted) return;
    setSheet(() => busy.add(identity));
    String? err;
    try {
      await SupabaseService.instance.removeCallParticipant(livekitRoomName: roomName, targetIdentity: identity);
    } catch (e) {
      err = SupabaseService.instance.friendlyError(e);
    }
    if (sheetCtx.mounted) setSheet(() => busy.remove(identity));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: err == null ? JuzzioColors.deepForest : JuzzioColors.red500,
      content: Text(err ??
          _app.loc('$name görüşmeden çıkarıldı.', '$name was removed from the call.', '$name wurde aus dem Anruf entfernt.')),
    ));
  }

  /// Katılımcıları yönet: yetkili kişi (host / grup yöneticisi) uzaktaki katılımcıları çıkarabilir.
  Future<void> _openManageParticipantsSheet() async {
    final roomName = _controller.activeRoomName;
    if (roomName.isEmpty) return;
    final busy = <String>{};
    await showJuzzioGlassSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final remotes = _controller.remoteParticipants.toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.55,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Text(
                  _app.loc('Katılımcıları yönet', 'Manage participants', 'Teilnehmer verwalten'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _app.loc('Çıkarılan kişi bu görüşmeye tekrar katılamaz.', 'Removed people cannot rejoin this call.',
                      'Entfernte Personen können diesem Anruf nicht erneut beitreten.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: remotes.isEmpty
                      ? Center(
                          child: Text(
                            _app.loc('Görüşmede başka kimse yok.', 'No one else is in the call.', 'Niemand sonst ist im Anruf.'),
                            style: const TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView.builder(
                          itemCount: remotes.length,
                          itemBuilder: (_, i) {
                            final rp = remotes[i];
                            final name = rp.name.trim().isNotEmpty ? rp.name.trim() : rp.identity;
                            final working = busy.contains(rp.identity);
                            return ListTile(
                              leading: JuzzioGlassAvatar(imageUrl: _avatarForIdentity(rp.identity), name: name, radius: 20),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              trailing: working
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                                        shape: const StadiumBorder(),
                                      ),
                                      onPressed: () => _confirmAndRemove(ctx, setSheet, busy, roomName, rp.identity, name),
                                      child: Text(_app.loc('Çıkar', 'Remove', 'Entfernen')),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _hangUpAndCloseForEveryone() async {
    if (_isClosingCall) return;
    _isClosingCall = true;
    _ringTimeoutTimer?.cancel();
    _sessionWatchSub?.cancel();
    final othersStillInCall = _controller.remoteParticipants.isNotEmpty;
    // 1'e 1 aramada kapatınca karşı tarafın araması da kapanır; konferansta yalnızca ben ayrılırım.
    if (!_isConference) {
      await _controller.broadcastCallEnded();
    }
    if (widget.sessionId != null) {
      if (!widget.isCaller && widget.callLogId != null && _isConference && othersStillInCall) {
        await SupabaseService.instance.updateCallStatus(
          callId: widget.callLogId!,
          status: 'ended',
          durationSec: _elapsedSeconds,
        );
      }
      await SupabaseService.instance.endCallSession(
        sessionId: widget.sessionId!,
        durationSec: _elapsedSeconds,
        force: !_isConference || !othersStillInCall,
      );
    }
    await _controller.disconnectCall();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Süren aramaya kişi ekler (1'e 1 arama konferansa dönüşür)
  Future<void> _openAddParticipantSheet() async {
    final sessionId = widget.sessionId;
    if (sessionId == null) return;
    final inCallNames = _controller.remoteParticipants.map((p) => p.name.trim().toLowerCase()).toSet();
    final candidates = widget.invitableUsers
        .where((u) => u.id != SupabaseService.instance.currentUserId)
        .where((u) => !inCallNames.contains(u.displayName.trim().toLowerCase()))
        .toList();
    final selected = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuzzioGlassTokens.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Text(
                  _app.loc('Aramaya Kişi Ekle', 'Add People to Call', 'Personen zum Anruf hinzufügen'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _app.loc('Seçilen kişilerin telefonu çalar; katıldıklarında konferans başlar.',
                      'Selected people will be rung; the call becomes a conference when they join.', 'Bei den ausgewählten Personen klingelt es; sobald sie beitreten, wird der Anruf zur Konferenz.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: candidates.isEmpty
                      ? Center(
                          child: Text(
                            _app.loc('Eklenebilecek arkadaş bulunamadı.', 'No friends available to add.', 'Keine Freunde zum Hinzufügen verfügbar.'),
                            style: const TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView.builder(
                          itemCount: candidates.length,
                          itemBuilder: (_, i) {
                            final u = candidates[i];
                            final isSel = selected.contains(u.id);
                            return CheckboxListTile(
                              value: isSel,
                              activeColor: JuzzioColors.blue600,
                              onChanged: (v) => setSheet(() {
                                if (v == true) {
                                  selected.add(u.id);
                                } else {
                                  selected.remove(u.id);
                                }
                              }),
                              title: Text(u.displayName, style: const TextStyle(color: Colors.white)),
                              subtitle: Text('@${u.username}', style: const TextStyle(color: Colors.white54)),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JuzzioColors.blue600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              Navigator.of(ctx).pop();
                              try {
                                final count = await SupabaseService.instance.inviteToCall(
                                  sessionId: sessionId,
                                  userIds: selected.toList(),
                                );
                                if (!mounted) return;
                                setState(() => _isConference = true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: JuzzioColors.deepForest,
                                    content: Text(_app.loc('$count kişi aranıyor...', 'Ringing $count people...', 'Es klingelt bei $count Personen...')),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(backgroundColor: Colors.redAccent, content: Text(SupabaseService.instance.friendlyError(e))),
                                );
                              }
                            },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(_app.loc('Aramaya Ekle', 'Add to Call', 'Zum Anruf hinzufügen')),
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

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_controller.remoteParticipants.isNotEmpty && !_remoteEverJoined) {
      _remoteEverJoined = true;
      _ringTimeoutTimer?.cancel();
    }
    if (_controller.remoteParticipants.length >= 2 && !_isConference) {
      _isConference = true;
    }
    if (_isConference && !_canManageChecked && _controller.activeRoomName.isNotEmpty) {
      _canManageChecked = true;
      SupabaseService.instance.canManageCall(_controller.activeRoomName).then((v) {
        if (mounted && v != _canManageCall) setState(() => _canManageCall = v);
      });
    }
    if (_controller.hasForeignParticipant &&
        !_isTranslatorVisible &&
        !_userManuallyToggledTranslator) {
      _isTranslatorVisible = true;
      _isTranslatorMinimized = false;
    }
    final currentLen = _controller.subtitleHistory.length;
    final shouldScroll = currentLen != _lastHistoryCount;
    _lastHistoryCount = currentLen;
    setState(() {});
    if (shouldScroll && _inlineHistoryScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_inlineHistoryScrollController.hasClients) {
          _inlineHistoryScrollController.animateTo(
            _inlineHistoryScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Katılımcıların gerçek profil fotoğraflarını bir kez yükler.
  void _ensureAvatars(Iterable<String> uids) {
    final missing = uids.where((u) => u.isNotEmpty && !_avatarRequested.contains(u)).toSet();
    if (missing.isEmpty) return;
    _avatarRequested.addAll(missing);
    SupabaseService.instance.fetchProfilesByIds(missing).then((list) {
      if (!mounted) return;
      setState(() {
        for (final p in list) {
          _avatarByUid[p.id] = (p.avatarUrl ?? '').trim().isEmpty ? null : p.avatarUrl;
        }
      });
    }).catchError((_) {});
  }

  String? _avatarForIdentity(String identity) {
    final uid = DeepgramLiveKitController.userIdFromIdentity(identity);
    _ensureAvatars([uid]);
    return _avatarByUid[uid];
  }

  Future<void> _initCall() async {
    try {
      await _controller.connectToCall(
        identity: widget.userIdentity,
        displayName: widget.displayName,
        myLanguage: widget.myLanguage,
        enableVideo: widget.initialVideoEnabled,
        livekitRoomName: widget.livekitRoomName,
      );
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorText = SupabaseService.instance.friendlyError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _sessionWatchSub?.cancel();
    _ringTimeoutTimer?.cancel();
    _callDurationTimer?.cancel();
    _batteryPollTimer?.cancel();
    _batteryStateSub?.cancel();
    _controller.onParticipantQualityChanged = null;
    _controller.onRemoteBatteryLow = null;
    _controller.onRemovedFromCall = null;
    _controller.onModerationViolation = null;
    _inlineHistoryScrollController.dispose();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatTimeOfDay(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  VideoTrack? _resolveLocalVideoTrack() {
    final local = _controller.localParticipant;
    if (local == null) return null;
    for (final pub in local.videoTrackPublications) {
      if (pub.track is VideoTrack && !pub.muted) {
        return pub.track as VideoTrack;
      }
    }
    return null;
  }

  /// Katılımcı listesini oluşturur (Gerçek LiveKit katılımcıları + Grup/Partner bilgisi)
  List<_ParticipantSlotData> _buildRemoteParticipantSlots() {
    final slots = <_ParticipantSlotData>[];
    for (final p in _controller.remoteParticipants) {
      VideoTrack? vTrack;
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track is VideoTrack && !pub.muted) {
          vTrack = pub.track as VideoTrack;
          break;
        }
      }
      final name = p.name.trim().isNotEmpty ? p.name.trim() : p.identity;
      final lang = _controller.extractParticipantLanguage(p);
      final fallbackAvatar = _controller.remoteParticipants.length == 1 ? widget.partnerAvatarUrl : null;
      slots.add(
        _ParticipantSlotData(
          id: p.sid,
          name: name,
          lang: lang,
          videoTrack: vTrack,
          isLocal: false,
          avatarUrl: _avatarForIdentity(p.identity) ?? fallbackAvatar,
          isSpeaking: _controller.isParticipantSpeaking(p),
        ),
      );
    }

    if (slots.isEmpty) {
      // Eğer henüz LiveKit odasına bağlanıyorlarsa grup üyelerini veya partneri göster
      final myClean = widget.displayName.trim().toLowerCase().replaceAll('@', '');
      final otherGroupMembers = widget.groupMembers
          .where((m) => m.trim().toLowerCase().replaceAll('@', '') != myClean)
          .toList();

      if (otherGroupMembers.length >= 2) {
        for (int i = 0; i < otherGroupMembers.length; i++) {
          final mName = otherGroupMembers[i];
          final mLang = i < widget.groupMemberLanguages.length
              ? widget.groupMemberLanguages[i]
              : (i >= 1 ? 'en' : widget.myLanguage);
          final member = widget.invitableUsers.where(
            (u) => u.username.toLowerCase() == mName.replaceAll('@', '').trim().toLowerCase() ||
                u.displayName.trim().toLowerCase() == mName.trim().toLowerCase(),
          );
          slots.add(
            _ParticipantSlotData(
              id: 'member_$i',
              name: mName,
              lang: mLang,
              videoTrack: null,
              isLocal: false,
              avatarUrl: member.isNotEmpty ? member.first.avatarUrl : null,
            ),
          );
        }
      } else {
        final pName = otherGroupMembers.isNotEmpty
            ? otherGroupMembers.first
            : (widget.partnerName ?? _app.loc('Katılımcı', 'Participant', 'Teilnehmer'));
        slots.add(
          _ParticipantSlotData(
            id: 'partner_0',
            name: pName,
            lang: widget.partnerLanguage ?? widget.myLanguage,
            videoTrack: null,
            isLocal: false,
            avatarUrl: widget.partnerAvatarUrl,
          ),
        );
      }
    }
    return slots;
  }

  _ParticipantSlotData _buildMyLocalSlot() {
    final myUid = SupabaseService.instance.currentUserId ?? '';
    _ensureAvatars([myUid]);
    return _ParticipantSlotData(
      id: 'local_me',
      name: '${widget.displayName} (${_app.t("you_badge")})',
      lang: widget.myLanguage,
      videoTrack: _resolveLocalVideoTrack(),
      isLocal: true,
      avatarUrl: _avatarByUid[myUid],
      isSpeaking: _controller.isMicEnabled && _controller.isParticipantSpeaking(_controller.localParticipant),
    );
  }

  /// Gerçek profil fotoğrafı + yalnızca konuşurken görünen yeşil halka
  /// Görüntülü arama mı? (başlangıçta görüntülü ya da kamera açık)
  bool get _isVideoCallNow => widget.initialVideoEnabled || _controller.isCameraEnabled;

  Widget _callAvatar(_ParticipantSlotData slot, double size) {
    final name = slot.name.replaceAll(RegExp(r'\s*\(.*\)$'), '');
    final speaking = slot.isSpeaking && !_isVideoCallNow;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.all(size > 70 ? 4 : 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? JuzzioColors.emerald400 : Colors.transparent,
          width: size > 70 ? 3.5 : 2.5,
        ),
        boxShadow: speaking
            ? [BoxShadow(color: JuzzioColors.emerald400.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1)]
            : const [],
      ),
      child: JuzzioGlassAvatar(imageUrl: slot.avatarUrl, name: name, radius: size / 2),
    );
  }

  /// Sağ üstteki kendi görüntümüze (veya ana ekrandaki bir kişiye) tıkladığımızda
  /// SADECE BİZİM EKRANIMIZDA kendi görüntümüzü ana ekrana (örn. FİKRET'in yerine) büyütür!
  void _toggleLocalViewSwap({int targetMainSlotIndex = 0}) {
    setState(() {
      if (_localSwappedMainSlotIndex == targetMainSlotIndex) {
        _localSwappedMainSlotIndex = null;
      } else {
        _localSwappedMainSlotIndex = targetMainSlotIndex;
      }
    });
  }

  String _resolveHeaderTitle(List<_ParticipantSlotData> remoteSlots) {
    if (widget.groupTitle != null && widget.groupTitle!.trim().isNotEmpty) {
      return widget.groupTitle!;
    }
    if (remoteSlots.length >= 2) {
      return remoteSlots.map((e) => e.name).join(' & ');
    }
    return remoteSlots.first.name;
  }

  Color _resolveHealthColor() {
    switch (_controller.networkHealth) {
      case NetworkHealthLevel.excellent:
        return JuzzioColors.emerald500;
      case NetworkHealthLevel.good:
        return JuzzioColors.emerald400;
      case NetworkHealthLevel.fair:
        return JuzzioColors.amber500;
      case NetworkHealthLevel.poor:
        return JuzzioColors.red500;
    }
  }

  Future<void> _flipCamera() async {
    try {
      final local = _controller.localParticipant;
      if (local == null) return;
      for (final pub in local.videoTrackPublications) {
        if (pub.track is LocalVideoTrack) {
          final track = pub.track as LocalVideoTrack;
          _cameraPosition = _cameraPosition == CameraPosition.front
              ? CameraPosition.back
              : CameraPosition.front;
          await track.setCameraPosition(_cameraPosition);
          setState(() {});
          break;
        }
      }
    } catch (_) {}
  }

  void _openSubtitleHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (ctx, _) {
            final history = _controller.subtitleHistory.reversed.toList();
            final liveSeg = _controller.interimBySpeaker.values.isEmpty ? null : _controller.interimBySpeaker.values.last;
            final liveInterim = liveSeg?.translatedText;
            final liveHandle = liveSeg?.speakerName ?? '';

            return DraggableScrollableSheet(
              initialChildSize: 0.76,
              minChildSize: 0.45,
              maxChildSize: 0.94,
              builder: (_, scrollCtrl) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurModal, sigmaY: JuzzioGlassTokens.blurModal),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _callGlassTint(0.82),
                        border: Border.all(color: JuzzioGlassTokens.borderStrong),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
                            blurRadius: 30,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 44,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _app.loc('Canlı Çeviri Geçmişi', 'Live Translation History', 'Live-Übersetzungsverlauf'),
                                              style: const TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: Colors.white,
                                                fontSize: 17.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: JuzzioColors.emerald500.withOpacity(0.16),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _app.loc('CANLI AKTARIM', 'LIVE SYNC', 'LIVE-SYNC'),
                                              style: const TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: JuzzioColors.emerald400,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        _app.loc(
                                          'Söylenen her kelime çevrildiği an buraya canlı aktarılır (${history.length} kayıt)',
                                          'Every spoken word streams here live as translated (${history.length} items)', 'Jedes gesprochene Wort erscheint hier live übersetzt (${history.length} Einträge)',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (history.isNotEmpty)
                                  IconButton(
                                    tooltip: _app.loc('Tüm Geçmişi Kopyala', 'Copy All History', 'Gesamten Verlauf kopieren'),
                                    icon: const Icon(Icons.copy_all_rounded, color: Colors.white, size: 21),
                                    onPressed: () {
                                      final buffer = StringBuffer();
                                      for (final item in _controller.subtitleHistory) {
                                        buffer.writeln(
                                          '[${_formatTimeOfDay(item.timestamp)}] ${item.speakerName} (${item.sourceLang.toUpperCase()} -> ${item.targetLang.toUpperCase()}):',
                                        );
                                        buffer.writeln('  ${_app.loc('Çeviri', 'Translation', 'Übersetzung')}: ${item.translatedText}');
                                        buffer.writeln('  ${_app.loc('Orijinal', 'Original', 'Original')}: ${item.originalText}\n');
                                      }
                                      Clipboard.setData(ClipboardData(text: buffer.toString()));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _app.loc('Çeviri geçmişi panoya kopyalandı', 'Translation history copied to clipboard', 'Übersetzungsverlauf in die Zwischenablage kopiert'),
                                          ),
                                          backgroundColor: JuzzioColors.deepForest,
                                        ),
                                      );
                                    },
                                  ),
                                if (history.isNotEmpty)
                                  IconButton(
                                    tooltip: _app.loc('Geçmişi Temizle', 'Clear History', 'Verlauf löschen'),
                                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 22),
                                    onPressed: () {
                                      _controller.clearSubtitleHistory();
                                      setState(() {});
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                          ),
                          if (liveInterim != null && liveInterim.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0x1AFFFFFF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.graphic_eq_rounded, color: JuzzioColors.emerald400, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$liveHandle · ${_app.loc("konuşuyor", "speaking", "spricht")}: $liveInterim',
                                      style: const TextStyle(
                                        fontFamily: JuzzioConfig.fontRegularBold,
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(color: Colors.white12, height: 1),
                          Expanded(
                            child: history.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Text(
                                        _app.loc(
                                          'Henüz çeviri kaydı oluşmadı.\nKonuşmaya başladığınızda söylenen her kelime anlık olarak buraya aktarılır.',
                                          'No translation entries yet.\nStart speaking to see every word stream here in real time.', 'Noch keine Übersetzungen.\nFang an zu sprechen, um jedes Wort hier in Echtzeit zu sehen.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 14.5,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollCtrl,
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                                    itemCount: history.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (_, idx) {
                                      final item = history[idx];
                                      final isMe = item.speakerId == widget.userIdentity;
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0x14FFFFFF),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: isMe ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(999),
                                                  ),
                                                  child: Text(
                                                    '${isMe ? _app.loc('Sen', 'You', 'Du') : item.speakerName} · ${item.sourceLang.toUpperCase()} → ${item.targetLang.toUpperCase()}',
                                                    style: const TextStyle(
                                                      fontFamily: JuzzioConfig.fontRegularBold,
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  _formatTimeOfDay(item.timestamp),
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 11.5,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              item.translatedText,
                                              style: TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: Colors.white,
                                                fontSize: 18.0 * _subtitleFontScale,
                                                fontWeight: FontWeight.w800,
                                                height: 1.35,
                                              ),
                                            ),
                                            if (item.originalText.trim().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                item.originalText,
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 14.5 * _subtitleFontScale,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
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
              },
            );
          },
        );
      },
    );
  }

  /// v0.8.1: arama ekranı camları — koyu taban + seçili cam temasının hafif tonu
  /// (video üstünde okunurluk korunur)
  /// v0.8.3: arama ekranı vurgusu seçili temadan (özel temada buton rengi)
  Color get _callAccent => JuzzioGlassTokens.custom?.button ?? JuzzioAppController.instance.glassPalette.swatchA;

  Color _callGlassTint(double alpha) => Color.alphaBlend(
        JuzzioAppController.instance.glassPalette.swatchA.withValues(alpha: 0.22),
        Colors.black.withValues(alpha: alpha),
      ).withValues(alpha: alpha);

  @override
  Widget build(BuildContext context) {
    final remoteSlots = _buildRemoteParticipantSlots();
    final mySlot = _buildMyLocalSlot();
    // 3 ve 4 kişilik konferansta herkes eşit ızgarada görünür (en fazla 4 kişi)
    final isConferenceLayout = remoteSlots.length >= 2;

    final effectiveMainSlots = List<_ParticipantSlotData>.from(remoteSlots);
    _ParticipantSlotData pipSlot = mySlot;
    if (!isConferenceLayout &&
        _localSwappedMainSlotIndex != null &&
        _localSwappedMainSlotIndex! >= 0 &&
        _localSwappedMainSlotIndex! < effectiveMainSlots.length) {
      final idx = _localSwappedMainSlotIndex!;
      pipSlot = effectiveMainSlots[idx];
      effectiveMainSlots[idx] = mySlot;
    }

    final headerTitle = _resolveHeaderTitle(remoteSlots);
    final screenSize = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final connectedRemoteCount = _controller.remoteParticipants.length;

    final header = SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopHeaderBar(
                headerTitle,
                isThreeOrMoreCall: isConferenceLayout,
                participantCount: connectedRemoteCount + 1,
              ),
              const SizedBox(height: 8),
              _buildLanguageStatusPill(isThreeOrMoreCall: isConferenceLayout),
              const SizedBox(height: 8),
              _buildAlertsOverlay(),
            ],
          ),
        ),
      ),
    );

    if (isConferenceLayout) {
      final gridSlots = <_ParticipantSlotData>[...remoteSlots.take(3), mySlot];
      // Glassmorphism: sayfa zemini saydam, arkada seçili aurora cam teması görünür
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: topInset + 104, left: 6, right: 6, bottom: 6),
                    child: _buildConferenceGrid(gridSlots),
                  ),
                  header,
                  if (_showSubtitles)
                    (_isVoiceOnlyCall(gridSlots)
                        ? _buildVoiceTranscriptCard(screenSize: screenSize, bottomBase: 12)
                        : _buildVideoCaptionStrip(screenSize: screenSize, bottomBase: 12)),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: _buildBottomControlsBar(),
              ),
            ),
          ],
        ),
      );
    }

    final allParticipantStripSlots = <_ParticipantSlotData>[...remoteSlots, mySlot];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              child: Container(
                color: Colors.transparent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. ANA SAHNE (1'e 1)
                    if (!_controller.isCameraEnabled && effectiveMainSlots.first.videoTrack == null)
                      _buildAudioOnlyLayer(headerTitle, effectiveMainSlots.first)
                    else
                      _buildTwoPersonSingleStage(effectiveMainSlots.first),

                    // 2. Üst bilgi çubuğu + ağ/pil uyarıları
                    header,

                    // 3. Sağ üst köşede kendi görüntümüz (PiP) — v0.7.0: yalnızca görüntülü aramada
                    if (!_isVoiceOnlyCall([effectiveMainSlots.first, pipSlot]))
                    Positioned(
                      top: topInset + 118,
                      right: 14,
                      child: GestureDetector(
                        onTap: () => _toggleLocalViewSwap(targetMainSlotIndex: 0),
                        child: _buildTopRightPipCard(pipSlot, isThreeOrMoreCall: false),
                      ),
                    ),

                    // 4. Canlı çeviri: sesli aramada ortada büyük kart, görüntülüde yüzleri
                    //    kapatmayan alt altyazı şeridi
                    if (_showSubtitles)
                      (_isVoiceOnlyCall([effectiveMainSlots.first, pipSlot])
                          ? _buildVoiceTranscriptCard(screenSize: screenSize, bottomBase: 96)
                          : _buildVideoCaptionStrip(screenSize: screenSize, bottomBase: 96)),

                    // 5. Alt kontrol butonları
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: _buildBottomControlsBar(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Alt katılımcı şeridi: gerçek profil fotoğrafları + konuşma halkası
          SafeArea(
            top: false,
            child: SizedBox(
              height: 92,
              width: double.infinity,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: allParticipantStripSlots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, idx) {
                  final slot = allParticipantStripSlots[idx];
                  final micOff = slot.isLocal && !_controller.isMicEnabled;
                  return GestureDetector(
                    onTap: () => _toggleLocalViewSwap(targetMainSlotIndex: 0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _callAvatar(slot, 56),
                        if (micOff)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: JuzzioColors.redAlert,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(Icons.mic_off_rounded, size: 12.5, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3–4 kişilik konferans ızgarası: 3 kişide üstte 2 + altta 1 geniş, 4 kişide 2×2
  Widget _buildConferenceGrid(List<_ParticipantSlotData> slots) {
    Widget tile(_ParticipantSlotData slot, int index) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: _buildParticipantVideoOrAvatarTile(
            slot: slot,
            slotIndex: index,
            isSplitHalf: true,
            compactLabel: true,
          ),
        ),
      );
    }

    if (slots.length <= 2) {
      return Column(
        children: [for (var i = 0; i < slots.length; i++) Expanded(child: tile(slots[i], i))],
      );
    }
    final firstRow = slots.take(2).toList();
    final secondRow = slots.skip(2).take(2).toList();
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [for (var i = 0; i < firstRow.length; i++) Expanded(child: tile(firstRow[i], i))],
          ),
        ),
        Expanded(
          child: Row(
            children: [for (var i = 0; i < secondRow.length; i++) Expanded(child: tile(secondRow[i], i + 2))],
          ),
        ),
      ],
    );
  }

  /// 2 Kişilik Görüntülü Arama Ana Sahnesi
  Widget _buildTwoPersonSingleStage(_ParticipantSlotData mainSlot) {
    return GestureDetector(
      onDoubleTap: () => _toggleLocalViewSwap(targetMainSlotIndex: 0),
      child: _buildParticipantVideoOrAvatarTile(
        slot: mainSlot,
        slotIndex: 0,
        isSplitHalf: false,
      ),
    );
  }

  Widget _buildParticipantVideoOrAvatarTile({
    required _ParticipantSlotData slot,
    required int slotIndex,
    required bool isSplitHalf,
    bool compactLabel = false,
  }) {
    // Uzak katılımcının görüntüsü benim kameramın açık olmasına bağlı değildir
    final hasVideo = slot.videoTrack != null && (!slot.isLocal || _controller.isCameraEnabled);
    final paletteColors = slotIndex == 0
        ? const [JuzzioColors.surface1F2430, JuzzioColors.surface12151C]
        : const [JuzzioColors.surface231F2E, JuzzioColors.surface13111A];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasVideo)
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: VideoTrackRenderer(
              slot.videoTrack!,
              fit: VideoViewFit.cover,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: paletteColors,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _callAvatar(slot, isSplitHalf ? 80 : 112),
                  const SizedBox(height: 10),
                  Text(
                    slot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: isSplitHalf ? 17 : 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${slot.lang.toUpperCase()} • ${_app.loc("Kamera kapalı", "Camera off", "Kamera aus")}',
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // v0.7.0: Görüntülü aramada konuşma çerçevesi/halkası gösterilmez (yalnızca sesli aramada).

        // Sol Alt Katılımcı İsim Etiketi (tam ekran sahnede başlık zaten adı gösterir)
        if (compactLabel || isSplitHalf)
        Positioned(
          left: compactLabel ? 8 : 16,
          bottom: compactLabel ? 8 : (slotIndex == 0 ? 22 : 98),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _callGlassTint(0.58),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: (slot.isSpeaking && !_isVideoCallNow) ? JuzzioColors.emerald400 : Colors.white38,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${slot.name} · ${slot.lang.toUpperCase()}',
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.swap_vert_circle_outlined, color: Colors.white70, size: 15),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Sağ Üst Köşedeki Kamera Kartı (Tıklandığında görüntüyü kendi ekranımızda büyütür!)
  Widget _buildTopRightPipCard(_ParticipantSlotData pipSlot, {required bool isThreeOrMoreCall}) {
    final hasVideo = pipSlot.videoTrack != null && (!pipSlot.isLocal || _controller.isCameraEnabled);
    final isSwapped = _localSwappedMainSlotIndex != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 106,
            height: 150,
            decoration: BoxDecoration(
              color: JuzzioColors.surface181A22,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.55),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasVideo)
                  ColorFiltered(
                    colorFilter: const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                    child: VideoTrackRenderer(
                      pipSlot.videoTrack!,
                      fit: VideoViewFit.cover,
                    ),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [JuzzioColors.surface282B36, JuzzioColors.surface161820],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _callAvatar(pipSlot, 54),
                  ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _callGlassTint(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSwapped ? Icons.fullscreen_exit_rounded : Icons.open_in_full_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 7,
                  left: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: _callGlassTint(0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pipSlot.isLocal
                          ? _app.loc('Ben • Büyüt', 'Me • Enlarge', 'Ich • Vergrößern')
                          : pipSlot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isThreeOrMoreCall) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _toggleLocalViewSwap(targetMainSlotIndex: 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _localSwappedMainSlotIndex == 0
                        ? _callAccent
                        : _callGlassTint(0.62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _app.loc('Üst Ekran', 'Top Slot', 'Oberer Platz'),
                    style: const TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _toggleLocalViewSwap(targetMainSlotIndex: 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _localSwappedMainSlotIndex == 1
                        ? JuzzioColors.blue600
                        : _callGlassTint(0.62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _app.loc('Alt Ekran', 'Bottom Slot', 'Unterer Platz'),
                    style: const TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: Colors.white,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Dil Durumu Bilgilendirme Kapsülü (İki Türk görüşüyorsa çeviri kapalı uyarısı / Yabancı katıldıysa çeviri aktif)
  Widget _buildLanguageStatusPill({required bool isThreeOrMoreCall}) {
    final s = JuzzioStrings(_app.uiLang);
    final isForeignActive = _isTranslatorVisible || _controller.hasForeignParticipant;

    return GestureDetector(
      onTap: () {
        setState(() {
          _userManuallyToggledTranslator = true;
          _isTranslatorVisible = !_isTranslatorVisible;
          if (_isTranslatorVisible) _controller.ensureSubtitles(force: true);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
        decoration: BoxDecoration(
          color: isForeignActive
              ? _callAccent.withValues(alpha: 0.90)
              : _callGlassTint(0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForeignActive ? Icons.translate_rounded : Icons.verified_user_rounded,
              color: Colors.white,
              size: 13.5,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isForeignActive
                    ? s.t('foreign_joined_info')
                    : s.t('same_lang_tr_info'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioOnlyLayer(String remoteName, _ParticipantSlotData slot) {
    final healthColor = _resolveHealthColor();
    return Align(
      alignment: const Alignment(0.0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _callAvatar(slot, 124),
            const SizedBox(height: 14),
            Text(
              remoteName,
              style: const TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _isConnecting
                  ? _app.loc('Bağlanıyor...', 'Connecting...', 'Verbindung wird hergestellt...')
                  : '${_app.t('hd_audio_call')} (${_formatDuration(_elapsedSeconds)})',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: healthColor.withOpacity(0.45)),
              ),
              child: Text(
                '${_controller.networkStatusLabel} • ${_controller.latencyMs} ms',
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: healthColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeaderBar(String remoteName, {required bool isThreeOrMoreCall, int participantCount = 2}) {
    // Sade başlık: yalnızca kişi/grup adı, süre ve konferansta kişi sayısı
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurNavigation, sigmaY: JuzzioGlassTokens.blurNavigation),
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                color: _callGlassTint(0.38),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    isThreeOrMoreCall
                        ? const CircleAvatar(
                            radius: 15,
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.groups_rounded, color: Colors.white, size: 16),
                          )
                        : JuzzioGlassAvatar(
                            imageUrl: _remoteHeaderAvatar(),
                            name: remoteName,
                            radius: 15,
                          ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            remoteName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            isThreeOrMoreCall
                                ? '${_formatDuration(_elapsedSeconds)} • $participantCount/4'
                                : _formatDuration(_elapsedSeconds),
                            style: const TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isConference && _canManageCall && _controller.remoteParticipants.isNotEmpty) ...[
              _topGlassCircleButton(
                icon: Icons.manage_accounts_rounded,
                iconColor: Colors.white,
                tooltip: _app.loc('Katılımcıları yönet', 'Manage participants', 'Teilnehmer verwalten'),
                onTap: _openManageParticipantsSheet,
              ),
              const SizedBox(width: 6),
            ],
            if (widget.sessionId != null && widget.invitableUsers.isNotEmpty) ...[
              _topGlassCircleButton(
                icon: Icons.person_add_alt_1_rounded,
                iconColor: Colors.white,
                tooltip: _app.loc('Kişi ekle', 'Add people', 'Personen hinzufügen'),
                onTap: _openAddParticipantSheet,
              ),
              const SizedBox(width: 6),
            ],
            if (_controller.isCameraEnabled && JuzzioFeaturesService.instance.lastAppConfig.beautyFilterEnabled) ...[
              _topGlassCircleButton(
                icon: Icons.auto_awesome_rounded,
                iconColor: _controller.isBeautyOn ? const Color(0xFF111113) : Colors.white,
                active: _controller.isBeautyOn,
                tooltip: _app.loc('Güzelleştirme', 'Beauty', 'Verschönerung'),
                onTap: _toggleBeauty,
              ),
              const SizedBox(width: 6),
            ],
            if (_controller.isCameraEnabled)
              _topGlassCircleButton(
                icon: Icons.cameraswitch_rounded,
                iconColor: Colors.white,
                tooltip: _app.loc('Kamera Çevir', 'Flip Camera', 'Kamera wechseln'),
                onTap: _flipCamera,
              )
            else
              _topGlassCircleButton(
                icon: Icons.history_rounded,
                iconColor: Colors.white,
                tooltip: _app.loc('Çeviri Geçmişi', 'Translation History', 'Übersetzungsverlauf'),
                onTap: _openSubtitleHistorySheet,
              ),
          ],
        ),
      ],
    );
  }

  Widget _topGlassCircleButton({
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurNavigation, sigmaY: JuzzioGlassTokens.blurNavigation),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? Colors.white.withValues(alpha: 0.92) : _callGlassTint(0.40),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: iconColor, size: 17.5),
          ),
        ),
      ),
    );
  }

  /// Canlı Altyazı Çeviri Kartı:
  /// - Arka planı kapatmayan hafif blurlu buzlu cam (Colors.white.withOpacity(0.72))
  /// - Okunurluğu artıran yüksek kontrastlı siyah yazı fontu (JuzzioColors.midnight)
  /// - Özel boyutlandırma tutamacı (en ve boy sürükleyerek ayarlanabilir)
  /// - Mini geçmiş kapalıyken bile son 3 mesajı gösterme
  /// - Ses izi algılama (@fikret39, @ari, @tugkancr) ve bölünen konuyu otomatik devam ettirme
  bool get _showSubtitles =>
      _isTranslatorVisible && JuzzioFeaturesService.instance.lastAppConfig.liveTranslationEnabled;

  /// Sesli arama mı? (kimsenin görüntüsü yok)
  bool _isVoiceOnlyCall(List<_ParticipantSlotData> slots) {
    return !_controller.isCameraEnabled && slots.every((s) => s.videoTrack == null || s.isLocal);
  }

  String? _remoteHeaderAvatar() {
    final remotes = _controller.remoteParticipants;
    if (remotes.length == 1) return _avatarForIdentity(remotes.first.identity) ?? widget.partnerAvatarUrl;
    return widget.partnerAvatarUrl;
  }

  String _speakerLabel(LiveSubtitlePacket p) {
    if (p.speakerId == widget.userIdentity) return _app.loc('Sen', 'You', 'Du');
    final n = p.speakerName.trim();
    return n.isEmpty ? p.formattedHandle : n;
  }

  /// Altyazı paneli başlığı (dil çifti + geçmiş/küçült/kapat)
  Widget _captionHeader({required bool dense}) {
    final langs = '${_app.subtitleLang.toUpperCase()} ⇄ ${_controller.targetLang.toUpperCase()}';
    return Row(
      children: [
        const Icon(Icons.translate_rounded, color: JuzzioColors.emerald400, size: 16),
        const SizedBox(width: 6),
        Text(langs, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w800)),
        const Spacer(),
        _pillIcon(Icons.history_rounded, _app.loc('Çeviri geçmişi', 'Translation history', 'Übersetzungsverlauf'),
            _openSubtitleHistorySheet),
        _pillIcon(Icons.text_increase_rounded, _app.loc('Yazı boyutu', 'Text size', 'Textgröße'), () {
          setState(() => _subtitleFontScale = _subtitleFontScale >= 1.3 ? 0.9 : _subtitleFontScale + 0.2);
        }),
        _pillIcon(Icons.unfold_less_rounded, _app.loc('Küçült', 'Minimize', 'Minimieren'),
            () => setState(() => _isTranslatorMinimized = true)),
        _pillIcon(Icons.close_rounded, _app.loc('Kapat', 'Close', 'Schließen'), () {
          setState(() {
            _isTranslatorVisible = false;
            _userManuallyToggledTranslator = true;
          });
        }),
      ],
    );
  }

  Widget _collapsedCaption(String last) {
    final langs = '${_app.subtitleLang.toUpperCase()} ⇄ ${_controller.targetLang.toUpperCase()}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.translate_rounded, color: JuzzioColors.emerald400, size: 16),
        const SizedBox(width: 6),
        Text(langs, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
        if (last.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  /// SESLİ ARAMA: ekranın ortasında büyük, okunaklı konuşma kartı.
  /// Yüz olmadığı için alan geniştir; son 3 bölüt konuşmacı adıyla gösterilir.
  Widget _buildVoiceTranscriptCard({required Size screenSize, required double bottomBase}) {
    final segs = _controller.recentSegments(count: 3);
    final collapsed = _isTranslatorMinimized;
    final waiting = _app.loc('Konuşma bekleniyor...', 'Waiting for speech...', 'Warte auf Sprache...');
    final scale = _subtitleFontScale;
    return Positioned(
      left: 14,
      right: 14,
      bottom: bottomBase,
      child: GestureDetector(
        onTap: collapsed ? () => setState(() => _isTranslatorMinimized = false) : null,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: JuzzioGlass(
            radius: collapsed ? 999 : 26,
            padding: collapsed
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                : const EdgeInsets.fromLTRB(16, 10, 8, 16),
            color: _callGlassTint(0.30),
            strongBorder: true,
            shadow: JuzzioGlassTokens.shadow,
            child: collapsed
                ? _collapsedCaption(segs.isEmpty ? '' : segs.last.translatedText)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: screenSize.height * 0.42, maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _captionHeader(dense: false),
                        const SizedBox(height: 6),
                        if (segs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(waiting, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                          )
                        else
                          Flexible(
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < segs.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10, right: 8),
                                      child: Opacity(
                                        opacity: i == segs.length - 1 ? 1 : 0.62,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _speakerLabel(segs[i]) + (segs[i].isFinal ? '' : ' · ${_app.loc("konuşuyor", "speaking", "spricht")}'),
                                              style: const TextStyle(
                                                color: JuzzioColors.emerald400,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              segs[i].translatedText,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: (22 * scale).clamp(17.0, 30.0),
                                                fontWeight: FontWeight.w700,
                                                height: 1.3,
                                              ),
                                            ),
                                            if (segs[i].originalText.trim().isNotEmpty &&
                                                segs[i].originalText.trim() != segs[i].translatedText.trim())
                                              Padding(
                                                padding: const EdgeInsets.only(top: 3),
                                                child: Text(
                                                  segs[i].originalText,
                                                  style: TextStyle(color: Colors.white60, fontSize: (14 * scale).clamp(12.0, 19.0)),
                                                ),
                                              ),
                                          ],
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
          ),
        ),
      ),
    );
  }

  /// GÖRÜNTÜLÜ ARAMA: kontrollerin hemen üstünde, yüzleri kapatmayan alt altyazı
  /// şeridi. Büyük yazı, en fazla 2 bölüt; yukarı sürüklenebilir.
  Widget _buildVideoCaptionStrip({required Size screenSize, required double bottomBase}) {
    final segs = _controller.recentSegments(count: 2);
    final collapsed = _isTranslatorMinimized;
    final waiting = _app.loc('Konuşma bekleniyor...', 'Waiting for speech...', 'Warte auf Sprache...');
    final double maxBottom = screenSize.height - 240.0 > 8.0 ? screenSize.height - 240.0 : 8.0;
    final double bottom = (bottomBase - _translatorOffset.dy).clamp(8.0, maxBottom).toDouble();
    final scale = _subtitleFontScale;

    return Positioned(
      left: 10,
      right: 10,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() {
            final nextDy = (_translatorOffset.dy + d.delta.dy).clamp(-(screenSize.height * 0.55), bottomBase - 8.0);
            _translatorOffset = Offset(0, nextDy);
          }),
          onTap: collapsed ? () => setState(() => _isTranslatorMinimized = false) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(collapsed ? 999 : 22),
            child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurNavigation, sigmaY: JuzzioGlassTokens.blurNavigation),
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(maxWidth: collapsed ? 300 : min(screenSize.width - 20, 520.0)),
            padding: collapsed
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : const EdgeInsets.fromLTRB(14, 6, 6, 12),
            decoration: BoxDecoration(
              // Glassmorphism altyazı şeridi: buzlu koyu cam + kristal kenar + üstten ışık
              // v0.8.1: sıvı cam altyazı şeridi seçili cam temasının tonunu taşır
              // (renk + gradyan tek kutuda çizilmediği için ton gradyana karıştırıldı)
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(const Color(0x33FFFFFF), _callGlassTint(0.42)),
                  Color.alphaBlend(const Color(0x0AFFFFFF), _callGlassTint(0.42)),
                  Color.alphaBlend(const Color(0x14000000), _callGlassTint(0.46)),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(collapsed ? 999 : 22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            child: collapsed
                ? _collapsedCaption(segs.isEmpty ? '' : segs.last.translatedText)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _captionHeader(dense: true),
                      if (segs.isEmpty)
                        Text(waiting, style: const TextStyle(color: Colors.white54, fontSize: 15))
                      else
                        for (var i = 0; i < segs.length; i++)
                          Padding(
                            padding: EdgeInsets.only(right: 8, top: i == 0 ? 0 : 6),
                            child: RichText(
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: const TextStyle(fontFamilyFallback: kJuzzioEmojiFallback),
                                children: [
                                  TextSpan(
                                    text: '${_speakerLabel(segs[i])}: ',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: (14 * scale).clamp(12.0, 19.0),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(
                                    text: segs[i].translatedText,
                                    style: TextStyle(
                                      color: i == segs.length - 1 ? Colors.white : Colors.white70,
                                      fontSize: (19 * scale).clamp(15.0, 26.0),
                                      fontWeight: FontWeight.w700,
                                      height: 1.28,
                                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
          ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        iconSize: 18,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white70),
      ),
    );
  }

  Widget _buildBottomControlsBar() {
    // Glassmorphism kontrol rafı: buzlu cam kapsül içinde yuvarlak cam düğmeler
    return JuzzioGlass(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: _callGlassTint(0.26),
      strongBorder: true,
      shadow: JuzzioGlassTokens.shadow,
      child: _buildBottomControlsRow(),
    );
  }

  Widget _buildBottomControlsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 1. Mikrofon (Yarı Saydam Cam Yuvarlak)
        _bottomCircleBtn(
          icon: _controller.isMicEnabled ? Icons.mic_none_rounded : Icons.mic_off_rounded,
          isMutedOrOff: !_controller.isMicEnabled,
          onTap: _controller.toggleMicrophone,
        ),
        // 2. Hoparlör / Ses (Yarı Saydam Cam Yuvarlak)
        _bottomCircleBtn(
          icon: _controller.isSpeakerphoneOn ? Icons.volume_up_outlined : Icons.volume_off_outlined,
          isMutedOrOff: !_controller.isSpeakerphoneOn,
          onTap: _controller.toggleSpeakerphone,
        ),
        // 3. Kamera (Yarı Saydam Cam Yuvarlak)
        _bottomCircleBtn(
          icon: _controller.isCameraEnabled ? Icons.videocam_outlined : Icons.videocam_off_outlined,
          isMutedOrOff: !_controller.isCameraEnabled,
          onTap: _controller.toggleCamera,
        ),
        // 6. Canlı çeviri kapsülünü aç / kapat
        if (JuzzioFeaturesService.instance.lastAppConfig.liveTranslationEnabled)
          _bottomCircleBtn(
            icon: Icons.translate_rounded,
            isMutedOrOff: false,
            highlighted: _isTranslatorVisible,
            onTap: () => setState(() {
              _isTranslatorVisible = !_isTranslatorVisible;
          if (_isTranslatorVisible) _controller.ensureSubtitles(force: true);
              _isTranslatorMinimized = false;
              _userManuallyToggledTranslator = true;
            }),
          ),
        // 5. Aramayı Kapat 'X' (Canlı Kırmızı #EA3423 Yuvarlak — Görsel ile Birebir!)
        GestureDetector(
          onTap: _hangUpAndCloseForEveryone,
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: JuzzioColors.redAlert,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  /// Güzelleştirme: tek dokunuşla aç/kapat (doğal mod, görüntüyü bulanıklaştırmaz)
  Future<void> _toggleBeauty() async {
    final ok = await _controller.toggleBeauty();
    _app.setCameraBeautyEnabled(_controller.isBeautyOn);
    if (!mounted) return;
    setState(() {});
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 1400),
      content: Text(
        !ok && _controller.isBeautyOn
            ? _app.loc('Güzelleştirme kamera açıldığında uygulanacak.', 'The filter will apply once the camera is on.',
                'Der Filter wird angewendet, sobald die Kamera an ist.')
            : (_controller.isBeautyOn
                ? _app.loc('Güzelleştirme açık', 'Beauty on', 'Verschönerung an')
                : _app.loc('Güzelleştirme kapalı', 'Beauty off', 'Verschönerung aus')),
      ),
    ));
  }

  Widget _bottomCircleBtn({
    required IconData icon,
    required bool isMutedOrOff,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: JuzzioGlassTokens.blurNavigation, sigmaY: JuzzioGlassTokens.blurNavigation),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isMutedOrOff
                  ? JuzzioColors.redAlert.withValues(alpha: 0.75)
                  : (highlighted ? Colors.white.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.16)),
              gradient: isMutedOrOff || highlighted
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x40FFFFFF), Color(0x10FFFFFF)],
                    ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: highlighted && !isMutedOrOff ? const Color(0xFF111113) : Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
