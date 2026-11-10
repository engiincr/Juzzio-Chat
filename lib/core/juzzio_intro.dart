// =============================================================================
// JUZZIO v1.2.7 — İlk giriş tanıtım videosu (20 sn, arka plan müziği ile)
//  Ne zaman gösterilir:
//   • Bu cihazda daha önce hiç gösterilmediyse (yeni yükleme). v1.2.7 güncellemesi gelince
//     mevcut kullanıcıların cihazında da işaret olmadığı için HERKES bir kez görür; işaret
//     kalıcı olduğundan sonraki güncellemelerde artık görünmez.
//   • Ya da hesap yeni açıldıysa (son 3 gün) ve bu hesap videoyu henüz görmediyse (eski bir
//     cihazda yeni hesap açan kişi de görür).
//  Video uygulamaya gömülüdür (assets/intro/…, TR ve EN) → internet gerekmez. "Atla" ile
//  geçilebilir. Yapımcı sayfasındaki "Uygulama Tanıtımı" düğmesiyle istenince tekrar izlenir.
//  Kaynak: tools/intro_video/intro.py (kareler kodla çizilir, ffmpeg ile kodlanır).
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/creator_reel_page.dart';
import '../services/supabase_service.dart';
import 'app_theme_and_locale.dart';

const String kJuzzioIntroAssetTr = 'assets/intro/juzzio_intro_tr.mp4';
const String kJuzzioIntroAssetEn = 'assets/intro/juzzio_intro_en.mp4';

/// Cihaz işaret dosyası (sürüm eki: tanıtım ileride yenilenirse _v2 ile herkese yeniden gösterilebilir)
const String kJuzzioIntroDeviceMarker = 'juzzio_intro_seen_v1';

/// Hesap düzeyi önbellek adı
const String kJuzzioIntroAccountCache = 'intro_seen_v1';

/// Hesap "yeni" sayılır: açılıştan bu yana en fazla bu kadar süre geçtiyse
const Duration kJuzzioIntroNewAccountWindow = Duration(days: 3);

/// Uygulama diline göre video (Türkçe → TR, diğer tüm diller → EN). Saf; test edilir.
String juzzioIntroAssetFor(String lang) => lang.toLowerCase().startsWith('tr') ? kJuzzioIntroAssetTr : kJuzzioIntroAssetEn;

/// Tanıtım gösterilmeli mi (saf; test edilir).
bool juzzioShouldShowIntro({
  required bool deviceSeen,
  required bool accountSeen,
  DateTime? accountCreatedAt,
  required DateTime now,
}) {
  if (!deviceSeen) return true;
  if (accountSeen || accountCreatedAt == null) return false;
  final age = now.difference(accountCreatedAt);
  return !age.isNegative && age <= kJuzzioIntroNewAccountWindow;
}

Future<File?> _marker() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$kJuzzioIntroDeviceMarker');
  } catch (_) {
    return null;
  }
}

bool _shownThisRun = false;

/// Gerekirse tanıtımı tam ekran oynatır ve işaretler. Hata olursa sessizce geçer.
Future<void> juzzioMaybeShowIntro(BuildContext context) async {
  if (_shownThisRun) return;
  try {
    final f = await _marker();
    final deviceSeen = f == null || await f.exists(); // dosya sistemi yoksa gösterme
    final acc = await SupabaseService.instance.readLocalCache(kJuzzioIntroAccountCache);
    final accountSeen = acc == true;
    final created = DateTime.tryParse(Supabase.instance.client.auth.currentUser?.createdAt ?? '');
    if (!juzzioShouldShowIntro(deviceSeen: deviceSeen, accountSeen: accountSeen, accountCreatedAt: created, now: DateTime.now())) {
      return;
    }
    _shownThisRun = true;
    // önce işaretle: video yarıda kapansa/uygulama çökse de bir daha zorla gösterilmez
    try {
      await f?.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (_) {}
    await SupabaseService.instance.writeLocalCache(kJuzzioIntroAccountCache, true);
    if (!context.mounted) return;
    final app = JuzzioAppController.instance;
    await JuzzioCreatorReelPage.open(
      context,
      asset: juzzioIntroAssetFor(app.uiLang),
      title: app.trEn('Juzzio\'ya hoş geldin', 'Welcome to Juzzio', 'Willkommen bei Juzzio'),
      isIntro: true,
    );
  } catch (_) {
    // tanıtım isteğe bağlıdır; hiçbir hata uygulamanın açılışını engellemez
  }
}
