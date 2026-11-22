// =============================================================================
// GM-014 — Juzzio'nun kendi geçici klasörü
//  Android/iOS'ta getTemporaryDirectory() zaten uygulamaya özeldir.
//  Windows/macOS/Linux'ta ise kullanıcının ORTAK geçici klasörüdür (%TEMP%): orada
//  "Önbelleği temizle" başka programların dosyalarını da siliyor, boyut da yanlış
//  (3–4 GB) görünüyordu. Masaüstünde tüm geçici dosyalar <TEMP>/Juzzio altına yazılır,
//  ölçüm ve temizlik yalnız bu klasörde yapılır.
// =============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Masaüstü mü (geçici klasör ortak mı)? Saf; test edilir.
bool juzzioTempIsShared({required bool isWeb, required String os}) =>
    !isWeb && (os == 'windows' || os == 'macos' || os == 'linux');

/// Uygulamanın geçici klasörü (masaüstünde `<TEMP>/Juzzio`, mobilde uygulama geçici klasörü).
Future<Directory> juzzioTempDir() async {
  final base = await getTemporaryDirectory();
  if (!juzzioTempIsShared(isWeb: kIsWeb, os: Platform.operatingSystem)) return base;
  final dir = Directory('${base.path}${Platform.pathSeparator}Juzzio');
  if (!dir.existsSync()) {
    try {
      dir.createSync(recursive: true);
    } catch (_) {
      return base;
    }
  }
  return dir;
}
