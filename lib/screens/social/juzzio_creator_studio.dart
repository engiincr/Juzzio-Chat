// =============================================================================
// JUZZIO v0.5.0 — İçerik Stüdyosu (Gönderi · Hikâye)
//  v0.5.0: Reels kaldırıldı. Kaynak ekranı kamera öncelikli yeniden tasarlandı:
//   1) Kaynak      : canlı vizör + iOS tarzı beyaz halkalı deklanşör (dokun = fotoğraf,
//                    basılı tut = video), galeri, kamera çevir, zamanlayıcı, "Aa" yazı
//   2) Düzenle     : canlı önizleme, filtreler, yazı stilleri, cam müzik kapsülü,
//                    video kırpıcı, hız, ses, gönderi oranı
//   3) Paylaş      : açıklama, konum, kitle, yorumlar, kapak — yükleme ilerlemesiyle
// Sonuç: gönderi için JuzzioPost, hikâye için List<JuzzioStory> döner.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/native_bridge.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_aurora.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../models/social_models.dart';
import '../../services/juzzio_features_service.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/juzzio_video_kit.dart';
import '../../widgets/media_viewer.dart';
import '../../widgets/juzzio_story_stickers.dart';
import '../../widgets/profile_extras.dart';
import '../close_friends_page.dart';

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

enum JuzzioStudioMode { post, story }

JuzzioStudioMode juzzioStudioModeFromString(String raw) {
  return raw == 'story' ? JuzzioStudioMode.story : JuzzioStudioMode.post;
}

class JuzzioStudioMedia {
  final File file;
  final bool isVideo;
  int durationMs;
  int startMs;
  int endMs;
  String? coverPath;
  String? thumbPath;

  JuzzioStudioMedia({
    required this.file,
    required this.isVideo,
    this.durationMs = 0,
    this.startMs = 0,
    this.endMs = 0,
    this.coverPath,
    this.thumbPath,
  });

  int get effectiveEndMs => endMs > startMs ? endMs : durationMs;
  int get lengthMs => isVideo ? (effectiveEndMs - startMs).clamp(0, 1 << 30) : 0;
  bool get isTrimmed => isVideo && (startMs > 0 || (endMs > 0 && endMs < durationMs));
  String? get previewImagePath => isVideo ? (coverPath ?? thumbPath) : file.path;
}

class JuzzioCreatorStudioPage extends StatefulWidget {
  final JuzzioUserProfile currentUser;
  final JuzzioStudioMode initialMode;

  const JuzzioCreatorStudioPage({
    super.key,
    required this.currentUser,
    this.initialMode = JuzzioStudioMode.post,
  });

  static Future<Object?> open(
    BuildContext context, {
    required JuzzioUserProfile currentUser,
    JuzzioStudioMode mode = JuzzioStudioMode.post,
  }) {
    return Navigator.of(context).push<Object?>(
      PageRouteBuilder<Object?>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => JuzzioAuroraPage(child: JuzzioCreatorStudioPage(currentUser: currentUser, initialMode: mode)),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<JuzzioCreatorStudioPage> createState() => _JuzzioCreatorStudioPageState();
}

class _JuzzioCreatorStudioPageState extends State<JuzzioCreatorStudioPage> with WidgetsBindingObserver {
  static const int _storyMaxMs = 60000;
  static const int _postVideoMaxMs = 90000;
  static const int _maxItems = 10;
  // v0.5 nötr cam: metin hikâyesi arka planları yalnız gri-beyaz tonlarıdır
  static const List<List<Color>> _textBackgrounds = [
    [Color(0xFF2C2C2E), Color(0xFF0B0B0D)],
    [Color(0xFF48484A), Color(0xFF1C1C1E)],
    [Color(0xFF8E8E93), Color(0xFF3A3A3C)],
    [Color(0xFF7C7C82), Color(0xFF2C2C2E)],
    [Color(0xFF111113), Color(0xFF3A3A3C)],
    [Color(0xFF5A5A5F), Color(0xFF0B0B0D)],
    [Color(0xFF636366), Color(0xFF1C1C1E)],
  ];
  static const List<String> _textBackgroundHex = [
    '#2C2C2E',
    '#48484A',
    '#8E8E93',
    '#7C7C82',
    '#111113',
    '#5A5A5F',
    '#636366',
  ];

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _altCtrl = TextEditingController();
  final TextEditingController _overlayCtrl = TextEditingController();
  final PageController _pageCtrl = PageController();

  late JuzzioStudioMode _mode = widget.initialMode;
  int _stage = 0; // 0 = kaynak, 1 = düzenle, 2 = paylaş
  final List<JuzzioStudioMedia> _media = <JuzzioStudioMedia>[];
  int _page = 0;
  bool _textOnlyStory = false;
  int _textBgIndex = 0;

  String _filter = 'none';
  double _speed = 1.0;
  bool _muted = false;
  JuzzioMusicSelection? _music;
  String _overlayText = '';
  String _overlayStyle = 'classic';
  String _overlayColor = '#FFFFFF';
  bool _editingText = false;
  bool _showFilters = false;
  double _postRatio = 1.0;

  late String _storyAudience =
      JuzzioAppController.instance.statusPrivacy == 'nobody' ? 'private' : 'friends';
  String _postVisibility = 'public';
  bool _commentsEnabled = true;

  int _timerSec = 0;
  int? _countdown;
  bool _busy = false;
  bool _publishing = false;
  double _progress = 0;
  String? _error;
  String? _clientRequestId;

  JuzzioVideoController? _preview;
  String _previewKey = '';

  bool get _isStory => _mode == JuzzioStudioMode.story;
  bool get _isPost => _mode == JuzzioStudioMode.post;
  JuzzioStudioMedia? get _current => _media.isEmpty ? null : _media[_page.clamp(0, _media.length - 1)];

  // Canlı vizör (kaynak ekranı)
  lk.LocalVideoTrack? _camTrack;
  bool _camStarting = false;
  bool _camFront = true;
  bool _shutterDown = false;
  // Flaş: arka kamerada gerçek donanım feneri (torch), ön kamerada ekran flaşı
  bool _flashOn = false;
  bool _screenFlash = false;
  // Hikâye emoji çıkartmaları
  List<JuzzioStorySticker> _stickers = <JuzzioStorySticker>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startViewfinder());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopViewfinder();
    _preview?.dispose();
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    _altCtrl.dispose();
    _overlayCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _preview?.pause();
      if (state == AppLifecycleState.paused) _stopViewfinder();
    } else if (state == AppLifecycleState.resumed) {
      if (_stage == 1) _preview?.play();
      if (_stage == 0) _startViewfinder();
    }
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------
  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? JuzzioColors.red500 : JuzzioColors.ink,
        content: Text(text),
      ),
    );
  }

  int _maxVideoMsForMode() {
    if (_isStory) return _storyMaxMs;
    return _postVideoMaxMs;
  }

  Future<bool> _ensurePermission({bool mic = false}) async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _snack(
          _l('Kamera izni gerekli. Ayarlardan izin verebilir veya galeriden seçebilirsin.',
              'Camera permission is required. Allow it in settings or pick from your gallery.',
              'Kamerazugriff wird benötigt. Erlaube ihn in den Einstellungen oder wähle aus der Galerie.'),
          error: true,
        );
        return false;
      }
      if (mic) {
        final m = await Permission.microphone.request();
        if (!m.isGranted) {
          _snack(
            _l('Video sesi için mikrofon izni gerekli.', 'Microphone permission is required for video sound.',
                'Für Videoton wird die Mikrofonberechtigung benötigt.'),
            error: true,
          );
          return false;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<JuzzioStudioMedia> _probeVideo(File f) async {
    final res = await JuzzioNative.videoFrames(f.path, timesMs: const [0], maxWidth: 420, quality: 82);
    var dur = res.durationMs;
    if (dur <= 0) {
      final c = VideoPlayerController.file(f);
      try {
        await c.initialize();
        dur = c.value.duration.inMilliseconds;
      } catch (_) {
      } finally {
        await c.dispose();
      }
    }
    return JuzzioStudioMedia(
      file: f,
      isVideo: true,
      durationMs: dur,
      startMs: 0,
      endMs: dur,
      thumbPath: res.paths.isNotEmpty ? res.paths.first : null,
    );
  }

  /// Video eklendiğinde mod sınırını aşıyorsa kırpıcı açılır (vazgeçilirse ilk kısım alınır).
  Future<void> _addVideo(File f) async {
    setState(() => _busy = true);
    try {
      final item = await _probeVideo(f);
      final maxMs = _maxVideoMsForMode();
      if (item.durationMs > maxMs && mounted) {
        final sel = await JuzzioVideoTrimmerPage.open(
          context,
          file: f,
          maxDurationMs: maxMs,
          initialEndMs: maxMs,
          initialSpeed: _speed,
          initialMuted: _muted,
          showSpeed: !_isPost,
          title: _l('Videoyu kısalt', 'Shorten video', 'Video kürzen'),
        );
        if (sel != null) {
          item
            ..startMs = sel.startMs
            ..endMs = sel.endMs
            ..coverPath = sel.coverPath ?? item.coverPath;
          if (!_isPost) {
            _speed = sel.speed;
            _muted = sel.muted;
          }
        } else {
          item.endMs = maxMs;
        }
      }
      if (!mounted) return;
      setState(() {
        _media.add(item);
        _page = _media.length - 1;
        _textOnlyStory = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Canlı vizör (LiveKit/WebRTC kamera izi; ek paket gerektirmez)
  // ---------------------------------------------------------------------------
  Future<void> _startViewfinder() async {
    if (_camTrack != null || _camStarting || _stage != 0 || !mounted) return;
    _camStarting = true;
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return;
      final t = await lk.LocalVideoTrack.createCameraTrack(lk.CameraCaptureOptions(
        cameraPosition: _camFront ? lk.CameraPosition.front : lk.CameraPosition.back,
        params: lk.VideoParametersPresets.h1080_169,
      ));
      if (!mounted || _stage != 0) {
        try {
          await t.stop();
          await t.dispose();
        } catch (_) {}
        return;
      }
      setState(() => _camTrack = t);
    } catch (_) {
      // Vizör açılamazsa kaynak ekranı yine çalışır (deklanşör sistem kamerasını açar)
    } finally {
      _camStarting = false;
    }
  }

  Future<void> _stopViewfinder() async {
    final t = _camTrack;
    _camTrack = null;
    if (t == null) return;
    await _setTorch(t, false);
    try {
      await t.stop();
    } catch (_) {}
    try {
      await t.dispose();
    } catch (_) {}
  }

  /// Donanım fenerini yalnız destekleniyorsa açar/kapatır (ön kamerada genelde yoktur).
  Future<bool> _setTorch(lk.LocalVideoTrack t, bool on) async {
    try {
      final track = t.mediaStreamTrack;
      if (!await track.hasTorch()) return false;
      await track.setTorch(on);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _toggleFlash() {
    HapticFeedback.selectionClick();
    setState(() => _flashOn = !_flashOn);
  }

  /// Deklanşör anında flaş: arka kamera → fener darbesi, ön kamera (veya fener yoksa) → beyaz ekran flaşı.
  /// Dönen değer: fener açıldıysa true (çekimden sonra kapatılır).
  Future<bool> _fireFlashBeforeCapture(lk.LocalVideoTrack t) async {
    if (!_flashOn) return false;
    if (!_camFront && await _setTorch(t, true)) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      return true;
    }
    if (!mounted) return false;
    setState(() => _screenFlash = true);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return false;
  }

  bool _flipping = false;

  /// v0.7.0 KALICI DÜZELTME: Bazı cihazlarda setCameraPosition sessizce başarısız olup
  /// yalnızca ayna (mirror) değişiyordu → ön kamera "sağa sola dönüyordu". Artık kamera
  /// izi tamamen kapatılıp istenen yöndeki (ön/arka) kamerayla yeniden açılır.
  Future<void> _flipViewfinder() async {
    if (_flipping) return;
    _flipping = true;
    HapticFeedback.selectionClick();
    try {
      final old = _camTrack;
      if (old == null) {
        setState(() => _camFront = !_camFront);
        await _startViewfinder();
        return;
      }
      final next = !_camFront;
      setState(() => _camTrack = null);
      await _setTorch(old, false);
      try {
        await old.stop();
      } catch (_) {}
      try {
        await old.dispose();
      } catch (_) {}
      if (!mounted) return;
      _camFront = next;
      try {
        final t = await lk.LocalVideoTrack.createCameraTrack(lk.CameraCaptureOptions(
          cameraPosition: next ? lk.CameraPosition.front : lk.CameraPosition.back,
          params: lk.VideoParametersPresets.h1080_169,
        ));
        if (!mounted || _stage != 0) {
          await t.stop();
          await t.dispose();
          return;
        }
        setState(() => _camTrack = t);
      } catch (_) {
        if (mounted) setState(() {});
      }
    } finally {
      _flipping = false;
    }
  }

  /// Yakalanan kareyi ekranda görülenle birebir eşler: ön kamerada ayna, vizörün
  /// "cover" kırpmasıyla aynı en-boy oranı. Çözünürlük düşürülmez (PNG, kayıpsız).
  Future<Uint8List> _matchViewfinderFrame(Uint8List png, {required bool mirror, required double targetAspect}) async {
    try {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width.toDouble();
      final h = img.height.toDouble();
      double cw = w, ch = h;
      if (targetAspect > 0) {
        if (w / h > targetAspect) {
          cw = h * targetAspect;
        } else {
          ch = w / targetAspect;
        }
      }
      final src = Rect.fromLTWH((w - cw) / 2, (h - ch) / 2, cw, ch);
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      if (mirror) {
        canvas.translate(cw, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, cw, ch), Paint()..filterQuality = FilterQuality.high);
      final out = await rec.endRecording().toImage(cw.round(), ch.round());
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.dispose();
      return bytes == null ? png : bytes.buffer.asUint8List();
    } catch (_) {
      return png;
    }
  }

  /// Deklanşöre dokununca: vizörden kare yakalanır (yoksa sistem kamerası açılır).
  Future<void> _shutterPhoto() async {
    if (_media.length >= _maxItems) return;
    HapticFeedback.mediumImpact();
    if (_timerSec > 0) {
      for (var i = _timerSec; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdown = i);
        HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
    }
    final t = _camTrack;
    if (t != null) {
      var torchUsed = false;
      try {
        torchUsed = await _fireFlashBeforeCapture(t);
        final buf = await t.mediaStreamTrack.captureFrame();
        if (torchUsed) await _setTorch(t, false);
        if (mounted && _screenFlash) setState(() => _screenFlash = false);
        final size = mounted ? MediaQuery.of(context).size : Size.zero;
        final shot = await _matchViewfinderFrame(
          buf.asUint8List(),
          mirror: _camFront,
          targetAspect: size.height > 0 ? size.width / size.height : 0,
        );
        final dir = Directory.systemTemp;
        final f = File('${dir.path}/juzzio_shot_${DateTime.now().millisecondsSinceEpoch}.png');
        await f.writeAsBytes(shot, flush: true);
        if (!mounted) return;
        setState(() {
          _media.add(JuzzioStudioMedia(file: f, isVideo: false));
          _page = _media.length - 1;
          _textOnlyStory = false;
        });
        _goToEditor();
        return;
      } catch (_) {
        // Yakalama desteklenmiyorsa sistem kamerasına düş
        if (torchUsed) await _setTorch(t, false);
        if (mounted && _screenFlash) setState(() => _screenFlash = false);
      }
    }
    await _capturePhoto();
  }

  /// Galeriden fotoğraf + video birlikte seçimi
  Future<void> _pickGalleryMedia() async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty) return;
      for (final x in picked) {
        if (_media.length >= _maxItems) break;
        final f = File(x.path);
        if (!f.existsSync()) continue;
        if (JuzzioPost.looksLikeVideoUrl(x.path) || (x.mimeType ?? '').startsWith('video/')) {
          await _addVideo(f);
        } else {
          setState(() => _media.add(JuzzioStudioMedia(file: f, isVideo: false)));
        }
      }
      if (!mounted) return;
      setState(() {
        _page = _media.isEmpty ? 0 : _media.length - 1;
        _textOnlyStory = false;
      });
      _goToEditor();
    } catch (_) {
      _snack(_l('Galeriden seçilemedi.', 'Could not pick from gallery.', 'Auswahl aus der Galerie fehlgeschlagen.'), error: true);
    }
  }

  void _goToEditor() {
    if (_media.isEmpty && !_textOnlyStory) return;
    _stopViewfinder();
    setState(() {
      _stage = 1;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients && _media.isNotEmpty) {
        _pageCtrl.jumpToPage(_page.clamp(0, _media.length - 1));
      }
      _syncPreview(force: true);
    });
  }

  // ---------------------------------------------------------------------------
  // Kaynak seçimi
  // ---------------------------------------------------------------------------
  Future<void> _pickGalleryPhotos() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      setState(() {
        for (final x in picked) {
          if (_media.length >= _maxItems) break;
          final f = File(x.path);
          if (f.existsSync()) _media.add(JuzzioStudioMedia(file: f, isVideo: false));
        }
        _page = _media.isEmpty ? 0 : _media.length - 1;
        _textOnlyStory = false;
      });
      _goToEditor();
    } catch (_) {
      _snack(_l('Galeriden fotoğraf seçilemedi.', 'Could not pick photos.', 'Fotos konnten nicht ausgewählt werden.'), error: true);
    }
  }

  Future<void> _pickGalleryVideo() async {
    if (_media.length >= _maxItems) return;
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      final f = File(picked.path);
      if (!f.existsSync()) return;
      await _addVideo(f);
      _goToEditor();
    } catch (_) {
      _snack(_l('Galeriden video seçilemedi.', 'Could not pick a video.', 'Video konnte nicht ausgewählt werden.'), error: true);
    }
  }

  Future<void> _capturePhoto() async {
    if (_media.length >= _maxItems) return;
    if (!await _ensurePermission()) return;
    try {
      await _stopViewfinder();
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: _camFront ? CameraDevice.front : CameraDevice.rear,
      );
      if (picked == null) {
        if (mounted && _stage == 0) _startViewfinder();
        return;
      }
      final f = File(picked.path);
      if (!f.existsSync()) return;
      setState(() {
        _media.add(JuzzioStudioMedia(file: f, isVideo: false));
        _page = _media.length - 1;
        _textOnlyStory = false;
      });
      _goToEditor();
    } catch (_) {
      _snack(_l('Kamera açılamadı.', 'Camera could not be opened.', 'Kamera konnte nicht geöffnet werden.'), error: true);
    }
  }

  Future<void> _captureVideo() async {
    if (_media.length >= _maxItems) return;
    if (!await _ensurePermission(mic: true)) return;
    if (_timerSec > 0) {
      for (var i = _timerSec; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdown = i);
        HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
    }
    try {
      final maxSec = (_maxVideoMsForMode() / 1000).floor().clamp(3, 600);
      await _stopViewfinder();
      final picked = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: _camFront ? CameraDevice.front : CameraDevice.rear,
        maxDuration: Duration(seconds: maxSec),
      );
      if (picked == null) {
        if (mounted && _stage == 0) _startViewfinder();
        return;
      }
      final f = File(picked.path);
      if (!f.existsSync()) return;
      await _addVideo(f);
      _goToEditor();
    } catch (_) {
      _snack(_l('Kamera açılamadı.', 'Camera could not be opened.', 'Kamera konnte nicht geöffnet werden.'), error: true);
    }
  }

  void _startTextStory() {
    _stopViewfinder();
    setState(() {
      _textOnlyStory = true;
      _media.clear();
      _page = 0;
      _stage = 1;
    });
    _openTextEditor();
  }

  // ---------------------------------------------------------------------------
  // Önizleme
  // ---------------------------------------------------------------------------
  Future<void> _syncPreview({bool force = false}) async {
    final cur = _current;
    if (_stage != 1 || cur == null || !cur.isVideo) {
      final old = _preview;
      _preview = null;
      _previewKey = '';
      old?.dispose();
      if (mounted) setState(() {});
      return;
    }
    final key = '${cur.file.path}|${cur.startMs}|${cur.endMs}|$_speed|$_muted';
    if (!force && key == _previewKey && _preview != null) return;
    _previewKey = key;
    final old = _preview;
    _preview = null;
    old?.dispose();
    final ctrl = JuzzioVideoController.file(
      cur.file,
      trimStartMs: cur.startMs,
      trimEndMs: cur.endMs < cur.durationMs ? cur.endMs : 0,
      speed: _speed,
      muted: _muted,
    );
    await ctrl.initialize(loop: true);
    if (!mounted || _previewKey != key) {
      ctrl.dispose();
      return;
    }
    ctrl.play();
    setState(() => _preview = ctrl);
  }

  Future<void> _openTrimmer({JuzzioStudioMedia? target}) async {
    final m = target ?? _current;
    if (m == null || !m.isVideo) return;
    _preview?.pause();
    final maxMs = _isStory ? _storyMaxMs : _postVideoMaxMs;
    final sel = await JuzzioVideoTrimmerPage.open(
      context,
      file: m.file,
      maxDurationMs: maxMs,
      initialStartMs: m.startMs,
      initialEndMs: m.endMs,
      initialSpeed: _speed,
      initialMuted: _muted,
      showSpeed: !_isPost,
    );
    if (!mounted) return;
    if (sel != null) {
      setState(() {
        m
          ..startMs = sel.startMs
          ..endMs = sel.endMs
          ..durationMs = sel.durationMs > 0 ? sel.durationMs : m.durationMs
          ..coverPath = sel.coverPath ?? m.coverPath;
        if (!_isPost) {
          _speed = sel.speed;
          _muted = sel.muted;
        }
      });
    }
    await _syncPreview(force: true);
  }

  Future<void> _cropCurrentPhoto() async {
    final m = _current;
    if (m == null || m.isVideo) return;
    final ratio = _isPost ? _postRatio : 9 / 16;
    final cropped = await JuzzioImageCropperModal.show(
      context,
      sourceFile: m.file,
      isCircular: false,
      aspectRatio: ratio,
      title: _l('Kırp', 'Crop', 'Zuschneiden'),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _media[_page] = JuzzioStudioMedia(file: cropped, isVideo: false);
    });
  }

  void _removeCurrent() {
    if (_media.isEmpty) return;
    setState(() {
      _media.removeAt(_page.clamp(0, _media.length - 1));
      if (_page >= _media.length) _page = _media.isEmpty ? 0 : _media.length - 1;
    });
    if (_media.isEmpty && !_textOnlyStory) {
      setState(() => _stage = 0);
      _startViewfinder();
    }
    _syncPreview(force: true);
  }

  Future<void> _pickMusic() async {
    _preview?.pause();
    final sel = await JuzzioMusicPickerPage.pick(context, initial: _music);
    if (!mounted) return;
    if (sel != null) {
      setState(() {
        if (sel.isEmpty) {
          _music = null;
        } else {
          final firstTime = _music == null;
          _music = sel;
          // Müzik eklenince orijinal ses varsayılan olarak kısılır (Instagram davranışı)
          if (firstTime && _media.any((m) => m.isVideo)) _muted = true;
        }
      });
    }
    await _syncPreview(force: true);
  }

  Future<void> _cycleSpeed() async {
    const order = [1.0, 1.5, 2.0, 0.5];
    final idx = order.indexWhere((s) => (s - _speed).abs() < 0.01);
    setState(() => _speed = order[(idx + 1) % order.length]);
    await _syncPreview(force: true);
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final p = _preview;
    if (p != null && p.isInitialized && p.isMuted != _muted) p.toggleMute();
    _previewKey = '${_current?.file.path}|${_current?.startMs}|${_current?.endMs}|$_speed|$_muted';
  }

  // ---------------------------------------------------------------------------
  // Yazı düzenleyici
  // ---------------------------------------------------------------------------
  void _openTextEditor() {
    _overlayCtrl.text = _overlayText;
    _preview?.pause();
    setState(() {
      _editingText = true;
      _showFilters = false;
    });
  }

  void _closeTextEditor() {
    setState(() {
      _overlayText = _overlayCtrl.text.trim();
      _editingText = false;
    });
    FocusScope.of(context).unfocus();
    _preview?.play();
    if (_textOnlyStory && _overlayText.isEmpty && _captionCtrl.text.trim().isEmpty) {
      setState(() {
        _textOnlyStory = false;
        _stage = 0;
      });
      _startViewfinder();
    }
  }

  // ---------------------------------------------------------------------------
  // Paylaşım
  // ---------------------------------------------------------------------------
  Future<bool> _confirmDiscard() async {
    final hasDraft = _media.isNotEmpty ||
        _textOnlyStory ||
        _captionCtrl.text.trim().isNotEmpty ||
        _overlayText.isNotEmpty;
    if (!hasDraft) return true;
    final res = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _l('Taslak silinsin mi?', 'Discard draft?', 'Entwurf verwerfen?'),
              style: const TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _l('Çıkarsan yaptığın düzenlemeler kaybolur.', 'If you leave, your edits will be lost.',
                  'Wenn du gehst, gehen deine Änderungen verloren.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            _SheetButton(
              label: _l('Sil ve çık', 'Discard', 'Verwerfen'),
              color: JuzzioColors.red500,
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 8),
            _SheetButton(
              label: _l('Düzenlemeye devam et', 'Keep editing', 'Weiter bearbeiten'),
              color: Colors.white24,
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    return res == true;
  }

  Future<void> _handleBack() async {
    if (_publishing) return;
    if (_editingText) {
      _closeTextEditor();
      return;
    }
    if (_stage == 2) {
      setState(() => _stage = 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreview(force: true));
      return;
    }
    if (_stage == 1) {
      final ok = await _confirmDiscard();
      if (!ok || !mounted) return;
      _preview?.dispose();
      setState(() {
        _preview = null;
        _previewKey = '';
        _media.clear();
        _textOnlyStory = false;
        _overlayText = '';
        _music = null;
        _filter = 'none';
        _speed = 1.0;
        _muted = false;
        _stage = 0;
      });
      _startViewfinder();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    if (_isStory) {
      _publishStory();
      return;
    }
    if (_media.isEmpty) return;
    _preview?.pause();
    setState(() {
      _stage = 2;
      _error = null;
    });
  }

  Future<void> _publishStory() async {
    if (_publishing) return;
    final caption = _captionCtrl.text.trim();
    if (_media.isEmpty && _overlayText.isEmpty && caption.isEmpty) {
      _snack(_l('Fotoğraf, video veya yazı ekle.', 'Add a photo, video or text.', 'Füge ein Foto, Video oder Text hinzu.'),
          error: true);
      return;
    }
    _preview?.pause();
    setState(() {
      _publishing = true;
      _progress = 0.05;
      _error = null;
    });
    final created = <JuzzioStory>[];
    try {
      final music = _music;
      if (_media.isEmpty) {
        final st = await SupabaseService.instance.uploadAndCreateStory(
          author: widget.currentUser,
          mediaType: 'text',
          caption: caption,
          overlayText: _overlayText,
          bgColorHex: _textBackgroundHex[_textBgIndex % _textBackgroundHex.length],
          visibility: _storyAudience,
          musicUrl: music?.url ?? '',
          musicTitle: music?.displayTitle ?? '',
          musicStartSec: music?.startSec ?? 0,
          overlayStyle: _overlayStyle,
          overlayColor: _overlayColor,
          stickers: _stickers,
        );
        created.add(st);
      } else {
        for (var i = 0; i < _media.length; i++) {
          final m = _media[i];
          final st = await SupabaseService.instance.uploadAndCreateStory(
            author: widget.currentUser,
            mediaType: m.isVideo ? 'video' : 'image',
            mediaFile: m.file,
            caption: caption,
            overlayText: _overlayText,
            videoDurationSec: m.isVideo ? (m.lengthMs / 1000 / _speed).ceil().clamp(3, 60) : 7,
            filterPreset: _filter,
            visibility: _storyAudience,
            trimStartMs: m.isVideo ? m.startMs : 0,
            trimEndMs: m.isVideo && m.endMs < m.durationMs ? m.endMs : 0,
            playbackSpeed: _speed,
            isMuted: _muted,
            musicUrl: music?.url ?? '',
            musicTitle: music?.displayTitle ?? '',
            musicStartSec: music?.startSec ?? 0,
            overlayStyle: _overlayStyle,
            overlayColor: _overlayColor,
            stickers: _stickers,
          );
          created.add(st);
          if (mounted) setState(() => _progress = (i + 1) / _media.length);
        }
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = SupabaseService.instance.friendlyError(e);
      });
      if (created.isNotEmpty) {
        _snack(
          _l('${created.length} hikâye paylaşıldı, kalanlar yüklenemedi.', '${created.length} stories shared, the rest failed.',
              '${created.length} Storys geteilt, der Rest ist fehlgeschlagen.'),
          error: true,
        );
      }
    }
  }

  Future<void> _publishPost() async {
    if (_publishing || _media.isEmpty) return;
    _clientRequestId ??= '${widget.currentUser.id}_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _publishing = true;
      _progress = 0.05;
      _error = null;
    });
    try {
      final hasVideo = _media.any((m) => m.isVideo);
      final contentType = _media.length > 1 ? 'carousel' : (hasVideo ? 'video' : 'image');
      final first = _media.first;
      final totalMs = _media.fold<int>(0, (s, m) => s + m.lengthMs);
      final coverPath = _media.firstWhere(
        (m) => m.isVideo && (m.coverPath ?? m.thumbPath) != null,
        orElse: () => first,
      );
      final coverFilePath = first.isVideo ? (coverPath.coverPath ?? coverPath.thumbPath) : null;
      final music = _music;
      final created = await JuzzioSocialService.instance.uploadAndCreatePost(
        author: widget.currentUser,
        mediaFiles: _media.map((m) => m.file).toList(),
        contentType: contentType,
        caption: _captionCtrl.text,
        locationName: _locationCtrl.text,
        altText: _altCtrl.text,
        visibility: _postVisibility,
        commentsEnabled: _commentsEnabled,
        aspectRatio: _postRatio,
        videoDurationSec: (totalMs / 1000 / (_isPost ? 1 : _speed)).ceil(),
        trimStartSec: first.isVideo ? (first.startMs / 1000).floor() : 0,
        trimEndSec: first.isVideo && first.endMs < first.durationMs ? (first.endMs / 1000).ceil() : 0,
        audioTitle: music?.displayTitle ?? '',
        filterPreset: _filter,
        playbackSpeed: _isPost ? 1.0 : _speed,
        isMuted: _muted,
        musicUrl: music?.url ?? '',
        musicStartSec: music?.startSec ?? 0,
        clipMeta: [
          for (final m in _media)
            {
              'start_ms': m.isVideo ? m.startMs : 0,
              'end_ms': m.isVideo && m.endMs < m.durationMs ? m.endMs : 0,
            },
        ],
        customCoverFile: coverFilePath != null ? File(coverFilePath) : null,
        clientRequestId: _clientRequestId,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ARAYÜZ
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _stage == 2 ? _buildDetailsStage() : _buildDarkStage(),
      ),
    );
  }

  Widget _buildDarkStage() {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_stage == 0) _buildSourceStage() else _buildEditorStage(),
          if (_editingText) _buildTextEditorOverlay(),
          if (_countdown != null)
            Container(
              color: Colors.black.withOpacity(0.55),
              alignment: Alignment.center,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_countdown),
                tween: Tween(begin: 1.6, end: 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Text(
                  '$_countdown',
                  style: const TextStyle(color: Colors.white, fontSize: 120, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          if (_screenFlash) const IgnorePointer(child: ColoredBox(color: Colors.white)),
          if (_busy)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: Colors.white),
            ),
          if (_publishing) _buildPublishingOverlay(),
        ],
      ),
    );
  }

  // ----- 1. KAYNAK (kamera öncelikli) ------------------------------------------
  Widget _buildSourceStage() {
    final mq = MediaQuery.of(context);
    final cam = _camTrack;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Canlı vizör ya da sade grafit zemin
        if (cam != null)
          lk.VideoTrackRenderer(
            cam,
            fit: lk.VideoViewFit.cover,
            mirrorMode: _camFront ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off,
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.1,
                colors: [Color(0xFF2A2A2E), Color(0xFF0B0B0D)],
              ),
            ),
            child: Center(child: Icon(Icons.photo_camera_outlined, color: Colors.white24, size: 64)),
          ),
        // Üst ve alt okunurluk gölgeleri
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.18, 0.66, 1],
                colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
              ),
            ),
          ),
        ),
        // Üst çubuk: kapat · zamanlayıcı · devam
        Positioned(
          top: mq.padding.top + 8,
          left: 12,
          right: 12,
          child: Row(
            children: [
              JuzzioGlassIconButton(icon: Icons.close_rounded, onTap: _handleBack, size: 42),
              const SizedBox(width: 8),
              JuzzioGlassIconButton(
                icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                active: _flashOn,
                onTap: _toggleFlash,
                size: 42,
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _timerSec = _timerSec == 0 ? 3 : (_timerSec == 3 ? 10 : 0));
                },
                child: JuzzioGlass(
                  radius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, color: _timerSec > 0 ? const Color(0xFFFFD60A) : Colors.white, size: 18),
                      const SizedBox(width: 5),
                      Text(
                        _timerSec == 0 ? _l('Kapalı', 'Off', 'Aus') : '${_timerSec}s',
                        style: TextStyle(
                          color: _timerSec > 0 ? const Color(0xFFFFD60A) : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (_media.isNotEmpty)
                GestureDetector(
                  onTap: _goToEditor,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '${_l('Devam', 'Next', 'Weiter')} (${_media.length})',
                      style: const TextStyle(color: Color(0xFF111113), fontWeight: FontWeight.w900),
                    ),
                  ),
                )
              else
                const SizedBox(width: 42),
            ],
          ),
        ),
        // Sağ dikey araçlar (hikâyede "Aa" yazı)
        if (_isStory)
          Positioned(
            right: 14,
            top: mq.padding.top + 76,
            child: Column(
              children: [
                _CircleGlassButton(icon: Icons.text_fields_rounded, onTap: _startTextStory),
                const SizedBox(height: 6),
                Text(_l('Yazı', 'Text', 'Text'),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        // Alt: galeri · deklanşör · kamera çevir + mod seçici
        Positioned(
          left: 0,
          right: 0,
          bottom: mq.padding.bottom + 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _l('Dokun: fotoğraf · Basılı tut: video', 'Tap: photo · Hold: video', 'Tippen: Foto · Halten: Video'),
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _pickGalleryMedia,
                      child: JuzzioGlass(
                        radius: 14,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: _media.isNotEmpty && _media.last.previewImagePath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.file(File(_media.last.previewImagePath!), fit: BoxFit.cover),
                                )
                              : const Icon(Icons.photo_library_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                    _IosShutterButton(
                      pressed: _shutterDown,
                      onTapDown: () => setState(() => _shutterDown = true),
                      onTapCancel: () => setState(() => _shutterDown = false),
                      onTap: () {
                        setState(() => _shutterDown = false);
                        _shutterPhoto();
                      },
                      onLongPress: () {
                        setState(() => _shutterDown = false);
                        HapticFeedback.heavyImpact();
                        _stopViewfinder().then((_) => _captureVideo()).whenComplete(() {
                          if (mounted && _stage == 0) _startViewfinder();
                        });
                      },
                    ),
                    JuzzioGlassIconButton(icon: Icons.cameraswitch_rounded, onTap: _flipViewfinder, size: 48),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildModeSwitcher(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    Widget item(JuzzioStudioMode m, String label) {
      final sel = _mode == m;
      return GestureDetector(
        onTap: () {
          if (_mode == m) return;
          HapticFeedback.selectionClick();
          setState(() {
            _mode = m;
            if (m != JuzzioStudioMode.story) _textOnlyStory = false;
            _page = 0;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: sel ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(JuzzioStudioMode.post, _l('GÖNDERİ', 'POST', 'BEITRAG')),
          if (JuzzioFeaturesService.instance.lastAppConfig.storiesEnabled)
            item(JuzzioStudioMode.story, _l('HİKÂYE', 'STORY', 'STORY')),
        ],
      ),
    );
  }

  // ----- 2. DÜZENLE -----------------------------------------------------------
  Widget _buildEditorStage() {
    final mq = MediaQuery.of(context);
    final cur = _current;
    final canvasRatio = _isPost ? _postRatio : 9 / 16;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                var w = box.maxWidth - (_isPost ? 0 : 12);
                var h = w / canvasRatio;
                if (h > box.maxHeight - 8) {
                  h = box.maxHeight - 8;
                  w = h * canvasRatio;
                }
                return Center(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_isPost ? 6 : 22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_music != null && !_editingText)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: JuzzioBackgroundMusic(
                                musicUrl: _music!.url,
                                startSec: _music!.startSec,
                                playing: _stage == 1,
                              ),
                            ),
                          _buildCanvasContent(),
                          if (_overlayText.isNotEmpty && !_editingText && (_isStory || _textOnlyStory))
                            Center(
                              child: GestureDetector(
                                onTap: _openTextEditor,
                                child: Padding(
                                  // v0.7.0: yazı boyutu tuval genişliğine oranlıdır; paylaşımdan
                                  // sonra izleyicide de ekranda görüldüğü oranda çıkar.
                                  padding: EdgeInsets.symmetric(horizontal: w * kJuzzioStoryTextPadRatio),
                                  child: JuzzioOverlayText(
                                    text: _overlayText,
                                    styleId: _overlayStyle,
                                    colorHex: _overlayColor,
                                    fontSize: w * kJuzzioStoryTextSizeRatio,
                                  ),
                                ),
                              ),
                            ),
                          if (_isStory && _stickers.isNotEmpty && !_editingText)
                            Positioned.fill(
                              child: JuzzioStickerLayer(
                                stickers: _stickers,
                                onChanged: (next) => setState(() => _stickers = next),
                              ),
                            ),
                          // Üst gölge + araçlar
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 110,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.black54, Colors.transparent],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 6,
                            child: _CircleGlassButton(icon: Icons.arrow_back_ios_new_rounded, onTap: _handleBack),
                          ),
                          if (_music != null)
                            Positioned(
                              top: 14,
                              left: 58,
                              right: 64,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: _pickMusic,
                                  child: _MusicSticker(selection: _music!),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 6,
                            child: _buildToolRail(cur),
                          ),
                          if (_media.length > 1)
                            Positioned(
                              bottom: 10,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < _media.length; i++)
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        margin: const EdgeInsets.symmetric(horizontal: 3),
                                        width: i == _page ? 18 : 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: i == _page ? Colors.white : Colors.white54,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (cur != null && cur.isVideo && (cur.isTrimmed || (_speed - 1).abs() > 0.01))
                            Positioned(
                              bottom: _media.length > 1 ? 26 : 12,
                              left: 12,
                              child: _GlassLabel(
                                icon: Icons.content_cut_rounded,
                                text: '${juzzioFormatSeconds(cur.lengthMs)}'
                                    '${(_speed - 1).abs() > 0.01 ? ' · ${_speed}x' : ''}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _showFilters ? _buildFilterStrip() : const SizedBox.shrink(),
          ),
          if ((_isPost && _media.isNotEmpty) || (_isStory && _media.length > 1)) _buildMediaStrip(),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + (_editingText ? 0 : mq.viewInsets.bottom)),
            child: _isStory ? _buildStoryBottomBar() : _buildNextBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasContent() {
    if (_textOnlyStory || _media.isEmpty) {
      final colors = _textBackgrounds[_textBgIndex % _textBackgrounds.length];
      return GestureDetector(
        onTap: _openTextEditor,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          ),
          alignment: Alignment.center,
          child: _overlayText.isEmpty
              ? Text(
                  _l('Yazmak için dokun', 'Tap to type', 'Zum Schreiben tippen'),
                  style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w700),
                )
              : null,
        ),
      );
    }
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: _media.length,
      onPageChanged: (i) {
        setState(() => _page = i);
        _syncPreview();
      },
      itemBuilder: (_, i) {
        final m = _media[i];
        Widget content;
        if (m.isVideo) {
          final p = _preview;
          if (i == _page && p != null && p.isInitialized) {
            content = GestureDetector(
              onTap: () => setState(() => p.isPlaying ? p.pause() : p.play()),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  p.buildView(fit: BoxFit.cover),
                  if (!p.isPlaying)
                    const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 72)),
                ],
              ),
            );
          } else {
            final thumb = m.previewImagePath;
            content = Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null) Image.file(File(thumb), fit: BoxFit.cover) else const ColoredBox(color: Colors.black),
                const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
              ],
            );
          }
        } else {
          content = Image.file(m.file, fit: BoxFit.cover, gaplessPlayback: true);
        }
        return JuzzioMediaFilters.apply(_filter, content);
      },
    );
  }

  Future<void> _addSticker() async {
    if (_stickers.length >= 20) {
      _snack(_l('En fazla 20 çıkartma eklenebilir.', 'Up to 20 stickers.', 'Höchstens 20 Sticker.'), error: true);
      return;
    }
    final emoji = await pickJuzzioStickerEmoji(context);
    if (emoji == null || !mounted) return;
    HapticFeedback.selectionClick();
    final n = _stickers.length;
    setState(() {
      _stickers = <JuzzioStorySticker>[
        ..._stickers,
        JuzzioStorySticker(emoji: emoji, x: 0.5 + ((n % 3) - 1) * 0.12, y: 0.42 + (n % 4) * 0.05),
      ];
    });
    if (n == 0) {
      _snack(_l('Sürükle, iki parmakla büyüt; kaldırmak için uzun bas.', 'Drag, pinch to resize; long-press to remove.',
          'Ziehen, mit zwei Fingern skalieren; lange drücken zum Entfernen.'));
    }
  }

  Widget _buildToolRail(JuzzioStudioMedia? cur) {
    final tools = <Widget>[
      if (_isStory)
        _RailButton(icon: Icons.text_fields_rounded, label: _l('Yazı', 'Text', 'Text'), onTap: _openTextEditor),
      if (_textOnlyStory)
        _RailButton(
          icon: Icons.palette_rounded,
          label: _l('Zemin', 'Background', 'Hintergrund'),
          onTap: () => setState(() => _textBgIndex = (_textBgIndex + 1) % _textBackgrounds.length),
        ),
      if (!_textOnlyStory)
        _RailButton(
          icon: Icons.auto_awesome_rounded,
          label: _l('Filtre', 'Filters', 'Filter'),
          active: _showFilters || _filter != 'none',
          onTap: () => setState(() => _showFilters = !_showFilters),
        ),
      _RailButton(
        icon: Icons.music_note_rounded,
        label: _l('Müzik', 'Music', 'Musik'),
        active: _music != null,
        onTap: _pickMusic,
      ),
      if (_isStory)
        _RailButton(
          icon: Icons.emoji_emotions_outlined,
          label: _l('Çıkartma', 'Sticker', 'Sticker'),
          active: _stickers.isNotEmpty,
          onTap: _addSticker,
        ),
      if (cur != null && cur.isVideo) ...[
        _RailButton(
          icon: Icons.content_cut_rounded,
          label: _l('Kırp', 'Trim', 'Schneiden'),
          active: cur.isTrimmed,
          onTap: () => _openTrimmer(),
        ),
        if (!_isPost)
          _RailButton(
            icon: Icons.speed_rounded,
            label: (_speed - 1).abs() < 0.01 ? _l('Hız', 'Speed', 'Tempo') : '${_speed}x',
            active: (_speed - 1).abs() > 0.01,
            onTap: _cycleSpeed,
          ),
        _RailButton(
          icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: _muted ? _l('Sessiz', 'Muted', 'Stumm') : _l('Ses', 'Sound', 'Ton'),
          active: _muted,
          onTap: _toggleMute,
        ),
      ],
      if (cur != null && !cur.isVideo)
        _RailButton(icon: Icons.crop_rotate_rounded, label: _l('Kırp', 'Crop', 'Zuschnitt'), onTap: _cropCurrentPhoto),
      if (_media.isNotEmpty)
        _RailButton(icon: Icons.delete_outline_rounded, label: _l('Kaldır', 'Remove', 'Entfernen'), onTap: _removeCurrent),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: tools);
  }

  Widget _buildFilterStrip() {
    final cur = _current;
    final thumb = cur?.previewImagePath;
    return Container(
      key: const ValueKey('filters'),
      height: 104,
      padding: const EdgeInsets.only(top: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: JuzzioMediaFilters.presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final preset = JuzzioMediaFilters.presets[i];
          final sel = preset.id == _filter;
          final img = thumb != null
              ? Image.file(File(thumb), fit: BoxFit.cover, gaplessPlayback: true)
              : const ColoredBox(color: JuzzioColors.slate700);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _filter = preset.id);
            },
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: sel ? Colors.white : Colors.white24, width: sel ? 2.5 : 1),
                  ),
                  child: ClipOval(child: JuzzioMediaFilters.apply(preset.id, img)),
                ),
                const SizedBox(height: 6),
                Text(
                  preset.label,
                  style: TextStyle(
                    color: sel ? Colors.white : Colors.white60,
                    fontSize: 11.5,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaStrip() {
    return Container(
      height: 74,
      margin: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12),
              itemCount: _media.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _media.removeAt(oldIndex);
                  _media.insert(newIndex, item);
                  _page = newIndex;
                });
                if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_page);
                _syncPreview(force: true);
              },
              itemBuilder: (_, i) {
                final m = _media[i];
                final sel = i == _page;
                final thumb = m.previewImagePath;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('${m.file.path}#$i'),
                  index: i,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _page = i);
                      if (_pageCtrl.hasClients) {
                        _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
                      }
                      _syncPreview();
                    },
                    onDoubleTap: m.isVideo ? () => _openTrimmer(target: m) : null,
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? Colors.white : Colors.white12, width: sel ? 2.4 : 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumb != null)
                              JuzzioMediaFilters.apply(_filter, Image.file(File(thumb), fit: BoxFit.cover))
                            else
                              const ColoredBox(color: JuzzioColors.slate800),
                            if (m.isVideo)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    juzzioFormatClock(m.lengthMs),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_media.length < _maxItems)
            GestureDetector(
              onTap: _showAddMoreSheet,
              child: Container(
                width: 56,
                height: 74,
                margin: const EdgeInsets.only(right: 12, left: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddMoreSheet() async {
    _preview?.pause();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTile(
                icon: Icons.photo_library_rounded,
                label: _l('Fotoğraf ekle', 'Add photos', 'Fotos hinzufügen'),
                onTap: () => Navigator.of(ctx).pop('photos'),
              ),
            _SheetTile(
              icon: Icons.video_library_rounded,
              label: _l('Video ekle', 'Add video', 'Video hinzufügen'),
              onTap: () => Navigator.of(ctx).pop('video'),
            ),
            _SheetTile(
                icon: Icons.photo_camera_rounded,
                label: _l('Fotoğraf çek', 'Take photo', 'Foto aufnehmen'),
                onTap: () => Navigator.of(ctx).pop('camera_photo'),
              ),
            _SheetTile(
              icon: Icons.videocam_rounded,
              label: _l('Video çek', 'Record video', 'Video aufnehmen'),
              onTap: () => Navigator.of(ctx).pop('camera_video'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'photos':
        await _pickGalleryPhotos();
        break;
      case 'video':
        await _pickGalleryVideo();
        break;
      case 'camera_photo':
        await _capturePhoto();
        break;
      case 'camera_video':
        await _captureVideo();
        break;
      default:
        _preview?.play();
    }
  }

  Widget _buildStoryBottomBar() {
    String audienceLabel() {
      switch (_storyAudience) {
        case 'everyone':
          return _l('Herkes', 'Everyone', 'Alle');
        case 'private':
          return _l('Sadece ben', 'Only me', 'Nur ich');
        case 'close_friends':
          return _l('Yakın arkadaşlar', 'Close friends', 'Enge Freunde');
        default:
          return _l('Arkadaşlar', 'Friends', 'Freunde');
      }
    }

    IconData audienceIcon() {
      switch (_storyAudience) {
        case 'everyone':
          return Icons.public_rounded;
        case 'private':
          return Icons.lock_rounded;
        case 'close_friends':
          return Icons.stars_rounded;
        default:
          return Icons.group_rounded;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w700)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: _captionCtrl,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              icon: const Icon(Icons.subtitles_outlined, color: Colors.white60, size: 20),
              hintText: _l('Açıklama ekle… (otomatik çevrilir)', 'Add a caption… (auto-translated)',
                  'Beschreibung hinzufügen … (wird übersetzt)'),
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GestureDetector(
              // v0.7.0: Arkadaşlar → Yakın arkadaşlar → Herkes → Sadece ben
              // Uzun basınca yakın arkadaş listesi düzenlenir.
              onLongPress: () => JuzzioCloseFriendsPage.open(context),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _storyAudience = switch (_storyAudience) {
                    'friends' => 'close_friends',
                    'close_friends' => 'everyone',
                    'everyone' => 'private',
                    _ => 'friends',
                  };
                });
                if (_storyAudience == 'close_friends') {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                    content: Text(_l('Yalnızca yakın arkadaş listendekiler görecek. Listeyi düzenlemek için uzun bas.',
                        'Only people on your close friends list will see it. Long-press to edit the list.',
                        'Nur deine engen Freunde sehen es. Lange drücken zum Bearbeiten.')),
                    action: SnackBarAction(
                      label: _l('Liste', 'List', 'Liste'),
                      onPressed: () => JuzzioCloseFriendsPage.open(context),
                    ),
                  ));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _storyAudience == 'close_friends'
                      ? const Color(0xFF34C759).withOpacity(0.28)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(audienceIcon(), color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(audienceLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 2),
                    const Icon(Icons.unfold_more_rounded, color: Colors.white54, size: 16),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _GradientPill(
              label: _media.length > 1
                  ? _l('${_media.length} hikâye paylaş', 'Share ${_media.length} stories', '${_media.length} Storys teilen')
                  : _l('Hikâyene ekle', 'Your story', 'Deine Story'),
              icon: Icons.arrow_forward_rounded,
              onTap: _publishStory,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNextBar() {
    return Row(
      children: [
        if (_isPost)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in const [
                  [1.0, '1:1'],
                  [0.8, '4:5'],
                  [1.91, '16:9'],
                ])
                  GestureDetector(
                    onTap: () => setState(() => _postRatio = r[0] as double),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_postRatio - (r[0] as double)).abs() < 0.01 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r[1] as String,
                        style: TextStyle(
                          color: (_postRatio - (r[0] as double)).abs() < 0.01 ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const Spacer(),
        _GradientPill(
          label: _l('İleri', 'Next', 'Weiter'),
          icon: Icons.arrow_forward_rounded,
          onTap: _next,
        ),
      ],
    );
  }

  // ----- Yazı düzenleyici katmanı ----------------------------------------------
  Widget _buildTextEditorOverlay() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final id in JuzzioOverlayStyles.ids)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _overlayStyle = id),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _overlayStyle == id ? Colors.white : Colors.white12,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        JuzzioOverlayStyles.label(id),
                                        style: TextStyle(
                                          color: _overlayStyle == id ? Colors.black : Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _closeTextEditor,
                        child: Text(
                          _l('Bitti', 'Done', 'Fertig'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: TextField(
                        controller: _overlayCtrl,
                        autofocus: true,
                        maxLines: null,
                        maxLength: 220,
                        textAlign: TextAlign.center,
                        cursorColor: Colors.white,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          fontFamily: _overlayStyle == 'typewriter' ? 'monospace' : JuzzioConfig.fontRegularBold,
                          color: JuzzioOverlayStyles.parse(_overlayColor),
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          shadows: _overlayStyle == 'neon'
                              ? [Shadow(color: JuzzioOverlayStyles.parse(_overlayColor), blurRadius: 14)]
                              : const [Shadow(color: Colors.black54, blurRadius: 10)],
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          counterText: '',
                          hintText: _l('Bir şeyler yaz…', 'Type something…', 'Schreib etwas …'),
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + bottomInset),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final hex in JuzzioOverlayStyles.palette)
                          GestureDetector(
                            onTap: () => setState(() => _overlayColor = hex),
                            child: Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: JuzzioOverlayStyles.parse(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: _overlayColor == hex ? 3.5 : 1.5,
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
        ),
      ),
    );
  }

  Widget _buildPublishingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.72),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 86,
              height: 86,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _progress <= 0.06 ? null : _progress.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      color: Colors.white,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Text(
                    '${(_progress.clamp(0.0, 1.0) * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _l('Paylaşılıyor…', 'Sharing…', 'Wird geteilt …'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // ----- 3. PAYLAŞ (gönderi) -------------------------------------------
  Widget _buildDetailsStage() {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    // v0.6 Glassmorphism: aurora zemin + buzlu cam kartlar
    const bg = Colors.transparent;
    final fg = isDark ? Colors.white : JuzzioColors.ink;
    final sub = isDark ? Colors.white60 : JuzzioColors.slate500;
    final card = isDark ? const Color(0x24FFFFFF) : const Color(0xB3FFFFFF);
    final first = _media.isNotEmpty ? _media.first : null;
    final thumb = first?.previewImagePath;
    final hasImage = _media.any((m) => !m.isVideo);

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: sub, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    InputDecoration deco(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: sub),
          prefixIcon: Icon(icon, color: sub, size: 20),
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        );

    final visOptions = <List<Object>>[
      ['public', Icons.public_rounded, _l('Herkes', 'Everyone', 'Alle')],
      ['followers', Icons.how_to_reg_rounded, _l('Ekleyenler', 'Followers', 'Follower')],
      ['friends', Icons.group_rounded, _l('Arkadaşlar', 'Friends', 'Freunde')],
      ['private', Icons.lock_rounded, _l('Sadece ben', 'Only me', 'Nur ich')],
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: fg,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _handleBack),
        title: Text(
          _l('Yeni gönderi', 'New post', 'Neuer Beitrag'),
          style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() => _stage = 1);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreview(force: true));
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 84,
                        height: 104,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (thumb != null)
                              JuzzioMediaFilters.apply(_filter, Image.file(File(thumb), fit: BoxFit.cover))
                            else
                              ColoredBox(color: card),
                            if (_media.length > 1)
                              const Positioned(
                                top: 6,
                                right: 6,
                                child: Icon(Icons.collections_rounded, color: Colors.white, size: 18),
                              ),
                            if (first != null && first.isVideo)
                              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _captionCtrl,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 2200,
                      style: TextStyle(color: fg, fontSize: 15, height: 1.4),
                      decoration: InputDecoration(
                        hintText: _l('Açıklama yaz… #etiket @kişi', 'Write a caption… #tag @person',
                            'Beschreibung schreiben … #tag @person'),
                        hintStyle: TextStyle(color: sub),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterStyle: TextStyle(color: sub, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(color: isDark ? Colors.white10 : JuzzioColors.slate200, height: 24),
              _DetailTile(
                icon: Icons.music_note_rounded,
                title: _music == null ? _l('Müzik ekle', 'Add music', 'Musik hinzufügen') : _music!.displayTitle,
                subtitle: _music == null
                    ? _l('Şarkı adını ara, tek dokunuşla ekle', 'Search a song and add it with one tap', 'Song suchen und mit einem Tippen hinzufügen')
                    : _l('Değiştirmek için dokun', 'Tap to change', 'Zum Ändern tippen'),
                fg: fg,
                sub: sub,
                onTap: _pickMusic,
              ),
              if (first != null && first.isVideo)
                _DetailTile(
                  icon: Icons.photo_size_select_actual_rounded,
                  title: _l('Kapak ve kırpma', 'Cover and trim', 'Cover und Zuschnitt'),
                  subtitle:
                      '${juzzioFormatSeconds(first.lengthMs)} · ${first.coverPath != null ? _l('özel kapak', 'custom cover', 'eigenes Cover') : _l('otomatik kapak', 'auto cover', 'automatisches Cover')}',
                  fg: fg,
                  sub: sub,
                  onTap: () async {
                    await _openTrimmer(target: first);
                    _preview?.pause();
                    if (mounted) setState(() {});
                  },
                ),
              section(
                _l('KONUM', 'LOCATION', 'ORT'),
                TextField(
                  controller: _locationCtrl,
                  maxLength: 80,
                  style: TextStyle(color: fg),
                  decoration: deco(_l('Konum ekle', 'Add location', 'Ort hinzufügen'), Icons.location_on_outlined)
                      .copyWith(counterText: ''),
                ),
              ),
              section(
                _l('KİMLER GÖREBİLİR', 'WHO CAN SEE THIS', 'WER KANN DAS SEHEN'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in visOptions)
                      GestureDetector(
                        onTap: () => setState(() => _postVisibility = o[0] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _postVisibility == o[0] ? JuzzioColors.blue500 : card,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(o[1] as IconData, size: 17, color: _postVisibility == o[0] ? Colors.white : fg),
                              const SizedBox(width: 6),
                              Text(
                                o[2] as String,
                                style: TextStyle(
                                  color: _postVisibility == o[0] ? Colors.white : fg,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile.adaptive(
                  value: _commentsEnabled,
                  onChanged: (v) => setState(() => _commentsEnabled = v),
                  title: Text(
                    _l('Yorumlara izin ver', 'Allow comments', 'Kommentare erlauben'),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                  secondary: Icon(Icons.mode_comment_outlined, color: sub),
                ),
              ),
              if (hasImage)
                section(
                  _l('ERİŞİLEBİLİRLİK', 'ACCESSIBILITY', 'BARRIEREFREIHEIT'),
                  TextField(
                    controller: _altCtrl,
                    maxLength: 200,
                    style: TextStyle(color: fg),
                    decoration: deco(
                      _l('Alternatif metin (görme engelliler için)', 'Alt text (for screen readers)',
                          'Alternativtext (für Screenreader)'),
                      Icons.accessibility_new_rounded,
                    ).copyWith(counterText: ''),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JuzzioColors.red500.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: JuzzioColors.red500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!, style: const TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: _publishing
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              _l('Yükleniyor…', 'Uploading…', 'Wird hochgeladen …'),
                              style: TextStyle(color: fg, fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                            Text(
                              '${(_progress.clamp(0.0, 1.0) * 100).round()}%',
                              style: TextStyle(color: fg, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _progress.clamp(0.0, 1.0),
                            minHeight: 6,
                            color: isDark ? Colors.white : JuzzioColors.ink,
                            backgroundColor: isDark ? Colors.white12 : JuzzioColors.slate200,
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: 54,
                    child: _GradientPill(
                      label: _l('Paylaş', 'Share', 'Teilen'),
                      icon: Icons.send_rounded,
                      onTap: _publishPost,
                      expand: true,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Küçük yapı taşları
// =============================================================================
class _CircleGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 42,
            height: 42,
            color: Colors.black.withOpacity(0.3),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _RailButton({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, color: active ? Colors.black : Colors.white, size: 21),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 60,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _GlassLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MusicSticker extends StatelessWidget {
  final JuzzioMusicSelection selection;
  const _MusicSticker({required this.selection});

  @override
  Widget build(BuildContext context) {
    final cover = selection.coverUrl.isNotEmpty ? selection.coverUrl : juzzioYoutubeThumb(selection.videoId);
    return JuzzioGlassMusicCapsule(
      coverUrl: cover,
      label: selection.displayTitle,
      playing: true,
      maxWidth: 240,
    );
  }
}

class _GradientPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool expand;

  const _GradientPill({required this.label, required this.icon, required this.onTap, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: Color(0xFF111113),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: const Color(0xFF111113), size: 19),
        ],
      ),
    );
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: body,
    );
  }
}

class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              color: const Color(0xFF1B1B22).withOpacity(0.92),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color fg;
  final Color sub;
  final VoidCallback onTap;

  const _DetailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.fg,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: fg, size: 20),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 12.5)),
      trailing: Icon(Icons.chevron_right_rounded, color: sub),
    );
  }
}

/// iOS tarzı deklanşör: beyaz dış halka + basınca küçülen beyaz iç daire
class _IosShutterButton extends StatelessWidget {
  final bool pressed;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTapDown;
  final VoidCallback onTapCancel;

  const _IosShutterButton({
    required this.pressed,
    required this.onTap,
    required this.onLongPress,
    required this.onTapDown,
    required this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: JuzzioAppController.instance.trEn('Deklanşör', 'Shutter', 'Auslöser'),
      child: GestureDetector(
        onTapDown: (_) => onTapDown(),
        onTapCancel: onTapCancel,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4.5),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16)],
          ),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            width: pressed ? 56 : 64,
            height: pressed ? 56 : 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pressed ? const Color(0xFFE5E5EA) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
