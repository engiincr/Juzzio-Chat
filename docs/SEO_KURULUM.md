# Juzzio — Google ve GitHub'da görünürlük (SEO) kurulumu

Kod tarafında hazır olanlar (v0.9.3):
- `docs/index.html` (Türkçe) ve `docs/en.html` (İngilizce): başlık, açıklama, anahtar kelimeler,
  canonical, hreflang, Open Graph/Twitter kartları ve JSON-LD (SoftwareApplication, Organization, FAQPage).
- `docs/sitemap.xml`, `docs/robots.txt`, `docs/.nojekyll`.
- README'ye web sitesi bağlantısı ve İngilizce anahtar ifadeler eklendi.

Google bir siteyi ancak taranıp dizine eklendikten sonra gösterir. Bunun için aşağıdaki adımları sizin hesabınızla yapmanız gerekir.

## 1. GitHub Pages'i açın (bir kez)
GitHub → `engiincr/Juzzio-Chat` → **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main`, klasör: `/docs` → **Save**.
Birkaç dakika sonra site şu adreste açılır: https://engiincr.github.io/Juzzio-Chat/

## 2. Depo açıklaması, web sitesi ve konular (Termux)
```
gh repo edit engiincr/Juzzio-Chat \
  --description "Juzzio — live translated voice & video calls, end-to-end encrypted messenger (Android). Canlı çevirili görüntülü arama ve şifreli mesajlaşma." \
  --homepage "https://engiincr.github.io/Juzzio-Chat/" \
  --add-topic juzzio --add-topic translation --add-topic live-translation --add-topic video-call \
  --add-topic messenger --add-topic e2ee --add-topic flutter --add-topic android --add-topic supabase \
  --add-topic chat-app --add-topic post-quantum-cryptography
```
Depo **Public** olmalıdır; özel depolar Google'da görünmez.

## 3. Google Search Console
1. https://search.google.com/search-console → **Mülk ekle** → **URL ön eki**: `https://engiincr.github.io/Juzzio-Chat/`
2. Doğrulama yöntemi **HTML etiketi**: verilen `<meta name="google-site-verification" ...>` satırını
   `docs/index.html` içindeki "Google Search Console doğrulaması" yorumunun altına yapıştırıp gönderin (push), sonra **Doğrula**.
3. **Site haritaları** → `sitemap.xml` gönderin.
4. **URL denetimi** → ana sayfa adresini girin → **Dizine eklenmeyi iste**.

## 4. Bing / Yandex (isteğe bağlı, hızlandırır)
- https://www.bing.com/webmasters → Search Console'dan içe aktar.
- https://webmaster.yandex.com → siteyi ekleyin, `sitemap.xml` gönderin.

## 5. Bağlantı (backlink) — en etkili adım
Yeni bir ad (Juzzio) için Google'ın sıralaması zamanla ve dış bağlantılarla oluşur. Web sitesi bağlantısını
Instagram/TikTok/X profil biyografilerine, YouTube video açıklamalarına, Reddit/Ekşi/Donanımhaber gibi forumlara ve
uygulama içi "Arkadaşını davet et" paylaşımlarına ekleyin. İlk dizine ekleme genellikle birkaç gün–birkaç hafta sürer;
kesin bir sıra garantisi verilemez.
