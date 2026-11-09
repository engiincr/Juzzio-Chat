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
