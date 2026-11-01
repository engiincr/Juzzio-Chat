// =============================================================================
// JUZZIO v0.2.0 — Ortak medya bileşenleri
//  • JuzzioVideoController: hikâye ve sohbet videolarını gerçekten oynatır
//    (eski sürümde video hikâyeler yalnızca "oynatılıyor" yazısı gösteriyordu).
//  • JuzzioMediaViewerPage: sohbet fotoğraf/videolarını tam ekran açar.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class JuzzioVideoController {
  JuzzioVideoController(
    String url, {
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.speed = 1.0,
    bool muted = false,
  })  : _controller = VideoPlayerController.networkUrl(Uri.parse(url)),
        isMuted = muted;

  /// Yerel dosya (oluşturma ekranlarındaki önizleme) için.
  JuzzioVideoController.file(
    File file, {
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.speed = 1.0,
    bool muted = false,
  })  : _controller = VideoPlayerController.file(file),
        isMuted = muted;

  final VideoPlayerController _controller;
  final int trimStartMs;
  final int trimEndMs;
  final double speed;
  bool _initialized = false;
  bool _failed = false;
  bool _disposed = false;
  bool _loop = false;
  bool _ended = false;
  bool isMuted;

  bool get isInitialized => _initialized && !_failed && !_disposed;
  bool get hasError => _failed;

  int get _rawDurationMs => isInitialized ? _controller.value.duration.inMilliseconds : 0;
  int get _startMs {
    final s = trimStartMs < 0 ? 0 : trimStartMs;
    final raw = _rawDurationMs;
    return raw > 0 && s > raw ? raw : s;
  }
  int get _endMs {
    final raw = _rawDurationMs;
    if (trimEndMs > _startMs && (raw <= 0 || trimEndMs <= raw)) return trimEndMs;
    return raw;
  }

  /// Kırpılmış (oynatılacak) bölümün uzunluğu.
  int get durationMs {
    if (!isInitialized) return 0;
    final d = _endMs - _startMs;
    return d > 0 ? d : _rawDurationMs;
  }

  /// Kırpılmış bölüm içindeki konum.
  int? get positionMs {
    if (!isInitialized) return null;
    if (_ended) return durationMs;
    final p = _controller.value.position.inMilliseconds - _startMs;
    final d = durationMs;
    if (p < 0) return 0;
    return p > d ? d : p;
  }

  bool get isPlaying => isInitialized && _controller.value.isPlaying;
  bool get hasEnded => _ended;
  VideoPlayerController get raw => _controller;

  Future<void> initialize({bool loop = false}) async {
    _loop = loop;
    try {
      await _controller.initialize();
      final hasTrimEnd = trimEndMs > trimStartMs && trimEndMs > 0;
      // Kırpma sonu varsa döngüyü dinleyici yönetir (video_player kendi döngüsünü sona göre yapar)
      await _controller.setLooping(loop && !hasTrimEnd);
      if (trimStartMs > 0) {
        await _controller.seekTo(Duration(milliseconds: trimStartMs));
      }
      if ((speed - 1.0).abs() > 0.01) {
        try {
          await _controller.setPlaybackSpeed(speed.clamp(0.25, 3.0));
        } catch (_) {}
      }
      if (isMuted) await _controller.setVolume(0);
      _controller.addListener(_onTick);
      _initialized = true;
    } catch (_) {
      _failed = true;
    }
  }

  void _onTick() {
    if (_disposed || !_initialized) return;
    final v = _controller.value;
    final pos = v.position.inMilliseconds;
    final end = _endMs;
    final reachedTrimEnd = end > 0 && trimEndMs > 0 && pos >= end;
    final reachedNaturalEnd = !_loop && end > 0 && pos >= end - 40 && !v.isPlaying;
    if (reachedTrimEnd || reachedNaturalEnd) {
      if (_loop) {
        _controller.seekTo(Duration(milliseconds: _startMs));
        if (!v.isPlaying) _controller.play();
      } else if (!_ended) {
        _ended = true;
        _controller.pause();
      }
    }
  }

  void play() {
    if (!isInitialized) return;
    if (_ended) {
      _ended = false;
      _controller.seekTo(Duration(milliseconds: _startMs));
    }
    _controller.play();
  }

  void pause() {
    if (isInitialized) _controller.pause();
  }

  Future<void> restart() async {
    if (!isInitialized) return;
    _ended = false;
    await _controller.seekTo(Duration(milliseconds: _startMs));
    await _controller.play();
  }

  void toggleMute() {
    if (!isInitialized) return;
    isMuted = !isMuted;
    _controller.setVolume(isMuted ? 0 : 1);
  }

  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (!isInitialized) {
      return const Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48));
    }
    final ratio = _controller.value.aspectRatio;
    final safeRatio = ratio > 0 ? ratio : 9 / 16;
    if (fit == BoxFit.cover) {
      final size = _controller.value.size;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width > 0 ? size.width : 1080,
            height: size.height > 0 ? size.height : 1920,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: safeRatio,
      child: VideoPlayer(_controller),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _controller.removeListener(_onTick);
    } catch (_) {}
    _controller.dispose();
  }
}

class JuzzioMediaViewerPage extends StatefulWidget {
  final String url;
  final bool isVideo;

  const JuzzioMediaViewerPage({super.key, required this.url, required this.isVideo});

  static Future<void> open(BuildContext context, {required String url, required bool isVideo}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JuzzioMediaViewerPage(url: url, isVideo: isVideo),
      ),
    );
  }

  @override
  State<JuzzioMediaViewerPage> createState() => _JuzzioMediaViewerPageState();
}

class _JuzzioMediaViewerPageState extends State<JuzzioMediaViewerPage> {
  JuzzioVideoController? _video;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _loading = true;
      final c = JuzzioVideoController(widget.url);
      _video = c;
      c.initialize(loop: true).then((_) {
        if (!mounted) return;
        c.play();
        setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: widget.isVideo
            ? (_loading || video == null
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                    onTap: () => setState(() => video.isPlaying ? video.pause() : video.play()),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        video.buildView(),
                        if (video.isInitialized && !video.isPlaying)
                          const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 72),
                      ],
                    ),
                  ))
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.network(
                  widget.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) =>
                      progress == null ? child : const CircularProgressIndicator(color: Colors.white),
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56),
                ),
              ),
      ),
    );
  }
}
