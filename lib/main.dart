// =============================================================================
// JUZZIO v0.1.0 - Instagram.jpg Beyaz Tema ("Inspired people" / "Cool!" &
// "Turn on notifications") Onboarding + 139+ Dil Otomatik Cihaz Dili Algılama
// + R-RegularBold.otf & RBold-İtalic.otf Font Entegrasyonu
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme_and_locale.dart';
import 'core/config.dart';
import 'core/native_bridge.dart';
import 'screens/chat_screen.dart';
import 'services/fcm_push_service.dart';
import 'services/juzzio_quick_reply.dart';
import 'services/supabase_service.dart';
import 'services/juzzio_features_service.dart';
import 'screens/banned_screen.dart';
import 'core/theme/juzzio_colors.dart';
import 'core/theme/juzzio_aurora.dart';
import 'core/theme/juzzio_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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

  // Glassmorphism: her sayfanın arkasındaki aurora zemini seçili cam temasını izler
  final appCtrl = JuzzioAppController.instance;
  JuzzioAuroraScope.palette = () => appCtrl.glassPalette;
  JuzzioAuroraScope.isDark = () => appCtrl.isDark;
  JuzzioAuroraScope.listenable = appCtrl;
  // v0.7.0: cam belirteçleri (metin/zemin/kenar renkleri) tema duyarlı
  JuzzioGlassTokens.isDarkResolver = () => appCtrl.isDark;
  // v0.8.4: hazır temanın cam karakteri (özel temada standart karakter)
  JuzzioGlassTokens.characterResolver = () => appCtrl.glassPalette.character;
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

  // Düşük donanımlı cihazda blur fallback (kullanıcı seçimi her zaman önceliklidir)
  JuzzioNative.isLowEndDevice().then((low) => appCtrl.applyDeviceProfile(lowEnd: low));

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
  var ok = false;
  try {
    await Supabase.initialize(url: JuzzioConfig.supabaseUrl, anonKey: JuzzioConfig.supabaseAnonKey);
    final req = await channel.invokeMapMethod<String, dynamic>('take');
    if (req != null) {
      ok = await JuzzioQuickReply.send(roomId: '${req['room_id'] ?? ''}', text: '${req['text'] ?? ''}');
    }
  } catch (_) {
    ok = false;
  }
  try {
    await channel.invokeMethod('result', {'ok': ok});
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

const Set<String> _kRtlLangs = {'ar', 'fa', 'he', 'iw', 'ur', 'ps', 'ckb', 'yi', 'sd', 'ug', 'dv'};

bool juzzioIsRtl(String uiLang) => _kRtlLangs.contains(uiLang.toLowerCase().split(RegExp('[-_]')).first) || uiLang.toLowerCase() == 'ckb';

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
    return ChatScreen(myDisplayName: uname, myLanguage: lang);
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
              child: child ?? const SizedBox.shrink(),
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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

  Future<void> _submitAuth() async {
    final appCtrl = JuzzioAppController.instance;
    final s = JuzzioStrings(appCtrl.uiLang);

    setState(() => _errorText = null);

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
        );

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
    final onboarding = !_booting && _step < 2;
    final p = JuzzioPalette(onboarding ? false : appCtrl.isDark);
    final s = JuzzioStrings(appCtrl.uiLang);

    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Giriş/kayıttan itibaren nötr cam zemin; ilk iki karşılama adımı özgün kalır
        decoration: onboarding ? BoxDecoration(gradient: p.backgroundGradient) : JuzzioGlassTokens.backdrop,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(p, s, appCtrl),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _booting
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                      : _step == 0
                      ? _buildOnboardingStep1Cool(p, s)
                      : _step == 1
                          ? _buildOnboardingStep2Notifications(p, s, appCtrl)
                          : _buildAuthScreen(p, s, appCtrl),
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
              child: Icon(
                appCtrl.isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                color: p.textPrimary,
                size: 17,
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
                        ? Colors.white.withOpacity(0.02)
                        : JuzzioColors.surfaceF5F6FA,
                  ),
                ),
                Container(
                  width: 175,
                  height: 175,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.isDark
                        ? Colors.white.withOpacity(0.03)
                        : JuzzioColors.surfaceECEFF5.withOpacity(0.7),
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
                              color: Colors.black.withOpacity(0.14),
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
                        color: Colors.black.withOpacity(0.18),
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
                    color: p.isDark ? Colors.white.withOpacity(0.85) : JuzzioColors.surface4A2E40.withOpacity(0.55),
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
            color: Colors.black.withOpacity(0.08),
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
                backgroundColor: avatarColor.withOpacity(0.25),
                child: Text(
                  name.substring(0, 1),
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

  Widget _buildAuthScreen(JuzzioPalette p, JuzzioStrings s, JuzzioAppController appCtrl) {
    return SingleChildScrollView(
      key: const ValueKey('auth_screen'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Sekme: Giriş Yap / Kayıt Ol (Instagram.jpg Hap Tasarımı)
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: p.pillBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.glassBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isRegisterMode = false;
                      _errorText = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: !_isRegisterMode ? (p.isDark ? Colors.white : JuzzioColors.ink) : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.t('login_tab'),
                        style: TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: !_isRegisterMode ? (p.isDark ? const Color(0xFF111113) : Colors.white) : p.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isRegisterMode = true;
                      _errorText = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _isRegisterMode ? (p.isDark ? Colors.white : JuzzioColors.ink) : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.t('register_tab'),
                        style: TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: _isRegisterMode ? (p.isDark ? const Color(0xFF111113) : Colors.white) : p.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // v0.5.0: "Hey" kaldırıldı. Kayıtta Ad Soyad alanına yazılan İLK ad her
          // tuşta canlı güncellenir: "Hoşgeldin! E" → "Hoşgeldin! Engin" (soyad eklenmez).
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _fullNameCtrl,
            builder: (context, value, _) {
              final parts = value.text.trim().split(RegExp(r'\s+'));
              final firstName = _isRegisterMode && parts.isNotEmpty ? parts.first : '';
              final hello = appCtrl.trEn('Hoşgeldin!', 'Welcome!', 'Willkommen!');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _isRegisterMode ? hello : appCtrl.trEn('Tekrar hoşgeldin!', 'Welcome back!', 'Willkommen zurück!'),
                        ),
                        if (firstName.isNotEmpty)
                          TextSpan(
                            text: ' $firstName',
                            style: TextStyle(color: p.textPrimary.withValues(alpha: 0.72)),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                  if (_isRegisterMode) ...[
                    const SizedBox(height: 2),
                    Text(
                      appCtrl.trEn('Hesap Oluştur', 'Create Account', 'Konto erstellen'),
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textSecondary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          // Kısa slogan (giriş ve kayıtta)
          Text(
            appCtrl.trEn(
              'Dil engeline takılmadan dünyayla konuş, özgürce ilham al.',
              'Talk to the world without language barriers and get inspired freely.',
              'Sprich ohne Sprachbarrieren mit der Welt und lass dich frei inspirieren.',
            ),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: p.glassBorder),
              boxShadow: p.softCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isRegisterMode ? s.t('username_label') : s.t('username_or_email_label'),
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameCtrl,
                  // Kullanıcı adı: otomatik düzeltme / büyük harf / öneri kapalı
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.visiblePassword,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: _isRegisterMode ? s.t('username_hint') : s.t('username_or_email_hint'),
                    hintStyle: TextStyle(color: p.textMuted),
                    prefixIcon: Icon(Icons.alternate_email_rounded, color: p.textPrimary, size: 20),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                  ),
                ),
                if (_isRegisterMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    appCtrl.t('full_name_label'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fullNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: appCtrl.t('full_name_hint'),
                      hintStyle: TextStyle(color: p.textMuted),
                      counterText: '',
                      prefixIcon: Icon(Icons.badge_outlined, color: p.textPrimary, size: 20),
                      filled: true,
                      fillColor: p.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appCtrl.t('gender_label'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in const ['female', 'male', 'unspecified'])
                        ChoiceChip(
                          label: Text(appCtrl.t('gender_$g')),
                          selected: _gender == g,
                          onSelected: (_) => setState(() => _gender = g),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appCtrl.t('gender_private_note'),
                    style: TextStyle(color: p.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.t('email_label'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: s.t('email_hint'),
                      hintStyle: TextStyle(color: p.textMuted),
                      prefixIcon: Icon(Icons.mail_outline_rounded, color: p.textPrimary, size: 20),
                      filled: true,
                      fillColor: p.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  s.t('password_label'),
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: s.t('password_hint'),
                    hintStyle: TextStyle(color: p.textMuted),
                    prefixIcon: Icon(Icons.lock_outline_rounded, color: p.textPrimary, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: p.textMuted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                  ),
                ),
                if (_isRegisterMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    s.t('password_confirm_label'),
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPasswordCtrl,
                    obscureText: _obscureConfirmPassword,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: s.t('password_confirm_hint'),
                      hintStyle: TextStyle(color: p.textMuted),
                      prefixIcon: Icon(Icons.verified_user_outlined, color: p.textPrimary, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: p.textMuted,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                      filled: true,
                      fillColor: p.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: p.glassBorder),
                      ),
                    ),
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.dangerRed.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.dangerRed.withOpacity(0.40)),
                    ),
                    child: Text(
                      _errorText!,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.dangerRed,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                JuzzioCoolPillButton(
                  label: _isRegisterMode ? s.t('register_btn') : s.t('login_btn'),
                  isLoading: _isLoading,
                  onTap: _submitAuth,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
