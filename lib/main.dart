// =============================================================================
// GM-002 (21.11.2026): ilk açılış doğrudan Giriş/Kayıt (K2); giriş/kayıt arayüzü
// widgets/auth/ altındaki ortak bileşenlerle yeniden kuruldu (K1, K4). Aşağıdaki eski başlık tarihseldir.
// JUZZIO v0.1.0 - Instagram.jpg Beyaz Tema ("Inspired people" / "Cool!" &
// "Turn on notifications") Onboarding + 139+ Dil Otomatik Cihaz Dili Algılama
// + R-RegularBold.otf & RBold-İtalic.otf Font Entegrasyonu
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme_and_locale.dart';
import 'core/config.dart';
import 'widgets/juzzio_desktop_frame.dart';
import 'widgets/juzzio_weather_hd.dart' show JuzzioWeatherDebugFile;
import 'widgets/juzzio_clock_guard.dart';
import 'widgets/juzzio_eye_comfort.dart';
import 'widgets/juzzio_theme_reveal.dart';
import 'core/native_bridge.dart';
import 'screens/chat_screen.dart';
import 'services/juzzio_e2ee.dart';
import 'services/juzzio_error_reporter.dart';
import 'services/fcm_push_service.dart';
import 'services/juzzio_quick_reply.dart';
import 'services/juzzio_notification_preview.dart';
import 'services/juzzio_call_actions.dart';
import 'services/supabase_service.dart';
import 'services/juzzio_features_service.dart';
import 'screens/banned_screen.dart';
import 'core/theme/juzzio_aurora.dart';
import 'core/theme/juzzio_glass.dart';
import 'core/theme/juzzio_design_tokens.dart';
import 'widgets/juzzio_motion.dart' show JuzzioLiveIsland;
import 'widgets/juzzio_splash.dart';
import 'widgets/juzzio_consent.dart';
import 'widgets/juzzio_weather_ambience.dart';
import 'widgets/juzzio_weather_doodles.dart';
import 'widgets/profile_extras.dart' show JuzzioMusicRouteObserver;
import 'core/juzzio_ui_sync.dart';
import 'core/juzzio_audio_guard.dart';
import 'widgets/juzzio_a11y_filter.dart';
import 'widgets/auth/juzzio_auth_kit.dart' show JuzzioAuthBackdrop;
import 'widgets/auth/juzzio_auth_view.dart';
import 'services/juzzio_mfa_service.dart';
import 'screens/settings/juzzio_settings_v21.dart' show showJuzzioMfaCodeDialog;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // v1.2.9 (telif): gömülü emoji yazı tipinin OFL lisansı "Açık kaynak lisansları" sayfasında görünür
  // v1.2.9: arama gelince / arka plana geçince / başka uygulama ses çalınca tüm müzikler durur
  unawaited(JuzzioAudioGuard.instance.install());
  LicenseRegistry.addLicense(() async* {
    try {
      final ofl = await rootBundle.loadString('assets/fonts/NotoColorEmoji-OFL.txt');
      yield LicenseEntryWithLineBreaks(const ['Noto Color Emoji'], ofl);
    } catch (_) {}
    // GM-002: giriş/kayıt yazı tipi ve emoji görselleri
    try {
      yield LicenseEntryWithLineBreaks(const ['Inter'], await rootBundle.loadString('assets/fonts/inter/Inter-OFL.txt'));
    } catch (_) {}
    try {
      yield LicenseEntryWithLineBreaks(const ['Fluent Emoji (Microsoft)'], await rootBundle.loadString('assets/auth/emoji/FluentEmoji-LICENSE-MIT.txt'));
    } catch (_) {}
    yield const LicenseEntryWithLineBreaks(['Open-Meteo'], 'Weather data by Open-Meteo.com — Creative Commons Attribution 4.0 International (CC BY 4.0). https://open-meteo.com/');
  });

  // v2.0.0: Masaüstü ve iPad tüm yönlendirmelere izin verir; telefon dikey kalır
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await SystemChrome.setPreferredOrientations([]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await Supabase.initialize(
    url: JuzzioConfig.supabaseUrl,
    anonKey: JuzzioConfig.supabaseAnonKey,
  );
  JuzzioFcmPushService.instance.ensureAuthStateListener();
  // v0.9.6: otomatik hata / çökme bildirimi (Yönetici → Sistem → Hatalar)
  JuzzioErrorReporter.instance.install();

  // Glassmorphism: her sayfanın arkasındaki aurora zemini seçili cam temasını izler
  final appCtrl = JuzzioAppController.instance;
  JuzzioAuroraScope.palette = () => appCtrl.glassPalette;
  JuzzioAuroraScope.isDark = () => appCtrl.isDark;
  JuzzioAuroraScope.listenable = appCtrl;
  // v0.7.0: cam belirteçleri (metin/zemin/kenar renkleri) tema duyarlı
  JuzzioGlassTokens.isDarkResolver = () => appCtrl.isDark;
  // v0.8.4: hazır temanın cam karakteri (özel temada standart karakter)
  JuzzioGlassTokens.characterResolver = () => appCtrl.glassPalette.character;
  JuzzioGlassTokens.accentPairResolver = () => [appCtrl.glassPalette.swatchA, appCtrl.glassPalette.swatchB];
  JuzzioGlassTokens.spaceResolver = () => appCtrl.glassPalette.space;
  // v0.8.2 erişilebilirlik: Yüksek Kontrast teması, Ayarlar → Erişilebilirlik → "Kontrastı artır"
  // veya işletim sisteminin yüksek kontrast ayarı açıkken kenar ve metinler belirginleşir.
  JuzzioGlassTokens.highContrastResolver = () =>
      appCtrl.glassPaletteId == 'high_contrast' ||
      appCtrl.highContrastMode ||
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.highContrast;
  JuzzioAuroraScope.reduceMotion = () =>
      appCtrl.reduceMotion || WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  WidgetsBinding.instance.addObserver(_JuzzioSystemAppearanceObserver(appCtrl));
  // v2.2.0: Ayarlar ve diğer cam sayfalarda da aynı hava katmanı (referanstaki bulut/güneş/yağmur/ay)
  JuzzioAuroraPage.weatherLayerBuilder = () => const JuzzioWeatherDoodleLayer();

  // v0.8.1 tema motoru §3.3: kullanıcının kayıtlı teması ilk kareden ÖNCE yüklenir
  // (yanlış tema parlaması olmaz). Bozuk/eksik veri güvenli varsayılana döner.
  try {
    await appCtrl
        .loadUserPreferences(Supabase.instance.client.auth.currentUser?.id)
        .timeout(const Duration(milliseconds: 800));
  } catch (_) {}

  JuzzioErrorReporter.instance.userEnabled = appCtrl.autoErrorReports;

  // Düşük donanımlı cihazda blur fallback (kullanıcı seçimi her zaman önceliklidir)
  JuzzioNative.isLowEndDevice().then((low) => appCtrl.applyDeviceProfile(lowEnd: low));

  // v1.2.4: dil değişince açık olan TÜM ekranlar anında yeni dile geçer
  JuzzioUiSync.attach();
  JuzzioWeatherDebugFile.start(); // yalnız hata ayıklama derlemesi; arayüzde iz yok
  runApp(const JuzzioApp());
}

/// v0.8.3: uygulama kapalıyken bildirimden hızlı yanıt için başsız (ekransız) Dart
/// giriş noktası. Android JuzzioReplyReceiver bu fonksiyonu ayrı bir motorda çalıştırır,
/// yanıtı 'take' ile alır, normal (E2EE) gönderim yolundan gönderir, sonucu 'result'
/// ile bildirir. Ekran çizilmez.
@pragma('vm:entry-point')
Future<void> juzzioQuickReplyMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juzzio/quick_reply');
  Map<String, Object> outcome = {'ok': false, 'status': JuzzioQuickReplyStatus.failed.name};
  try {
    JuzzioE2ee.instance.headless = true;
    await Supabase.initialize(url: JuzzioConfig.supabaseUrl, anonKey: JuzzioConfig.supabaseAnonKey);
    final req = await channel.invokeMapMethod<String, dynamic>('take');
    if (req != null) {
      try {
        await JuzzioAppController.instance
            .loadUserPreferences(Supabase.instance.client.auth.currentUser?.id)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      // v0.9.0 N-E: Android'in ürettiği client_msg_id ile idempotent gönderim
      outcome = await JuzzioQuickReply.handleChannelArgs(req);
    }
  } catch (_) {
    outcome = {'ok': false, 'status': JuzzioQuickReplyStatus.failed.name};
  }
  try {
    await channel.invokeMethod('result', outcome);
  } catch (_) {}
}

/// v0.9.0 N-D: uygulama kapalıyken mesaj bildirimini cihazda çözmek için ekransız giriş noktası.
/// Android JuzzioNotificationDecryptor bunu ayrı motorda çalıştırır, {room_id, message_id}
/// alır, mesajı kullanıcının kendi oturumuyla okuyup (RLS) cihazda çözer, metni 'result' ile
/// döndürür. Hata/zaman aşımında null → genel "yeni mesaj" metni. Ekran çizilmez.
@pragma('vm:entry-point')
Future<void> juzzioNotificationPreviewMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juzzio/notif_preview');
  Map<String, Object?> outcome = {'text': null};
  try {
    JuzzioE2ee.instance.headless = true;
    await Supabase.initialize(url: JuzzioConfig.supabaseUrl, anonKey: JuzzioConfig.supabaseAnonKey);
    final req = await channel.invokeMapMethod<String, dynamic>('take');
    if (req != null) {
      try {
        await JuzzioAppController.instance
            .loadUserPreferences(Supabase.instance.client.auth.currentUser?.id)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      outcome = await JuzzioNotificationPreview.handleChannelArgs(req);
    }
  } catch (_) {
    outcome = {'text': null};
  }
  try {
    await channel.invokeMethod('result', outcome);
  } catch (_) {}
}

/// v0.9.0 N-F: uygulama kapalıyken gelen arama bildirimindeki "Reddet" için ekransız giriş noktası.
@pragma('vm:entry-point')
Future<void> juzzioCallActionMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('juzzio/call_action');
  Map<String, Object?> outcome = {'status': 'error'};
  try {
    await Supabase.initialize(url: JuzzioConfig.supabaseUrl, anonKey: JuzzioConfig.supabaseAnonKey);
    final req = await channel.invokeMapMethod<String, dynamic>('take');
    if (req != null) outcome = await JuzzioCallActions.handleChannelArgs(req);
  } catch (_) {
    outcome = {'status': 'error'};
  }
  try {
    await channel.invokeMethod('result', outcome);
  } catch (_) {}
}

/// v0.8.2: sistem açık/koyu görünümü veya erişilebilirlik ayarı değişince tema
/// tokenları anında yeniden hesaplanır (System modu ve yüksek kontrast için).
class _JuzzioSystemAppearanceObserver with WidgetsBindingObserver {
  final JuzzioAppController app;
  _JuzzioSystemAppearanceObserver(this.app);

  @override
  void didChangePlatformBrightness() => app.onSystemAppearanceChanged();

  @override
  void didChangeAccessibilityFeatures() => app.onSystemAppearanceChanged();
}

/// Akıcı sayfa geçişleri: Android ve iOS'ta kaydırmalı (geri hareketi destekli) geçiş.
const PageTransitionsTheme kJuzzioPageTransitions = PageTransitionsTheme(
  builders: {
    // Her sayfa kendi aurora cam zeminiyle çizilir; iOS tarzı kaydırma + geri hareketi korunur
    TargetPlatform.android: JuzzioAuroraPageTransitionsBuilder(),
    TargetPlatform.iOS: JuzzioAuroraPageTransitionsBuilder(),
    TargetPlatform.windows: JuzzioAuroraPageTransitionsBuilder(),
    TargetPlatform.linux: JuzzioAuroraPageTransitionsBuilder(),
    TargetPlatform.macOS: JuzzioAuroraPageTransitionsBuilder(),
  },
);

const Set<String> _kRtlLangs = {'ar', 'fa', 'he', 'iw', 'ur', 'ps', 'ckb', 'yi', 'sd', 'ug', 'dv', 'bal'};

bool juzzioIsRtl(String uiLang) => _kRtlLangs.contains(uiLang.toLowerCase().split(RegExp('[-_]')).first) || uiLang.toLowerCase() == 'ckb' || uiLang.toLowerCase().endsWith('-arab');

/// Uygulama dilini Flutter'ın desteklediği en yakın Material diline eşler.
Locale juzzioMaterialLocale(String uiLang) {
  final base = uiLang.toLowerCase().split(RegExp('[-_]')).first;
  if (base == 'zh') {
    return uiLang.toLowerCase().contains('tw')
        ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
        : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  }
  if (kMaterialSupportedLanguages.contains(base)) return Locale(base);
  return const Locale('en');
}

Widget? _juzzioInitialHome;

Widget _resolveInitialHome() {
  final auth = Supabase.instance.client.auth;
  final user = auth.currentUser;
  if (auth.currentSession != null && user != null) {
    final meta = user.userMetadata ?? {};
    final uname = (meta['username'] ?? meta['display_name'] ?? user.email?.split('@').first ?? 'Trawave User')
        .toString()
        .replaceAll('@', '');
    final lang = (meta['preferred_lang'] ?? JuzzioAppController.instance.subtitleLang).toString();
    // v1.1.0: Android açılışından kesintisiz marka perdesi (sohbetler altında yüklenir)
    return JuzzioLaunchCurtain(child: ChatScreen(myDisplayName: uname, myLanguage: lang));
  }
  return const JuzzioRootFlow();
}

class JuzzioApp extends StatelessWidget {
  const JuzzioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        // v0.8.1: durum/gezinme çubuğu simgeleri temaya göre (aydınlık temada koyu simge)
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: appCtrl.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: appCtrl.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: appCtrl.isDark ? Brightness.light : Brightness.dark,
        ));
        return MaterialApp(
          title: 'Trawave',
          // v1.3.2 masaüstü: fare/dokunmatik yüzeyle sürükleyerek kaydırma
          scrollBehavior: const JuzzioScrollBehavior(),
          // v1.2.8: hava katmanı yalnız ana ekranda (tam ekran sayfaların üstüne binmez)
          navigatorObservers: [JuzzioAmbienceRouteObserver.instance, JuzzioMusicRouteObserver.instance, JuzzioDesktopFrameObserver.instance],
          debugShowCheckedModeBanner: false,
          themeMode: appCtrl.themeMode,
          // v0.8.1: aydınlık mod da aynı cam bileşen temalarını kullanır
          theme: buildJuzzioDarkTheme(
            fontFamily: JuzzioConfig.fontRegularBold,
            transitions: kJuzzioPageTransitions,
            dark: false,
          ),
          darkTheme: buildJuzzioDarkTheme(
            fontFamily: JuzzioConfig.fontRegularBold,
            transitions: kJuzzioPageTransitions,
          ),
          // Arayüz dili değiştiğinde (yeniden başlatmadan) sistem metinleri, tarih
          // seçiciler ve yazı yönü (RTL: Arapça, Farsça, İbranice, Urduca...) güncellenir.
          locale: juzzioMaterialLocale(appCtrl.uiLang),
          supportedLocales: [
            ...kMaterialSupportedLanguages.map((code) => Locale(code)),
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // v0.7.0: durum çubuğu simgeleri temaya göre (aydınlıkta koyu, karanlıkta açık);
          // gece/gündüz geçişinde tüm sayfa renkleri yumuşak geçişle değişir.
          // v0.8.2: tema geçişi yumuşak; hareket azaltılmışsa anında (renk sıçraması yok)
          themeAnimationDuration: appCtrl.reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          themeAnimationCurve: Curves.easeOutCubic,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: appCtrl.isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: appCtrl.isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: appCtrl.isDark ? Brightness.light : Brightness.dark,
            ),
            child: Directionality(
              textDirection: juzzioIsRtl(appCtrl.uiLang) ? TextDirection.rtl : TextDirection.ltr,
              // v0.9.4: cihaz saati sunucudan 2 dk'dan fazla saparsa tüm sayfaların üstünde uyarı
              // v0.9.6: Göz Konforu (amber mavi ışık filtresi) en üst katmanda, dokunmayı engellemez
              // v0.9.7: koyu/aydınlık geçişinde dairesel reveal
              // v1.1.0: Dynamic Island tarzı canlı durum kapsülü (arama, ses kaydı, yükleme) tüm sayfaların üstünde
              // v1.3.2: Windows'ta geniş pencerede içerik ortada okunaklı bir panelde
              // v2.1 (Faz 8.5): kalın yazı + renk düzeltme (kapalıyken katman eklenmez)
              child: JuzzioA11yFilter(
                child: JuzzioDesktopFrame(
                child: JuzzioEyeComfortOverlay(
                  child: JuzzioThemeReveal(
                    child: JuzzioClockGuard(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          child ?? const SizedBox.shrink(),
                          // v2.1: hava ambiyansı artık sayfaların ÜSTÜNDE değil, ana ekranın arka planında
                          // (chat_screen → JuzzioWeatherAmbience()); yazıların/diyalogların üstüne binmez.
                          const JuzzioLiveIsland(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
          // Başlangıç ekranı yalnızca bir kez belirlenir: oturum açıksa doğrudan
          // Sohbetler açılır (giriş ekranı hiç görünmez, sayfa titremesi olmaz).
          home: _juzzioInitialHome ??= _resolveInitialHome(),
        );
      },
    );
  }
}

class JuzzioRootFlow extends StatefulWidget {
  const JuzzioRootFlow({super.key});

  @override
  State<JuzzioRootFlow> createState() => _JuzzioRootFlowState();
}

class _JuzzioRootFlowState extends State<JuzzioRootFlow> {
  // Açılışta oturum/tanıtım durumu belirlenene kadar yalnızca logo gösterilir
  // (tanıtım ekranı her açılışta görünmez).
  bool _booting = true;
  bool _isRegisterMode = false;
  // v2.1: "Beni hatırla" (yalnız kullanıcı adı/e-posta saklanır)
  bool _rememberMe = JuzzioAppController.instance.rememberedLoginId.isNotEmpty;

  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _fullNameCtrl = TextEditingController();
  // Cinsiyet yalnızca arka planda (Civciv bildirimleri için) saklanır, profilde görünmez
  String _gender = 'unspecified';
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final remembered = JuzzioAppController.instance.rememberedLoginId;
    if (remembered.isNotEmpty) _usernameCtrl.text = remembered;
    _boot();
  }

  /// Açılış: oturum varsa doğrudan Mesajlar'a gider (cihaz engeli ChatScreen'de denetlenir);
  /// oturum yoksa doğrudan giriş ekranı açılır (GM-002, K2).
  Future<void> _boot() async {
    if (_checkActiveSession()) return;
    if (!mounted) return;
    // GM-002 (K2): tanıtım/izin ekranları yok; oturum yoksa doğrudan Giriş Yap / Kayıt Ol
    setState(() => _booting = false);
    final res = await JuzzioFeaturesService.instance.checkDeviceAccess();
    if (res.banned && mounted) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => JuzzioBannedScreen(reasonCode: res.reason)),
      );
    }
  }

  bool _checkActiveSession() {
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    if (session != null && user != null) {
      final meta = user.userMetadata ?? {};
      final uname = (meta['username'] ??
              meta['display_name'] ??
              user.email?.split('@').first ??
              'Trawave User')
          .toString()
          .replaceAll('@', '');
      final lang = (meta['preferred_lang'] ?? JuzzioAppController.instance.subtitleLang).toString();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // v2.1 (Faz 7.3): yarım kalmış (AAL1) oturumda iki adımlı doğrulama kodu istenir
        if (await JuzzioMfaService.instance.needsChallenge()) {
          if (!mounted) return;
          final code = await showJuzzioMfaCodeDialog(context);
          var ok = false;
          if (code != null) {
            try {
              await JuzzioMfaService.instance.verifyLogin(code);
              ok = true;
            } catch (_) {}
          }
          if (!ok) {
            await Supabase.instance.client.auth.signOut();
            if (!mounted) return;
            setState(() {
              _booting = false;
              _errorText = JuzzioAppController.instance.trEn('İki adımlı doğrulama tamamlanmadı. Tekrar giriş yap.',
                  'Two-step verification was not completed. Please sign in again.', 'Zwei-Schritt-Verifizierung nicht abgeschlossen. Bitte erneut anmelden.');
            });
            return;
          }
          if (!mounted) return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              myDisplayName: uname,
              myLanguage: lang,
            ),
          ),
        );
      });
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // v1.2.3: iki kutu — zorunlu (koşullar + 15 yaş + aydınlatma beyanı) ve isteğe bağlı ticari ileti
  JuzzioConsentState _consent = const JuzzioConsentState();

  /// v2.1: şifre sıfırlama bağlantısı. Hesabın var olup olmadığı açıklanmaz (aynı yanıt).
  Future<void> _forgotPassword() async {
    final appCtrl = JuzzioAppController.instance;
    final initial = _usernameCtrl.text.contains('@') && _usernameCtrl.text.contains('.') ? _usernameCtrl.text.trim() : '';
    final ctrl = TextEditingController(text: initial);
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appCtrl.trEn('Şifreni sıfırla', 'Reset your password', 'Passwort zurücksetzen')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: appCtrl.trEn('Hesabındaki e-posta adresi', 'Your account email', 'E-Mail deines Kontos'),
            prefixIcon: const Icon(Icons.mail_outline_rounded),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(appCtrl.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(appCtrl.trEn('Bağlantı gönder', 'Send link', 'Link senden')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (email == null || !mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _errorText = appCtrl.trEn('Geçerli bir e-posta adresi yaz.', 'Enter a valid email address.', 'Gib eine gültige E-Mail-Adresse ein.'));
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
    } catch (_) {
      // hız sınırı vb. — kullanıcıya hesap varlığını sızdırmamak için aynı mesaj gösterilir
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(appCtrl.trEn(
        'Bu adrese kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi.',
        'If an account exists for this address, a reset link has been sent.',
        'Falls ein Konto existiert, wurde ein Link zum Zurücksetzen gesendet.',
      )),
    ));
  }

  /// v2.1: Google / Apple / GitHub ile giriş (yalnız JuzzioConfig.oauthProviders içindekiler görünür;
  /// sağlayıcı Supabase panelinde açılmış ve yönlendirme adresi eklenmiş olmalıdır).
  Future<void> _oauthSignIn(String provider) async {
    final appCtrl = JuzzioAppController.instance;
    if (!_consent.requiredAccepted) {
      final ok = await juzzioOpenRequiredConsent(context);
      if (!mounted || !ok) return;
      setState(() => _consent = _consent.copyWith(termsNotice: true));
    }
    final p = switch (provider) {
      'google' => OAuthProvider.google,
      'apple' => OAuthProvider.apple,
      'github' => OAuthProvider.github,
      _ => null,
    };
    if (p == null) return;
    try {
      await Supabase.instance.client.auth.signInWithOAuth(p, redirectTo: JuzzioConfig.oauthRedirect);
      await JuzzioConsentService.instance.record(_consent);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = appCtrl.trEn(
            'Bu giriş yöntemi şu an kullanılamıyor. Kullanıcı adı ve şifreyle giriş yapabilirsin.',
            'This sign-in method is unavailable right now. Use your username and password.',
            'Diese Anmeldeart ist gerade nicht verfügbar. Nutze Benutzername und Passwort.',
          ));
    }
  }

  Future<void> _submitAuth() async {
    final appCtrl = JuzzioAppController.instance;
    final s = JuzzioStrings(appCtrl.uiLang);

    setState(() => _errorText = null);

    // v1.2.3: zorunlu kutu (Kullanım Koşulları + 15 yaş + Aydınlatma "okudum ve anladım") verilmeden
    // kayıt olunamaz ve giriş yapılamaz. İşaretlenmemişse metin otomatik açılır; sonuna inip
    // "Okudum ve anladım"a basınca işlem kaldığı yerden devam eder.
    if (!_consent.requiredAccepted) {
      final ok = await juzzioOpenRequiredConsent(context);
      if (!mounted) return;
      if (!ok) {
        setState(() => _errorText = appCtrl.trEn(
              'Devam etmek için Kullanım Koşulları ve Aydınlatma Metni\'ni okuyup onaylayın.',
              'To continue, read and confirm the Terms of Use and Privacy Notice.',
              'Bitte lies und bestätige die Nutzungsbedingungen und den Datenschutzhinweis.',
            ));
        return;
      }
      setState(() => _consent = _consent.copyWith(termsNotice: true));
    }

    final password = _passwordCtrl.text;
    if (password.length < 6) {
      setState(() {
        _errorText = appCtrl.trEn(
          'Şifreniz en az 6 karakter olmalıdır.',
          'Password must be at least 6 characters.',
          'Das Passwort muss mindestens 6 Zeichen lang sein.',
        );
      });
      return;
    }

    if (_isRegisterMode) {
      final confirmPassword = _confirmPasswordCtrl.text;
      if (password != confirmPassword) {
        setState(() => _errorText = s.t('password_mismatch'));
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegisterMode) {
        final rawUser = _usernameCtrl.text.trim().replaceAll('@', '');
        final result = await SupabaseService.instance.registerAccount(
          username: rawUser,
          email: _emailCtrl.text.trim(),
          displayName: _fullNameCtrl.text.trim(),
          gender: _gender,
          password: password,
          preferredLang: appCtrl.subtitleLang,
        );

        await JuzzioConsentService.instance.record(_consent);
        if (!mounted) return;
        final uname = (result['username'] ?? rawUser).toString();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              myDisplayName: uname,
              myLanguage: appCtrl.subtitleLang,
            ),
          ),
        );
      } else {
        final result = await SupabaseService.instance.signInWithUsernameOrEmail(
          usernameOrEmail: _usernameCtrl.text.trim(),
          password: password,
          fallbackLang: appCtrl.subtitleLang,
          mfaCodePrompt: () => showJuzzioMfaCodeDialog(context),
        );

        await JuzzioConsentService.instance.record(_consent);
        appCtrl.setRememberedLoginId(_rememberMe ? _usernameCtrl.text.trim() : '');
        if (!mounted) return;
        final uname = (result['username'] ?? _usernameCtrl.text.trim()).toString().replaceAll('@', '');
        final lang = (result['preferredLang'] ?? appCtrl.subtitleLang).toString();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              myDisplayName: uname,
              myLanguage: lang,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } catch (e) {
      setState(() => _errorText = SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    // GM-002 (K2): ilk açılıştaki 2 tanıtım/izin ekranı kaldırıldı; açılış → (oturum yoksa) doğrudan
    // Giriş Yap / Kayıt Ol. Zemin: lime hero yalnız bu ekranda (K1); gece/gündüz temasından bağımsızdır.
    return Scaffold(
      // Klavye sayfayı küçültmez; JuzzioAuthLayout kendi içinde kaydırır ve odaktaki alanı gösterir.
      resizeToAvoidBottomInset: false,
      backgroundColor: JuzzioColorTokens.formDark,
      body: Stack(
        children: [
          // Açılış (splash) koyu AMOLED zeminde; lime hero yalnız giriş/kayıt görünürken (K1)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: appCtrl.reduceMotion ? Duration.zero : JuzzioMotion.fadeIn,
              child: _booting
                  ? const ColoredBox(key: ValueKey('bg_boot'), color: JuzzioColorTokens.appBackgroundDark, child: SizedBox.expand())
                  : const JuzzioAuthBackdrop(key: ValueKey('bg_auth')),
            ),
          ),
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: appCtrl.reduceMotion ? Duration.zero : JuzzioMotion.fadeIn,
              switchInCurve: Curves.easeOutCubic,
              child: _booting
                  ? const KeyedSubtree(key: ValueKey('boot'), child: JuzzioSplash())
                  : KeyedSubtree(key: const ValueKey('auth'), child: _buildAuthScreen(appCtrl)),
            ),
          ),
        ],
      ),
    );
  }

  /// K6: sağlayıcı yalnız (1) Supabase'de açıldığı derleme ayarıyla bildirildiyse (OAUTH_PROVIDERS) ve
  /// (2) bu platformda OAuth dönüş adresi (com.juzzio.app://login-callback) kayıtlıysa etkindir.
  /// Şu an dönüş adresi yalnız Android manifestinde kayıtlı; iOS/macOS/Windows için pasif kalır.
  bool _oauthAvailable(String provider) {
    if (!JuzzioConfig.oauthProviders.contains(provider)) return false;
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  void _socialUnavailable(String provider) {
    final appCtrl = JuzzioAppController.instance;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(appCtrl.trEn(
          'Bu giriş yöntemi bu cihazda henüz kullanılamıyor.',
          'This sign-in method isn’t available on this device yet.',
          'Diese Anmeldeart ist auf diesem Gerät noch nicht verfügbar.',
        )),
      ));
  }

  Widget _buildAuthScreen(JuzzioAppController appCtrl) {
    final reg = _isRegisterMode;
    return JuzzioAuthView(
      registerMode: reg,
      t: appCtrl.trEn,
      identifierController: _usernameCtrl,
      emailController: _emailCtrl,
      passwordController: _passwordCtrl,
      obscurePassword: _obscurePassword,
      onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
      rememberMe: _rememberMe,
      onRememberChanged: (v) => setState(() => _rememberMe = v),
      loading: _isLoading,
      errorText: _errorText,
      reduceMotion: appCtrl.reduceMotion,
      onSubmit: () {
        if (reg) {
          // v2.1 davranışı korunur: tasarımda şifre tekrarı ve ad alanı yok → ad = kullanıcı adı
          _confirmPasswordCtrl.text = _passwordCtrl.text;
          if (_fullNameCtrl.text.trim().isEmpty) {
            _fullNameCtrl.text = _usernameCtrl.text.trim().replaceAll('@', '');
          }
        }
        _submitAuth();
      },
      onForgotPassword: _forgotPassword,
      onToggleMode: () => setState(() {
        _isRegisterMode = !_isRegisterMode;
        _errorText = null;
      }),
      // Geri düğmesi yalnız gerçek bir geri işlemi olduğunda (kayıt → giriş). Girişte gidilecek yer yok.
      onBack: reg
          ? () => setState(() {
                _isRegisterMode = false;
                _errorText = null;
              })
          : null,
      socialEnabled: {for (final p in JuzzioAuthView.providers) p: _oauthAvailable(p)},
      onSocial: _oauthSignIn,
      onSocialUnavailable: _socialUnavailable,
    );
  }
}
