// JUZZIO v0.8.3 — küresel tema önceliği, hızlı yanıt doğrulaması, dil senkronu
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/app_theme_and_locale.dart';
import 'package:juzzio/core/theme/juzzio_custom_theme.dart';
import 'package:juzzio/core/theme/juzzio_glass.dart';
import 'package:juzzio/services/juzzio_quick_reply.dart';

Map<String, dynamic> _row(int v) => {
      'version': v,
      'name': 'Global $v',
      'payload': JuzzioCustomTheme.blank(id: 'ct_global', name: 'Global $v', dark: v.isOdd).toJson(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final app = JuzzioAppController.instance;

  tearDown(() {
    app.setGlobalThemeFromServer(null);
    app.setFollowGlobalTheme(false);
    app.clearCustomTheme();
    JuzzioGlassTokens.custom = null;
  });

  test('Küresel tema yalnızca takip eden kullanıcıya uygulanır', () {
    app.setGlobalThemeFromServer(_row(3));
    expect(app.globalThemeVersion, 3);
    app.setGlassPalette('emerald'); // kullanıcı kendi temasını seçti
    expect(app.effectiveCustomTheme, isNull, reason: 'yönetici yayını seçim yapanı etkilememeli');
    app.setFollowGlobalTheme(true);
    expect(app.effectiveCustomTheme?.id, 'global_v3');
    expect(JuzzioGlassTokens.custom?.id, 'global_v3');
  });

  test('Kullanıcının özel teması küresel temadan önceliklidir', () {
    app.setGlobalThemeFromServer(_row(5));
    app.setFollowGlobalTheme(true);
    final mine = JuzzioCustomTheme.blank(id: 'ct_mine01', name: 'Benim', dark: false);
    app.saveCustomTheme(mine);
    app.applyCustomTheme(mine.id);
    expect(app.effectiveCustomTheme?.id, 'ct_mine01');
    expect(app.followGlobalTheme, isFalse);
    app.deleteCustomTheme(mine.id);
  });

  test('Yayın kaldırılınca küresel tema temizlenir; bozuk yük yok sayılır', () {
    app.setGlobalThemeFromServer(_row(7));
    app.setFollowGlobalTheme(true);
    app.setGlobalThemeFromServer(null);
    expect(app.globalTheme, isNull);
    expect(app.effectiveCustomTheme, isNull);
    app.setGlobalThemeFromServer({'version': 9, 'payload': {'schema': 'baska'}});
    expect(app.globalTheme, isNull);
  });

  test('Hızlı yanıt: geçersiz girdiler ağ çağrısı yapmadan reddedilir', () async {
    expect(await JuzzioQuickReply.send(roomId: 'not-a-room', text: 'merhaba'), isFalse);
    expect(await JuzzioQuickReply.send(roomId: '00000000-0000-0000-0000-000000000000', text: '   '), isFalse);
    expect(
      await JuzzioQuickReply.send(roomId: '00000000-0000-0000-0000-000000000000', text: 'x' * (JuzzioQuickReply.maxLength + 1)),
      isFalse,
    );
  });

  test('Desteklenen dil sayısı en az 139', () {
    expect(JuzzioAppController.supportedLanguages.length, greaterThanOrEqualTo(139));
  });
}
