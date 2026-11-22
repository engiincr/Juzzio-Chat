// GM-002 (21.11.2026) — Giriş / Kayıt yenilemesi: ortak bileşenler, K2 ilk açılış, K6 sosyal giriş
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/theme/juzzio_design_tokens.dart';
import 'package:juzzio/widgets/auth/juzzio_auth_kit.dart';
import 'package:juzzio/widgets/auth/juzzio_auth_view.dart';

String _src(String p) => File(p).readAsStringSync();
String _tr(String tr, String en, String de) => tr;

class _Calls {
  int submit = 0, forgot = 0, toggle = 0, back = 0;
  final social = <String>[];
  final unavailable = <String>[];
}

Widget _host({
  required bool register,
  required _Calls c,
  Map<String, bool> social = const {
    'google': false,
    'apple': false,
    'github': false,
  },
  bool loading = false,
  String? error,
  bool withBack = false,
  double textScale = 1.0,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: JuzzioAuthBackdrop()),
          JuzzioAuthView(
            registerMode: register,
            t: _tr,
            identifierController: TextEditingController(),
            emailController: TextEditingController(),
            passwordController: TextEditingController(),
            obscurePassword: true,
            onToggleObscure: () {},
            rememberMe: true,
            onRememberChanged: (_) {},
            loading: loading,
            errorText: error,
            onSubmit: () => c.submit++,
            onForgotPassword: () => c.forgot++,
            onToggleMode: () => c.toggle++,
            socialEnabled: social,
            onSocial: c.social.add,
            onSocialUnavailable: c.unavailable.add,
            onBack: withBack ? () => c.back++ : null,
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, Widget w, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('GM-002 giriş ekranı', () {
    testWidgets(
      'giriş: chip, başlık, alanlar, beni hatırla, şifremi unuttum, CTA, sosyal, alt bağlantı',
      (tester) async {
        final c = _Calls();
        await _pumpAt(
          tester,
          _host(register: false, c: c),
          const Size(393, 800),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Giriş Yap'), findsWidgets); // chip + CTA
        expect(find.byKey(const ValueKey('auth_identifier')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth_password')), findsOneWidget);
        expect(find.text('Beni hatırla'), findsOneWidget);
        expect(find.text('Şifremi unuttum?'), findsOneWidget);
        expect(find.text('veya'), findsOneWidget);
        expect(find.text('Hesap Oluştur'), findsOneWidget);
        for (final p in JuzzioAuthView.providers) {
          expect(find.byKey(ValueKey('auth_social_$p')), findsOneWidget);
        }
      },
    );

    testWidgets(
      'kayıt: üç alan, beni hatırla yok, geri düğmesi giriş ekranına döner',
      (tester) async {
        final c = _Calls();
        await _pumpAt(
          tester,
          _host(register: true, c: c, withBack: true),
          const Size(393, 800),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('auth_username')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth_email')), findsOneWidget);
        expect(find.byKey(const ValueKey('auth_password')), findsOneWidget);
        expect(find.text('Beni hatırla'), findsNothing);
        expect(find.text('Kayıt Ol'), findsOneWidget);
        expect(find.byType(JuzzioHeroBackButton), findsOneWidget);
        await tester.tap(find.byType(JuzzioHeroBackButton));
        expect(c.back, 1);
      },
    );

    testWidgets('girişte geri işlemi yoksa sahte geri düğmesi çizilmez', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        _host(register: false, c: _Calls()),
        const Size(393, 800),
      );
      expect(find.byType(JuzzioHeroBackButton), findsNothing);
    });

    testWidgets(
      'K6: pasif sağlayıcı giriş denemez, bilgi verir; etkin olan gerçek akışa gider',
      (tester) async {
        final c = _Calls();
        await _pumpAt(
          tester,
          _host(
            register: false,
            c: c,
            social: const {'google': true, 'apple': false, 'github': false},
          ),
          const Size(393, 800),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('auth_social_apple')),
        );
        await tester.tap(find.byKey(const ValueKey('auth_social_apple')));
        await tester.tap(find.byKey(const ValueKey('auth_social_google')));
        expect(c.unavailable, ['apple']);
        expect(c.social, ['google']);
        final opacities = tester.widgetList<Opacity>(
          find.descendant(
            of: find.byKey(const ValueKey('auth_social_github')),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacities.single.opacity, JuzzioSocialButton.passiveOpacity);
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp('GitHub.*kullanılamıyor')),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('yüklenirken CTA ikinci kez gönderim yapmaz', (tester) async {
      final c = _Calls();
      await _pumpAt(
        tester,
        _host(register: false, c: c, loading: true),
        const Size(393, 800),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('auth_submit')));
      await tester.tap(find.byKey(const ValueKey('auth_submit')));
      expect(c.submit, 0);
    });

    testWidgets('hata metni gösterilir', (tester) async {
      await _pumpAt(
        tester,
        _host(register: false, c: _Calls(), error: 'Şifre hatalı'),
        const Size(393, 800),
      );
      expect(find.text('Şifre hatalı'), findsOneWidget);
    });
  });

  group('GM-002 duyarlı yerleşim (taşma yok)', () {
    const sizes = [
      Size(360, 640),
      Size(393, 760),
      Size(412, 870),
      Size(1280, 800),
    ];
    for (final reg in [false, true]) {
      for (final s in sizes) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '${reg ? 'kayıt' : 'giriş'} ${s.width.toInt()}x${s.height.toInt()} metin x$scale',
            (tester) async {
              await _pumpAt(
                tester,
                _host(
                  register: reg,
                  c: _Calls(),
                  textScale: scale,
                  error: 'Örnek hata mesajı',
                ),
                s,
              );
              expect(tester.takeException(), isNull);
              // CTA kaydırılarak erişilebilir
              await tester.ensureVisible(
                find.byKey(const ValueKey('auth_submit')),
              );
              await tester.pump();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('GM-002 kurallar', () {
    test(
        'K2: ilk açılış doğrudan giriş; tanıtım/izin ekranları yok; girişte kamera/mikrofon istenmez',
        () {
      final m = _src('lib/main.dart');
      expect(m.contains('_buildOnboardingStep1Cool'), isFalse);
      expect(m.contains('_buildOnboardingStep2Notifications'), isFalse);
      expect(m.contains('_handleTurnOnNotifications'), isFalse);
      expect(m.contains('Permission.camera'), isFalse);
      expect(m.contains('Permission.microphone'), isFalse);
      expect(m.contains('setState(() => _booting = false);'), isTrue);
      final p = _src('lib/widgets/juzzio_notification_prompt.dart');
      expect(p.contains('Permission.notification.request()'), isTrue);
      expect(p.contains('Permission.camera'), isFalse);
      expect(
        _src('lib/screens/chat_screen.dart')
            .contains('JuzzioNotificationPrompt.maybeAsk(context)'),
        isTrue,
      );
    });

    test('K3: auth iş mantığı korunur', () {
      final m = _src('lib/main.dart');
      for (final s in [
        'SupabaseService.instance.registerAccount(',
        'SupabaseService.instance.signInWithUsernameOrEmail(',
        'resetPasswordForEmail(email)',
        'signInWithOAuth(p, redirectTo: JuzzioConfig.oauthRedirect)',
        'juzzioOpenRequiredConsent(context)',
        'JuzzioMfaService.instance.needsChallenge()',
        'setRememberedLoginId(_rememberMe',
      ]) {
        expect(m.contains(s), isTrue, reason: s);
      }
    });

    test(
      'K1: auth bileşenlerinde sabit renk yok; tokenlar K1 varyantlarıyla aynı',
      () {
        for (final f in [
          'lib/widgets/auth/juzzio_auth_kit.dart',
          'lib/widgets/auth/juzzio_auth_view.dart',
        ]) {
          expect(RegExp(r'Color\(0x').hasMatch(_src(f)), isFalse, reason: f);
        }
        expect(JuzzioSizes.primaryHeight, 56);
        expect(JuzzioSizes.authInputHeight, 54);
        expect(JuzzioSizes.iconCircleSocial, 54);
        expect(JuzzioRadius.authGlassTop, 54);
        expect(JuzzioColorTokens.accent, const Color(0xFFC5F63F));
      },
    );

    test('K5: katman varlıkları ayrı dosyalar; lisanslar pakette', () {
      for (final a in [
        JuzzioAuthAssets.portrait,
        JuzzioAuthAssets.emojiSunglasses,
        JuzzioAuthAssets.emojiGrin,
        JuzzioAuthAssets.emojiBeaming,
        JuzzioAuthAssets.emojiWave,
        'assets/auth/emoji/FluentEmoji-LICENSE-MIT.txt',
        'assets/fonts/inter/Inter-OFL.txt',
      ]) {
        expect(File(a).existsSync(), isTrue, reason: a);
      }
      final pub = _src('pubspec.yaml');
      expect(pub.contains('- assets/auth/portrait_temp.png'), isTrue);
      expect(pub.contains('- assets/auth/emoji/'), isTrue);
      expect(pub.contains('family: JuzzioInter'), isTrue);
    });
  });

  testWidgets('semantik: başlık ve düğmeler erişilebilir', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpAt(
      tester,
      _host(register: false, c: _Calls()),
      const Size(393, 800),
    );
    expect(find.bySemanticsLabel('Tekrar Hoş Geldin!'), findsOneWidget);
    expect(find.bySemanticsLabel('Trawave'), findsWidgets);
    handle.dispose();
  });
}
