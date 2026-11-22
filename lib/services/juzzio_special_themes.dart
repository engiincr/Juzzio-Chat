// =============================================================================
// JUZZIO v2.2.0 — GM-029 / GM-031: Özel gün temaları
//  • Türk bayrağı teması: yönetici panelinden açılır; YALNIZ Türkiye'deki kullanıcılar görür.
//    Ülke: önce sunucunun bildirdiği bağlantı ülkesi (juzzio_my_country — giriş IP'sinin ülkesi),
//    sunucu yoksa cihazın bölge ayarı + Türkiye saat dilimi (UTC+3) birlikte.
//  • Halloween teması: yönetici panelinden açılır; tüm kullanıcılar görür.
//  İkisi de gece/gündüz ve TÜM temalarla çalışır. Etkinken hava katmanı çizilmez (dekoru örtmez).
//  Kullanıcı bu temaları kendisi açıp kapatamaz; karar yalnız app_settings'tedir.
// =============================================================================

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'juzzio_features_service.dart' show JuzzioAppConfig;
import 'supabase_service.dart';

enum JuzzioSpecialTheme { none, turkey, halloween }

/// Türkiye'deki kullanıcı mı? (saf; test edilir)
/// [serverCountry] biliniyorsa tek ölçüt odur; bilinmiyorsa bölge "TR" VE saat dilimi UTC+3 olmalı.
bool juzzioIsTurkeyUser({String? serverCountry, required String localeName, required Duration utcOffset}) {
  final cc = (serverCountry ?? '').trim().toUpperCase();
  if (cc.length == 2) return cc == 'TR';
  final loc = localeName.replaceAll('-', '_').toUpperCase();
  final region = loc.contains('_') ? loc.split('_')[1].split('.').first : '';
  return region == 'TR' && utcOffset == const Duration(hours: 3);
}

/// Hangi özel tema görünür? (saf; test edilir) — Türkiye'deki kullanıcıda bayrak önceliklidir.
JuzzioSpecialTheme juzzioResolveSpecialTheme({required bool turkeyOn, required bool halloweenOn, required bool turkeyUser}) {
  if (turkeyOn && turkeyUser) return JuzzioSpecialTheme.turkey;
  if (halloweenOn) return JuzzioSpecialTheme.halloween;
  return JuzzioSpecialTheme.none;
}

class JuzzioSpecialThemes extends ChangeNotifier {
  JuzzioSpecialThemes._();
  static final JuzzioSpecialThemes instance = JuzzioSpecialThemes._();

  bool _turkeyOn = false;
  bool _halloweenOn = false;
  String? _serverCountry;
  bool _countryAsked = false;
  JuzzioSpecialTheme _active = JuzzioSpecialTheme.none;

  JuzzioSpecialTheme get active => _force ?? _active;

  /// GM-037: yalnız hata ayıklama derlemesinde önizleme (yayında kullanılmaz)
  JuzzioSpecialTheme? _force;
  JuzzioSpecialTheme? get debugForced => _force;
  void debugForce(JuzzioSpecialTheme? t) {
    if (!kDebugMode) return;
    _force = t;
    notifyListeners();
  }
  bool get turkeyEnabled => _turkeyOn;
  bool get halloweenEnabled => _halloweenOn;

  /// Testler için: ülke bilgisini dışarıdan ver
  @visibleForTesting
  void debugSet({bool? turkeyOn, bool? halloweenOn, String? country}) {
    if (turkeyOn != null) _turkeyOn = turkeyOn;
    if (halloweenOn != null) _halloweenOn = halloweenOn;
    if (country != null) {
      _serverCountry = country;
      _countryAsked = true;
    }
    _recompute();
  }

  void applyConfig(JuzzioAppConfig cfg) {
    _turkeyOn = cfg.specialThemeTurkey;
    _halloweenOn = cfg.specialThemeHalloween;
    if (_turkeyOn && !_countryAsked) _askCountry();
    _recompute();
  }

  Future<void> _askCountry() async {
    _countryAsked = true;
    try {
      final r = await SupabaseService.instance.client.rpc('juzzio_my_country');
      final cc = (r ?? '').toString().trim().toUpperCase();
      if (cc.length == 2) _serverCountry = cc;
    } catch (_) {
      // sunucu işlevi yoksa (SQL 10.56 uygulanmadı) cihaz bölgesi + saat dilimi kullanılır
    }
    _recompute();
  }

  static String _localeName() {
    try {
      return Platform.localeName;
    } catch (_) {
      return '';
    }
  }

  void _recompute() {
    final next = juzzioResolveSpecialTheme(
      turkeyOn: _turkeyOn,
      halloweenOn: _halloweenOn,
      turkeyUser: juzzioIsTurkeyUser(serverCountry: _serverCountry, localeName: _localeName(), utcOffset: DateTime.now().timeZoneOffset),
    );
    if (next != _active) {
      _active = next;
      notifyListeners();
    }
  }
}
