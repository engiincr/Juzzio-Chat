// =============================================================================
// JUZZIO — Android yerel köprüsü (paylaşım menüsü vb.)
// =============================================================================

import 'dart:async';

import 'package:flutter/services.dart';

class JuzzioNative {
  JuzzioNative._();

  static const MethodChannel _channel = MethodChannel('juzzio/notifications');

  /// v0.8.2: cihaz profili — düşük RAM (Android isLowRamDevice veya < 3 GB) ise true
  static Future<bool> isLowEndDevice() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('deviceProfile');
      if (res is Map) {
        final low = res['lowRam'] == true;
        final mem = res['totalMemMb'] is num ? (res['totalMemMb'] as num).toInt() : 0;
        return low || (mem > 0 && mem < 3072);
      }
    } catch (_) {}
    return false;
  }

  /// Sistem paylaşım menüsünü açar (WhatsApp, Instagram, SMS ...). Başarısızsa false.
  static Future<bool> shareText(String text, {String title = 'Juzzio'}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareText', {'text': text, 'title': title});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Yerel video dosyasından belirtilen anlardaki kareleri JPEG olarak çıkarır
  /// (kırpıcı zaman çizelgesi ve otomatik kapak için). Android dışı veya hata → boş.
  static Future<JuzzioVideoFrames> videoFrames(
    String path, {
    required List<int> timesMs,
    int maxWidth = 240,
    int quality = 78,
  }) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('videoFrames', {
        'path': path,
        'timesMs': timesMs,
        'maxWidth': maxWidth,
        'quality': quality,
      });
      if (res is Map) {
        final frames = (res['frames'] is List)
            ? (res['frames'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final dur = (res['durationMs'] is num) ? (res['durationMs'] as num).toInt() : 0;
        return JuzzioVideoFrames(frames, dur);
      }
    } catch (_) {}
    return const JuzzioVideoFrames(<String>[], 0);
  }

  // ---------------------------------------------------------------------------
  // v0.6: Glassmorphism ana ekran widget'ı
  // ---------------------------------------------------------------------------
  static final StreamController<String> _widgetActions = StreamController<String>.broadcast();

  /// Widget'taki hızlı eylemler: chats | camera | global | calls
  static Stream<String> get widgetActions => _widgetActions.stream;

  static void emitWidgetAction(String action) {
    if (action.isNotEmpty) _widgetActions.add(action);
  }

  /// Uygulama widget'tan açıldıysa bekleyen eylemi döndürür (bir kez).
  static Future<String?> takePendingWidgetAction() async {
    try {
      return await _channel.invokeMethod<String>('getWidgetAction');
    } catch (_) {
      return null;
    }
  }

  static String _lastWidgetSignature = '';

  /// Widget verisini günceller (yalnızca değiştiğinde yerel tarafa yazılır).
  static Future<void> updateHomeWidget({
    required int unread,
    required String lastName,
    required String lastText,
    required String userName,
    required String palette,
    required String lang,
    bool dark = true,
    String recentJson = '[]',
    String lastCallJson = '',
  }) async {
    final signature = '$unread|$lastName|$lastText|$userName|$palette|$lang|$dark|$recentJson|$lastCallJson';
    if (signature == _lastWidgetSignature) return;
    _lastWidgetSignature = signature;
    try {
      await _channel.invokeMethod<bool>('updateHomeWidget', {
        'unread': unread,
        'lastName': lastName,
        'lastText': lastText,
        'userName': userName,
        'palette': palette,
        'lang': lang,
        'dark': dark,
        'recent': recentJson,
        'lastCall': lastCallJson,
      });
    } catch (_) {}
  }

  /// v0.7.0: Sahip olunmayan bir alan adına (juzzio.app) yönlendirme kaldırıldı;
  /// paylaşılan bağlantı resmi indirme sayfasına gider, kullanıcı adı parametrede taşınır.
  static String profileLink(String username) =>
      'https://github.com/engiincr/Juzzio-Chat/releases/latest?u=${Uri.encodeQueryComponent(username.replaceAll('@', ''))}';
}

class JuzzioVideoFrames {
  final List<String> paths;
  final int durationMs;
  const JuzzioVideoFrames(this.paths, this.durationMs);
}
