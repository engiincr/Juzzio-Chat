// =============================================================================
// JUZZIO v0.9.6 — Otomatik hata / çökme bildirimi (Yönetici → Sistem → Hatalar)
//  • FlutterError.onError + PlatformDispatcher.onError ile yakalanan istisnalar,
//    yığın izi (stack trace) ile birlikte `report_app_error` RPC'sine gönderilir.
//  • Aynı hata (parmak izi + sürüm) sunucuda tek satırda toplanır; sayaç artar.
//  • Gizlilik: mesaj metni, e-posta, telefon, uzun sayı dizileri, belirteçler ve
//    URL sorgu parametreleri istemcide maskelenir. Kullanıcı Ayarlar'dan kapatabilir;
//    yönetici `error_reporting_enabled` bayrağıyla tümden durdurabilir.
//  • Sınırlar: oturum başına en fazla 20 rapor, aynı parmak izi 60 sn'de bir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'supabase_service.dart';

/// Hassas bilgileri maskeler (test edilebilir saf fonksiyon).
String juzzioScrubErrorText(String input, {int maxLength = 1000}) {
  var s = input;
  s = s.replaceAll(RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>');
  s = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'), '<jwt>');
  s = s.replaceAllMapped(RegExp(r'(bearer|token|apikey|api_key|password|secret)\s*[:=]\s*\S+', caseSensitive: false),
      (m) => '${m.group(1)}=<redacted>');
  s = s.replaceAllMapped(RegExp(r'(https?://[^\s?#]+)\?[^\s#]*'), (m) => '${m.group(1)}?<q>');
  s = s.replaceAll(RegExp(r'\+?\d[\d \-]{8,}\d'), '<number>');
  if (s.length > maxLength) s = s.substring(0, maxLength);
  return s;
}

/// Hata parmak izi: tür + uygulama içi ilk 3 yığın çerçevesi (satır numaraları hariç).
String juzzioErrorFingerprint(String errorType, String stack) {
  final frames = stack
      .split('\n')
      .where((l) => l.contains('package:juzzio') || l.contains('lib/'))
      .take(3)
      .map((l) => l.replaceAll(RegExp(r':\d+(:\d+)?'), '').replaceAll(RegExp(r'^#\d+\s+'), '').trim())
      .join('|');
  final basis = '$errorType|${frames.isEmpty ? stack.split('\n').take(2).join('|') : frames}';
  final bytes = const DartSha256().hashSync(utf8.encode(basis)).bytes;
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 32);
}

class JuzzioErrorReporter {
  JuzzioErrorReporter._();
  static final JuzzioErrorReporter instance = JuzzioErrorReporter._();

  /// Kullanıcı tercihi (Ayarlar → Gizlilik → "Hata raporlarını otomatik gönder").
  bool userEnabled = true;

  /// Sunucu bayrağı (Yönetici → Ayarlar → error_reporting_enabled).
  bool serverEnabled = true;

  int _sentThisSession = 0;
  final Map<String, DateTime> _lastSent = {};
  bool _installed = false;

  static const int _maxPerSession = 20;

  void install() {
    if (_installed) return;
    _installed = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previous != null) previous(details);
      unawaited(report(details.exception, details.stack ?? StackTrace.empty,
          context: details.library ?? 'flutter', fatal: false));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack, context: 'platform_dispatcher', fatal: true));
      return true; // işlendi: uygulama kapanmaz
    };
  }

  Future<void> report(Object error, StackTrace stack, {String context = '', bool fatal = false}) async {
    try {
      if (!userEnabled || !serverEnabled) return;
      if (_sentThisSession >= _maxPerSession) return;
      final svc = SupabaseService.instance;
      if (svc.currentUserId == null) return;
      final type = error.runtimeType.toString();
      final stackText = stack.toString();
      // Ağ kesintileri ve iptal edilen istekler hata merkezini doldurmasın
      if (error is SocketException || error is TimeoutException || error is HttpException) return;
      final fp = juzzioErrorFingerprint(type, stackText);
      final last = _lastSent[fp];
      final now = DateTime.now();
      if (last != null && now.difference(last) < const Duration(seconds: 60)) return;
      _lastSent[fp] = now;
      _sentThisSession++;
      await svc.client.rpc('report_app_error', params: {
        'p_fingerprint': fp,
        'p_error_type': type,
        'p_message': juzzioScrubErrorText(error.toString()),
        'p_stack': juzzioScrubErrorText(stackText, maxLength: 8000),
        'p_app_version': '${JuzzioConfig.appVersion}+${JuzzioConfig.appVersionCode}',
        'p_platform': kIsWeb ? 'web' : Platform.operatingSystem,
        'p_context': juzzioScrubErrorText(context, maxLength: 200),
        'p_fatal': fatal,
        'p_device_info': kIsWeb ? '' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim(),
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Raporlayıcı asla yeni bir hata üretmez
    }
  }
}
