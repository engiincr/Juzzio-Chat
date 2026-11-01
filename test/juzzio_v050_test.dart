// JUZZIO v0.5.0 — canlı altyazı bölütü, kimlik çözümü ve yazı paylaşımı testleri.

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/models/social_models.dart';
import 'package:juzzio/services/deepgram_livekit_service.dart';

void main() {
  test('LiveKit kimliğinden kullanıcı kimliği çıkarılır', () {
    expect(
      DeepgramLiveKitController.userIdFromIdentity('7f9c2a10-1111-2222-3333-444455556666_tr'),
      '7f9c2a10-1111-2222-3333-444455556666',
    );
    expect(DeepgramLiveKitController.userIdFromIdentity('tekparca'), 'tekparca');
  });

  test('Altyazı paketi yalnızca kendi bölüt metnini taşır (birleştirme yok)', () {
    final p = LiveSubtitlePacket(
      id: 'u_1',
      speakerId: 'u',
      speakerName: 'Fikret',
      gender: 'male',
      sourceLang: 'tr',
      targetLang: 'en',
      originalText: 'Merhaba',
      translatedText: 'Hello',
      isFinal: true,
      timestamp: DateTime.utc(2026, 10, 30),
    );
    final json = p.toJson();
    expect(json.containsKey('resumedAfterInterruption'), isFalse);
    expect(json.containsKey('interruptedTopicTranslated'), isFalse);
    // Eski istemcilerden gelen fazladan alanlar yok sayılır
    final back = LiveSubtitlePacket.fromJson({
      ...json,
      'resumedPreviousTranslated': 'eski konu',
      'interruptedTopicTranslated': 'eski konu',
    });
    expect(back.translatedText, 'Hello');
    expect(back.originalText, 'Merhaba');
    expect(back.isFinal, isTrue);
  });

  test('Küresel akış yazı paylaşımı tanınır', () {
    final post = JuzzioPost.fromMap({
      'id': 'p1',
      'author_id': 'u1',
      'content_type': 'text',
      'caption': 'Merhaba dünya',
      'media_urls': <String>[],
      'created_at': '2026-10-30T10:00:00Z',
    });
    expect(post.isText, isTrue);
    expect(post.isVideo, isFalse);
  });
}
