// JUZZIO v1.2.8 — güvenlik, Sinema Parti, canlı çeviri, medya, PIN, hava teması, egress
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/screens/social/juzzio_creator_studio.dart' show juzzioClampPostRatio, juzzioRatioLabel;
import 'package:juzzio/screens/watch_party_screen.dart';
import 'package:juzzio/services/deepgram_livekit_service.dart' show juzzioCaptionEngineLabel;
import 'package:juzzio/services/juzzio_chat_lock.dart';
import 'package:juzzio/services/juzzio_translation_memory.dart';
import 'package:juzzio/services/juzzio_video_compress.dart';
import 'package:juzzio/services/juzzio_weather_service.dart';
import 'package:juzzio/services/supabase_service.dart' show juzzioDeepgramErrorReason, juzzioShouldPrefetch;
import 'package:juzzio/widgets/juzzio_weather_ambience.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('Sinema Parti', () {
    test('her bağlantı türü tanınır', () {
      expect(juzzioWatchKindOf('https://youtu.be/HziuStFGhRE'), 'youtube');
      expect(juzzioWatchKindOf('https://www.youtube.com/watch?v=HziuStFGhRE&t=3'), 'youtube');
      expect(juzzioWatchKindOf('https://www.fullhdfilmizlesene.now/film/can-dostumun-mukemmel-noeli-a-dogs-perfect-christmas/'), 'web');
      expect(juzzioWatchKindOf('https://x.com/a/master.m3u8?token=1'), 'hls');
      expect(juzzioWatchKindOf('https://x.com/a.mp4'), 'direct');
    });
    test('YouTube kimliği', () {
      expect(juzzioYoutubeId('https://youtu.be/HziuStFGhRE'), 'HziuStFGhRE');
      expect(juzzioYoutubeId('https://m.youtube.com/shorts/HziuStFGhRE'), 'HziuStFGhRE');
      expect(juzzioYoutubeId('https://example.com/watch?v=HziuStFGhRE'), isNull);
    });
    test('eşitleme toleransı', () {
      expect(juzzioWatchNeedsSeek(10000, 10800), isFalse);
      expect(juzzioWatchNeedsSeek(10000, 12000), isTrue);
    });
    test('eşitleme betiği tüm çerçevelere eklenir ve videoyu bulur', () {
      expect(kJuzzioWatchSyncJs.contains("getElementsByTagName('video')"), isTrue);
      expect(kJuzzioWatchSyncJs.contains("callHandler('jzwp'"), isTrue);
      final s = _src('lib/screens/watch_party_screen.dart');
      expect(s.contains('forMainFrameOnly: false'), isTrue);
      expect(s.contains('senkron oynatılamaz'), isFalse); // eski hata metni yok
      expect(s.contains("watch_party_full"), isTrue);
      expect(s.contains('isSpeaking'), isTrue); // konuşan yeşil halka
      expect(s.contains('Icons.mic_off_rounded'), isTrue); // mikrofon kapalı simgesi
    });
    test('sohbette KATIL kartı', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains("msg.metadata['kind'] == 'watch_party'"), isTrue);
      expect(c.contains("'KATIL'"), isTrue);
    });
  });

  group('Canlı çeviri / Deepgram', () {
    test('hata nedeni', () {
      expect(juzzioDeepgramErrorReason('FunctionException(status: 503, details: {error: deepgram_not_configured})'), 'no_key');
      expect(juzzioDeepgramErrorReason('no_active_call'), 'no_active_call');
      expect(juzzioDeepgramErrorReason('SocketException: Failed host lookup'), 'network');
    });
    test('motor etiketi', () {
      String loc(String tr, String en, String de) => tr;
      expect(juzzioCaptionEngineLabel('deepgram', '', loc), contains('Deepgram'));
      expect(juzzioCaptionEngineLabel('device', 'no_key', loc), contains('anahtar'));
      expect(juzzioCaptionEngineLabel('off', '', loc), '');
    });
    test('dil ayarı yanlış olsa da altyazı başlar; cihaz tanıyıcısı yedek', () {
      final s = _src('lib/services/deepgram_livekit_service.dart');
      expect(s.contains('if (!force && remoteParticipants.isEmpty) return;'), isTrue);
      expect(s.contains("invokeMethod('speechStart'"), isTrue);
      expect(s.contains('onDone: _onDeepgramClosed'), isTrue);
      expect(File('android/app/src/main/kotlin/com/juzzio/app/JuzzioSpeech.kt').existsSync(), isTrue);
    });
    test('çeviri hafızası anahtarı ve kelime çıkarma', () {
      expect(juzzioTmKey('auto', 'EN', '  Merhaba   dünya '), 'auto|en|merhaba dünya');
      final v = juzzioVocabularyFrom(['Hello there', 'hello again', 'there we go']);
      expect(v.first, anyOf('hello', 'there'));
      expect(v, isNot(contains('a')));
    });
  });

  group('Medya', () {
    test('video sıkıştırma kararı (720p / 6 MB)', () {
      expect(juzzioVideoNeedsCompression(width: 1920, height: 1080, bytes: 2 << 20), isTrue);
      expect(juzzioVideoNeedsCompression(width: 1280, height: 720, bytes: 3 << 20), isFalse);
      expect(juzzioVideoNeedsCompression(width: 640, height: 360, bytes: 12 << 20), isTrue);
    });
    test('fotoğraf kırpılmaz, titreme yok, indir düğmesi var', () {
      final c = _src('lib/screens/chat_screen.dart');
      expect(c.contains('JuzzioEncryptedImage(messageId: msg.id, url: msg.imageUrl!, fit: BoxFit.contain)'), isTrue);
      expect(c.contains("app.trEn('İndir', 'Download', 'Herunterladen')"), isTrue);
      final e = _src('lib/widgets/juzzio_encrypted_image.dart');
      expect(e.contains('class JuzzioEncryptedImage extends StatefulWidget'), isTrue);
      expect(e.contains('JuzzioDownloadAction'), isTrue);
      expect(_src('lib/widgets/media_viewer.dart').contains('JuzzioDownloadAction'), isTrue);
    });
    test('gönderi oranı otomatik (9:16 dahil)', () {
      expect(juzzioClampPostRatio(9 / 16), closeTo(0.5625, 1e-9));
      expect(juzzioClampPostRatio(3.0), 1.91);
      expect(juzzioRatioLabel(9 / 16), '9:16');
      expect(juzzioRatioLabel(16 / 9), '16:9');
    });
    test('egress: ön yükleme yalnız Wi-Fi ve veri tasarrufu kapalıyken', () {
      expect(juzzioShouldPrefetch(unmetered: true, dataSaver: false), isTrue);
      expect(juzzioShouldPrefetch(unmetered: false, dataSaver: false), isFalse);
      expect(juzzioShouldPrefetch(unmetered: true, dataSaver: true), isFalse);
      expect(_src('lib/services/juzzio_media_cache.dart').contains('_tooBig'), isTrue);
    });
  });

  test('kilitli sohbet: varsayılan PIN 0000', () async {
    JuzzioChatLock.memoryStore = <String, String>{};
    final lock = JuzzioChatLock.instance;
    await lock.reset();
    expect(await lock.hasPin(), isFalse);
    expect(await lock.unlock(JuzzioChatLock.defaultPin), isTrue);
    await lock.setPin('482913');
    expect(await lock.pinLength(), 6);
    lock.relock();
    expect(await lock.unlock('0000'), isFalse);
    expect(await lock.unlock('482913'), isTrue);
    await lock.reset();
    JuzzioChatLock.memoryStore = null;
  });

  group('Hava teması', () {
    test('yalnız ana ekranda görünür', () {
      expect(juzzioAmbienceVisibleForPages(1), isTrue);
      expect(juzzioAmbienceVisibleForPages(2), isFalse);
      expect(_src('lib/main.dart').contains('JuzzioAmbienceRouteObserver.instance'), isTrue);
    });
    test('yağmurda şimşek, yavaş geçiş', () {
      expect(juzzioWeatherHasLightning(JuzzioWeatherKind.rain), isTrue);
      expect(juzzioWeatherHasLightning(JuzzioWeatherKind.clear), isFalse);
      expect(kJuzzioWeatherCrossfade.inSeconds, greaterThanOrEqualTo(10));
    });
  });

  test('küresel akış SQL güncellemesinde kapanmaz', () {
    final sql = _src('supabase/juzzio_database.sql');
    expect(sql.contains("('global_feed_enabled', 'false'::jsonb)\nON CONFLICT (key) DO UPDATE"), isFalse);
  });

  test('profil müziği sayfa değişince durur; hikâyede müzik baştan', () {
    expect(_src('lib/widgets/profile_extras.dart').contains('class JuzzioMusicRouteObserver'), isTrue);
    expect(_src('lib/screens/chat_screen.dart').contains("ValueKey<String>('story_music_\${st.id}')"), isTrue);
  });

  test('v1.2.8 sürüm notu en üstte', () {
    final n = kJuzzioBundledReleaseNotes.first;
    expect(n.versionName, '1.2.8');
    expect(n.versionCode, 128);
  });
}
