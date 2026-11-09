// =============================================================================
// JUZZIO v0.9.5 — Watch Party (sohbette senkron film/video izleme)
//  • Doğrudan video (.mp4/.webm/.mov) ve canlı akış (.m3u8/HLS) uygulama içinde, herkeste
//    aynı saniyede oynar. Ev sahibi oynat/duraklat/sar yapar; diğerleri sunucu saatine göre
//    kendiliğinden eşitlenir (1,5 sn'den fazla kayma düzeltilir).
//  • Diğer site bağlantıları (film siteleri vb.) tarayıcıda açılır: telif/DRM ve site
//    kısıtlamaları nedeniyle başka sitenin oynatıcısı uygulamadan kontrol EDİLEMEZ; oturum
//    "ortak başlat" sayacı ile birlikte paylaşılır.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_time_sync.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_ui_kit.dart';

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
  });

  static JuzzioWatchSession fromMap(Map<String, dynamic> m) => JuzzioWatchSession(
        id: '${m['id']}',
        hostId: '${m['host_id']}',
        url: '${m['media_url']}',
        title: '${m['media_title'] ?? ''}',
        kind: '${m['source_kind'] ?? 'direct'}',
        playing: m['is_playing'] == true,
        positionMs: int.tryParse('${m['position_ms']}') ?? 0,
        rate: double.tryParse('${m['playback_rate']}') ?? 1.0,
        status: '${m['status']}',
        changedAt: DateTime.tryParse('${m['state_changed_at']}')?.toUtc() ?? DateTime.now().toUtc(),
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

class JuzzioWatchPartyScreen extends StatefulWidget {
  const JuzzioWatchPartyScreen({super.key, required this.roomId});
  final String roomId;

  static Future<void> open(BuildContext context, String roomId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioWatchPartyScreen(roomId: roomId)));

  @override
  State<JuzzioWatchPartyScreen> createState() => _JuzzioWatchPartyScreenState();
}

class _JuzzioWatchPartyScreenState extends State<JuzzioWatchPartyScreen> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  JuzzioWatchSession? _s;
  VideoPlayerController? _vc;
  String? _loadedUrl;
  Timer? _syncTimer;
  String? _error;
  bool _loading = true;

  bool get _isHost => _s != null && _s!.hostId == SupabaseService.instance.currentUserId;

  @override
  void initState() {
    super.initState();
    _sub = _db
        .from('watch_party_sessions')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .listen((rows) {
      final active = rows.where((r) => r['status'] == 'active').toList();
      final s = active.isEmpty ? null : JuzzioWatchSession.fromMap(active.last);
      if (!mounted) return;
      setState(() {
        _s = s;
        _loading = false;
      });
      unawaited(_applySession());
    }, onError: (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _correctDrift());
    unawaited(JuzzioTimeSync.instance.check());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncTimer?.cancel();
    _vc?.dispose();
    super.dispose();
  }

  Future<void> _applySession() async {
    final s = _s;
    if (s == null || s.kind == 'web') {
      await _vc?.dispose();
      _vc = null;
      _loadedUrl = null;
      if (mounted) setState(() {});
      return;
    }
    if (_loadedUrl != s.url) {
      await _vc?.dispose();
      final vc = VideoPlayerController.networkUrl(Uri.parse(s.url),
          formatHint: s.kind == 'hls' ? VideoFormat.hls : null);
      _vc = vc;
      _loadedUrl = s.url;
      try {
        await vc.initialize();
      } catch (_) {
        if (mounted) setState(() => _error = _app.trEn('Video açılamadı. Bağlantı doğrudan bir video/akış adresi olmalı.', 'Video could not be opened. The link must be a direct video/stream URL.', 'Video konnte nicht geöffnet werden.'));
        return;
      }
      if (mounted) setState(() {});
    }
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;
    await vc.setPlaybackSpeed(s.rate);
    await vc.seekTo(Duration(milliseconds: s.expectedPositionMs(JuzzioClock.nowUtc())));
    if (s.playing) {
      await vc.play();
    } else {
      await vc.pause();
    }
  }

  void _correctDrift() {
    final s = _s;
    final vc = _vc;
    if (s == null || vc == null || !vc.value.isInitialized || !s.playing) return;
    final want = s.expectedPositionMs(JuzzioClock.nowUtc());
    final have = vc.value.position.inMilliseconds;
    if ((want - have).abs() > 1500) vc.seekTo(Duration(milliseconds: want));
  }

  Future<void> _control({bool? playing, int? positionMs, double? rate}) async {
    final s = _s;
    if (s == null || !_isHost) return;
    final pos = positionMs ?? _vc?.value.position.inMilliseconds ?? s.expectedPositionMs(JuzzioClock.nowUtc());
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

  Future<void> _start() async {
    final url = TextEditingController();
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('İzleme partisi başlat', 'Start a watch party', 'Watch-Party starten')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: _app.trEn('Video bağlantısı (https://…)', 'Video link (https://…)', 'Videolink (https://…)')),
          ),
          TextField(controller: title, maxLength: 150, decoration: InputDecoration(labelText: _app.trEn('Başlık', 'Title', 'Titel'))),
          Text(
            _app.trEn('.mp4 / .m3u8 gibi doğrudan bağlantılar uygulamada senkron oynar. Diğer siteler tarayıcıda açılır.',
                'Direct links like .mp4 / .m3u8 play in sync in the app. Other sites open in the browser.', 'Direkte Links spielen synchron.'),
            style: const TextStyle(fontSize: 12),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_app.trEn('Başlat', 'Start', 'Starten'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('start_watch_party', params: {'p_room': widget.roomId, 'p_url': url.text.trim(), 'p_title': title.text.trim()});
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

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final vc = _vc;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(s?.title.isNotEmpty == true ? s!.title : _app.trEn('İzleme partisi', 'Watch party', 'Watch-Party')),
        actions: [
          if (s != null && _isHost) IconButton(tooltip: _app.trEn('Bitir', 'End', 'Beenden'), onPressed: _end, icon: const Icon(Icons.stop_circle_outlined)),
        ],
      ),
      body: _loading
          ? const JuzzioListSkeleton()
          : s == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.movie_filter_rounded, color: Colors.white70, size: 56),
                      const SizedBox(height: 12),
                      Text(_app.trEn('Bu sohbette şu an izleme partisi yok.', 'No watch party in this chat right now.', 'Gerade keine Watch-Party.'),
                          style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow_rounded), label: Text(_app.trEn('Başlat', 'Start', 'Starten'))),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                    ]),
                  ),
                )
              : s.kind == 'web'
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.public_rounded, color: Colors.white70, size: 52),
                          const SizedBox(height: 10),
                          Text(
                            _app.trEn('Bu bağlantı bir web sitesi. Site kendi oynatıcısını kullandığı için uygulama içinde senkron oynatılamaz; herkes aynı anda "Aç"a basarak birlikte izleyebilir.',
                                'This link is a website with its own player, so it cannot be synced in the app; everyone can tap "Open" together.',
                                'Webseite mit eigenem Player — bitte gemeinsam öffnen.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: Text(_app.trEn('Tarayıcıda aç', 'Open in browser', 'Im Browser öffnen')),
                          ),
                        ]),
                      ),
                    )
                  : Column(children: [
                      Expanded(
                        child: Center(
                          child: vc != null && vc.value.isInitialized
                              ? AspectRatio(aspectRatio: vc.value.aspectRatio == 0 ? 16 / 9 : vc.value.aspectRatio, child: VideoPlayer(vc))
                              : _error != null
                                  ? Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center)
                                  : const CircularProgressIndicator(),
                        ),
                      ),
                      if (vc != null && vc.value.isInitialized)
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: vc,
                          builder: (_, v, __) => Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                            child: Column(children: [
                              Slider(
                                value: v.position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
                                max: v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds.toDouble(),
                                onChanged: _isHost ? (x) => vc.seekTo(Duration(milliseconds: x.round())) : null,
                                onChangeEnd: _isHost ? (x) => _control(positionMs: x.round()) : null,
                              ),
                              Row(children: [
                                Text('${_fmt(v.position)} / ${_fmt(v.duration)}', style: const TextStyle(color: Colors.white70)),
                                const Spacer(),
                                if (_isHost) ...[
                                  IconButton(
                                    color: Colors.white,
                                    icon: const Icon(Icons.replay_10_rounded),
                                    onPressed: () => _control(positionMs: (v.position.inMilliseconds - 10000).clamp(0, 1 << 31)),
                                  ),
                                  IconButton(
                                    color: Colors.white,
                                    iconSize: 40,
                                    icon: Icon(s.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                                    onPressed: () => _control(playing: !s.playing),
                                  ),
                                  IconButton(
                                    color: Colors.white,
                                    icon: const Icon(Icons.forward_10_rounded),
                                    onPressed: () => _control(positionMs: v.position.inMilliseconds + 10000),
                                  ),
                                ] else
                                  Text(_app.trEn('Ev sahibi kontrol ediyor · senkron', 'Host controls · in sync', 'Host steuert · synchron'),
                                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ]),
                            ]),
                          ),
                        ),
                    ]),
    );
  }
}
