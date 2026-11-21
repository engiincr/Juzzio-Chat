// Juzzio 2.1 (Faz 9.4) — "Verilerimi indir" (KVKK m.11 · GDPR m.15/20)
// Sunucudaki juzzio_export_my_data() yalnız çağıranın kendi verisini döndürür.
// Android'de İndirilenler/Juzzio, masaüstünde İndirilenler, iOS'ta uygulama Belgeler klasörüne kaydedilir.
// Mesaj içerikleri uçtan uca şifreli olduğu için dosyaya konmaz.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/native_bridge.dart';

/// Dosya adı: Juzzio_verilerim_2026-11-21.json (saf; test edilir)
String juzzioExportFileName(DateTime now) =>
    'Juzzio_verilerim_${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';

Future<void> juzzioExportMyData(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
  if (kIsWeb) {
    say(app.trEn('Bu işlem uygulamada yapılabilir.', 'Available in the app.', 'In der App verfügbar.'));
    return;
  }
  say(app.trEn('Verilerin hazırlanıyor…', 'Preparing your data…', 'Daten werden vorbereitet…'));
  try {
    final data = await Supabase.instance.client.rpc('juzzio_export_my_data');
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name = juzzioExportFileName(DateTime.now());
    var ok = false;
    String? savedTo;
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      ok = await JuzzioNative.saveToGallery(path: f.path, mime: 'application/json', name: name, kind: 'document');
      try {
        await f.delete();
      } catch (_) {}
    } else {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsBytes(bytes, flush: true);
      savedTo = f.path;
      ok = true;
    }
    say(ok
        ? app.trEn('Verilerin kaydedildi: ${savedTo ?? 'İndirilenler/Juzzio/$name'}', 'Your data was saved: ${savedTo ?? 'Downloads/Juzzio/$name'}',
            'Deine Daten wurden gespeichert: ${savedTo ?? 'Downloads/Juzzio/$name'}')
        : app.trEn('Dosya kaydedilemedi', 'Could not save the file', 'Datei konnte nicht gespeichert werden'));
  } on PostgrestException catch (e) {
    say(e.message.contains('rate_limited')
        ? app.trEn('Bugün en çok 3 kez indirebilirsin. Yarın tekrar dene.', 'You can download at most 3 times a day.', 'Höchstens 3-mal pro Tag.')
        : app.trEn('Veriler alınamadı. Tekrar dene.', 'Could not get your data. Try again.', 'Daten nicht verfügbar. Erneut versuchen.'));
  } catch (_) {
    say(app.trEn('Veriler alınamadı. Tekrar dene.', 'Could not get your data. Try again.', 'Daten nicht verfügbar. Erneut versuchen.'));
  }
}
