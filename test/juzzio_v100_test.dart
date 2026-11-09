// JUZZIO v1.0.0 birim testleri — Juzzio Space tasarım dili, bağlantılar, konum kartı,
// vardiya aralığı, okunur yönetici kayıtları, civciv dönüşü, anında gönderim
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/core/theme/juzzio_aurora.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';
import 'package:juzzio/screens/admin_audit_format.dart';
import 'package:juzzio/screens/shift_planner_screen.dart';
import 'package:juzzio/services/supabase_service.dart';
import 'package:juzzio/widgets/juzzio_chick_art.dart';
import 'package:juzzio/widgets/juzzio_rich_text.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('Juzzio Space tema motoru', () {
    test('16 temanın hepsinde parlayan vurgu ve okunur vurgu metni var', () {
      expect(kJuzzioAuroraPalettes.length, 16);
      for (final p in kJuzzioAuroraPalettes) {
        final sp = p.space;
        expect(sp.depth.length, 3, reason: p.id);
        expect(sp.depthLight.length, 3, reason: p.id);
        expect(_contrast(sp.glow, sp.onGlow(true)), greaterThanOrEqualTo(4.5), reason: '${p.id} vurgu üstü metin');
        // koyu zeminde vurgu belirgin
        expect(_contrast(sp.glow, sp.depth[1]), greaterThanOrEqualTo(3.0), reason: '${p.id} vurgu/zemin');
      }
    });

    test('Zümrüt (Figma) birebir renkler', () {
      final e = juzzioAuroraPaletteById('emerald').space;
      expect(e.glow, const Color(0xFFC9FD7F));
      expect(e.depth, const [Color(0xFF16362B), Color(0xFF102A21), Color(0xFF071714)]);
    });

    test('Cam belirteçleri etkin temayı izler', () {
      JuzzioGlassTokens.spaceResolver = () => juzzioAuroraPaletteById('emerald').space;
      expect(JuzzioGlassTokens.glow, const Color(0xFFC9FD7F));
      expect(JuzzioGlassTokens.accentFill, JuzzioGlassTokens.glow);
      // menüler okunur: neredeyse opak
      JuzzioGlassTokens.isDarkResolver = () => true;
      expect(JuzzioGlassTokens.sheet.a, greaterThan(0.9));
      JuzzioGlassTokens.spaceResolver = () => kJuzzioAuroraPalettes.first.space;
    });
  });

  group('Bağlantılar', () {
    test('web, www, e-posta ve telefon bulunur; sondaki noktalama dahil edilmez', () {
      final l = juzzioFindLinks('Bak: https://juzzio.app/a?b=1. www.example.com, mail ali@ornek.com ara +90 555 123 45 67!');
      expect(l.map((e) => e.text).toList(), ['https://juzzio.app/a?b=1', 'www.example.com', 'ali@ornek.com', '+90 555 123 45 67']);
      expect(l[1].uri.toString(), 'https://www.example.com');
      expect(l[2].uri.scheme, 'mailto');
      expect(l[3].uri.toString(), 'tel:+905551234567');
    });

    test('tarih ve saat telefon sanılmaz', () {
      expect(juzzioFindLinks('Toplantı 2026-11-09 18:21 de, oda 1234'), isEmpty);
    });

    test('tehlikeli şemalar açılmaz', () async {
      expect(await juzzioOpenLink(Uri.parse('javascript:alert(1)')), isFalse);
      expect(await juzzioOpenLink(Uri.parse('file:///etc/passwd')), isFalse);
    });
  });

  group('Konum kartı', () {
    test('Juzzio konum mesajı çözülür', () {
      final p = juzzioParseLocation('📍 Konumum\nhttps://maps.google.com/?q=41.008240,28.978359');
      expect(p, isNotNull);
      expect(p!.lat, closeTo(41.00824, 1e-6));
      expect(p.lng, closeTo(28.978359, 1e-6));
      expect(p.label, 'Konumum');
    });

    test('Apple ve Google Haritalar bağlantıları da kart olur; normal metin olmaz', () {
      expect(juzzioParseLocation('https://maps.apple.com/?ll=48.858370,2.294481'), isNotNull);
      expect(juzzioParseLocation('https://www.google.com/maps/search/?api=1&query=-33.8568,151.2153'), isNotNull);
      expect(juzzioParseLocation('Merhaba, nasılsın?'), isNull);
      expect(juzzioParseLocation('geo:999.0,1.0'), isNull);
    });

    test('Google Haritalar adresi koordinatı taşır', () {
      final u = juzzioGoogleMapUri(const JuzzioGeoPoint(41.0, 29.0));
      expect(u.host, 'www.google.com');
      expect(u.queryParameters['query'], '41.000000,29.000000');
    });
  });

  group('Vardiya aralığı', () {
    test('bir hafta 00:00–12:00 tek seferde', () {
      final rows = juzzioBuildShiftRows(
        userId: 'u',
        from: DateTime(2026, 11, 9),
        to: DateTime(2026, 11, 15),
        code: 'custom',
        start: const TimeOfDay(hour: 0, minute: 0),
        end: const TimeOfDay(hour: 12, minute: 0),
        roomId: 'g',
      );
      expect(rows.length, 7);
      expect(rows.first['shift_date'], '2026-11-09');
      expect(rows.last['shift_date'], '2026-11-15');
      expect(rows.every((r) => r['room_id'] == 'g'), isTrue);
      final s = DateTime.parse(rows.first['starts_at'] as String).toLocal();
      final e = DateTime.parse(rows.first['ends_at'] as String).toLocal();
      expect(e.difference(s), const Duration(hours: 12));
    });

    test('gece vardiyası ertesi gün biter; hafta içi filtresi; ters aralık boş', () {
      final rows = juzzioBuildShiftRows(
        userId: 'u',
        from: DateTime(2026, 11, 9),
        to: DateTime(2026, 11, 15),
        code: 'custom',
        start: const TimeOfDay(hour: 20, minute: 0),
        end: const TimeOfDay(hour: 8, minute: 0),
        weekdays: const {1, 2, 3, 4, 5},
      );
      expect(rows.length, 5);
      final s = DateTime.parse(rows.first['starts_at'] as String);
      final e = DateTime.parse(rows.first['ends_at'] as String);
      expect(e.difference(s), const Duration(hours: 12));
      expect(juzzioBuildShiftRows(userId: 'u', from: DateTime(2026, 2, 2), to: DateTime(2026, 2, 1), code: 'off_day'), isEmpty);
      expect(juzzioBuildShiftRows(userId: 'u', from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31), code: 'off_day').length, 92);
    });
  });

  group('Yönetici kayıtları', () {
    test('kim, ne yaptı, kime — yöneticinin dilinde', () {
      final a = {
        'action': 'ban_user',
        'admin_username': 'ayse',
        'target': '3f2a9c10-0000-4000-8000-000000000001',
        'target_username': 'mehmet',
        'details': {'reason': 'spam', 'devices': 2},
      };
      final tr = juzzioFormatAudit(a, 'tr');
      expect(tr.sentence, '@ayse, @mehmet kullanıcısını yasakladı');
      expect(tr.details, contains('Gerekçe: spam'));
      expect(tr.tone, 3);
      final en = juzzioFormatAudit(a, 'en');
      expect(en.sentence, '@ayse banned @mehmet');
      final de = juzzioFormatAudit(a, 'de');
      expect(de.sentence, '@ayse hat @mehmet gesperrt');
      // ham kimlik cümlede görünmez
      expect(tr.sentence.contains('3f2a9c10'), isFalse);
    });

    test('bilinmeyen eylem okunur kelimelere, UUID kısaltılır', () {
      final l = juzzioFormatAudit({'action': 'reset_cache_now', 'admin_username': 'x', 'target': '3f2a9c10-0000-4000-8000-000000000001'}, 'en');
      expect(l.sentence, '@x: reset cache now → #3f2a9c10');
    });

    test('sunucudaki tüm kayıt türleri için özel cümle var', () {
      final sql = File('supabase/juzzio_database.sql').readAsStringSync();
      final acts = RegExp(r"admin_audit_log\s*\([^)]*\)\s*VALUES\s*\([^,]+,\s*'([a-z0-9_.]+)'").allMatches(sql).map((m) => m.group(1)!).toSet();
      expect(acts.length, greaterThanOrEqualTo(35));
      for (final act in acts) {
        final l = juzzioFormatAudit({'action': act, 'admin_username': 'a'}, 'tr');
        expect(l.sentence.startsWith('@a: '), isFalse, reason: '$act özel cümleye sahip değil');
      }
    });
  });

  group('Civciv prenses dönüşü', () {
    test('başta ve sonda nötr; ortada dönüş, sonra cilve ve göz kırpma', () {
      final a = juzzioChickTwirlPose(0);
      expect(a.spinX, 1.0);
      expect(a.wink, isFalse);
      final mid = juzzioChickTwirlPose(0.25);
      expect(mid.spinX, lessThan(0)); // arkası dönük an
      expect(mid.hop, greaterThan(0.2));
      final flirt = juzzioChickTwirlPose(0.75);
      expect(flirt.wink, isTrue);
      expect(flirt.tilt, greaterThan(0.1)); // sağa eğik
      expect(flirt.blush, greaterThan(0.5));
      expect(juzzioChickTwirlPose(1).tilt, 0.0);
    });
  });

  group('Anında gönderim', () {
    test('mesaj istemci kimliğini taşır (yerel balon eşleşir)', () {
      final m = JuzzioMessage.fromMap({
        'id': '1',
        'room_id': 'r',
        'sender_id': 's',
        'message_type': 'text',
        'original_text': 'Merhaba',
        'client_msg_id': 'abc12345xyz',
        'created_at': '2026-11-09T10:00:00Z',
      });
      expect(m.clientMsgId, 'abc12345xyz');
      expect(m.isLocalPending, isFalse);
      expect(m.withText('a', 'b').clientMsgId, 'abc12345xyz');
    });

    test('gönderim çeviriyi beklemez (kaynak kodu sözleşmesi)', () {
      final src = File('lib/services/supabase_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> sendTextMessage({');
      final end = src.indexOf('Future<void> _translateAfterSend({');
      final body = src.substring(start, end);
      expect(body.contains('await translateText('), isFalse);
      expect(body.contains('unawaited(_translateAfterSend('), isTrue);
    });
  });

  test('Sürüm notu 1.0.0 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.0.0');
    expect(n.versionCode, 100);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
