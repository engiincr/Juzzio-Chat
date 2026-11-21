# Juzzio 2.1 — Google Play hazırlığı (Faz 17–18)

Bu belge Play Console'a girilecek metinleri, izin gerekçelerini ve yayın kontrol listelerini toplar.
Görseller `docs/play/` klasöründe; hepsi kodla çizilir (`tools/play_feature_graphic.py`), stok görsel yoktur.

## 17.1 Paket ve imza

- CI (`android-ci.yml`) imza anahtarı varsa APK'nın yanında **imzalı AAB** de üretir:
  `juzzio-v<sürüm>-play.aab` (+ `.sha256`). Dosya GitHub Actions **artefaktında** (`juzzio-apk`) bulunur,
  herkese açık GitHub Release'e konmaz.
- Play App Signing: Play Console → Kurulum → Uygulama imzalama → "Google tarafından yönetilen anahtar".
  CI'daki anahtar (`ANDROID_KEYSTORE_BASE64`) **yükleme anahtarı** olarak kalır.
- `targetSdkVersion 36`, `minSdkVersion 24`, `compileSdk 36`.

## 17.2 İzinler ve gerekçeleri

| İzin | Neden | Play notu |
|---|---|---|
| CAMERA, RECORD_AUDIO | Görüntülü/sesli arama, sesli mesaj, karekod tarama | — |
| FOREGROUND_SERVICE_MICROPHONE / CAMERA | Ekran kapalıyken süren arama | Ön plan servisi beyanı: "Arama" |
| FOREGROUND_SERVICE_MEDIA_PROJECTION | Aramada ekran paylaşımı (her seferinde kullanıcı izni) | Ön plan servisi beyanı: "Ekran paylaşımı" |
| FOREGROUND_SERVICE_MEDIA_PLAYBACK | Sinema Parti oynatma | — |
| USE_FULL_SCREEN_INTENT | Gelen arama ekranı | Arama uygulaması olarak izinli; beyan gerekir |
| POST_NOTIFICATIONS, VIBRATE, WAKE_LOCK, RECEIVE_BOOT_COMPLETED | Bildirimler, arama zili | — |
| ACCESS_COARSE_LOCATION | Hava durumu teması (konum ~10 km yuvarlanır) | **ACCESS_FINE_LOCATION** gerekmiyorsa Play paketinden çıkarılmalı |
| READ_MEDIA_IMAGES / VIDEO | Galeriden fotoğraf/video gönderme | Fotoğraf seçici kullanılırsa kaldırılabilir; beyan formu gerekir |
| BLUETOOTH_CONNECT | Aramada kulaklık | — |
| REQUEST_IGNORE_BATTERY_OPTIMIZATIONS | Aramaların kaçmaması | Gerekçe ister; reddedilirse kaldırılmalı |
| **REQUEST_INSTALL_PACKAGES** | Uygulama içi OTA güncelleme (APK) | **Play'den dağıtılan sürümde OLMAMALI.** Play uygulaması kendini Play dışından güncelleyemez. Play paketi için bu izin ve OTA indirme kapatılmalı |

> Yapılacak (Play'e ilk yüklemeden önce): `play` adlı ayrı bir derleme türü (flavor) ile
> REQUEST_INSTALL_PACKAGES / ACCESS_FINE_LOCATION kaldırılmalı ve OTA kapatılmalı. Bu değişiklik
> APK derleme komutunu da değiştirdiği için derleme denenmeden yapılmadı.

## 17.3 Veri Güvenliği formu (Data safety)

- **Veriler aktarımda şifreleniyor mu?** Evet (TLS). Mesajlar ayrıca uçtan uca şifreli.
- **Kullanıcı verilerini silme isteği:** Evet — uygulamada Ayarlar → Hesap ve Profil → Hesabı sil.
- **Toplanan veriler** (hepsi uygulama işlevi için, satılmaz, reklam için kullanılmaz):
  - Kişisel bilgiler: ad, kullanıcı adı, e-posta (hesap), isteğe bağlı telefon
  - Mesajlar: uçtan uca şifreli (sunucu içeriği okuyamaz); çeviri açılınca metin çeviri hizmetine gider
  - Fotoğraf/video, ses: kullanıcının gönderdiği medya, sesli mesajlar
  - Konum: yaklaşık (yalnız hava teması, cihazdan doğrudan Open-Meteo'ya; sunucuda saklanmaz)
  - Uygulama etkinliği: arama kayıtları, gönderiler, beğeniler
  - Uygulama bilgileri ve performans: hata raporları (uygulamanın kendi hata kaydı)
  - Cihaz kimlikleri: bildirim jetonu, cihaz kimliği (oturum güvenliği)
- **Paylaşım:** Hizmet sağlayıcılar (Supabase, LiveKit, Firebase, Deepgram, çeviri hizmetleri, Open-Meteo) yalnız hizmeti sunmak için.
- Ayrıntı: `PRIVACY.md` ve `docs/legal/tr/PRIVACY.md`.

## 17.3 İçerik derecelendirmesi (IARC) yanıtları

- Kategori: İletişim / sosyal. Kullanıcılar arası etkileşim: **Evet** (sohbet, arama, gönderi).
- Kullanıcı tarafından oluşturulan içerik paylaşılabilir: **Evet**; raporlama ve engelleme var, moderasyon var.
- Konum paylaşımı: Hayır (yalnız hava teması için yaklaşık konum, başkalarına gösterilmez).
- Dijital ürün satın alma: Hayır. Kumar/şiddet/cinsel içerik: Hayır.
- Yaş sınırı: 15+ (kayıtta beyan).

## 17.4 Mağaza listesi

**Kısa açıklama (TR, ≤80):** Uçtan uca şifreli sohbet, canlı çeviriyle sesli ve görüntülü arama.

**Kısa açıklama (EN, ≤80):** End-to-end encrypted chat with live-translated voice and video calls.

**Uzun açıklama (TR):**
Juzzio; arkadaşlarınla dil engeli olmadan konuşman için tasarlandı.
• Uçtan uca şifreli mesajlar — içeriği biz dahil kimse okuyamaz
• Sesli ve görüntülü aramada canlı çeviri ve altyazı
• Sesli mesajları kendi dilinde dinle ve oku
• Aramada ekran paylaşımı
• Keşfet ile yeni insanlarla tanış (istersen gizlen)
• Profil karekodu ile hızlı arkadaş ekle
• İki adımlı doğrulama, oturum bildirimleri, cihaz yönetimi
• Sessiz saatler, kalın yazı, renk düzeltme ve daha fazlası

**Görseller:** `docs/play/icon_512.png` (512×512), `docs/play/feature_graphic_1024x500.png`.
Ekran görüntüleri gerçek cihazdan alınmalı (en az 2 telefon görüntüsü; kişisel veri görünmemeli).

## 17.5 Çökme izleme

Uygulamanın kendi hata kaydı vardır (`app_error_reports`, Yönetici → Hata bildirimleri ve
Modül 28 "Sistem Olayları ve Alarmlar"). Firebase Crashlytics **eklenmedi** (Gradle eklentisi ve
derleme denemesi gerektirir). Play Console → Android vitals ayrıca ANR/çökme verir.

## 18.1–18.2 Başarım ve düşük internet

- Ölçülecekler (gerçek cihazda): soğuk açılış < 2,5 sn, sohbet listesi kaydırma 60 fps, aramada CPU.
- Düşük internet: Android geliştirici seçenekleri → ağ hızı sınırlama veya emülatörde "EDGE"; mesajlar
  çevrimdışı kuyruğa girer, arama 360p'ye düşer (Düşük veri), Gökyüzü katmanı "hareketi azalt"ta durur.

## 18.3 Kapalı beta kontrol listesi

1. Play Console → Test → Kapalı test kanalı, test kullanıcı listesi (e-posta)
2. AAB yükle, sürüm notlarını `lib/core/release_notes.dart`'tan kopyala
3. Testçilere: kayıt/giriş, 2FA, mesaj, sesli mesaj çevirisi, arama + çeviri, ekran paylaşımı, Keşfet, QR
4. Android vitals ve uygulama içi hata kayıtlarını 7 gün izle

## 18.4 Yayın öncesi son kontrol (18 madde)

1. Sürüm numarası (`version.json`, `pubspec.yaml`, `APP_BUILD`) aynı
2. Veritabanı güncellemeleri (10.43–10.47) üretimde uygulandı
3. Edge Function'lar yeniden dağıtıldı (`translate-bridge` çeviri kipi)
4. Supabase gizli anahtarları (Deepgram, DeepL, LiveKit) tanımlı; sistem sağlığı yeşil
5. RLS denetimi: Yönetici → Sistem → yetki denetimi boş
6. Gizlilik politikası ve koşullar güncel ve uygulamadan açılıyor
7. Veri Güvenliği formu bu belgeyle uyumlu
8. İzin beyanları (ön plan servisi, tam ekran bildirim) dolduruldu
9. REQUEST_INSTALL_PACKAGES Play paketinde yok
10. İçerik derecelendirmesi tamam
11. Hedef kitle ve içerik (15+) beyanı tamam
12. Mağaza görselleri ve ekran görüntüleri yüklendi
13. Kapalı beta en az 7 gün, kritik hata yok
14. Uçtan uca şifreleme: yeni cihazda eski mesajların okunduğu doğrulandı
15. Arama: Wi-Fi ↔ mobil veri geçişinde arama sürüyor
16. Bildirimler: uygulama kapalıyken mesaj ve arama bildirimi geliyor
17. Hesap silme ve "Verilerimi indir" çalışıyor
18. Geri dönüş planı: önceki AAB ve veritabanı yedeği hazır

## 18.5 Kademeli yayın planı

- Gün 1: %5 → Gün 3: %20 → Gün 5: %50 → Gün 7: %100.
- Her adımda: çökme oranı < %1, ANR < %0,47, kritik geri bildirim yok. Aşılırsa yayını durdur,
  düzeltmeyi kapalı testte doğrula, aynı sırayla yeniden başlat.
