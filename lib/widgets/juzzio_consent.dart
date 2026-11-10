// =============================================================================
// JUZZIO v1.2.3 — Kayıt / giriş onayları (KVKK, 6563 s. Kanun) — İKİ seçenek
//
//  Hukuki dayanak ve tasarım kararları:
//   • KVKK Kurulu 18.02.2026 tarih ve 2026/347 sayılı İlke Kararı (RG 24.03.2026, 33203):
//     aydınlatma metni ile açık rıza metni AYRI düzenlenir; aydınlatma metninde onay/rıza
//     alınmaz, yalnız "okudum ve anladım" beyanı alınabilir; gerekmeyen yerde açık rıza istenmez.
//   • KVKK m.9 (7499 s. Kanun ile değişik, 01.06.2024): sürekli yurt dışı aktarım açık rızaya
//     DEĞİL uygun güvencelere (Kurul'un standart sözleşmesi, 5 iş günü içinde Kurul'a bildirim)
//     dayanır; açık rıza yalnız arızi aktarım içindir. Bu yüzden ayrı "yurt dışı aktarım açık
//     rızası" kutusu kaldırıldı; aktarım aydınlatma metninde açıklanır.
//   • 6563 s. Kanun ve Ticari İletişim Yönetmeliği: ticari ileti onayı ayrı, isteğe bağlı,
//     önceden işaretlenmemiş olmalı ve hizmet şartına bağlanamaz.
//
//  Ekranda yalnız iki kutu:
//   1) ZORUNLU — "Kullanım Koşulları'nı kabul ediyorum, 15 yaşından büyüğüm; Aydınlatma
//      Metni'ni okudum ve anladım." Dokununca metinler açılır; en alta inilince
//      "Okudum ve anladım" etkinleşir, basınca kutu işaretlenir.
//   2) İSTEĞE BAĞLI — Kampanya/duyuru e-postaları (ticari ileti onayı + bu amaçla açık rıza);
//      dokununca ayrı metni açılır, "Onay veriyorum" ile işaretlenir.
//  Onay, giriş/kayıt başarılı olunca `record_juzzio_consent` ile yazılır (sürüm + zaman +
//  uygulama sürümü; IP yok). Oturum yoksa yerelde bekletilir ve ilk girişte yazılır.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/legal_texts.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

/// Metin sürümü (metin değişince artar → kullanıcılar bir sonraki girişte yeniden onaylar)
const String kJuzzioConsentVersion = '2026-11-10.2';

/// Onay durumu (saf; test edilir)
class JuzzioConsentState {
  const JuzzioConsentState({this.termsNotice = false, this.marketing = false});

  /// Zorunlu tek kutu: Kullanım Koşulları kabulü + 15 yaş beyanı + aydınlatma "okudum ve anladım" beyanı
  final bool termsNotice;

  /// İsteğe bağlı: ticari elektronik ileti onayı
  final bool marketing;

  bool get requiredAccepted => termsNotice;

  JuzzioConsentState copyWith({bool? termsNotice, bool? marketing}) =>
      JuzzioConsentState(termsNotice: termsNotice ?? this.termsNotice, marketing: marketing ?? this.marketing);

  /// Sunucu parametreleri. Yurt dışı aktarım artık rıza DEĞİL (KVKK m.9 uygun güvence) → false gönderilir.
  Map<String, dynamic> toRpc() => <String, dynamic>{
        'p_version': kJuzzioConsentVersion,
        'p_privacy': termsNotice,
        'p_terms': termsNotice,
        'p_age': termsNotice,
        'p_cross_border': false,
        'p_marketing': marketing,
        'p_app_version': JuzzioConfig.appVersion,
      };
}

/// Sunucuya kayıt (oturum yoksa ilk girişe kadar bekletilir)
class JuzzioConsentService {
  JuzzioConsentService._();
  static final JuzzioConsentService instance = JuzzioConsentService._();

  JuzzioConsentState? _pending;

  Future<bool> record(JuzzioConsentState s) async {
    if (!s.requiredAccepted) return false;
    final client = SupabaseService.instance.client;
    if (client.auth.currentSession == null) {
      _pending = s;
      return false;
    }
    try {
      await client.rpc('record_juzzio_consent', params: s.toRpc());
      _pending = null;
      return true;
    } catch (_) {
      _pending = s;
      return false;
    }
  }

  /// Bekleyen onayı (ör. e-posta doğrulamasından sonraki ilk giriş) yazmayı dener
  Future<void> flushPending() async {
    final p = _pending;
    if (p != null) await record(p);
  }

  Future<void> setMarketing(bool on) async {
    await SupabaseService.instance.client.rpc('set_marketing_consent', params: {'p_on': on});
  }
}

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

/// Onay metinleri (TR/EN; diğer dillerde uygulamanın çeviri katmanı devreye girer)
class JuzzioConsentTexts {
  static bool get _tr => JuzzioAppController.instance.uiLang.startsWith('tr');

  static String get aydinlatma => _l(
        '''KİŞİSEL VERİLERİN KORUNMASI KANUNU KAPSAMINDA AYDINLATMA METNİ

Bu metin 6698 sayılı Kanun'un (KVKK) 10. maddesi ve Aydınlatma Yükümlülüğünün Yerine Getirilmesinde Uyulacak Usul ve Esaslar Hakkında Tebliğ uyarınca bilgilendirme amacıyla hazırlanmıştır. Bu metin bir onay metni değildir.

1. Veri sorumlusu
Engin ÇIRPAN (Juzzio, bağımsız geliştirici) · engiincr@pm.me

2. İşlenen kişisel veriler
Kimlik ve iletişim: e-posta, kullanıcı adı, görünen ad, profil fotoğrafı.
Hizmet verileri: mesajlar, medya, hikâye ve gönderiler, arama kayıtları (kim, ne zaman, ne kadar).
Cihaz ve güvenlik: bildirim belirteci, cihaz kimliği, oturum ve güvenlik olayları.
Tercihler: dil, tema ve uygulama ayarları; onay kayıtlarınız.
Yalnız siz açarsanız: yaklaşık konum (hava durumu teması, konum paylaşımı), mikrofon/kamera (aramalar), rehber eşleştirme.

3. Toplama yöntemi
Veriler uygulama üzerinden, elektronik ortamda, kısmen otomatik yollarla (sizin girmeniz ve uygulamanın çalışması sırasında) toplanır.

4. Amaçlar ve hukuki sebepler
• Hesabın oluşturulması, mesajlaşma, arama ve diğer hizmetlerin sunulması — sözleşmenin kurulması ve ifası (KVKK m.5/2-c).
• Güvenlik, kötüye kullanımın ve saldırıların önlenmesi, hız sınırları — veri sorumlusunun meşru menfaati (m.5/2-f).
• Mevzuattan doğan yükümlülükler ve yetkili makam talepleri — hukuki yükümlülük (m.5/2-ç).
• Onay kayıtlarının saklanması — bir hakkın tesisi, kullanılması veya korunması (m.5/2-e).
• Kampanya ve duyuru e-postaları — yalnız ayrıca vereceğiniz isteğe bağlı onay ve açık rıza ile (m.5/1; 6563 s. Kanun).

5. Uçtan uca şifreleme ve güvenlik
Birebir sohbetlerde mesaj, fotoğraf, video, sesli mesaj, belge, konum ve hikâye yanıtları cihazınızda X25519 + ML-KEM-768 (kuantum sonrası hibrit) anahtar değişimi ve AES-256-GCM ile şifrelenir; özel anahtarlar telefonunuzdan çıkmaz, sunucu ve yöneticiler bu içerikleri okuyamaz. Grup ve kanal mesajları uçtan uca şifreli değildir, TLS ile korunur. Ayrıca: tüm bağlantılarda TLS, veritabanında satır düzeyi erişim kuralları, hız sınırları ve girdi doğrulaması, PIN'li kilitli sohbetler, oturum yönetimi; reklam ve izleme kütüphanesi kullanılmaz.

6. Aktarım ve yurt dışına aktarım
Veriler yalnız hizmetin sunulması için şu hizmet sağlayıcılara aktarılır: Supabase (veritabanı, dosya depolama, kimlik doğrulama), LiveKit Cloud (arama sırasında ses/görüntü akışı, kayıt yapılmaz), Google Firebase Cloud Messaging (bildirim), Deepgram (yalnız canlı altyazı/çeviri açıkken konuşma sesi), Google Çeviri / MyMemory (çevirisini istediğiniz metin), Open-Meteo (hava durumu teması açıksa ~10 km'ye yuvarlanmış konum). Bu sağlayıcıların sunucuları Türkiye dışındadır. Yurt dışına aktarım KVKK m.9 kapsamında uygun güvencelere (Kurul tarafından ilan edilen standart sözleşme) dayanılarak yapılır. Uçtan uca şifreli içerikler bu sağlayıcılarda yalnız okunamaz şifreli veri olarak bulunur. Kanunen yetkili kamu kurum ve kuruluşlarına, talep hâlinde ve mevzuatın izin verdiği ölçüde aktarım yapılabilir.

7. Saklama süresi
Veriler hesabınız açık olduğu sürece saklanır; hesap silindiğinde veriler ve medya silme kuyruğuna alınır. Mevzuatın öngördüğü süreler ve olası uyuşmazlıklar için gerekli kayıtlar (ör. onay kayıtları) bu süreler boyunca saklanır.

8. Haklarınız (KVKK m.11)
Kişisel verinizin işlenip işlenmediğini öğrenme, bilgi talep etme, amacına uygun kullanılıp kullanılmadığını öğrenme, aktarıldığı üçüncü kişileri bilme, eksik/yanlış işlenmişse düzeltilmesini, silinmesini veya yok edilmesini ve bunların aktarıldığı kişilere bildirilmesini isteme, münhasıran otomatik sistemlerle analiz sonucu aleyhinize bir sonuca itiraz etme ve kanuna aykırı işleme nedeniyle zararın giderilmesini talep etme haklarına sahipsiniz.

9. Başvuru
Başvurunuzu Veri Sorumlusuna Başvuru Usul ve Esasları Hakkında Tebliğ'e uygun olarak, uygulamada kayıtlı e-posta adresinizden engiincr@pm.me adresine yazılı olarak iletebilirsiniz. Başvurular en geç 30 gün içinde ücretsiz yanıtlanır. Başvurunuzun reddedilmesi, cevabı yetersiz bulmanız veya süresinde cevap verilmemesi hâlinde Kişisel Verileri Koruma Kurulu'na şikâyette bulunabilirsiniz (KVKK m.14).

Tam metin: Ayarlar → Yardım ve Destek → Gizlilik, KVKK ve yasal haklar.''',
        '''PRIVACY NOTICE (KVKK Art. 10 / GDPR Art. 13)

This text is for information only; it is not a consent form.

1. Controller
Engin ÇIRPAN (Juzzio, independent developer) · engiincr@pm.me

2. Data processed
Identity and contact: e-mail, username, display name, profile photo. Service data: messages, media, stories and posts, call logs. Device and security: notification token, device ID, sessions and security events. Preferences and your consent records. Only if you turn it on: approximate location (weather theme, location sharing), microphone/camera (calls), contact matching.

3. How it is collected
Electronically through the app, partly automatically.

4. Purposes and legal bases
Providing your account and the service (contract); security, abuse and attack prevention, rate limits (legitimate interest); legal obligations; keeping consent records (establishing/defending rights); marketing e-mails only with your separate, optional consent.

5. End-to-end encryption and security
In 1:1 chats, messages, photos, videos, voice notes, documents, locations and story replies are encrypted on your device with an X25519 + ML-KEM-768 (post-quantum hybrid) key exchange and AES-256-GCM; private keys never leave your phone and the server and admins cannot read this content. Group and channel messages are protected by TLS, not end-to-end. Also: TLS everywhere, row-level security, rate limits and input validation, PIN-locked chats, session management; no ads or tracking libraries.

6. Recipients and transfers abroad
Supabase (database, storage, auth), LiveKit Cloud (call media, no recording), Google Firebase Cloud Messaging (notifications), Deepgram (speech, only while live captions are on), Google Translate / MyMemory (texts you translate), Open-Meteo (location rounded to ~10 km, only with the weather theme). Their servers are outside Türkiye; transfers rely on appropriate safeguards (standard contractual clauses) under KVKK Art. 9 / GDPR Chapter V. Encrypted content exists there only as ciphertext. Data may be disclosed to competent authorities where the law requires.

7. Retention
While your account exists; on deletion, data and media are queued for removal. Records required by law or for possible disputes (e.g. consent records) are kept for those periods.

8. Your rights
Access, information, rectification, erasure, notification of recipients, objection to automated decisions, compensation (KVKK Art. 11) and, in the EU, portability and restriction (GDPR). Contact engiincr@pm.me from your registered e-mail; free reply within 30 days. You can complain to the Personal Data Protection Board (KVKK Art. 14) or your EU supervisory authority.

Full text: Settings → Help & Support → Privacy, data rights & legal.''',
        'Datenschutzhinweis (Zusammenfassung) — siehe Einstellungen → Hilfe → Datenschutz.',
      );

  /// Kullanım Koşulları'nın tam metni (uygulamaya gömülü yasal metinden, işaretler temizlenmiş)
  static String get terms => juzzioPlainLegal(_tr ? kJuzzioTermsMd : kJuzzioTermsMdEn);

  static String get ticariIleti => _l(
        '''TİCARİ ELEKTRONİK İLETİ ONAYI VE AÇIK RIZA METNİ (isteğe bağlı)

6563 sayılı Elektronik Ticaretin Düzenlenmesi Hakkında Kanun ve Ticari İletişim ve Ticari Elektronik İletiler Hakkında Yönetmelik kapsamında; Juzzio'nun yenilikleri, kampanyaları, etkinlikleri ve duyuruları hakkında kayıtlı e-posta adresime ticari elektronik ileti gönderilmesine onay veriyorum. Bu amaçla e-posta adresimin ve adımın işlenmesine KVKK m.5/1 uyarınca açık rıza veriyorum.

• Bu onay ZORUNLU DEĞİLDİR; vermemeniz uygulamayı kullanmanızı hiçbir şekilde etkilemez.
• Onayınızı dilediğiniz an, gerekçe göstermeden ve ücretsiz olarak Ayarlar → Bildirimler'den veya her e-postadaki bağlantıdan geri alabilirsiniz; geri alma bildiriminiz en geç 3 iş günü içinde işleme alınır.
• Onayınız ve geri almanız tarihiyle kayıt altına alınır; mevzuat gerektirdiğinde İleti Yönetim Sistemi'ne (İYS) iletilir.
• Verilerin işlenmesine ilişkin ayrıntılar Aydınlatma Metni'nde yer alır.''',
        '''MARKETING E-MAIL CONSENT (optional)

I agree to receive commercial e-mails about Juzzio news, campaigns, events and announcements at my registered e-mail address, and I consent to my e-mail address and name being processed for this purpose.

• This is OPTIONAL and does not affect your use of the app in any way.
• You can withdraw at any time, free of charge and without giving a reason, in Settings → Notifications or via the link in every e-mail; withdrawals are processed within 3 business days.
• Your consent and withdrawal are recorded with their date.
• Details of processing are in the Privacy Notice.''',
        'Einwilligung in Marketing-E-Mails (optional, jederzeit widerrufbar).',
      );
}

/// Markdown yasal metnini düz okunur metne çevirir (saf; test edilir)
String juzzioPlainLegal(String md) {
  var s = md.replaceAll('\r\n', '\n');
  s = s.replaceAll(RegExp(r'^#{1,6}[ \t]*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^>[ \t]?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^[ \t]*[-*][ \t]+', multiLine: true), '• ');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);
  s = s.replaceAll('**', '').replaceAll('`', '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Metin okuyucu: metin açılır, en alta inildiğinde onay düğmesi etkinleşir.
/// true → kullanıcı en alttaki düğmeye bastı.
Future<bool> juzzioShowConsentReader(
  BuildContext context, {
  required String title,
  required List<(String, String)> sections,
  required String confirmLabel,
  String? footnote,
}) async {
  final r = await showJuzzioSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioPalette(JuzzioAppController.instance.isDark).sheetBg,
    builder: (ctx) => JuzzioConsentReader(title: title, sections: sections, confirmLabel: confirmLabel, footnote: footnote),
  );
  return r == true;
}

/// Okuyucu (test edilebilmesi için herkese açık)
class JuzzioConsentReader extends StatefulWidget {
  const JuzzioConsentReader({super.key, required this.title, required this.sections, required this.confirmLabel, this.footnote});
  final String title;
  final List<(String, String)> sections;
  final String confirmLabel;
  final String? footnote;

  @override
  State<JuzzioConsentReader> createState() => _JuzzioConsentReaderState();
}

class _JuzzioConsentReaderState extends State<JuzzioConsentReader> {
  final ScrollController _sc = ScrollController();
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_check);
    // metin kısa ve kaydırma gerekmiyorsa düğme hemen etkin olur
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted || !_sc.hasClients || _atEnd) return;
    final pos = _sc.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) setState(() => _atEnd = true);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _toEnd() {
    if (!_sc.hasClients) return;
    _sc.animateTo(_sc.position.maxScrollExtent, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final txt = JuzzioGlassTokens.textPrimary;
    final sub = JuzzioGlassTokens.textSecondary;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: TextStyle(color: txt, fontSize: 17, fontWeight: FontWeight.w900))),
                IconButton(
                  tooltip: _l('Kapat', 'Close', 'Schließen'),
                  onPressed: () => Navigator.pop(context, false),
                  icon: Icon(Icons.close_rounded, color: sub),
                ),
              ]),
            ),
            Expanded(
              child: Stack(children: [
                Scrollbar(
                  controller: _sc,
                  thumbVisibility: true,
                  child: ListView(
                    controller: _sc,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 64),
                    children: [
                      for (final sec in widget.sections) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 6),
                          child: Text(sec.$1, style: TextStyle(color: JuzzioGlassTokens.glowText, fontSize: 14.5, fontWeight: FontWeight.w900)),
                        ),
                        SelectableText(sec.$2, style: TextStyle(color: txt, fontSize: 13.5, height: 1.5)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                if (!_atEnd)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('consent_to_end'),
                      onPressed: _toEnd,
                      icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18),
                      label: Text(_l('Sona in', 'Scroll to end', 'Zum Ende')),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.footnote != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(widget.footnote!, style: TextStyle(color: sub, fontSize: 12, height: 1.4)),
                  ),
                FilledButton(
                  key: const ValueKey('consent_confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: JuzzioGlassTokens.accentFill,
                    foregroundColor: JuzzioGlassTokens.onAccent,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _atEnd ? () => Navigator.pop(context, true) : null,
                  child: Text(
                    _atEnd ? widget.confirmLabel : _l('Devam etmek için metnin sonuna inin', 'Scroll to the end to continue', 'Bis zum Ende scrollen'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Zorunlu kutunun okuyucusu: Aydınlatma Metni + Kullanım Koşulları (ayrı başlıklar, ayrı beyanlar)
Future<bool> juzzioOpenRequiredConsent(BuildContext context) => juzzioShowConsentReader(
      context,
      title: _l('Aydınlatma Metni ve Kullanım Koşulları', 'Privacy Notice and Terms of Use', 'Datenschutz und Nutzungsbedingungen'),
      sections: [
        (_l('1 · KVKK Aydınlatma Metni', '1 · Privacy Notice', '1 · Datenschutzhinweis'), JuzzioConsentTexts.aydinlatma),
        (_l('2 · Kullanım Koşulları', '2 · Terms of Use', '2 · Nutzungsbedingungen'), JuzzioConsentTexts.terms),
      ],
      confirmLabel: _l('Okudum ve anladım', 'I have read and understood', 'Gelesen und verstanden'),
      footnote: _l(
        'Bu düğmeye basarak: (1) Aydınlatma Metni\'ni okuyup anladığınızı beyan edersiniz — bu bir rıza değildir; (2) Kullanım Koşulları\'nı kabul eder ve 15 yaşından büyük olduğunuzu beyan edersiniz.',
        'By tapping this you (1) confirm you have read and understood the Privacy Notice — this is not consent; and (2) accept the Terms of Use and confirm you are over 15.',
        'Damit bestätigst du, den Datenschutzhinweis gelesen zu haben, und akzeptierst die Nutzungsbedingungen (ab 15 Jahren).',
      ),
    );

/// İsteğe bağlı kutunun okuyucusu: ticari ileti onayı (ayrı metin)
Future<bool> juzzioOpenMarketingConsent(BuildContext context) => juzzioShowConsentReader(
      context,
      title: _l('Kampanya ve duyuru e-postaları', 'News & campaign e-mails', 'Neuigkeiten per E-Mail'),
      sections: [(_l('İsteğe bağlı onay', 'Optional consent', 'Optionale Einwilligung'), JuzzioConsentTexts.ticariIleti)],
      confirmLabel: _l('Onay veriyorum', 'I agree', 'Ich willige ein'),
    );

/// Onay paneli: yalnız İKİ özel tik kutusu
class JuzzioConsentPanel extends StatelessWidget {
  const JuzzioConsentPanel({super.key, required this.state, required this.onChanged, this.showError = false});

  final JuzzioConsentState state;
  final ValueChanged<JuzzioConsentState> onChanged;

  /// Zorunlu kutu işaretlenmeden gönderilmeye çalışıldıysa kırmızıyla vurgulanır
  final bool showError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: JuzzioGlassTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: showError && !state.requiredAccepted ? const Color(0xFFFF5A6A) : JuzzioGlassTokens.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _JuzzioConsentTick(
          value: state.termsNotice,
          error: showError && !state.termsNotice,
          label: _l(
            'Kullanım Koşulları\'nı kabul ediyorum ve 15 yaşından büyük olduğumu beyan ederim. KVKK Aydınlatma Metni\'ni okudum ve anladım.',
            'I accept the Terms of Use and confirm I am over 15. I have read and understood the Privacy Notice.',
            'Ich akzeptiere die Nutzungsbedingungen, bin über 15 und habe den Datenschutzhinweis gelesen.',
          ),
          onChanged: (v) async {
            if (!v) {
              onChanged(state.copyWith(termsNotice: false));
              return;
            }
            final ok = await juzzioOpenRequiredConsent(context);
            if (ok) onChanged(state.copyWith(termsNotice: true));
          },
        ),
        Divider(height: 1, color: JuzzioGlassTokens.border),
        _JuzzioConsentTick(
          value: state.marketing,
          optional: true,
          label: _l(
            'Kampanya, yenilik ve duyuru e-postaları almak istiyorum (isteğe bağlı).',
            'Send me news, campaign and announcement e-mails (optional).',
            'Neuigkeiten per E-Mail (optional).',
          ),
          onChanged: (v) async {
            if (!v) {
              onChanged(state.copyWith(marketing: false));
              return;
            }
            final ok = await juzzioOpenMarketingConsent(context);
            if (ok) onChanged(state.copyWith(marketing: true));
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Row(children: [
            Icon(Icons.lock_rounded, size: 13, color: JuzzioGlassTokens.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _l('Birebir sohbetler uçtan uca şifreli (kuantum sonrası hibrit). Reklam ve izleme yok.',
                    '1:1 chats are end-to-end encrypted (post-quantum hybrid). No ads, no tracking.', 'Ende-zu-Ende-verschlüsselt. Keine Werbung.'),
                style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Özel tik kutusu: yaylı dolan kare + çizilen tik (Material Checkbox değil)
class _JuzzioConsentTick extends StatelessWidget {
  const _JuzzioConsentTick({
    required this.value,
    required this.label,
    required this.onChanged,
    this.error = false,
    this.optional = false,
  });

  final bool value;
  final String label;
  final Future<void> Function(bool) onChanged;
  final bool error;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final accent = JuzzioGlassTokens.glow;
    final border = error ? const Color(0xFFFF5A6A) : (value ? accent : JuzzioGlassTokens.textSecondary.withValues(alpha: 0.6));
    return Semantics(
      checked: value,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          JuzzioHaptics.toggle();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: kJuzzioSpring,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 2),
                boxShadow: value ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 10)] : null,
              ),
              child: AnimatedScale(
                scale: value ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: kJuzzioSpring,
                child: Icon(Icons.check_rounded, size: 17, color: JuzzioGlassTokens.onAccent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (!optional) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFFF5A6A), fontWeight: FontWeight.w900)),
                  const TextSpan(text: '  '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.article_outlined, size: 15, color: JuzzioGlassTokens.glowText),
                  ),
                ]),
                style: TextStyle(
                  color: error ? const Color(0xFFFF8A95) : JuzzioGlassTokens.textPrimary,
                  fontSize: 12.8,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Oturumu açık kalmış eski kullanıcılar ve metin sürümü değişince: zorunlu kutu (koşullar + 15 yaş + aydınlatma beyanı) alınmadan
/// uygulamaya devam edilmez. Reddedilirse [onDecline] (oturumu kapatır) çağrılır.
/// Ağ hatasında kullanıcı engellenmez (çevrimdışı açılış bozulmasın); bir sonraki açılışta yine sorulur.
Future<void> juzzioEnsureConsent(BuildContext context, {required Future<void> Function() onDecline}) async {
  final svc = JuzzioConsentService.instance;
  await svc.flushPending();
  String? current;
  try {
    final r = await SupabaseService.instance.client.rpc('my_consent_version');
    current = r?.toString();
  } catch (_) {
    return;
  }
  if (current == kJuzzioConsentVersion || !context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _JuzzioConsentDialog(),
  );
  if (ok != true) await onDecline();
}

class _JuzzioConsentDialog extends StatefulWidget {
  const _JuzzioConsentDialog();

  @override
  State<_JuzzioConsentDialog> createState() => _JuzzioConsentDialogState();
}

class _JuzzioConsentDialogState extends State<_JuzzioConsentDialog> {
  JuzzioConsentState _s = const JuzzioConsentState();
  bool _err = false;
  bool _busy = false;

  Future<void> _continue() async {
    if (!_s.requiredAccepted) {
      setState(() => _err = true);
      final ok = await juzzioOpenRequiredConsent(context);
      if (!ok || !mounted) return;
      setState(() => _s = _s.copyWith(termsNotice: true));
    }
    setState(() => _busy = true);
    await JuzzioConsentService.instance.record(_s);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: p.sheetBg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_l('Metinlerimiz güncellendi', 'Our terms were updated', 'Aktualisierte Bedingungen'),
                  style: TextStyle(color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                _l('Aydınlatma Metni ve Kullanım Koşulları güncellendi. Devam etmek için zorunlu kutuya dokunup metinleri okuyun.',
                    'The Privacy Notice and Terms were updated. Tap the required box and read them to continue.', 'Bitte lies die aktualisierten Texte.'),
                style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              JuzzioConsentPanel(state: _s, showError: _err, onChanged: (v) => setState(() => _s = v)),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: JuzzioGlassTokens.accentFill,
                  foregroundColor: JuzzioGlassTokens.onAccent,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _busy ? null : _continue,
                child: Text(_l('Devam et', 'Continue', 'Weiter'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(_l('Kabul etmiyorum — çıkış yap', 'I do not accept — sign out', 'Ablehnen — abmelden'),
                    style: TextStyle(color: p.textSecondary)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ayarlar → Bildirimler: kampanya / duyuru e-postaları onayı (verme ve geri alma kaydedilir)
class JuzzioMarketingConsentTile extends StatefulWidget {
  const JuzzioMarketingConsentTile({super.key});

  @override
  State<JuzzioMarketingConsentTile> createState() => _JuzzioMarketingConsentTileState();
}

class _JuzzioMarketingConsentTileState extends State<JuzzioMarketingConsentTile> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final r = await SupabaseService.instance.client.from('profiles').select('marketing_opt_in').eq('id', uid).maybeSingle();
      if (mounted) setState(() => _on = r?['marketing_opt_in'] == true);
    } catch (_) {
      if (mounted) setState(() => _on = false);
    }
  }

  Future<void> _set(bool v) async {
    setState(() {
      _busy = true;
      _on = v;
    });
    try {
      await JuzzioConsentService.instance.setMarketing(v);
    } catch (e) {
      if (mounted) {
        setState(() => _on = !v);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Container(
      decoration: BoxDecoration(color: p.cardBg, borderRadius: BorderRadius.circular(24), border: Border.all(color: p.glassBorder)),
      child: JuzzioSwitchListTile(
        style: JuzzioToggleStyle.check,
        secondary: Icon(Icons.mark_email_unread_rounded, color: p.amberGlow),
        title: Text(_l('Kampanya ve duyuru e-postaları', 'News & campaign e-mails', 'Neuigkeiten per E-Mail'),
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        subtitle: Text(
          _l('Ticari elektronik ileti onayı (isteğe bağlı). Kapatınca onayın geri alınır ve kaydedilir.',
              'Optional marketing consent. Turning it off withdraws your consent (recorded).', 'Optionale Einwilligung; jederzeit widerrufbar.'),
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
        value: _on ?? false,
        onChanged: (_on == null || _busy) ? null : _set,
      ),
    );
  }
}
