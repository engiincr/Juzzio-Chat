// =============================================================================
// JUZZIO v1.2.4 — Arayüz dili canlı senkronu
//  Metinler JuzzioAppController.trEn/loc/t ile üretildiği için yalnız denetleyiciyi
//  dinleyen bileşenler kendini yeniliyordu; açık sayfalar (yönetici paneli, ayarlar,
//  açılır pencereler, kayıt/giriş ekranındaki politika metinleri) eski dilde kalabiliyordu.
//  Bu yardımcı, dil değiştiğinde ya da arka planda yeni çeviriler geldiğinde ağaçtaki TÜM
//  öğeleri bir kez yeniden çizdirir (durum korunur; gezinme yığını bozulmaz).
//  Arka arkaya gelen çeviriler 350 ms içinde tek yeniden çizime toplanır.
// =============================================================================

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_theme_and_locale.dart';

/// Ağaçtaki her öğeyi yeniden çizilmek üzere işaretler (yapı korunur).
void juzzioRebuildAllElements() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
}

class JuzzioUiSync {
  JuzzioUiSync._();

  static bool _attached = false;
  static String _lastLang = '';
  static int _lastRevision = -1;
  static Timer? _debounce;

  /// Dil ya da metin sürümü değişti mi (saf; test edilir)
  static bool shouldRebuild({required String lang, required int revision, required String lastLang, required int lastRevision}) =>
      lang != lastLang || revision != lastRevision;

  static void attach() {
    if (_attached) return;
    _attached = true;
    final c = JuzzioAppController.instance;
    _lastLang = c.uiLang;
    _lastRevision = c.uiTextRevision;
    c.addListener(() {
      if (!shouldRebuild(lang: c.uiLang, revision: c.uiTextRevision, lastLang: _lastLang, lastRevision: _lastRevision)) return;
      final langChanged = c.uiLang != _lastLang;
      _lastLang = c.uiLang;
      _lastRevision = c.uiTextRevision;
      _debounce?.cancel();
      // dil değişimi hemen; arka planda gelen çeviriler toplu
      _debounce = Timer(langChanged ? Duration.zero : const Duration(milliseconds: 350), () {
        WidgetsBinding.instance.addPostFrameCallback((_) => juzzioRebuildAllElements());
        WidgetsBinding.instance.scheduleFrame();
      });
    });
  }
}
