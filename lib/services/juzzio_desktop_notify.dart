// =============================================================================
// JUZZIO v1.3.2 — Windows (masaüstü) bildirimleri
//
//  Telefonda bildirimler FCM + Android yerel koduyla gelir; ikisi de Windows'ta yoktur. Uygulama
//  açıkken gelen mesaj ve aramalar zaten Supabase Realtime ile dinleniyor; bu servis onları Windows'un
//  yerel bildirimi (toast) olarak gösterir. Uçtan uca şifreli içerik bildirime YAZILMAZ: yalnız gönderen
//  adı ve "Yeni mesaj" / "Gelen arama". Bildirime tıklayınca pencere öne gelir ve ilgili işlem çalışır.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../widgets/juzzio_desktop_frame.dart';

class JuzzioDesktopNotify {
  JuzzioDesktopNotify._();
  static final JuzzioDesktopNotify instance = JuzzioDesktopNotify._();

  bool _ready = false;
  final Map<String, DateTime> _lastByKey = {};

  Future<void> _ensure() async {
    if (_ready || !juzzioIsDesktop) return;
    try {
      await localNotifier.setup(appName: 'Juzzio', shortcutPolicy: ShortcutPolicy.requireCreate);
      _ready = true;
    } catch (e) {
      debugPrint('Desktop notify setup failed: $e');
    }
  }

  /// [key] aynı sohbet/arama için 4 sn içinde tekrar bildirim çıkmasını önler.
  Future<void> show({required String key, required String title, required String body, VoidCallback? onTap}) async {
    if (!juzzioIsDesktop) return;
    final now = DateTime.now();
    final last = _lastByKey[key];
    if (last != null && now.difference(last) < const Duration(seconds: 4)) return;
    _lastByKey[key] = now;
    if (_lastByKey.length > 200) _lastByKey.clear();
    await _ensure();
    if (!_ready) return;
    try {
      final n = LocalNotification(identifier: key, title: title, body: body);
      if (onTap != null) n.onClick = onTap;
      await n.show();
    } catch (e) {
      debugPrint('Desktop notify failed: $e');
    }
  }
}
