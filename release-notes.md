# Juzzio v0.8.4 — Liquid Glass Tasarım Ailesi ve Tema Galerisi

## Neden bu güncelleme?

12 temayı tek bir Liquid Glass tasarım ailesinde birleştirmek, her temayı hem uygulama hem sohbet teması olarak seçilebilir yapmak ve CI analiz hatasını gidermek için getirildi.

## ✨ Yeni özellikler

- 12 tema tek Liquid Glass ailesi: her temanın kendi cam karakteri (blur, opaklık, ışık yansıması, derinlik, kenar ışığı)
- Ayarlar › Görünüm: tüm uygulama arayüz temaları ve sohbet temaları tek galeride
- 12 cam teması artık sohbet teması olarak da seçilebiliyor; 16 klasik sohbet teması korunuyor
- Tema önizlemesinde ve cam teması listesinde tema karakteri açıklaması
- Siber Neon'da neon kenar parıltısı, Krom'da metalik yansıma, Obsidyen OLED'de derin katmanlar

## 🛠️ Düzeltilen hatalar

- CI analiz hatası: 'num' tür adını gölgeleyen yerel fonksiyon yeniden adlandırıldı
- Sohbet parlaklık kaydırıcısı seçili temayı sıfırlamıyor
- Açık renkli temalarda (Cam Beyaz, Krom vb.) giden mesaj balonunda beyaz yazı okunur kalıyor (WCAG AA ≥ 4.5:1)

## 🔒 Güvenlik ve gizlilik

- Veritabanı değişikliği yok; tema seçimleri yalnızca kullanıcının kendi tercihlerine kaydedilir

---

<details><summary>English</summary>

## Why this update?

Unifies the 12 themes into one Liquid Glass design family, makes every theme selectable as both app and chat theme, and fixes the CI analyze error.

## ✨ New features

- 12 themes, one Liquid Glass family: each theme has its own glass character (blur, opacity, sheen, depth, rim light)
- Settings › Appearance: all app and chat themes in one gallery
- All 12 glass themes can now be used as chat themes; 16 classic chat themes kept
- Theme character description in preview and glass theme list
- Neon rim glow on Cyber Neon, metallic sheen on Chrome, deep layers on Obsidian OLED

## 🛠️ Fixed bugs

- CI analyze error: local function shadowing the 'num' type renamed
- Chat brightness slider no longer resets the selected theme
- White text on outgoing bubbles stays readable on light themes (WCAG AA ≥ 4.5:1)

## 🔒 Security and privacy

- No database changes; theme choices are stored only in the user's own preferences

</details>

## İndirme

- Son sürüm: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- Bu sürüm: `juzzio-v0.8.4-release.apk` (99.17 MB)

## APK doğrulama

```bash
sha256sum Juzzio-latest.apk
# 2ddeaa96db0ca7e952b6f8feaa945024ce357e7e8105b02dc809db800fb513d7  Juzzio-latest.apk
```

Derleme zamanı: 2026-11-01 15:23 UTC — GitHub Actions
