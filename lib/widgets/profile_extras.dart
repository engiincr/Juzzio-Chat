// =============================================================================
// JUZZIO v0.3.0 — Profil ekstraları
//  • JuzzioVerifiedTick   : mavi tik
//  • JuzzioBadgeRow       : arama dakikasına göre kazanılan herkese açık rozetler
//  • JuzzioWebsiteChip    : herkese görünen web sitesi bağlantısı
//  • v0.7.0 Müzik: isimle arama + 30 sn resmi önizleme (YouTube/WebView yok)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';

class JuzzioVerifiedTick extends StatelessWidget {
  final double size;
  const JuzzioVerifiedTick({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: JuzzioAppController.instance.t('badge_verified'),
      child: Icon(Icons.verified_rounded, color: JuzzioColors.sky500, size: size),
    );
  }
}

/// Rozet kodu → (simge, renk, çeviri anahtarı)
class JuzzioBadgeStyle {
  final String emoji;
  final Color color;
  final String labelKey;
  final String descKey;
  const JuzzioBadgeStyle(this.emoji, this.color, this.labelKey, this.descKey);

  static const Map<String, JuzzioBadgeStyle> all = {
    'verified': JuzzioBadgeStyle('✔️', JuzzioColors.sky500, 'badge_verified', 'badge_verified_desc'),
    // v0.5 nötr cam: rozet rengini emoji taşır; çerçeve gümüş tonlarındadır
    'voice_chatter': JuzzioBadgeStyle('🎙️', JuzzioColors.slate300, 'badge_voice_chatter', 'badge_voice_chatter_desc'),
    'voice_storyteller': JuzzioBadgeStyle('📻', JuzzioColors.slate300, 'badge_voice_storyteller', 'badge_voice_storyteller_desc'),
    'voice_hafiz': JuzzioBadgeStyle('📿', JuzzioColors.slate300, 'badge_voice_hafiz', 'badge_voice_hafiz_desc'),
    'voice_legend': JuzzioBadgeStyle('👑', JuzzioColors.slate200, 'badge_voice_legend', 'badge_voice_legend_desc'),
    'video_rookie': JuzzioBadgeStyle('📸', JuzzioColors.slate300, 'badge_video_rookie', 'badge_video_rookie_desc'),
    'video_star': JuzzioBadgeStyle('🌟', JuzzioColors.slate200, 'badge_video_star', 'badge_video_star_desc'),
    'video_ninja': JuzzioBadgeStyle('🥷', JuzzioColors.slate300, 'badge_video_ninja', 'badge_video_ninja_desc'),
    'video_monster': JuzzioBadgeStyle('👾', JuzzioColors.slate300, 'badge_video_monster', 'badge_video_monster_desc'),
  };
}

class JuzzioBadgeRow extends StatefulWidget {
  final String userId;
  final bool isDark;
  final bool alignStart;
  const JuzzioBadgeRow({super.key, required this.userId, required this.isDark, this.alignStart = false});

  @override
  State<JuzzioBadgeRow> createState() => _JuzzioBadgeRowState();
}

class _JuzzioBadgeRowState extends State<JuzzioBadgeRow> {
  JuzzioBadgeInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JuzzioBadgeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    final info = await JuzzioFeaturesService.instance.fetchBadges(widget.userId);
    if (mounted) setState(() => _info = info);
  }

  void _showDetails(String code) {
    final app = JuzzioAppController.instance;
    final style = JuzzioBadgeStyle.all[code];
    if (style == null) return;
    final info = _info ?? const JuzzioBadgeInfo();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.isDark ? JuzzioColors.surface141519 : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(style.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                app.t(style.labelKey),
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: widget.isDark ? Colors.white : JuzzioColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                app.t(style.descKey),
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.isDark ? Colors.white70 : JuzzioColors.slate600, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text(
                app
                    .t('badge_minutes_summary')
                    .replaceAll('{voice}', '${info.voiceMinutes}')
                    .replaceAll('{video}', '${info.videoMinutes}'),
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: widget.isDark ? Colors.white60 : JuzzioColors.slate500,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final badges = (_info?.badges ?? const <String>[]).where((b) => b != 'verified').toList();
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: widget.alignStart ? WrapAlignment.start : WrapAlignment.center,
      children: [
        for (final code in badges)
          if (JuzzioBadgeStyle.all[code] != null)
            GestureDetector(
              onTap: () => _showDetails(code),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JuzzioBadgeStyle.all[code]!.color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JuzzioBadgeStyle.all[code]!.color.withOpacity(0.55)),
                ),
                child: Text(
                  '${JuzzioBadgeStyle.all[code]!.emoji} ${app.t(JuzzioBadgeStyle.all[code]!.labelKey)}',
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: widget.isDark ? Colors.white : JuzzioColors.ink,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class JuzzioWebsiteChip extends StatelessWidget {
  final String url;
  final bool isDark;
  const JuzzioWebsiteChip({super.key, required this.url, required this.isDark});

  String get _label {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
    final path = uri.path == '/' ? '' : uri.path;
    final out = '$host$path';
    return out.length > 40 ? '${out.substring(0, 39)}…' : out;
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(JuzzioAppController.instance.t('err_open_link'))),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_rounded, size: 16, color: JuzzioColors.blue500),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  color: JuzzioColors.blue500,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// v0.7.0 — MÜZİK: YouTube ve WebView tamamen kaldırıldı.
//  • Şarkı adını yaz → liste gelir → tek dokunuşla ekle (URL istenmez).
//  • Kaynak: Apple iTunes Search API'nin resmi 30 sn önizleme sesleri
//    (reklamsız, hızlı, anahtar gerektirmez). Ses uygulama içinde just_audio ile çalar.
//  • Profilde yalnızca oynat/durdur düğmesi; hikâyelerde müzik otomatik başlar.
// =============================================================================

/// Eski YouTube bağlantılarından kimlik (geriye dönük okuma; yeni kayıtlarda kullanılmaz).
String juzzioYoutubeId(String url) {
  final m = RegExp(r'(?:youtu\.be/|[?&]v=|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})').firstMatch(url);
  return m?.group(1) ?? '';
}

String juzzioYoutubeThumb(String videoId) =>
    videoId.isEmpty ? '' : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

/// Çalınabilir bir önizleme sesi mi? (YouTube bağlantıları artık çalınmaz)
bool juzzioIsPlayableMusic(String url) {
  final u = url.trim();
  return u.startsWith('https://') && juzzioYoutubeId(u).isEmpty;
}

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

/// Arama sonucundaki parça
class JuzzioTrack {
  final String title;
  final String artist;
  final String coverUrl;
  final String previewUrl;
  final int durationMs;

  const JuzzioTrack({
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.previewUrl,
    this.durationMs = 30000,
  });

  factory JuzzioTrack.fromItunes(Map<String, dynamic> m) {
    final art = (m['artworkUrl100'] ?? m['artworkUrl60'] ?? '').toString();
    return JuzzioTrack(
      title: (m['trackName'] ?? '').toString(),
      artist: (m['artistName'] ?? '').toString(),
      coverUrl: art.replaceAll('100x100bb', '300x300bb').replaceFirst('http://', 'https://'),
      previewUrl: (m['previewUrl'] ?? '').toString().replaceFirst('http://', 'https://'),
      durationMs: (m['trackTimeMillis'] as num?)?.toInt() ?? 30000,
    );
  }
}

class JuzzioMusicSearch {
  static final Map<String, List<JuzzioTrack>> _cache = {};

  static Future<List<JuzzioTrack>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const <JuzzioTrack>[];
    final lang = JuzzioAppController.instance.uiLang;
    final country = lang == 'de' ? 'DE' : (lang == 'en' ? 'US' : 'TR');
    final key = '$country|${q.toLowerCase()}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': q,
      'media': 'music',
      'entity': 'song',
      'limit': '30',
      'country': country,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw StateError('music_search_${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final list = <JuzzioTrack>[];
    if (body is Map && body['results'] is List) {
      for (final r in body['results'] as List) {
        if (r is! Map) continue;
        final t = JuzzioTrack.fromItunes(Map<String, dynamic>.from(r));
        if (t.previewUrl.startsWith('https://') && t.title.isNotEmpty) list.add(t);
      }
    }
    if (_cache.length > 40) _cache.clear();
    _cache[key] = list;
    return list;
  }
}

/// Uygulama genelinde tek önizleme oynatıcısı: aynı anda tek şarkı çalar.
class JuzzioMusicPlayer {
  JuzzioMusicPlayer._();
  static final JuzzioMusicPlayer instance = JuzzioMusicPlayer._();

  AudioPlayer? _player;
  /// Şu an çalan önizlemenin adresi (çalmıyorsa boş)
  final ValueNotifier<String> nowPlaying = ValueNotifier<String>('');
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  Future<void> toggle(String url, {bool loop = false}) async {
    if (nowPlaying.value == url) {
      await stop();
    } else {
      await play(url, loop: loop);
    }
  }

  Future<void> play(String url, {bool loop = false}) async {
    if (!juzzioIsPlayableMusic(url)) return;
    try {
      final p = _player ??= AudioPlayer();
      nowPlaying.value = url;
      loading.value = true;
      await p.stop();
      await p.setUrl(url);
      await p.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      loading.value = false;
      p.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed).then((_) {
        if (nowPlaying.value == url && !loop) nowPlaying.value = '';
      }).catchError((_) {});
      await p.play();
    } catch (_) {
      loading.value = false;
      if (nowPlaying.value == url) nowPlaying.value = '';
    }
  }

  Future<void> stop() async {
    nowPlaying.value = '';
    loading.value = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

/// Profilde biyografinin altında görünen müzik hapı: dokun → çal, tekrar dokun → durdur.
/// Hiçbir pencere veya web sayfası açılmaz.
class JuzzioMusicPill extends StatelessWidget {
  /// Geriye dönük uyumluluk (kullanılmaz)
  final String videoId;
  final int startSec;
  final String title;
  final String artist;
  final String coverUrl;
  final String musicUrl;
  final bool isDark;
  final double maxWidth;
  final bool playing;
  /// false → yalnızca gösterge (hikâyede müzik zaten otomatik çalar)
  final bool interactive;

  const JuzzioMusicPill({
    super.key,
    this.interactive = true,
    this.videoId = '',
    this.startSec = 0,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.musicUrl,
    required this.isDark,
    this.maxWidth = 260,
    this.playing = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = [
      if (title.trim().isNotEmpty) title.trim() else JuzzioAppController.instance.t('profile_music_title'),
      if (artist.trim().isNotEmpty) artist.trim(),
    ].join(' · ');
    final player = JuzzioMusicPlayer.instance;
    final playable = interactive && juzzioIsPlayableMusic(musicUrl);
    return ValueListenableBuilder<String>(
      valueListenable: player.nowPlaying,
      builder: (context, now, _) {
        final isPlaying = playing || (playable && now == musicUrl);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: JuzzioGlassMusicCapsule(
                coverUrl: coverUrl,
                label: label,
                playing: isPlaying,
                maxWidth: maxWidth - 46,
                onTap: playable ? () => player.toggle(musicUrl) : null,
              ),
            ),
            if (playable) ...[
              const SizedBox(width: 6),
              _PlayStopButton(
                playing: isPlaying,
                onTap: () {
                  HapticFeedback.selectionClick();
                  player.toggle(musicUrl);
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PlayStopButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  final double size;

  const _PlayStopButton({required this.playing, required this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    final bg = isDark ? Colors.white : JuzzioColors.ink;
    final fg = isDark ? JuzzioColors.ink : Colors.white;
    return Semantics(
      button: true,
      label: playing ? _l('Durdur', 'Stop', 'Stopp') : _l('Oynat', 'Play', 'Abspielen'),
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.7,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              color: fg,
              size: size * 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

/// Müzik seçici: şarkı adı yaz → liste → önizle (oynat/durdur) → tek dokunuşla ekle.
class JuzzioMusicPickerPage extends StatefulWidget {
  final String initialUrl;
  final int initialStartSec;
  final String initialTitle;
  final String initialArtist;
  /// true → profili güncellemez, seçimi [JuzzioMusicSelection] olarak döndürür
  /// (hikâye / gönderi müziği için).
  final bool selectOnly;

  const JuzzioMusicPickerPage({
    super.key,
    this.initialUrl = '',
    this.initialStartSec = 0,
    this.initialTitle = '',
    this.initialArtist = '',
    this.selectOnly = false,
  });

  /// Seçim modunda açar; kaldırıldıysa boş seçim (isEmpty) döner, vazgeçildiyse null.
  static Future<JuzzioMusicSelection?> pick(
    BuildContext context, {
    JuzzioMusicSelection? initial,
  }) async {
    final res = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => JuzzioMusicPickerPage(
          initialUrl: initial?.url ?? '',
          initialTitle: initial?.title ?? '',
          initialArtist: initial?.artist ?? '',
          selectOnly: true,
        ),
      ),
    );
    return res is JuzzioMusicSelection ? res : null;
  }

  @override
  State<JuzzioMusicPickerPage> createState() => _JuzzioMusicPickerPageState();
}

class _JuzzioMusicPickerPageState extends State<JuzzioMusicPickerPage> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<JuzzioTrack> _results = const [];
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _seq = 0;

  static const List<String> _suggestions = [
    'Tarkan', 'Sezen Aksu', 'Duman', 'Mor ve Ötesi', 'Sertab Erener', 'Manifest',
    'Dua Lipa', 'The Weeknd', 'Coldplay', 'Billie Eilish', 'Imagine Dragons', 'Taylor Swift',
  ];

  @override
  void initState() {
    super.initState();
    final seed = [widget.initialTitle, widget.initialArtist].where((e) => e.trim().isNotEmpty).join(' ');
    if (seed.isNotEmpty) {
      _query.text = seed;
      _run(seed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    JuzzioMusicPlayer.instance.stop();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v));
  }

  Future<void> _run(String q) async {
    final my = ++_seq;
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await JuzzioMusicSearch.search(q);
      if (!mounted || my != _seq) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || my != _seq) return;
      setState(() {
        _loading = false;
        _error = _l('Müzik araması şu an yapılamadı. İnternet bağlantını kontrol edip tekrar dene.',
            'Music search failed. Check your connection and try again.', 'Musiksuche fehlgeschlagen. Prüfe deine Verbindung.');
      });
    }
  }

  Future<void> _choose(JuzzioTrack? t) async {
    await JuzzioMusicPlayer.instance.stop();
    if (!mounted) return;
    final sel = t == null
        ? const JuzzioMusicSelection.empty()
        : JuzzioMusicSelection(url: t.previewUrl, startSec: 0, title: t.title, artist: t.artist, coverUrl: t.coverUrl);
    if (widget.selectOnly) {
      Navigator.of(context).pop(sel);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await JuzzioFeaturesService.instance.updateProfileMusic(
        musicUrl: sel.url,
        startSec: 0,
        title: sel.title,
        artist: sel.artist,
        coverUrl: sel.coverUrl,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    final hasCurrent = widget.initialUrl.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textPrimary,
        title: Text(_l('Müzik ekle', 'Add music', 'Musik hinzufügen'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
        actions: [
          if (hasCurrent)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: p.dangerRed),
              onPressed: _saving ? null : () => _choose(null),
              icon: const Icon(Icons.music_off_rounded, size: 18),
              label: Text(_l('Kaldır', 'Remove', 'Entfernen')),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: p.inputBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.glassBorder),
              ),
              child: TextField(
                controller: _query,
                autofocus: !hasCurrent,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _run,
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: _l('Şarkı veya sanatçı ara…', 'Search songs or artists…', 'Songs oder Künstler suchen…'),
                  hintStyle: TextStyle(color: p.textMuted),
                  prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: p.textMuted),
                          onPressed: () {
                            _query.clear();
                            _run('');
                          },
                        ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          if (_loading || _saving) LinearProgressIndicator(minHeight: 2, color: p.textPrimary, backgroundColor: Colors.transparent),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.dangerRed, fontWeight: FontWeight.w700)),
            ),
          Expanded(
            child: _query.text.trim().length < 2
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(_l('Önerilen aramalar', 'Suggested searches', 'Vorschläge'),
                          style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _suggestions)
                            ActionChip(
                              label: Text(s),
                              labelStyle: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                              backgroundColor: p.pillBg,
                              side: BorderSide(color: p.glassBorder),
                              shape: const StadiumBorder(),
                              onPressed: () {
                                _query.text = s;
                                _run(s);
                              },
                            ),
                        ],
                      ),
                    ],
                  )
                : (!_loading && _results.isEmpty && _error == null)
                    ? Center(
                        child: Text(_l('Sonuç bulunamadı', 'No results', 'Keine Ergebnisse'),
                            style: TextStyle(color: p.textSecondary)),
                      )
                    : ValueListenableBuilder<String>(
                        valueListenable: JuzzioMusicPlayer.instance.nowPlaying,
                        builder: (context, now, _) => ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                          itemBuilder: (context, i) {
                            final t = _results[i];
                            final isPlaying = now == t.previewUrl;
                            return Material(
                              color: isPlaying ? p.pillBg : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _saving ? null : () => _choose(t),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: t.coverUrl.isEmpty
                                            ? Container(width: 52, height: 52, color: p.pillBg, child: Icon(Icons.music_note_rounded, color: p.textMuted))
                                            : Image.network(t.coverUrl, width: 52, height: 52, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: p.pillBg)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(t.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14.5)),
                                            const SizedBox(height: 2),
                                            Text(t.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _PlayStopButton(
                                        size: 36,
                                        playing: isPlaying,
                                        onTap: () => JuzzioMusicPlayer.instance.toggle(t.previewUrl),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        tooltip: _l('Ekle', 'Add', 'Hinzufügen'),
                                        onPressed: _saving ? null : () => _choose(t),
                                        icon: Icon(Icons.add_circle_rounded, color: p.textPrimary, size: 28),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              _l('Önizlemeler Apple Music\'in herkese açık 30 saniyelik kesitleridir.',
                  'Previews are Apple Music\'s public 30-second clips.', 'Vorschauen sind öffentliche 30-Sekunden-Clips von Apple Music.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hikâye / gönderiye eklenen müzik seçimi.
class JuzzioMusicSelection {
  final String url;
  final int startSec;
  final String title;
  final String artist;
  final String coverUrl;

  const JuzzioMusicSelection({
    required this.url,
    required this.startSec,
    required this.title,
    required this.artist,
    required this.coverUrl,
  });

  const JuzzioMusicSelection.empty()
      : url = '',
        startSec = 0,
        title = '',
        artist = '',
        coverUrl = '';

  bool get isEmpty => !juzzioIsPlayableMusic(url);
  /// Geriye dönük uyumluluk
  String get videoId => juzzioYoutubeId(url);

  /// Veritabanında tek alanda tutulan başlık: "Şarkı · Sanatçı"
  String get displayTitle => [
        if (title.trim().isNotEmpty) title.trim(),
        if (artist.trim().isNotEmpty) artist.trim(),
      ].join(' · ');
}

/// Hikâye / gönderi açıkken müziği otomatik çalar ([playing] false → duraklatır).
/// Görünmez; WebView kullanılmaz.
class JuzzioBackgroundMusic extends StatefulWidget {
  final String musicUrl;
  final int startSec;
  final bool playing;

  const JuzzioBackgroundMusic({
    super.key,
    required this.musicUrl,
    this.startSec = 0,
    this.playing = true,
  });

  @override
  State<JuzzioBackgroundMusic> createState() => _JuzzioBackgroundMusicState();
}

class _JuzzioBackgroundMusicState extends State<JuzzioBackgroundMusic> {
  AudioPlayer? _player;
  String _loadedUrl = '';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant JuzzioBackgroundMusic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicUrl != widget.musicUrl || oldWidget.playing != widget.playing) _sync();
  }

  Future<void> _sync() async {
    final url = widget.musicUrl.trim();
    if (!juzzioIsPlayableMusic(url)) {
      _loadedUrl = '';
      try {
        await _player?.stop();
      } catch (_) {}
      return;
    }
    try {
      final p = _player ??= AudioPlayer();
      if (url != _loadedUrl) {
        _loadedUrl = url;
        // Profil önizlemesi çalıyorsa durdur: aynı anda tek ses
        await JuzzioMusicPlayer.instance.stop();
        await p.setUrl(url);
        await p.setLoopMode(LoopMode.one);
        if (widget.startSec > 0) await p.seek(Duration(seconds: widget.startSec.clamp(0, 25)));
      }
      if (!mounted || url != _loadedUrl) return;
      if (widget.playing) {
        await p.play();
      } else {
        await p.pause();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final p = _player;
    _player = null;
    if (p != null) {
      p.stop().whenComplete(p.dispose).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Kayan yazı (sığmayan şarkı adları yavaşça akar).
class JuzzioMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const JuzzioMarqueeText({super.key, required this.text, required this.style});

  @override
  State<JuzzioMarqueeText> createState() => _JuzzioMarqueeTextState();
}

class _JuzzioMarqueeTextState extends State<JuzzioMarqueeText> {
  final ScrollController _ctrl = ScrollController();
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  Future<void> _loop() async {
    while (_running && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!_running || !mounted || !_ctrl.hasClients) return;
      final max = _ctrl.position.maxScrollExtent;
      if (max <= 0) return;
      await _ctrl.animateTo(max, duration: Duration(milliseconds: (max * 28).round()), curve: Curves.linear);
      if (!_running || !mounted || !_ctrl.hasClients) return;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!_running || !mounted || !_ctrl.hasClients) return;
      _ctrl.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _running = false;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
    );
  }
}

/// v0.5.0 — Zarif cam müzik kapsülü (iOS "Şimdi Çalıyor" esintili):
/// buzlu cam zemin, dönen plak kapağı, canlı ekolayzer çubukları, kayan şarkı adı.
class JuzzioGlassMusicCapsule extends StatefulWidget {
  final String coverUrl;
  final String label;
  final bool playing;
  final double maxWidth;
  final VoidCallback? onTap;

  const JuzzioGlassMusicCapsule({
    super.key,
    required this.coverUrl,
    required this.label,
    this.playing = true,
    this.maxWidth = 240,
    this.onTap,
  });

  @override
  State<JuzzioGlassMusicCapsule> createState() => _JuzzioGlassMusicCapsuleState();
}

class _JuzzioGlassMusicCapsuleState extends State<JuzzioGlassMusicCapsule> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant JuzzioGlassMusicCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capsule = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            // v0.8.1: renk + gradyan aynı kutuda çizilmez; tonu gradyana karıştır
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: 0.16), Colors.black.withValues(alpha: 0.32)),
                Color.alphaBlend(Colors.white.withValues(alpha: 0.04), Colors.black.withValues(alpha: 0.32)),
              ],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _spin,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.2),
                  ),
                  child: ClipOval(
                    child: widget.coverUrl.isNotEmpty
                        ? Image.network(widget.coverUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const _MusicFallbackIcon())
                        : const _MusicFallbackIcon(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _EqBars(animate: widget.playing, listenable: _spin),
              const SizedBox(width: 7),
              Flexible(
                child: JuzzioMarqueeText(
                  text: widget.label.isNotEmpty ? widget.label : 'Juzzio Music',
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.onTap == null) return capsule;
    return GestureDetector(onTap: widget.onTap, child: capsule);
  }
}

/// Üç küçük ekolayzer çubuğu (çalarken dalgalanır)
class _EqBars extends AnimatedWidget {
  final bool animate;
  const _EqBars({required this.animate, required Animation<double> listenable}) : super(listenable: listenable);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value * 2 * math.pi * 6;
    double h(int i) => animate ? 5 + 7 * (0.5 + 0.5 * math.sin(t + i * 1.9)) : 6.0 + i * 2;
    return SizedBox(
      width: 14,
      height: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 3,
              height: h(i),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
            ),
        ],
      ),
    );
  }
}

class _MusicFallbackIcon extends StatelessWidget {
  const _MusicFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF3A3A3C),
      child: Icon(Icons.music_note_rounded, color: Colors.white, size: 15),
    );
  }
}

