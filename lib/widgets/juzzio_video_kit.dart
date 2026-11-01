// =============================================================================
// JUZZIO v0.4.0 — Medya kiti
//  • JuzzioMediaFilters   : gönderi / hikâye renk filtreleri (önizleme ve
//                           izleme ekranlarında aynı sonuç)
//  • JuzzioOverlayText    : hikâye yazı stilleri (Klasik, Vurgu, Neon, Daktilo, Çizgi)
//  • JuzzioVideoTrimmerPage: Instagram tarzı video kırpıcı — önizleme, kare şeridi,
//                           sürüklenebilir başlangıç/bitiş tutamakları, hız, ses, kapak
//  • JuzzioInlineVideo    : akışta kırpma/hız bilgisine uyan satır içi oynatıcı
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme/juzzio_colors.dart';
import 'media_viewer.dart';
import 'profile_extras.dart';

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

String juzzioFormatClock(int ms) {
  final totalSec = (ms / 1000).floor();
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String juzzioFormatSeconds(int ms) {
  final sec = ms / 1000;
  return sec >= 10 ? '${sec.round()} sn' : '${sec.toStringAsFixed(1)} sn';
}

// -----------------------------------------------------------------------------
// FİLTRELER
// -----------------------------------------------------------------------------
class JuzzioFilterPreset {
  final String id;
  final String tr;
  final String en;
  final String de;
  const JuzzioFilterPreset(this.id, this.tr, this.en, this.de);
  String get label => _l(tr, en, de);
}

class JuzzioMediaFilters {
  JuzzioMediaFilters._();

  static const List<JuzzioFilterPreset> presets = [
    JuzzioFilterPreset('none', 'Normal', 'Normal', 'Normal'),
    JuzzioFilterPreset('vivid', 'Canlı', 'Vivid', 'Lebendig'),
    JuzzioFilterPreset('warm', 'Sıcak', 'Warm', 'Warm'),
    JuzzioFilterPreset('cool', 'Serin', 'Cool', 'Kühl'),
    JuzzioFilterPreset('vintage', 'Vintage', 'Vintage', 'Vintage'),
    JuzzioFilterPreset('fade', 'Soluk', 'Fade', 'Verblasst'),
    JuzzioFilterPreset('mono', 'S/B', 'B&W', 'S/W'),
    JuzzioFilterPreset('noir', 'Noir', 'Noir', 'Noir'),
  ];

  static String labelFor(String id) {
    for (final p in presets) {
      if (p.id == id) return p.label;
    }
    return presets.first.label;
  }

  // 4x5 renk matrislerini 5x5 olarak çarpar (b uygulanır, sonra a)
  static List<double> _compose(List<double> a, List<double> b) {
    double at(List<double> m, int r, int c) {
      if (r == 4) return c == 4 ? 1 : 0;
      return m[r * 5 + c];
    }

    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = 0.0;
        for (var k = 0; k < 5; k++) {
          sum += at(a, r, k) * at(b, k, c);
        }
        out[r * 5 + c] = sum;
      }
    }
    return out;
  }

  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return [
      sr + s, sg, sb, 0, 0,
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _contrast(double c, {double lift = 0}) {
    final t = (1 - c) * 127.5 + lift;
    return [
      c, 0, 0, 0, t,
      0, c, 0, 0, t,
      0, 0, c, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _scale(double r, double g, double b, {double or = 0, double og = 0, double ob = 0}) => [
        r, 0, 0, 0, or,
        0, g, 0, 0, og,
        0, 0, b, 0, ob,
        0, 0, 0, 1, 0,
      ];

  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static final Map<String, List<double>> _cache = {};

  static List<double>? matrixFor(String id) {
    if (id == 'none' || id.isEmpty) return null;
    final cached = _cache[id];
    if (cached != null) return cached;
    List<double>? m;
    switch (id) {
      case 'vivid':
        m = _compose(_contrast(1.08), _saturation(1.38));
        break;
      case 'warm':
        m = _compose(_scale(1.07, 1.01, 0.88, or: 12, og: 4), _saturation(1.1));
        break;
      case 'cool':
        m = _compose(_scale(0.92, 1.0, 1.1, og: 2, ob: 14), _saturation(0.95));
        break;
      case 'vintage':
        final sep = _sepia;
        final ident = _saturation(1);
        final blended = List<double>.generate(20, (i) => ident[i] * 0.45 + sep[i] * 0.55);
        m = _compose(_contrast(0.92, lift: 10), blended);
        break;
      case 'fade':
        m = _compose(_contrast(0.82, lift: 18), _saturation(0.78));
        break;
      case 'mono':
        m = _saturation(0);
        break;
      case 'noir':
        m = _compose(_contrast(1.35, lift: -12), _saturation(0));
        break;
      default:
        m = null;
    }
    if (m != null) _cache[id] = m;
    return m;
  }

  static ColorFilter? colorFilter(String id) {
    final m = matrixFor(id);
    return m == null ? null : ColorFilter.matrix(m);
  }

  static Widget apply(String id, Widget child) {
    final f = colorFilter(id);
    if (f == null) return child;
    return ColorFiltered(colorFilter: f, child: child);
  }
}

// -----------------------------------------------------------------------------
// HİKÂYE YAZI STİLLERİ
// -----------------------------------------------------------------------------
class JuzzioOverlayStyles {
  JuzzioOverlayStyles._();

  static const List<String> ids = ['classic', 'bold', 'neon', 'typewriter', 'outline'];

  static String label(String id) {
    switch (id) {
      case 'bold':
        return _l('Vurgu', 'Strong', 'Stark');
      case 'neon':
        return 'Neon';
      case 'typewriter':
        return _l('Daktilo', 'Typewriter', 'Schreibmaschine');
      case 'outline':
        return _l('Çizgi', 'Outline', 'Kontur');
      default:
        return _l('Klasik', 'Classic', 'Klassisch');
    }
  }

  static const List<String> palette = [
    '#FFFFFF',
    '#111111',
    '#FF3B5C',
    '#64D2FF',
    '#FFD60A',
    '#30D158',
    '#0A84FF',
    '#BF5AF2',
    '#FF6AC1',
  ];

  static Color parse(String hex, {Color fallback = Colors.white}) {
    var clean = hex.replaceAll('#', '').trim().toUpperCase();
    // Eski turuncu yazı rengi artık açık cam mavisi olarak çizilir
    if (clean == 'FF9F0A' || clean == 'FFFF9F0A') clean = '64D2FF';
    final v = int.tryParse(clean.length == 6 ? 'FF$clean' : clean, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

/// v0.7.0: Hikâye yazısı boyutu ve kenar boşluğu, tuval/ekran GENİŞLİĞİNE oranlıdır.
/// Düzenleyicide ve izleyicide aynı oran kullanıldığı için paylaşılan yazı, ekranda
/// görüldüğü punto ve satır kırılımıyla görünür.
const double kJuzzioStoryTextSizeRatio = 0.072;
const double kJuzzioStoryTextPadRatio = 0.064;

class JuzzioOverlayText extends StatelessWidget {
  final String text;
  final String styleId;
  final String colorHex;
  final double fontSize;
  final String? secondaryText;

  const JuzzioOverlayText({
    super.key,
    required this.text,
    this.styleId = 'classic',
    this.colorHex = '#FFFFFF',
    this.fontSize = 26,
    this.secondaryText,
  });

  @override
  Widget build(BuildContext context) {
    final color = JuzzioOverlayStyles.parse(colorHex);
    final isLight = color.computeLuminance() > 0.55;
    final secondary = (secondaryText ?? '').trim();
    Widget main;
    switch (styleId) {
      case 'bold':
        main = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: isLight ? Colors.black : Colors.white,
              fontSize: fontSize * 0.92,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
        );
        break;
      case 'neon':
        main = Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1.2,
            shadows: [
              Shadow(color: color, blurRadius: 6),
              Shadow(color: color, blurRadius: 16),
              Shadow(color: color.withOpacity(0.9), blurRadius: 30),
            ],
          ),
        );
        break;
      case 'typewriter':
        main = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: isLight ? Colors.black.withOpacity(0.55) : Colors.white.withOpacity(0.85),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              color: color,
              fontSize: fontSize * 0.78,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              height: 1.3,
            ),
          ),
        );
        break;
      case 'outline':
        main = Stack(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.2,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4
                  ..color = isLight ? Colors.black : Colors.white,
              ),
            ),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ],
        );
        break;
      default:
        main = Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1.2,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2))],
          ),
        );
    }
    if (secondary.isEmpty || secondary == text.trim()) return main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        main,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '🌐 $secondary',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// VİDEO KIRPICI
// -----------------------------------------------------------------------------
class JuzzioTrimSelection {
  final int startMs;
  final int endMs;
  final int durationMs;
  final double speed;
  final bool muted;
  final String? coverPath;
  final List<String> thumbnails;

  const JuzzioTrimSelection({
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    this.speed = 1.0,
    this.muted = false,
    this.coverPath,
    this.thumbnails = const [],
  });

  int get lengthMs => (endMs - startMs).clamp(0, 1 << 30);

  /// Hız uygulanmış gerçek izlenme süresi
  int get playbackLengthMs => speed <= 0 ? lengthMs : (lengthMs / speed).round();
}

class JuzzioVideoTrimmerPage extends StatefulWidget {
  final File file;
  final int maxDurationMs;
  final int minDurationMs;
  final int initialStartMs;
  final int initialEndMs;
  final double initialSpeed;
  final bool initialMuted;
  final bool showSpeed;
  final bool showCover;
  final String? title;

  const JuzzioVideoTrimmerPage({
    super.key,
    required this.file,
    this.maxDurationMs = 60000,
    this.minDurationMs = 1000,
    this.initialStartMs = 0,
    this.initialEndMs = 0,
    this.initialSpeed = 1.0,
    this.initialMuted = false,
    this.showSpeed = true,
    this.showCover = true,
    this.title,
  });

  static Future<JuzzioTrimSelection?> open(
    BuildContext context, {
    required File file,
    int maxDurationMs = 60000,
    int initialStartMs = 0,
    int initialEndMs = 0,
    double initialSpeed = 1.0,
    bool initialMuted = false,
    bool showSpeed = true,
    bool showCover = true,
    String? title,
  }) {
    return Navigator.of(context).push<JuzzioTrimSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JuzzioVideoTrimmerPage(
          file: file,
          maxDurationMs: maxDurationMs,
          initialStartMs: initialStartMs,
          initialEndMs: initialEndMs,
          initialSpeed: initialSpeed,
          initialMuted: initialMuted,
          showSpeed: showSpeed,
          showCover: showCover,
          title: title,
        ),
      ),
    );
  }

  @override
  State<JuzzioVideoTrimmerPage> createState() => _JuzzioVideoTrimmerPageState();
}

class _JuzzioVideoTrimmerPageState extends State<JuzzioVideoTrimmerPage> {
  static const double _handleW = 16;
  static const int _thumbCount = 10;
  static const List<double> _speeds = [0.5, 1.0, 1.5, 2.0];

  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _ready = false;
  bool _failed = false;
  bool _finishing = false;
  int _durationMs = 0;
  int _startMs = 0;
  int _endMs = 0;
  int _positionMs = 0;
  int _coverMs = 0;
  late double _speed = widget.initialSpeed;
  late bool _muted = widget.initialMuted;
  List<String> _thumbs = const [];
  Timer? _ticker;
  bool _dragging = false;

  int get _minLen {
    final m = widget.minDurationMs.clamp(300, 5000);
    return _durationMs > 0 && m > _durationMs ? _durationMs : m;
  }
  int get _maxLen => widget.maxDurationMs <= 0 ? (_durationMs > 0 ? _durationMs : 60000) : widget.maxDurationMs;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _c.initialize();
      final dur = _c.value.duration.inMilliseconds;
      if (dur <= 0) throw StateError('duration');
      _durationMs = dur;
      _startMs = widget.initialStartMs.clamp(0, dur);
      final desiredEnd = widget.initialEndMs > _startMs ? widget.initialEndMs : dur;
      _endMs = desiredEnd.clamp(_startMs, dur);
      if (_endMs - _startMs > _maxLen) _endMs = _startMs + _maxLen;
      if (_endMs - _startMs < _minLen) {
        _endMs = (_startMs + _minLen).clamp(0, dur);
        if (_endMs - _startMs < _minLen) _startMs = (_endMs - _minLen).clamp(0, dur);
      }
      _coverMs = _startMs;
      await _c.setLooping(false);
      await _c.setVolume(_muted ? 0 : 1);
      if ((_speed - 1).abs() > 0.01) {
        try {
          await _c.setPlaybackSpeed(_speed);
        } catch (_) {}
      }
      await _c.seekTo(Duration(milliseconds: _startMs));
      await _c.play();
      if (!mounted) return;
      setState(() => _ready = true);
      _ticker = Timer.periodic(const Duration(milliseconds: 60), (_) => _tick());
      _loadThumbs();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadThumbs() async {
    final times = List<int>.generate(_thumbCount, (i) => ((_durationMs * (i + 0.5)) / _thumbCount).round());
    final res = await JuzzioNative.videoFrames(widget.file.path, timesMs: times, maxWidth: 180);
    if (!mounted) return;
    setState(() => _thumbs = res.paths);
  }

  Future<void> _tick() async {
    if (!_ready || _dragging || !mounted) return;
    final pos = (await _c.position)?.inMilliseconds ?? _c.value.position.inMilliseconds;
    if (!mounted) return;
    if (pos >= _endMs || pos < _startMs - 250) {
      await _c.seekTo(Duration(milliseconds: _startMs));
      if (!_c.value.isPlaying) await _c.play();
      if (mounted) setState(() => _positionMs = _startMs);
      return;
    }
    setState(() => _positionMs = pos);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onDragStart() {
    _dragging = true;
    _c.pause();
  }

  Future<void> _onDragEnd({int? seekTo}) async {
    _dragging = false;
    final target = seekTo ?? _startMs;
    await _c.seekTo(Duration(milliseconds: target));
    await _c.play();
    if (mounted) setState(() => _positionMs = target);
  }

  void _moveStart(double dxPx, double trackW) {
    final delta = (dxPx / trackW * _durationMs).round();
    var ns = (_startMs + delta).clamp(0, _endMs - _minLen);
    if (_endMs - ns > _maxLen) ns = _endMs - _maxLen;
    if (ns != _startMs) {
      setState(() => _startMs = ns);
      _c.seekTo(Duration(milliseconds: ns));
      HapticFeedback.selectionClick();
    }
  }

  void _moveEnd(double dxPx, double trackW) {
    final delta = (dxPx / trackW * _durationMs).round();
    var ne = (_endMs + delta).clamp(_startMs + _minLen, _durationMs);
    if (ne - _startMs > _maxLen) ne = _startMs + _maxLen;
    if (ne != _endMs) {
      setState(() => _endMs = ne);
      _c.seekTo(Duration(milliseconds: ne));
      HapticFeedback.selectionClick();
    }
  }

  void _moveWindow(double dxPx, double trackW) {
    final delta = (dxPx / trackW * _durationMs).round();
    final len = _endMs - _startMs;
    final ns = (_startMs + delta).clamp(0, _durationMs - len);
    if (ns != _startMs) {
      setState(() {
        _startMs = ns;
        _endMs = ns + len;
      });
      _c.seekTo(Duration(milliseconds: ns));
    }
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    try {
      await _c.setPlaybackSpeed(s);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _c.setVolume(_muted ? 0 : 1);
  }

  Future<void> _togglePlay() async {
    if (_c.value.isPlaying) {
      await _c.pause();
    } else {
      await _c.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _c.pause();
    String? cover;
    if (widget.showCover) {
      final coverAt = _coverMs.clamp(_startMs, _endMs);
      final res = await JuzzioNative.videoFrames(
        widget.file.path,
        timesMs: [coverAt],
        maxWidth: 1080,
        quality: 88,
      );
      if (res.paths.isNotEmpty) cover = res.paths.first;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      JuzzioTrimSelection(
        startMs: _startMs,
        endMs: _endMs,
        durationMs: _durationMs,
        speed: _speed,
        muted: _muted,
        coverPath: cover,
        thumbnails: _thumbs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lenMs = _endMs - _startMs;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  ),
                  Expanded(
                    child: Text(
                      widget.title ?? _l('Videoyu kırp', 'Trim video', 'Video zuschneiden'),
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: JuzzioColors.blue500,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: _ready && !_finishing ? _finish : null,
                    child: _finishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_l('Bitti', 'Done', 'Fertig'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _failed
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(
                          _l('Bu video açılamadı. Başka bir video deneyin.', 'This video could not be opened. Try another one.',
                              'Dieses Video konnte nicht geöffnet werden. Versuche ein anderes.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ),
                    )
                  : !_ready
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : GestureDetector(
                          onTap: _togglePlay,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: AspectRatio(
                                    aspectRatio: _c.value.aspectRatio > 0 ? _c.value.aspectRatio : 9 / 16,
                                    child: VideoPlayer(_c),
                                  ),
                                ),
                              ),
                              if (!_c.value.isPlaying)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                                ),
                              Positioned(
                                top: 12,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: _glassChip(
                                    '${juzzioFormatSeconds(lenMs)} · ${juzzioFormatClock(_startMs)} – ${juzzioFormatClock(_endMs)}',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            if (_ready) ...[
              const SizedBox(height: 12),
              _buildTimeline(),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _roundIcon(
                      _c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      _togglePlay,
                    ),
                    const SizedBox(width: 8),
                    _roundIcon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      _toggleMute,
                      active: _muted,
                    ),
                    const Spacer(),
                    if (widget.showSpeed)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final sp in _speeds)
                              GestureDetector(
                                onTap: () => _setSpeed(sp),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: (_speed - sp).abs() < 0.01 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${sp == sp.roundToDouble() ? sp.toStringAsFixed(0) : sp.toString()}x',
                                    style: TextStyle(
                                      color: (_speed - sp).abs() < 0.01 ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.showCover && _thumbs.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildCoverPicker(),
              ],
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _glassChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: active ? Colors.black : Colors.white, size: 22),
      ),
    );
  }

  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          final fullW = box.maxWidth;
          final trackW = (fullW - _handleW * 2).clamp(40.0, 4000.0);
          double xFor(int ms) => _handleW + (ms / _durationMs) * trackW;
          final left = xFor(_startMs);
          final right = xFor(_endMs);
          final playX = xFor(_positionMs.clamp(_startMs, _endMs));
          const h = 58.0;
          return SizedBox(
            height: h + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Kare şeridi
                Positioned(
                  left: _handleW,
                  right: _handleW,
                  top: 4,
                  height: h,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _thumbs.isEmpty
                        ? Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [JuzzioColors.surface1E2029, JuzzioColors.slate700, JuzzioColors.surface1E2029],
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              for (final t in _thumbs)
                                Expanded(
                                  child: Image.file(
                                    File(t),
                                    fit: BoxFit.cover,
                                    height: h,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => const ColoredBox(color: JuzzioColors.slate800),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                // Seçim dışını karart
                Positioned(
                  left: _handleW,
                  width: (left - _handleW).clamp(0.0, fullW),
                  top: 4,
                  height: h,
                  child: Container(color: Colors.black.withOpacity(0.62)),
                ),
                Positioned(
                  left: right,
                  width: (fullW - _handleW - right).clamp(0.0, fullW),
                  top: 4,
                  height: h,
                  child: Container(color: Colors.black.withOpacity(0.62)),
                ),
                // Seçili pencere (sürükleyerek kaydır)
                Positioned(
                  left: left,
                  width: (right - left).clamp(0.0, fullW),
                  top: 0,
                  height: h + 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) => _onDragStart(),
                    onHorizontalDragUpdate: (d) => _moveWindow(d.delta.dx, trackW),
                    onHorizontalDragEnd: (_) => _onDragEnd(),
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: Colors.white, width: 3.5),
                        ),
                      ),
                    ),
                  ),
                ),
                // Oynatma çizgisi
                Positioned(
                  left: playX - 1.5,
                  top: 0,
                  height: h + 8,
                  child: IgnorePointer(
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
                // Sol tutamak
                Positioned(
                  left: left - _handleW,
                  top: 0,
                  width: _handleW + 10,
                  height: h + 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _onDragStart(),
                    onHorizontalDragUpdate: (d) => _moveStart(d.delta.dx, trackW),
                    onHorizontalDragEnd: (_) => _onDragEnd(),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _handle(isLeft: true, height: h + 8),
                    ),
                  ),
                ),
                // Sağ tutamak
                Positioned(
                  left: right - 10,
                  top: 0,
                  width: _handleW + 10,
                  height: h + 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _onDragStart(),
                    onHorizontalDragUpdate: (d) => _moveEnd(d.delta.dx, trackW),
                    onHorizontalDragEnd: (_) => _onDragEnd(seekTo: (_endMs - 1500).clamp(_startMs, _endMs)),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _handle(isLeft: false, height: h + 8),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _handle({required bool isLeft, required double height}) {
    return Container(
      width: _handleW,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isLeft ? 10 : 0),
          right: Radius.circular(isLeft ? 0 : 10),
        ),
      ),
      child: Icon(
        isLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        color: Colors.black,
        size: 18,
      ),
    );
  }

  Widget _buildCoverPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            _l('Kapak seç', 'Choose cover', 'Cover wählen'),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _thumbs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final ms = ((_durationMs * (i + 0.5)) / _thumbCount).round();
              final inRange = ms >= _startMs && ms <= _endMs;
              final selected = (_coverMs - ms).abs() < (_durationMs / _thumbCount / 2);
              return GestureDetector(
                onTap: inRange
                    ? () {
                        setState(() => _coverMs = ms);
                        _c.seekTo(Duration(milliseconds: ms));
                      }
                    : null,
                child: Opacity(
                  opacity: inRange ? 1 : 0.35,
                  child: Container(
                    width: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(_thumbs[i]), fit: BoxFit.cover),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// AKIŞ İÇİ VİDEO
// -----------------------------------------------------------------------------
class JuzzioInlineVideo extends StatefulWidget {
  final String source; // https://... veya yerel dosya yolu
  final String? coverUrl;
  final int trimStartMs;
  final int trimEndMs;
  final double speed;
  final bool startMuted;
  final String filterPreset;
  final BoxFit fit;
  final bool showBadge;
  final String badgeLabel;
  final String musicUrl;
  final int musicStartSec;

  const JuzzioInlineVideo({
    super.key,
    required this.source,
    this.coverUrl,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.speed = 1.0,
    this.startMuted = true,
    this.filterPreset = 'none',
    this.fit = BoxFit.cover,
    this.showBadge = true,
    this.badgeLabel = 'Video',
    this.musicUrl = '',
    this.musicStartSec = 0,
  });

  @override
  State<JuzzioInlineVideo> createState() => _JuzzioInlineVideoState();
}

class _JuzzioInlineVideoState extends State<JuzzioInlineVideo> {
  JuzzioVideoController? _video;
  bool _loading = false;
  bool _failed = false;

  bool get _isRemote => widget.source.startsWith('http');

  bool get _hasImageCover {
    final c = widget.coverUrl ?? '';
    if (c.isEmpty || c == widget.source) return false;
    final clean = c.split('?').first.toLowerCase();
    return !(clean.endsWith('.mp4') || clean.endsWith('.mov') || clean.endsWith('.webm') || clean.endsWith('.mkv'));
  }

  @override
  void didUpdateWidget(covariant JuzzioInlineVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _video?.dispose();
      _video = null;
      _failed = false;
    }
  }

  Future<void> _start() async {
    if (_loading) return;
    final existing = _video;
    if (existing != null && existing.isInitialized) {
      setState(() => existing.isPlaying ? existing.pause() : existing.play());
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final ctrl = _isRemote
        ? JuzzioVideoController(
            widget.source,
            trimStartMs: widget.trimStartMs,
            trimEndMs: widget.trimEndMs,
            speed: widget.speed,
            muted: widget.startMuted,
          )
        : JuzzioVideoController.file(
            File(widget.source),
            trimStartMs: widget.trimStartMs,
            trimEndMs: widget.trimEndMs,
            speed: widget.speed,
            muted: widget.startMuted,
          );
    await ctrl.initialize(loop: true);
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    if (ctrl.hasError) {
      ctrl.dispose();
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    ctrl.play();
    setState(() {
      _video = ctrl;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _video;
    final JuzzioVideoController? video = (candidate != null && candidate.isInitialized) ? candidate : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _start,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null && widget.musicUrl.isNotEmpty)
            Positioned(
              left: 0,
              bottom: 0,
              child: JuzzioBackgroundMusic(
                musicUrl: widget.musicUrl,
                startSec: widget.musicStartSec,
                playing: video.isPlaying,
              ),
            ),
          const ColoredBox(color: Colors.black),
          if (video != null)
            JuzzioMediaFilters.apply(widget.filterPreset, video.buildView(fit: widget.fit))
          else if (_hasImageCover)
            JuzzioMediaFilters.apply(
              widget.filterPreset,
              Image.network(
                widget.coverUrl!,
                fit: widget.fit,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (video == null)
            Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)
                  : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Icon(
                        _failed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
            ),
          if (video != null && !video.isPlaying)
            const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 64)),
          if (video != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: GestureDetector(
                onTap: () => setState(video.toggleMute),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    video.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          if (widget.showBadge)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.62),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      widget.badgeLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    if ((widget.speed - 1).abs() > 0.01) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${widget.speed}x',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
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
}
