// =============================================================================
// JUZZIO v0.9.3 — Süren arama oturumu (WhatsApp benzeri)
//  Eskiden arama ekranı normal bir sayfaydı: geri tuşu / sayfadan çıkış aramayı kapatıyor,
//  uygulama arka plana atılınca Android mikrofonu kesiyordu. Şimdi:
//   • Arama ekranı kök Navigator'ın katmanında (OverlayEntry) yaşar; kendi iç Navigator'ı
//     vardır (ekran içi sayfalar/diyaloglar arama üstünde açılır). Küçültülünce ekran
//     KAPANMAZ (durumu, bağlantısı, zamanlayıcıları sürer), sağ altta sürüklenebilir bir
//     küçük pencereye iner; altta sohbetlere, mesajlara serbestçe gidilir. Dokununca büyür.
//   • Geri tuşu aramayı kapatmaz, küçültür. Bildirime dokunulunca arama küçülür ve
//     ilgili sohbet açılır — görüşme kesilmez.
//   • Uygulama arka plana atılınca Android ekran içinde ekran (PiP) açılır; arama süresince
//     ön plan servisi mikrofon/kamera erişimini korur ("Arama sürüyor" bildirimi).
// =============================================================================

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/app_theme_and_locale.dart';
import 'deepgram_livekit_service.dart';

enum JuzzioCallView { full, minimized, pip }

class JuzzioCallSession extends ChangeNotifier with WidgetsBindingObserver {
  JuzzioCallSession._();
  static final JuzzioCallSession instance = JuzzioCallSession._();

  static const MethodChannel _native = MethodChannel('juzzio/notifications');

  OverlayEntry? _entry;
  Completer<void>? _done;
  final GlobalKey<NavigatorState> _innerNav = GlobalKey<NavigatorState>();

  JuzzioCallView _view = JuzzioCallView.full;
  JuzzioCallView get view => _view;
  bool _inPip = false;

  /// Arama ekranının kaydettiği canlı denetleyici (küçük pencere görüntüsü için).
  DeepgramLiveKitController? controller;
  DateTime? startedAt;
  String title = '';
  String? avatarUrl;
  bool isVideo = false;

  /// Arama ekranının "kapat" eylemi (bildirimden kapatma için).
  Future<void> Function()? hangUp;

  bool get isActive => _entry != null;
  bool get isMinimized => _view == JuzzioCallView.minimized;

  // ---------------------------------------------------------------------------
  // Başlat / bitir
  // ---------------------------------------------------------------------------
  /// Arama ekranını gösterir; arama BİTTİĞİNDE tamamlanır (sayfa kapanınca değil).
  Future<void> start(
    BuildContext context, {
    required WidgetBuilder builder,
    required String title,
    String? avatarUrl,
    required bool isVideo,
  }) {
    if (isActive) return _done!.future;
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return Future.value();
    this.title = title;
    this.avatarUrl = avatarUrl;
    this.isVideo = isVideo;
    startedAt = DateTime.now();
    _view = JuzzioCallView.full;
    _inPip = false;
    _done = Completer<void>();
    _entry = OverlayEntry(builder: (_) => _JuzzioCallHost(session: this, builder: builder));
    overlay.insert(_entry!);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setNative(true));
    notifyListeners();
    return _done!.future;
  }

  /// Arama ekranı arama bitince çağırır.
  void finish() {
    final e = _entry;
    if (e == null) return;
    _entry = null;
    WidgetsBinding.instance.removeObserver(this);
    controller = null;
    hangUp = null;
    _view = JuzzioCallView.full;
    _inPip = false;
    try {
      e.remove();
    } catch (_) {}
    unawaited(_setNative(false));
    final d = _done;
    _done = null;
    if (d != null && !d.isCompleted) d.complete();
    notifyListeners();
  }

  Future<void> _setNative(bool active) async {
    try {
      await _native.invokeMethod('setCallActive', {'active': active, 'video': isVideo, 'title': title});
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------
  void minimize() {
    if (!isActive || _view == JuzzioCallView.minimized) return;
    // Arama içinde açık diyalog/sayfa varsa önce onlar kapanır
    _innerNav.currentState?.popUntil((r) => r.isFirst);
    _view = JuzzioCallView.minimized;
    _entry?.markNeedsBuild();
    notifyListeners();
  }

  void expand() {
    if (!isActive) return;
    _view = JuzzioCallView.full;
    _entry?.markNeedsBuild();
    notifyListeners();
  }

  /// Android PiP girişi/çıkışı (MainActivity.onPictureInPictureModeChanged).
  void setPip(bool inPip) {
    if (!isActive || _inPip == inPip) return;
    _inPip = inPip;
    _entry?.markNeedsBuild();
    notifyListeners();
  }

  bool get inPip => _inPip;

  /// "Arama sürüyor" bildirimindeki "Kapat".
  Future<void> hangUpFromNotification() async {
    final h = hangUp;
    if (h != null) {
      await h();
    } else {
      finish();
    }
  }

  // Geri tuşu: arama içindeki sayfayı kapatır, yoksa aramayı KÜÇÜLTÜR (kapatmaz)
  @override
  Future<bool> didPopRoute() async {
    if (!isActive || _view != JuzzioCallView.full || _inPip) return false;
    final nav = _innerNav.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    minimize();
    return true;
  }

  /// Süre metni (m:ss / h:mm:ss)
  String elapsedText() {
    final s = startedAt == null ? 0 : DateTime.now().difference(startedAt!).inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  VideoTrack? remoteVideoTrack() {
    final c = controller;
    if (c == null) return null;
    for (final p in c.remoteParticipants) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t is VideoTrack && !pub.muted) return t;
      }
    }
    return null;
  }

  /// Test için durum sıfırlama.
  @visibleForTesting
  void debugReset() {
    _entry = null;
    _done = null;
    _view = JuzzioCallView.full;
    _inPip = false;
  }

  /// Test edilebilir saf geri tuşu kararı.
  static String backDecision({required bool active, required JuzzioCallView view, required bool inPip, required bool innerCanPop}) {
    if (!active || view != JuzzioCallView.full || inPip) return 'pass';
    return innerCanPop ? 'pop_inner' : 'minimize';
  }
}

class _JuzzioCallHost extends StatefulWidget {
  const _JuzzioCallHost({required this.session, required this.builder});
  final JuzzioCallSession session;
  final WidgetBuilder builder;

  @override
  State<_JuzzioCallHost> createState() => _JuzzioCallHostState();
}

class _JuzzioCallHostState extends State<_JuzzioCallHost> {
  Offset? _pos;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.view != JuzzioCallView.full) setState(() {});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.session.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final full = s.view == JuzzioCallView.full && !s.inPip;
    // Arama ekranı HER ZAMAN ağaçta kalır (durum korunur); küçükken yalnız çizilmez
    final screen = Offstage(
      offstage: !full,
      child: TickerMode(
        enabled: full,
        child: HeroControllerScope.none(
          child: Navigator(
            key: s._innerNav,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (ctx, __, ___) => widget.builder(ctx),
              transitionDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    if (s.inPip) {
      return Stack(children: [screen, Positioned.fill(child: _CallCompactView(session: s, pip: true))]);
    }
    if (full) return screen;
    // Küçük, sürüklenebilir pencere (sağ alt). Yalnız pencere dokunuş alır; altı serbest.
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    const w = 112.0, h = 168.0;
    final pos = _pos ?? Offset(size.width - w - 14, size.height - h - pad.bottom - 96);
    return Stack(children: [
      screen,
      Positioned(
        left: pos.dx.clamp(8.0, size.width - w - 8),
        top: pos.dy.clamp(pad.top + 8, size.height - h - pad.bottom - 8),
        width: w,
        height: h,
        child: GestureDetector(
          onTap: s.expand,
          onPanUpdate: (d) => setState(() => _pos = (_pos ?? pos) + d.delta),
          onPanEnd: (_) => setState(() {
            // Kenara yapışır
            final p = _pos ?? pos;
            _pos = Offset(p.dx + w / 2 < size.width / 2 ? 14 : size.width - w - 14, p.dy);
          }),
          child: Semantics(
            button: true,
            label: JuzzioAppController.instance.trEn('Aramaya dön', 'Return to call', 'Zurück zum Anruf'),
            child: _CallCompactView(session: s, pip: false),
          ),
        ),
      ),
    ]);
  }
}

/// Küçük pencere / PiP içeriği: karşı tarafın görüntüsü ya da fotoğrafı + süre.
class _CallCompactView extends StatelessWidget {
  const _CallCompactView({required this.session, required this.pip});
  final JuzzioCallSession session;
  final bool pip;

  @override
  Widget build(BuildContext context) {
    final track = session.remoteVideoTrack();
    final radius = pip ? 0.0 : 22.0;
    final avatar = session.avatarUrl;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1C2333), Color(0xFF0E1118)],
            ),
            border: pip ? null : Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: pip ? null : const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (track != null)
              VideoTrackRenderer(track, fit: VideoViewFit.cover)
            else
              Center(
                child: CircleAvatar(
                  radius: pip ? 36 : 30,
                  backgroundColor: Colors.white24,
                  backgroundImage: (avatar != null && avatar.startsWith('http')) ? NetworkImage(avatar) : null,
                  child: (avatar == null || !avatar.startsWith('http'))
                      ? Text(
                          session.title.isNotEmpty ? session.title.characters.first.toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                        )
                      : null,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: Colors.black.withValues(alpha: 0.38),
                child: Row(children: [
                  const Icon(Icons.call_rounded, color: Color(0xFF4ADE80), size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      session.elapsedText(),
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
