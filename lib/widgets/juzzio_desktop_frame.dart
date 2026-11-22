// =============================================================================
// JUZZIO v1.3.2 — Windows / masaüstü çerçevesi
//
//  Juzzio telefon için tasarlandı. Geniş bir Windows penceresinde sayfalar yatayda 1200+ piksele
//  yayılıyor, giriş formu ve düğmeler dağınık görünüyordu. Bu çerçeve:
//   • Dar pencerede (≤ [kJuzzioDesktopFullBleed]) hiçbir şey yapmaz: uygulama pencereyi doldurur.
//   • Geniş pencerede içeriği ortada, okunaklı genişlikte, yuvarlak köşeli bir panelde gösterir;
//     çevresi etkin temanın derin zemin gradyanıyla dolar. MediaQuery boyutu da panele çekilir, böylece
//     ekran genişliğine göre çizilen sayfalar, açılır pencereler ve alt menüler panele göre ölçeklenir.
//   • Telefonda (Android/iOS) ve web'de devre dışıdır.
// =============================================================================

import 'dart:io' show Platform;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_call_session.dart';
import 'juzzio_desktop_shell.dart' show kJuzzioDesktopThreePanelMin;

/// Bu genişliğin altında uygulama pencereyi tam doldurur.
const double kJuzzioDesktopFullBleed = 600;

/// Geniş pencerede panelin en fazla genişliği.
const double kJuzzioDesktopPanelWidth = 560;

bool get juzzioIsDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Panel ölçüsü (saf; test edilir). null → tam pencere.
Size? juzzioDesktopPanelSize(Size window) {
  if (window.width <= kJuzzioDesktopFullBleed) return null;
  final w = kJuzzioDesktopPanelWidth.clamp(0.0, window.width - 32).toDouble();
  final vPad = window.height >= 760 ? 20.0 : 0.0;
  return Size(w, window.height - vPad * 2);
}

/// GM-006: Kendi masaüstü düzenini kuran sayfaların (sohbet ana ekranı → 3 panel) rotası.
/// Bu rota en üstteki TAM SAYFA rota olduğunda çerçeve pencereyi daraltmaz; diyalog/alt menü
/// (PopupRoute) açıkken karar değişmez, böylece düzen sıçramaz.
class JuzzioDesktopFrameObserver extends NavigatorObserver {
  JuzzioDesktopFrameObserver._();
  static final JuzzioDesktopFrameObserver instance = JuzzioDesktopFrameObserver._();

  /// true → çerçeve devre dışı (sayfa pencerenin tamamını kendisi yönetir)
  final ValueNotifier<bool> fullWindow = ValueNotifier<bool>(false);
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  Route<dynamic>? _fullWindowRoute;

  /// Kendi masaüstü düzeni olan sayfa, kendi rotasını bildirir (null → kaydı kaldır).
  void registerFullWindowRoute(Route<dynamic>? route) {
    _fullWindowRoute = route;
    _update();
  }

  void _update() {
    Route<dynamic>? topPage;
    for (final r in _stack.reversed) {
      if (r is! PopupRoute) {
        topPage = r;
        break;
      }
    }
    final v = _fullWindowRoute != null && identical(topPage, _fullWindowRoute);
    if (fullWindow.value != v) fullWindow.value = v;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        _stack[i] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    } else if (i >= 0) {
      _stack.removeAt(i);
    }
    _update();
  }
}

class JuzzioDesktopFrame extends StatelessWidget {
  const JuzzioDesktopFrame({super.key, required this.child, this.enabled});

  final Widget child;

  /// Testler için zorlama; null → yalnız masaüstünde etkin.
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? juzzioIsDesktop)) return child;
    // GM-006: sohbet ana ekranı en üstteyken pencerenin tamamı 3 panel düzenine bırakılır
    final obs = JuzzioDesktopFrameObserver.instance;
    final call = JuzzioActiveCall.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([obs.fullWindow, call]),
      // 3 panel düzeni ≥ kJuzzioDesktopThreePanelMin genişlikte açılır; daha dar pencerede çerçeve sürer.
      // GM-9276: tam ekran arama (küçültülmemiş) da pencerenin tamamını kullanır (masaüstü arama düzeni).
      builder: (context, _) {
        final full = obs.fullWindow.value || (call.isActive && call.view == JuzzioCallView.full);
        return full && MediaQuery.sizeOf(context).width >= kJuzzioDesktopThreePanelMin ? child : _framed(context);
      },
    );
  }

  Widget _framed(BuildContext context) {
    final mq = MediaQuery.of(context);
    final panel = juzzioDesktopPanelSize(mq.size);
    if (panel == null) return child;
    final depth = JuzzioGlassTokens.space;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? depth.depth : depth.depthLight;
    final radius = BorderRadius.circular(panel.height < mq.size.height ? 26 : 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: bg),
      ),
      child: Center(
        child: Container(
          width: panel.width,
          height: panel.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: JuzzioGlassTokens.spaceCardBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14), blurRadius: 40, offset: const Offset(0, 18)),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: MediaQuery(
              data: mq.copyWith(
                size: panel,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Masaüstünde fare ve dokunmatik yüzeyle sürükleyerek kaydırma + görünür kaydırma çubukları.
class JuzzioScrollBehavior extends MaterialScrollBehavior {
  const JuzzioScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
