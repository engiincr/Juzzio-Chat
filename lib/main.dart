// =============================================================================
// JUZZIO v0.1.0 - Instagram.jpg Beyaz Tema ("Inspired people" / "Cool!" &
// "Turn on notifications") Onboarding + 139+ Dil Otomatik Cihaz Dili Algılama
// + R-RegularBold.otf & RBold-İtalic.otf Font Entegrasyonu
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme_and_locale.dart';
import 'core/config.dart';
import 'widgets/juzzio_desktop_frame.dart';
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
import 'core/theme/juzzio_colors.dart';
import 'core/theme/juzzio_aurora.dart';
import 'core/theme/juzzio_glass.dart';
import 'widgets/juzzio_motion.dart';
import 'widgets/juzzio_splash.dart';
import 'widgets/juzzio_consent.dart';
import 'widgets/juzzio_weather_ambience.dart';
import 'widgets/profile_extras.dart' show JuzzioMusicRouteObserver;
import 'core/juzzio_ui_sync.dart';
import 'widgets/juzzio_password_strength.dart';
import 'core/juzzio_text_safety.dart';
import 'core/juzzio_audio_guard.dart';
import 'widgets/juzzio_intro_motion.dart';
import 'widgets/juzzio_auth_hero.dart';
import 'widgets/juzzio_brand.dart';
import 'widgets/juzzio_neon_kit.dart';
import 'widgets/juzzio_a11y_filter.dart';
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
    final uname = (meta['username'] ?? meta['display_name'] ?? user.email?.split('@').first ?? 'Juzzio User')
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
          title: 'Juzzio',
          // v1.3.2 masaüstü: fare/dokunmatik yüzeyle sürükleyerek kaydırma
          scrollBehavior: const JuzzioScrollBehavior(),
          // v1.2.8: hava katmanı yalnız ana ekranda (tam ekran sayfaların üstüne binmez)
          navigatorObservers: [JuzzioAmbienceRouteObserver.instance, JuzzioMusicRouteObserver.instance],
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
  // 0 = Onboarding 1 (Instagram.jpg Left: Inspired people / Cool!),
  // 1 = Onboarding 2 (Instagram.jpg Right: Turn on notifications),
  // 2 = Kayıt Ol / Giriş Yap
  int _step = 0;
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
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final remembered = JuzzioAppController.instance.rememberedLoginId;
    if (remembered.isNotEmpty) _usernameCtrl.text = remembered;
    _boot();
  }

  static Future<File> _onboardingFlagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/juzzio_onboarding_done');
  }

  Future<void> _markOnboardingDone() async {
    try {
      final f = await _onboardingFlagFile();
      if (!f.existsSync()) await f.writeAsString('1');
    } catch (_) {}
  }

  /// Açılış: oturum varsa doğrudan Mesajlar'a gider (cihaz engeli ChatScreen'de denetlenir);
  /// oturum yoksa tanıtım yalnızca ilk kurulumda gösterilir, sonrasında giriş ekranı açılır.
  Future<void> _boot() async {
    if (_checkActiveSession()) return;
    var seen = false;
    try {
      seen = (await _onboardingFlagFile()).existsSync();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _step = seen ? 2 : 0;
      _booting = false;
    });
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
              'Juzzio User')
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
              _step = 2;
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

  Future<void> _handleTurnOnNotifications() async {
    try {
      await [
        Permission.notification,
        Permission.microphone,
        Permission.camera,
        Permission.photos,
        Permission.videos,
        Permission.ignoreBatteryOptimizations,
      ].request();
    } catch (_) {}
    if (!mounted) return;
    unawaited(_markOnboardingDone());
    setState(() => _step = 2);
  }

  // v1.2.3: iki kutu — zorunlu (koşullar + 15 yaş + aydınlatma beyanı) ve isteğe bağlı ticari ileti
  JuzzioConsentState _consent = const JuzzioConsentState();
  bool _consentError = false;

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
      setState(() => _consentError = true);
      final ok = await juzzioOpenRequiredConsent(context);
      if (!mounted || !ok) return;
      setState(() {
        _consent = _consent.copyWith(termsNotice: true);
        _consentError = false;
      });
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
      setState(() => _consentError = true);
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
      setState(() {
        _consent = _consent.copyWith(termsNotice: true);
        _consentError = false;
      });
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
    // İlk iki karşılama adımı ("Harika!" ve "Bildirimleri aç") kullanıcının
    // isteğiyle özgün görünümünde kalır; giriş/kayıttan itibaren cam tema.
    // v1.2.9 düzeltme: karşılama adımları açık zemine ZORLANIYORDU ama yazı renkleri gerçek temadan
    // geliyordu → koyu temada açık zemin üstünde beyaz yazı (okunmuyordu). Zemin de yazı da artık
    // aynı kaynaktan (gerçek gece/gündüz modu) gelir.
    // v1.2.9 düzeltme (2): açık zeminde beyaz yazı / koyu kart sorunu sürüyordu çünkü zemin ile yazı
    // rengi farklı kaynaklardan gelebiliyordu (gece-gündüz modu, özel tema, hava teması). Artık zemin,
    // GERÇEKTE kullanılan yazı renginden türetilir ve opaktır: yazı açıksa zemin koyu, yazı koyuysa
    // zemin açık. Karşılama, bildirim izni ve giriş/kayıt sayfalarında karşıtlık her koşulda sağlanır.
    final lightText = JuzzioGlassTokens.textPrimary.computeLuminance() > 0.5;
    final p = JuzzioPalette(lightText);
    final s = JuzzioStrings(appCtrl.uiLang);
    final authBg = (!_booting && _step >= 2)
        // v2.1 (tasarım: Giriş/Kayıt): üst yarı limon, alt yarı koyu
        ? const [Color(0xFF8DB02E), Color(0xFF0E0F10), Color(0xFF0E0F10)]
        : lightText
            ? const [Color(0xFF050916), Color(0xFF0A1230), Color(0xFF070B1C)]
            : const [Color(0xFFF6F8FE), Color(0xFFE9EEFA), Color(0xFFF3F6FD)];

    return Scaffold(
      backgroundColor: authBg.first,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: authBg)),
        child: SafeArea(
          child: Column(
            children: [
              // v2.1: giriş/kayıt sayfasında üst çubuk yok (tasarım: sayfanın kendi başlığı var)
              if (_booting || _step < 2) _buildTopBar(p, s, appCtrl),
              Expanded(
                // v1.2.9: karşılama → bildirim → giriş/kayıt arasında akıcı sayfa geçişi
                // (paylaşılan eksen: yeni sayfa sağdan süzülür + hafif büyür, eskisi sola kayıp söner)
                // ve arkada adıma göre yer değiştiren yumuşak renk lekeleri
                child: Stack(
                  children: [
                    if (!_booting && _step < 2 && !appCtrl.reduceMotion) Positioned.fill(child: IgnorePointer(child: JuzzioIntroBlobs(step: _step))),
                    AnimatedSwitcher(
                      duration: Duration(milliseconds: appCtrl.reduceMotion ? 0 : 560),
                      reverseDuration: Duration(milliseconds: appCtrl.reduceMotion ? 0 : 380),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: juzzioIntroTransition,
                      child: KeyedSubtree(
                        key: ValueKey(_booting ? -1 : _step),
                        child: _booting
                            ? const JuzzioSplash()
                            : _step == 0
                            ? JuzzioStaggerIn(child: _buildOnboardingStep1Cool(p, s))
                            : _step == 1
                                ? JuzzioStaggerIn(child: _buildOnboardingStep2Notifications(p, s, appCtrl))
                                : JuzzioStaggerIn(child: _buildAuthScreen(p, s, appCtrl)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    final langOpt = appCtrl.getLanguageOption(appCtrl.uiLang);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: JuzzioColors.ink,
              borderRadius: BorderRadius.circular(12),
              boxShadow: p.softCardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/logo/juzzio_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Juzzio',
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: p.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          // 139+ Dil Hızlı Seçici Kapsülü (Giriş / Kayıt ekranı dahil her yerde dil değiştirilebilir)
          GestureDetector(
            onTap: () {
              JuzzioLanguagePickerSheet.show(
                context,
                title: s.t('app_lang_title'),
                subtitle: s.t('app_lang_sub'),
                currentCode: appCtrl.uiLang,
                onSelected: (code) {
                  juzzioSwitchUiLanguage(context, code, alsoSubtitle: true);
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
              decoration: BoxDecoration(
                color: p.pillBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(langOpt.flag, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(
                    langOpt.code.toUpperCase(),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary, size: 15),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: appCtrl.toggleThemeMode,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.pillBg,
                shape: BoxShape.circle,
                border: Border.all(color: p.glassBorder),
              ),
              child: JuzzioSymbolSwap(
                child: Icon(
                  appCtrl.isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                  key: ValueKey(appCtrl.isDark),
                  color: p.textPrimary,
                  size: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Instagram.jpg Sol Ekran: "Inspired people" + "Cool!" Geniş Siyah Hap Buton
  Widget _buildOnboardingStep1Cool(JuzzioPalette p, JuzzioStrings s) {
    // İlk iki karşılama ekranı v0.5.0 cam temasından muaftır: özgün renkler sabit tutulur
    const orbitColors = [
      Color(0xFF1F2937),
      Color(0xFF8E8E93),
      JuzzioColors.amber500,
      JuzzioColors.emerald500,
      Color(0xFF9A9AA0),
      Color(0xFFC7C7CC),
      JuzzioColors.red500,
      JuzzioColors.teal500,
      Color(0xFF636366),
      JuzzioColors.amber600,
    ];
    const orbitInitials = ['M', 'S', 'V', 'K', 'A', 'L', 'T', 'N', 'R', 'E'];

    return Padding(
      key: const ValueKey('onb1_cool'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: Column(
        children: [
          const Spacer(),
          SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Yumuşak eşmerkezli halkalar (Instagram.jpg sol görseldeki gibi)
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : JuzzioColors.surfaceF5F6FA,
                  ),
                ),
                Container(
                  width: 175,
                  height: 175,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : JuzzioColors.surfaceECEFF5.withValues(alpha: 0.7),
                  ),
                ),
                // Yörüngedeki yuvarlatılmış kare profil kartları
                ...List.generate(10, (i) {
                  final angle = (i * 2 * math.pi / 10) - math.pi / 2;
                  final radius = i.isEven ? 114.0 : 104.0;
                  final dx = radius * math.cos(angle);
                  final dy = radius * math.sin(angle);
                  final size = i % 3 == 0 ? 48.0 : 42.0;
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.rotate(
                      angle: (i.isEven ? 0.12 : -0.12),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: orbitColors[i % orbitColors.length],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          orbitInitials[i],
                          style: const TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                // Merkezdeki büyük yuvarlatılmış kare portre kartı
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [JuzzioColors.surface23252C, JuzzioColors.surface141519],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.translate_rounded, color: Colors.white, size: 42),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            s.t('onb1_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: p.textPrimary,
              fontSize: 29,
              height: 1.18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.t('onb1_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: JuzzioCoolPillButton(
              label: s.t('onb1_cta'),
              height: 58,
              onTap: () => setState(() => _step = 1),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  /// Instagram.jpg Sağ Ekran: "Lia Maria / Tom Avril" Bildirim Önizlemesi + "Turn on notifications" Siyah Hap Buton
  Widget _buildOnboardingStep2Notifications(
    JuzzioPalette p,
    JuzzioStrings s,
    JuzzioAppController appCtrl,
  ) {
    return Padding(
      key: const ValueKey('onb2_notif'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          const Spacer(),
          // Instagram.jpg Sağ Görseldeki Pembe-Lavanta Telefon Çerçevesi ve Yüzen Beyaz Bildirim Kartları
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: p.isDark
                    ? const [JuzzioColors.surface2B1E2E, JuzzioColors.surface181A22]
                    : const [JuzzioColors.pink50, JuzzioColors.purple50, JuzzioColors.white],
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: p.isDark ? Colors.white24 : JuzzioColors.surface3A1D2E,
                width: 2.2,
              ),
              boxShadow: p.softCardShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 24,
                  decoration: BoxDecoration(
                    color: JuzzioColors.surface280D1D,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  appCtrl.trEn('Pazartesi, 28 Ekim', 'Monday, October 28', 'Montag, 28. Oktober'),
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.isDark ? Colors.white70 : JuzzioColors.surface6B4C62,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '9:41',
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.isDark ? Colors.white.withValues(alpha: 0.85) : JuzzioColors.surface4A2E40.withValues(alpha: 0.55),
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMockNotificationCard(
                  avatarColor: JuzzioColors.sky400,
                  badgeIcon: Icons.videocam_rounded,
                  badgeColor: JuzzioColors.blue600,
                  name: 'Lia Maria',
                  body: appCtrl.trEn(
                    'Görüntülü arama başlattı • Canlı çeviri hazır',
                    'Started a video call • Live translation ready',
                    'Hat einen Videoanruf gestartet • Live-Übersetzung',
                  ),
                  timeLabel: appCtrl.trEn('şimdi', 'now', 'jetzt'),
                ),
                const SizedBox(height: 10),
                _buildMockNotificationCard(
                  avatarColor: JuzzioColors.purple400,
                  badgeIcon: Icons.translate_rounded,
                  badgeColor: JuzzioColors.emerald500,
                  name: 'Tom Avril',
                  body: appCtrl.trEn(
                    'Yeni sesli mesaj gönderdi (Otomatik çevrildi)',
                    'Sent a new voice message (auto-translated)',
                    'Hat eine Sprachnotiz gesendet (Übersetzt)',
                  ),
                  timeLabel: appCtrl.trEn('2 dk', '2m', '2 Min.'),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            s.t('onb2_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              color: p.textPrimary,
              fontSize: 25,
              height: 1.22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s.t('onb2_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: JuzzioCoolPillButton(
              label: s.t('onb2_cta'),
              height: 56,
              onTap: _handleTurnOnNotifications,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              unawaited(_markOnboardingDone());
              setState(() => _step = 2);
            },
            child: Text(
              s.t('skip'),
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: p.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMockNotificationCard({
    required Color avatarColor,
    required IconData badgeIcon,
    required Color badgeColor,
    required String name,
    required String body,
    required String timeLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: avatarColor.withValues(alpha: 0.25),
                child: Text(
                  juzzioInitial(name),
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(badgeIcon, color: Colors.white, size: 10),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: JuzzioColors.surface141519,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JuzzioColors.surface686D78,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeLabel,
            style: const TextStyle(
              color: JuzzioColors.surface9AA0AC,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // v2.1 — Giriş Yap / Kayıt Ol (tasarım şablonu birebir)
  //  Üst yarı limon sahne: geri düğmesi, ortada J Juzzio, yüzen emojiler, ses hapı ve büyük J logosu.
  //  Alt yarı limon kenarlı cam kart: "Giriş Yap"/"Hesap Oluştur" hapı, limon vurgulu başlık, hap
  //  alanlar, Beni hatırla / Şifremi unuttum, limon "→" düğmesi, "veya", Google · Apple · GitHub.
  //  Kullanım Koşulları onayı gönderirken (henüz verilmediyse) metin açılarak alınır.
  // ===========================================================================
  Widget _buildAuthScreen(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    const lime = JuzzioBrandColors.lime;
    final reg = _isRegisterMode;
    String t(String tr, String en, String de) => appCtrl.trEn(tr, en, de);

    Widget field({
      required TextEditingController c,
      required String hint,
      required IconData icon,
      bool obscure = false,
      Widget? suffix,
      TextInputType? type,
    }) {
      // v2.1 Liquid Glass alan: arkası bulanık, yarı saydam
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: TextField(
        controller: c,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: type,
        textCapitalization: TextCapitalization.none,
        cursorColor: lime,
        style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14.5),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 18, right: 10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.12),
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.26))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.26))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: lime, width: 1.8)),
        ),
          ),
        ),
      );
    }

    Widget social(String provider) {
      final Widget mark = switch (provider) {
        'google' => const JuzzioGoogleMark(size: 26),
        'apple' => const Icon(Icons.apple, size: 30, color: Colors.white),
        _ => const JuzzioGithubMark(size: 28),
      };
      return GestureDetector(
        onTap: _isLoading
            ? null
            : () {
                if (JuzzioConfig.oauthProviders.contains(provider)) {
                  _oauthSignIn(provider);
                } else {
                  setState(() => _errorText = t(
                      '${provider == 'google' ? 'Google' : provider == 'apple' ? 'Apple' : 'GitHub'} ile giriş yakında açılacak. Şimdilik kullanıcı adı ve şifreyle devam et.',
                      'Sign-in with ${provider == 'google' ? 'Google' : provider == 'apple' ? 'Apple' : 'GitHub'} is coming soon. Use your username and password for now.',
                      'Anmeldung mit ${provider == 'google' ? 'Google' : provider == 'apple' ? 'Apple' : 'GitHub'} folgt bald.'));
                }
              },
        child: Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          alignment: Alignment.center,
          child: mark,
        ),
      );
    }

    final title = reg ? t("Juzzio'ya ", 'Join ', 'Willkommen bei ') : t('Tekrar Hoş ', 'Welcome ', 'Willkommen ');
    final titleMark = reg ? t('Katıl', 'Juzzio', 'Juzzio') : t('Geldin!', 'back!', 'zurück!');

    // Kartın içeriği (tasarım ölçüleri; küçük ekranlarda bütünüyle orantılı küçülür → kaydırma yok)
    final cardColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
          child: Text(reg ? t('Hesap Oluştur', 'Create Account', 'Konto erstellen') : t('Giriş Yap', 'Sign In', 'Anmelden'),
              style: const TextStyle(color: Color(0xFF111113), fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(height: 12),
        JuzzioMarkedTitle(
          prefix: title,
          mark: titleMark,
          suffix: reg ? '' : ' 👋',
          scribbleColor: lime,
          style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              fontFamilyFallback: kJuzzioEmojiFallback,
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6),
        ),
        const SizedBox(height: 6),
        Text(
          reg
              ? t('Arkadaşlarınla bağlan, dünyanın her yerinden\ninsanlarla sohbet et.',
                  'Connect with friends and chat with\npeople all over the world.', 'Verbinde dich mit Freunden und\nchatte weltweit.')
              : t('Juzzio hesabına giriş yap, arkadaşlarınla\nkaldığın yerden devam et.',
                  'Sign in to Juzzio and pick up where\nyou left off with your friends.', 'Melde dich bei Juzzio an und mach\nweiter, wo du aufgehört hast.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        if (reg) ...[
          field(c: _usernameCtrl, hint: t('Kullanıcı adı', 'Username', 'Benutzername'), icon: Icons.person_outline_rounded),
          const SizedBox(height: 10),
          field(c: _emailCtrl, hint: t('E-posta adresi', 'Email address', 'E-Mail-Adresse'), icon: Icons.mail_outline_rounded, type: TextInputType.emailAddress),
        ] else
          field(
              c: _usernameCtrl,
              hint: t('E-posta adresi veya kullanıcı adı', 'Email or username', 'E-Mail oder Benutzername'),
              icon: Icons.mail_outline_rounded,
              type: TextInputType.emailAddress),
        const SizedBox(height: 10),
        field(
          c: _passwordCtrl,
          hint: t('Şifre', 'Password', 'Passwort'),
          icon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          suffix: IconButton(
            padding: const EdgeInsets.only(right: 14),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white),
          ),
        ),
        if (!reg) ...[
          const SizedBox(height: 12),
          Row(children: [
            GestureDetector(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _rememberMe ? lime : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: lime, width: 1.6),
                  ),
                  child: _rememberMe ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF111113)) : null,
                ),
                const SizedBox(width: 10),
                Text(t('Beni hatırla', 'Remember me', 'Angemeldet bleiben'),
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500)),
              ]),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _forgotPassword,
              child: Text(t('Şifremi unuttum?', 'Forgot password?', 'Passwort vergessen?'),
                  style: const TextStyle(color: lime, fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 10),
          Text(_errorText!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    if (reg) {
                      // tasarımda şifre tekrarı ve ad alanı yok: ad = kullanıcı adı
                      _confirmPasswordCtrl.text = _passwordCtrl.text;
                      if (_fullNameCtrl.text.trim().isEmpty) {
                        _fullNameCtrl.text = _usernameCtrl.text.trim().replaceAll('@', '');
                      }
                    }
                    _submitAuth();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: lime,
              disabledBackgroundColor: lime.withValues(alpha: 0.6),
              foregroundColor: const Color(0xFF111113),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: _isLoading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF111113)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_forward_rounded, size: 24),
                    const SizedBox(width: 12),
                    Text(reg ? t('Kayıt Ol', 'Sign Up', 'Registrieren') : t('Giriş Yap', 'Sign In', 'Anmelden'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ]),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18), indent: 28)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(t('veya', 'or', 'oder'), style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
          ),
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18), endIndent: 28)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [social('google'), social('apple'), social('github')]),
        const SizedBox(height: 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(reg ? t('Zaten hesabın var mı? ', 'Already have an account? ', 'Schon ein Konto? ') : t('Hesabın yok mu? ', "Don't have an account? ", 'Noch kein Konto? '),
                style: const TextStyle(color: Colors.white, fontSize: 14.5)),
            GestureDetector(
              onTap: () => setState(() {
                _isRegisterMode = !_isRegisterMode;
                _errorText = null;
              }),
              child: Text(reg ? t('Giriş Yap', 'Sign In', 'Anmelden') : t('Hesap Oluştur', 'Create Account', 'Konto erstellen'),
                  style: const TextStyle(color: lime, fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '© ${DateTime.now().year} Juzzio · ${t('Tüm hakları saklıdır.', 'All rights reserved.', 'Alle Rechte vorbehalten.')}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    );

    final cardDecoration = BoxDecoration(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(44)),
      // buzlu cam: arkadaki sahne hafifçe görünür (BackdropFilter ile bulanık)
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF2B3A1C).withValues(alpha: 0.72), const Color(0xFF17191A).withValues(alpha: 0.86), const Color(0xFF0E0F10).withValues(alpha: 0.94)],
      ),
      border: Border.all(color: lime.withValues(alpha: 0.8), width: 1.4),
      boxShadow: [BoxShadow(color: lime.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, -4))],
    );

    Widget topRow() => SizedBox(
          height: 58,
          child: Stack(children: [
            Positioned(
              left: 18,
              top: 6,
              child: GestureDetector(
                onTap: () {
                  if (reg) {
                    setState(() {
                      _isRegisterMode = false;
                      _errorText = null;
                    });
                  } else {
                    setState(() => _step = 1);
                  }
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.22)),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
            const Positioned(top: 8, left: 0, right: 0, child: Center(child: JuzzioWordmark(size: 30, color: Colors.white))),
          ]),
        );

    return LayoutBuilder(
      key: const ValueKey('auth_screen'),
      builder: (context, box) {
        // Klavye açıkken alanlar görünür kalsın diye doğal boyutta kaydırılabilir düzen
        if (MediaQuery.viewInsetsOf(context).bottom > 0) {
          return SingleChildScrollView(
            child: Column(children: [
              topRow(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                decoration: cardDecoration,
                child: cardColumn,
              ),
            ]),
          );
        }
        // Tek ekran (kaydırmasız): üstte görseldeki sahne, altta kart — her ekran boyutunda sığar
        final heroH = box.maxHeight * 0.40;
        return Stack(
          children: [
            // Tasarım görselindeki sahne (kadın, emojiler, ses hapı) — genişliğe oturur, alttan karta girer
            // görseldeki limon zemin rengi (görselin kenarlarıyla birebir)
            Positioned(left: 0, right: 0, top: 0, height: heroH + 30, child: const ColoredBox(color: Color(0xFFAFD939))),
            Positioned(
              left: 0,
              right: 0,
              top: 58,
              height: heroH - 58 + 30,
              child: ClipRect(child: Image.asset(
                'assets/images/auth_hero.jpg',
                fit: BoxFit.fitWidth,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
              )),
            ),
            // canlı limonu yumuşatan hafif koyu örtü (üstte ve karta doğru)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: heroH + 30,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0.08), Colors.black.withValues(alpha: 0.30)],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 0, right: 0, top: 0, child: topRow()),
            Positioned(
              left: 0,
              right: 0,
              top: heroH,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(44)),
                child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                decoration: cardDecoration,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: (box.maxWidth - 48).clamp(260.0, 520.0), child: cardColumn),
                ),
              ),
              ),
              ),
            ),
          ],
        );
      },
    );
  }
}
