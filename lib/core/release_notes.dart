// =============================================================================
// JUZZIO v0.6.1 — Şeffaf güncelleme notları
//  Her sürüm için: neden getirildi, yeni özellikler, düzeltilen hatalar,
//  güvenlik / gizlilik değişiklikleri. Yönetici panelinden yayınlanan sürümler
//  (app_releases.details) ile uygulamaya gömülü geçmiş birleştirilir.
//  Kullanıcının dilinde yoksa Türkçe metin otomatik çevrilir.
// =============================================================================

import 'app_theme_and_locale.dart';

/// Bir dildeki not içeriği
class JuzzioReleaseSection {
  final String reason;
  final List<String> features;
  final List<String> fixes;
  final List<String> security;

  const JuzzioReleaseSection({
    this.reason = '',
    this.features = const <String>[],
    this.fixes = const <String>[],
    this.security = const <String>[],
  });

  bool get isEmpty => reason.trim().isEmpty && features.isEmpty && fixes.isEmpty && security.isEmpty;

  static List<String> _lines(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String) {
      return raw
          .split('\n')
          .map((e) => e.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  factory JuzzioReleaseSection.fromMap(Object? raw) {
    if (raw is! Map) return const JuzzioReleaseSection();
    return JuzzioReleaseSection(
      reason: (raw['reason'] ?? '').toString().trim(),
      features: _lines(raw['features']),
      fixes: _lines(raw['fixes']),
      security: _lines(raw['security']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'reason': reason,
        'features': features,
        'fixes': fixes,
        'security': security,
      };
}

class JuzzioReleaseNote {
  final String versionName;
  final int versionCode;
  final DateTime? publishedAt;
  final bool mandatory;
  final String legacyNotes;
  final Map<String, JuzzioReleaseSection> sections; // dil kodu → içerik

  const JuzzioReleaseNote({
    required this.versionName,
    required this.versionCode,
    this.publishedAt,
    this.mandatory = false,
    this.legacyNotes = '',
    this.sections = const <String, JuzzioReleaseSection>{},
  });

  /// app_releases satırından (yönetici panelinden yayınlanan sürüm)
  factory JuzzioReleaseNote.fromRow(Map<String, dynamic> row) {
    final details = row['details'];
    final sections = <String, JuzzioReleaseSection>{};
    if (details is Map) {
      details.forEach((k, v) {
        final s = JuzzioReleaseSection.fromMap(v);
        if (!s.isEmpty) sections[k.toString()] = s;
      });
    }
    return JuzzioReleaseNote(
      versionName: (row['version_name'] ?? '').toString(),
      versionCode: (row['version_code'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse((row['published_at'] ?? '').toString())?.toLocal(),
      mandatory: row['is_mandatory'] == true,
      legacyNotes: (row['notes_tr'] ?? '').toString(),
      sections: sections,
    );
  }

  /// Kullanıcının dilindeki içerik; yoksa Türkçe metin (ekranda otomatik çevrilir)
  JuzzioReleaseSection sectionFor(String lang) {
    final code = lang.toLowerCase();
    final exact = sections[code];
    if (exact != null && !exact.isEmpty) return exact;
    final tr = sections['tr'];
    if (tr == null || tr.isEmpty) return const JuzzioReleaseSection();
    final en = sections['en'];
    final de = sections['de'];
    final app = JuzzioAppController.instance;
    String t(String trText, String? enText, String? deText) =>
        app.translateUiDynamic(trText, enText: enText, deText: deText);
    String? at(List<String>? list, int i) => (list != null && i < list.length) ? list[i] : null;
    return JuzzioReleaseSection(
      reason: t(tr.reason, en?.reason, de?.reason),
      features: [for (var i = 0; i < tr.features.length; i++) t(tr.features[i], at(en?.features, i), at(de?.features, i))],
      fixes: [for (var i = 0; i < tr.fixes.length; i++) t(tr.fixes[i], at(en?.fixes, i), at(de?.fixes, i))],
      security: [for (var i = 0; i < tr.security.length; i++) t(tr.security[i], at(en?.security, i), at(de?.security, i))],
    );
  }

  /// Yönetici satırı ile gömülü geçmiş birleşirken boş alanları tamamlar
  JuzzioReleaseNote mergedWith(JuzzioReleaseNote? bundled) {
    if (bundled == null) return this;
    return JuzzioReleaseNote(
      versionName: versionName,
      versionCode: versionCode > 0 ? versionCode : bundled.versionCode,
      publishedAt: publishedAt ?? bundled.publishedAt,
      mandatory: mandatory,
      legacyNotes: legacyNotes.isNotEmpty ? legacyNotes : bundled.legacyNotes,
      sections: sections.isNotEmpty ? sections : bundled.sections,
    );
  }

  static int compareSemver(String a, String b) {
    List<int> parts(String v) => v.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Yönetici sürümleri + gömülü geçmiş → yeniden eskiye sıralı tek liste
  static List<JuzzioReleaseNote> mergeAll(List<JuzzioReleaseNote> remote) {
    final byVersion = <String, JuzzioReleaseNote>{};
    for (final b in kJuzzioBundledReleaseNotes) {
      byVersion[b.versionName] = b;
    }
    for (final r in remote) {
      if (r.versionName.isEmpty) continue;
      byVersion[r.versionName] = r.mergedWith(byVersion[r.versionName]);
    }
    final list = byVersion.values.toList()..sort((a, b) => compareSemver(b.versionName, a.versionName));
    return list;
  }
}

/// Uygulamaya gömülü sürüm geçmişi (yayınlanmış sürümlerin gerçek içeriği)
final List<JuzzioReleaseNote> kJuzzioBundledReleaseNotes = <JuzzioReleaseNote>[
  JuzzioReleaseNote(
    versionName: '0.8.4',
    versionCode: 84,
    publishedAt: DateTime(2026, 11, 1),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "12 temayı tek bir Liquid Glass tasarım ailesinde birleştirmek, her temayı hem uygulama hem sohbet teması olarak seçilebilir yapmak ve CI analiz hatasını gidermek için getirildi.",
        features: [
          "12 tema tek Liquid Glass ailesi: her temanın kendi cam karakteri (blur, opaklık, ışık yansıması, derinlik, kenar ışığı)",
          "Ayarlar › Görünüm: tüm uygulama arayüz temaları ve sohbet temaları tek galeride",
          "12 cam teması artık sohbet teması olarak da seçilebiliyor; 16 klasik sohbet teması korunuyor",
          "Tema önizlemesinde ve cam teması listesinde tema karakteri açıklaması",
          "Siber Neon'da neon kenar parıltısı, Krom'da metalik yansıma, Obsidyen OLED'de derin katmanlar",
        ],
        fixes: [
          "CI analiz hatası: 'num' tür adını gölgeleyen yerel fonksiyon yeniden adlandırıldı",
          "Sohbet parlaklık kaydırıcısı seçili temayı sıfırlamıyor",
          "Açık renkli temalarda (Cam Beyaz, Krom vb.) giden mesaj balonunda beyaz yazı okunur kalıyor (WCAG AA ≥ 4.5:1)",
        ],
        security: [
          "Veritabanı değişikliği yok; tema seçimleri yalnızca kullanıcının kendi tercihlerine kaydedilir",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Unifies the 12 themes into one Liquid Glass design family, makes every theme selectable as both app and chat theme, and fixes the CI analyze error.",
        features: [
          "12 themes, one Liquid Glass family: each theme has its own glass character (blur, opacity, sheen, depth, rim light)",
          "Settings › Appearance: all app and chat themes in one gallery",
          "All 12 glass themes can now be used as chat themes; 16 classic chat themes kept",
          "Theme character description in preview and glass theme list",
          "Neon rim glow on Cyber Neon, metallic sheen on Chrome, deep layers on Obsidian OLED",
        ],
        fixes: [
          "CI analyze error: local function shadowing the 'num' type renamed",
          "Chat brightness slider no longer resets the selected theme",
          "White text on outgoing bubbles stays readable on light themes (WCAG AA ≥ 4.5:1)",
        ],
        security: [
          "No database changes; theme choices are stored only in the user's own preferences",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.8.3',
    versionCode: 83,
    publishedAt: DateTime(2026, 11, 1),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Tema sistemini uygulamanın tamamını yöneten bir tasarım motoruna dönüştürmek, yöneticiye güvenli küresel tema yayını ve rol tabanlı yetki vermek ve bildirimden uygulamayı açmadan yanıt verebilmek için getirildi.",
        features: [
          "Tema Stüdyosu: kendi temanı oluştur; 13 renk rolü, HEX/RGB/HSL seçici, blur/opaklık/yoğunluk, canlı önizleme",
          "Temaları JSON ile içe/dışa aktar, çoğalt, yeniden adlandır, varsayılana dön",
          "Zamanlı gece/gündüz modu",
          "Bildirimden hızlı yanıt: uygulamayı açmadan, uçtan uca şifreli",
          "Juzzio'nun önerdiği tema (yönetici yayını; tema seçmeyenler için, kapatılabilir)",
          "5 yeni tema: Obsidyen OLED, Lavanta Sisi, Gül Kuvars, Siber Neon, Yüksek Kontrast",
          "Cam yoğunluğu ve performans modu",
        ],
        fixes: [
          "Arama ekranı ve oyun ekranı artık seçili temaya uyuyor",
          "Telefonun açık/koyu ayarı değişince tema anında güncelleniyor",
          "Yeni telefonda hesabın uygulama dili otomatik geliyor",
          "Düşük donanımlı cihazlarda bulanıklık otomatik azaltılıyor",
        ],
        security: [
          "Rol tabanlı yetki (RBAC): yönetici, moderatör, destek, analist, içerik yöneticisi, denetçi; tüm işlemler denetim kaydında",
          "Küresel temalar sunucuda doğrulanıyor; taslaklar yalnızca yetkililere görünür (RLS)",
          "Hızlı yanıt normal şifreli gönderim yolunu kullanır; metin cihazda saklanmaz",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Turns the theme system into a design engine for the whole app, adds safe global theme publishing with role-based access, and lets you reply from notifications without opening the app.",
        features: [
          "Theme Studio: build your own theme with 13 color roles, HEX/RGB/HSL picker, glass controls and live preview",
          "Import/export themes as JSON, duplicate, rename, reset",
          "Scheduled light/dark mode",
          "Quick reply from notifications, end-to-end encrypted",
          "Juzzio recommended theme (published by admins, optional)",
          "5 new themes",
          "Glass intensity and performance mode",
        ],
        fixes: [
          "Call and game screens follow the selected theme",
          "Theme follows system appearance instantly",
          "App language syncs to new devices",
          "Blur reduced automatically on low-end devices",
        ],
        security: [
          "Role-based access control with audit log",
          "Global themes validated server-side; drafts visible only to staff (RLS)",
          "Quick reply uses the normal encrypted send path",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.8.0',
    versionCode: 80,
    publishedAt: DateTime(2026, 11, 1),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Mesajlaşmayı kuantum bilgisayarlara karşı bile güvenli hâle getirmek, telefon değiştirince hiçbir şeyin kaybolmamasını sağlamak (şifreli Google Drive yedeği) ve arayüzü yumuşak, okunaklı cam tasarıma taşımak için getirildi. 0.6.1 ve 0.7.0'ın tüm ayrıntıları da aşağıda ve Ayarlar → Güncellemeler'de.",
        features: [
          "Kuantum sonrası uçtan uca şifreleme: X25519 + ML-KEM-768 (NIST FIPS 203) hibrit anahtar değişimi, AES-256-GCM",
          "Otomatik anahtar yenileme: 50 mesajda/24 saatte bir yeni oturum anahtarı, 30 günde bir yeni kimlik anahtarı",
          "Ayarlar → Mesajları / Sohbetleri yedekle: en az 8 karakterlik şifreyle Google Drive'a şifreli yedek",
          "Yeni telefonda veya yeniden kurulumda girişten sonra 'Yedeği geri yükle'",
          "Güncelleme dosyaları için ML-DSA-65 (FIPS 204) imza doğrulama altyapısı",
          "Ayarlar → Hakkında: baştan tasarlanan yapımcı sayfası",
          "Yönetici girişi artık ayrı, cam temalı bir sayfa",
          "Sohbette 'son mesaja git' düğmesi",
          "0.6.1 özeti: güncelleme notları sayfası, zorunlu güncelleme rozeti, gerekçeli sürüm yayını, konum izninin kaldırılması, medya klasörlerinin listelenememesi",
          "0.7.0 özeti: uçtan uca şifreleme (🔒), zil sesleri, kişi bilgisi ve arama ayrıntısı sayfaları, YouTube'suz müzik, yakın arkadaşlar, 6 widget, Yenilikler penceresi, anında güncelleme bildirimi",
        ],
        fixes: [
          "Cam tema yumuşatıldı: arka plan görünür, blur sert değil; renk binmesi ve çamurlanma giderildi",
          "Arama çubuğundaki çift kenarlık, çipler, + düğmesi ve Mesajlar rozetindeki boş beyaz daire düzeltildi",
          "İzlenen hikâyenin renkli halkası artık kayboluyor",
          "Profildeki Gönderiler/Kaydedilenler siyah şeridi kaldırıldı",
          "Gönderi metnindeki açık boşluklar ve yazı kayması/titreme düzeltildi",
          "Emoji paneli veya klavye açılınca son mesaj artık altında kalmıyor",
          "Sohbet teması önizleme balonları gerçek balonlarla aynı",
          "Alt sayfa tutamaçları aydınlık temada da görünüyor",
        ],
        security: [
          "Gizlilik politikası güncellendi: kuantum sonrası şifreleme ve Drive yedeği açıklandı",
          "Kullanım koşulları ve lisansa izinsiz erişim ve saldırılara karşı yasal maddeler eklendi (TCK 132-136, 243-245, KVKK, FSEK, 5651)",
          "Yedek şifresi Argon2id ile korunur, hiçbir yere gönderilmez",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Released to make messaging safe even against quantum computers, make sure nothing is lost when changing phones (encrypted Google Drive backup) and move the UI to a soft, readable glass design. Full details of 0.6.1 and 0.7.0 are included below and in Settings → Updates.",
        features: [
          "Post-quantum end-to-end encryption: hybrid X25519 + ML-KEM-768 (NIST FIPS 203), AES-256-GCM",
          "Automatic rekeying every 50 messages/24 h; new identity key every 30 days",
          "Settings → Back up messages: encrypted Google Drive backup with a password (min. 8 characters)",
          "'Restore backup' after login on a new phone or reinstall",
          "ML-DSA-65 (FIPS 204) signature verification for updates",
          "Settings → About: redesigned creator page",
          "Admin login is now a separate glass page",
          "'Jump to latest' button in chats",
          "0.6.1 recap: release notes page, mandatory badge, release reasons, location permission removed, media folders no longer listable",
          "0.7.0 recap: end-to-end encryption, ringtones, contact and call detail pages, music without YouTube, close friends, 6 widgets, What's new sheet, instant update notice",
        ],
        fixes: [
          "Softer glass: visible background, gentle blur, no colour bleeding",
          "Search bar double border, chips, + button and empty white badge fixed",
          "Viewed stories lose their coloured ring",
          "Black band behind Posts/Saved tabs removed",
          "Wide gaps and jumping text in posts fixed",
          "Last message no longer hidden by keyboard or emoji panel",
          "Chat theme preview bubbles match real bubbles",
          "Sheet handles visible in light mode",
        ],
        security: [
          "Privacy policy updated (post-quantum crypto, Drive backup)",
          "Legal articles against unauthorised access and attacks added to terms and license",
          "Backup password protected with Argon2id and never sent anywhere",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.7.0',
    versionCode: 70,
    publishedAt: DateTime(2026, 11, 1),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Kullanıcı geri bildirimlerindeki tüm sorunları tek pakette çözmek, gizliliği güçlendirmek (uçtan uca şifreleme) ve uygulamadaki her şeyi açıkça anlatmak için getirildi.",
        features: [
          "1'e 1 yazılı mesajlarda uçtan uca şifreleme (🔒)",
          "Zil sesleri ve uyarı tonları: Juzzio'ya özel sesler, varsayılan ve kişiye özel zil sesi/bildirim tonu",
          "Kişi bilgisi sayfası: profil, arama, süreli mesajlar, sessize al, özel tonlar, engelle",
          "Arama ayrıntısı sayfası (başlangıç/cevap/bitiş saati, süre, ilk kim kapattı) ve arama filtreleri; arama kayıtları sohbette görünür",
          "Müzik: YouTube kaldırıldı; isimle arama, tek dokunuşla ekleme, profilde oynat/durdur, hikâyede otomatik çalma",
          "Yakın arkadaşlar: hikâyeyi yalnızca seçtiğin favori arkadaşlar görür",
          "6 farklı Android widget'ı (tema ve dil uyumlu)",
          "Güncellemeden sonra 'Yenilikler' penceresi; notlar GitHub'dan otomatik gelir",
          "Yeni sürüm yayınlanınca anında güncelleme bildirimi",
          "Cam Beyaz teması, üçlü tema seçici, yeniden tasarlanan güncelleme merkezi",
          "Ekran görüntüsüyle hata bildirme; uygulama içi Gizlilik/KVKK/Kullanım koşulları/Lisans",
          "Saman yuvası civciv sahnesi; beslendikçe titreyen ve çatlayan yumurta",
          "Yaylı ve dirençli 'kaydır → yanıtla' animasyonu",
        ],
        fixes: [
          "Ertelenen güncelleme bildirimi her açılışta tekrar çıkıyordu; erteleme artık kalıcı",
          "Aynı dili konuşanlar arasında çeviri paneli açılıyordu; yalnızca farklı dil olunca açılır",
          "Görüntülü aramada yeşil konuşma halkası/çerçevesi ve sesli aramadaki 'Ben' kartı kaldırıldı",
          "Aramalar sayfasında çevrimdışı kişiler de çevrimiçi görünüyordu",
          "Hikâye kamerasında ön/arka geçiş çalışmıyordu",
          "Hikâye yazı boyutu paylaşınca değişiyordu; çekilen fotoğraf kayıyor/aynalanıyordu",
          "Sohbete girince son mesaj yerine ortadan bir mesaj açılıyordu",
          "Gönderilerde 'çevrilemedi' hatası ve yazı kayması",
          "Yönetici teması herkese uygulanıyor ve değiştirmeyi engelliyordu",
          "Aydınlık temada okunmayan beyaz yazılar ve buton ton uyumsuzlukları",
          "Görüşme sırasında ekran kararıp sönüyordu",
        ],
        security: [
          "Aramalarda konuşma artık ceza sebebi değil; konuşma sesi yalnızca farklı dil varsa altyazı hizmetine gider",
          "Göstermelik 'bulut yedekleme' ve 'QR aktarım' ekranları kaldırıldı, verilerin nasıl saklandığı açıklandı",
          "Sahip olunmayan alan adına giden paylaşım bağlantıları resmi indirme sayfasına çevrildi",
          "Gizli bilgi taraması README dahil tüm dosyalara genişletildi",
          "Arka plan uyanık kalma kilidi 24 saatten 10 dakikaya indirildi",
          "Tescilli lisans: kopyalama, çoğaltma ve satış yasak",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Released to fix every issue from user feedback in one package, strengthen privacy (end-to-end encryption) and explain everything in the app openly.",
        features: [
          "End-to-end encryption for 1:1 text messages (🔒)",
          "Ringtones & alert tones: Juzzio sounds, default and per-contact",
          "Contact info page: profile, calls, disappearing messages, mute, custom tones, block",
          "Call details page and call filters; call records appear in chats",
          "Music: YouTube removed; search by name, add with one tap, play/stop on profile, auto-play in stories",
          "Close friends for stories",
          "6 Android widgets (theme and language aware)",
          "'What's new' sheet after updating, notes fetched from GitHub automatically",
          "Instant update notification on release",
          "Glass White theme, three-way theme selector, redesigned update center",
          "Bug reports with screenshots; in-app privacy, terms and license",
          "Straw-nest chick scene with a wobbling, cracking egg",
          "Springy swipe-to-reply",
        ],
        fixes: [
          "Snoozed update notice reappeared on every launch",
          "Translation panel opened between same-language speakers",
          "Speaking ring in video calls and 'Me' card in voice calls removed",
          "Offline people looked online on the calls page",
          "Front/back camera switch in story camera",
          "Story text size changed after sharing; captured photo shifted/mirrored",
          "Chats opened in the middle instead of the latest message",
          "'Translation unavailable' error and text jumping in posts",
          "Admin theme was forced on everyone",
          "Unreadable white text and button tones in light mode",
          "Screen dimmed during calls",
        ],
        security: [
          "Speech is never a reason for penalties; call audio goes to the caption service only when another language is present",
          "Fake 'cloud backup' and 'QR transfer' screens removed",
          "Share links to an unowned domain replaced with the official download page",
          "Secret scanning extended to all files including README",
          "Background wake lock reduced from 24 h to 10 min",
          "Proprietary license: copying, redistribution and sale prohibited",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.6.1',
    versionCode: 61,
    publishedAt: DateTime(2026, 11, 1),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason:
            'Kullanıcılarımızın verilerinin nasıl korunduğunu ve her güncellemede neyin değiştiğini açıkça görebilmesi için getirildi. Aynı zamanda bir güvenlik açığı kapatıldı.',
        features: [
          'Güncelleme notları sayfası: her sürümün neden getirildiği, yeni özellikleri, düzeltilen hataları ve güvenlik değişiklikleri.',
          'Güncelleme bildiriminde "Ayrıntılar" düğmesi; güncellemeden önce neyin değiştiğini okuyabilirsiniz.',
          'Zorunlu güncellemeler artık açıkça "Zorunlu" olarak işaretlenir ve ertelenemez.',
        ],
        fixes: [
          'Zorunlu olarak yayınlanan güncellemeler uygulamada zorunlu olarak uygulanmıyordu; düzeltildi.',
        ],
        security: [
          'Sohbet fotoğrafları ve sesli mesaj dosyalarının adları, uygulamaya gömülü herkese açık anahtarla listelenebiliyordu. Listeleme kapatıldı; artık herkes yalnızca kendi dosyalarını listeleyebilir.',
          'Uygulama hiç kullanmadığı konum iznini artık istemiyor ve konum izni Android bildiriminden kaldırıldı.',
        ],
      ),
      'en': JuzzioReleaseSection(
        reason:
            'So that our users can clearly see how their data is protected and what changes in every update. A security weakness was also closed.',
        features: [
          'Release notes page: why each version was released, new features, fixed bugs and security changes.',
          '"Details" button on the update notice, so you can read what changed before updating.',
          'Mandatory updates are now clearly labelled "Mandatory" and cannot be postponed.',
        ],
        fixes: [
          'Updates published as mandatory were not enforced in the app; fixed.',
        ],
        security: [
          'The names of chat photos and voice message files could be listed with the public key built into the app. Listing is now closed; everyone can only list their own files.',
          'The app no longer asks for the location permission it never used, and the permission was removed from the Android manifest.',
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.6.0',
    versionCode: 60,
    publishedAt: DateTime(2026, 10, 31),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason:
            'Uygulamayı daha modern hale getirmek ve kullanıcıları müstehcen, küfürlü ve uygunsuz içerikten korumak için getirildi.',
        features: [
          'Uygulamanın tamamında Glassmorphism (buzlu cam) tasarım ve 5 cam teması.',
          'Android ana ekran widget\'ı: okunmamış mesajlar, son sohbet ve kısayollar.',
          'Görüntülü aramada müstehcen görüntü ve ağır küfür algılanınca arama kapanır; ceza basamağı: 1 saat, 4 saat, kalıcı engel.',
          'Ad, kullanıcı adı, grup adı ve profil fotoğrafında müstehcen içerik denetimi.',
          'Yönetici panelinde denetim merkezi, gruplar, canlı aramalar ve içerik yönetimi.',
        ],
        fixes: [
          'Süreli uzaklaştırma süresi dolduğu halde hesap erişimi açılmıyordu; düzeltildi.',
          'Kısa süreli ceza alan bir kişinin yeni cihazı kalıcı olarak engelleniyordu; düzeltildi.',
        ],
        security: [
          'Görüntülü aramada denetim için yalnızca kişinin KENDİ kamerasından küçük kareler, Google Cloud Vision\'a gönderilir; kareler saklanmaz, yalnızca sonuç kaydedilir.',
          'Konuşma denetiminde metin saklanmaz; yalnızca ağır ifade sayısı tutulur.',
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: 'To make the app more modern and to protect users from explicit, abusive and inappropriate content.',
        features: [
          'Glassmorphism (frosted glass) design across the app with 5 glass themes.',
          'Android home screen widget: unread messages, latest chat and shortcuts.',
          'Explicit video or heavy abuse in a video call ends the call; penalty ladder: 1 hour, 4 hours, permanent ban.',
          'Explicit content checks for names, usernames, group names and profile photos.',
          'Admin panel moderation center, groups, live calls and content management.',
        ],
        fixes: [
          'Account access did not reopen after a timed suspension ended; fixed.',
          'A new device of someone with a short suspension was banned permanently; fixed.',
        ],
        security: [
          'For moderation, only small frames from the user\'s OWN camera are sent to Google Cloud Vision during video calls; frames are not stored, only the result is recorded.',
          'Speech moderation stores no text; only the number of abusive phrases is kept.',
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.5.1',
    versionCode: 51,
    publishedAt: DateTime(2026, 10, 31),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: 'Konferans aramalarında düzeni sağlamak ve hikâye/akış deneyimini tamamlamak için getirildi.',
        features: [
          'Aramayı başlatan kişi veya grup yöneticisi konferanstan katılımcı çıkarabilir (yetki sunucuda doğrulanır).',
          'Hikâye stüdyosunda flaş ve emoji çıkartmaları.',
          'Küresel akışta konular ve canlı yeni paylaşım bildirimi.',
          'Tüm uygulamada tutarlı emoji seti.',
        ],
        fixes: [
          'Hikâye başlığında uzun adların kesilmesi düzeltildi.',
          'Veritabanı tek dosyada birleştirildi; veri silinmeden uygulanır.',
        ],
        security: [
          'Çıkarılan kişi aynı görüşmeye yeniden giriş anahtarı alamaz.',
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: 'To keep order in conference calls and complete the story/feed experience.',
        features: [
          'The call host or a group admin can remove participants from a conference (authorised on the server).',
          'Flash and emoji stickers in the story studio.',
          'Topics and live new-post notice in the global feed.',
          'A consistent emoji set across the app.',
        ],
        fixes: [
          'Long names being cut off in the story header was fixed.',
          'The database was merged into a single file; it applies without data loss.',
        ],
        security: [
          'A removed person cannot get a new join key for the same call.',
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.5.0',
    versionCode: 50,
    publishedAt: DateTime(2026, 10, 30),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: 'Canlı çeviriyi uzun aramalarda kararlı hale getirmek ve tasarımı sadeleştirmek için getirildi.',
        features: [
          'Bölüt tabanlı canlı çeviri; sesli ve görüntülü arama için ayrı arayüzler.',
          'Mesaj tepkileri ve tepki bildirimleri, mesaj yıldızlama.',
          'Kamera öncelikli yeni hikâye stüdyosu; Reels kaldırıldı.',
          'X / Reddit tarzı küresel akış, herkes kendi dilinde okur.',
        ],
        fixes: [
          '70 dakikayı aşan aramalarda çeviri metinlerinin birikmesi düzeltildi.',
          'Grup oluştururken alınan "P0001" hatası düzeltildi.',
        ],
        security: [],
      ),
      'en': JuzzioReleaseSection(
        reason: 'To make live translation stable in long calls and to simplify the design.',
        features: [
          'Segment-based live translation; separate layouts for voice and video calls.',
          'Message reactions with notifications, starred messages.',
          'Camera-first story studio; Reels removed.',
          'X / Reddit style global feed, everyone reads in their own language.',
        ],
        fixes: [
          'Translation text piling up in calls longer than 70 minutes was fixed.',
          'The "P0001" error when creating a group was fixed.',
        ],
        security: [],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.4.0',
    versionCode: 40,
    publishedAt: DateTime(2026, 10, 29),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: 'Profil ve içerik paylaşımını zenginleştirmek, güncellemeleri uygulama içinden yapabilmek için getirildi.',
        features: [
          'Instagram tarzı profil, profil kartı ve müzik.',
          'Gönderi / hikâye stüdyosu ve video kırpıcı.',
          'Uygulama içi güncelleme (OTA).',
          'Arkadaş ekleme ve gizli hesaplar için mesaj istekleri.',
        ],
        fixes: [],
        security: [
          'Gizli hesaba arkadaş olmayan kişilerin mesajları "Mesaj istekleri"ne düşer.',
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: 'To enrich profiles and content sharing and to allow updating from inside the app.',
        features: [
          'Instagram-style profile, profile card and music.',
          'Post / story studio and video trimmer.',
          'In-app update (OTA).',
          'Add friend and message requests for private accounts.',
        ],
        fixes: [],
        security: [
          'Messages from non-friends to private accounts go to "Message requests".',
        ],
      ),
    },
  ),
];
