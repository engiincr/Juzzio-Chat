// JUZZIO v0.9.4 birim testleri
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/services/deepgram_livekit_service.dart';
import 'package:juzzio/services/juzzio_chick_wardrobe.dart';
import 'package:juzzio/services/juzzio_time_sync.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_attach_menu.dart';
import 'package:juzzio/widgets/juzzio_chick_art.dart';

void main() {
  test('Belge: güvenli dosya adı', () {
    expect(juzzioSafeFileName('../../etc/passwd'), 'passwd');
    expect(juzzioSafeFileName(r'C:\Users\x\rapor.pdf'), 'rapor.pdf');
    expect(juzzioSafeFileName('a<b>:c?.txt'), 'a_b__c_.txt');
    expect(juzzioSafeFileName('..'), 'dosya');
    final long = '${'x' * 200}.docx';
    final safe = juzzioSafeFileName(long);
    expect(safe.length, 120);
    expect(safe.endsWith('.docx'), isTrue);
  });

  test('Belge: MIME ve boyut', () {
    expect(juzzioDocumentMime('a.PDF'), 'application/pdf');
    expect(juzzioDocumentMime('tablo.xlsx'), contains('spreadsheetml'));
    expect(juzzioDocumentMime('bilinmeyen.xyz'), 'application/octet-stream');
    expect(juzzioFormatBytes(512), '512 B');
    expect(juzzioFormatBytes(2048), '2 KB');
    expect(juzzioFormatBytes(5 * 1024 * 1024), '5.0 MB');
  });

  test('Konum metni ayrıştırma', () {
    final app = JuzzioAppController.instance;
    final t = juzzioLocationMessageText(37.774929, 29.087959, app);
    final p = juzzioParseLocationText(t);
    expect(p, isNotNull);
    expect(p!.lat, closeTo(37.774929, 1e-6));
    expect(juzzioParseLocationText('maps.google.com/?q=200,10'), isNull);
    expect(juzzioParseLocationText('merhaba'), isNull);
  });

  test('Saat eşitleme: ofset ve sapma', () {
    final sent = DateTime.utc(2026, 11, 9, 10, 0, 0);
    final recv = sent.add(const Duration(milliseconds: 400));
    // Sunucu, cihazdan 5 dk ileride
    final server = sent.add(const Duration(milliseconds: 200)).add(const Duration(minutes: 5));
    final off = juzzioClockOffset(serverUtc: server, sentUtc: sent, receivedUtc: recv);
    expect(off, const Duration(minutes: 5));
    expect(juzzioClockDrifted(off), isTrue);
    expect(juzzioClockDrifted(const Duration(seconds: 90)), isFalse);
    expect(juzzioClockDrifted(const Duration(minutes: -3)), isTrue);
  });

  test('Canlı altyazı: parçalar tek cümlede birleşir', () {
    expect(juzzioJoinTranscript('', 'merhaba'), 'merhaba');
    expect(juzzioJoinTranscript('bugün hava ', ' çok güzel'), 'bugün hava çok güzel');
    expect(juzzioJoinTranscript('tamam', ''), 'tamam');
  });

  test('Gardırop durumu ayrıştırma', () {
    final st = JuzzioChickWardrobeState.fromMap({
      'has_chick': true,
      'stage': 1,
      'coins': 40,
      'owned': ['party_hat'],
      'style': {'hat': 'party_hat', 'color': '#FF8800'},
      'catalog': [
        {'code': 'party_hat', 'slot': 'hat', 'price': 30, 'min_stage': 1},
        {'code': 'crown', 'slot': 'hat', 'price': 120, 'min_stage': 2},
        {'code': 'theme_meadow', 'slot': 'theme', 'price': 0, 'min_stage': 0},
      ],
    });
    expect(st.catalog.length, 3);
    expect(st.owns(st.catalog[0]), isTrue);
    expect(st.canBuy(st.catalog[1]), isFalse, reason: 'evre ve jeton yetersiz');
    expect(st.owns(st.catalog[2]), isTrue, reason: 'ücretsiz');
    expect(juzzioParseHexColor(st.style['color']), const Color(0xFFFF8800));
    expect(juzzioParseHexColor('kırmızı'), isNull);
  });
}
