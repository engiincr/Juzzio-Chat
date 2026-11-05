// JUZZIO v0.9.3 — çeviri parçalama, sesli mesaj süresi
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/screens/chat_screen.dart' show juzzioFormatVoiceDuration;
import 'package:juzzio/services/juzzio_backup_service.dart';
import 'package:juzzio/services/juzzio_call_session.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'dart:typed_data';
import 'package:juzzio/services/juzzio_beauty.dart';
import 'package:juzzio/widgets/juzzio_chick_art.dart';
import 'package:juzzio/widgets/juzzio_swipe_reply.dart';

void main() {
  test('uzun metin ≤ 450 karakterlik kayıpsız parçalara bölünür', () {
    final long = List.generate(40, (i) => 'Bu $i. cümle sesli mesaj dökümünden geliyor.').join(' ');
    final parts = splitForTranslation(long);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.length <= translationChunkMax), isTrue);
    expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), long.replaceAll(RegExp(r'\s+'), ' '));
    expect(splitForTranslation('x' * 1200).every((p) => p.length <= translationChunkMax), isTrue);
    expect(splitForTranslation('kısa'), ['kısa']);
  });

  test('servis hata metni çeviri sayılmaz', () {
    expect(isTranslationProviderError('QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS'), isTrue);
    expect(isTranslationProviderError('MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY'), isTrue);
    expect(isTranslationProviderError('Merhaba'), isFalse);
  });

  test('eski kayıttaki hata metni boş çeviri olarak okunur', () {
    final m = JuzzioMessage.fromMap({
      'id': '1', 'room_id': 'r', 'sender_id': 's', 'created_at': '2026-11-05T10:00:00Z',
      'original_text': 'merhaba', 'translated_text': 'QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS',
    });
    expect(m.translatedText, '');
  });

  test('sesli mesaj süresi biçimi', () {
    expect(juzzioFormatVoiceDuration(0), '0:00');
    expect(juzzioFormatVoiceDuration(9400), '0:09');
    expect(juzzioFormatVoiceDuration(75000), '1:15');
    expect(juzzioFormatVoiceDuration(3725000), '1:02:05');
    expect(juzzioFormatVoiceDuration(-5), '0:00');
  });

  test('çevrimdışı kuyruk yalnız ağ hatalarını bekletir', () {
    expect(SupabaseService.isNetworkError(const SocketException('Failed host lookup')), isTrue);
    expect(SupabaseService.isNetworkError(TimeoutException('x')), isTrue);
    expect(SupabaseService.isNetworkError(Exception('ClientException: Connection closed')), isTrue);
    expect(SupabaseService.isNetworkError(Exception('permission denied for table profiles')), isFalse);
    expect(SupabaseService.isNetworkError(Exception('new row violates row-level security')), isFalse);
  });

  test('önbellek adı güvenli', () {
    expect(SupabaseService.safeCacheName('posts_ab-1/../x'), 'posts_ab-1x');
  });

  test('arama sırasında geri tuşu aramayı kapatmaz, küçültür', () {
    String d({bool active = true, JuzzioCallView view = JuzzioCallView.full, bool pip = false, bool inner = false}) =>
        JuzzioCallSession.backDecision(active: active, view: view, inPip: pip, innerCanPop: inner);
    expect(d(), 'minimize');
    expect(d(inner: true), 'pop_inner');
    expect(d(view: JuzzioCallView.minimized), 'pass');
    expect(d(pip: true), 'pass');
    expect(d(active: false), 'pass');
  });

  test('arama oturumu başlangıçta etkin değil', () {
    expect(JuzzioCallSession.instance.isActive, isFalse);
    expect(JuzzioCallSession.instance.elapsedText(), '0:00');
  });

  test('Drive "erişim reddedildi" nedenleri ayrıştırılır', () {
    String d(int st, String reason) =>
        JuzzioBackupService.driveErrorCode(st, '{"error":{"errors":[{"reason":"$reason"}],"code":$st}}');
    expect(d(403, 'accessNotConfigured'), 'drive_api_disabled');
    expect(d(403, 'insufficientPermissions'), 'drive_scope_denied');
    expect(d(403, 'storageQuotaExceeded'), 'drive_full');
    expect(d(429, 'rateLimitExceeded'), 'drive_rate_limited');
    expect(JuzzioBackupService.driveErrorCode(401, ''), 'drive_auth_expired');
    expect(JuzzioBackupService.driveErrorCode(500, 'x'), 'drive_500');
  });

  test('Google giriş hataları ayrıştırılır', () {
    expect(JuzzioBackupService.signInErrorCode('sign_in_failed', 'com.google.android.gms.common.api.ApiException: 10: '), 'google_config');
    expect(JuzzioBackupService.signInErrorCode('sign_in_canceled', null), 'cancelled');
    expect(JuzzioBackupService.signInErrorCode('network_error', null), 'network');
    expect(JuzzioBackupService.signInErrorCode('sign_in_failed', 'ApiException: 12500'), 'google_access_denied');
  });

  test('sola yaylı kaydırma: genişliğe kadar doğrusal, sonrası dirençli ve sınırlı', () {
    expect(juzzioSwipeResistLeft(10, 96), 0);
    expect(juzzioSwipeResistLeft(-50, 96), -50);
    final far = juzzioSwipeResistLeft(-400, 96);
    expect(far, lessThan(-96));
    expect(far, greaterThan(-96 - 36));
    expect(juzzioSwipeResistLeft(-200, 96), greaterThan(juzzioSwipeResistLeft(-300, 96)));
  });

  test('bırakınca açık kalma kararı', () {
    expect(juzzioSwipeShouldOpen(-50, 96, 0), isTrue);
    expect(juzzioSwipeShouldOpen(-30, 96, 0), isFalse);
    expect(juzzioSwipeShouldOpen(-10, 96, -900), isTrue);
  });

  test('Civciv: yumurta sohbette yalnızca açken / davette görünür', () {
    bool v(String mood, {String cp = 'u2', bool inv = false, bool has = true}) => juzzioChickEggVisible(
        hasChick: has, mood: mood, chickPartnerId: cp, chatPartnerId: 'u2', hasIncomingInviteFromPartner: inv);
    expect(v('happy'), isFalse);
    expect(v('hungry'), isTrue);
    expect(v('dying'), isTrue);
    expect(v('hungry', cp: 'u3'), isFalse, reason: 'başka arkadaşla ortak civciv');
    expect(v('happy', has: false), isFalse);
    expect(v('happy', has: false, inv: true), isTrue);
  });

  test('Civciv: açlık seviyesi ve yüz ifadesi', () {
    expect(juzzioChickHungerLevel(0), 0);
    expect(juzzioChickHungerLevel(84), closeTo(0.5, 1e-9));
    expect(juzzioChickHungerLevel(500), 1);
    expect(JuzzioChickLook.forMood('happy').eyeOpen, 1);
    expect(JuzzioChickLook.forMood('hungry').beakOpen, 1);
    expect(JuzzioChickLook.forMood('dying').tears, isTrue);
  });

  test('Güzelleştirme: yoğunluk eşlemesi ve kenar koruma', () {
    final lo = JuzzioBeautyParams.forLevel(10);
    final hi = JuzzioBeautyParams.forLevel(100);
    expect(hi.alpha > lo.alpha, isTrue);
    expect(hi.threshold > lo.threshold, isTrue);
    expect(JuzzioBeautyParams.forLevel(500).alpha, 240);
    // 16x16: sol yarı 100, sağ yarı 200 (keskin kenar) + küçük doku gürültüsü
    const w = 16, h = 16;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (x < 8 ? 100 : 200) + ((x + y).isEven ? 3 : -3);
        final j = (y * w + x) * 4;
        px[j] = v; px[j + 1] = v; px[j + 2] = v; px[j + 3] = 255;
      }
    }
    expect(identical(juzzioBeautifyRgba(px, w, h, 0), px), isTrue, reason: '0 = kapalı');
    final out = juzzioBeautifyRgba(px, w, h, 80);
    int g(int x, int y) => out[(y * w + x) * 4 + 1];
    // Doku yumuşar: komşu farkı azalır
    expect((g(3, 4) - g(4, 4)).abs() < 6, isTrue);
    // Kenar korunur: iki taraf arasındaki ~100 fark büyük ölçüde kalır
    expect(g(9, 8) - g(6, 8) > 80, isTrue);
  });
}
