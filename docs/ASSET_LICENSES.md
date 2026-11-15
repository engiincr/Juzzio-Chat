# Juzzio — Varlık (asset) lisans ve köken kaydı

v1.2.9 telif denetimi. Uygulamaya gömülü her dosyanın kaynağı ve hakkı burada tutulur.
Yeni bir görsel/ses/video eklenmeden önce bu tabloya satır eklenmelidir.

| Dosya | Kaynak | Hak / lisans |
|---|---|---|
| `assets/logo/juzzio_logo.png` | `tools/brand/*.svg` (kendi çizimimiz) | Juzzio'ya ait |
| `assets/creator/engin.jpg` | Yapımcının kendi fotoğrafı | Yapımcıya ait, izinli |
| `assets/creator/juzzio_creator_reel.mp4` | Görüntü: `tools/creator_reel/reel.py` (kodla çizildi). Ses: `tools/juzzio_music_synth.py 26.6 11` | Juzzio'ya ait, özgün |
| `assets/intro/juzzio_intro_tr.mp4`, `_en.mp4` | Görüntü: `tools/intro_video/intro.py`. Ses: `tools/juzzio_music_synth.py 20 7` | Juzzio'ya ait, özgün |
| `assets/intro/juzzio_whatsnew_tr.mp4`, `_en.mp4` | Görüntü: `tools/intro_video/whatsnew.py` (kodla çizildi; bayraklar Noto Color Emoji). Ses: `tools/juzzio_music_synth.py 18 129` (v1.2.9) | Juzzio'ya ait, özgün |
| `assets/weather/moon.png`, `sun.png`, `cloud_a.png`, `cloud_b.png` | `tools/weather_sprites.py` (tamamen kodla üretildi; fotoğraf ya da üçüncü taraf görsel yok) | Juzzio'ya ait, özgün |
| Hareketli "GIF" çıkartmalar (`lib/widgets/juzzio_gif_stickers.dart`) | Dosya yok: emoji yazı tipi + kodla çizilen hareket/efektler (v1.2.9) | Juzzio'ya ait; emoji glifleri SIL OFL 1.1 |
| `docs/images/juzzio-social-preview.png` | `tools/github_banner.py` (logo + Inter yazı tipi, kodla çizildi) | Juzzio'ya ait; Inter SIL OFL 1.1 |
| `assets/images/pdf_logo.png` | Yasal PDF raporunun antet logosu (şeffaf arka plan); Juzzio logosu + "Juzzio." yazısı (v1.2.9). Uygulama logosundan ayrı dosyadır | Juzzio'ya ait |
| `assets/fonts/pdf/LiberationSans-Regular.ttf`, `-Bold.ttf` | Liberation Fonts (github.com/liberationfonts) — yalnız yasal PDF raporuna gömülür (Türkçe karakter) | SIL Open Font License 1.1 (`LiberationSans-LICENSE.txt`) |
| `assets/sounds/juzzio_ringback.wav` | 400+450 Hz çift ton, kodla üretildi | Juzzio'ya ait |
| `assets/sounds/juzzio_reconnect.wav` | 660/880 Hz yumuşak darbe, kodla üretildi (v1.2.9) | Juzzio'ya ait |
| `android/app/src/main/res/raw/juzzio_*.ogg` | Kodla sentezlenen zil/mesaj tonları | Juzzio'ya ait |
| `assets/fonts/NotoColorEmoji.ttf` | Google Noto Emoji | SIL Open Font License 1.1 (`NotoColorEmoji-OFL.txt`, uygulama içi Lisanslar sayfasında) |

## v1.2.9'da kaldırılanlar (telif riski)
- Tanıtım videosundaki müzik bir Instagram reel'inden alınmış bir sesti (`luca_radez_*.mp3`); hakkı bize ait
  değildi. Yerine matematiksel sentezle üretilmiş özgün müzik kondu.
- Yapımcı tanıtım videosunun eski ses izi kaynağı belgelenmemişti; aynı şekilde özgün müzikle değiştirildi.

## Üçüncü taraf hizmet atıfları (uygulamada gösterilir)
- **Open-Meteo** hava verisi — CC BY 4.0; "Hava verisi: Open-Meteo.com" atfı hava teması ayarında ve Lisanslar sayfasında.
- **Apple iTunes Search** 30 sn önizlemeleri — yalnız akış (cihaza indirilmez/önbelleğe alınmaz), her parçada
  "Apple Music'te aç" bağlantısı ve "Önizleme: Apple Music" atfı; yönetici panelinden tek anahtarla kapatılabilir
  (`app_settings.itunes_previews_enabled`).
- **Çeviri**: sunucuda resmî Google Cloud Translation (`GOOGLE_TRANSLATE_API_KEY`) veya DeepL (`DEEPL_API_KEY`) anahtarı
  tanımlıysa yalnız resmî API kullanılır; tanımlı değilse eski ücretsiz uç noktalara düşülür ve Sistem Sağlığı
  sayfası bunu "resmî olmayan sağlayıcı" diye uyarır.
- **Sinema Parti**: uygulama içerik barındırmaz, yalnız kullanıcıların açtığı bağlantıyı eş zamanlar. Paylaşmadan önce
  "yalnız izleme hakkına sahip olduğun içerik" onayı alınır; yönetici korsan alan adlarını
  `watch_party_blocked_domains` listesine ekleyerek engelleyebilir; her parti şikâyet edilebilir.
