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
    versionName: '1.2.7',
    versionCode: 127,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Uygulamayı ilk kez açanlar Juzzio'yu tanıyamıyordu; doğum günü kutlaması düz ve kısa kalıyordu; mesaj gönderirken uçan metnin altında sarı çizgi çıkıyordu; aşağı çekip yenilemede el ancak ikinci denemede sayfayı tutuyordu. Bu güncelleme hepsini düzeltir ve hava durumu temasına saate göre minik simgeler ekler.",
        features: [
          "🎬 20 saniyelik tanıtım videosu (müzikli): uygulamayı ilk kez açanlara ve yeni hesap açanlara bir kez gösterilir; bu güncellemede herkes bir kez görür. \"Atla\" ile geçilebilir, Yapımcı sayfasındaki \"Uygulama Tanıtımı\" düğmesiyle istediğin zaman yeniden izlenir (Türkçe ve İngilizce)",
          "🎂 Doğum günü kutlaması 3 boyutlu: patlatıcı eller perspektifle döner, konfeti 3B uzayda döner ve ışığa göre parlar, kurdeleler bükülür, parlak küreler ve yıldızlar saçılır; iki patlama, toplam 7 saniye",
          "🌙 Hava durumu temasında saate göre minik vektör simgeler: gece hilal ve yıldız, gündüz güneş ve bulut, akşam turuncu güneş; yağmurda damla, karda kar tanesi, fırtınada şimşek",
          "🤚 Yenileme eli biraz daha büyük ve tombul",
        ],
        fixes: [
          "Mesaj gönderirken uçan metnin altında çıkan sarı çizgi kaldırıldı",
          "Gönderme animasyonu artık gerçek balonun yerine sıçramadan, yumuşakça iner",
          "Aşağı çekip yenilemede el ilk çekişte sayfayı tutar: daha kısa çekiş yeter, el yumruk yaptıktan sonra parmak biraz geri gelse de yenileme başlar, listenin ortasından tepeye varan çekiş de çalışır",
        ],
        security: [
          "Tanıtım videosu uygulamanın içindedir; internet gerekmez, hiçbir veri gönderilmez",
          "Videonun gösterildiği bilgisi yalnız cihazda tutulur",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "First-time users had no introduction to Juzzio; the birthday celebration felt flat and short; a yellow line appeared under the flying text while sending; and the pull-to-refresh hand only grabbed the page on the second try. This update fixes all of that and adds tiny time-of-day icons to the weather theme.",
        features: [
          "🎬 A 20-second intro video with music: shown once to anyone opening the app for the first time and to new accounts; everyone sees it once with this update. Skip it with \"Skip\", or replay it any time from the \"App Introduction\" button on the Creator page (Turkish and English)",
          "🎂 3D birthday celebration: the popper hands turn in perspective, confetti spins in 3D space and catches the light, ribbons twist, glossy orbs and stars burst out; two pops, 7 seconds in total",
          "🌙 Tiny vector icons in the weather theme by time of day: crescent moon and stars at night, sun and clouds by day, an orange sun in the evening; raindrops in rain, snowflakes in snow, lightning in storms",
          "🤚 The refresh hand is a little bigger and chubbier",
        ],
        fixes: [
          "Removed the yellow line under the flying text when sending a message",
          "The send animation now lands smoothly on the real bubble without jumping",
          "Pull-to-refresh grabs the page on the first pull: a shorter pull is enough, the refresh still starts if your finger moves back a little after the fist, and pulls that start mid-list and reach the top work too",
        ],
        security: [
          "The intro video is bundled in the app; no internet needed, no data sent",
          "Whether the video was shown is stored only on the device",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "First-time users had no introduction to Juzzio; the birthday celebration felt flat and short; a yellow line appeared under the flying text while sending; and the pull-to-refresh hand only grabbed the page on the second try. This update fixes all of that and adds tiny time-of-day icons to the weather theme.",
        features: [
          "🎬 A 20-second intro video with music: shown once to anyone opening the app for the first time and to new accounts; everyone sees it once with this update. Skip it with \"Skip\", or replay it any time from the \"App Introduction\" button on the Creator page (Turkish and English)",
          "🎂 3D birthday celebration: the popper hands turn in perspective, confetti spins in 3D space and catches the light, ribbons twist, glossy orbs and stars burst out; two pops, 7 seconds in total",
          "🌙 Tiny vector icons in the weather theme by time of day: crescent moon and stars at night, sun and clouds by day, an orange sun in the evening; raindrops in rain, snowflakes in snow, lightning in storms",
          "🤚 The refresh hand is a little bigger and chubbier",
        ],
        fixes: [
          "Removed the yellow line under the flying text when sending a message",
          "The send animation now lands smoothly on the real bubble without jumping",
          "Pull-to-refresh grabs the page on the first pull: a shorter pull is enough, the refresh still starts if your finger moves back a little after the fist, and pulls that start mid-list and reach the top work too",
        ],
        security: [
          "The intro video is bundled in the app; no internet needed, no data sent",
          "Whether the video was shown is stored only on the device",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.6',
    versionCode: 126,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Juzzio Topluluğu bir sohbet grubu gibi davranıyordu: üyeler birbirinin adını görebiliyor, tepki bırakabiliyor ve kanalda başka yetkili tanımlanabiliyordu. Topluluk artık gerçek bir resmî duyuru KANALI: logosu uygulama logosu, üyeler birbirini göremez, kanala mesaj atılamaz, yalnız güncelleme duyuruları düşer ve tek yetkili @tugkancr. Ayrıca tüm gruplara ve kanallara logo ekleme özelliği geldi.",
        features: [
          "🖼️ Gruplara ve kanallara logo: yönetici/moderatör, grup bilgisindeki fotoğrafa dokunup galeriden ya da kameradan logo koyar veya kaldırır; logo sohbet listesinde ve sohbet başlığında görünür",
          "📣 Juzzio Topluluğu resmî kanal: uygulama logosu, onay rozeti ve \"Resmî kanal · Yalnız güncelleme duyuruları\" başlığı",
          "ℹ️ \"Kanal bilgisi\" sayfası: kanalın kuralları ve tek yetkilisi (@tugkancr) açıkça yazılı",
        ],
        fixes: [
          "Toplulukta üye sayısı ve üye adları artık gösterilmiyor; üye listesi yalnız yetkiliye açık",
          "Toplulukta tepki, \"kim tepki verdi\" listesi, sesli/görüntülü arama, izleme partisi ve elle üye ekleme kaldırıldı",
          "Topluluk duyuruları her zaman @tugkancr adına (Juzzio Official) gönderiliyor",
        ],
        security: [
          "Üyelerin birbirini görmemesi SUNUCUDA zorunlu: katılımcı satırları, üye önbelleği, üye listesi, okundu bilgisi ve canlı \"yazıyor\" yayını yalnız kişinin kendisine ve yetkiliye açık",
          "Toplulukta @tugkancr dışında kimse sahip/moderatör olamaz (veritabanı tetikleyicisi zorlar); rol atama, tepki ve arama sunucuda reddedilir",
          "Grup logosu yalnız kendi yüklediğin dosya olabilir, profil fotoğrafıyla aynı müstehcenlik denetiminden geçer ve yalnız yönetici/moderatör değiştirebilir; dış bağlantı kabul edilmez",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Juzzio Community behaved like a chat group: members could see each other's names, leave reactions, and extra admins could be assigned. The community is now a real official announcement CHANNEL: the app logo is its logo, members cannot see each other, nobody can post, only update announcements appear, and @tugkancr is the only admin. Groups and channels can now also have a logo.",
        features: [
          "🖼️ Logos for groups and channels: an admin/moderator taps the photo in group info to set a logo from the gallery or camera, or remove it; the logo shows in the chat list and chat header",
          "📣 Juzzio Community is an official channel: app logo, verified badge and an \"Official channel · Update announcements only\" header",
          "ℹ️ \"Channel info\" page clearly lists the channel rules and its only admin (@tugkancr)",
        ],
        fixes: [
          "The community no longer shows the member count or member names; the member list is visible only to the admin",
          "Reactions, the \"who reacted\" list, voice/video calls, watch party and manual member adding were removed from the community",
          "Community announcements are always sent as @tugkancr (Juzzio Official)",
        ],
        security: [
          "Members not seeing each other is enforced ON THE SERVER: participant rows, the member cache, the member list, read receipts and the live \"typing\" broadcast are visible only to the person themselves and the admin",
          "Nobody but @tugkancr can be owner/moderator of the community (a database trigger enforces it); role changes, reactions and calls are rejected by the server",
          "A group logo must be a file you uploaded yourself, passes the same content review as profile photos and can only be changed by an admin/moderator; external links are rejected",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "Juzzio Community behaved like a chat group: members could see each other's names, leave reactions, and extra admins could be assigned. The community is now a real official announcement CHANNEL: the app logo is its logo, members cannot see each other, nobody can post, only update announcements appear, and @tugkancr is the only admin. Groups and channels can now also have a logo.",
        features: [
          "🖼️ Logos for groups and channels: an admin/moderator taps the photo in group info to set a logo from the gallery or camera, or remove it; the logo shows in the chat list and chat header",
          "📣 Juzzio Community is an official channel: app logo, verified badge and an \"Official channel · Update announcements only\" header",
          "ℹ️ \"Channel info\" page clearly lists the channel rules and its only admin (@tugkancr)",
        ],
        fixes: [
          "The community no longer shows the member count or member names; the member list is visible only to the admin",
          "Reactions, the \"who reacted\" list, voice/video calls, watch party and manual member adding were removed from the community",
          "Community announcements are always sent as @tugkancr (Juzzio Official)",
        ],
        security: [
          "Members not seeing each other is enforced ON THE SERVER: participant rows, the member cache, the member list, read receipts and the live \"typing\" broadcast are visible only to the person themselves and the admin",
          "Nobody but @tugkancr can be owner/moderator of the community (a database trigger enforces it); role changes, reactions and calls are rejected by the server",
          "A group logo must be a file you uploaded yourself, passes the same content review as profile photos and can only be changed by an admin/moderator; external links are rejected",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.5',
    versionCode: 125,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Yeni sürüm duyurulduktan hemen sonra \"Güncelle\"ye basınca \"Güncellemenin doğrulama bilgisi henüz yayınlanmadı\" uyarısı çıkabiliyordu. İki nedeni vardı: topluluk duyurusu APK derlenmeden önce gidiyordu ve GitHub, imzalı version.json dosyasını ~5 dakika eski hâliyle sunuyordu. Bu güncelleme ikisini de kökünden çözüyor; güvenlik kuralı (doğrulanmamış APK asla kurulmaz) aynen korunuyor.",
        features: [
          "✅ Güncelleme, sürüm kaydındaki imzalı (ML-DSA-65) doğrulama bilgisiyle anında doğrulanır; GitHub önbelleği beklenmez",
          "🔁 Bilgi henüz yoksa uygulama 20 dakikaya kadar kendisi tekrar dener ve hazır olunca \"✅ Güncelleme hazır\" bildirimi gönderir",
        ],
        fixes: [
          "Juzzio Topluluğu sürüm duyurusu artık APK ve imzalı doğrulama bilgisi yayınlandıktan SONRA gönderiliyor",
          "İmzalı version.json her sürüme ayrıca ekleniyor (önbelleğe takılmayan sabit adres)",
        ],
        security: [
          "Doğrulanmamış veya imzası tutmayan APK yine indirilmez/kurulmaz (fail-closed); imza sürüm adı, derleme numarası ve SHA-256'yı birlikte kapsar",
          "Güncelleme kendiliğinden kurulmaz; kullanıcı dokunuşuyla başlar",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Tapping \"Update\" right after a release was announced could show \"The update's verification data is not published yet\". Two causes: the community announcement was sent before the APK was built, and GitHub served the signed version.json from a ~5 minute cache. Both are fixed at the root; the security rule (an unverified APK is never installed) is unchanged.",
        features: [
          "✅ Updates are verified instantly from the signed (ML-DSA-65) data in the release record — no waiting for GitHub's cache",
          "🔁 If the data is not out yet, the app retries for up to 20 minutes and sends a \"✅ Update ready\" notification",
        ],
        fixes: [
          "The Juzzio Community release announcement is now sent AFTER the APK and signed verification data are published",
          "The signed version.json is also attached to every release (a fixed, cache-free address)",
        ],
        security: [
          "An unverified or wrongly signed APK is still never downloaded or installed (fail-closed); the signature covers version name, build number and SHA-256 together",
          "Updates never install by themselves; they start on the user's tap",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "Tapping \"Update\" right after a release was announced could show \"The update's verification data is not published yet\". Two causes: the community announcement was sent before the APK was built, and GitHub served the signed version.json from a ~5 minute cache. Both are fixed at the root; the security rule (an unverified APK is never installed) is unchanged.",
        features: [
          "✅ Updates are verified instantly from the signed (ML-DSA-65) data in the release record — no waiting for GitHub's cache",
          "🔁 If the data is not out yet, the app retries for up to 20 minutes and sends a \"✅ Update ready\" notification",
        ],
        fixes: [
          "The Juzzio Community release announcement is now sent AFTER the APK and signed verification data are published",
          "The signed version.json is also attached to every release (a fixed, cache-free address)",
        ],
        security: [
          "An unverified or wrongly signed APK is still never downloaded or installed (fail-closed); the signature covers version name, build number and SHA-256 together",
          "Updates never install by themselves; they start on the user's tap",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.4',
    versionCode: 124,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "İnternet yokken de Keşfet, sohbetler, hikâyeler, aramalar, bildirimler, profil ve görevler en son yüklenen hâliyle açılıyor; bağlantı gelince her şey kendiliğinden tazeleniyor ve çevrimdışı yapılan profil/ayar değişiklikleri uygulanıyor. Sohbette yukarı kaydırırken yaşanan takılma ve titreme kökünden çözüldü. Bildirimler genişletilebilir sohbet görünümü, Yanıtla ve Okundu olarak işaretle ile geldi. Yönetici panelindeki yasal paket hatası (P0001) ve sürüm alanı sorunu giderildi, kilitli sohbet şifre açığı kapatıldı ve uygulamanın tamamı seçilen dile anında geçiyor.",
        features: [
          "📶 Çevrimdışı öncelikli: Keşfet en son yüklenen hâliyle açılır (\"internet yok\" yerine), önbelleğin bittiği yerde \"İnternet bağlantısı yok\" satırı; önbellekte olmayan görselde dönen yükleme logosu, bağlantı gelince kendiliğinden yüklenir",
          "📞 Aramalar sayfası önbellekte; interneti açıp kapatınca liste boşalmaz, aşağı çekerek yenileme eklendi",
          "🔔 Bildirimler, 👤 profil (gönderiler, kaydedilenler, gönderi/arkadaş/ekleyen sayaçları, arkadaşların profilleri), ✅ görev ve hatırlatıcılar internet varken arka planda önbelleğe alınır, internetsiz görüntülenir",
          "🎵 Profildeki müzik dinlendikten sonra cihazda saklanır, internetsiz çalar; 📖 hikâyeler arka planda indirilir ve internetsiz izlenir",
          "✏️ İnternet yokken yapılan profil ve ayar değişiklikleri kaybolmaz; bağlantı gelince sunucuya yazılır",
          "💬 Genişletilebilir sohbet bildirimi: gönderen fotoğrafı ve adı, grup/kanal adı, aynı sohbetin mesajları alt alta; Yanıtla ve Okundu olarak işaretle (uygulamayı açmadan)",
          "🖼 Sohbette gelen fotoğraf, video ve belgeler galeriye (Juzzio klasörü) kaydedilir ve internetsiz açılır (Ayarlar → Sohbetler'den kapatılabilir; tek görüntülemelik kaydedilmez)",
          "⚡ Fotoğraf, video ve belge gönderirken bekleme yok: anında sohbette görünür, yükleme arka planda sürer",
          "😍 Tepki rozetine dokununca kimin hangi tepkiyi verdiği görünür (herkesin tek tepkisi)",
          "📤 Küresel gönderiler ve hikâyeler birebir sohbetlere ve gruplara iletilir; sohbette \"Gönderiyi aç / Hikâyeyi aç\" düğmesi",
          "🧑‍💼 Yönetici panelinde güncel profil fotoğrafınla \"Hoşgeldin! Engin ÇIRPAN\"; minimum sürüm artık geçmiş paketler listesinden seçiliyor (paket no, kimlik, SHA-256, ML-DSA imza, tarih ile)",
          "🎬 Yapımcı sayfasında cam tasarımlı \"Portfolyo · Yapımcı Tanıtımı\" düğmesi: \"Hello…\" ile başlayan 26 sn'lik tanıtım videosu (internetsiz oynar)",
          "🌍 Uygulama dili değişince açık olan TÜM ekranlar (kayıt/giriş politikaları, yönetici paneli, açılır pencereler dahil) uygulamadan çıkmadan yeni dile geçer",
          "♀♂ Kayıt ekranında kadın (pembe) ve erkek (mavi) simgeleri; şifre gücü ölçer; profilde arkadaş eklerken +1 animasyonu",
        ],
        fixes: [
          "Sohbette geçmiş mesajlara çıkarken takılma/titreme: mesaj balonundaki kaydırarak yanıtla hareketi artık dikey kaydırmayı çalmıyor; eski sayfa yüklenince kullanıcı zorla en alta çekilmiyor",
          "Kilitli sohbete şifresiz girilebiliyordu: PIN oluşturmak kilidi açmıyor, kilit 2 dk sonra ve sohbetten çıkınca yeniden kapanıyor",
          "Yönetici paneli → Acil durum → Yasal paket P0001 hatası: kullanıcı adı sunucuda (büyük/küçük harf duyarsız) çözülüyor, gerekçe ve süresi dolan oturum için açık uyarı",
          "Minimum desteklenen derleme alanına 1.0.2 gibi sürüm yazılamıyordu: paket listesinden seçim",
          "Durum paylaşmayanlar artık durum şeridinde görünmüyor",
          "İnternet yokken sohbette \"Son görülme gizli\" yerine gerçek son görülme",
          "Her paylaşım türü (tek görüntülemelik, kişi kartı, konum, video, görsel, anket, etkinlik, belge) uzun basma menüsünden silinebilir",
          "CI: başarısız testlerin hata ayrıntısı artık GitHub'da açıkça görünüyor; yönetici kaydı cümleleri ve belirsiz içe aktarmalar push'tan önce yerelde denetleniyor",
        ],
        security: [
          "Kilitli sohbet kilidi zaman ve çıkışla yeniden kapanır; PIN hiçbir yere yazılmaz",
          "Bildirim avatarı yalnız herkese açık https adresinden, 3 sn sınırla indirilir; gizli önizleme kipinde ad/fotoğraf gönderilmez",
          "Galeriye yalnız uygulamanın kendi klasöründeki dosyalar kaydedilir; şifreli medya cihazda çözülüp geçici dosya hemen silinir; tek görüntülemelik medya asla kaydedilmez",
          "Yasal paket yine yalnız şifreli süper yönetici oturumuyla, gerekçeyle ve denetim kaydıyla alınır",
          "Uçtan uca şifreleme, RLS ve depolama kuralları değişmedi",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Explore, chats, stories, calls, notifications, profile and tasks now open in their last-loaded state without internet; everything refreshes on its own when the connection returns and offline profile/settings changes are applied. The chat stutter when scrolling up is fixed at the root. Notifications are expandable with Reply and Mark as read. The admin legal bundle error (P0001) and the version field are fixed, the locked-chat PIN bypass is closed and the whole app switches language instantly.",
        features: [
          "📶 Offline-first: Explore opens in its last-loaded state; an \"No internet connection\" row where the cache ends; uncached images show a spinning loader and load by themselves when back online",
          "📞 Calls page cached; toggling internet no longer empties it; pull-to-refresh added",
          "🔔 Notifications, 👤 profile (posts, saved, counters, friends' profiles) and ✅ tasks/reminders are cached in the background and viewable offline",
          "🎵 Profile music plays offline after the first listen; 📖 stories are pre-downloaded and watchable offline",
          "✏️ Profile and settings changes made offline are kept and applied when you reconnect",
          "💬 Expandable chat notifications: sender photo and name, group/channel name, stacked messages; Reply and Mark as read without opening the app",
          "🖼 Received photos, videos and documents are saved to the gallery (Juzzio folder) and open offline (toggle in Settings → Chats; view-once never saved)",
          "⚡ No waiting when sending photos, videos and documents: they appear instantly and upload in the background",
          "😍 Tap a reaction badge to see who reacted with what (one reaction per person)",
          "📤 Forward Explore posts and stories to 1:1 chats and groups; \"Open post / Open story\" button in chat",
          "🧑‍💼 Admin panel greets you with your current photo; minimum version is picked from past packages with build number, ID, SHA-256, ML-DSA fingerprint and date",
          "🎬 Glass \"Portfolio · Creator Showreel\" button on the creator page: a 26 s video starting with \"Hello…\" (plays offline)",
          "🌍 Changing the app language instantly updates EVERY open screen, including sign-up/login policies, admin panel and dialogs",
          "♀♂ Pink/blue gender icons at sign-up; password strength meter; +1 animation when adding a friend",
        ],
        fixes: [
          "Chat stutter when scrolling up: swipe-to-reply no longer steals vertical scrolling; loading older messages no longer yanks you to the bottom",
          "Locked chats could be opened without the PIN: creating a PIN no longer unlocks; the lock closes again after 2 minutes and when leaving the chat",
          "Admin → Emergency → Legal bundle P0001: username is resolved on the server (case-insensitive) with clear errors for missing reason and expired session",
          "Minimum supported build couldn't take versions like 1.0.2: now picked from a package list",
          "People without a status no longer appear in the status strip",
          "Offline chats show the real last seen instead of \"Last seen hidden\"",
          "Every message type (view-once, contact card, location, video, image, poll, event, document) can be deleted from the long-press menu",
          "CI: failing test details are now visible on GitHub; admin log sentences and ambiguous imports are checked locally before push",
        ],
        security: [
          "Locked-chat unlock expires and re-locks on exit; the PIN is never stored",
          "Notification avatars are downloaded only from public https URLs with a 3 s limit; nothing is sent in hidden preview mode",
          "Only files from the app's own folders are saved to the gallery; encrypted media is decrypted on device and the temp file deleted; view-once media is never saved",
          "Legal bundle still requires the super-admin password session, a reason and is audit-logged",
          "End-to-end encryption, RLS and storage rules unchanged",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "Explore, chats, stories, calls, notifications, profile and tasks now open in their last-loaded state without internet; everything refreshes on its own when the connection returns and offline profile/settings changes are applied. The chat stutter when scrolling up is fixed at the root. Notifications are expandable with Reply and Mark as read. The admin legal bundle error (P0001) and the version field are fixed, the locked-chat PIN bypass is closed and the whole app switches language instantly.",
        features: [
          "📶 Offline-first: Explore opens in its last-loaded state; an \"No internet connection\" row where the cache ends; uncached images show a spinning loader and load by themselves when back online",
          "📞 Calls page cached; toggling internet no longer empties it; pull-to-refresh added",
          "🔔 Notifications, 👤 profile (posts, saved, counters, friends' profiles) and ✅ tasks/reminders are cached in the background and viewable offline",
          "🎵 Profile music plays offline after the first listen; 📖 stories are pre-downloaded and watchable offline",
          "✏️ Profile and settings changes made offline are kept and applied when you reconnect",
          "💬 Expandable chat notifications: sender photo and name, group/channel name, stacked messages; Reply and Mark as read without opening the app",
          "🖼 Received photos, videos and documents are saved to the gallery (Juzzio folder) and open offline (toggle in Settings → Chats; view-once never saved)",
          "⚡ No waiting when sending photos, videos and documents: they appear instantly and upload in the background",
          "😍 Tap a reaction badge to see who reacted with what (one reaction per person)",
          "📤 Forward Explore posts and stories to 1:1 chats and groups; \"Open post / Open story\" button in chat",
          "🧑‍💼 Admin panel greets you with your current photo; minimum version is picked from past packages with build number, ID, SHA-256, ML-DSA fingerprint and date",
          "🎬 Glass \"Portfolio · Creator Showreel\" button on the creator page: a 26 s video starting with \"Hello…\" (plays offline)",
          "🌍 Changing the app language instantly updates EVERY open screen, including sign-up/login policies, admin panel and dialogs",
          "♀♂ Pink/blue gender icons at sign-up; password strength meter; +1 animation when adding a friend",
        ],
        fixes: [
          "Chat stutter when scrolling up: swipe-to-reply no longer steals vertical scrolling; loading older messages no longer yanks you to the bottom",
          "Locked chats could be opened without the PIN: creating a PIN no longer unlocks; the lock closes again after 2 minutes and when leaving the chat",
          "Admin → Emergency → Legal bundle P0001: username is resolved on the server (case-insensitive) with clear errors for missing reason and expired session",
          "Minimum supported build couldn't take versions like 1.0.2: now picked from a package list",
          "People without a status no longer appear in the status strip",
          "Offline chats show the real last seen instead of \"Last seen hidden\"",
          "Every message type (view-once, contact card, location, video, image, poll, event, document) can be deleted from the long-press menu",
          "CI: failing test details are now visible on GitHub; admin log sentences and ambiguous imports are checked locally before push",
        ],
        security: [
          "Locked-chat unlock expires and re-locks on exit; the PIN is never stored",
          "Notification avatars are downloaded only from public https URLs with a 3 s limit; nothing is sent in hidden preview mode",
          "Only files from the app's own folders are saved to the gallery; encrypted media is decrypted on device and the temp file deleted; view-once media is never saved",
          "Legal bundle still requires the super-admin password session, a reason and is audit-logged",
          "End-to-end encryption, RLS and storage rules unchanged",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.3',
    versionCode: 123,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Kayıt ve giriş ekranındaki dört ayrı onay kutusu, KVKK Kurulu'nun 2026/347 sayılı İlke Kararı (aydınlatma ile açık rıza ayrı tutulur, aydınlatma metninde onay alınmaz) ve 2024'te değişen KVKK m.9 (sürekli yurt dışı aktarım standart sözleşmeye dayanır) dikkate alınarak iki kutuya indirildi. Kutuya dokununca metin kendiliğinden açılıyor; sona inip \"Okudum ve anladım\"a basınca kayıt ya da giriş tamamlanıyor.",
        features: [
          "✅ Yalnız iki kutu: (1) zorunlu — \"Kullanım Koşulları'nı kabul ediyorum ve 15 yaşından büyük olduğumu beyan ederim. KVKK Aydınlatma Metni'ni okudum ve anladım.\" (2) isteğe bağlı — kampanya ve duyuru e-postaları",
          "📖 Kutuya dokununca Aydınlatma Metni ve Kullanım Koşulları kendiliğinden açılır; \"Sona in\" ile metnin sonuna kayılır, sonda \"Okudum ve anladım\" düğmesi etkinleşir ve basınca kutu işaretlenir",
          "🚀 Kutuyu işaretlemeden \"Kayıt ol\" / \"Giriş yap\"a basılırsa metin otomatik açılır; onaylayınca işlem kaldığı yerden devam eder ve kayıt/giriş tamamlanır",
          "📧 Ticari ileti onayı kendi metniyle ayrı açılır, önceden işaretli gelmez, \"Onay veriyorum\" ile verilir",
        ],
        fixes: [
          "Aydınlatma Metni, Aydınlatma Tebliği'ndeki tüm unsurlarla yeniden yazıldı: veri sorumlusu, işlenen veriler, toplama yöntemi, amaçlar ve hukuki sebepler, aktarılan taraflar, yurt dışı aktarımın dayanağı, saklama, KVKK m.11 hakları, başvuru yöntemi ve Kurul'a şikâyet hakkı",
          "Ayrı \"yurt dışı aktarım açık rızası\" kaldırıldı: hizmetin sürekli işleyişi için yapılan aktarım KVKK m.9 uyarınca uygun güvenceye (standart sözleşme) dayanır ve aydınlatma metninde açıklanır",
          "Kullanım Koşulları'na yaş şartı eklendi (en az 15; 18 yaş altı veli/vasi bilgisi dahilinde); Gizlilik Politikası'nın çocuklar ve haklar bölümleri güncellendi",
          "Metinler değiştiği için mevcut kullanıcılara bir kez yeni metin gösterilir",
        ],
        security: [
          "Sunucu yalnız zorunlu beyanı (koşullar + 15 yaş + aydınlatma okundu) şart koşar; yurt dışı aktarım rızası artık istenmez",
          "Onay kaydı sürümü, zamanı ve uygulama sürümüyle tutulur (IP yazılmaz); istemci onay sütunlarını doğrudan değiştiremez",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "The four separate consent boxes on the sign-up and sign-in screen were reduced to two, in line with the Turkish Data Protection Board's Principle Decision No. 2026/347 (privacy notice and consent kept separate, no consent taken in the notice) and the 2024 amendment of KVKK Art. 9 (continuous transfers abroad rely on standard contracts). Tapping the box opens the text automatically; scroll to the end, tap \"I have read and understood\" and sign-up or sign-in completes.",
        features: [
          "✅ Only two boxes: (1) required — \"I accept the Terms of Use and confirm I am over 15. I have read and understood the Privacy Notice.\" (2) optional — news and campaign e-mails",
          "📖 Tapping the box opens the Privacy Notice and Terms; \"Scroll to end\" takes you to the bottom, where \"I have read and understood\" becomes active and ticks the box",
          "🚀 Tapping \"Sign up\" / \"Sign in\" without the tick opens the text automatically; after confirming, the action continues and completes",
          "📧 Marketing consent opens its own text, is never pre-ticked and is given with \"I agree\"",
        ],
        fixes: [
          "Privacy Notice rewritten with every element required by the Turkish notice regulation: controller, data, collection method, purposes and legal bases, recipients, basis for transfers abroad, retention, rights, how to apply and the right to complain to the Board",
          "Removed the separate \"consent to cross-border transfer\": continuous transfers rely on appropriate safeguards (standard contracts) under KVKK Art. 9 and are explained in the notice",
          "Age requirement added to the Terms (15+, under 18 with a parent's or guardian's knowledge); Privacy Policy children and rights sections updated",
          "Existing users see the updated texts once",
        ],
        security: [
          "The server only requires the mandatory statement (terms + age 15+ + notice read); cross-border consent is no longer required",
          "Consent records keep version, time and app version (no IP); clients cannot write the consent columns directly",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "The four separate consent boxes on the sign-up and sign-in screen were reduced to two, in line with the Turkish Data Protection Board's Principle Decision No. 2026/347 (privacy notice and consent kept separate, no consent taken in the notice) and the 2024 amendment of KVKK Art. 9 (continuous transfers abroad rely on standard contracts). Tapping the box opens the text automatically; scroll to the end, tap \"I have read and understood\" and sign-up or sign-in completes.",
        features: [
          "✅ Only two boxes: (1) required — \"I accept the Terms of Use and confirm I am over 15. I have read and understood the Privacy Notice.\" (2) optional — news and campaign e-mails",
          "📖 Tapping the box opens the Privacy Notice and Terms; \"Scroll to end\" takes you to the bottom, where \"I have read and understood\" becomes active and ticks the box",
          "🚀 Tapping \"Sign up\" / \"Sign in\" without the tick opens the text automatically; after confirming, the action continues and completes",
          "📧 Marketing consent opens its own text, is never pre-ticked and is given with \"I agree\"",
        ],
        fixes: [
          "Privacy Notice rewritten with every element required by the Turkish notice regulation: controller, data, collection method, purposes and legal bases, recipients, basis for transfers abroad, retention, rights, how to apply and the right to complain to the Board",
          "Removed the separate \"consent to cross-border transfer\": continuous transfers rely on appropriate safeguards (standard contracts) under KVKK Art. 9 and are explained in the notice",
          "Age requirement added to the Terms (15+, under 18 with a parent's or guardian's knowledge); Privacy Policy children and rights sections updated",
          "Existing users see the updated texts once",
        ],
        security: [
          "The server only requires the mandatory statement (terms + age 15+ + notice read); cross-border consent is no longer required",
          "Consent records keep version, time and app version (no IP); clients cannot write the consent columns directly",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.2',
    versionCode: 122,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "v1.2.0'da mesaj gönderirken yaşanan yazı tipi değişimi, pembe parlama ve zıplama sorunu, kaynağı düzeltilmek yerine uçuş efekti kapatılarak giderilmişti. Bu güncelleme sorunun üç nedenini de kaynağında düzeltip yazma kutusundan balona uçan mesaj efektini geri getiriyor.",
        features: [
          "🕊 Mesaj gönderme uçuşu geri geldi: yazdığın metin yazma kutusundan kopup damla gibi süzülür ve sohbet balonuna dönüşür",
        ],
        fixes: [
          "Yazı tipi değişimi giderildi: uçan metin artık balonla birebir aynı yazı tipi, boyut, kalınlık ve satır yüksekliğiyle çiziliyor; metin balondaki genişlikte dizildiği için uçarken satır kırılımı da değişmiyor",
          "Pembe parlama giderildi: kapsül vurgu rengine ve pembe gölgeye boyanmıyor; yazma kutusu renginden balonun kendi rengine geçiyor",
          "Zıplama giderildi: kapsül tahmini bir noktaya değil gerçek balonun konumuna (liste kayarken bile kare kare) iner; hedefi aşmayan eğri kullanılır; balon ayrıca ölçeklenip girmez, kapsülün indiği karede yerini alır",
          "Sunucu kaydı uçuş bitmeden gelirse çift balon görünmez",
          "Hareketi azalt ve Performans modunda uçuş yine kapalı; büyük emoji, yanıt alıntısı, kişi kartı ve konum mesajlarında uçuş oynatılmaz",
        ],
        security: [
          "Değişiklik yalnız görsel; şifreleme, mesaj gönderimi ve sunucu kuralları değişmedi",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "In v1.2.0 the font change, pink glow and bounce when sending were 'fixed' by turning the flight effect off instead of fixing the cause. This update fixes all three causes at the source and brings back the message flight from the composer to the bubble.",
        features: [
          "🕊 The send-message flight is back: your text lifts off the composer, glides like a droplet and becomes the chat bubble",
        ],
        fixes: [
          "No more font change: the flying text uses exactly the bubble's font, size, weight and line height, laid out at the bubble's width so line breaks don't change mid-flight",
          "No more pink glow: the capsule is no longer painted with the accent colour and a pink shadow; it blends from the composer colour into the bubble's own colour",
          "No more bounce: the capsule lands on the real bubble's position (tracked every frame, even while the list scrolls) with a non-overshooting curve; the bubble no longer scales in separately, it takes over on the exact landing frame",
          "No double bubble if the server confirms before the flight ends",
          "Still off with Reduce motion and Performance mode; no flight for big emoji, replies, contact cards and locations",
        ],
        security: [
          "Visual-only change; encryption, sending and server rules are unchanged",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "In v1.2.0 the font change, pink glow and bounce when sending were 'fixed' by turning the flight effect off instead of fixing the cause. This update fixes all three causes at the source and brings back the message flight from the composer to the bubble.",
        features: [
          "🕊 The send-message flight is back: your text lifts off the composer, glides like a droplet and becomes the chat bubble",
        ],
        fixes: [
          "No more font change: the flying text uses exactly the bubble's font, size, weight and line height, laid out at the bubble's width so line breaks don't change mid-flight",
          "No more pink glow: the capsule is no longer painted with the accent colour and a pink shadow; it blends from the composer colour into the bubble's own colour",
          "No more bounce: the capsule lands on the real bubble's position (tracked every frame, even while the list scrolls) with a non-overshooting curve; the bubble no longer scales in separately, it takes over on the exact landing frame",
          "No double bubble if the server confirms before the flight ends",
          "Still off with Reduce motion and Performance mode; no flight for big emoji, replies, contact cards and locations",
        ],
        security: [
          "Visual-only change; encryption, sending and server rules are unchanged",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.1',
    versionCode: 121,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Bu güncelleme kayıt ve girişte açık ve anlaşılır onay formunu (KVKK aydınlatma, açık rıza, 15 yaş, yurt dışı aktarım, isteğe bağlı kampanya e-postası), sunucu tarafı istek sınırlarını ve girdi doğrulamasını, bulunduğun yerin havasına göre değişen temayı ve görseldeki gibi tombul 3D bebek eliyle yeniden yazılan yukarıdan yenilemeyi getiriyor. v1.0.0 video kaydında görülen arama geçmişi okları ve profil düğmesi kısalmaları da düzeltildi.",
        features: [
          "✅ Kayıt / giriş onay formu: özel animasyonlu tik kutuları; KVKK aydınlatma metnini okudum, Kullanım Koşulları, 15 yaşından büyüğüm ve yurt dışı aktarım (Supabase, LiveKit, Firebase, Open-Meteo) onayları zorunlu — işaretlenmeden kayıt olunamaz ve giriş yapılamaz",
          "📧 İsteğe bağlı \"Kampanya ve yenilik e-postaları\" (ticari ileti onayı); istediğin an Ayarlar → Bildirimler'den geri alınır",
          "🔐 Formda uçtan uca şifreleme (E2EE) ve güvenlik önlemleri sade dille anlatılıyor; \"Oku\" bağlantılarıyla tam metinler açılıyor",
          "🔄 Onay metni güncellenirse mevcut kullanıcılara bir kez yeniden onay penceresi gösterilir (kabul edilmezse oturum kapanır)",
          "🌦 Hava durumu teması (varsayılan açık): bulunduğun yerin havasına göre güneş/ay hâlesi, bulut, sis, çisenti, yağmur, kar ve şimşek efektleri. Görünüm → Hava durumu teması'ndan kapatılabilir",
          "👶 Yukarıdan yenileme baştan yazıldı: görseldeki gibi 4 parmak + başparmaklı tombul 3D kil bebek eli, Dynamic Island ile başlık arasındaki boşlukta kalır (en fazla 80 dp), eşikte yumuşak 3D kumaş tutma gölgesi, bırakınca 200 ms elastik geri dönüş, ardından boşlukta sade yükleme halkası",
        ],
        fixes: [
          "Yenileme yalnız bir kez tetiklenir (çift istek kilidi); eşik altında bırakınca temiz iptal; tüm denetleyiciler kapatılıyor",
          "\"Hareketi azalt\" açıkken el animasyonu atlanır, yalnız standart yükleme halkası görünür",
          "Eski 2D yelpaze / ışın çizgileri ve el üzerindeki beyaz tırnak daireleri kaldırıldı; el başlığa, arama çubuğuna ve profil fotoğraflarına artık değmiyor",
          "Arama geçmişinde çift ok giderildi: tek simge, gelen ↙ / giden ↗ yönüyle",
          "Profilinde \"Profili düzenle\" / \"Profili paylaş\" düğmeleri kısalmıyor: \"Düzenle\" ve \"Paylaş\"",
          "Profil fotoğrafı yakınlaştırma seçeneği daha anlaşılır: \"Başkalarının yakınlaştırmasını kapat/aç\"",
        ],
        security: [
          "Onaylar sunucuda sürümüyle birlikte kayıt altına alınır (yalnız kendi kaydını görürsün; istemci onay sütunlarını doğrudan değiştiremez)",
          "Sunucu tarafı istek sınırları: mesaj 40/dk ve 3000/gün, yorum 20/dk, gönderi 30/saat, hikâye 60/gün, arkadaşlık isteği 40/saat, şikâyet 20/saat, grup oluşturma 20/saat, onay kaydı 20/saat",
          "Girdi doğrulama: kontrol ve görünmez/yön değiştiren karakterler temizlenir, uzunluk sınırları sunucuda zorunlu; javascript:, data:, file: gibi tehlikeli bağlantılar reddedilir; kullanıcı arama terimi yalnız harf/rakam/_/- ile sınırlanır",
          "Hava durumu için konum ~10 km'ye yuvarlanır, yalnız Open-Meteo'ya gönderilir; Juzzio sunucusuna gitmez ve saklanmaz. Konum izni yalnız bir kez istenir",
          "Uçtan uca şifreleme davranışı değişmedi (fail-closed); RLS gevşetilmedi, depolama alanları herkese açılmadı",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "This update adds a clear consent form at sign-up and login (privacy notice, explicit consent, age 15+, cross-border transfer, optional marketing e-mails), server-side rate limits and input validation, a theme that follows your local weather and a pull-to-refresh rewritten with a chubby 3D baby hand like the reference image. The call-history arrows and the truncated profile buttons seen in the v1.0.0 recording are fixed too.",
        features: [
          "✅ Sign-up / login consent form with custom animated ticks; privacy notice, Terms, \"I am over 15\" and cross-border transfer (Supabase, LiveKit, Firebase, Open-Meteo) are required — you can't register or log in without them",
          "📧 Optional \"Campaign and news e-mails\" (marketing consent); withdraw any time in Settings → Notifications",
          "🔐 The form explains end-to-end encryption (E2EE) and the security measures in plain words; \"Read\" links open the full texts",
          "🔄 If the consent text changes, existing users see a one-time re-consent dialog (declining signs you out)",
          "🌦 Weather theme (on by default): sun/moon glow, clouds, fog, drizzle, rain, snow and lightning effects from your local weather. Turn it off in Appearance → Weather theme",
          "👶 Pull-to-refresh rewritten: a chubby 3D clay baby hand with 4 fingers and a thumb, staying in the gap between the Dynamic Island and the header (max 80 dp), a soft 3D cloth-pinch shade at the threshold, a 200 ms elastic snap back on release, then a minimal spinner in the gap",
        ],
        fixes: [
          "Refresh fires exactly once (duplicate lock); releasing below the threshold cancels cleanly; all controllers are disposed",
          "With Reduce motion on, the hand animation is skipped and only the standard spinner is shown",
          "Removed the old 2D fan / radial lines and the white nail circles; the hand no longer touches the header, search bar or avatars",
          "Call history: no more double arrows — one icon with the incoming ↙ / outgoing ↗ direction",
          "Your profile's \"Edit profile\" / \"Share profile\" buttons are no longer truncated: \"Edit\" and \"Share\"",
          "Clearer profile photo zoom option: \"Turn off/on zoom for others\"",
        ],
        security: [
          "Consents are recorded on the server with their version (you only see your own; clients can't write the consent columns directly)",
          "Server-side rate limits: messages 40/min and 3000/day, comments 20/min, posts 30/hour, stories 60/day, friend requests 40/hour, reports 20/hour, group creation 20/hour, consent records 20/hour",
          "Input validation: control and invisible/bidi characters are stripped, length limits enforced on the server; dangerous links such as javascript:, data:, file: are rejected; user search terms are limited to letters/digits/_/-",
          "For the weather theme your location is rounded to ~10 km and sent only to Open-Meteo — never to Juzzio's server and never stored. Location permission is asked only once",
          "End-to-end encryption behaviour unchanged (fail-closed); RLS not weakened; storage buckets not made public",
        ],
      ),
      'de': JuzzioReleaseSection(
        reason: "This update adds a clear consent form at sign-up and login (privacy notice, explicit consent, age 15+, cross-border transfer, optional marketing e-mails), server-side rate limits and input validation, a theme that follows your local weather and a pull-to-refresh rewritten with a chubby 3D baby hand like the reference image. The call-history arrows and the truncated profile buttons seen in the v1.0.0 recording are fixed too.",
        features: [
          "✅ Sign-up / login consent form with custom animated ticks; privacy notice, Terms, \"I am over 15\" and cross-border transfer (Supabase, LiveKit, Firebase, Open-Meteo) are required — you can't register or log in without them",
          "📧 Optional \"Campaign and news e-mails\" (marketing consent); withdraw any time in Settings → Notifications",
          "🔐 The form explains end-to-end encryption (E2EE) and the security measures in plain words; \"Read\" links open the full texts",
          "🔄 If the consent text changes, existing users see a one-time re-consent dialog (declining signs you out)",
          "🌦 Weather theme (on by default): sun/moon glow, clouds, fog, drizzle, rain, snow and lightning effects from your local weather. Turn it off in Appearance → Weather theme",
          "👶 Pull-to-refresh rewritten: a chubby 3D clay baby hand with 4 fingers and a thumb, staying in the gap between the Dynamic Island and the header (max 80 dp), a soft 3D cloth-pinch shade at the threshold, a 200 ms elastic snap back on release, then a minimal spinner in the gap",
        ],
        fixes: [
          "Refresh fires exactly once (duplicate lock); releasing below the threshold cancels cleanly; all controllers are disposed",
          "With Reduce motion on, the hand animation is skipped and only the standard spinner is shown",
          "Removed the old 2D fan / radial lines and the white nail circles; the hand no longer touches the header, search bar or avatars",
          "Call history: no more double arrows — one icon with the incoming ↙ / outgoing ↗ direction",
          "Your profile's \"Edit profile\" / \"Share profile\" buttons are no longer truncated: \"Edit\" and \"Share\"",
          "Clearer profile photo zoom option: \"Turn off/on zoom for others\"",
        ],
        security: [
          "Consents are recorded on the server with their version (you only see your own; clients can't write the consent columns directly)",
          "Server-side rate limits: messages 40/min and 3000/day, comments 20/min, posts 30/hour, stories 60/day, friend requests 40/hour, reports 20/hour, group creation 20/hour, consent records 20/hour",
          "Input validation: control and invisible/bidi characters are stripped, length limits enforced on the server; dangerous links such as javascript:, data:, file: are rejected; user search terms are limited to letters/digits/_/-",
          "For the weather theme your location is rounded to ~10 km and sent only to Open-Meteo — never to Juzzio's server and never stored. Location permission is asked only once",
          "End-to-end encryption behaviour unchanged (fail-closed); RLS not weakened; storage buckets not made public",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.2.0',
    versionCode: 120,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Bu güncelleme bildirdiğin 18 eksiğin tamamını kapatıyor: doğum günü kutlaması, gerçek kanallar ve herkesin otomatik üye olduğu Juzzio Topluluğu, tek sayfada toplanan Görünüm ayarları, düzeltilen mesaj ve arama tepkileri, yenilenen mesaj kartları, sohbet içi arama ve çalışan kilitli sohbetler.",
        features: [
          "🎂 Doğum günü kutlaması: \"Happy Birthday\", \"Doğum günün kutlu olsun\", \"İyi ki doğdun\" (ve benzerleri) geçen mesajda soldan ve sağdan konfeti patlatıcılı iki el girip patlatır, 🌸🎂😍⚡🥳💖❤️ yumuşakça yükselip kaybolur, balonun çevresinde elektrik dalgası dolaşır — toplam 4 saniye",
          "📣 Gerçek kanallar: \"Yeni kanal\" artık grup formunu değil kendi akışını açar (ad + açıklama + canlı önizleme → kişi seçimi). Kanalda yalnız sahip ve yöneticiler paylaşır; üyeler okur, tepki verir (sunucuda da zorunlu)",
          "🌍 Juzzio Topluluğu: uygulama dilinde adlandırılan resmî kanal (TR \"Juzzio Topluluğu\", EN \"Juzzio Community\"). Tüm mevcut kullanıcılar ve her yeni kayıt otomatik üye; paylaşımlar \"Juzzio Official\" adı, mavi tik ve uygulama logosuyla görünür",
          "🚀 Her güncelleme yayınlandığında sürüm notları Juzzio Topluluğu'nda otomatik paylaşılır (yönetici emeği yok, aynı sürüm iki kez paylaşılmaz)",
          "🛠 Yönetici paneline \"Juzzio Community\" sayfası: metin, bağlantı, görsel, video, müzik veya herhangi bir dosya seçip \"Paylaş\" ile tüm kullanıcılara duyuru",
          "🎨 Görünüm tek sayfada: Gece/Gündüz (Gündüz · Gece · Sistem · Zamanlı), uygulama teması, cam teması, Tema Stüdyosu, sohbet teması ve parlaklığı, canlı önizlemeli yazı boyutu, performans modu",
          "🕰 Zamanlı gece/gündüz modu: gece modunun başlayıp biteceği saati seç, uygulama kendisi geçer",
          "🗂 Ayarlar yeniden düzenlendi: Hesap ve güvenlik · Sohbetler ve bildirimler · Görünüm ve dil · Depolama ve pil · Destek",
          "🔍 Mesaj araması yenilendi: cam arama kutusu, simgeli filtreler, tarih başlıkları, eşleşen kelime vurgusu; sohbet içinden açılınca (⋮ → Sohbette ara) yalnız o sohbette arar, sonuca dokununca mesaja kaydırıp vurgular",
          "🔒 Kilitli sohbetler tamamlandı: PIN yoksa oluşturur, varsa açar; kilitli sohbetler listelenir, buradan sohbet kilitlenir/kilidi kaldırılır",
          "🪪 Kişi kartı: dokunulabilir, paylaşılan kişinin profil fotoğrafı, adı, mavi tiki ve \"Profili Görüntüle\" düğmesi",
          "💣 Tek görüntülemelik medya: bulanık önizleme, cam \"Tek görüntülemelik\" etiketi ve cam bomba simgesi; açıldıktan sonra modern \"Açıldı\" durumu, tekrar açılamaz",
          "📸 Hikâye yanıtları yeni tasarım: tam küçük görsel, köşede büyük tepki emojisi, dokununca hikâye açılır (eski çerçeve ve \"İzle\" düğmesi kaldırıldı)",
          "💬 Hikâye bildirimleri: \"Fikret39 hikâyene 🌸 tepkisi verdi\" ve \"Fikret39 hikâyene \"…\" yorumunu ekledi\" (Instagram gibi)",
          "📅 Paylaşılan vardiya planı artık dokunulabilir kart: gün gün hangi saatler çalışılacağı ve hangi günlerin izin olduğu ayrıntılı görüntüleyicide",
          "🗓 Vardiya planım sayfası baştan tasarlandı: ay başlık kartı ve özet (çalışma günü, izin, saat), sıradaki vardiya kartı, degrade takvim hücreleri, renk etiketleri, kart görünümlü ekip takvimi",
          "⏰ Mesajı zamanla: mesaj bu sayfada yazılır; ayrı tarih ve saat seçici, hızlı seçenekler (1 saat, 3 saat, yarın 09:00)",
          "✨ \"Ne paylaşmak istersin?\": güçlü bulanıklık, okunur metin, yeni Gönderi ve Hikâye/Durum simgeleri",
          "🫧 Canlı durum kapsülü (\"Ses kaydediliyor\", \"Fotoğraf gönderiliyor\") artık başlığın altında, şeffaf cam görünümünde — profil fotoğrafını ve adı örtmüyor",
        ],
        fixes: [
          "Mesaj gönderirken yazı tipinin değişmesi, pembe parıltı ve zıplama tamamen kaldırıldı; balon beklemeden ve sakin şekilde belirir",
          "Mesaj tepkileri: emoji küçülüp bozulmuyor, rozet büyük, renkli ve kırpılmadan görünüyor; ❤️‍🔥 artık düz kalp olarak çizilmiyor",
          "Arama tepkileri: basılı tutup seçtiğin emoji (⚡, 🎉 …) artık her dokunuşta gönderilir (önceden bir kez gidip ❤️'ye dönüyordu); kalplerin altındaki sarı çizgiler giderildi",
          "Arama ekranı: mobil veri uyarısı modern cam kart oldu (sarı alt çizgi ve bozuk yazı tipi yok); pil tasarrufu siyah ekranı canlı altyazı ve çeviriyi gösteriyor",
          "Bildirimlerde yenileme eli başlık yazısının üstünden değil listenin üst kenarından tutuyor",
          "Görünüm'deki gece/gündüz uyuşmazlığı ve birbiriyle çakışan iki kontrol giderildi (tek seçici; özel tema etkinken seçim artık uygulanıyor)",
          "\"Yazı boyutu\"na dokununca sohbet ayarlarına atma sorunu giderildi",
          "Performans modu gerçekten çalışıyor: bulanıklık, konfeti/parçacık ve kutlama efektleri ile yaylı girişler kapanıyor",
        ],
        security: [
          "Kanallarda paylaşım kuralı sunucuda zorunlu (RLS sıkılaştırıldı); topluluk kanalı istemciden oluşturulamaz/değiştirilemez, adı rezervedir",
          "Topluluk paylaşımı ve sürüm duyurusu yalnız yönetici/sunucu tarafından yapılabilir",
          "Şifreli sohbette hikâye yorumunun metni sunucuya ve bildirime yazılmaz (yalnız tepki emojisi, mesaj tepkileri gibi)",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "This update closes all 18 issues you reported: a birthday celebration, real channels and a Juzzio Community everyone joins automatically, all Appearance settings on one page, fixed message and call reactions, redesigned message cards, in-chat search and working locked chats.",
        features: [
          "🎂 Birthday celebration: when a message contains \"Happy Birthday\", \"Doğum günün kutlu olsun\" (and similar), two hands with party poppers come in from the left and right and pop, 🌸🎂😍⚡🥳💖❤️ rise and fade smoothly and an electric wave runs around the bubble — 4 seconds in total",
          "📣 Real channels: \"New channel\" now opens its own flow (name + description + live preview → pick people). Only owners and admins post; members read and react (enforced on the server)",
          "🌍 Juzzio Community: an official channel named in your app language. Every existing user and every new sign-up joins automatically; posts appear as \"Juzzio Official\" with a blue tick and the app logo",
          "🚀 Release notes are posted to Juzzio Community automatically on every update (no admin effort, never twice for the same version)",
          "🛠 New \"Juzzio Community\" admin page: text, link, image, video, music or any file → \"Share\" to every user",
          "🎨 Appearance on one page: Light/Dark (Light · Dark · System · Scheduled), app theme, glass theme, Theme Studio, chat theme and brightness, font size with live preview, performance mode",
          "🕰 Scheduled light/dark mode: choose when dark mode starts and ends",
          "🗂 Settings reorganised: Account & security · Chats & notifications · Appearance & language · Storage & battery · Support",
          "🔍 New message search: glass search field, filter chips with icons, date headers, highlighted matches; opened from a chat (⋮ → Search in chat) it searches only that chat and jumps to the message",
          "🔒 Locked chats completed: creates a PIN if needed, lists locked chats, lock/unlock chats right there",
          "🪪 Contact card: tappable, with the shared person's photo, name, blue tick and \"View profile\"",
          "💣 View-once media: blurred preview, glass \"View once\" label and glass bomb icon; modern \"Opened\" state afterwards, can't be reopened",
          "📸 Story replies redesigned: full thumbnail, big reaction emoji in the corner, tap opens the story",
          "💬 Story notifications: \"Fikret39 reacted 🌸 to your story\" and \"Fikret39 commented on your story: …\"",
          "📅 Shared shift plans are tappable cards with a day-by-day viewer (hours and days off)",
          "🗓 My shifts page redesigned: month header with summary, next-shift card, gradient calendar cells, colour chips, card-style team calendar",
          "⏰ Schedule message: write the message right in the sheet; separate date and time pickers and quick presets",
          "✨ \"What would you like to share?\": stronger blur, readable text, new Post and Story/Status icons",
          "🫧 The live activity pill now sits below the header as transparent glass and no longer covers the profile photo and name",
        ],
        fixes: [
          "Removed the font change, pink glow and bounce when sending; the bubble appears instantly and calmly",
          "Message reactions no longer shrink or break; the badge is larger, colourful and never clipped; ❤️‍🔥 is no longer drawn as a plain heart",
          "Call reactions: the emoji you pick by long-press is sent on every tap (it used to revert to ❤️); yellow lines under the hearts are gone",
          "Call screen: modern glass data-saver card; the battery-saver black screen now shows live captions and translation",
          "On Notifications the refresh hand grabs the top edge of the list, not the header",
          "Fixed the light/dark mismatch and the two conflicting controls in Appearance",
          "Tapping \"Font size\" no longer jumps to chat settings",
          "Performance mode really works: blur, confetti/particle and celebration effects and springy entrances are turned off",
        ],
        security: [
          "Channel posting rule enforced on the server (stricter RLS); the community channel can't be created or changed by clients and its name is reserved",
          "Community posts and release announcements can only be made by the admin/server",
          "In encrypted chats the text of a story comment is never written to the server or notification (only the reaction emoji, like message reactions)",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.1.1',
    versionCode: 111,
    publishedAt: DateTime(2026, 11, 10),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Aşağı çekip yenilemedeki tombul el baştan vektörle çizildi; bildirimler sayfasında yenilerken listenin kaybolması giderildi ve profil sayfası çok daha hızlı açılıyor.",
        features: [
          "✋ Yenileme eli yeniden çizildi: tombul, temiz çizgili el temanın renginde bir kollukla çentikten çıkar, sallanır, yumruk yapıp sayfayı yukarı çeker — her ekranda keskin",
          "🧺 Kumaş artık temanın renginden açık bir yüzey; yumuşak kıvrımlarla toplanıp kaybolur",
        ],
        fixes: [
          "Yenileme elinin poz geçişlerinde \"ayak gibi\" görünmesi ve hayalet görüntü giderildi",
          "Koyu temada kumaşın içeriğin üstünde siyah leke gibi görünmesi giderildi",
          "Bildirimler: yenilerken veya filtre değiştirirken liste boş kartlara dönüp yanıp sönmüyor; eski istek yeni listeyi ezmiyor; boş/hata durumunda da aşağı çekilebiliyor; kaydırarak silme kimlikle yapılıyor",
          "Profil: sayaçlar, gönderiler ve ilişki bilgisi geldiği an görünür, sekmeye dönüşte anında açılır; arka plandaki istekler sırayla değil paralel çalışır",
          "Arkadaşlar, dosyalar, kaydedilenler, güvenlik ve gönderi yorumları sayfalarında yenileme sırasında içerik kaybolmuyor",
        ],
        security: [],
      ),
      'en': JuzzioReleaseSection(
        reason: "The chubby pull-to-refresh hand was redrawn as vector art; the notifications list no longer disappears while refreshing, and the profile page opens much faster.",
        features: [
          "✋ Redrawn refresh hand: a chubby, clean-lined hand comes out of the notch with a sleeve in your theme colour, swings, makes a fist and pulls the page up — crisp on every screen",
          "🧺 The cloth is now a light surface in your theme colour that gathers up with soft folds",
        ],
        fixes: [
          "Fixed the refresh hand looking like a foot and ghosting between poses",
          "Fixed the cloth looking like a black smear over the content in dark themes",
          "Notifications: refreshing or switching filters no longer flashes empty placeholder cards; stale requests can't overwrite the new list; empty/error states can be pulled to refresh; swipe-to-delete removes by id",
          "Profile: counts, posts and relationship appear as soon as each arrives and reopen instantly; background requests run in parallel instead of one after another",
          "Friends, files, saved messages, security and post comments no longer lose their content while refreshing",
        ],
        security: [],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.1.0',
    versionCode: 110,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Juzzio artık her dokunuşta canlı: sayfa geçişleri, anahtarlar, yükleyiciler, mesaj gönderme, beğeni ve ikon dönüşümleri baştan tasarlandı; yeni logo geldi. Aramalarda kullanıcının söylemediği \"Tamam aşkım\" gibi hayalet altyazılar giderildi ve alıntıya dokununca alıntılanan mesaja gidiliyor.",
        features: [
          "🐣 Yeni logo: civciv + cam sohbet balonu kanat + yörünge halkası; Android uyarlanabilir ve tematik (tek renk) ikon, yeni açılış ekranı",
          "🚀 Açılış/yükleme ekranı: logonun etrafında dönen ışıklı yörünge, kıvılcımlı ilerleme çubuğu ve \"Bağlanıyor → Şifreleme doğrulanıyor → Mesajlar eşitleniyor\"",
          "💬 Mesaj gönderme: yazma kutusundaki metin damla gibi koparak balona dönüşür ve yukarı kayar; gönder düğmesindeki kağıt uçak swoosh ile uçar",
          "✓✓ Okundu bilgisi çizilerek değişir: saat → ✓ gönderildi → ✓✓ iletildi → parlayan ✓✓ okundu",
          "😀 Yalnız emoji gönderilince büyük ve zıplayarak gelir; \"İyi ki doğdun\", \"Tebrikler\", \"Happy Birthday\" gibi mesajlarda konfeti patlar",
          "❤️ Tepkiler: kalp çizilerek dolar, etrafında halka ve parçacık patlaması; yeni tepki rozeti yaylanarak belirir; fotoğrafa çift dokununca ortada kalp",
          "⭐ Yıldızlı mesaja eklerken yıldız dönerek ışıltı saçar",
          "🔘 Yeni anahtarlar: genel ayarlarda akışkan (gooey) neon anahtar; gizlilik, şifreleme, okundu bilgisi ve izinlerde ✕→✓ anahtar; koyu temada güneşin aya dönüştüğü Gece/Gündüz anahtarı",
          "⏻ Canlı çeviri ve Rahatsız Etme tek dokunuşla açılan neon Power düğmesiyle",
          "🧭 Geçişler: alt sayfalar arkayı bulanıklaştırıp yaylanarak açılır; fotoğraf ve videolar dokunulan yerden yakınlaşarak tam ekrana büyür; profil fotoğrafı profil sayfasına kesintisiz uçar",
          "➕ İkon dönüşümleri: ekle (+) menü açılınca ×'e döner, ⋮ menüsü ×'e, gelen kutusu menüsü halka içinde ×'e, geri düğmesi menüden oka dönüşür",
          "🏝️ Dynamic Island tarzı canlı durum kapsülü: süren arama, ses kaydı ve dosya yüklemeleri üstte süre/ilerlemeyle görünür",
          "🫧 Kopyalandı, mikrofon açık/kapalı, canlı çeviri gibi durumlar ekranı kaplamayan cam bildirimle (HUD) gösterilir; mesaj silme alttan açılan eylem sayfasıyla onaylanır",
          "🎉 Aramalarda anlık tepki: kalbe dokun (basılı tutarak başka tepki seç), herkesin ekranında alttan süzülür",
          "⌛ Karşı taraf yazarken sohbetin dibinde üç ışıklı nokta zıplar; ses ve dosya yüklemelerinde kıvılcımlı çubuk, bağlantıda yörünge halkası",
          "📳 Gönderimde, anahtarlarda, kaydırma eşiğinde ve uzun basmada titreşim geri bildirimi",
        ],
        fixes: [
          "Sesli/görüntülü aramada kimse konuşmazken altyazıda çıkan \"Tamam aşkım\" gibi uydurma metinler giderildi: altyazı mikrofonu artık yankı engelleme ve gürültü bastırmayla okunur, otomatik kazanç kapalı; gerçekten konuşmadıkça tanıyıcıya ses değil sessizlik gider",
          "Karşı taraf konuşurken onun sesinin hoparlörden mikrofona girip \"Sen: …\" satırı olarak yazılması engellendi (yankı süzgeci); düşük güvenli ve hayalet kalıp sonuçlar gösterilmez, ekranda kalmış ara satır geri çekilir",
          "Alıntıya (yanıtlanan mesaja) dokununca sohbet alıntılanan mesaja kayar ve onu kısa süre parlatır; eski mesajsa geçmiş otomatik yüklenir",
          "Görsel alıntılarında resim yazısı yerine küçük resim gösterilir; video, sesli mesaj ve belge alıntıları türüyle birlikte görünür",
        ],
        security: [
          "Canlı altyazı yalnız gerçekten konuştuğunuz anların sesini konuşma tanıma servisine gönderir; sessizlik ve oda sesi gönderilmez",
          "Arama tepkileri beyaz listeli emojilerle sınırlıdır (rastgele metin yayınlanamaz)",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Juzzio now feels alive at every touch: page transitions, switches, loaders, message sending, likes and icon morphs were redesigned, and there is a new logo. Phantom captions like \"Okay my love\" that users never said are gone from calls, and tapping a quote jumps to the quoted message.",
        features: [
          "🐣 New logo: a chick with a glass chat-bubble wing and an orbit ring; Android adaptive and themed (monochrome) icon, new launch screen",
          "🚀 Launch/loading screen: a glowing orbit around the logo, a sparkler progress bar and \"Connecting → Verifying encryption → Syncing messages\"",
          "💬 Sending: the text in the composer breaks off like a droplet, turns into a bubble and slides up; the paper plane on the send button flies off with a swoosh",
          "✓✓ Read receipts draw themselves: clock → ✓ sent → ✓✓ delivered → glowing ✓✓ read",
          "😀 Emoji-only messages arrive big with a pop; messages like \"Happy Birthday\", \"Congrats\" or \"İyi ki doğdun\" burst into confetti",
          "❤️ Reactions: the heart draws itself and fills with a ring and particle burst; new reaction badges spring in; double-tap a photo for a heart",
          "⭐ Starring a message spins the star with sparkles",
          "🔘 New switches: a gooey neon switch for general settings; ✕→✓ switches for privacy, encryption, read receipts and permissions; a Day/Night switch where the sun turns into the moon",
          "⏻ Live translation and Do Not Disturb get a one-tap neon Power button",
          "🧭 Transitions: bottom sheets blur the background and spring open; photos and videos zoom to full screen from where you tapped; the profile photo flies seamlessly into the profile page",
          "➕ Icon morphs: attach (+) turns into × while the menu is open, ⋮ turns into ×, the inbox menu becomes × inside a ring, the back button morphs from menu to arrow",
          "🏝️ Dynamic Island–style live activity: ongoing calls, voice recording and uploads appear at the top with a timer/progress",
          "🫧 Copied, microphone on/off and live translation states show as a glass HUD that doesn't cover the screen; deleting a message is confirmed with an action sheet",
          "🎉 Live reactions in calls: tap the heart (hold to pick another reaction) and it floats up on everyone's screen",
          "⌛ Three glowing dots bounce at the bottom of the chat while the other person types; sparkler bars for uploads and an orbit ring while connecting",
          "📳 Haptic feedback on send, switches, swipe thresholds and long presses",
        ],
        fixes: [
          "Fixed made-up captions such as \"Okay my love\" appearing in voice/video calls while nobody was speaking: the caption microphone now uses echo cancellation and noise suppression with auto-gain off, and the recognizer only receives silence unless you are actually speaking",
          "The other person's voice leaking from the speaker into your microphone is no longer written as a \"You: …\" line (echo filter); low-confidence and phantom-phrase results are dropped and a stale interim line is retracted",
          "Tapping a quote (the replied message) scrolls the chat to the quoted message and highlights it briefly; older history loads automatically",
          "Image quotes show a thumbnail instead of caption text; video, voice and document quotes show their type",
        ],
        security: [
          "Live captions only send audio to the speech recognizer while you are actually speaking; silence and room sound are not sent",
          "Call reactions are limited to an allow-list of emojis (no arbitrary text can be broadcast)",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '1.0.0',
    versionCode: 100,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Juzzio, Figma'da tasarlanan \"Juzzio Space\" arayüzüne taşındı: derin tema gradyanları, buzlu cam kartlar ve her temada parlayan vurgu rengi. Aynı güncellemede mesajlar beklemeden gönderiliyor, konum/bağlantı/anket deneyimi yenilendi, vardiyalar tarih aralığıyla planlanıyor ve yönetici kayıtları okunur hâle geldi.",
        features: [
          "🎨 Juzzio Space tasarımı: \"Senin alanın · Juzzio.\" başlığı, ⌘K kısayollu arama, hikâye halkaları, Gelen kutusu · Mesajlar, sayaçlı filtre hapları, cam sohbet kartları ve yüzen cam alt menü",
          "🌈 16 temanın tamamı aynı tasarım dilini kullanır; vurgu rengi, zemin derinliği ve cam opaklığı seçili temadan gelir (yeni kullanıcılarda varsayılan Zümrüt)",
          "⚡ Mesajlar anında gönderilir: balon hemen görünür, çeviri arka planda yapılır ve hazır olunca mesajın altında belirir (uçtan uca şifreli sohbetlerde çeviri de şifreli eklenir)",
          "📍 Paylaşılan konum harita önizlemeli kart olarak görünür; Android'de Google Haritalar, iOS'ta Apple Haritalar ya da Google Maps ile açılır",
          "🔗 Mesajlar, biyografi, gönderi ve yorumlardaki bağlantılar, e-postalar ve telefon numaraları tıklanabilir; varsayılan tarayıcıda/uygulamada açılır",
          "🪪 Profil ve yönetici paneli de Juzzio Space düzeninde: büyük başlık, parlayan halkalı kare avatar, cam sayaç karoları, vurgu renkli birincil düğme, kapsül sekmeler ve cam istatistik kartları",
          "📊 Yeni anket kartı: oran çubuklu seçenekler, yüzdeler, kazanan vurgusu ve canlı durum çipi",
          "📅 Vardiya planlayıcıda tarih aralığı: başlangıç–bitiş günü ve saatleri seç (gece vardiyası dahil), hafta içi/sonu filtrele, grupla paylaş ve gruba otomatik plan özeti gönder",
          "🐣 Civciv sevilince prenses gibi sağa dönüp göz kırpar ve cilve yapar; sohbetteki civciv rozeti de aynı animasyonu yapar",
          "👑 Yeni civciv özelleştirmeleri: prenses tacı, çiçek taç, büyücü şapkası, yıldız gözlük, prenses tütüsü, inci kolye, bale pabucu, Şato/Uzay/Sakura sahneleri",
          "🧾 Yönetici kayıtları yöneticinin dilinde okunur cümleler: kim, ne yaptı, kime, ne zaman (kod ve kimlik gösterilmez)",
        ],
        fixes: [
          "Kumaş yenileme mobilde düzeltildi: Android taşma esnemesi ve iOS sekmesi ile çakışma giderildi, kısa listelerde de çekilebilir",
          "El gölgesindeki GPU bulanıklık artefaktı (dikdörtgen leke/titreme) kaldırıldı; yumuşak radyal gölge kullanılıyor",
          "Sohbet ⋯ menüsü sadeleşti: emojiler kaldırıldı, ikonlu ve opak (okunur) arka plan, tehlikeli işlemler ayrı ve kırmızı",
          "Menü, alt sayfa ve diyalog arka planları artık neredeyse opak — yazılar okunur",
        ],
        security: [
          "Bağlantı açıcı yalnız http/https/mailto/tel/geo şemalarına izin verir (javascript:, file: vb. reddedilir)",
          "Arka plan çevirisi uçtan uca şifrelemeyi bozmaz: şifreli sohbette çeviri ayrı bir şifreli yük olarak eklenir",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Juzzio moves to the \"Juzzio Space\" interface designed in Figma: deep theme gradients, frosted glass cards and a glowing accent in every theme. In the same update messages send without waiting, location/link/poll experiences were rebuilt, shifts can be planned by date range and admin logs became readable.",
        features: [
          "🎨 Juzzio Space design: \"Your space · Juzzio.\" header, search with a ⌘K shortcut, story rings, Inbox · Messages, filter pills with counters, glass chat cards and a floating glass bottom bar",
          "🌈 All 16 themes share the same design language; accent, background depth and glass opacity come from the selected theme (Emerald is the default for new users)",
          "⚡ Messages send instantly: the bubble appears right away, translation runs in the background and shows up under the message when ready (in end-to-end encrypted chats the translation is added encrypted too)",
          "📍 Shared locations appear as a card with a map preview and open in Google Maps on Android, Apple Maps on iOS, or Google Maps",
          "🔗 Links, e-mail addresses and phone numbers in messages, bios, posts and comments are tappable and open in the default browser/app",
          "🪪 Profile and admin panel use the Juzzio Space layout too: large header, square avatar with a glowing ring, glass counter tiles, accent primary button, capsule tabs and glass stat cards",
          "📊 New poll card: options with share bars, percentages, winner highlight and a live status chip",
          "📅 Date ranges in the shift planner: pick start–end days and hours (overnight shifts included), filter weekdays/weekends, share with a group and post a plan summary automatically",
          "🐣 When petted, the chick twirls to the right like a princess, winks and flirts; the chick badge in chats does the same animation",
          "👑 New chick customizations: princess tiara, flower crown, wizard hat, star glasses, princess tutu, pearl necklace, ballet shoes, Castle/Space/Sakura scenes",
          "🧾 Admin logs are readable sentences in the admin's language: who did what, to whom and when (no raw codes or IDs)",
        ],
        fixes: [
          "Cloth pull-to-refresh fixed on mobile: no more conflict with Android's stretch overscroll or iOS bouncing, and short lists can be pulled too",
          "Removed the GPU blur artifact on the hand shadow (rectangular smudge/flicker); a soft radial shadow is used instead",
          "Chat ⋯ menu cleaned up: no emojis, icons and an opaque (readable) background, destructive actions separated in red",
          "Menus, bottom sheets and dialogs are now nearly opaque — text stays readable",
        ],
        security: [
          "The link opener only allows http/https/mailto/tel/geo (javascript:, file: etc. are rejected)",
          "Background translation keeps end-to-end encryption: in encrypted chats the translation is attached as a separate encrypted payload",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.9',
    versionCode: 99,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "v0.9.8 kumaş yenileme önizlemesi referans videoyla kare kare karşılaştırıldı ve 11 görsel/zamanlama sapması bulundu. Bu güncelleme 3D el, kumaş kıvrımları, çentik katmanı ve sayfa senkronizasyonunu bu 11 maddeye birebir uyacak şekilde düzeltir.",
        features: [
          "⚫ Dynamic Island her iki temada tam siyah (#000000) ve en üst katmanda; el çentiğin alt kenarından maskelenerek çıkar ve içine girerek kaybolur",
          "👀 İlk çekişte (0–35 px) çentiğin altından önce yalnız 4 tombul parmak ucu ve tırnaklar görünür; çekme sürdükçe el ve bilek iner",
          "🖐️ Daha kısa ve tombul 3D kil kol (bilek ≈ çentik genişliğinin %55'i), başparmak dahil tüm parmaklarda parlak 3D tırnaklar ve boğum çizgileri; sıcak mat şeftali cilt (#F2C2B3 / #DF9F8E / #F9DCD3)",
          "🕰️ Sarkaçta kök çentikte sabit, kol ve bilek esnek bir kemik gibi bükülür; +25° zirvede parmaklar yelpaze gibi açılır, merkeze dönerken kapanır (9 ayrı 3D poz)",
          "✊ Yumrukta 4 kıvrık parmağın boğumları, aralarındaki dikey gölge oyukları ve altta sıkılı başparmak net görünür",
          "🦋 Yumruk anında sol ve sağ yanda çentiğe doğru kıvrılan kelebek kanadı kıstırma katları; alt taraf pürüzsüz",
          "🧵 Yukarı çekmede 6 kavisli, asimetrik 3D perde katı arama ikonu, konum başlığı ve avatarın üzerini yarı saydam bir çarşaf gibi örter ve \"Popular Food\" hizasına iner",
          "📏 Çekme ve sarkaç boyunca içerik 140–155 px aşağı kayar; el hiçbir yazı veya ikonla çakışmadan temiz boşlukta sallanır",
          "🔒 Sayfa yumruk kumaşı kavrayana kadar tam çekilmiş konumda kilitli kalır; yalnız yukarı çekmede yumruğun alt sınırına bağlı olarak elle aynı hızda kalkar",
          "🧺 Son 250 ms'de kıvrımlar yukarı gerilerek düzleşir; sayfa titremeden yerine oturur",
        ],
        fixes: [
          "Aydınlık temada kumaş kıvrımlarındaki siyah/koyu gri \"güneş ışını\" çizgiler kaldırıldı: vadiler yalnız gümüş-gri (#DFE2E8–#C8CDD6), sırtlar saf beyaz",
          "Koyu temada yumruk çevresindeki beyaz sis/hale kaldırıldı: vadiler #07080B, sırtlar #222630",
          "El artık çentiğin üstüne binmiyor; koyu temada gri çentik düzeltildi",
          "Kolun tek parça döndürülmesi (katı sprite) kaldırıldı",
          "Sayfanın yumruk anında erken yukarı kaçması düzeltildi",
          "APK derlemesi bağımlılık çakışması nedeniyle başarısız oluyordu (file_picker <12 → win32 ^5, flutter_secure_storage ^11 → win32 ^6); file_picker ^13'e yükseltildi, şifreli anahtar deposu değiştirilmedi",
        ],
        security: [
          "Yeni görseller tamamen özgün, kendi ürettiğimiz 3D render'lar; ek izin veya veri toplanmaz",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "The v0.9.8 cloth refresh preview was compared frame by frame with the reference video and 11 visual/timing deviations were found. This update fixes the 3D hand, fabric folds, notch layering and page sync to match all 11 points exactly.",
        features: [
          "⚫ The Dynamic Island is pure black (#000000) in both themes and always on the top layer; the hand is masked at the island's bottom edge, emerges from it and disappears back into it",
          "👀 On the first pull (0–35 px) only the 4 chubby fingertips and nails peek out from under the island; the hand and wrist come down as you keep pulling",
          "🖐️ A shorter, chubbier 3D clay arm (wrist ≈ 55% of the island width), glossy 3D nails on every finger including the thumb, knuckle creases and a warm matte peach skin (#F2C2B3 / #DF9F8E / #F9DCD3)",
          "🕰️ During the pendulum the root stays fixed at the island while the arm and wrist bend like a flexible bone; at the +25° peak the fingers fan out, then close again on the way back (9 separate 3D poses)",
          "✊ The fist clearly shows the 4 curled fingers' knuckles, vertical shadow grooves between them and the thumb clenched underneath",
          "🦋 When the fist closes, butterfly-wing pinch folds curl up toward the island on its left and right; the bottom stays smooth",
          "🧵 On the yank, 6 curved, asymmetric 3D drapery pleats cover the search icon, location title and avatar like a semi-transparent sheet and reach down to \"Popular Food\"",
          "📏 The content moves 140–155 px down while pulling and swinging, so the hand swings in clean empty space without touching any text or icon",
          "🔒 The page stays locked at the fully pulled position until the fist grabs the fabric; only during the yank does it rise, attached to the fist's lower edge at the same speed as the hand",
          "🧺 In the last 250 ms the folds stretch upward and flatten, and the page settles with no jitter",
        ],
        fixes: [
          "Removed the black/dark grey \"sunburst\" lines in light mode: valleys are only silver grey (#DFE2E8–#C8CDD6), ridges pure white",
          "Removed the white haze around the fist in dark mode: valleys #07080B, ridges #222630",
          "The hand no longer paints over the notch; the grey notch in dark mode is fixed",
          "Removed the rigid single-sprite arm rotation",
          "Fixed the page jumping up early while the fist was still closing",
          "The APK build failed on a dependency conflict (file_picker <12 needs win32 ^5, flutter_secure_storage ^11 needs win32 ^6); file_picker was upgraded to ^13 and the encrypted key store was left untouched",
        ],
        security: [
          "The new visuals are fully original 3D renders made by us; no extra permissions or data collection",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.8',
    versionCode: 98,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "v0.9.7'deki iki boyutlu kumaş efekti gönderilen videodaki animasyonla örtüşmüyordu. Aşağı çekip yenileme, videoyla birebir aynı 5 fazlı 3D fizik ve görsel mimariyle sıfırdan yeniden yazıldı.",
        features: [
          "🖐️ 3D kil/vinil dokulu el ve kol: yumuşak alt yüzey saçılımı, ortam kapanması ve mat parıltıyla gerçek 3D render (açık elden yumruğa 8 kare)",
          "📱 Kol ekranın üst ortasından, Dynamic Island / çentiğin içinden çıkıyormuş gibi keskin maskelenir",
          "🌑 Elin altında kendi silüetinden üretilen yumuşak 3D zemin gölgesi; el sallandıkça ve kalktıkça ışık açısına göre kayar",
          "⬇️ Faz 1: aşağı çekince içerik ~90–110 px kayar, el çekme mesafesiyle orantılı süzülür",
          "🕰️ Faz 2: yenilenirken kol önce sola (~15°) sonra sağa (~25°) ağırlığı hissedilen bir sarkaç gibi sallanır; parmaklarda ikincil esneme",
          "✊ Faz 3: yenileme bitince parmaklar yumruk olur, ekranı kumaş gibi kavrar; gerilme kıvrımları belirir",
          "🧵 Faz 4: yumruk çentiğe çekilirken ekranın üst yarısında derin 3D perde kıvrımları açılır (parlak sırtlar + gölge vadileri); sayfa ele bağlı bir yayla birlikte yukarı çekilip yerine oturur",
          "🧺 Faz 5: kıvrımlar ~250 ms'de yukarı gerilerek ütülenir",
          "🎨 Kumaş rengi temaya uyar: aydınlıkta beyaz/gümüş-gri, koyu ve cam temalarda buzlu sırt + koyu mat gölge",
          "⚡ Tek RepaintBoundary içinde, sayfa yeniden kurulmadan 60/120 fps; Sohbetler, Profil, Keşif ve tüm ana sayfalarda",
        ],
        fixes: [
          "v0.9.7'deki iki boyutlu damla çizimi videodaki animasyonla örtüşmüyordu; tamamen kaldırıldı",
        ],
        security: [
          "Yeni görseller tamamen özgün ve kendi ürettiğimiz 3D render'lar; ek izin veya veri toplanmaz",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "The 2D cloth effect in v0.9.7 did not match the reference video. Pull-to-refresh has been rewritten from scratch with the same 5-phase 3D physics and visual architecture as the video.",
        features: [
          "🖐️ 3D clay/vinyl hand and arm: real 3D render with soft subsurface scattering, ambient occlusion and matte sheen (8 frames from open hand to fist)",
          "📱 The arm emerges from the top center, cleanly masked as if coming out of the Dynamic Island / notch",
          "🌑 A soft 3D drop shadow generated from the hand's own silhouette, shifting with the light angle as the hand swings and lifts",
          "⬇️ Phase 1: pulling down shifts the content ~90–110 px while the hand glides down in proportion",
          "🕰️ Phase 2: while refreshing, the arm swings like a weighted pendulum — left (~15°), right (~25°), back to center — with secondary finger motion",
          "✊ Phase 3: when refreshing finishes, the fingers clench into a fist and grab the screen like fabric; tension creases appear",
          "🧵 Phase 4: as the fist is yanked into the notch, deep 3D drapery folds fan out across the top half (bright ridges + shadow valleys); the page is pulled up by a spring tethered to the hand",
          "🧺 Phase 5: the folds stretch upward and smooth out in ~250 ms",
          "🎨 Fabric color follows your theme: white/silver-grey in light mode, frosted ridges with deep matte shadows in dark and glass themes",
          "⚡ Isolated in one RepaintBoundary, no page rebuilds, 60/120 fps — on Chats, Profile, Explore and every main page",
        ],
        fixes: [
          "The 2D drop drawing from v0.9.7 did not match the video and has been removed",
        ],
        security: [
          "The new visuals are fully original 3D renders made by us; no extra permissions or data collection",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.7',
    versionCode: 97,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Bugün yayınlanan 0.9.4, 0.9.5 ve 0.9.6 güncellemelerinin üzerine; sohbetlerin anında açılması (yerel SQLite önbelleği), kaydırma titremesinin tamamen giderilmesi, aramalarda pil/ısı tasarrufu ve canlı çevirinin küçük pencerede sürmesi ile arayüzü daha modern, akışkan ve elit bir Liquid Glass deneyimine taşımak için getirildi. Bu notlar bugün yapılan TÜM değişiklikleri içerir.",
        features: [
          "⚡ Anında açılış: sohbet listesi ve mesajlar Drift (SQLite) yerel önbelleğinden ilk karede görünür; senkronizasyon arka planda sürer, 'dokun yaz' beklemesi yok",
          "🧵 Kumaş yenileme: tüm ana sayfalarda aşağı çekince ekranın üstü esnek bir kumaş gibi sarkar, bırakınca yay etkisiyle toparlanır",
          "💬 Sohbet her zaman en son mesajdan açılır; yukarı kaydırınca eski mesajlar kendiliğinden yüklenir (50'şer), titreme ve aşağı fırlama yok",
          "🔴 Modern hap şeklinde okunmamış rozeti: tema renklerinde, yaylanarak beliren animasyon, 99+ sınırı",
          "🫧 Parıldayan iskelet yükleyiciler: sohbet listesi, profil, akış ve listelerde boş gri ekran yerine",
          "🌗 Koyu/aydınlık geçişinde dokunduğun noktadan açılan dairesel geçiş animasyonu",
          "🔔 Uygulama içi bildirim yığını: kartlar üst üste kayarak gelir, arkadakiler küçülüp solar; Android bildirim çekmecesinde de gruplanır",
          "🎨 4 yeni cam teması: Kuzey Işıkları, Buzlu İnci, Gece Safiri, Kuzey Buzu (toplam 16) ve cam yüzeylerde ince buzlu doku",
          "👤 Avatar baş harf zeminleri ve çevrimiçi noktaları artık gri değil, seçili temanın renklerinde",
          "📺 PiP (küçük pencere) modunda canlı çeviri altyazısı görünmeye devam eder",
          "🔋 Aramada güç profili: arka planda/PiP'te veya zayıf ağda 360p·15 fps; ekran her saniye yeniden çizilmez",
          "🧹 Akıllı medya önbelleği: yönetici panelinden sınır (MB) ve azami yaş; eski dosyalar otomatik temizlenir",
          "🛡️ Yönetici → Sistem (Tanrı modu): sistem sağlığı, çökme merkezi, depolama bakımı, çoklu hesap tespiti, AI kotası, ses/video sınırları, minimum sürüm, yasal dışa aktarım, tüm oturumları kapat (0.9.6)",
          "👁️ Göz Konforu: elle, zamanlanmış veya gün batımından gün doğumuna amber filtre (0.9.6)",
          "📌 Sabit mesajlar, ✏️ 'Düzeltildi' etiketi + yeniden çeviri + '(Düzenlendi)' bildirimi, 🐞 otomatik hata bildirimi (0.9.6)",
          "📶 Mobil veride aramada 'Veri Koruma' önerisi ve 'Uygula' düğmesi — artık kendiliğinden açılmaz (0.9.6)",
          "🎬 İzleme partisi, 🆘 güvenli takip (SOS), 1️⃣ tek seferlik medya, ❓ anonim soru kutusu, 🏅 rozet ve seriler, 🔐 güvenlik numarası (0.9.5)",
          "📎 Ataş menüsü: belge, konum, kişi kartı, etkinlik; 🐥 civciv gardırobu; 🗓️ vardiya planlayıcı (0.9.4)",
        ],
        fixes: [
          "Sohbete girince listenin yukarıda kalması, yukarı kaydırırken titreme ve sürekli en alta fırlama sorunu giderildi (ters liste mimarisi)",
          "Uygulama açılışında mesajı olan sohbetlerde 'Sohbet başlatmak için dokun' yazısı görünmesi giderildi",
          "Arama ekranında süre sayacı her saniye tüm ekranı (video katmanları dahil) yeniden çiziyordu; pil ve ısınma azaltıldı",
          "Kumaş yenileme saydam zeminli temalarda siyah görünmesin diye tema zeminiyle karıştırıldı",
          "Düzenlenen grup mesajında eski çevirinin görünmesi (0.9.6)",
          "Yönetici panelinde tema seçerken 'geçersiz ayar' hatası (0.9.5)",
          "Arama ekranının arkasında sohbet sayfasının görünmesi (0.9.4)",
        ],
        security: [
          ".gitignore en katı hâline getirildi: ortam değişkenleri, imza anahtarları, sertifikalar, yerel veritabanları ve derleme çıktıları depoya giremez",
          "Gizli bilgi taraması depoda izlenen yasak dosyaları (.env, keystore, google-services.json, SQLite) ve webhook sırlarını da yakalar",
          "Yerel SQLite önbelleği hesaba özeldir ve çıkışta silinir; uçtan uca şifreli mesajlar diskte de şifreli kalır",
          "Birebir sohbette sesli mesaj, video ve hikâye yanıtları uçtan uca şifreli (0.9.6)",
          "Hata raporlarında e-posta, telefon, belirteç ve bağlantı parametreleri cihazda maskelenir (0.9.6)",
          "Tek seferlik medya açıldıktan sonra kalıcı silinir; anonim soru göndereni yalnız kayıtlı şikâyet incelemesinde görülür (0.9.5)",
          "Engellenen kişi kimin engellediğini göremez; görseller yüklenmeden önce sıkıştırılır (0.9.4)",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Builds on today's 0.9.4, 0.9.5 and 0.9.6 updates: chats now open instantly from a local SQLite cache, scroll jitter is gone, calls save battery and keep live translation visible in picture-in-picture, and the whole interface moves to a more modern, fluid and elite Liquid Glass experience. These notes cover ALL of today's changes.",
        features: [
          "⚡ Instant launch: the chat list and messages appear on the first frame from a Drift (SQLite) local cache; syncing continues in the background with no 'tap to start' wait",
          "🧵 Cloth pull-to-refresh: on every main page the top of the screen sags like elastic fabric and springs back when released",
          "💬 Chats always open at the latest message; older messages load automatically as you scroll up (50 at a time) with no jitter or jumping",
          "🔴 Modern pill-shaped unread badge in theme colors with a springy animation and a 99+ cap",
          "🫧 Shimmering skeleton loaders instead of empty grey screens on the chat list, profile, feed and lists",
          "🌗 Circular reveal animation from your tap point when switching between dark and light mode",
          "🔔 In-app notification stack: cards slide in on top of each other while older ones shrink and fade; also grouped in the Android notification shade",
          "🎨 4 new glass themes: Aurora Borealis, Frosted Pearl, Midnight Sapphire, Nordic Frost (16 in total) plus a subtle frosted texture on glass surfaces",
          "👤 Avatar initials and online dots now use your theme colors instead of grey",
          "📺 Live translation captions stay visible in picture-in-picture (PiP) mode",
          "🔋 Call power profile: 360p·15 fps in the background/PiP or on weak networks; the call screen no longer redraws every second",
          "🧹 Smart media cache: limit (MB) and maximum age set from the admin panel; old files are cleaned automatically",
          "🛡️ Admin → System (god mode): system health, crash center, storage maintenance, multi-account detection, AI quota, voice/video limits, minimum build, legal export, sign everyone out (0.9.6)",
          "👁️ Eye Comfort: amber filter — manual, scheduled or sunset to sunrise (0.9.6)",
          "📌 Pinned messages, ✏️ 'Edited' label + re-translation + '(Edited)' notification, 🐞 automatic crash reporting (0.9.6)",
          "📶 On mobile data, calls offer a 'Data saver' prompt with an 'Apply' button — it no longer switches on by itself (0.9.6)",
          "🎬 Watch parties, 🆘 safety check (SOS), 1️⃣ view-once media, ❓ anonymous question box, 🏅 badges & streaks, 🔐 safety number (0.9.5)",
          "📎 Attachment menu: documents, location, contact card, events; 🐥 chick wardrobe; 🗓️ shift planner (0.9.4)",
        ],
        fixes: [
          "Fixed chats opening scrolled up, jitter while scrolling up and the list constantly jumping to the bottom (reverse list architecture)",
          "Fixed 'Tap to start chatting' showing on chats that already have messages at launch",
          "The call timer redrew the whole call screen (including video layers) every second; battery use and heat reduced",
          "Cloth refresh is blended with the theme background so it never looks black on transparent themes",
          "Edited group messages kept showing the old translation (0.9.6)",
          "'Invalid setting' error when choosing a theme in the admin panel (0.9.5)",
          "The chat page showing through behind the call screen (0.9.4)",
        ],
        security: [
          ".gitignore is now as strict as possible: environment files, signing keys, certificates, local databases and build outputs can never enter the repository",
          "The secret scanner also catches forbidden tracked files (.env, keystores, google-services.json, SQLite) and webhook secrets",
          "The local SQLite cache is per account and deleted on sign-out; end-to-end encrypted messages stay encrypted on disk",
          "Voice messages, videos and story replies in 1:1 chats are end-to-end encrypted (0.9.6)",
          "Crash reports mask emails, phone numbers, tokens and URL parameters on the device (0.9.6)",
          "View-once media is permanently deleted after opening; anonymous askers are only revealed during logged report review (0.9.5)",
          "A blocked person cannot see who blocked them; images are compressed before upload (0.9.4)",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.6',
    versionCode: 96,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Yönetici paneline Tanrı modu (sistem sağlığı, çökme merkezi, depolama bakımı, AI kotası), göz konforu, sabit mesajlar ve birebir sohbette uçtan uca şifreli ses/video getirmek için getirildi.",
        features: [
          "Göz Konforu: elle, zamanlanmış (ör. 20:00–07:00) veya gün batımından gün doğumuna amber mavi ışık filtresi; yoğunluk ayarı",
          "Sabit mesajlar: grupta ve birebirde mesaj sabitle; sohbetin üstünde sabit mesaj şeridi (en fazla 5)",
          "Mesaj düzenleme: 'Düzeltildi' etiketi, çeviri yeniden yapılır, karşı tarafa '(Düzenlendi)' bildirimi",
          "Aramada mobil veride şıkça bir 'Veri Koruma' önerisi ve 'Uygula' düğmesi (artık kendiliğinden açılmaz)",
          "Aramada karşı tarafın mikrofonu/kamerası kapalıysa rozet gösterilir",
          "Sohbetler en yeni 50 mesajla hızlı açılır; 'Daha eski mesajlar' ile geriye gidilir",
          "Otomatik hata bildirimi: çökme ve hatalar yığın iziyle yönetici paneline gelir (Ayarlar'dan kapatılabilir)",
          "Yönetici → Sistem: sağlık, çökme merkezi, depolama kuyruğu, öksüz medya taraması, çoklu hesap tespiti, AI kotası, ses/video sınırları, minimum sürüm, kaba kuvvet eşikleri, yasal dışa aktarım, tüm oturumları kapat",
        ],
        fixes: [
          "Düzenlenen grup mesajında eski çeviri gösterilmeye devam ediyordu",
        ],
        security: [
          "Birebir sohbette sesli mesaj, video ve hikâye yanıtları artık uçtan uca şifreli",
          "Hata raporlarında e-posta, telefon, belirteç ve bağlantı parametreleri cihazda maskelenir",
          "Minimum sürüm, yasal dışa aktarım ve genel oturum kapatma yalnız süper yöneticiye açık ve denetim kaydına yazılır",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Adds a god-mode admin system tab (health, crash center, storage maintenance, AI quota), eye comfort mode, pinned messages and end-to-end encrypted voice/video in direct chats.",
        features: [
          "Eye Comfort: amber blue-light filter — manual, scheduled (e.g. 20:00–07:00) or sunset to sunrise, with intensity control",
          "Pinned messages in groups and direct chats, shown in a bar at the top (up to 5)",
          "Message edits: 'Edited' label, re-translation and an '(Edited)' notification",
          "On mobile data, calls offer a 'Data saver' prompt with an 'Apply' button (no longer switches on by itself)",
          "Calls show badges when the other side's microphone or camera is off",
          "Chats open faster with the newest 50 messages; load older ones on demand",
          "Automatic crash reporting with stack traces to the admin panel (can be turned off in Settings)",
          "Admin → System: health, crash center, storage queue, orphan media scan, multi-account detection, AI quota, voice/video limits, minimum build, brute-force thresholds, legal export, sign everyone out",
        ],
        fixes: [
          "Edited group messages kept showing the old translation",
        ],
        security: [
          "Voice messages, videos and story replies in direct chats are now end-to-end encrypted",
          "Crash reports mask emails, phone numbers, tokens and URL parameters on the device",
          "Minimum build, legal export and global sign-out are super-admin only and audit-logged",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.5',
    versionCode: 95,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "İzleme partisi, güvenli takip (SOS), tek seferlik medya, anonim soru kutusu ve rozetler gibi yeni özellikleri getirmek ve yönetici panelindeki tema seçimi hatasını gidermek için getirildi.",
        features: [
          "İzleme partisi: sohbette .mp4/.m3u8 videoları herkeste aynı saniyede oynar; ev sahibi kontrol eder",
          "Güvenli takip (SOS): varış süresi dolarsa, hareket yoksa ya da pil %5'e düşerse sohbete konumlu 🆘 uyarısı",
          "Tek seferlik fotoğraf: alıcı bir kez açar, sonra kalıcı silinir; görüntülerken ekran görüntüsü engellenir",
          "Anonim soru kutusu: profilinde soru al, yanıtla; anonim soranın kimliği sana bile gösterilmez",
          "Rozetler ve seriler: günlük seri, civciv bakım serisi, 10 rozet; 'Bugün 1 yıl önce' anı bildirimi",
          "Güvenlik numarası: uçtan uca şifrelemeyi QR ve 60 haneyle doğrula",
          "Giden aramada 'Çalıyor…' / 'Aranıyor…' durumu ve bekleme tonu",
          "Anketler süre dolunca otomatik kapanır; kazanan şık herkese bildirilir",
          "Hikâyeye sesli ve görüntülü yanıt",
          "Düşük veri modu, aramada gürültü engelleme ve pil dostu siyah ekran modu",
          "Yönetici paneli: güven puanı sekmesi",
        ],
        fixes: [
          "Yönetici panelinde varsayılan cam teması seçerken 'geçersiz ayar' hatası (sunucu yalnız 6 temayı kabul ediyordu) düzeltildi",
        ],
        security: [
          "Tek seferlik medya açıldıktan sonra sunucudan ve depodan kalıcı olarak silinir",
          "Anonim soruların göndereni yalnız şikâyet incelemesinde yetkili personele, kayıt altına alınarak gösterilir",
          "Güven puanı şeffaf kurallarla hesaplanır; 30 altındaki hesaplar günde en fazla 3 gönderi paylaşabilir",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Adds watch parties, safety check (SOS), view-once media, anonymous question box and badges, and fixes the admin panel theme selection error.",
        features: [
          "Watch party: .mp4/.m3u8 videos play at the same second for everyone; the host controls playback",
          "Safety check (SOS): an 🆘 alert with location if arrival time passes, no movement, or battery drops to 5%",
          "View-once photos: opened once, then permanently deleted; screenshots blocked while viewing",
          "Anonymous question box on your profile; anonymous askers stay hidden even from you",
          "Badges and streaks: daily streak, chick-care streak, 10 badges; 'On this day' memories",
          "Safety number: verify end-to-end encryption with a QR code and 60 digits",
          "Outgoing calls show 'Ringing…' / 'Calling…' with a ringback tone",
          "Polls can close automatically; the winning option is announced to everyone",
          "Voice and video replies to stories",
          "Data saver, call noise suppression and a battery-friendly black screen mode",
          "Admin panel: trust score tab",
        ],
        fixes: [
          "Fixed the 'invalid setting' error when choosing the default glass theme in the admin panel",
        ],
        security: [
          "View-once media is permanently deleted from the server and storage after opening",
          "Anonymous askers are only revealed to authorized staff during report review, and that access is logged",
          "Trust score uses transparent rules; accounts under 30 can share at most 3 posts per day",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.4',
    versionCode: 94,
    publishedAt: DateTime(2026, 11, 9),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Canlı veritabanı denetiminde bulunan güvenlik ve performans sorunlarını gidermek, sohbete belge/konum/etkinlik eklemek ve arama ekranındaki görüntü hatasını düzeltmek için getirildi.",
        features: [
          "Ataş menüsü: belge (PDF, ZIP, DOCX…; birebirde uçtan uca şifreli), galeri, video, konum, kişi kartı, anket, etkinlik, zamanlama",
          "Kamera düğmesi artık yalnız çekim yapar (dokun: fotoğraf, basılı tut: video)",
          "Grup etkinlikleri: tarih/saat, katılım (Katılıyorum/Belki/Katılmıyorum) ve otomatik hatırlatma bildirimi",
          "Civciv gardırobu: şapka, gözlük, kıyafet, ayakkabı, tema ve gövde rengi; besledikçe jeton kazanılır",
          "Vardiya planlayıcı (08-16 / 16-00 / 00-08, izin, fazla mesai) ve grupla paylaşılan ekip takvimi",
          "Cihaz saati ülke saatinden 2 dakikadan fazla saparsa 'Tarih ve saatinizi eşitleyin' uyarısı",
          "Anket sonuçları diğer üyeler oy verdikçe kendiliğinden yenilenir",
        ],
        fixes: [
          "Arama ekranının arkasında sohbet sayfasının görünmesi (saydam zemin) düzeltildi",
          "Anket oluştururken hata mesajı görünmüyordu; artık sayfanın içinde gösteriliyor",
          "Canlı altyazıda konuşma cümlenin ortasında ikiye bölünmüyor",
          "Kopya veritabanı indeksleri kaldırıldı (daha hızlı yazma)",
          "Grup rol kısıtına yanlışlıkla karışmış dil kodları temizlendi",
        ],
        security: [
          "Engellenen kişi artık kimin engellediğini ve engelleme sebebini göremez",
          "Profil/kapak görselleri yüklenmeden önce sıkıştırılır (5 MB sınırı); gönderi/reels kovaları yalnız görsel ve video kabul eder",
          "Konum yalnız siz 'Konum'a dokunduğunuzda alınır ve birebir sohbette şifreli gönderilir",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Fixes security and performance issues found in a live database audit, adds documents, location and events to chats, and fixes the call screen display bug.",
        features: [
          "Attachment menu: documents (PDF, ZIP, DOCX…; end-to-end encrypted in 1:1 chats), gallery, video, location, contact card, poll, event, schedule",
          "The camera button now only captures (tap: photo, hold: video)",
          "Group events with date/time, RSVP and automatic reminder notifications",
          "Chick wardrobe: hats, glasses, outfits, shoes, themes and body color; earn coins by feeding",
          "Shift planner (08-16 / 16-00 / 00-08, day off, overtime) with a shared team calendar",
          "Warning when the device clock is more than 2 minutes off",
          "Poll results refresh automatically as others vote",
        ],
        fixes: [
          "Fixed the chat page showing through behind the call screen",
          "Poll creation errors are now shown inside the sheet",
          "Live captions no longer split a sentence in the middle",
          "Removed duplicate database indexes",
          "Removed language codes that had slipped into the group role constraint",
        ],
        security: [
          "A blocked person can no longer see who blocked them or the reason",
          "Profile/cover images are compressed before upload (5 MB limit); posts/reels buckets accept only images and videos",
          "Location is only read when you tap 'Location' and is sent encrypted in 1:1 chats",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.3',
    versionCode: 93,
    publishedAt: DateTime(2026, 11, 6),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Görüşme sırasında uygulamayı kullanmaya devam edebilmek (küçük pencere / PiP), bildirimleri dilinizde okuyup yanıtlayabilmek ve kullanıcıların bildirdiği 17 sorunu gidermek için getirildi.",
        features: [
          "Görüşme sürerken sohbetlere geçilebilir; uygulama küçültülünce görüşme sağ köşede ekran içinde ekran (PiP) olarak sürer",
          "Görüşme sırasında gelen mesaj bildirimine dokununca görüşme kesilmeden o sohbet açılır",
          "Bildirimler uygulama dilinize çevrilmiş mesaj içeriğiyle gelir ve uygulama kapalıyken bile yanıtlanabilir",
          "Hikâyeler 30 saniye görünür; hikâyede paylaşanın adına dokununca profili açılır",
          "Juzzio Official: mavi tikli resmi tanıtım hikâyeleri Durumlar'da herkeste ilk sırada",
          "Güzelleştirme yoğunluğu ayarı: görüntülü aramada ve hikâye fotoğraflarında",
          "Yorum yanıtında otomatik @bahsetme; 'yorumunuza yanıt verdi' ve 'yorumunuzu beğendi' bildirimleri",
          "Sesli mesajlarda toplam süre ve oynatılırken geçen süre",
          "Civciv oyunu yenilendi: HD vektör civciv, likit cam butonlar, sevme ve besleme animasyonları; yumurta sohbette yalnız civciv acıktığında görünür",
          "Yaylı ve akıcı sola kaydırarak silme (onaylı)",
          "224 dil desteği (80 yeni dil)",
          "İnternet yokken profil sayfası açılır; çevrimdışı değiştirilen ayarlar bağlantı gelince uygulanır",
          "Tanıtım web sitesi: engiincr.github.io/Juzzio-Chat",
        ],
        fixes: [
          "Sesli mesaj dökümünde 'QUERY LENGTH LIMIT EXCEEDED' hata metni artık görünmüyor; uzun metinler parça parça çevrilir",
          "Sohbetler ilk açılışta 'Sohbet başlatmak için dokun' yerine son mesajı gösterir",
          "Google Drive yedeklemede 'erişim reddedildi' hatası: izin yeniden istenir, süresi dolan oturum yenilenir, anlamlı hata mesajları",
          "@bahsetme ve hatırlatma bildirimleri artık telefona (push) da gelir",
          "Şonaca ve Kirundi dil kodları düzeltildi",
        ],
        security: [
          "Juzzio Official hikâyesini yalnız yönetici paylaşabilir; sunucu tarafında zorunlu denetim",
          "Uçtan uca şifreleme değişmedi; bildirim çevirisi cihazda çözülen metinle yapılır",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Lets you keep using the app during calls (mini window / PiP), read and reply to notifications in your language, and fixes 17 user-reported issues.",
        features: [
          "You can switch to chats during a call; minimizing the app keeps the call in a picture-in-picture window",
          "Tapping a message notification during a call opens that chat without ending the call",
          "Notifications show the message translated into your app language and can be answered even when the app is closed",
          "Stories are shown for 30 seconds; tap the poster's name to open their profile",
          "Juzzio Official: blue-tick official teaser stories shown first in everyone's Stories",
          "Adjustable beauty intensity in video calls and story photos",
          "Automatic @mention when replying to comments; 'replied to your comment' and 'liked your comment' notifications",
          "Total duration on voice messages, elapsed time while playing",
          "Chick game redesigned: HD vector chick, liquid glass buttons, cuddle and feeding animations; the egg shows in chat only when the chick is hungry",
          "Springy, smooth swipe-left to delete (with confirmation)",
          "224 languages (80 new)",
          "Profile page opens offline; settings changed offline apply when the connection returns",
          "Website: engiincr.github.io/Juzzio-Chat",
        ],
        fixes: [
          "Voice transcripts no longer show the 'QUERY LENGTH LIMIT EXCEEDED' error; long texts are translated in chunks",
          "Chats show the last message on first open instead of 'Tap to start chatting'",
          "Google Drive backup 'access denied': permission is re-requested, expired sessions are refreshed, clear error messages",
          "@mention and reminder notifications now also arrive as push",
          "Fixed Shona and Kirundi language codes",
        ],
        security: [
          "Only the admin can post Juzzio Official stories; enforced on the server",
          "End-to-end encryption unchanged; notification translation uses text decrypted on the device",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.2',
    versionCode: 92,
    publishedAt: DateTime(2026, 11, 2),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "İnternet yokken de sohbetlerin, fotoğrafların, sesli mesajların ve profillerin WhatsApp'taki gibi açılabilmesi için getirildi.",
        features: [
          "Çevrimdışı sohbet: her sohbetin son 300 mesajı cihazda saklanır, internet yokken okunabilir",
          "Görüntülenen fotoğraflar ve profil resimleri cihazda saklanır, internetsiz görünür",
          "Dinlenen sesli mesajlar internetsiz tekrar çalınabilir",
          "Kişi profilleri internet yokken son görülen hâliyle açılır",
          "Bağlantı gelince sohbet kendiliğinden yenilenir (5 sn arayla yeniden bağlanır)",
        ],
        fixes: [
          "İnternet yokken şifreli mesajlar 'kilitli' görünmüyor; anahtarlar cihazdan okunur",
          "Hesap silindiğinde cihazdaki önbellek de siliniyor",
        ],
        security: [
          "Şifreli mesajlar ve şifreli fotoğraflar cihazda da şifreli hâliyle saklanır; çözme yalnız bellekte",
          "Önbellek hesaba özeldir; çıkışta ve hesap silmede silinir",
          "Medya önbelleği en fazla 300 MB; Ayarlar > Depolama > Önbelleği Temizle ile silinebilir (mesajlar silinmez)",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Lets chats, photos, voice messages and profiles open without internet, like WhatsApp.",
        features: [
          "Offline chats: the last 300 messages of each chat are kept on the device and readable without internet",
          "Viewed photos and profile pictures are stored on the device and shown offline",
          "Played voice messages can be replayed offline",
          "Contact profiles open offline with their last seen data",
          "Chats refresh automatically when the connection returns (reconnects every 5 s)",
        ],
        fixes: [
          "Encrypted messages no longer show as locked while offline; keys are read from the device",
          "Deleting the account also deletes the on-device cache",
        ],
        security: [
          "Encrypted messages and photos are stored encrypted on the device too; decryption happens only in memory",
          "The cache is per account and is deleted on sign-out and account deletion",
          "Media cache is capped at 300 MB and can be cleared in Settings > Storage > Clear cache (messages are kept)",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.1',
    versionCode: 91,
    publishedAt: DateTime(2026, 11, 2),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Uygulamayı yeniden Sohbetler ekranından açmak, birebir sohbetlerde mesaj çevirisini geri getirmek, Business'ı kaldırmak ve medya yüklenirken yaşanan takılmayı gidermek için getirildi.",
        features: [
          "Uygulama Sohbetler ekranından açılır; alt menü: Sohbetler, Keşfet, Aramalar, Bildirimler, Profil",
          "Görevlerim ve hatırlatıcılar Profil sekmesinin üstünden açılır",
        ],
        fixes: [
          "Birebir sohbetlerde mesaj çevirisi yeniden çalışıyor (varsayılan açık; Ayarlar > Gizlilik'ten kapatılabilir)",
          "Fotoğraf, sesli mesaj ve hikâyelerin yüklenirken takılması giderildi",
          "Ana Sayfa kartındaki bozuk (dikey) yazı görünümü sayfayla birlikte kaldırıldı",
          "Geri tuşu Sohbetler'e döner, Sohbetler'de iki kez basınca çıkar",
        ],
        security: [
          "Business hesabı ve ilgili tüm ekranlar kaldırıldı",
          "Çeviri açıkken mesajlar sunucuda yine şifreli saklanır",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Opens the app on Chats again, restores message translation in one-to-one chats, removes Business and fixes media hanging while loading.",
        features: [
          "The app opens on Chats; bottom bar: Chats, Explore, Calls, Notifications, Profile",
          "My tasks & reminders open from the top of the Profile tab",
        ],
        fixes: [
          "Message translation works again in one-to-one chats (on by default; can be turned off in Settings > Privacy)",
          "Fixed photos, voice messages and stories hanging while loading",
          "Removed the broken (vertical) text card together with the Home page",
          "Back button returns to Chats; press twice on Chats to exit",
        ],
        security: [
          "Business account and all related screens removed",
          "Messages stay encrypted on the server while translation is on",
        ],
      ),
    },
  ),
  JuzzioReleaseNote(
    versionName: '0.9.0',
    versionCode: 90,
    publishedAt: DateTime(2026, 11, 2),
    sections: const {
      'tr': JuzzioReleaseSection(
        reason: "Mesaj çevirisini yeniden etkinleştirmek, uygulamayı Sohbetler ekranından açmak, güvenliği sertleştirmek ve uçtan uca şifrelemeyi fotoğraflara genişletmek için getirildi.",
        features: [
          "Yaşam Merkezi: görevler ve mesaj hatırlatıcıları; kayıtlı mesajlar; gelişmiş mesaj arama",
          "Mesaj düzenleme (15 dk) ve düzenleme geçmişi; sohbet kilidi; @etiketleme ve 'beni kim etiketleyebilir'",
          "Güvenlik Merkezi: cihazlar, diğer oturumları kapat, doğrulanabilir güvenlik uyarıları, şifreli yedek durumu",
          "Dosya Merkezi: sohbetlerdeki medya, belge ve sesli mesajlar",
          "Grup anketleri (tekli/çoklu, gizli oylama) ve zamanlanmış mesajlar",
          "Sesli mesajda 1x / 1.5x / 2x oynatma hızı",
          "Bildirimden yanıtla, gelen aramayı bildirimden reddet; sohbet başına bildirim ayarları; yazıyor göstergesi",
        ],
        fixes: [
          "Sohbet içindeyken geri tuşu artık uygulamadan çıkmıyor",
          "Keşfet metin rengi açık temalarda okunur",
          "Tepki bildirimi şifreli metni önizlemeye kopyalamıyor",
          "Gelen arama tam ekran izni eklendi",
        ],
        security: [
          "Birebir sohbet fotoğrafları uçtan uca şifreli (AES-256-GCM + SHA-256 bütünlük); şifrelenemezse gönderilmez",
          "Kilit ekranında mesaj bildirimleri gizli; önizleme modu seçilebilir",
          "Zamanlanmış birebir mesajlar sunucuda yalnız şifreli saklanır",
          "Tüm yeni tablolarda satır düzeyi güvenlik (RLS); güvenlik olaylarını istemci yazamaz",
        ],
      ),
      'en': JuzzioReleaseSection(
        reason: "Re-enables message translation, opens the app on Chats again, hardens security and extends end-to-end encryption to photos.",
        features: [
          "Life Center: tasks and message reminders; saved messages; advanced message search",
          "Message editing (15 min) with edit history; chat lock; @mentions and 'who can mention me'",
          "Security Center: devices, sign out other sessions, verifiable security alerts, encrypted backup status",
          "File Center: media, documents and voice messages from your chats",
          "Group polls (single/multiple choice, anonymous) and scheduled messages",
          "Voice message playback speed 1x / 1.5x / 2x",
          "Reply from notification, decline incoming calls from notification; per-chat notification settings; typing indicator",
        ],
        fixes: [
          "Back button inside a chat no longer exits the app",
          "Explore text colour readable on light themes",
          "Reaction notifications no longer copy encrypted text into previews",
          "Full-screen intent permission added for incoming calls",
        ],
        security: [
          "Direct-chat photos are end-to-end encrypted (AES-256-GCM + SHA-256 integrity); never sent unencrypted",
          "Message notifications are private on the lock screen; preview mode selectable",
          "Scheduled direct messages are stored server-side only in encrypted form",
          "Row-level security on all new tables; clients cannot write security events",
        ],
      ),
    },
  ),
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
