// Juzzio 2.1 — Ayarlar (Neon Lime) yardımcı ekranları
//
// * [JuzzioCallSettingsPage]   — Faz 8.1 "Arama Ayarları"
// * [showJuzzioLogoutDialog]   — Faz 9.3 "Çıkış Yap" onay penceresi
// * [JuzzioTwoFactorPage]      — Faz 7.3 İki adımlı doğrulama (TOTP)
// * [showJuzzioMfaCodeDialog]  — girişte/açılışta 6 haneli kod
//
// Buradaki her anahtar uygulamada gerçekten kullanılan bir tercihe bağlıdır
// (veri tasarrufu → 480p·60 fps kamera, gürültü engelleme → mikrofon işleme, vb.).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../core/theme/juzzio_aurora.dart';
import '../../widgets/juzzio_brand.dart';
import '../../widgets/juzzio_neon_kit.dart';
import '../../services/juzzio_mfa_service.dart';
import '../../services/social_service.dart';
import '../social/juzzio_discover_view.dart';
import '../sound_settings_page.dart';

class JuzzioCallSettingsPage extends StatelessWidget {
  const JuzzioCallSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final quality = app.dataSaverEnabled
            ? app.trEn('Düşük veri · 480p · 60 fps', 'Low data · 480p · 60 fps', 'Datensparen · 480p · 60 fps')
            : app.trEn('En yüksek · 1080p · 60 fps', 'Highest · 1080p · 60 fps', 'Höchste · 1080p · 60 fps');
        return JuzzioAuroraPage(child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                JuzzioScreenHeader(
                  title: app.trEn('Arama Ayarları', 'Call Settings', 'Anrufeinstellungen'),
                  subtitle: app.trEn('Sesli ve görüntülü aramalarını özelleştir.', 'Customise voice and video calls.',
                      'Sprach- und Videoanrufe anpassen.'),
                ),
                JuzzioNeonSectionLabel(app.trEn('Görüntü ve veri', 'Video & data', 'Video & Daten')),
                JuzzioNeonGroup(children: [
                  JuzzioNeonRow(
                    icon: Icons.hd_outlined,
                    title: app.trEn('Görüntü kalitesi', 'Video quality', 'Videoqualität'),
                    value: quality,
                    showChevron: false,
                  ),
                  JuzzioNeonRow.toggle(
                    icon: Icons.data_saver_on_outlined,
                    title: app.trEn('Düşük veri kullanımı', 'Low data usage', 'Wenig Daten'),
                    subtitle: app.trEn('Kamera 480p · 60 fps gönderilir (akıcılık korunur), mobil veriden tasarruf edilir',
                        'Camera is sent at 480p · 60 fps (stays smooth) to save mobile data', 'Kamera mit 480p · 60 fps, spart mobile Daten'),
                    value: app.dataSaverEnabled,
                    onChanged: app.setDataSaverEnabled,
                  ),
                  JuzzioNeonRow.toggle(
                    icon: Icons.battery_saver_outlined,
                    title: app.trEn('Arama pil tasarrufu', 'Call battery saver', 'Anruf-Akkusparen'),
                    subtitle: app.trEn('Arka plan ölçümleri seyrekleşir', 'Background checks run less often',
                        'Hintergrundprüfungen seltener'),
                    value: app.callBatterySaverEnabled,
                    onChanged: app.setCallBatterySaverEnabled,
                  ),
                ]),
                JuzzioNeonSectionLabel(app.trEn('Ses', 'Audio', 'Audio')),
                JuzzioNeonGroup(children: [
                  JuzzioNeonRow.toggle(
                    icon: Icons.graphic_eq_rounded,
                    title: app.trEn('Gürültü engelleme', 'Noise suppression', 'Rauschunterdrückung'),
                    subtitle: app.trEn('Arka plan sesini ve yankıyı azaltır', 'Reduces background noise and echo',
                        'Reduziert Hintergrundgeräusche und Echo'),
                    value: app.callNoiseFilterEnabled,
                    onChanged: app.setCallNoiseFilterEnabled,
                  ),
                  JuzzioNeonRow(
                    icon: Icons.music_note_outlined,
                    title: app.trEn('Zil ve arama sesleri', 'Ringtone & call sounds', 'Klingelton & Anruftöne'),
                    onTap: () => JuzzioSoundSettingsPage.open(context),
                  ),
                ]),
                JuzzioNeonSectionLabel(app.trEn('Gizlilik', 'Privacy', 'Datenschutz')),
                JuzzioNeonGroup(children: [
                  JuzzioNeonRow.toggle(
                    icon: Icons.shield_outlined,
                    title: app.trEn('Aramalarda IP adresini koru', 'Protect IP address in calls', 'IP-Adresse in Anrufen schützen'),
                    subtitle: app.trEn('Bağlantı Trawave sunucusu üzerinden aktarılır', 'Calls are relayed through Trawave servers',
                        'Anrufe laufen über Trawave-Server'),
                    value: app.protectIpInCalls,
                    onChanged: app.setProtectIpInCalls,
                  ),
                  JuzzioNeonRow.toggle(
                    icon: Icons.phone_disabled_outlined,
                    title: app.trEn('Bilinmeyen arayanları sustur', 'Silence unknown callers', 'Unbekannte stummschalten'),
                    value: app.silenceUnknownCallers,
                    onChanged: app.setSilenceUnknownCallers,
                  ),
                ]),
                JuzzioNeonSectionLabel(app.trEn('Arama sırasında', 'During a call', 'Während eines Anrufs')),
                JuzzioNeonGroup(children: [
                  JuzzioNeonRow(
                    icon: Icons.screen_share_outlined,
                    title: app.trEn('Ekran paylaşımı', 'Screen sharing', 'Bildschirmfreigabe'),
                    subtitle: app.trEn('Görüntülü aramada üst çubuktaki düğmeyle başlatılır; her seferinde izin istenir',
                        'Start from the top bar in a video call; permission is asked every time',
                        'Über die obere Leiste im Videoanruf; Erlaubnis wird jedes Mal abgefragt'),
                    showChevron: false,
                  ),
                  JuzzioNeonRow(
                    icon: Icons.translate_rounded,
                    title: app.trEn('Canlı çeviri', 'Live translation', 'Live-Übersetzung'),
                    subtitle: app.trEn('Aramada çeviri düğmesiyle açılır; dil ikilisi kartta seçilir',
                        'Turn on with the translate button; choose the language pair on the card',
                        'Mit der Übersetzen-Taste; Sprachpaar auf der Karte wählen'),
                    showChevron: false,
                  ),
                ]),
              ],
            ),
          ),
        ));
      },
    );
  }
}

/// Faz 9.3 — Çıkış onayı. `true` dönerse çağıran oturumu kapatır.
Future<bool> showJuzzioLogoutDialog(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final res = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: JuzzioNeonCard(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        radius: 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF5A6A).withValues(alpha: 0.12),
                border: Border.all(color: const Color(0xFFFF5A6A).withValues(alpha: 0.45)),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFFF5A6A), size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              app.trEn('Çıkış yapmak istiyor musun?', 'Sign out?', 'Abmelden?'),
              textAlign: TextAlign.center,
              style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              app.trEn(
                'Bu cihazda oturumun kapanır; mesajların hesabında kalır.',
                'You will be signed out on this device; your messages stay in your account.',
                'Du wirst auf diesem Gerät abgemeldet; deine Nachrichten bleiben im Konto.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 20),
            JuzzioLimeButton(
              label: app.trEn('Çıkış Yap', 'Sign out', 'Abmelden'),
              icon: Icons.logout_rounded,
              style: JuzzioLimeButtonStyle.danger,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 10),
            JuzzioLimeButton(
              label: app.trEn('Vazgeç', 'Cancel', 'Abbrechen'),
              style: JuzzioLimeButtonStyle.outline,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  return res == true;
}


/// Girişte ve açılışta istenen 6 haneli kod. İptal → null.
Future<String?> showJuzzioMfaCodeDialog(BuildContext context) {
  // v2.1: saydam iletişim kutusu yerine OPAK tam sayfa (giriş ekranının üstüne binip okunmaz olmuyordu)
  return Navigator.of(context, rootNavigator: true).push<String>(
    PageRouteBuilder<String>(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const JuzzioMfaCodePage(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

/// v2.1 — İki adımlı doğrulama kodu sayfası (tam ekran, temaya uyumlu, 6 kutulu kod alanı)
class JuzzioMfaCodePage extends StatefulWidget {
  const JuzzioMfaCodePage({super.key});

  @override
  State<JuzzioMfaCodePage> createState() => _JuzzioMfaCodePageState();
}

class _JuzzioMfaCodePageState extends State<JuzzioMfaCodePage> {
  final _app = JuzzioAppController.instance;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      if (_done || !mounted) return;
      if (_error != null) setState(() => _error = null);
      setState(() {});
      if (_ctrl.text.length == 6) _submit();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// GM-060: kod bir kez gönderilir. Yapıştırınca denetleyici birden çok kez bildirim yapıyor,
  /// _submit iki kez çalışıp ikinci pop alttaki giriş sayfasını da kapatıyordu → gri boş ekran.
  bool _done = false;

  void _submit() {
    if (_done || !mounted) return;
    final code = juzzioCleanTotpCode(_ctrl.text);
    if (code == null) {
      setState(() => _error = _app.trEn('6 haneli kodu gir', 'Enter the 6-digit code', '6-stelligen Code eingeben'));
      return;
    }
    _done = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _done) return;
    final digits = (data?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      setState(() => _error = _app.trEn('Panoda 6 haneli kod yok', 'No 6-digit code on the clipboard', 'Kein 6-stelliger Code in der Zwischenablage'));
      return;
    }
    final code = digits.substring(0, 6);
    _ctrl.value = TextEditingValue(text: code, selection: TextSelection.collapsed(offset: code.length));
  }

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioGlassTokens.isDarkResolver();
    final depth = dark ? JuzzioGlassTokens.space.depth : JuzzioGlassTokens.space.depthLight;
    final glow = JuzzioGlassTokens.glow;
    final text = _ctrl.text;
    return Scaffold(
      backgroundColor: depth.last,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: depth),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, box) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        JuzzioHeaderCircleButton(
                          icon: Icons.close_rounded,
                          tooltip: _app.trEn('Vazgeç', 'Cancel', 'Abbrechen'),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(child: Center(child: JuzzioWordmark(size: 20))),
                        const SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 44),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: glow.withValues(alpha: 0.12),
                        border: Border.all(color: glow.withValues(alpha: 0.55), width: 1.4),
                        boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.28), blurRadius: 30)],
                      ),
                      child: Icon(Icons.shield_moon_outlined, color: JuzzioGlassTokens.glowText, size: 46),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      _app.trEn('İki adımlı doğrulama', 'Two-step verification', 'Zwei-Schritt-Verifizierung'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioGlassTokens.heading,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _app.trEn('Hesabın korunuyor. Kimlik doğrulayıcı uygulamandaki 6 haneli kodu gir.',
                          'Your account is protected. Enter the 6-digit code from your authenticator app.',
                          'Dein Konto ist geschützt. Gib den 6-stelligen Code deiner Authenticator-App ein.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 14.5, height: 1.4),
                    ),
                    const SizedBox(height: 34),
                    // 6 kutulu kod alanı (tek gizli metin alanı; yapıştırma ve SMS/otomatik doldurma destekli)
                    GestureDetector(
                      onTap: () => _focus.requestFocus(),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(6, (i) {
                              final filled = i < text.length;
                              final current = i == text.length && _focus.hasFocus;
                              return Container(
                                width: 46,
                                height: 58,
                                margin: EdgeInsets.only(right: i == 5 ? 0 : (i == 2 ? 16 : 8)),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: JuzzioGlassTokens.spaceInset,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _error != null
                                        ? JuzzioColors.redAlert
                                        : (current || filled ? glow : JuzzioGlassTokens.spaceCardBorder),
                                    width: current ? 2 : 1.3,
                                  ),
                                ),
                                child: Text(
                                  filled ? text[i] : '',
                                  style: TextStyle(
                                    fontFamily: JuzzioConfig.fontRegularBold,
                                    color: JuzzioGlassTokens.heading,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              );
                            }),
                          ),
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0,
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focus,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                showCursor: false,
                                enableInteractiveSelection: false,
                                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: JuzzioColors.redAlert, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _paste,
                      icon: Icon(Icons.content_paste_rounded, size: 18, color: JuzzioGlassTokens.glowText),
                      label: Text(
                        _app.trEn('Kodu yapıştır', 'Paste code', 'Code einfügen'),
                        style: TextStyle(color: JuzzioGlassTokens.glowText, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 30),
                    JuzzioLimeButton(
                      label: _app.trEn('Doğrula ve giriş yap', 'Verify and sign in', 'Bestätigen und anmelden'),
                      icon: Icons.verified_user_rounded,
                      onPressed: text.length == 6 ? _submit : null,
                    ),
                    const SizedBox(height: 10),
                    JuzzioLimeButton(
                      label: _app.trEn('Vazgeç', 'Cancel', 'Abbrechen'),
                      style: JuzzioLimeButtonStyle.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: JuzzioGlassTokens.textMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _app.trEn('Kod her 30 saniyede yenilenir.', 'The code refreshes every 30 seconds.',
                                'Der Code erneuert sich alle 30 Sekunden.'),
                            style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faz 7.3 — İki adımlı doğrulama ayarı (tasarım: Gizlilik ve Güvenlik → 2FA)
class JuzzioTwoFactorPage extends StatefulWidget {
  const JuzzioTwoFactorPage({super.key});

  @override
  State<JuzzioTwoFactorPage> createState() => _JuzzioTwoFactorPageState();
}

class _JuzzioTwoFactorPageState extends State<JuzzioTwoFactorPage> {
  final _app = JuzzioAppController.instance;
  final _code = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _enabled = false;
  JuzzioMfaEnrollment? _pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final on = await JuzzioMfaService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = on;
      _loading = false;
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final e = await JuzzioMfaService.instance.enroll();
      if (!mounted) return;
      setState(() => _pending = e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _app.trEn('Kurulum başlatılamadı. İnternetini kontrol edip tekrar dene.',
          'Could not start setup. Check your connection and retry.', 'Einrichtung fehlgeschlagen. Verbindung prüfen.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final p = _pending;
    final code = juzzioCleanTotpCode(_code.text);
    if (p == null) return;
    if (code == null) {
      setState(() => _error = _app.trEn('6 haneli kodu gir', 'Enter the 6-digit code', '6-stelligen Code eingeben'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await JuzzioMfaService.instance.verify(p.factorId, code);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _pending = null;
        _enabled = true;
      });
      _snack(_app.trEn('İki adımlı doğrulama açıldı', 'Two-step verification is on', 'Zwei-Schritt-Verifizierung aktiv'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _app.trEn('Kod hatalı veya süresi doldu', 'Wrong or expired code', 'Falscher oder abgelaufener Code'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final code = await showJuzzioMfaCodeDialog(context);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await JuzzioMfaService.instance.verifyLogin(code);
      await JuzzioMfaService.instance.disable();
      if (!mounted) return;
      setState(() => _enabled = false);
      _snack(_app.trEn('İki adımlı doğrulama kapatıldı', 'Two-step verification is off', 'Zwei-Schritt-Verifizierung aus'));
    } catch (_) {
      if (mounted) _snack(_app.trEn('Kod hatalı; kapatılmadı', 'Wrong code; not turned off', 'Falscher Code; nicht deaktiviert'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final pending = _pending;
    return JuzzioAuroraPage(child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            JuzzioScreenHeader(
              title: app.trEn('İki Adımlı Doğrulama', 'Two-Step Verification', 'Zwei-Schritt-Verifizierung'),
              subtitle: app.trEn('Şifren ele geçse bile hesabın korunur.', 'Your account stays safe even if your password leaks.',
                  'Dein Konto bleibt sicher, selbst wenn dein Passwort bekannt wird.'),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else ...[
              JuzzioNeonGroup(children: [
                JuzzioNeonRow.toggle(
                  icon: Icons.verified_user_outlined,
                  title: app.trEn('İki adımlı doğrulama', 'Two-step verification', 'Zwei-Schritt-Verifizierung'),
                  subtitle: _enabled
                      ? app.trEn('Açık · girişte kimlik doğrulayıcı kodu istenir', 'On · a code is asked at sign-in', 'An · Code bei Anmeldung')
                      : app.trEn('Kapalı', 'Off', 'Aus'),
                  value: _enabled || pending != null,
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v && !_enabled) {
                            _start();
                          } else if (!v && _enabled) {
                            _disable();
                          } else if (!v) {
                            setState(() => _pending = null);
                          }
                        },
                ),
              ]),
              if (pending != null) ...[
                JuzzioNeonSectionLabel(app.trEn('1 · Karekodu okut', '1 · Scan the QR code', '1 · QR-Code scannen')),
                JuzzioNeonCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    if (pending.uri.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                        child: QrImageView(data: pending.uri, size: 190, padding: EdgeInsets.zero, backgroundColor: Colors.white),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      app.trEn('Google Authenticator, Microsoft Authenticator veya benzeri bir uygulamayla okut. Okutamıyorsan anahtarı elle gir:',
                          'Scan with Google Authenticator, Microsoft Authenticator or similar. Or enter the key manually:',
                          'Mit Google/Microsoft Authenticator o. ä. scannen oder Schlüssel manuell eingeben:'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: pending.secret));
                        _snack(app.trEn('Anahtar kopyalandı', 'Key copied', 'Schlüssel kopiert'));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: SelectableText(pending.secret,
                                style: TextStyle(color: JuzzioGlassTokens.glowText, fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded, size: 16, color: JuzzioGlassTokens.glowText),
                        ]),
                      ),
                    ),
                  ]),
                ),
                JuzzioNeonSectionLabel(app.trEn('2 · Kodu doğrula', '2 · Verify the code', '2 · Code bestätigen')),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                ),
                const SizedBox(height: 10),
                JuzzioLimeButton(
                  label: app.trEn('Doğrula ve aç', 'Verify and turn on', 'Bestätigen und aktivieren'),
                  busy: _busy,
                  onPressed: _busy ? null : _confirm,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF5A6A))),
                ),
              const SizedBox(height: 16),
              Text(
                app.trEn(
                  'Telefonunu kaybedersen hesabına giremeyebilirsin. Kimlik doğrulayıcı uygulamanın yedeklemesini aç; erişimi kaybedersen Yardım ve Destek üzerinden kimliğini doğrulayarak sıfırlama iste.',
                  'If you lose your phone you may be locked out. Turn on backup in your authenticator app; if you lose access, request a reset via Help & Support after identity verification.',
                  'Bei Verlust des Telefons kannst du ausgesperrt werden. Aktiviere das Backup deiner Authenticator-App; sonst Zurücksetzen über Hilfe & Support anfragen.',
                ),
                style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    ));
  }
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Faz 7.4 — Zamanlanmış sessiz saatler (Bildirimler sayfasının başında)
class JuzzioQuietHoursCard extends StatelessWidget {
  const JuzzioQuietHoursCard({super.key});

  Future<void> _pick(BuildContext context, bool start) async {
    final app = JuzzioAppController.instance;
    final cur = start ? app.quietStartMin : app.quietEndMin;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    if (start) {
      app.setQuietHours(startMin: m);
    } else {
      app.setQuietHours(endMin: m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: JuzzioNeonGroup(children: [
          JuzzioNeonRow.toggle(
            icon: Icons.bedtime_outlined,
            title: app.trEn('Zamanlanmış sessiz', 'Scheduled quiet hours', 'Ruhezeiten'),
            subtitle: app.quietHoursEnabled
                ? app.trEn('${_hm(app.quietStartMin)} – ${_hm(app.quietEndMin)} arası ses ve titreşim yok (aramalar hariç)',
                    'No sound or vibration ${_hm(app.quietStartMin)} – ${_hm(app.quietEndMin)} (calls excluded)',
                    'Kein Ton ${_hm(app.quietStartMin)} – ${_hm(app.quietEndMin)} (Anrufe ausgenommen)')
                : app.trEn('Kapalı', 'Off', 'Aus'),
            value: app.quietHoursEnabled,
            onChanged: (v) => app.setQuietHours(enabled: v),
          ),
          if (app.quietHoursEnabled) ...[
            JuzzioNeonRow(
              icon: Icons.nightlight_round,
              title: app.trEn('Başlangıç', 'Start', 'Beginn'),
              value: _hm(app.quietStartMin),
              onTap: () => _pick(context, true),
            ),
            JuzzioNeonRow(
              icon: Icons.wb_sunny_outlined,
              title: app.trEn('Bitiş', 'End', 'Ende'),
              value: _hm(app.quietEndMin),
              onTap: () => _pick(context, false),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Faz 7.5 — Çeviri kipi (Çeviri ve Dil sayfasının başında)
class JuzzioTranslationModeCard extends StatelessWidget {
  const JuzzioTranslationModeCard({super.key});

  static const modes = ['realtime', 'fast', 'accurate'];

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final i = modes.indexOf(app.translationQuality).clamp(0, 2);
        final desc = [
          app.trEn('En düşük gecikme; canlı altyazı ve sesli notlar için.', 'Lowest latency; for live captions and voice notes.',
              'Geringste Verzögerung; für Live-Untertitel und Sprachnachrichten.'),
          app.trEn('Hız ve doğruluk dengesi (önerilen).', 'Balance of speed and accuracy (recommended).', 'Ausgewogen (empfohlen).'),
          app.trEn('En doğal çeviri; biraz daha yavaş olabilir.', 'Most natural translation; may be a bit slower.',
              'Natürlichste Übersetzung; evtl. etwas langsamer.'),
        ][i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: JuzzioNeonCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.translate_rounded, color: JuzzioGlassTokens.glowText, size: 20),
                const SizedBox(width: 8),
                Text(app.trEn('Çeviri kipi', 'Translation mode', 'Übersetzungsmodus'),
                    style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 15.5, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              JuzzioNeonChips(
                labels: [
                  app.trEn('Gerçek Zamanlı', 'Real-time', 'Echtzeit'),
                  app.trEn('Hızlı', 'Fast', 'Schnell'),
                  app.trEn('Yüksek Doğruluk', 'High accuracy', 'Hohe Genauigkeit'),
                ],
                selected: i,
                onChanged: (k) => app.setTranslationQuality(modes[k]),
              ),
              const SizedBox(height: 10),
              Text(desc, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5)),
            ]),
          ),
        );
      },
    );
  }
}

/// Faz 8.4 — Görünüm: mesaj balonu köşe yuvarlaklığı (tema kipi GM-014'te tek kontrole indi)
class JuzzioAppearanceQuickCard extends StatelessWidget {
  const JuzzioAppearanceQuickCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final r = app.bubbleRadius;
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: JuzzioNeonCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // GM-014: Sistem/Açık/Koyu/Zamanlı burada ikinci kez vardı; tek kontrol aşağıdaki
              // "Gece / Gündüz" (JuzzioThemeModeSelector). Bu kartta yalnız balon köşeleri kalır.
              Row(children: [
                Expanded(
                  child: Text(app.trEn('Mesaj balonu köşeleri', 'Message bubble corners', 'Ecken der Sprechblasen'),
                      style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Text('${r.round()}', style: TextStyle(color: JuzzioGlassTokens.glowText, fontWeight: FontWeight.w800)),
              ]),
              Slider(
                value: r,
                min: 8,
                max: 28,
                divisions: 10,
                activeColor: JuzzioGlassTokens.glowText,
                onChanged: app.setBubbleRadius,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: JuzzioGlassTokens.glowText,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(r),
                      topRight: Radius.circular(r),
                      bottomLeft: Radius.circular(r),
                      bottomRight: const Radius.circular(6),
                    ),
                  ),
                  child: Text(app.trEn('Önizleme 👋', 'Preview 👋', 'Vorschau 👋'),
                      style: const TextStyle(color: Color(0xFF111113), fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Faz 8.3 — Medya ve Depolama halka grafiği (tür dökümü)
class JuzzioStorageRingCard extends StatefulWidget {
  const JuzzioStorageRingCard({super.key, this.refreshKey = 0});

  /// Değişince yeniden ölçülür (ör. önbellek temizlendikten sonra)
  final int refreshKey;

  @override
  State<JuzzioStorageRingCard> createState() => _JuzzioStorageRingCardState();
}

class _JuzzioStorageRingCardState extends State<JuzzioStorageRingCard> {
  Map<String, int>? _data;

  static const _colors = <String, Color>{
    'photos': Color(0xFFC6F135),
    'videos': Color(0xFF5BC0FF),
    'audio': Color(0xFFFFB547),
    'documents': Color(0xFFB98CFF),
    'other': Color(0xFF7A8194),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JuzzioStorageRingCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    final d = await JuzzioSocialService.instance.measureStorageByCategory();
    if (mounted) setState(() => _data = d);
  }

  static String _fmt(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(b < 10240 ? 1 : 0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final d = _data;
    final labels = <String, String>{
      'photos': app.trEn('Fotoğraflar', 'Photos', 'Fotos'),
      'videos': app.trEn('Videolar', 'Videos', 'Videos'),
      'audio': app.trEn('Ses ve sesli mesajlar', 'Audio & voice messages', 'Audio & Sprachnachrichten'),
      'documents': app.trEn('Belgeler', 'Documents', 'Dokumente'),
      'other': app.trEn('Diğer', 'Other', 'Sonstiges'),
    };
    final total = d == null ? 0 : d.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: JuzzioNeonCard(
        padding: const EdgeInsets.all(18),
        child: d == null
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : Row(children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _StorageRingPainter([for (final k in _colors.keys) (d[k] ?? 0, _colors[k]!)]),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_fmt(total), style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(app.trEn('kullanılan', 'used', 'belegt'), style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final k in _colors.keys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: _colors[k], shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(labels[k]!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 12.5)),
                          ),
                          Text(_fmt(d[k] ?? 0), style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                        ]),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

class _StorageRingPainter extends CustomPainter {
  _StorageRingPainter(this.parts);
  final List<(int, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.12;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final total = parts.fold<int>(0, (a, b) => a + b.$1);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawArc(rect, 0, 6.283185307179586, false, bg);
    if (total <= 0) return;
    var start = -1.5707963267948966;
    for (final (bytes, color) in parts) {
      if (bytes <= 0) continue;
      final sweep = 6.283185307179586 * bytes / total;
      canvas.drawArc(
        rect,
        start,
        (sweep - 0.04).clamp(0.01, 6.3),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StorageRingPainter old) => true;
}

/// Faz 8.5 — Erişilebilirlik: kalın yazı + renk düzeltme
class JuzzioA11yExtrasCard extends StatelessWidget {
  const JuzzioA11yExtrasCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final modes = JuzzioAppController.colorVisionModes;
        final i = modes.indexOf(app.colorVisionMode).clamp(0, modes.length - 1);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            JuzzioNeonGroup(children: [
              JuzzioNeonRow.toggle(
                icon: Icons.format_bold_rounded,
                title: app.trEn('Kalın yazı', 'Bold text', 'Fettschrift'),
                subtitle: app.trEn('Tüm metinler daha kalın görünür', 'All text appears bolder', 'Alle Texte fetter'),
                value: app.boldTextEnabled,
                onChanged: app.setBoldTextEnabled,
              ),
            ]),
            const SizedBox(height: 12),
            JuzzioNeonCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.palette_outlined, color: JuzzioGlassTokens.glowText, size: 20),
                  const SizedBox(width: 8),
                  Text(app.trEn('Renk düzeltme', 'Colour correction', 'Farbkorrektur'),
                      style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 15.5, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var k = 0; k < modes.length; k++)
                    ChoiceChip(
                      label: Text([
                        app.trEn('Kapalı', 'Off', 'Aus'),
                        app.trEn('Kırmızı körlüğü', 'Protanopia', 'Protanopie'),
                        app.trEn('Yeşil körlüğü', 'Deuteranopia', 'Deuteranopie'),
                        app.trEn('Mavi körlüğü', 'Tritanopia', 'Tritanopie'),
                        app.trEn('Gri tonlama', 'Grayscale', 'Graustufen'),
                      ][k]),
                      selected: i == k,
                      selectedColor: JuzzioGlassTokens.glowText,
                      labelStyle: TextStyle(
                          color: i == k ? const Color(0xFF111113) : JuzzioGlassTokens.heading, fontWeight: FontWeight.w700),
                      onSelected: (_) => app.setColorVisionMode(modes[k]),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(
                  app.trEn('Renkler ayırt edilebilsin diye tüm ekrana yaklaşık bir düzeltme uygulanır.',
                      'An approximate correction is applied to the whole screen to make colours easier to tell apart.',
                      'Eine ungefähre Korrektur wird auf den ganzen Bildschirm angewendet.'),
                  style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Faz 9.5 — Onaylarım ve yaş sınırı: verilen onayların geçmişi + geri alınabilir izinler
class JuzzioConsentCenterPage extends StatefulWidget {
  const JuzzioConsentCenterPage({super.key});

  @override
  State<JuzzioConsentCenterPage> createState() => _JuzzioConsentCenterPageState();
}

class _JuzzioConsentCenterPageState extends State<JuzzioConsentCenterPage> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw StateError('no_user');
      final res = await Supabase.instance.client
          .from('user_consents')
          .select('doc_key, document_version, consent_type, action, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(res));
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  String _docName(String key) {
    final app = JuzzioAppController.instance;
    switch (key) {
      case 'terms':
        return app.trEn('Kullanım Koşulları', 'Terms of Use', 'Nutzungsbedingungen');
      case 'privacy':
        return app.trEn('Gizlilik / Aydınlatma Metni', 'Privacy Notice', 'Datenschutzhinweis');
      case 'marketing':
        return app.trEn('Ticari elektronik ileti', 'Marketing messages', 'Werbenachrichten');
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final rows = _rows;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => JuzzioAuroraPage(child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              JuzzioScreenHeader(
                title: app.trEn('Onaylarım ve İzinler', 'Consents & Permissions', 'Einwilligungen & Berechtigungen'),
                subtitle: app.trEn('Verdiğin onayları gör, isteğe bağlı olanları istediğin an geri al.',
                    'See your consents and withdraw optional ones at any time.', 'Sieh deine Einwilligungen und widerrufe optionale jederzeit.'),
              ),
              JuzzioNeonCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.cake_outlined, color: JuzzioGlassTokens.glowText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.trEn('Trawave 15 yaş ve üzeri içindir. Kayıtta yaş beyanı alınır; 15 yaşından küçük olduğu anlaşılan hesaplar kapatılır.',
                          'Trawave is for ages 15 and over. Age is declared at sign-up; accounts found to be under 15 are closed.',
                          'Trawave ist ab 15 Jahren. Konten unter 15 werden geschlossen.'),
                      style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 13.5, height: 1.35),
                    ),
                  ),
                ]),
              ),
              JuzzioNeonSectionLabel(app.trEn('İsteğe bağlı izinler', 'Optional permissions', 'Optionale Berechtigungen')),
              JuzzioNeonGroup(children: [
                JuzzioNeonRow.toggle(
                  icon: Icons.cloud_outlined,
                  title: app.trEn('Hava durumu teması (yaklaşık konum)', 'Weather theme (approximate location)', 'Wetter-Design (ungefährer Standort)'),
                  subtitle: app.trEn('Konum ~10 km yuvarlanır, yalnız Open-Meteo\'ya gider', 'Location rounded to ~10 km, sent only to Open-Meteo',
                      'Standort ~10 km gerundet, nur an Open-Meteo'),
                  value: app.weatherThemeEnabled,
                  onChanged: app.setWeatherThemeEnabled,
                ),
              ]),
              const SizedBox(height: 10),
              const JuzzioDiscoverVisibilityTile(),
              JuzzioNeonSectionLabel(app.trEn('Onay geçmişi', 'Consent history', 'Verlauf')),
              if (rows == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (rows.isEmpty)
                Text(app.trEn('Kayıt bulunamadı.', 'No records found.', 'Keine Einträge.'),
                    style: TextStyle(color: JuzzioGlassTokens.textSecondary))
              else
                JuzzioNeonGroup(children: [
                  for (final r in rows)
                    JuzzioNeonRow(
                      icon: (r['action'] ?? '') == 'accept' ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                      title: '${_docName((r['doc_key'] ?? '').toString())} · v${r['document_version'] ?? ''}',
                      subtitle: '${(r['action'] ?? '') == 'accept' ? app.trEn('Onaylandı', 'Accepted', 'Akzeptiert') : app.trEn('Geri alındı', 'Withdrawn', 'Widerrufen')}'
                          ' · ${(r['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}',
                      showChevron: false,
                    ),
                ]),
            ],
          ),
        ),
      )),
    );
  }
}


/// Faz 9.1 — Sık Sorulan Sorular (Yardım ve Destek)
class JuzzioFaqCard extends StatelessWidget {
  const JuzzioFaqCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final items = <(String, String)>[
      (
        app.trEn('Mesajlarımı Trawave okuyabilir mi?', 'Can Trawave read my messages?', 'Kann Trawave meine Nachrichten lesen?'),
        app.trEn('Hayır. Mesajlar uçtan uca şifrelidir; anahtarlar yalnız cihazlarındadır. Çeviriyi açtığında metin yalnız çeviri için çeviri hizmetine gönderilir.',
            'No. Messages are end-to-end encrypted; keys stay on your devices. When you use translation, text is sent to the translation service only to translate it.',
            'Nein. Nachrichten sind Ende-zu-Ende-verschlüsselt. Bei Übersetzung wird Text nur dafür an den Übersetzungsdienst gesendet.'),
      ),
      (
        app.trEn('Canlı çeviri nasıl açılır?', 'How do I turn on live translation?', 'Wie aktiviere ich die Live-Übersetzung?'),
        app.trEn('Aramada çeviri düğmesine dokun, dil ikilisini seç. Kipi Ayarlar → Çeviri ve Dil\'den değiştirebilirsin.',
            'Tap the translate button in a call and pick the language pair. Change the mode in Settings → Translation & Language.',
            'Tippe im Anruf auf Übersetzen und wähle das Sprachpaar. Modus unter Einstellungen → Übersetzung & Sprache.'),
      ),
      (
        app.trEn('Ekranımı nasıl paylaşırım?', 'How do I share my screen?', 'Wie teile ich meinen Bildschirm?'),
        app.trEn('Görüntülü aramada üst çubuktaki ekran paylaşımı düğmesine dokun; Android her seferinde izin ister.',
            'In a video call tap the screen-share button in the top bar; Android asks for permission each time.',
            'Im Videoanruf oben auf Bildschirm teilen tippen; Android fragt jedes Mal nach.'),
      ),
      (
        app.trEn('Keşfet\'te görünmek istemiyorum.', 'I don\'t want to appear in Explore.', 'Ich möchte nicht in Entdecken erscheinen.'),
        app.trEn('Profil Düzenle → "Keşfet\'te görün" anahtarını kapat. Gizli hesaplar Keşfet\'te hiç görünmez.',
            'Edit Profile → turn off "Show me in Explore". Private accounts never appear in Explore.',
            'Profil bearbeiten → „In Entdecken zeigen“ aus. Private Konten erscheinen nie.'),
      ),
      (
        app.trEn('İki adımlı doğrulamayı nasıl açarım?', 'How do I turn on two-step verification?', 'Wie aktiviere ich 2FA?'),
        app.trEn('Ayarlar → Gizlilik ve Güvenlik → İki adımlı doğrulama. Karekodu kimlik doğrulayıcı uygulamayla okut, kodu gir.',
            'Settings → Privacy & Security → Two-step verification. Scan the QR code with an authenticator app and enter the code.',
            'Einstellungen → Datenschutz & Sicherheit → Zwei-Schritt-Verifizierung.'),
      ),
      (
        app.trEn('Verilerimi nasıl indiririm veya hesabımı silerim?', 'How do I download my data or delete my account?', 'Daten herunterladen oder Konto löschen?'),
        app.trEn('Ayarlar → Hesap ve Profil → Verilerimi indir / Hesabı sil.', 'Settings → Account & Profile → Download my data / Delete account.',
            'Einstellungen → Konto & Profil → Meine Daten / Konto löschen.'),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: JuzzioNeonCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Icon(Icons.quiz_outlined, color: JuzzioGlassTokens.glowText, size: 20),
                const SizedBox(width: 8),
                Text(app.trEn('Sık Sorulan Sorular', 'FAQ', 'Häufige Fragen'),
                    style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 15.5, fontWeight: FontWeight.w800)),
              ]),
            ),
            for (final (q, a) in items)
              ExpansionTile(
                iconColor: JuzzioGlassTokens.glowText,
                collapsedIconColor: JuzzioGlassTokens.textSecondary,
                title: Text(q, style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 14, fontWeight: FontWeight.w700)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(a, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
          ]),
        ),
      ),
    );
  }
}

/// Faz 8.2 — Sohbet Ayarları hızlı kartı
class JuzzioChatQuickCard extends StatelessWidget {
  const JuzzioChatQuickCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: JuzzioNeonGroup(children: [
          JuzzioNeonRow.toggle(
            icon: Icons.link_rounded,
            title: app.trEn('Bağlantı önizlemeleri', 'Link previews', 'Link-Vorschau'),
            subtitle: app.trEn('Kapalıyken bağlantılar için önizleme sayfası çekilmez', 'When off, no preview is fetched for links',
                'Aus: keine Vorschau für Links'),
            value: !app.disableLinkPreviews,
            onChanged: (v) => app.setDisableLinkPreviews(!v),
          ),
          JuzzioNeonRow.toggle(
            icon: Icons.data_saver_on_outlined,
            title: app.trEn('Mobil veride tasarruf', 'Save mobile data', 'Mobile Daten sparen'),
            subtitle: app.trEn('Görüntülü aramada 480p · 60 fps ve daha az arka plan verisi', '480p · 60 fps in video calls and less background data',
                '480p · 60 fps im Videoanruf, weniger Hintergrunddaten'),
            value: app.dataSaverEnabled,
            onChanged: app.setDataSaverEnabled,
          ),
          JuzzioNeonRow(
            icon: Icons.rounded_corner_rounded,
            title: app.trEn('Balon köşeleri ve tema', 'Bubble corners & theme', 'Blasenecken & Design'),
            value: '${app.bubbleRadius.round()}',
            showChevron: false,
          ),
        ]),
      ),
    );
  }
}

/// Faz 8.2 — Medya otomatik indirme seçimi
class JuzzioAutoDownloadCard extends StatelessWidget {
  const JuzzioAutoDownloadCard({super.key});
  static const modes = ['always', 'wifi', 'never'];

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: JuzzioNeonCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.download_for_offline_outlined, color: JuzzioGlassTokens.glowText, size: 20),
              const SizedBox(width: 8),
              Text(app.trEn('Medyayı otomatik indir', 'Auto-download media', 'Medien automatisch laden'),
                  style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 15.5, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            JuzzioNeonChips(
              labels: [
                app.trEn('Her zaman', 'Always', 'Immer'),
                app.trEn('Yalnız Wi-Fi', 'Wi-Fi only', 'Nur WLAN'),
                app.trEn('Hiçbir zaman', 'Never', 'Nie'),
              ],
              selected: modes.indexOf(app.autoDownloadMode).clamp(0, 2),
              onChanged: (k) => app.setAutoDownloadMode(modes[k]),
            ),
            const SizedBox(height: 8),
            Text(
              app.trEn('Kapalıyken sohbetteki fotoğraflar dokununca indirilir. Kendi gönderdiklerin her zaman görünür.',
                  'When off, photos in chats download when you tap them. Your own media is always shown.',
                  'Aus: Fotos werden beim Tippen geladen. Eigene Medien immer sichtbar.'),
              style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5),
            ),
          ]),
        ),
      ),
    );
  }
}

/// v2.1 (Faz 14.1) — Mavi tik başvurusu (kullanıcı tarafı)
class JuzzioVerificationRequestPage extends StatefulWidget {
  const JuzzioVerificationRequestPage({super.key});

  @override
  State<JuzzioVerificationRequestPage> createState() => _JuzzioVerificationRequestPageState();
}

class _JuzzioVerificationRequestPageState extends State<JuzzioVerificationRequestPage> {
  static const _cats = ['creator', 'public_figure', 'business', 'journalist', 'other'];
  final _reason = TextEditingController();
  final _links = TextEditingController();
  int _cat = 0;
  bool _busy = false;
  Map<String, dynamic>? _status;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('verification_my_status');
      if (mounted) setState(() => _status = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{});
    } catch (_) {
      if (mounted) setState(() => _status = <String, dynamic>{});
    }
  }

  Future<void> _submit() async {
    final app = JuzzioAppController.instance;
    if (_reason.text.trim().length < 10) {
      setState(() => _msg = app.trEn('Neden doğrulanman gerektiğini en az 10 karakterle yaz.', 'Explain why in at least 10 characters.',
          'Bitte mindestens 10 Zeichen.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await Supabase.instance.client.rpc('verification_submit',
          params: {'p_category': _cats[_cat], 'p_reason': _reason.text.trim(), 'p_links': _links.text.trim()});
      await _load();
      if (mounted) setState(() => _msg = app.trEn('Başvurun alındı. Sonuç bildirim olarak gelecek.', 'Request received.', 'Antrag erhalten.'));
    } catch (e) {
      final m = e.toString();
      if (mounted) {
        setState(() => _msg = m.contains('already_pending')
            ? app.trEn('Zaten bekleyen bir başvurun var.', 'You already have a pending request.', 'Bereits ein offener Antrag.')
            : m.contains('already_verified')
                ? app.trEn('Hesabın zaten doğrulanmış.', 'Your account is already verified.', 'Bereits verifiziert.')
                : m.contains('rate_limited')
                    ? app.trEn('Bugün çok deneme yaptın, yarın tekrar dene.', 'Too many attempts today.', 'Zu viele Versuche.')
                    : app.trEn('Başvuru gönderilemedi.', 'Could not send the request.', 'Antrag fehlgeschlagen.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final st = _status;
    final verified = st?['verified'] == true;
    final req = st?['request'] is Map ? Map<String, dynamic>.from(st!['request'] as Map) : null;
    final pending = req?['status'] == 'pending';
    return JuzzioAuroraPage(child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            JuzzioScreenHeader(
              title: app.trEn('Mavi tik başvurusu', 'Verification request', 'Verifizierung beantragen'),
              subtitle: app.trEn('Tanınmış, özgün ve aktif hesaplar doğrulanır.', 'Notable, authentic and active accounts can be verified.',
                  'Bekannte, echte und aktive Konten.'),
            ),
            if (st == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (verified || pending || req?['status'] == 'rejected')
              JuzzioNeonCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(verified ? Icons.verified_rounded : (pending ? Icons.hourglass_top_rounded : Icons.info_outline_rounded),
                      color: JuzzioGlassTokens.glowText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      verified
                          ? app.trEn('Hesabın doğrulandı.', 'Your account is verified.', 'Dein Konto ist verifiziert.')
                          : pending
                              ? app.trEn('Başvurun inceleniyor.', 'Your request is under review.', 'Dein Antrag wird geprüft.')
                              : app.trEn('Son başvurun reddedildi; yeniden başvurabilirsin.', 'Your last request was rejected; you can apply again.',
                                  'Letzter Antrag abgelehnt; erneut möglich.'),
                      style: TextStyle(color: JuzzioGlassTokens.heading, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            if (st != null && !verified && !pending) ...[
              const SizedBox(height: 12),
              JuzzioNeonSectionLabel(app.trEn('Kategori', 'Category', 'Kategorie')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var k = 0; k < _cats.length; k++)
                  ChoiceChip(
                    label: Text([
                      app.trEn('İçerik üreticisi', 'Creator', 'Creator'),
                      app.trEn('Tanınmış kişi', 'Public figure', 'Person des öffentlichen Lebens'),
                      app.trEn('İşletme / marka', 'Business / brand', 'Unternehmen'),
                      app.trEn('Gazeteci', 'Journalist', 'Journalist'),
                      app.trEn('Diğer', 'Other', 'Sonstiges'),
                    ][k]),
                    selected: _cat == k,
                    selectedColor: JuzzioGlassTokens.glowText,
                    labelStyle: TextStyle(color: _cat == k ? const Color(0xFF111113) : JuzzioGlassTokens.heading, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() => _cat = k),
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _reason,
                maxLines: 4,
                maxLength: 600,
                style: TextStyle(color: JuzzioGlassTokens.heading),
                decoration: InputDecoration(
                    labelText: app.trEn('Neden doğrulanmalısın?', 'Why should you be verified?', 'Warum verifizieren?')),
              ),
              TextField(
                controller: _links,
                maxLength: 600,
                style: TextStyle(color: JuzzioGlassTokens.heading),
                decoration: InputDecoration(
                    labelText: app.trEn('Bağlantılar (web sitesi, haber, sosyal hesap)', 'Links (website, press, social)', 'Links')),
              ),
              const SizedBox(height: 8),
              JuzzioLimeButton(
                label: app.trEn('Başvur', 'Apply', 'Beantragen'),
                icon: Icons.verified_outlined,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_msg!, style: TextStyle(color: JuzzioGlassTokens.textSecondary)),
              ),
          ],
        ),
      ),
    ));
  }
}
