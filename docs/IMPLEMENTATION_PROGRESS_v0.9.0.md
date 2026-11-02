# Juzzio v0.9.0 — Uygulama İlerleme Kaydı (devam noktası)

Bu dosya, `apply prompt/` içindeki iki talimat dosyasının (ChatGPT master prompt +
ürün genişletme eki, Gemini bulgu listesi) uygulanma durumunu tutar. Oturum
kesilirse **"devam et"** komutuyla en üstteki `ŞU AN` satırından devam edilir.
Hiçbir madde yalnızca arayüzü olduğu için "tamam" sayılmaz: backend + RLS +
hata durumları + test + l10n + 12 tema uyumu gerekir.

## ŞU AN
- ✅ TÜM AŞAMALAR TAMAM (C-A6 dahil). Sürüm 0.9.0 (+90). ZIP teslim edildi. Kalan tek dış adım: GitHub'a gönderim ve CI'da Flutter derlemesi (bu ortamda proxy 403).
- Sayaç: SQL 20 blok PASS (yerel PG16); Edge birim 13/13 PASS; Dart 30 test dosyası (CI'da).

## Doğrulama ortamı (gerçek)
| Kontrol | Araç | Durum |
| :-- | :-- | :-- |
| Kanonik SQL ×2 (idempotent) + `supabase/tests/juzzio_database_tests.sql` | Yerel PostgreSQL 16 — `bash scripts/sql_test.sh` | Gerçek çalıştırma |
| Python kapıları (`check_secrets`, `verify_tree`, `release_meta check`, `l10n_tools check`) | Python 3 | Gerçek çalıştırma |
| Edge Function sözdizimi/tip | `tsc --noEmit` (Deno tipleri taklit) | Kısmi |
| `flutter analyze / test / build apk` | Flutter SDK | **NOT RUN yerelde** — bu çalışma ortamında Flutter/Dart indirilemiyor (storage.googleapis.com, pub.dev engelli). Gerçek sonuç GitHub Actions'ta |
| Cihaz/emülatör testleri | — | **NOT RUN** |

## Faz durumu
| Faz | Kapsam | Tamamlanma kriteri | Durum |
| :-- | :-- | :-- | :-- |
| 0 | Baseline: denetim, Python kapıları, SQL test iskeleti | Tüm baseline kontrolleri koşar ve sonuç kayıtlı | ✅ (SQL 97 doğrulama PASS, Python 4/4 PASS) |
| 1a | CI/yayın: yıkıcı silmeler kaldırılır, dağıtım tüm kapılara bağlanır, SQL testleri CI'da, push betikleri geçmişi korur | YAML geçerli, guard testi geçer | ✅ yerel: ci_guards PASS, YAML PASS, push.sh 4 senaryo (ilk push, CI commit'i ile çakışma, ayrık HEAD, squash) PASS; push.bat CRLF + aynı mantık (Windows'ta NOT RUN) |
| 1b | Backend güvenlik (Gemini backend bulguları + storage gizliliği + RBAC yayılımı + storage temizliği) | SQL testleri (pozitif+negatif) PASS, tsc PASS | ⏳ |
| 1c | İstemci güvenlik (E2EE fail-closed, OTA SHA-256, GTX seli, tercih debounce, picker arka planı, kırpıcı zoom, PQ isolate) | Dart değişiklikleri + birim testleri; CI'da analyze/test | 🟡 kod + testler yazıldı; yerel: sözcük denetimi PASS; analyze/test/build CI'da (NOT RUN yerelde) |
| 2 | 5 sekmeli kabuk + Android çift geri çıkış durum makinesi | Durum makinesi birim testleri | 🟡 `lib/core/juzzio_back_navigation.dart` (saf durum makinesi: emoji paneli → sohbetten çık → Sohbetler sekmesi → Tümü filtresi → ipucu → 2 sn içinde çıkış) + `PopScope` + engellemeyen `IgnorePointer` ipucu (canlı bölge, azaltılmış hareket); dock: Sohbetler·Keşfet·Oluştur·Aramalar·Profil. Eski hata: sohbet içindeyken geri tuşu uygulamayı kapatıyordu. 5 birim testi `test/juzzio_back_navigation_test.dart`. CI'da |
| 3 | F3-01 … F3-21 özellik dilimleri (aşağıda) | Her biri: SQL+RLS+test, servis, UI, l10n, tema | ⏳ |
| Son | Kapanış matrisi, belgeler, sürüm, ZIP | Tüm kapılar | ⏳ |

## Faz 3 özellik listesi (hiçbiri kapsam dışı bırakılmaz)
F3-01 Shorts · F3-02 Creator Studio + Analytics · F3-03 İçerik takvimi/planlı gönderi ·
F3-04 Profil kişiselleştirme + rozetler · F3-05 Dil ve Çeviri Merkezi ·
F3-06 Erişilebilirlik Merkezi · F3-07 Dijital Denge · F3-08 Evrensel arama + komutlar ·
F3-09 Planlı görüşmeler · F3-10 Canlı Odalar · F3-11 Bildirim merkezi + profiller (DND) ·
F3-12 Civciv Merkezi · F3-13 Koleksiyonlar/kaydedilenler · F3-14 Kişiler ve Arkadaşlar Merkezi ·
F3-15 Konular/etiketler · F3-16 Notlar + hatırlatıcılar · F3-17 Çevrimdışı + güvenli kuyruk ·
F3-18 Depolama + medya arşivi · F3-19 Yönetici analiz/moderasyon/destek ·
F3-20 Geçiş + geri navigasyon optimizasyonu · F3-21 Büyük dosya modülerleştirme ·
ayrıca ek talimattaki: sohbet klasörleri/filtreleri, Sohbet Bilgileri, Sohbet Medya Merkezi,
Topluluklar/Kanallar, Etkinlikler, Anket/Soru-Cevap, Taslaklar, Güvenlik Merkezi.

## Gemini kaynak denetimi maddeleri (G01–G36, her biri ayrı görev)
Durum işaretleri: ⏳ bekliyor · 🔧 sürüyor · ✅ kod+test tamam · 🟡 kod tamam, doğrulama CI'da (NOT RUN yerelde) · ❌ geçersiz bulgu (kanıtlı)

| # | Madde | Dosya / fonksiyon | Tamamlanma kriteri | Durum |
| :-- | :-- | :-- | :-- | :-- |
| G01 | can_join_livekit_room ban + call_removals | SQL | negatif SQL testi PASS | ✅ Kaynakta yasak+call_removals ZATEN vardı (Bölüm 7, can_join_livekit_room) — Gemini eski tanımı okumuş. Kalan açık kapatıldı: bitmiş 'answered' kayıt 12 saat token veriyordu. SQL testleri + mutasyon testi PASS |
| G02 | content-moderation canUseRoom / deleteRoom | content-moderation/index.ts | yalnız aktif+çıkarılmamış çağrı; tsc PASS | ✅ SQL `juzzio_is_active_call_participant` + content-moderation; yaptırım yalnız etkin katılımcıya; SQL testi PASS, tsc PASS |
| G03 | UUID doğrulaması | _shared/auth.ts `isUuid` | tüm kullanıcı girdili sorgular | ✅ `_shared/auth.ts isUuid/UUID_RE`; content-moderation, get-livekit-token, translate-bridge |
| G04 | voice_note oda üyeliği | translate-bridge + SQL RPC | üye değil → 403; SQL testi | 🟡 Sunucu ✅ (8 SQL testi PASS); istemci artık `storagePath` gönderir (eski istemcilerin URL'si de sunucuda yola çevrilip doğrulanır). Dart: sözcük denetimi PASS, derleme CI'da |
| G05 | deepgram_token aktif arama + ban | translate-bridge + SQL RPC | SQL testi | ✅ SQL `juzzio_can_use_live_captions` + translate-bridge; SQL testi PASS |
| G06 | invite_to_call sınır + ban | SQL | SQL testi | ✅ Sınır (call_full) ve davet edilenin yasağı ZATEN vardı; eklenen: davet edenin yasağı, bitmiş/çıkarılmış davet eden, çıkarılan kişinin yeniden daveti, 16 kişi tavanı; SQL testi PASS |
| G07 | get_or_create_dm_room ban | SQL | SQL testi | ✅ GEÇERSİZ BULGU — `account_banned` kontrolü kaynakta zaten var (get_or_create_dm_room, Bölüm 8). Değişiklik yapılmadı; regresyon testi eklendi (PASS) |
| G08 | push-webhook stale kilit | push-webhook + SQL RPC | atomik devralma testi | ✅ SQL `juzzio_claim_stale_push_delivery` (FOR UPDATE SKIP LOCKED) + push-webhook; 4 SQL testi PASS |
| G09 | FCM kontrollü paralel | push-webhook | sınırlı eşzamanlılık | ✅ push-webhook: FCM_CONCURRENCY=5, istek başına 10 sn zaman aşımı, tek cihaz hatası diğerlerini durdurmaz; tsc PASS |
| G10 | username-login timing/sızıntı | auth-username-login | sabit gecikme, genel hata | ✅ ≥900 ms + sapma, tüm kimlik hataları tek kod; IP özeti başına hız sınırı. Not: GoTrue 'onaylanmadı' yanıtını yalnızca doğru şifreden sonra verir — yine de ayrı kod kaldırıldı |
| G11 | LiveKit ortak modül | _shared/livekit_admin.ts (TypeScript; talimattaki ".dart" uzantısı yanlış) | kopya kod yok | ✅ get-livekit-token kopya JWT/HTTP kodu kaldırıldı; `_shared/livekit_admin.ts` tek imzalama yolu |
| G12 | batch_ui + sunucu önbelleği | translate-bridge + istemci | istemci önce sunucu, yedek ≤2 işçi | 🟡 Sunucu ✅; istemci önce `batch_ui` (yer tutucular maskelenir), yalnız sunucu yoksa ≤2 işçi + üstel geri çekilme. Birim testi `juzzio_v090_test.dart`. Derleme/test CI'da |
| G13 | OTA SHA-256 | app_theme_and_locale.dart | uyuşmazlıkta silinir; birim testi | 🟡 Akış hâlinde SHA-256 (cryptography Sha256 HashSink), ML-DSA doğrulanmış version.json özetiyle sabit zamanlı karşılaştırma; özet yoksa kurulum reddedilir; uyuşmazlıkta dosya silinir. 3 birim testi. CI'da çalışacak |
| G14 | Tercih atomik + 400 ms debounce | app_theme_and_locale.dart | tmp+rename, debounce | 🟡 400 ms debounce + .tmp→rename atomik yazım + yazım zinciri; kullanıcı değişmeden/geri yükleme öncesi/arka plana geçişte flush. CI'da |
| G15 | Dil seçici arka planı | JuzzioLanguagePickerSheet | opak cam yüzey | 🟡 Sheet cam rengi + BackdropFilter; azaltılmış efektte opak yüzey. CI'da (görsel kontrol cihazda NOT RUN) |
| G16 | Kırpıcı pan koruma | JuzzioImageCropperModal | odak noktası korunur | 🟡 Odak noktası korunarak ölçekleme (saf fonksiyon `zoomAroundFocal`, deprecated Matrix4.scale yok); 2 birim testi. CI'da |
| G17 | PQ Isolate | juzzio_pq.dart | *Async API + çağıranlar | 🟡 `JuzzioPqAsync` (Isolate.run): keyPairFromSeed/encapsulate/decapsulate/verify; E2EE ve OTA çağrıları async sürümde. KAT eşdeğerlik testleri. CI'da |
| G18 | withOpacity temizliği | lib/ (98 yer) | grep = 0 | 🟡 102 `withOpacity` → `withValues(alpha:)` (lib 98 + test 4); kalan 0. Kod tabanında zaten 130 `withValues` kullanımı vardı (SDK destekliyor). CI analyze ile doğrulanacak |
| G19 | Kullanılmayan kod | call_screen / chat_screen | referans yok kanıtı | ✅ `_checkInitialForeignPresence` tek referansı tanımıydı → kaldırıldı. `pendingCount` kaynakta YOK (bulgu eski, ❌ geçersiz) |
| G20 | Tüm admin RPC'lerinde RBAC | SQL | RPC başına izin testi | ✅ 47 admin RPC `_admin_require` → `_staff_require(p_token,'izin')`; süper yönetici hâlâ şifreli oturum ister; geçersiz belirteçte eski hata kodu korunur (istemci uyumu) |
| G21 | 5 rol izni | SQL + admin_panel_screen | rol başına izin/ret testi | 🟡 Sunucu ✅ (35 durumluk matris PASS). İstemci: personel şifresiz girer, sekmeler izne göre, veri yüklemeleri izne göre; Ayarlar'da personele de görünür. CI'da |
| G22 | Storage temizliği | SQL tetikleyici/cron | SQL testi | ✅ Kuyruk + tetikleyiciler (gönderi/hikâye/mesaj/sesli not/hesap) + süresi dolan içerik temizliği (pg_cron) + `storage-cleanup` Edge Function + saatlik `maintenance.yml`; 15 SQL testi PASS |
| G23 | AES-256-GCM E2EE medya | Dart medya servisi | şifreli yükleme | 🟡 `juzzio_media_crypto.dart`: dosya başına rastgele 256-bit anahtar + 96-bit nonce, AAD; birebir sohbette FOTOĞRAF cihazda şifrelenip `.jenc` (octet-stream) olarak yüklenir, şifrelenemezse GÖNDERİLMEZ; mesaj yazılamazsa yetim dosya silinir; `JuzzioEncryptedImage` imzalı URL → indir → doğrula → bellekte göster (hesaba bağlı önbellek, diske yazılmaz). 6 Dart testi. **Sınır:** video/ses/belge henüz şifresiz (100 MB bellek içi şifreleme ve akışlı oynatma ayrı iş); gruplar metinle aynı kuralla E2EE değil |
| G24 | Anahtar+SHA-256 zarfı | juzzio_e2ee.dart | bütünlük başarısızsa kapalı | 🟡 {k,n,h,mime} mesajın E2EE zarfının İÇİNDE ('m'; eski istemciler yok sayar); açılışta önce SHA-256 sonra GCM etiketi; biri tutmazsa kilit simgesi (fail-closed) |
| G25 | Kanallar + topluluk odaları | SQL + sayfalar | RLS testleri | ✅ MEVCUT (`rooms.is_channel`, `create_group_room(p_is_channel)`); yeniden yapılmadı (konsolidasyon kuralı) |
| G26 | Sohbet anketleri | SQL + sohbet UI | oy tekilliği, gizli oy testi | 🟡 SQL 10.23 `polls`/`poll_votes` (istemci yazamaz; oylar yalnız sahibine görünür), `create_poll` (yalnız grup, 2–10 benzersiz seçenek, mesaj olarak), `vote_poll` (tekil/çoklu, kapalıya yok), `close_poll` (yalnız oluşturan), `poll_results` (gizlide seçmen yok). Sohbet ek menüsü → Anket; balonda canlı kart. SQL testleri PASS, 5 Dart testi |
| G27 | Zamanlanmış mesaj | SQL + cron + UI | idempotent işçi testi | 🟡 SQL 10.23 `scheduled_messages`; birebirde yalnız E2EE zarf kabul (düz metin reddedilir), gönderimde yazma hakkı yeniden denetlenir (`juzzio_can_post`), işçi FOR UPDATE SKIP LOCKED + `client_msg_id`, pg_cron her dakika; ek menü → Mesajı zamanla (tarih/saat, bekleyenler, iptal). SQL testleri PASS |
| G28 | Sesli mesaj hız | sohbet UI | 1x/1.5x/2x | 🟡 sesli balonda hız düğmesi (çalan sese anında `setSpeed`) |
| G29 | Waveform | kayıt + balon | örnekler meta veride | ✅ MEVCUT (`waveformPeaks` kayıtta toplanır, balonda çizilir) |
| G30 | Civciv evrimi | SQL + oyun UI | sunucu doğrulamalı, SQL testi | SKIPPED — konsolidasyon §1.1: mevcut Civciv yalnız hata düzeltmesi alır; yeni oyun/ekonomi yok |
| G31–G33 | SQL testleri (kapsam, negatif yetki, storage temizliği) | tests/*.sql | ilgili maddelerle | ✅ 167 doğrulama (9 blok) |
| G34–G36 | Dart testleri (E2EE medya, PQ isolate, yeni özellikler) | test/*.dart | ilgili maddelerle | ⏳ |

## Ek paket (2026-11-01 23:27): Canlı durum, etiketleme, gelişmiş Android bildirimleri
| # | Madde | Tamamlanma kriteri | Faz | Durum |
| :-- | :-- | :-- | :-- | :-- |
| N-A | Yazıyor... (animasyonlu) / Ses kaydediliyor.. (statik) / Çevrimiçi / Son görülme — tek merkezi öncelik çözümleyici | Realtime yayını + 3 sn TTL + gizlilik/engel; birim testleri | C-A2 | 🟡 SQL 10.12 `juzzio_can_room_activity` + realtime.messages RLS (yalnız etkin üye; DM'de engel iki yönü kapatır; çevrimiçi gizliliği 'nobody' veya karşı taraf göremiyorsa yayın yok) — 13 SQL testi PASS + mutasyon testi yakaladı. Dart: `lib/core/juzzio_chat_activity.dart` (öncelik kaydediliyor>yazıyor>çevrimiçi>son görülme, 3 sn TTL, 2 sn canlı tutma, 4 sn sonra yazma biter, sahte kimlik/kendi kimliği yok sayılır) + `lib/services/juzzio_chat_activity_service.dart` (özel kanal `room-activity:<oda>`, yükte metin yok) + başlıkta animasyonlu nokta (azaltılmış harekette sabit), grupta isim, ekran okuyucu canlı bölge. 9 birim testi `test/juzzio_chat_activity_test.dart`. Flutter/CI'da; gerçek Realtime üzerinde cihaz testi NOT RUN |
| N-B | @etiketleme (gönderi, yorum, yanıt, hikâye, paylaşım) | content_mentions + RLS + izin tercihleri + öneri RPC + tıklanabilir token + idempotent bildirim + SQL testleri | C-A2 | 🟡 SQL 10.17: `content_mentions` (RLS: yalnız yazar/etiketlenen okur; istemci yazamaz), sunucu tarafı ayrıştırıcı `juzzio_extract_mentions` (≤10/içerik), `juzzio_can_mention` (engel + `privacy_mentions` everyone/friends/nobody), görünürlük kontrolü (göremediği içerik için etiket yok), saatte 60 bildirim sınırı, düzenlemede yeniden bildirim yok; tetikleyiciler: gönderi, yorum/yanıt, hikâye; `suggest_mentions` (joker güvenli), `set_my_mention_privacy`; 'mention' bildirim türü + push metinleri (tr/en/de) + beğeni/yorum kategorisine bağlı. 13 SQL testi PASS. Dart: `lib/widgets/juzzio_mentions.dart` (aynı kural; tıklanabilir etiket → profil; yazarken öneri şeridi) — akış açıklaması, yorumlar, yorum girişi, gönderi/hikâye açıklaması; Gizlilik'te 'Beni kim etiketleyebilir'; bildirime dokununca gönderi (RLS ile görünürse) yoksa profil. 6 Dart testi |
| N-C | Sosyal bildirimler (beğeni, yorum, yanıt, kaydetme [varsayılan gizli], takip, arkadaşlık, paylaşım, hikâye yanıtı, davet, moderasyon) | Mevcut olanlar doğrulanır, eksikler eklenir; tekrar yok; kategori tercihi | C-A2 | 🟡 Mevcut: beğeni/yorum/yanıt/takip/arkadaşlık/hikâye/tepki tetikleyicileri + kategori anahtarları (push-webhook'ta uygulanır). Düzeltilen: kaydetme bildirimi artık **varsayılan KAPALI** (`profile_private.notify_post_saves`, `set_my_save_notifications`), Ayarlar'da anahtar — 5 SQL testi PASS. Etiketleme bildirimi N-B ile gelecek |
| N-D | Bildirimde mesaj içeriği — E2EE: FCM yükünde düz metin YOK; cihazda çözülür; çözülemezse genel metin | Önizleme kipleri + kilit ekranı | C-A2 | 🟡 Kip: full / sender / hidden (cihaz başına; `user_push_tokens.notify_preview` + `set_my_push_preview` RPC, yalnız kendi cihazı). push-webhook mesaj olaylarını data-only gönderir, hidden'da gönderen adı/kimliği de çıkar (`_shared/push_preview.ts`, 9 birim testi PASS). Android: 'full'de `JuzzioNotificationDecryptor` mesajı kullanıcının oturumuyla (RLS) okur ve cihazda çözer (canlı motor veya ekransız `juzzioNotificationPreviewMain`, 7 sn sınır) — çözülemezse genel metin; kilit ekranı VISIBILITY_PRIVATE + genel public sürüm. Ek düzeltme: tepki bildirimleri şifreli metnin ilk 80 karakterini önizlemeye kopyalıyordu → `notifications` BEFORE trigger'ı `juzzio_e2ee_` içeren önizlemeyi 🔒 yapar (eski kayıtlar da). SQL 8 test PASS; Dart 8 test `test/juzzio_notification_preview_test.dart` (CI). Kotlin derlemesi + cihaz testi NOT RUN |
| N-E | RemoteInput hızlı yanıt (uygulama açılmadan, idempotent, fail-closed) | Mevcut JuzzioReplyReceiver doğrulanır/sertleştirilir | 1c + 3 | 🟡 Kotlin her yanıta tek `client_msg_id` üretir, canlı motordan ekransız motora düşüşte aynı kimlik; Dart `{ok,status}` döner; E2EE yapılamazsa gönderilmez (`e2eeUnavailable`), zaman aşımı "doğrulanamadı" olarak gösterilir; kilit ekranında yanıt metni gizli (VISIBILITY_PRIVATE + public sürüm). 6 Dart birim testi `test/juzzio_quick_reply_test.dart`. Kotlin derlemesi CI'da (NOT RUN yerelde) |
| N-F | Gelen arama bildirimi Kabul/Reddet (CallStyle, full-screen intent) | Sunucuda çağrı geçerliliği; Kabul gerçekten katılır | C-A2 | 🟡 Kotlin: `NotificationCompat.CallStyle.forIncomingCall` + Kabul (uygulamayı açar, `call_action=accept`) + Reddet (`JuzzioCallActionReceiver`, uygulamayı açmadan); manifest'e eksik `USE_FULL_SCREEN_INTENT` izni eklendi; `androidx.core:core:1.13.1`. SQL `juzzio_decline_call` (yalnız aranan, yalnız çalan arama, idempotent) — 6 SQL testi PASS. Dart: Kabul bekleyen çağrı kimliği 30 sn tutulur, akışta gelince normal cevaplama yolu (sunucu doğrular); sessiz kip Kabul'ü düşürmez. 3 Dart testi. Kotlin derleme + cihaz NOT RUN |
| N-G | Sohbetler ekranındaki hızlı yanıt bandının kaldırılması | Yalnızca o bant + durumu; composer korunur | 2 | 🟡 `_headsUpMessage`, `_quickReplyCtrl`, `_isSendingQuickReply`, `_sendQuickReplyFromBanner`, `_buildQuickReplyMessageBanner` ve artık kullanılmayan `_messagePreviewLabel` kaldırıldı; gelen mesaj artık bant için çevrilmiyor. Sohbet composer'ı, arkadaşlık/arama bantları ve sistem bildirimleri korunur. CI'da |
| N-H | Bildirim ayarları (mesaj/arama/sosyal/gizlilik) | Kalıcı + senkron + push-webhook'ta uygulanır | C-A2 | 🟡 Mevcut kategori anahtarları doğrulandı (cihaz kaydında, webhook filtreler). Eklenen: önizleme kipi (gizlilik), kaydetme opt-in, sohbet bazlı ayar (§6.4): `set/get_room_notification_prefs` (süreli/süresiz sessiz, önizleme yalnız daha gizli, titreşim) + `after_new_message` süreli sessizi uygular — 8 SQL testi PASS; Android'de kilit ekranı GİZLİ + titreşimsiz kanal varyantı (Android 8+ kanal ayarı bildirimi ezdiği için; özel ton korunur). Arayüz: Sohbet Bilgileri ve Grup sayfasında 'Bildirimleri özelleştir' |
N-I (testler) ve N-J (tasarım: 12 tema, RTL, erişilebilirlik, performans modu) tüm N maddelerinin kabul kriteridir.

## Ek paket (2026-11-01 23:44): Personal / Business ikili deneyim (tek uygulama, tek kimlik)
Kaynak: kullanıcı eki "UNIVERSAL ECOSYSTEM + PERSONAL / BUSINESS DUAL EXPERIENCE" (tamamı okundu, 21 bölüm).
Sıra: mevcut Faz 2 → Faz 3 → B0…B11 → Son. Çakışanlar tek kez yapılır (F3-02 ↔ B6 Creator Studio,
F3-19 ↔ B19 admin, F3-08 ↔ Evrensel arama, F3-11 ↔ bildirim merkezi) ve iki tabloda da işaretlenir.
Değişmez kurallar: E2EE anahtarları/akışı Business geçişinde DEĞİŞMEZ; kişisel sohbet müşteri paneline
aktarılmaz; client `business_active` yazamaz (durum makinesi yalnız SECURITY DEFINER RPC); hukuki
metinler `DRAFT - LEGAL REVIEW REQUIRED`; sahte istatistik/ilerleme yok; ücretli API/GPU gerektirenler işaretlenir;
oyun/turnuva/sanal para/yeni evcil hayvan GELİŞTİRİLMEZ (envanterde "kapsam dışı").

| # | Madde | Tamamlanma kriteri | Durum |
| :-- | :-- | :-- | :-- |
| B0 | Envanter: 65 modül + alt özellikler + 40 yeni özellik → Personal/Business/Both/Business Optional/Admin Only/Future | `docs/FEATURE_INVENTORY_v0.9.0.md` + `feature_registry` tohum verisi aynı kaynaktan; hiçbir madde atlanmaz | ⏳ |
| B1 | Hesap modu mimarisi: `account_modes` (9 durum), merkezi feature registry (SQL + Dart), business_profiles (6 tür), işletme rolleri (Owner…Analyst) | Durum geçişleri yalnız RPC; RLS; kiracı izolasyonu SQL testleri | ⏳ |
| B2 | Hukuk & onay: belge sürümleri (14 belge taslağı), ayrı onaylar (zorunlu sözleşme ≠ açık rıza ≠ pazarlama), değiştirilemez onay kaydı + geri alma, yeniden onay | Onaysız başvuru tamamlanamaz; geri alma testi; ön işaretli kutu yok | ⏳ |
| B3 | Geçiş deneyimi: tanıtım, başvuru sihirbazı, 7 gerçek hazırlık adımı (sunucu adım kaydı), azaltılmış animasyon, kaldığı yerden devam, idempotent | Uygulama kapanınca devam; çift başvuru yok; sonsuz yükleme yok | ⏳ |
| B4 | Business dashboard + navigasyon + profil + modül tercihleri; avatar menüsünden mod geçişi (yeniden başlatmadan) | Gerçek sayımlar RPC'den; kullanılmayan modül gizli | ⏳ |
| B5 | Customer Inbox + ekip RBAC + atama/devir + notlar + hazır yanıt + mesai dışı yanıt + talep | Ekip üyesi yetkisiz konuşmayı göremez (SQL testi); E2EE kişisel sohbet aktarılmaz | ⏳ |
| B6 | Creator Studio + analitik (gerçek veri, demo etiketli), planlı paylaşım | Sahte metrik yok | ⏳ |
| B7 | Business AI Center (izinli, kota/maliyet yönetimi, E2EE içeriği izinsiz gönderilmez) | Harici servis yoksa "yapılandırılmadı" durumu | ⏳ |
| B8 | Automation (trigger/condition/action, döngü+spam koruması, yürütme geçmişi) + Integration Hub + Mini Apps izin manifestosu (kod çalıştırma YOK) | Döngü/hız sınırı SQL testleri; webhook imzası | ⏳ |
| B9 | Güvenlik paneli, raporlar, denetim kayıtları, veri taşınabilirliği | Audit log değiştirilemez | ⏳ |
| B10 | Kalan katalog (envanterdeki Personal/Both maddeleri öncelik sırasıyla) | Envanterde her madde: durum + gerekçe | ⏳ |
| B11 | Business→Personal dönüş (görünüm geçişi ≠ geçici devre dışı ≠ kapatma; veri silinmez), admin başvuru yönetimi, son entegrasyon | Dönüşte veri silinmez SQL testi; admin işlemleri audit'li | ⏳ |

## Son talimat (2026-11-02): Konsolidasyon — ÖNCELİKLİ, önceki eklerle çakışırsa bu geçerli
Kural: önce mevcut kodu incele; yoksa ekle, eksikse tamamla, hatalıysa düzelt; ikinci ekran/servis/tablo yok.
Yasaklılar: `docs/EXCLUDED_FEATURES.md` (34 madde SKIPPED; oyun/ekonomi dahil). Takip dosyası olarak BU dosya
kullanılır (talimat §16 "mevcut takip dosyaları varsa onları kullan"); yalnız EXCLUDED_FEATURES.md yeni.

Çakışma kararları:
- Faz 2 dock'u (Sohbetler·Keşfet·Oluştur·Aramalar·Profil) → **Ana Sayfa·Sohbetler·Keşfet·Bildirimler·Profil** olarak değiştirildi. Oluştur, Aramalar, Yeni sohbet, Arkadaşlar, Ara, Civciv Ana Sayfa kısayollarında; Bildirimler mevcut `JuzzioNotificationsFeedPage` gömülü kipte (ikinci bildirim ekranı yok).
- Business eki B4/B5/B6/B9: Business 5 sekme = Genel Bakış·Gelen Kutusu·Müşteriler·İş Alanı(Randevular, Hizmetler, Ekip, Görevler, Analizler, Otomasyonlar)·Profil.
- B7 ayrı "Business AI Center" ve B8 Mini Apps/Integration Hub: ayrı ana modül olarak **ertelendi** (§5'te yeri yok, "şişirme" yasağı); otomasyon yalnız İş Alanı > Otomasyonlar + Gelen Kutusu > Otomatik Yanıtlar. B10 katalog: yalnız bu talimatta adı geçenler.
- F3 listesi: F3-01 Shorts, F3-10 Canlı Odalar, F3-12 Civciv Merkezi (yeni oyun içeriği) yeni geliştirme olarak SKIP değil ama yeni sekme açılmaz; Civciv yalnız hata düzeltme. F3-11 bildirim merkezi = mevcut sayfa (✔ sekme olarak bağlandı).

| # | Aşama / madde | Konum | Durum |
| :-- | :-- | :-- | :-- |
| C-A1 | Mevcut durum analizi + yasaklı SKIP | docs | ✅ EXCLUDED_FEATURES.md, repo taraması temiz |
| C-NAV | Personal 5 sekme + Ana Sayfa (yalnız gerçek veri) + geri tuşu kökü Ana Sayfa | chat_screen, juzzio_back_navigation | 🟡 kod + 5 durum makinesi testi; CI'da |
| C-A2 | Mesaj bildirim önizleme/gizleme, RemoteInput (✔ N-E), gelen arama Kabul/Reddet, sosyal bildirimler, sohbet bazlı bildirim ayarları (ses/titreşim/önizleme/sessize alma süresi) | FCM + Kotlin + Sohbet Bilgileri | ⏳ |
| C-A3a | Yaşam Merkezi: görev + hatırlatma + takvim (Ana Sayfa > Görevlerim/Takvimim) | tek tablo + RLS | 🟡 SQL 10.18 `life_tasks` (RLS yalnız sahibi; sahiplik/bağlam güncellemede değişmez; idempotent istek kimliği; 2000 açık görev sınırı) + `juzzio_fire_due_reminders` (pg_cron her dakika, FOR UPDATE SKIP LOCKED, tekrar yok; zaman değişince yeniden) + 'reminder' bildirimi/push metinleri. `lib/screens/life_center_page.dart`: liste (gecikmiş/bugün/yaklaşan/tarihsiz), takvim, tamamlananlar, ekle/düzenle/sil(onaylı), hatırlatma seçenekleri; Ana Sayfa: Görevlerim/Takvimim/Hatırlatma Ekle + gerçek görev özeti. **Not:** hatırlatmalar Supabase'de pg_cron eklentisi açıksa çalışır (yoksa SQL bildirim verir; kurulum notu) |
| C-A3b | Mesaja hatırlatıcı (uzun bas > Hatırlat) | aynı hatırlatma altyapısı | 🟡 Aynı tablo (kind=message_reminder); üyelik tetikleyicide; mesaj METNİ sunucuya kopyalanmaz, bildirim metinsiz; 1 saat / bu akşam / yarın / özel; düzenle/iptal; bildirime dokununca sohbet |
| C-A3c | Kayıtlı mesajlar (uzun bas > Kaydet; karşı tarafa bildirilmez) | mevcut koleksiyon/kayıt altyapısı kontrol edilir | 🟡 Mevcut 'yıldız' yalnız cihazdaydı ve listesi yoktu → `saved_messages` (RLS; ekleme üyelik + mesaj/oda eşleşmesi şartlı; bildirim yok); uzun bas > Kaydet/Kaydı kaldır; Sohbet Bilgileri ve Grup sayfasında 'Kayıtlı mesajlar' (cihazda çözülür). Eski yerel yıldızlar okunur, kaldırılabilir. 15 SQL testi (a+b+c) PASS, 4 Dart testi |
| C-A3d | Gelişmiş sohbet araması (kişi/tarih/tür/kayıtlı) | mevcut arama ekranı | 🟡 Sohbetler arama alanının yanında 'Mesajlarda ara': metin, sohbet/kişi, tarih aralığı, fotoğraf/video/belge/ses, bağlantı, kayıtlı. Sunucu yalnız tür/tarih/sohbet + RLS ile daraltır; **E2EE metin cihazda çözülüp aranır** (son 400 mesaj — ekranda yazılı). Türkçe İ/ı duyarsız. 3 Dart testi |
| C-A3e | Düzenleme geçmişi (E2EE içerik sunucuda açık tutulmaz) | mesaj altyapısı | 🟡 Uygulamada mesaj DÜZENLEME hiç yoktu → eklendi: yalnız gönderen, metin, 15 dk, ≤10 kez (sunucu tetikleyicisi); birebirde yeni metin yeniden şifrelenir (fail-closed). `message_edits`: önceki sürüm düz metin ya da **şifreli zarf olduğu gibi** (sunucu açmaz), yalnız oda üyeleri, 30 gün (pg_cron temizlik), silinince geçmiş de silinir; istemci yazamaz. Balonda 'düzenlendi'; uzun bas > Düzenle / Düzenleme Geçmişi (cihazda çözülür). E2EE önbellek anahtarı düzenleme zamanını içerir. 11 SQL testi PASS |
| C-A3f | Sohbet kilidi (biyometrik/PIN) | Sohbet Bilgileri > Gizlilik | 🟡 PIN: PBKDF2-HMAC-SHA256 (60k tur, rastgele tuz) güvenli depoda, PIN düz yazılmaz; kilitli sohbetler listede gizli + 'Kilitli sohbetler' girişi; her açılış yolunda PIN; arka plana geçince yeniden kilit; 5 hatadan sonra artan bekleme; kilitlenince bildirim önizlemesi sunucuda 'gizli'. 5 Dart testi. **Biyometrik: YAPILMADI** — `local_auth` MainActivity'nin `FlutterFragmentActivity` + AppCompat temaya taşınmasını gerektiriyor; derleyip cihazda doğrulamadan uygulama açılışını riske atmamak için ertelendi |
| C-A3g | Profil > Paylaş içinde QR | mevcut profil paylaşımı | ✅ ZATEN VAR: `juzzio_profile_card_page.dart` (qr_flutter) 'Profili paylaş' içinde; yeni sayfa açılmadı |
| C-A4 | Business: geçiş (B1–B3) + Genel Bakış, Gelen Kutusu (sahiplik/atama, otomatik yanıt), Müşteriler (CRM, not, takip), İş Alanı (randevu, ekip, görev, analiz) | SQL+RLS+UI | 🟡 **SQL 10.20–10.21**: `business_accounts` (istemci yazamaz; 10 durumlu makine, izinli geçiş tablosu, `business_status_events` değiştirilemez geçmiş), 14 taslak hukuki belge (`DRAFT - LEGAL REVIEW REQUIRED`, SHA-256 politika özeti, yalnız `legal.publish` + inceleme notuyla 'LEGAL REVIEWED'), `user_consents` yalnız ekleme (kabul/geri alma ayrı satır; yeni sürüm → yeniden onay), başvuru (idempotent), 5 gerçek kurulum adımı (sıra zorunlu, kaldığı yerden), görünüm geçişi, duraklat/devam/kapat (veri silinmez, ekip erişimi kapanır), ekip (7 rol, davet/kabul/rol/erişim kaldır, işletme denetim kaydı), CRM/not/takip/gelen kutusu/hizmet/randevu/görev/otomatik yanıt tabloları — hepsi `juzzio_business_can` RLS; çapraz kiracı bağlantı ve ekip dışı atama tetikleyicide engelli; otomatik yanıt (karşılama/mesai dışı, 12 saatte 1, işaretli, kayıtlı); `business_overview` yalnız gerçek sayımlar; takip/randevu hatırlatmaları (pg_cron); personel: liste (business.read), askı/red/doğrulama (business.manage, gerekçe + denetim). **48 SQL kontrolü PASS + mutasyon testi yakaladı.** **Dart**: `juzzio_business_service.dart`, `screens/business/` (geçiş: tanıtım → tür/ad → ayrı onaylar → 7 ekranlı gerçek hazırlık [hareket azaltmada animasyonsuz, hata→tekrar dene] → karşılama), 5 sekmeli kabuk (Genel Bakış KPI, Gelen Kutusu filtre/atama/çözüldü/acil/talep/şablon/otomatik yanıt, Müşteriler liste+detay [not, takip, randevu, görev, geçmiş, düzenle], İş Alanı [randevu düzenle/saat/iptal/tamamla, hizmetler, ekip rol/izin açıklamalı, görevler, analiz 7/30/90 gün + önceki dönem, otomasyon], Profil [düzenle, çalışma saatleri, Personal'a dön, duraklat, kapat]); Profil sekmesinde hesap türü/geçiş şeridi + ekip davetleri; Yönetim'de Business sekmesi. 6 Dart testi. **Sınırlar:** ekip üyeleri E2EE sohbet içeriğini GÖREMEZ (yalnız kayıt bilgisi; sahip katılımcıdır) — gerçek paylaşımlı müşteri kanalı ayrı bir mesajlaşma modeli gerektirir (ertelendi); otomatik yanıt şifresizdir ve işaretlenir |
| C-A5 | Güvenlik Merkezi (cihazlar, oturumlar, gizlilik, şifreli yedek, uyarılar), Dosya Merkezi, erişilebilirlik, lokalizasyon | mevcut merkezler genişletilir | 🟡 **SQL 10.22**: `security_events` (istemci YAZAMAZ — yalnız tetikleyici/RPC; sahte uyarı imkânsız), olaylar: yeni cihaz (ilk cihaz hariç), cihaz kaldırıldı, E2EE anahtar değişti; `list_my_devices` (kimliğin son 6 hanesi), `forget_my_device` (mevcut cihaz korunur), `get_my_security_overview` (yalnız gerçek sayımlar), `mark_my_security_events_seen`; `user_devices` RLS sahip-okur. 15 SQL kontrolü PASS. **Dart**: `security_center_page.dart` (Hesap ayarlarından; özet, şifreli yedek son tarih, cihazlar, onaylı 'Diğer oturumları kapat' = `signOut(scope: others)`, uyarılar), `file_center_page.dart` (Depolama'dan; medya/belge/ses, son 300, RLS, E2EE açıklama cihazda çözülür, hiçbir şey silmez; önbellek temizliği mevcut onaylı akış). 2 Dart testi. l10n 144 dil temiz. **Sınır:** cihaz kaldırma yalnız listeyi temizler; oturumu bitirmek için 'Diğer oturumları kapat' (Supabase tekil oturum iptali sunmaz) |
| C-A6 | Regresyon, RLS, tema, responsive, buton eylem denetimi, build/CI | — | ⏳ |

## Mimari kararlar (otonom)
- Veritabanı değişiklikleri depo kuralına uygun olarak **tek kanonik dosyaya**
  (`supabase/juzzio_database.sql`) yeni bölüm olarak eklenir; idempotent, veri silmez.
- Yerel/CI SQL testi: `supabase/tests/supabase_stub_bootstrap.sql` (Supabase iskeleti) +
  `supabase/tests/test_fixtures.sql` + `scripts/sql_test.sh`.

## Önemli işletim notları
- ⚠️ **Çalışma sürerken bu klasörden push YAPMAYIN.** `.github/workflows/android-ci.yml`
  uzaktan araçlarla yazılamayan korumalı bir dosya; yeni hali yalnızca teslim ZIP'inde gelir.
  ZIP açılmadan push denenirse `verify_tree.py` / `ci_guards.py` gönderimi güvenle durdurur
  (hiçbir şey commit edilmez veya silinmez).
- `scripts/verify_tree.py`, manifestte olmayan `.dart` dosyalarını SİLER. Her kod değişikliğinden
  sonra `python3 scripts/verify_tree.py --update` çalıştırılır (bu çalışma bunu her kontrol noktasında yapar).
- Push artık geçmişi korur (force push yok). Tek-commit isteniyorsa: `set JUZZIO_SQUASH_HISTORY=1`.
- Supabase otomatik dağıtımı kapatmak için depo değişkeni: `JUZZIO_SUPABASE_AUTO_DEPLOY=false`.

## Günlük
- 2026-11-01: İki talimat dosyası okundu. Baseline: SQL 2× uygulama + 97 test PASS; Python kapıları PASS; `withOpacity` 98 adet.
- 2026-11-01: Faz 1a tamam — CI: dağıtım tüm kapılara bağlı, SQL/Edge işleri eklendi, yıkıcı silmeler kaldırıldı, eylemler SHA'ya sabitlendi, geçmiş sır taraması; push betikleri geçmişi korur; config.dart APP_BUILD 40→84 (pubspec ile aynı, `release_meta.py check` denetler).
- 2026-11-01: Faz 1b (1. kısım): Bölüm 10 SQL (LiveKit, etkin katılımcı, davet, altyazı, sesli not, hız sınırı, push kilidi, storage gizliliği, UI çeviri önbelleği). SQL: temiz kurulum ×2 + v0.8.4'ten yükseltme PASS; 145 doğrulama PASS (v0.9.0 bloğu dahil); mutasyon testi testlerin hatayı yakaladığını kanıtladı. Edge Functions tsc PASS. ⚠️ Storage özel hale geldiği için istemci imzalı URL geçişi (Faz 1c) yayından önce ZORUNLU.
- 2026-11-01: Faz 1b tamam — RBAC (47 RPC), storage temizliği kuyruğu + storage-cleanup fonksiyonu + bakım iş akışı. SQL 167 doğrulama PASS. Kurulum notu: GitHub + Supabase secret `STORAGE_CLEANUP_SECRET` (≥24 karakter) eklenmeli.
- 2026-11-01: Faz 2 + N-E + N-G (yukarıdaki satırlar). Regresyon: sözcük denetimi 86 dosya PASS, l10n PASS (1240 metin), sır taraması PASS, ci_guards PASS, release_meta PASS, SQL 5 blok PASS. Ek düzeltme: Keşfet bakım metni sabit beyazdı → tema rengi.
- 2026-11-02: C-A6 — v0.8.4→v0.9.0 yükseltme testi PASS (22/22), tüm kapılar PASS, sürüm 0.9.0, README/PRIVACY/sürüm notları, docs/CLOSURE_MATRIX_v0.9.0.md, ZIP.
- 2026-11-02: G23/G24 E2EE fotoğraf, G26 anket, G27 zamanlanmış mesaj, G28 hız (SQL 22 blok, 315 doğrulama PASS).
- 2026-11-02: C-A5 Güvenlik/Dosya Merkezi (SQL 21 blok, 285 doğrulama PASS; Edge 13/13; Dart 118 dosya sözcük PASS).
- 2026-11-02: C-A4 Business (SQL 20 blok PASS, mutasyon yakaladı; Dart 113 dosya sözcük PASS; l10n 1450).
- 2026-11-02: C-A3 d/e/f/g (SQL 19 blok PASS).
- 2026-11-02: C-A3 a/b/c (SQL 18 blok PASS).
- 2026-11-02: N-B @etiketleme (SQL 17 blok PASS).
- 2026-11-02: N-F, §6.4, N-C kaydetme opt-in; CI edge-check'e `scripts/edge_unit_test.sh` eklendi (tsc+node). Ek bulgu: tüm mesaj kanalları kilit ekranında PUBLIC'ti → mesaj bildirimleri için PRIVATE kanal varyantı.
- 2026-11-02: N-D bildirim önizlemesi (SQL 13 blok PASS, tsc PASS, push_preview 9/9, Dart sözcük 91 dosya, l10n 1258).
- 2026-11-02: N-A canlı durum (SQL 12 blok PASS, Dart sözcük 89 dosya PASS, l10n 1247 PASS). Test iskeletine realtime şeması eklendi.
- 2026-11-02: Son konsolidasyon talimatı eklendi (yukarıda C-*). Personal 5 sekme uygulandı; Bildirimler sayfasına gömülü kip (geri düğmesi gizli, kök rotayı kapatmaz).
- 2026-11-01 23:44: Personal/Business ikili deneyim eki tamamen okundu → B0–B11 olarak bu dosyaya eklendi.
- 2026-11-01: Faz 1c — (1) Özel medya: `lib/services/juzzio_media_url.dart` (imzalı URL + önbellek + `JuzzioStorageImage`), 10 görüntüleme noktası, video denetleyicisi imzadan sonra oluşturulur, sesli mesaj imzalı adresle çalınır; geri bildirim görüntüleri artık özel bucket'ta (personel yalnız `feedback.manage`, moderatör yalnız hikâye/gönderi medyası; özel sohbet medyası personele kapalı — SQL testli). (2) E2EE fail-closed: `encryptForRoomStrict` + `JuzzioE2eeRequiredException`; ağ hatasında oda grup sayılmaz; anahtarsız karşı tarafa düz metin yalnız açık onayla ve `metadata.security=plaintext_consented`; E2EE metni onaysız çeviriye gitmez (gönderen VE alıcı tarafı); Ayarlar'a izin anahtarı. (3) `client_msg_id` idempotency (SQL testli). (4) G13–G19, G21 istemci. Yeni: `scripts/dart_lexcheck.py` (CI'a eklendi), `test/juzzio_v090_test.dart`.
