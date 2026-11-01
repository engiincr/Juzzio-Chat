// JUZZIO v0.4.0 — içerik stüdyosu (filtre, kırpma, müzik) model testleri.

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/models/social_models.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_video_kit.dart';
import 'package:juzzio/widgets/profile_extras.dart';

void main() {
  test('Her filtre geçerli 4x5 renk matrisi üretir, "none" filtresizdir', () {
    expect(JuzzioMediaFilters.matrixFor('none'), isNull);
    for (final p in JuzzioMediaFilters.presets) {
      if (p.id == 'none') continue;
      final m = JuzzioMediaFilters.matrixFor(p.id);
      expect(m, isNotNull, reason: p.id);
      expect(m!.length, 20, reason: p.id);
      expect(m.every((v) => v.isFinite), isTrue, reason: p.id);
      // Alfa kanalı korunur
      expect(m[18], closeTo(1.0, 1e-9), reason: p.id);
    }
  });

  test('Gönderi klip kırpma bilgisi ve hız okunur', () {
    final post = JuzzioPost.fromMap({
      'id': 'p1',
      'author_id': 'u1',
      'author_username': 'deneme',
      'content_type': 'reel',
      'media_urls': ['https://x.co/a.mp4', 'https://x.co/b.mp4'],
      'playback_speed': 1.5,
      'is_muted': true,
      'music_url': 'https://youtu.be/dQw4w9WgXcQ',
      'music_start_sec': 42,
      'clip_meta': [
        {'start_ms': 1000, 'end_ms': 5000},
        {'start_ms': 0, 'end_ms': 0},
      ],
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(post.isReel, isTrue);
    expect(post.playbackSpeed, 1.5);
    expect(post.isMuted, isTrue);
    expect(post.musicStartSec, 42);
    expect(post.trimForMedia(0).startMs, 1000);
    expect(post.trimForMedia(0).endMs, 5000);
    expect(post.trimForMedia(1).endMs, 0);
    expect(post.trimForMedia(5).startMs, 0);
    expect(JuzzioPost.looksLikeVideoUrl('https://x.co/a.MP4?token=1'), isTrue);
    expect(JuzzioPost.looksLikeVideoUrl('https://x.co/a.jpg'), isFalse);
  });

  test('Eski gönderilerde saniye cinsinden kırpma geriye dönük çalışır', () {
    final post = JuzzioPost.fromMap({
      'id': 'p2',
      'author_id': 'u1',
      'content_type': 'video',
      'media_urls': ['https://x.co/a.mp4'],
      'trim_start_sec': 2,
      'trim_end_sec': 9,
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(post.trimForMedia(0).startMs, 2000);
    expect(post.trimForMedia(0).endMs, 9000);
    expect(post.playbackSpeed, 1.0);
    expect(post.clipMeta, isEmpty);
  });

  test('Hikâye stüdyo alanları okunur', () {
    final st = JuzzioStory.fromMap({
      'id': 's1',
      'user_id': 'u1',
      'media_type': 'video',
      'trim_start_ms': 500,
      'trim_end_ms': 4500,
      'playback_speed': '2.00',
      'overlay_style': 'neon',
      'overlay_color': '#FF3B5C',
      'music_url': 'https://youtu.be/dQw4w9WgXcQ',
      'music_title': 'Şarkı · Sanatçı',
      'created_at': '2026-10-29T10:00:00Z',
    });
    expect(st.hasTrim, isTrue);
    expect(st.playbackSpeed, 2.0);
    expect(st.overlayStyle, 'neon');
    expect(st.musicTitle, 'Şarkı · Sanatçı');
  });

  test('Müzik seçimi ve süre biçimleri', () {
    // v0.7.0: müzik artık isimle seçilen önizleme sesidir; YouTube bağlantısı geçersizdir
    expect(const JuzzioMusicSelection(url: 'https://youtu.be/dQw4w9WgXcQ', startSec: 0, title: '', artist: '', coverUrl: '').isEmpty, isTrue);
    expect(juzzioYoutubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    const sel = JuzzioMusicSelection(
      url: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/a/b.m4a',
      startSec: 10,
      title: 'Şarkı',
      artist: 'Sanatçı',
      coverUrl: '',
    );
    expect(sel.isEmpty, isFalse);
    expect(sel.displayTitle, 'Şarkı · Sanatçı');
    expect(const JuzzioMusicSelection.empty().isEmpty, isTrue);
    expect(juzzioFormatClock(65000), '01:05');
    expect(JuzzioOverlayStyles.parse('#000000').computeLuminance(), lessThan(0.01));
    expect(JuzzioOverlayStyles.parse('bozuk').computeLuminance(), greaterThan(0.99));
  });
}
