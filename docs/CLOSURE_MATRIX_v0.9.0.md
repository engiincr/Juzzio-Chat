# Juzzio v0.9.0 — Kapanış matrisi

Tarih: 2026-11-02 · Dal: `wip/v0.9.0-hardening` (yerel commit'ler; GitHub'a gönderim bu ortamda
proxy 403 nedeniyle yapılamadı — depo ZIP içindeki `.git` ile teslim edilir).

Durum anahtarı: ✅ doğrulandı · 🟡 kod + yerel test tamam, Flutter/Android derlemesi ve cihaz testi CI'da ·
SKIPPED kapsam dışı (docs/EXCLUDED_FEATURES.md).

## Doğrulama kapıları (bu ortamda gerçekten çalıştırılanlar)

| Kapı | Sonuç |
| :-- | :-- |
| Kanonik SQL temiz veritabanına 2 kez (idempotent) | ✅ PASS |
| Veritabanı testleri (22 blok) | ✅ PASS — 315 doğrulama |
| v0.8.4 şeması + veri → v0.9.0 yükseltme (2 kez) + tüm testler | ✅ PASS (22/22 blok) |
| Edge Functions `tsc` + birim testleri | ✅ PASS — 13/13 |
| Dart sözcük denetimi | ✅ PASS — 0 sorun |
| Yerelleştirme (144 dil) | ✅ PASS |
| Hassas bilgi taraması | ✅ PASS |
| CI koruma kapısı | ✅ PASS |
| Sürüm meta verisi (`release_meta check`) | ✅ v0.9.0 (+90) |
| Kaynak bütünlüğü (`verify_tree`) | ✅ PASS |
| `flutter analyze` / `flutter test` / APK derlemesi | NOT RUN — bu ortamda Flutter SDK yok; GitHub Actions'ta çalışır |
| Cihaz üzerinde uçtan uca test | NOT RUN |

## Özellik kapanışı

Ayrıntılı satırlar: `docs/IMPLEMENTATION_PROGRESS_v0.9.0.md` (B0–B11, C-A1…C-A6, N-A…N-H, G23–G30).

| Alan | Durum |
| :-- | :-- |
| C-A1 analiz, C-NAV gezinme + geri tuşu | 🟡 |
| C-A2 bildirimler (önizleme modları, kilit ekranı gizliliği, hızlı yanıt, arama reddi, sohbet başına ayar, etiketleme) | 🟡 |
| C-A3 Personal (Yaşam Merkezi, hatırlatıcı, kayıtlı mesaj, arama, düzenleme geçmişi, sohbet kilidi, QR) | 🟡 (QR ✅ mevcut) |
| C-A4 Business | 🟡 |
| C-A5 Güvenlik Merkezi, Dosya Merkezi, erişilebilirlik/l10n | 🟡 |
| G23/G24 E2EE fotoğraf | 🟡 — video/ses/belge şifresiz (bilinen sınır) |
| G25 kanallar, G29 dalga formu | ✅ mevcut |
| G26 anket, G27 zamanlanmış mesaj, G28 hız | 🟡 |
| G30 civciv evrimi | SKIPPED |

## Bilinen sınırlar

- Sohbet kilidinde biyometrik açma yok (FlutterFragmentActivity gerektirir).
- Mesaj arama son 400 mesajı cihazda tarar.
- Hatırlatıcılar, zamanlanmış mesajlar ve Business hatırlatmaları pg_cron gerektirir.
- Cihaz kaldırma yalnız listeyi temizler; oturum için "Diğer oturumları kapat".
- Etkinlik (yazıyor) olaylarında kullanıcı kimliği oda üyeleri arasında taklit edilebilir (yalnız gösterge).
