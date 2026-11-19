// =============================================================================
// JUZZIO v0.9.5 — Watch Party (sohbette senkron film/video izleme)
// JUZZIO v1.2.8 — Sinema Parti yeniden yazıldı
//  • HER bağlantı izlenir: doğrudan video (.mp4/.webm), canlı akış (.m3u8), YouTube ve kendi
//    oynatıcısını kullanan film/dizi siteleri. Siteler uygulama içi tarayıcıda açılır; sayfaya
//    (gömülü çerçeveler dahil) küçük bir eşitleme betiği eklenir, sayfadaki asıl video bulunur
//    ve oynat/duraklat/sar herkeste aynı saniyede uygulanır. "Senkron oynatılamaz" hatası yok.
//  • En çok 4 kişi: izleyiciler aynı zamanda sesli odada konuşur. Alttaki şeritte her kişinin
//    fotoğrafı; mikrofonu kapalıysa yanında üstü çizili mikrofon, konuşurken yeşil halka.
//  • Başlatınca sohbete "KATIL" kartı düşer ve herkese bildirim gider (sunucu: 10.37).
//  • Tam ekran (yatay) ve küçük pencere (uygulamadan çıkınca film yan pencerede sürer).
//  • Sitedeki altyazılar okunur, izleyicinin diline çevrilir ve kelimeler cihazdaki çeviri
//    hafızasına eklenir: izledikçe çeviri hızlanır.
// =============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:video_player/video_player.dart';

import '../core/juzzio_duration_format.dart';
import '../core/app_theme_and_locale.dart';
import '../core/juzzio_pip_state.dart';
import '../services/deepgram_livekit_service.dart' show DeepgramLiveKitController, juzzioBackupConnectOptions;
import '../services/juzzio_time_sync.dart';
import '../services/juzzio_translation_memory.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_motion.dart';
import '../widgets/juzzio_ui_kit.dart';
import '../core/juzzio_text_safety.dart';

class JuzzioWatchSession {
  final String id;
  final String hostId;
  final String url;
  final String title;
  final String kind;
  final bool playing;
  final int positionMs;
  final double rate;
  final String status;
  final DateTime changedAt;
  final String livekitRoom;
  final int maxViewers;

  const JuzzioWatchSession({
    required this.id,
    required this.hostId,
    required this.url,
    required this.title,
    required this.kind,
    required this.playing,
    required this.positionMs,
    required this.rate,
    required this.status,
    required this.changedAt,
    this.livekitRoom = '',
    this.maxViewers = 4,
  });

  static JuzzioWatchSession fromMap(Map<String, dynamic> m) => JuzzioWatchSession(
        id: '${m['id']}',
        hostId: '${m['host_id']}',
        url: '${m['media_url']}',
        title: '${m['media_title'] ?? ''}',
        kind: juzzioWatchKindOf('${m['media_url']}', fallback: '${m['source_kind'] ?? 'direct'}'),
        playing: m['is_playing'] == true,
        positionMs: int.tryParse('${m['position_ms']}') ?? 0,
        rate: double.tryParse('${m['playback_rate']}') ?? 1.0,
        status: '${m['status']}',
        changedAt: DateTime.tryParse('${m['state_changed_at']}')?.toUtc() ?? DateTime.now().toUtc(),
        livekitRoom: '${m['livekit_room_name'] ?? ''}',
        maxViewers: int.tryParse('${m['max_viewers']}') ?? 4,
      );

  /// Sunucu saatine göre şu anki beklenen konum (ms).
  int expectedPositionMs(DateTime nowUtc) => juzzioWatchExpectedPosition(
      positionMs: positionMs, playing: playing, rate: rate, changedAt: changedAt, nowUtc: nowUtc);
}

int juzzioWatchExpectedPosition({required int positionMs, required bool playing, required double rate, required DateTime changedAt, required DateTime nowUtc}) {
  if (!playing) return positionMs;
  final elapsed = nowUtc.difference(changedAt).inMilliseconds;
  return positionMs + (elapsed.clamp(0, 1 << 31) * rate).round();
}

/// Bağlantı türü (saf; test edilir): direct | hls | youtube | web
String juzzioWatchKindOf(String url, {String fallback = 'web'}) {
  final u = url.trim().toLowerCase();
  if (RegExp(r'\.m3u8(\?|#|$)').hasMatch(u)) return 'hls';
  if (RegExp(r'\.(mp4|webm|mov|m4v|mkv)(\?|#|$)').hasMatch(u)) return 'direct';
  if (juzzioYoutubeId(url) != null) return 'youtube';
  if (u.startsWith('https://')) return 'web';
  return fallback;
}

/// YouTube video kimliği (saf; test edilir): youtu.be/ID, watch?v=ID, shorts/ID, embed/ID, live/ID
String? juzzioYoutubeId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (host == 'youtu.be') {
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return idRe.hasMatch(id) ? id : null;
  }
  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && idRe.hasMatch(v)) return v;
    final seg = uri.pathSegments;
    if (seg.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(seg[0]) && idRe.hasMatch(seg[1])) return seg[1];
  }
  return null;
}

/// Eşitleme gerekli mi (saf; test edilir): 1,5 sn'den fazla kayma düzeltilir
bool juzzioWatchNeedsSeek(int haveMs, int wantMs, {int toleranceMs = 1500}) => (haveMs - wantMs).abs() > toleranceMs;

/// Sayfaya ve TÜM gömülü çerçevelere eklenen eşitleme betiği. Her çerçeve kendi videosunu
/// bulur, saniyede bir durumunu bildirir; yanıt olarak bekleyen komutu (sar/oynat/duraklat)
/// alır ve uygular. Kullanıcı sayfada oynat/duraklat/sar yaparsa olay olarak bildirilir.
const String kJuzzioWatchSyncJs = r'''
(function(){
  if (window.__jzWatch) return; window.__jzWatch = true;
  var fid = Math.random().toString(36).slice(2);
  var vid = null, applying = 0, lastCue = '';
  function bridge(){ return window.flutter_inappwebview && window.flutter_inappwebview.callHandler; }
  function score(v){
    var r = v.getBoundingClientRect ? v.getBoundingClientRect() : {width:0,height:0};
    var area = Math.max(r.width*r.height, (v.videoWidth||0)*(v.videoHeight||0)*0.2);
    var d = isFinite(v.duration) ? v.duration : 7200;
    return area * (d > 90 ? 3 : 1) * (v.readyState > 0 ? 2 : 1);
  }
  function pick(){
    var vs = document.getElementsByTagName('video'), best = null, bs = -1;
    for (var i = 0; i < vs.length; i++){ var s = score(vs[i]); if (s > bs){ bs = s; best = vs[i]; } }
    return best;
  }
  function state(t){
    return {t:t, fid:fid, href:location.href.slice(0,200), pos: vid ? vid.currentTime : 0,
      playing: vid ? !vid.paused : false, rate: vid ? vid.playbackRate : 1,
      dur: vid && isFinite(vid.duration) ? vid.duration : 0, score: vid ? score(vid) : 0};
  }
  function send(o){
    var b = bridge(); if (!b) return;
    try { window.flutter_inappwebview.callHandler('jzwp', JSON.stringify(o)).then(apply).catch(function(){}); } catch(e){}
  }
  function apply(cmd){
    if (!cmd || !vid) return;
    try { if (typeof cmd === 'string') cmd = JSON.parse(cmd); } catch(e){ return; }
    if (!cmd || cmd.fid !== fid) return;
    applying = Date.now();
    try {
      if (typeof cmd.rate === 'number' && cmd.rate > 0 && Math.abs(vid.playbackRate - cmd.rate) > 0.01) vid.playbackRate = cmd.rate;
      if (typeof cmd.seek === 'number' && Math.abs(vid.currentTime - cmd.seek) > 1.2) vid.currentTime = cmd.seek;
      if (cmd.play === true && vid.paused){ var p = vid.play(); if (p && p.catch) p.catch(function(){ vid.muted = true; vid.play(); }); }
      if (cmd.play === false && !vid.paused) vid.pause();
      if (cmd.unmute === true) vid.muted = false;
    } catch(e){}
  }
  function attach(v){
    if (vid === v) return; vid = v;
    ['play','pause','seeked','ratechange'].forEach(function(ev){
      v.addEventListener(ev, function(){ if (Date.now() - applying < 1300) return; send(state(ev)); });
    });
    send(state('found'));
  }
  function cues(){
    try {
      var tt = vid.textTracks, out = [];
      for (var i = 0; i < tt.length; i++){
        if (tt[i].mode === 'disabled' || !tt[i].activeCues) continue;
        for (var j = 0; j < tt[i].activeCues.length; j++){ var c = tt[i].activeCues[j]; if (c && c.text) out.push(c.text); }
      }
      var s = out.join(' ').replace(/<[^>]+>/g,'').trim();
      if (s && s !== lastCue){ lastCue = s; send({t:'cue', fid:fid, text:s.slice(0,300)}); }
    } catch(e){}
  }
  setInterval(function(){
    var v = pick(); if (v) attach(v);
    if (vid){ send(state('tick')); cues(); }
  }, 900);
})();
''';

class JuzzioWatchPartyScreen extends StatefulWidget {
  const JuzzioWatchPartyScreen({super.key, required this.roomId, this.autoStart = false});
  final String roomId;

  /// Açılınca doğrudan "bağlantı ekle" sayfasını göster (oturum yoksa)
  final bool autoStart;

  static Future<void> open(BuildContext context, String roomId, {bool autoStart = false}) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => JuzzioWatchPartyScreen(roomId: roomId, autoStart: autoStart),
          transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
          ),
        ),
      );

  @override
  State<JuzzioWatchPartyScreen> createState() => _JuzzioWatchPartyScreenState();
}

class _Viewer {
  _Viewer(this.userId, this.name, this.avatar);
  final String userId;
  final String name;
  final String? avatar;
}

class _JuzzioWatchPartyScreenState extends State<JuzzioWatchPartyScreen> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  static const MethodChannel _native = MethodChannel('juzzio/notifications');

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<Map<String, dynamic>>>? _viewerSub;
  JuzzioWatchSession? _s;
  String? _joinedSession;
  VideoPlayerController? _vc;
  String? _loadedUrl;
  Timer? _syncTimer;
  Timer? _heartbeat;
  Timer? _uiTick;
  String? _error;
  bool _loading = true;
  bool _fullscreen = false;
  bool _startShown = false;

  // web/YouTube oynatıcı durumu (betikten gelen)
  String? _webFrame; // asıl videonun çerçevesi
  double _webFrameScore = 0;
  int _webPosMs = 0;
  double _webDur = 0;
  Map<String, dynamic>? _pendingCmd;
  DateTime _lastLocalEvent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _youtubeFallback = false;

  // izleyiciler + sesli oda
  final List<_Viewer> _viewers = <_Viewer>[];
  final Map<String, _Viewer> _profileCache = <String, _Viewer>{};
  Room? _room;
  bool _micOn = true;
  bool _voiceConnecting = false;

  // altyazı çevirisi
  bool _translateCues = true;
  String _cueOriginal = '';
  String _cueTranslated = '';
  final List<String> _cueHistory = <String>[];

  String get _myId => SupabaseService.instance.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _sub = _db.from('watch_party_sessions').stream(primaryKey: ['id']).eq('room_id', widget.roomId).listen((rows) {
      final active = rows.where((r) => r['status'] == 'active').toList();
      final s = active.isEmpty ? null : JuzzioWatchSession.fromMap(active.last);
      if (!mounted) return;
      final changedSession = s?.id != _s?.id;
      setState(() {
        _s = s;
        _loading = false;
      });
      if (changedSession) unawaited(_onSessionChanged());
      unawaited(_applySession());
      if (s == null && widget.autoStart && !_startShown) {
        _startShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _start());
      }
    }, onError: (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _correctDrift());
    _uiTick = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted && _room != null) setState(() {}); // konuşma halkası / mikrofon simgesi
    });
    JuzzioPipState.inPip.addListener(_onPip);
    unawaited(JuzzioTimeSync.instance.check());
  }

  void _onPip() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _viewerSub?.cancel();
    _syncTimer?.cancel();
    _heartbeat?.cancel();
    _uiTick?.cancel();
    JuzzioPipState.inPip.removeListener(_onPip);
    _vc?.dispose();
    final sid = _joinedSession;
    if (sid != null) unawaited(_db.rpc('leave_watch_party', params: {'p_session': sid}).then((_) {}, onError: (_) {}));
    unawaited(_leaveVoice());
    unawaited(_native.invokeMethod('setWatchActive', {'active': false}).then((_) {}, onError: (_) {}));
    if (_fullscreen) _restoreOrientation();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Oturum: katıl, izleyiciler, sesli oda
  // ---------------------------------------------------------------------------
  Future<void> _onSessionChanged() async {
    final s = _s;
    _viewerSub?.cancel();
    _heartbeat?.cancel();
    final old = _joinedSession;
    if (old != null && old != s?.id) {
      unawaited(_db.rpc('leave_watch_party', params: {'p_session': old}).then((_) {}, onError: (_) {}));
      _joinedSession = null;
      await _leaveVoice();
    }
    _webFrame = null;
    _webFrameScore = 0;
    _pendingCmd = null;
    _youtubeFallback = false;
    if (s == null) {
      unawaited(_native.invokeMethod('setWatchActive', {'active': false}).then((_) {}, onError: (_) {}));
      return;
    }
    try {
      final res = await _db.rpc('join_watch_party', params: {'p_session': s.id});
      _joinedSession = s.id;
      final lk = (res is Map ? res['livekit_room'] : null)?.toString() ?? s.livekitRoom;
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(_db.rpc('watch_party_heartbeat', params: {'p_session': s.id}).then((_) {}, onError: (_) {}));
      });
      // v1.2.9: otomatik küçük pencere yalnız yerel oynatıcıda (web sayfası küçük pencerede siyah kalıyordu)
      unawaited(_native.invokeMethod('setWatchActive', {'active': true, 'auto': s.kind == 'direct' || s.kind == 'hls'}).then((_) {}, onError: (_) {}));
      if (lk.isNotEmpty) unawaited(_joinVoice(lk));
    } catch (e) {
      final raw = e.toString();
      if (mounted) {
        setState(() => _error = raw.contains('watch_party_full')
            ? _app.trEn('Sinema dolu: en fazla 4 kişi birlikte izleyebilir.', 'The cinema is full: up to 4 people can watch together.',
                'Das Kino ist voll: höchstens 4 Personen.')
            : SupabaseService.instance.friendlyError(e));
      }
    }
    _viewerSub = _db.from('watch_party_viewers').stream(primaryKey: ['session_id', 'user_id']).eq('session_id', s.id).listen((rows) async {
      final now = DateTime.now().toUtc();
      final ids = rows
          .where((r) => r['left_at'] == null &&
              (DateTime.tryParse('${r['last_seen_at']}')?.toUtc() ?? now).isAfter(now.subtract(const Duration(seconds: 75))))
          .map((r) => '${r['user_id']}')
          .toList();
      await _ensureProfiles(ids);
      if (!mounted) return;
      setState(() {
        _viewers
          ..clear()
          ..addAll(ids.map((id) => _profileCache[id] ?? _Viewer(id, 'Juzzio', null)));
      });
    }, onError: (_) {});
  }

  Future<void> _ensureProfiles(List<String> ids) async {
    final missing = ids.where((id) => !_profileCache.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final rows = await _db.from('profiles').select('id, display_name, username, avatar_url').inFilter('id', missing);
      for (final r in rows) {
        final id = '${r['id']}';
        final name = '${r['display_name'] ?? ''}'.trim().isNotEmpty ? '${r['display_name']}' : '${r['username'] ?? 'Juzzio'}';
        _profileCache[id] = _Viewer(id, name, r['avatar_url']?.toString());
      }
    } catch (_) {}
  }

  Future<void> _joinVoice(String livekitRoom) async {
    if (_room != null || _voiceConnecting) return;
    _voiceConnecting = true;
    try {
      final access = await SupabaseService.instance.fetchLiveKitToken(
        roomName: livekitRoom,
        identity: _myId,
        displayName: '',
        lang: _app.subtitleLang,
      );
      final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      try {
        await room.connect(access.url, access.token,
            connectOptions: DeepgramLiveKitController.preferBackupTurn && access.backupIceServers.isNotEmpty
                ? juzzioBackupConnectOptions(access.backupIceServers)
                : const ConnectOptions());
      } catch (_) {
        // v1.2.9: ana yol kurulamadı → yedek TURN
        if (access.backupIceServers.isEmpty) rethrow;
        await room.connect(access.url, access.token, connectOptions: juzzioBackupConnectOptions(access.backupIceServers));
      }
      await room.localParticipant?.setMicrophoneEnabled(_micOn);
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (_) {}
      if (!mounted) {
        await room.disconnect();
        return;
      }
      setState(() => _room = room);
    } catch (_) {
      // ses bağlanamasa da film izlenir
    } finally {
      _voiceConnecting = false;
    }
  }

  Future<void> _leaveVoice() async {
    final r = _room;
    _room = null;
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Participant? _participantFor(String userId) {
    final r = _room;
    if (r == null) return null;
    if (userId == _myId) return r.localParticipant;
    for (final p in r.remoteParticipants.values) {
      if (p.identity.split('_').first == userId) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Oynatma: doğrudan video / HLS
  // ---------------------------------------------------------------------------
  Future<void> _applySession() async {
    final s = _s;
    if (s == null || s.kind == 'web' || s.kind == 'youtube') {
      await _vc?.dispose();
      _vc = null;
      _loadedUrl = null;
      if (s != null) _queueWebCommand(s);
      if (mounted) setState(() {});
      return;
    }
    if (_loadedUrl != s.url) {
      await _vc?.dispose();
      final vc = VideoPlayerController.networkUrl(Uri.parse(s.url), formatHint: s.kind == 'hls' ? VideoFormat.hls : null);
      _vc = vc;
      _loadedUrl = s.url;
      try {
        await vc.initialize();
      } catch (_) {
        // açılamayan doğrudan bağlantı → sayfa olarak tarayıcıda dene
        _vc = null;
        if (mounted) setState(() => _error = null);
        return;
      }
      if (mounted) setState(() {});
    }
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;
    await vc.setPlaybackSpeed(s.rate);
    final want = s.expectedPositionMs(JuzzioClock.nowUtc());
    if (juzzioWatchNeedsSeek(vc.value.position.inMilliseconds, want, toleranceMs: 700)) {
      await vc.seekTo(Duration(milliseconds: want));
    }
    if (s.playing) {
      await vc.play();
    } else {
      await vc.pause();
    }
  }

  void _correctDrift() {
    final s = _s;
    if (s == null) return;
    if (s.kind == 'web' || s.kind == 'youtube' || _vc == null) {
      if (_webFrame != null && s.playing) {
        final want = s.expectedPositionMs(JuzzioClock.nowUtc());
        if (juzzioWatchNeedsSeek(_webPosMs, want, toleranceMs: 2000)) _queueWebCommand(s);
      }
      return;
    }
    final vc = _vc!;
    if (!vc.value.isInitialized || !s.playing) return;
    final want = s.expectedPositionMs(JuzzioClock.nowUtc());
    if (juzzioWatchNeedsSeek(vc.value.position.inMilliseconds, want)) vc.seekTo(Duration(milliseconds: want));
  }

  Future<void> _control({bool? playing, int? positionMs, double? rate}) async {
    final s = _s;
    if (s == null) return;
    final pos = positionMs ?? _vc?.value.position.inMilliseconds ?? (_webFrame != null ? _webPosMs : s.expectedPositionMs(JuzzioClock.nowUtc()));
    try {
      await _db.rpc('watch_party_control', params: {
        'p_session': s.id,
        'p_playing': playing ?? s.playing,
        'p_position_ms': pos,
        'p_rate': rate ?? s.rate,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  // ---------------------------------------------------------------------------
  // Oynatma: web sitesi / YouTube (uygulama içi tarayıcı + eşitleme betiği)
  // ---------------------------------------------------------------------------
  void _queueWebCommand(JuzzioWatchSession s) {
    final f = _webFrame;
    if (f == null) return;
    _pendingCmd = {
      'fid': f,
      'seek': s.expectedPositionMs(JuzzioClock.nowUtc()) / 1000.0,
      'play': s.playing,
      'rate': s.rate,
    };
  }

  /// Betikten gelen her bildirim: durum, olay veya altyazı. Yanıt: o çerçeveye bekleyen komut
  dynamic _onWebMessage(List<dynamic> args) {
    if (args.isEmpty) return null;
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(args.first.toString()) as Map);
    } catch (_) {
      return null;
    }
    final fid = '${m['fid'] ?? ''}';
    final t = '${m['t'] ?? ''}';
    if (t == 'cue') {
      // v1.2.9: sayfadan gelen altyazı güvenilmez girdidir — uzunluk ve hız sınırı (çeviri kotası korunur)
      final now = DateTime.now();
      if (now.difference(_lastCueAt).inMilliseconds < 350) return null;
      _lastCueAt = now;
      final raw = '${m['text'] ?? ''}';
      unawaited(_onCue(juzzioSafeCut(raw, 300)));
      return null;
    }
    final score = (m['score'] as num?)?.toDouble() ?? 0;
    final dur = (m['dur'] as num?)?.toDouble() ?? 0;
    // en büyük ve en uzun video asıl oynatıcıdır (reklam videoları elenir)
    if (_webFrame == null || fid == _webFrame || score > _webFrameScore * 1.5 || (dur > 300 && _webDur < 120)) {
      final isNew = _webFrame != fid;
      _webFrame = fid;
      _webFrameScore = score;
      _webDur = dur;
      _webPosMs = (((m['pos'] as num?)?.toDouble() ?? 0) * 1000).round();
      final s = _s;
      if (isNew && s != null) {
        _queueWebCommand(s);
        if (mounted) setState(() {});
      }
    }
    if (fid != _webFrame) return null;
    // izleyici sayfada oynat/duraklat/sar yaptı → herkese yay
    if ((t == 'play' || t == 'pause' || t == 'seeked' || t == 'ratechange') && DateTime.now().difference(_lastLocalEvent).inMilliseconds > 700) {
      _lastLocalEvent = DateTime.now();
      final s = _s;
      final pos = (((m['pos'] as num?)?.toDouble() ?? 0) * 1000).round();
      final rate = (m['rate'] as num?)?.toDouble() ?? 1.0;
      final playing = m['playing'] == true;
      if (s != null &&
          (playing != s.playing || juzzioWatchNeedsSeek(pos, s.expectedPositionMs(JuzzioClock.nowUtc()), toleranceMs: 2500) || (rate - s.rate).abs() > 0.01)) {
        unawaited(_control(playing: playing, positionMs: pos, rate: rate));
      }
    }
    final cmd = _pendingCmd;
    if (cmd != null && cmd['fid'] == fid) {
      _pendingCmd = null;
      return jsonEncode(cmd);
    }
    return null;
  }

  DateTime _lastCueAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _onCue(String text) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty || clean == _cueOriginal) return;
    _cueOriginal = clean;
    _cueHistory.add(clean);
    if (_cueHistory.length >= 40) {
      // izlenen filmin kelimeleri çeviri hafızasına (arka planda, yavaşça)
      final words = juzzioVocabularyFrom(_cueHistory, limit: 80);
      _cueHistory.clear();
      unawaited(JuzzioTranslationMemory.instance.warmUp(words, _app.subtitleLang, maxNew: 40));
    }
    if (!_translateCues) {
      if (mounted) setState(() => _cueTranslated = '');
      return;
    }
    final tr = await SupabaseService.instance.translateText(text: clean, sourceLang: 'auto', targetLang: _app.subtitleLang);
    if (!mounted || clean != _cueOriginal) return;
    setState(() => _cueTranslated = tr.trim() == clean ? '' : tr);
  }

  String _webStartUrl(JuzzioWatchSession s) {
    final yt = juzzioYoutubeId(s.url);
    if (yt != null) {
      return _youtubeFallback
          ? 'https://m.youtube.com/watch?v=$yt'
          : 'https://www.youtube.com/embed/$yt?playsinline=1&autoplay=1&rel=0&modestbranding=1&enablejsapi=1';
    }
    return s.url;
  }

  Widget _webPlayer(JuzzioWatchSession s) {
    final url = _webStartUrl(s);
    return InAppWebView(
      key: ValueKey('${s.id}|$url'),
      initialUrlRequest: URLRequest(
        url: WebUri(url),
        // YouTube gömülü oynatıcısı yönlendiren (Referer) bilgisi olmadan açılmıyor
        headers: juzzioYoutubeId(s.url) != null ? const {'Referer': 'https://juzzio.app/'} : null,
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        // v1.2.9: yalnız http/https gezinmesine izin verilir (intent:, file:, javascript:, data:, market: engellenir)
        useShouldOverrideUrlLoading: true,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        geolocationEnabled: false,
        transparentBackground: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(source: kJuzzioWatchSyncJs, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, forMainFrameOnly: false),
      ]),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(handlerName: 'jzwp', callback: _onWebMessage);
      },
      shouldOverrideUrlLoading: (c, action) async =>
          juzzioWatchNavigationAllowed(action.request.url?.toString() ?? '') ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL,
      onPermissionRequest: (c, req) async => PermissionResponse(resources: req.resources, action: PermissionResponseAction.DENY),
      onLoadStop: (c, _) async {
        // ana çerçeve için yedek ekleme (betik kendini tekrar kurmaz)
        try {
          await c.evaluateJavascript(source: kJuzzioWatchSyncJs);
        } catch (_) {}
      },
      onEnterFullscreen: (_) => _setFullscreen(true),
      onExitFullscreen: (_) => _setFullscreen(false),
    );
  }

  // ---------------------------------------------------------------------------
  // Tam ekran / küçük pencere
  // ---------------------------------------------------------------------------
  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setFullscreen(bool on) {
    if (_fullscreen == on) return;
    setState(() => _fullscreen = on);
    if (on) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restoreOrientation();
    }
  }

  Future<void> _enterPip() async {
    try {
      await _native.invokeMethod('setWatchActive', {'active': true, 'auto': _s?.kind == 'direct' || _s?.kind == 'hls'});
      final ok = await _native.invokeMethod('enterCallPip') == true;
      if (!ok && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(_app.trEn('Bu cihaz küçük pencereyi desteklemiyor.', 'This device does not support picture-in-picture.',
                'Dieses Gerät unterstützt kein Bild-im-Bild.'))));
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Başlat: modern bağlantı sayfası
  // ---------------------------------------------------------------------------
  Future<void> _start() async {
    final res = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _WatchLinkSheet(),
    );
    if (res == null) return;
    try {
      await _db.rpc('start_watch_party', params: {'p_room': widget.roomId, 'p_url': res.$1, 'p_title': res.$2});
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  Future<void> _end() async {
    final s = _s;
    if (s == null) return;
    try {
      await _db.rpc('end_watch_party', params: {'p_session': s.id});
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------
  Widget _videoArea(JuzzioWatchSession s) {
    final vc = _vc;
    final Widget player;
    if ((s.kind == 'direct' || s.kind == 'hls') && vc != null && vc.value.isInitialized) {
      player = Center(child: AspectRatio(aspectRatio: vc.value.aspectRatio == 0 ? 16 / 9 : vc.value.aspectRatio, child: VideoPlayer(vc)));
    } else if ((s.kind == 'direct' || s.kind == 'hls') && vc == null && _loadedUrl == s.url) {
      // doğrudan bağlantı açılamadı → sayfa olarak dene (yine eşitlenir)
      player = _webPlayer(s);
    } else if (s.kind == 'direct' || s.kind == 'hls') {
      player = const Center(child: JuzzioOrbitLoader());
    } else {
      player = _webPlayer(s);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black, child: player),
        // çevrilmiş altyazı
        if (_translateCues && _cueTranslated.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(10)),
                  child: Text(_cueTranslated,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _viewerStrip() {
    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final v in _viewers.take(4)) _viewerAvatar(v),
          for (var i = _viewers.length; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.4),
                ),
                child: Icon(Icons.person_add_alt_1_rounded, color: Colors.white.withValues(alpha: 0.28), size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewerAvatar(_Viewer v) {
    final part = _participantFor(v.userId);
    final speaking = part?.isSpeaking ?? false;
    final micOn = v.userId == _myId ? _micOn : (part?.isMicrophoneEnabled() ?? false);
    final first = v.name.trim().isEmpty ? 'J' : v.name.trim().characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // konuşan kişinin çevresinde yeşil halka
                  border: Border.all(color: speaking ? const Color(0xFF34D399) : Colors.transparent, width: 3),
                  boxShadow: speaking ? [BoxShadow(color: const Color(0xFF34D399).withValues(alpha: 0.55), blurRadius: 12)] : null,
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF2A2740),
                  backgroundImage: (v.avatar ?? '').startsWith('http') ? NetworkImage(v.avatar!) : null,
                  child: (v.avatar ?? '').startsWith('http')
                      ? null
                      : Text(first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
              if (!micOn)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                    child: const Icon(Icons.mic_off_rounded, size: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 66,
            child: Text(v.userId == _myId ? _app.trEn('Sen', 'You', 'Du') : v.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _controls(JuzzioWatchSession s) {
    final vc = _vc;
    Widget roundBtn(IconData icon, String tip, VoidCallback onTap, {Color? bg, double size = 22}) => Tooltip(
          message: tip,
          child: Material(
            color: bg ?? Colors.white.withValues(alpha: 0.10),
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, color: Colors.white, size: size))),
          ),
        );
    return Column(
      children: [
        if (vc != null && vc.value.isInitialized)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: vc,
            builder: (_, v, __) => Row(children: [
              Text(_fmt(v.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: v.position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
                  max: v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds.toDouble(),
                  onChanged: (x) => vc.seekTo(Duration(milliseconds: x.round())),
                  onChangeEnd: (x) => _control(positionMs: x.round()),
                ),
              ),
              Text(_fmt(v.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          )
        else if (_webFrame != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${_fmt(Duration(milliseconds: _webPosMs))}${_webDur > 0 ? ' / ${_fmt(Duration(seconds: _webDur.round()))}' : ''}  ·  '
              '${_app.trEn('herkeste senkron', 'in sync for everyone', 'für alle synchron')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _app.trEn('Videoyu sayfada başlat — herkeste aynı anda oynar', 'Start the video on the page — it plays for everyone at once',
                  'Starte das Video auf der Seite — es läuft bei allen gleichzeitig'),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            roundBtn(_micOn ? Icons.mic_rounded : Icons.mic_off_rounded, _app.trEn('Mikrofon', 'Microphone', 'Mikrofon'), _toggleMic,
                bg: _micOn ? null : const Color(0xFFEF4444)),
            roundBtn(Icons.replay_10_rounded, juzzioSecondsLabel('-10', _app.uiLang), () {
              final cur = vc != null && vc.value.isInitialized ? vc.value.position.inMilliseconds : (_webFrame != null ? _webPosMs : s.expectedPositionMs(JuzzioClock.nowUtc()));
              _control(positionMs: (cur - 10000).clamp(0, 1 << 31));
            }),
            roundBtn(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, s.playing ? _app.trEn('Duraklat', 'Pause', 'Pause') : _app.trEn('Oynat', 'Play', 'Abspielen'),
                () => _control(playing: !s.playing), bg: const Color(0xFF7B5CFF), size: 30),
            roundBtn(Icons.forward_10_rounded, juzzioSecondsLabel('+10', _app.uiLang), () {
              final cur = vc != null && vc.value.isInitialized ? vc.value.position.inMilliseconds : (_webFrame != null ? _webPosMs : s.expectedPositionMs(JuzzioClock.nowUtc()));
              _control(positionMs: cur + 10000);
            }),
            roundBtn(_translateCues ? Icons.subtitles_rounded : Icons.subtitles_off_rounded, _app.trEn('Altyazı çevirisi', 'Subtitle translation', 'Untertitel-Übersetzung'),
                () => setState(() {
                      _translateCues = !_translateCues;
                      if (!_translateCues) _cueTranslated = '';
                    })),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final inPip = JuzzioPipState.inPip.value;
    // küçük pencere veya tam ekran: yalnız video
    if (s != null && (inPip || _fullscreen)) {
      return PopScope(
        canPop: !_fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _fullscreen) _setFullscreen(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Positioned.fill(child: _videoArea(s)),
            if (_fullscreen && !inPip)
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    onPressed: () => _setFullscreen(false),
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
              ),
          ]),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A16),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.movie_filter_rounded, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              s?.title.isNotEmpty == true ? s!.title : _app.trEn('Sinema Parti', 'Cinema Party', 'Kino-Party'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          if (s != null) ...[
            IconButton(tooltip: _app.trEn('Küçük pencere', 'Picture-in-picture', 'Bild-im-Bild'), onPressed: _enterPip, icon: const Icon(Icons.picture_in_picture_alt_rounded)),
            IconButton(tooltip: _app.trEn('Tam ekran', 'Full screen', 'Vollbild'), onPressed: () => _setFullscreen(true), icon: const Icon(Icons.fullscreen_rounded)),
            if (s.hostId == _myId) IconButton(tooltip: _app.trEn('Bitir', 'End', 'Beenden'), onPressed: _end, icon: const Icon(Icons.stop_circle_outlined)),
          ],
        ],
      ),
      body: _loading
          ? const JuzzioListSkeleton()
          : s == null
              ? _empty()
              : SafeArea(
                  top: false,
                  child: Column(children: [
                    AspectRatio(aspectRatio: 16 / 9, child: _videoArea(s)),
                    if (s.kind == 'youtube' && _webFrame == null)
                      TextButton.icon(
                        onPressed: () => setState(() => _youtubeFallback = !_youtubeFallback),
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                        label: Text(_app.trEn('Oynatıcı açılmadı mı? Diğer YouTube görünümünü dene', 'Player not loading? Try the other YouTube view',
                            'Player lädt nicht? Andere YouTube-Ansicht'),
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                    if (_error != null)
                      Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center)),
                    const Spacer(),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _controls(s)),
                    const SizedBox(height: 10),
                    Text(
                      '${_viewers.length}/4 · ${_app.trEn('sinemadakiler', 'in the cinema', 'im Kino')}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    _viewerStrip(),
                    const SizedBox(height: 8),
                  ]),
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFF7B5CFF), Color(0xFFFF5CA8)]),
              ),
              child: const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 18),
            Text(_app.trEn('Birlikte izleyin', 'Watch together', 'Gemeinsam schauen'),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              _app.trEn('Film, dizi veya YouTube bağlantısı ekle. En fazla 4 kişi aynı anda izler ve sesli konuşur.',
                  'Add a film, series or YouTube link. Up to 4 people watch at the same time and talk.',
                  'Füge einen Film-, Serien- oder YouTube-Link hinzu. Bis zu 4 Personen schauen gleichzeitig.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7B5CFF), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              onPressed: _start,
              icon: const Icon(Icons.add_link_rounded),
              label: Text(_app.trEn('Bağlantı ekle', 'Add a link', 'Link hinzufügen')),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          ]),
        ),
      );
}

/// v1.2.8 — modern bağlantı ekleme sayfası: yapıştır, kaynak otomatik tanınır, başlık önerilir
class _WatchLinkSheet extends StatefulWidget {
  const _WatchLinkSheet();

  @override
  State<_WatchLinkSheet> createState() => _WatchLinkSheetState();
}

class _WatchLinkSheetState extends State<_WatchLinkSheet> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _app = JuzzioAppController.instance;
  /// v1.2.9 (telif): "izleme hakkım var" onayı olmadan parti başlatılamaz
  bool _rightsOk = false;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
    _pasteIfLink();
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _pasteIfLink() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = d?.text?.trim() ?? '';
      if (t.startsWith('https://') && _url.text.isEmpty && mounted) _url.text = t;
    } catch (_) {}
  }

  ({IconData icon, String label, Color color}) _source(String url) {
    switch (juzzioWatchKindOf(url, fallback: '')) {
      case 'youtube':
        return (icon: Icons.smart_display_rounded, label: 'YouTube', color: const Color(0xFFFF3B30));
      case 'hls':
        return (icon: Icons.live_tv_rounded, label: _app.trEn('Canlı akış', 'Live stream', 'Livestream'), color: const Color(0xFF34D399));
      case 'direct':
        return (icon: Icons.movie_rounded, label: _app.trEn('Video dosyası', 'Video file', 'Videodatei'), color: const Color(0xFF60A5FA));
      case 'web':
        final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
        return (icon: Icons.public_rounded, label: host.isEmpty ? _app.trEn('Web sitesi', 'Website', 'Webseite') : host, color: const Color(0xFFFBBF24));
      default:
        return (icon: Icons.link_rounded, label: _app.trEn('https:// ile başlayan bağlantı', 'A link starting with https://', 'Link mit https://'), color: Colors.white38);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url.text.trim();
    final linkOk = url.startsWith('https://') && url.length > 10;
    final valid = linkOk && _rightsOk;
    final src = _source(url);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF14121F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(colors: [Color(0xFF7B5CFF), Color(0xFFFF5CA8)]),
                  ),
                  child: const Icon(Icons.movie_filter_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_app.trEn('Sinema Parti başlat', 'Start a Cinema Party', 'Kino-Party starten'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(_app.trEn('Her bağlantı · en fazla 4 kişi · sesli sohbet', 'Any link · up to 4 people · voice chat', 'Jeder Link · bis zu 4 · Sprachchat'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: valid ? src.color.withValues(alpha: 0.7) : Colors.white12, width: 1.4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(children: [
                  Icon(src.icon, color: src.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _url,
                      autofocus: _url.text.isEmpty,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: _app.trEn('Film, dizi veya YouTube bağlantısını yapıştır', 'Paste a film, series or YouTube link',
                            'Film-, Serien- oder YouTube-Link einfügen'),
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _app.trEn('Yapıştır', 'Paste', 'Einfügen'),
                    icon: const Icon(Icons.content_paste_rounded, color: Colors.white70),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      final t = d?.text?.trim() ?? '';
                      if (t.isNotEmpty) _url.text = t;
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Row(
                  key: ValueKey(src.label),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: src.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(src.icon, size: 14, color: src.color),
                        const SizedBox(width: 6),
                        Text(src.label, style: TextStyle(color: src.color, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    if (linkOk)
                      Expanded(
                        child: Text(_app.trEn('herkeste senkron oynar', 'plays in sync for everyone', 'läuft bei allen synchron'),
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                maxLength: 150,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.title_rounded, color: Colors.white54),
                  hintText: _app.trEn('Başlık (isteğe bağlı)', 'Title (optional)', 'Titel (optional)'),
                  hintStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _rightsOk = !_rightsOk),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: _rightsOk ? const Color(0xFFC7F43A) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _rightsOk ? const Color(0xFFC7F43A) : Colors.white38, width: 1.6),
                      ),
                      child: _rightsOk ? const Icon(Icons.check_rounded, size: 16, color: Color(0xFF0F1604)) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _app.trEn(
                            'Bu içeriği izleme hakkım var (abonelik, ücretsiz yayın veya kendi videom). Korsan içerik paylaşmıyorum; Juzzio içerik barındırmaz, yalnız bağlantıyı eş zamanlar.',
                            'I have the right to watch this (subscription, free stream or my own video). I am not sharing pirated content; Juzzio hosts nothing and only syncs the link.',
                            'Ich habe das Recht, dies anzusehen. Keine Raubkopien; Juzzio hostet nichts und synchronisiert nur den Link.'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7B5CFF),
                    disabledBackgroundColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: valid ? () => Navigator.pop(context, (url, _title.text.trim())) : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_app.trEn('Başlat ve davet et', 'Start and invite', 'Starten und einladen'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// v1.2.9: Sinema Parti tarayıcısında izin verilen gezinme (saf; test edilir).
/// Yalnız http/https; uygulama açma (intent:, market:), yerel dosya (file:, content:) ve
/// betik (javascript:, data:, blob: üst düzey) adresleri engellenir.
bool juzzioWatchNavigationAllowed(String url) {
  final u = url.trim().toLowerCase();
  if (u.isEmpty || u == 'about:blank') return true;
  return u.startsWith('https://') || u.startsWith('http://');
}
