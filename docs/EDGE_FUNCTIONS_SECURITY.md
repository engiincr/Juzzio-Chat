# Edge Function güvenlik modeli (v0.9.0)

Tüm fonksiyonlar `--no-verify-jwt` ile dağıtılır; **kimlik doğrulama platformda değil, fonksiyon
gövdesinde zorunlu olarak** yapılır. Bu bilinçli bir seçimdir: `auth-username-login` giriş
öncesi (JWT yokken) çağrılır, `push-webhook` ise veritabanı webhook'u ile gizli başlık
kullanır. Diğer fonksiyonlar her istekte `requireUser()` → `auth.getUser(token)` çağırır.

| Fonksiyon | Kimlik | Yetki (sunucu tarafı) | Hız sınırı | Not |
| :-- | :-- | :-- | :-- | :-- |
| `get-livekit-token` | Kullanıcı JWT | `can_join_livekit_room` (yasak, üyelik, çıkarılma, 4 kişi sınırı) | 60/dk | Kimlik JWT'den; dil kodu doğrulanır |
| `get-livekit-token` (remove_participant) | Kullanıcı JWT | `juzzio_remove_call_participant` (host / grup yöneticisi) | — | UUID doğrulaması |
| `translate-bridge` text | Kullanıcı JWT | — | 120/dk | **E2EE mesaj metni gönderilmez** (istemci kuralı) |
| `translate-bridge` content | Kullanıcı JWT | Orijinal metin kullanıcının RLS'iyle okunur | 120/10 dk | Sunucu önbelleği |
| `translate-bridge` voice_note | Kullanıcı JWT | `juzzio_voice_note_for_transcription`: oda üyeliği + yasak + engel; ses sunucuda indirilir | 20/10 dk | URL yetki DEĞİLDİR; 25 MB, yalnız `audio/*` |
| `translate-bridge` deepgram_token | Kullanıcı JWT | `juzzio_can_use_live_captions`: yasaksız + etkin çağrı | 30/10 dk | 120 sn ömürlü token |
| `translate-bridge` batch_ui | Kullanıcı JWT | Yalnızca uygulama metinleri; kişisel veri yok | 60/10 dk, 80 metin/istek | `ui_translations` önbelleği |
| `content-moderation` call_frame | Kullanıcı JWT | `can_join_livekit_room` VEYA `juzzio_is_active_call_participant` | 30/dk | Biten/çıkarılan katılımcı odayı kapatamaz |
| `content-moderation` avatar | Kullanıcı JWT | Yalnız kendi `avatars/<uid>/` nesnesi | — | |
| `push-webhook` | `x-webhook-secret` (sabit zamanlı karşılaştırma) veya kullanıcı JWT (self_test) | Alıcı tercihleri/engeller | self_test: 1/dk | Askıda kilit 120 sn sonra atomik devralınır |
| `auth-username-login` | Yok (giriş öncesi) | Supabase Auth şifre doğrulaması | IP özeti başına 60/5 dk (altyapı hatasında açık) | Tüm hatalar aynı kod + ≥900 ms |

## İlkeler
- Kullanıcı girdisi PostgREST filtresine girmeden önce `isUuid()` ile doğrulanır.
- Hata yanıtları kararlı kodlardır; iç hata mesajları (`error.message`) istemciye dönmez.
- Gizli değerler yalnızca `Deno.env` (Supabase Secrets); günlüklere yazılmaz.
- Hız sınırı `juzzio_rate_check` (veritabanı, danışma kilidi ile yarışsız) — varsayılan olarak
  altyapı hatasında **reddeder** (ücretli sağlayıcıların kötüye kullanımını önler).
