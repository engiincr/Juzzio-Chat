// =============================================================================
// JUZZIO v0.9.0 — Business'a geçiş (Business eki §2–§4; son talimat §2.2)
//  1 Tanıtım → 2 Hesap türü + ad → 3 Sözleşme/KVKK/izinler (her biri AYRI, önceden işaretli YOK,
//  zorunlu ≠ isteğe bağlı) → 4 Hazırlık: 7 ekran, her biri GERÇEK sunucu adımına bağlı → Karşılama.
//  Uygulama kapanırsa durum sunucudan okunur ve kaldığı adımdan devam edilir. Sahte yüzde yok:
//  ilerleme = tamamlanan sunucu adımı / 5. Hareket azaltma açıksa animasyonlar kapanır.
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../services/juzzio_business_service.dart';
import '../../services/supabase_service.dart';

class JuzzioBusinessOnboardingPage extends StatefulWidget {
  const JuzzioBusinessOnboardingPage({super.key, this.onEnterBusiness});

  /// "Business Dünyasına Gir" — kabuk Business görünümüne geçer.
  final VoidCallback? onEnterBusiness;

  static Future<void> open(BuildContext context, {VoidCallback? onEnterBusiness}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => JuzzioBusinessOnboardingPage(onEnterBusiness: onEnterBusiness)),
      );

  @override
  State<JuzzioBusinessOnboardingPage> createState() => _JuzzioBusinessOnboardingPageState();
}

enum _Stage { loading, intro, application, legal, preparing, welcome, blocked, error }

class _JuzzioBusinessOnboardingPageState extends State<JuzzioBusinessOnboardingPage> {
  final _svc = JuzzioBusinessService.instance;
  final _app = JuzzioAppController.instance;
  _Stage _stage = _Stage.loading;
  Object? _error;
  String _type = 'individual_professional';
  final _name = TextEditingController();
  List<JuzzioLegalDoc> _docs = const [];
  bool _busy = false;
  String? _stepError;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _t(String tr, String en, String de) => _app.trEn(tr, en, de);

  /// Sunucudaki duruma göre doğru aşamadan devam eder.
  Future<void> _resume() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      final st = await _svc.refresh();
      if (st.isActive) {
        _stage = _Stage.welcome;
      } else if (st.isPreparing) {
        _stage = _Stage.preparing;
        _runSetup();
      } else if (st.inApplication) {
        _docs = await _svc.legalDocuments(_app.uiLang);
        _stage = _Stage.legal;
      } else if (st.status == 'business_suspended') {
        _stage = _Stage.blocked;
      } else {
        _name.text = st.displayName;
        _stage = _Stage.intro;
      }
    } catch (e) {
      _error = e;
      _stage = _Stage.error;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startApplication() async {
    if (_name.text.trim().length < 2) {
      setState(() => _stepError = _t('Görünen ad en az 2 karakter olmalı.', 'Display name must be at least 2 characters.', 'Mindestens 2 Zeichen.'));
      return;
    }
    setState(() {
      _busy = true;
      _stepError = null;
    });
    try {
      await _svc.startApplication(profileType: _type, displayName: _name.text);
      _docs = await _svc.legalDocuments(_app.uiLang);
      _stage = _Stage.legal;
    } catch (e) {
      _stepError = SupabaseService.instance.friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleConsent(JuzzioLegalDoc d, bool accept) async {
    setState(() => _busy = true);
    try {
      await _svc.recordConsent(d.key, accept, locale: _app.uiLang, clientInfo: 'juzzio ${JuzzioConfig.appVersion}');
      _docs = await _svc.legalDocuments(_app.uiLang);
    } catch (e) {
      _stepError = SupabaseService.instance.friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submitConsents() async {
    setState(() {
      _busy = true;
      _stepError = null;
    });
    try {
      await _svc.submitConsents();
      _stage = _Stage.preparing;
      _runSetup();
    } catch (e) {
      _stepError = SupabaseService.instance.friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Gerçek hazırlık: her adım sunucuda yürütülür; hata olursa "Tekrar dene" — sonsuz yükleme yok.
  Future<void> _runSetup() async {
    setState(() => _stepError = null);
    try {
      while (mounted) {
        final next = _svc.state.nextStep;
        if (next == null || _svc.state.isActive) break;
        await _svc.runStep(next).timeout(const Duration(seconds: 20));
        if (mounted) setState(() {});
        // Hızlı tamamlanırsa kısa bir an göster (gerçek adım bitti; yapay bekleme değil, ekran okunabilsin)
        if (!_app.reduceMotion) await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (mounted && _svc.state.isActive) setState(() => _stage = _Stage.welcome);
    } catch (e) {
      if (mounted) setState(() => _stepError = SupabaseService.instance.friendlyError(e));
    }
  }

  // --- Aşamalar --------------------------------------------------------------
  Widget _intro(JuzzioPalette p) {
    final items = [
      (Icons.inbox_rounded, _t('Müşteri gelen kutusu, atama ve hazır yanıtlar', 'Customer inbox, assignment and saved replies', 'Kunden-Posteingang, Zuweisung, Vorlagen')),
      (Icons.people_alt_rounded, _t('Müşteri kayıtları, notlar ve takip hatırlatmaları', 'Customer records, notes and follow-ups', 'Kundendaten, Notizen, Nachverfolgung')),
      (Icons.event_available_rounded, _t('Randevu ve hizmet yönetimi', 'Appointments and services', 'Termine und Leistungen')),
      (Icons.groups_rounded, _t('Ekip, roller ve yetkiler', 'Team, roles and permissions', 'Team, Rollen, Rechte')),
      (Icons.insights_rounded, _t('Gerçek verilerle analiz', 'Analytics from real data', 'Analysen aus echten Daten')),
      (Icons.smart_toy_outlined, _t('Otomatik karşılama ve mesai dışı yanıtlar', 'Automatic welcome and away replies', 'Automatische Antworten')),
      (Icons.lock_outline_rounded, _t('Kişisel sohbetlerin ve uçtan uca şifrelemen DEĞİŞMEZ', 'Your personal chats and end-to-end encryption stay unchanged', 'Private Chats und E2EE bleiben unverändert')),
    ];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(_t('Juzzio Business', 'Juzzio Business', 'Juzzio Business'),
          style: TextStyle(color: p.textPrimary, fontSize: 26, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(_t('Aynı hesap, aynı uygulama. Business ücretsizdir; istediğin an Personal görünüme dönebilirsin.',
          'Same account, same app. Business is free; switch back to Personal any time.', 'Gleiches Konto, gleiche App. Kostenlos; jederzeit zurück zu Personal.'),
          style: TextStyle(color: p.textSecondary)),
      const SizedBox(height: 16),
      JuzzioGlass(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [for (final i in items) ListTile(leading: Icon(i.$1, color: p.amberGlow), title: Text(i.$2, style: TextStyle(color: p.textPrimary)))]),
      ),
      const SizedBox(height: 16),
      _applicationForm(p),
    ]);
  }

  Widget _applicationForm(JuzzioPalette p) {
    final types = <(String, String)>[
      ('individual_professional', _t('Bireysel profesyonel', 'Individual professional', 'Einzelperson (beruflich)')),
      ('creator', _t('İçerik üreticisi', 'Creator', 'Creator')),
      ('business', _t('İşletme', 'Business', 'Unternehmen')),
      ('organization', _t('Kurum / kuruluş', 'Organization', 'Organisation')),
      ('community_operator', _t('Topluluk yöneticisi', 'Community operator', 'Community-Betreiber')),
      ('service_provider', _t('Hizmet sağlayıcı', 'Service provider', 'Dienstleister')),
    ];
    return JuzzioGlass(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_t('Hesap türü', 'Account type', 'Kontotyp'), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in types) ChoiceChip(label: Text(t.$2), selected: _type == t.$1, onSelected: (_) => setState(() => _type = t.$1)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          maxLength: 80,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(labelText: _t('Görünen işletme / profesyonel ad', 'Display business / professional name', 'Anzeigename'), errorText: _stepError),
        ),
        Text(_t('Gereksiz belge veya kimlik istenmez. Şirket doğrulaması yalnız ilgili özellik gerektirirse ayrıca istenir.',
            'No unnecessary documents are requested. Company verification is requested only if a feature requires it.',
            'Keine unnötigen Dokumente. Unternehmensprüfung nur falls erforderlich.'),
            style: TextStyle(color: p.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _startApplication,
          child: Text(_t('Devam: Koşullar ve izinler', 'Continue: terms and consents', 'Weiter: Bedingungen')),
        ),
      ]),
    );
  }

  Widget _legal(JuzzioPalette p) {
    final required = _docs.where((d) => d.required).toList();
    final optional = _docs.where((d) => !d.required).toList();
    final allRequired = required.every((d) => d.accepted);
    Widget tile(JuzzioLegalDoc d) => CheckboxListTile(
          value: d.accepted, // önceden işaretli değil: değer sunucudaki gerçek onay kaydından gelir
          onChanged: _busy ? null : (v) => _toggleConsent(d, v == true),
          title: Text(d.title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
          subtitle: Row(children: [
            if (d.isDraft)
              Container(
                margin: const EdgeInsetsDirectional.only(end: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: p.dangerRed.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text('DRAFT - LEGAL REVIEW REQUIRED', style: TextStyle(color: p.dangerRed, fontSize: 9.5, fontWeight: FontWeight.w800)),
              ),
            Flexible(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('${d.title} (v${d.version})'),
                    content: SingleChildScrollView(child: SelectableText(d.body)),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Kapat', 'Close', 'Schließen')))],
                  ),
                ),
                child: Text(_t('Metni oku', 'Read', 'Lesen')),
              ),
            ),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(_t('Koşullar ve izinler', 'Terms and consents', 'Bedingungen und Einwilligungen'),
          style: TextStyle(color: p.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(_t('Her onay ayrıdır ve kaydedilir (belge, sürüm, zaman). Zorunlu olanlar hizmet için gereklidir; isteğe bağlı izinler hizmeti kullanmanın şartı değildir ve Ayarlar\'dan geri alınabilir.',
          'Each consent is separate and recorded (document, version, time). Required items are needed for the service; optional ones are not a condition of use and can be withdrawn in Settings.',
          'Jede Einwilligung ist separat und wird protokolliert.'),
          style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
      const SizedBox(height: 10),
      JuzzioGlass(radius: 20, child: Column(children: [
        ListTile(title: Text(_t('Zorunlu', 'Required', 'Erforderlich'), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900))),
        for (final d in required) tile(d),
      ])),
      const SizedBox(height: 10),
      JuzzioGlass(radius: 20, child: Column(children: [
        ListTile(title: Text(_t('İsteğe bağlı', 'Optional', 'Optional'), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900))),
        for (final d in optional) tile(d),
      ])),
      if (_stepError != null) Padding(padding: const EdgeInsets.all(8), child: Text(_stepError!, style: TextStyle(color: p.dangerRed))),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: (_busy || !allRequired) ? null : _submitConsents,
        child: Text(allRequired
            ? _t('Business hesabını hazırla', 'Prepare Business account', 'Business-Konto vorbereiten')
            : _t('Zorunlu onaylar eksik', 'Required consents missing', 'Erforderliche Einwilligungen fehlen')),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () async {
                await _svc.ownerAction('cancel_application');
                if (mounted) Navigator.of(context).pop();
              },
        child: Text(_t('Başvurudan vazgeç', 'Cancel application', 'Antrag abbrechen')),
      ),
    ]);
  }

  /// 7 ekran: başlangıç + 5 gerçek adım + son kontrol. Her ekranın görseli farklıdır.
  Widget _preparing(JuzzioPalette p) {
    final st = _svc.state;
    final screens = <(IconData, String, String)>[
      (Icons.rocket_launch_rounded, _t('Juzzio Business yolculuğun başlıyor.', 'Your Juzzio Business journey begins.', 'Deine Business-Reise beginnt.'),
          _t('Profesyonel deneyimini hazırlıyoruz. Birkaç küçük ayarlamadan sonra Juzzio Business dünyasına hoş geldin diyeceğiz.',
              'We are preparing your professional experience.', 'Wir bereiten dein Erlebnis vor.')),
      (Icons.badge_rounded, _t('Profesyonel profilin hazırlanıyor.', 'Preparing your professional profile.', 'Profil wird vorbereitet.'),
          _t('Profil bilgilerini ve profesyonel çalışma alanını düzenliyoruz.', 'Arranging your profile and workspace.', 'Profil und Arbeitsbereich.')),
      (Icons.dashboard_customize_rounded, _t('Yeni çalışma alanın hazırlanıyor.', 'Preparing your new workspace.', 'Arbeitsbereich wird vorbereitet.'),
          _t('İhtiyacın olan profesyonel araçları senin için düzenliyoruz.', 'Arranging the tools you need.', 'Werkzeuge werden eingerichtet.')),
      (Icons.verified_user_rounded, _t('Güvenliğin bizim için önemli.', 'Your security matters.', 'Sicherheit ist wichtig.'),
          _t('Hesap ve çalışma alanı güvenlik ayarlarını kontrol ediyoruz.', 'Checking account and workspace security.', 'Sicherheit wird geprüft.')),
      (Icons.handyman_rounded, _t('Profesyonel araçların hazırlanıyor.', 'Preparing your professional tools.', 'Werkzeuge werden vorbereitet.'),
          _t('İşletme, içerik, iletişim ve AI araçlarını kullanımına göre düzenliyoruz.', 'Configuring business and communication tools.', 'Werkzeuge werden konfiguriert.')),
      (Icons.fact_check_rounded, _t('Son kontrolleri yapıyoruz.', 'Running final checks.', 'Letzte Prüfungen.'),
          _t('Her şeyin doğru çalıştığından emin oluyoruz.', 'Making sure everything works.', 'Alles wird geprüft.')),
    ];
    final done = st.steps.length;
    final idx = done.clamp(0, screens.length - 1);
    final s = screens[idx];
    final reduce = _app.reduceMotion;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: Duration(milliseconds: reduce ? 0 : 450),
            child: Icon(s.$1, key: ValueKey(idx), size: 84, color: p.amberGlow),
          ),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            child: Text(s.$2, textAlign: TextAlign.center, style: TextStyle(color: p.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          Text(s.$3, textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 20),
          // Gerçek ilerleme: tamamlanan sunucu adımı / toplam
          LinearProgressIndicator(value: st.setupProgress, minHeight: 6, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 6),
          Text('${st.steps.length}/${kJuzzioBusinessSetupSteps.length}', style: TextStyle(color: p.textMuted, fontSize: 12)),
          if (_stepError != null) ...[
            const SizedBox(height: 12),
            Text(_stepError!, textAlign: TextAlign.center, style: TextStyle(color: p.dangerRed)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _runSetup, child: Text(_t('Tekrar dene', 'Retry', 'Erneut versuchen'))),
          ],
        ]),
      ),
    );
  }

  Widget _welcome(JuzzioPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.celebration_rounded, size: 90, color: p.amberGlow),
            const SizedBox(height: 16),
            Text(_t('Juzzio Business\'a hoş geldin!', 'Welcome to Juzzio Business!', 'Willkommen bei Juzzio Business!'),
                textAlign: TextAlign.center, style: TextStyle(color: p.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_t('Artık Juzzio\'yu profesyonel ihtiyaçlarına göre kullanabilirsin.', 'You can now use Juzzio for your professional needs.',
                'Du kannst Juzzio jetzt beruflich nutzen.'), textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(_t('Business Dünyasına Gir', 'Enter Business', 'Business betreten')),
              onPressed: () async {
                try {
                  await _svc.setView('business');
                } catch (_) {}
                if (!mounted) return;
                Navigator.of(context).pop();
                widget.onEnterBusiness?.call();
              },
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    Widget body;
    switch (_stage) {
      case _Stage.loading:
        body = const Center(child: CircularProgressIndicator());
      case _Stage.intro:
      case _Stage.application:
        body = _intro(p);
      case _Stage.legal:
        body = _legal(p);
      case _Stage.preparing:
        body = _preparing(p);
      case _Stage.welcome:
        body = _welcome(p);
      case _Stage.blocked:
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _t('Business hesabın askıya alındı. Gerekçe: ${_svc.state.reason}. İtiraz için Destek\'e yazabilirsin.',
                  'Your Business account is suspended. Reason: ${_svc.state.reason}.', 'Dein Business-Konto ist gesperrt.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary),
            ),
          ),
        );
      case _Stage.error:
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(SupabaseService.instance.friendlyError(_error ?? 'error'), style: TextStyle(color: p.textSecondary)),
            FilledButton(onPressed: _resume, child: Text(_t('Tekrar dene', 'Retry', 'Erneut versuchen'))),
          ]),
        );
    }
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_t('Business\'a Geç', 'Switch to Business', 'Zu Business wechseln')),
      ),
      body: SafeArea(child: body),
    );
  }
}
