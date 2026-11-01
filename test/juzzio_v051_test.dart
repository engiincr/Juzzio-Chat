// JUZZIO v0.5.1 — hikâye çıkartmaları, akış konuları ve nötr sohbet temaları testleri.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/models/social_models.dart';
import 'package:juzzio/services/social_service.dart';
import 'package:juzzio/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Hikâye çıkartmaları okunur, sınırlanır ve geri yazılır', () {
    final list = JuzzioStorySticker.listFrom([
      {'type': 'emoji', 'emoji': '🔥', 'x': 0.25, 'y': 1.7, 'scale': 9},
      {'emoji': ''},
      'bozuk',
      {'emoji': '🌸', 'x': '0.5', 'y': '0.4'},
    ]);
    expect(list.length, 2);
    expect(list.first.emoji, '🔥');
    expect(list.first.y, 1.0);
    expect(list.first.scale, 4.0);
    expect(list[1].x, 0.5);
    final map = list.first.toMap();
    expect(map['emoji'], '🔥');
    expect(map['x'], 0.25);

    final fromJsonString = JuzzioStorySticker.listFrom('[{"emoji":"😎","x":0.1,"y":0.2}]');
    expect(fromJsonString.single.emoji, '😎');
    expect(JuzzioStorySticker.listFrom(null), isEmpty);
  });

  test('Hikâye kaydında çıkartmalar modele taşınır', () {
    final st = JuzzioStory.fromMap({
      'id': 's1',
      'user_id': 'u1',
      'media_type': 'text',
      'caption_original': '',
      'caption_translated': '',
      'created_at': '2026-10-31T10:00:00Z',
      'stickers_json': [
        {'emoji': '🎉', 'x': 0.3, 'y': 0.6, 'scale': 1.2},
      ],
    });
    expect(st.stickers.single.emoji, '🎉');
    expect(st.stickers.single.scale, closeTo(1.2, 0.0001));
  });

  test('Gönderi konusu okunur, yoksa genel kabul edilir', () {
    final withTopic = JuzzioPost.fromMap({
      'id': 'p1',
      'author_id': 'u1',
      'content_type': 'text',
      'caption': 'Maç başladı',
      'topic': 'sports',
      'created_at': '2026-10-31T10:00:00Z',
    });
    expect(withTopic.topic, 'sports');
    expect(withTopic.copyWith(likesCount: 3).topic, 'sports');
    final noTopic = JuzzioPost.fromMap({
      'id': 'p2',
      'author_id': 'u1',
      'content_type': 'text',
      'caption': 'Merhaba',
      'created_at': '2026-10-31T10:00:00Z',
    });
    expect(noTopic.topic, 'general');
    expect(kJuzzioFeedTopics.first, 'general');
    expect(kJuzzioFeedTopics.toSet().length, kJuzzioFeedTopics.length);
  });

  test('Sohbet temalarının her biri ayrı renkte ve turuncu değil (v0.8.1)', () {
    final ids = kJuzzioChatThemes.map((t) => t.id).toSet();
    expect(ids.length, kJuzzioChatThemes.length);
    final colors = kJuzzioChatThemes.map((t) => t.primaryColor.toARGB32()).toSet();
    expect(colors.length, kJuzzioChatThemes.length);
    for (final t in kJuzzioChatThemes) {
      final h = HSLColor.fromColor(t.primaryColor);
      expect(h.saturation > 0.35 && h.hue >= 12 && h.hue <= 48, isFalse, reason: t.id);
    }
  });
}
