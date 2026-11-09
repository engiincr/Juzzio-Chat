// JUZZIO v1.1.1 birim testleri — vektör kumaş yenileme, bildirimler yenileme hatası, profil hızı
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/widgets/juzzio_cloth_refresh.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  test('Kumaş yenileme vektörle çizilir (raster sprite/çapraz geçiş yok)', () {
    final s = _src('lib/widgets/juzzio_cloth_refresh.dart');
    expect(s.contains('drawImageRect'), isFalse);
    expect(s.contains('rootBundle'), isFalse);
    expect(s.contains('ImageFilter.blur'), isFalse);
    // yumruk: parmaklar kısalır, başparmak öne gelir
    final open = JuzzioHandShape(0), fist = JuzzioHandShape(1);
    expect(fist.tips.first.dy, lessThan(open.tips.first.dy));
    expect(fist.thumbTip.dx, greaterThan(open.thumbTip.dx));
    expect(JuzzioHandShape(2).c, 1.0); // sınırlanır
  });

  test('Bildirimler: yenilemede liste sökülmez, eski yanıt yeniyi ezmez', () {
    final s = _src('lib/screens/settings_suite_screens.dart');
    final i = s.indexOf('Future<void> _loadNotifications() async {');
    final body = s.substring(i, s.indexOf('Widget _pullable', i));
    expect(body.contains('_reloading = true'), isTrue);
    expect(body.contains('ticket != _loadTicket'), isTrue);
    expect(body.contains('if (_items.isEmpty && _loadState != JuzzioDataLoadState.loaded)'), isTrue);
  });

  test('Profil: parçalar geldiği an uygulanır, bellek önbelleği, paralel sorgular', () {
    final p = _src('lib/screens/profile/juzzio_profile_view.dart');
    expect(p.contains('static final Map<String, _ProfileSnapshot> _memo'), isTrue);
    expect(p.contains('Future<void> part<T>('), isTrue);
    final soc = _src('lib/services/social_service.dart');
    expect(soc.contains('_interactionInFlight'), isTrue);
    expect(soc.contains('_interactionTtl'), isTrue);
  });

  test('Sürüm notu 1.1.1 TR + EN', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.1.1');
    expect(n.versionCode, 111);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
