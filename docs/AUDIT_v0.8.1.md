# Juzzio v0.8.1 — Denetim Raporu ve Faz Planı

Kapsam: "Mega Güncelleme Master Prompt" (§1.4, §20, §21) uyarınca ilk denetim ve **Faz 1 (tema motoru)** uygulaması.
Ortam sınırı: Bu çalışma ortamında Flutter/Dart SDK yok; `flutter analyze/test/build` burada **NOT RUN**. Gerçek sonuçlar GitHub Actions'ta oluşur.

## 1. Teknoloji yığını (kanıt: `pubspec.yaml`, `supabase/`, `.github/workflows/android-ci.yml`)

| Katman | Teknoloji |
| :-- | :-- |
| Mobil istemci | Flutter (Dart SDK `>=3.4.0 <4.0.0`), Android öncelikli; CI Flutter 3.47 |
| State | `JuzzioAppController` (ChangeNotifier singleton) + ekran içi `setState` |
| Tema | `app_theme_and_locale.dart` (JuzzioPalette), `theme/juzzio_glass.dart` (cam tokenları + ThemeData), `theme/juzzio_aurora.dart` (arka plan temaları) |
| Backend | Supabase (Auth, Postgres + RLS, Realtime, Storage), tek kanonik SQL: `supabase/juzzio_database.sql` |
| Edge Functions | `auth-username-login`, `content-moderation`, `get-livekit-token`, `push-webhook`, `translate-bridge` |
| Arama/medya | LiveKit (WebRTC), Deepgram (canlı altyazı) |
| Bildirim | FCM |
| Şifreleme | X25519 + ML-KEM-768 hibrit E2EE (1'e 1 metin), ML-DSA-65 yayın imzası doğrulama |
| CI/CD | GitHub Actions: sır taraması → Supabase senkronu → analyze/test → APK → Release |

Ekranlar: 19 ekran dosyası + `profile/`, `social/` alt klasörleri (~24.400 satır). Testler: 13 dosya (+1 bu fazda).

## 2. Bulgular (öncelikli)

| Öğe | Durum | Kanıt/Dosya | Etki | Öncelik | Çözüm | Doğrulama |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| Cam rengi görünmüyordu | Düzeltildi (v0.8.1) | `JuzzioGlass`: aynı BoxDecoration'da color+gradient | Tema rengi kayboluyor, çamurlu görünüm | P1 | Dolgu/ışık ayrı katman | Kod incelemesi; cihazda doğrulanmalı |
| Sohbet temaları hep gri | Düzeltildi | `kJuzzioChatThemes` | Tema seçimi etkisiz | P1 | Gerçek renkler + yoğunluk | `juzzio_v051_test` |
| Aydınlık modda cam bileşen teması yoktu | Düzeltildi | `main.dart` light ThemeData | Diyalog/sheet/snackbar tutarsız | P1 | Ortak builder (`dark:false`) | `juzzio_theme_engine_test` |
| Açılışta yanlış tema parlaması | Düzeltildi | Tercihler girişten sonra yükleniyordu | §3.3 ihlali | P2 | `runApp` öncesi ön yükleme (800 ms sınırlı) | Cihazda doğrulanmalı |
| Aydınlık temada durum çubuğu simgeleri beyaz | Düzeltildi | `main.dart` sabit `Brightness.light` | Okunmaz simgeler | P2 | Temaya göre simge parlaklığı | Cihazda doğrulanmalı |
| Bozuk tema verisi | Güvenli | `juzzioAuroraPaletteById` + try/catch | Çökme yok, varsayılana döner | — | Test eklendi | `juzzio_theme_engine_test` |
| `withOpacity` kullanımı (108 yer) | Açık | çeşitli | Yalnızca deprecation bilgisi | P3 | Kademeli `withValues` geçişi | `flutter analyze` info |
| Kullanılmayan `_checkInitialForeignPresence`, `pendingCount` | Açık | `call_screen.dart`, `chat_screen.dart` | Uyarı | P3 | Temizlik | analyze |
| JuzzioPalette metinleri yüksek kontrastı izlemiyor | Açık | `app_theme_and_locale.dart` | Ayarlar sayfalarında kontrast artışı sınırlı | P2 | Palette'i cam tokenlarına bağlama | Faz 2 |
| Özel tema stüdyosu (kullanıcı/admin) yok | Açık | — | §3.5/§10.4 | P2 | Faz 2 (DB şema gerektirir → onay) | — |
| Zamanlanmış otomatik tema yok | Açık | — | §3.1 | P3 | Faz 2 | — |
| RBAC rol matrisi tek "admin" | Açık | `admin_panel_screen.dart`, SQL | §10.3 | P2 | DB rol tablosu + RLS (onay gerekir) | — |

## 3. Faz 1 — bu sürümde uygulananlar (tema motoru, §3 kritik öncelik)

- Modlar: Light / Dark / System (mevcut) + tema kataloğu 12 tema: Juzzio Sıvı Cam, Gece Mavisi, Cam Beyaz, Ametist, Zümrüt, Lagün, Krom, **Obsidyen OLED, Lavanta Sisi, Gül Kuvars, Siber Neon, Yüksek Kontrast** (turuncu tonlu "Sunset/Warm Sand" bilinçli olarak eklenmedi).
- Kalıcılık: tema kimliği, cam yoğunluğu, performans modu kullanıcı bazlı dosyada; ilk kareden önce yüklenir; bozuk değerler sınırlanır/varsayılana döner.
- Atomik geçiş: tek `notifyListeners` ile tüm tokenlar (cam, ThemeData, aurora) aynı karede güncellenir; sayfa yeniden başlatılmaz, form/sohbet durumu korunur.
- Yüzey seviyeleri: Subtle (`surface`), Standard (`surfaceStrong`), Prominent (`sheet`) + bileşen blur değerleri.
- Ayarlar → Görünüm: tema önizleme + Uygula, **cam yoğunluğu (0.6–1.4, varsayılana dön)**, **performans modu** (blur kapalı fallback).
- Yüksek Kontrast: kenar opaklığı ×2.2, ikincil/pasif metinler belirgin.
- Sohbet teması yalnızca balonları etkiler; navigasyon/input/modal ortak tokenlarda kalır (§21).

## 4. Test durumu

| Komut | Amaç | Sonuç |
| :-- | :-- | :-- |
| `flutter analyze` | Statik analiz | NOT RUN (ortamda SDK yok) → CI |
| `flutter test` | Birim testler (+`juzzio_theme_engine_test.dart`) | NOT RUN → CI |
| `flutter build apk` | Derleme | NOT RUN → CI |
| Tree-sitter Dart sözdizimi | Sözdizimi | PASS (0 hata) |
| const/getter taraması | const içinde dinamik token | PASS |
| `scripts/check_secrets.py` | Sır taraması | PASS |
| `scripts/verify_tree.py` | Dosya bütünlüğü | PASS |

## 5. Sonraki fazlar (yaklaşık)

- **Faz 2 (P1/P2):** JuzzioPalette'in cam tokenlarına tam bağlanması, kullanıcı özel tema stüdyosu (renk seçici, adlandırma, içe/dışa aktarma — yerel), zamanlanmış tema.
- **Faz 3 (P2):** Admin Tema Stüdyosu (taslak/yayın/geri alma) — `app_config` için yeni sütun/tablo gerekir → **kullanıcı onayı**.
- **Faz 4 (P2):** RBAC (Moderator/Support/Auditor) — yeni rol tablosu + RLS → **onay**.
- **Faz 5 (P3):** `withOpacity` temizliği, kullanılmayan kod, responsive taşma denetimi (cihaz/emülatör gerekir).

## 6. Açıkça tamamlanmayanlar

Mesajlaşma/sosyal "özellik evreni" (§5–§8, §14), admin dashboard metrikleri, görsel regresyon ve E2E testleri, cihaz üzerinde responsive/performans ölçümleri bu fazda yapılmadı. Bunlar SDK/emülatör, veritabanı şema değişikliği (onay) veya harici servis gerektirir.

---

# Faz 2 — Advanced Theme Studio (v0.8.2)

## Mimari kararlar
- Tema motoru yeniden yazılmadı. Mevcut üç katmana kanca eklendi: `JuzzioGlassTokens` (cam/metin/buton/ikon/kenar), `JuzzioPalette` (ekran renkleri, balonlar), ortak `buildJuzzioDarkTheme` (ThemeData; ikon ve başlık rolleri eklendi). Aurora arka planı özel temadan üretilen palet ile çizilir.
- Özel temalar **kullanıcının yerel tercih dosyasında** saklanır (veritabanı değişikliği yok, migration yok). Şifreli Google Drive yedeği bu dosyayı zaten içerdiği için temalar telefon değişiminde geri gelir.
- Şema sürümlüdür (`schema: juzzio-theme`, `version: 1`); daha yeni sürüm temalar reddedilir, eksik alanlar güvenli varsayılanlarla tamamlanır.

## Uygulananlar
| # | İstek | Durum | Dosya |
| :-- | :-- | :-- | :-- |
| 1 | Sıfırdan tema | Yapıldı (koyu/açık şablon veya mevcut görünümden) | `theme_studio_page.dart` |
| 2 | HEX/RGB/HSL seçici | Yapıldı (alfa, WCAG kontrast göstergesi) | `widgets/glass/juzzio_color_picker.dart` |
| 3 | 13 renk rolü ayrı ayrı | Yapıldı: arka plan, 3 gradyan, metin, başlık, buton, buton yazısı, kart, giden/gelen balon, ikon, kenarlık | `core/theme/juzzio_custom_theme.dart` |
| 4 | Blur/opaklık/yoğunluk/gradyan | Yapıldı (blur 6–30, opaklık 4–70%, yoğunluk 60–140%, gradyan aç/kapa) | aynı |
| 5 | Canlı önizleme | Yapıldı: taslak tüm uygulamaya geçici uygulanır; kaydetmeden çıkınca geri döner | `theme_studio_page.dart` |
| 6 | Kaydet/adlandır/çoğalt/sil/varsayılana dön | Yapıldı (en fazla 30 tema, aynı ada otomatik numara) | `app_theme_and_locale.dart` |
| 7 | JSON içe/dışa aktarma | Yapıldı: pano; 16 KB sınırı, şema/sürüm/HEX/sayı doğrulama, ad temizleme | model + stüdyo |
| 8 | Otomatik gece/gündüz | Yapıldı: "Zamanlı" mod, saat seçici, gece yarısını aşan aralık, 30 sn kontrol | ayarlar + kontrolcü |
| 9 | Sistem teması | Korundu; sistem değişimi artık anında yansır (gözlemci) | `main.dart` |
| 10 | Tüm ekranlarda tutarlılık | Ortak tokenlar üzerinden (ekranlar kendi teması yok) | — |
| 11 | Yüksek kontrast | Tema + "Kontrastı artır" ayarı + işletim sistemi yüksek kontrastı; kontrast uyarıları | `main.dart`, tokenlar |
| 12 | Geçiş/flash | Tema animasyonu 320 ms (hareket azaltılınca 0), aurora çapraz geçiş, açılış öncesi yükleme | `main.dart`, `juzzio_aurora.dart` |
| 13 | Performans modu + düşük donanım | Korundu; Android `isLowRamDevice` veya < 3 GB RAM'de blur otomatik kapanır (kullanıcı seçimi öncelikli) | `MainActivity.kt`, `native_bridge.dart` |

## Faz 2 test durumu
| Test | Tür | Sonuç |
| :-- | :-- | :-- |
| `test/juzzio_theme_studio_test.dart` (19 test: JSON gidiş-dönüş, bozuk JSON, şema/sürüm, geçersiz HEX, eksik renk, sınır dışı değer, boyut, ad temizleme, kimlik doğrulama, 12 hazır tema kontrastı, token yönetimi, palet yeniden çizimi, zamanlama, CRUD + önizleme, kalıcılık anlık görüntüsü, içe aktarma, hazır tema geçişi) | Birim | NOT RUN (SDK yok) → CI |
| Mevcut 14 test dosyası (regresyon) | Birim | NOT RUN → CI |
| 12 hazır tema metin kontrastı | Python ile önceden hesaplandı | Tümü ≥ 16:1 (koyu) / ≥ 16:1 (açık) |
| Dart sözdizimi, const taraması, sır taraması | Statik | PASS |
| Responsive taşma, ekran/modal/bottom sheet görsel kontrolü, yeniden başlatma sonrası kalıcılık | Cihaz | NOT RUN (cihaz/emülatör gerekir) |

## Kalan sorunlar
- Bazı eski ekranlarda doğrudan yazılmış sabit renkler (ör. arama ekranı video üstü koyu cam, oyun ekranı) özel temadan bilinçli olarak etkilenmez.
- Yönetici Tema Stüdyosu (küresel tema yayınlama/geri alma) Faz 3: `app_config` için yeni alan gerekir → onay.

---

# v0.8.3 — Açık işlerin kapatılması (Autonomous Mega Evolution Directive)

## A. Geçmiş iddiaların kaynak kod üzerinden doğrulanması
Her iddia için kanıt satırı (`dosya:satır`) — 26/26 **VERIFIED IN SOURCE** (cihazda çalıştırma ayrıca gerekir):

| İddia | Kanıt |
| :-- | :-- |
| Cam dolgu/ışık ayrı katman | `lib/core/theme/juzzio_glass.dart:209` |
| Sohbet temaları gerçek renkler | `lib/core/app_theme_and_locale.dart:230` |
| Aydınlık modda ortak cam teması | `lib/main.dart:187` |
| Açılış öncesi tema yükleme | `lib/main.dart:72` |
| Temaya göre durum çubuğu | `lib/main.dart:174` |
| Bozuk tema → varsayılan | `lib/core/theme/juzzio_aurora.dart:320` |
| 12 hazır tema | `lib/core/theme/juzzio_aurora.dart:299` |
| Cam yoğunluğu ayarı | `lib/screens/settings_suite_screens.dart:4095` |
| Performans modu | `lib/screens/settings_suite_screens.dart:4114` |
| Düşük RAM blur fallback | `android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt:777` |
| Tema Stüdyosu (özel tema) | `lib/screens/theme_studio_page.dart:347` |
| HEX/RGB/HSL seçici | `lib/widgets/glass/juzzio_color_picker.dart:141` |
| JSON içe/dışa aktarma | `lib/core/theme/juzzio_custom_theme.dart:235` |
| Zamanlı gece/gündüz | `lib/core/app_theme_and_locale.dart:461` |
| Sistem görünümü gözlemcisi | `lib/main.dart:112` |
| Yüksek kontrast (tema+ayar+sistem) | `lib/main.dart:63` |
| Arama ekranı tema rengi | `lib/screens/call_screen.dart:1303` |
| Oyun ekranı tema rengi | `lib/screens/chick_game_screen.dart:363` |
| Küresel tema SQL | `supabase/juzzio_database.sql:10112` |
| RBAC SQL + RLS | `supabase/juzzio_database.sql:9926` |
| Yönetici tema stüdyosu UI | `lib/screens/admin_theme_studio_page.dart:29` |
| Hızlı yanıt Android | `android/app/src/main/kotlin/com/juzzio/app/JuzzioReplyReceiver.kt:android/app/src/main/kotlin/com/juzzio/app/MainActivity.kt` |
| Hızlı yanıt Dart (E2EE yolu) | `lib/services/juzzio_quick_reply.dart:4` |
| Çeviri CI kapısı | `.github/workflows/android-ci.yml:154` |
| Dil cihazlar arası senkron | `lib/screens/chat_screen.dart:386` |
| RTL dilleri | `lib/main.dart:130` |
## B. Bu sürümde kapatılan açık işler
| Açık iş | Durum | Uygulama |
| :-- | :-- | :-- |
| Arama ekranı video kontrolleri temaya uyum | Kapatıldı | `call_screen.dart`: tüm koyu cam yüzeyler `_callGlassTint`, vurgular `_callAccent` (özel temada buton rengi); video bulanıklaştırılmadı |
| Oyun ekranı tüm temalarla uyum | Kapatıldı | `chick_game_screen.dart`: alt pencere, başlık, butonlar ve ilerleme çubuğu tema tokenları; durum renkleri (aç/tok) anlamsal olarak korundu |
| Yönetici Tema Stüdyosu | Kapatıldı | `admin_theme_studio_page.dart` + SQL: taslak, hemen yayın, ileri tarihli zamanlama, sürüm geçmişi, geri alma (yeni sürüm olarak), arşiv, kontrast raporu |
| RBAC + SQL + RLS | Kapatıldı | `staff_roles`, `juzzio_role_permissions`, `juzzio_has_permission`, `_staff_require`, rol ver/al (yalnız süper yönetici, kendine rol yok), RLS: rol tablosu ve taslaklar yetkisiz kullanıcıya kapalı, doğrudan yazım engelli, denetim kaydı |
| Küresel tema istemci tarafı | Kapatıldı | Öncelik: önizleme › kullanıcının özel teması › kullanıcının seçtiği hazır tema › küresel tema (yalnızca takip edene). Ayarlar'da "Juzzio'nun önerdiği tema" anahtarı |
| 139+ dil | Doğrulandı + güçlendirildi | 144 dil kaydı, RTL (ar, fa, he, ur, ps, ckb, yi, sd, ug, dv), yeniden başlatmadan değişim (mevcut). Yeni: hesap dili yeni cihaza taşınır; `scripts/l10n_tools.py` CI kapısı (eksik/eskimiş çeviri → derleme durur). Kök neden düzeltmesi: `_t/_tr` yardımcıları taranmıyordu → katalog 1064 → 1216 metin |
| Bildirimden hızlı yanıt | Kapatıldı | Android `RemoteInput` eylemi (`MainActivity.displaySystemNotification`), `JuzzioReplyReceiver`: çalışan motor varsa ona, yoksa ekransız motora (`juzzioQuickReplyMain`) iletir; gönderim `SupabaseService.sendTextMessage` → E2EE korunur; bildirim "Gönderildi/Gönderilemedi" olarak güncellenir; 25 sn zaman aşımı |

## C. Hata kapısı kayıtları (bu sürümde yakalanıp kökten düzeltilenler)
1. SQL test bloğu sonuç vermedi → kök neden: test DB'sinde `pgcrypto.digest` farklı şemada → `search_path = public, extensions` ile düzeltildi, tüm paket tekrar çalıştırıldı.
2. `DO $$` blokları içinde psql değişkeni genişlemiyordu → yük `set_config/current_setting` ile geçirildi, tekrar çalıştırıldı.
3. Yerelleştirme kapısı v030 anahtarlarında yanlış alarm verdi → kök neden: `{n}` yer tutucuları ayrıştırıcıyı bozuyordu → satır bazlı ayrıştırma; negatif test (eksik çeviri eklenince kapının durduğu) doğrulandı.
4. Yerelleştirme kapısı 3 yeni metni yakaladı → kök neden: `_t/_tr` yardımcıları taranmıyordu → tarayıcı genişletildi, katalog yeniden üretildi, kapı temiz.
5. Test anlamlılığı: SQL testinde bir beklenti bilerek bozuldu → test `FAIL v3 aktif` ile durdu (testler gerçekten başarısızlığı yakalıyor), sonra geri alındı.

## D. Test sonuçları (gerçek / çalıştırılmayan ayrımı)
| Test | Ortam | Sonuç |
| :-- | :-- | :-- |
| Kanonik SQL: boş DB ×2, canlı benzeri DB ×2 | PostgreSQL (yerel) | **PASS** (gerçek çalıştırma) |
| SQL regresyon: v0.5.0 → v0.7.0 | PostgreSQL | **PASS** |
| SQL v0.8.3: RBAC, RLS, taslak gizliliği, yayın, zamanlama, geri alma, arşiv, doğrudan yazım engeli, denetim kaydı, rol geri alma (18 doğrulama + 8 negatif senaryo) | PostgreSQL | **PASS** |
| `scripts/l10n_tools.py check` (+ negatif test) | Python | **PASS** |
| Dart sözdizimi (tree-sitter), const taraması, sır taraması, dosya bütünlüğü | Yerel | **PASS** |
| `flutter analyze`, `flutter test` (yeni: `juzzio_v083_test.dart`, `juzzio_theme_studio_test.dart`) | Flutter SDK | **NOT RUN** (ortamda yok) → CI |
| Kotlin derlemesi (`JuzzioReplyReceiver.kt`, `MainActivity.kt`) | Gradle | **NOT RUN** → CI APK adımı |
| Hızlı yanıtın gerçek cihazda uçtan uca testi, ekran taşmaları, RTL görsel kontrolü | Cihaz | **NOT RUN** |

## E. Kalan / doğrulanamayan
- Eski yönetici RPC'leri (kullanıcı yönetimi, moderasyon vb.) hâlâ yalnızca süper yönetici oturumuyla çalışır (daha kısıtlayıcı = güvenli). Yeni RBAC izinleri şu an tema yayını ve rol listesi için uygulanıyor; diğer yönetici işlevlerinin izin bazlı açılması sonraki adım.
- 144 dilin metinleri makine çevirisiyle dil paketlerine üretilir; insan çevirisi kalitesi garanti edilmez.
- Direktifteki geniş ürün matrisi (§31: topluluklar, kanallar, keşif, yapay zekâ vb.) bu sürümde ele alınmadı.

---

# v0.8.4 — Liquid Glass tasarım ailesi, tema galerisi, CI analiz düzeltmesi

## A. CI hatası (hata kapısı)
- `error • The name 'num' isn't a type` (`juzzio_custom_theme.dart:291`). **Kök neden:** `fromMap` içindeki yerel `num(...)` yardımcı fonksiyonu Dart'ın `num` tür adını gölgeliyordu; aynı kapsamdaki `v is! num` ifadesi tür yerine fonksiyona çözülüyordu. **Düzeltme:** yardımcı `glassNum` olarak yeniden adlandırıldı. Tüm `lib/` ve `test/` içinde tür adlarını gölgeleyen başka bildirim taraması yapıldı: yok.

## B. Tasarım ailesi
- 12 tema tek bileşen setini (JuzzioGlass, cam butonlar, menüler, kartlar, alt gezinme, pencereler) paylaşır; yalnızca `JuzzioGlassCharacter` değişir: blur, opaklık, ışık yansıması (sheen), derinlik (gölge), kenar ışığı rengi ve neon parıltı.
- Uygulama: `JuzzioGlassTokens.characterResolver` → `_scaled` (opaklık), `baseBlur`, `shadow`, `sheen`; `JuzzioGlassBorderPainter` `rim`/`glow`. Özel tema (Tema Stüdyosu) etkinken karakter devre dışı kalır, kullanıcının kendi değerleri geçerlidir.

## C. Hem uygulama hem sohbet teması
- `setChatPalette(id)`: 12 cam paleti sohbet teması olarak seçilir (doğrulanır, kullanıcı tercihlerine `chatPalette` olarak kaydedilir, cihazlar arası senkron mevcut tercih yolundan). Klasik ön ayar seçilince palet temizlenir.
- Ayarlar › Görünüm: "Uygulama arayüz teması" (12 kart: canlı aurora, ad, karakter açıklaması → önizleme + Uygula) ve "Sohbet teması" (12 cam + 16 klasik, dokununca uygulanır) galerileri. Sohbet teması sayfasına da aynı galeri eklendi.
- **Bulunan hata:** parlaklık kaydırıcısı `setChatTheme(index, intensity)` çağırıyordu ve seçili cam paletini sıfırlıyordu → `setChatThemeIntensity` ayrıldı, testle sabitlendi.
- **Bulunan hata:** açık renkli paletlerde (Cam Beyaz, Krom, Lavanta, Gül Kuvars, Zümrüt) giden balonda beyaz yazı kontrastı 3.4–3.96:1 idi → ton parlaklığı (luminance ≤ 0.12) olana dek koyulaştırılıyor. Yeniden hesap: tüm 12 palet × açık/koyu × yoğunluk 0.6/1.0/1.4 → en kötü 4.54:1 (WCAG AA ≥ 4.5). Aynı kontrol `juzzio_v084_test.dart` içinde.
- Karakter açıklamaları TR/EN/DE yerleşik; `l10n_tools.py` artık `JuzzioGlassCharacter(en: …)` metinlerini de kataloğa alıyor (1218 → 1231 metin, 144 dil).

## D. Test sonuçları
| Test | Sonuç |
| :-- | :-- |
| Kanonik SQL ×4 + regresyon v0.5.0 → v0.8.3 (SQL değişmedi) | **PASS** (gerçek PostgreSQL) |
| `l10n_tools.py check`, `check_secrets.py`, `release_meta.py check`, `verify_tree.py` | **PASS** |
| Dart sözdizimi (tree-sitter, 0 hata), const taraması, parantez dengesi, tanımsız özel ad taraması | **PASS** |
| Balon kontrast hesabı (Python ile Flutter formülünün yeniden üretimi) | **PASS** (min 4.54:1) |
| `flutter analyze`, `flutter test` (yeni `juzzio_v084_test.dart`: 5 test) | **NOT RUN** (ortamda Flutter SDK yok) → CI |
| Görsel kontrol (galeri taşmaları, açık/koyu, RTL) | **NOT RUN** (cihaz yok) |
