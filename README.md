# 📱 Juzzio - Otonom Canlı Çevirili Mesajlaşma & Arama Portalı

<div align="center">

```
   ███████╗███╗   ██╗████████╗███████╗██████╗ ██████╗ ██████╗ ██╗███████╗███████╗
   ██╔════╝████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║██╔════╝██╔════╝
   █████╗  ██╔██╗ ██║   ██║   █████╗  ██████╔╝██████╔╝██████╔╝██║███████╗█████╗  
   ██╔══╝  ██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔═══╝ ██╔══██╗██║╚════██║██╔══╝  
   ███████╗██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║  ██║██║███████║███████╗
   ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝
```

**🌐 Sınırları Kaldıran İletişim: Sesli/Görüntülü Aramalarda Gerçek Zamanlı Altyazı & Cihaz İçi ML Kit Çevirisi**

[![Flutter](https://img.shields.io/badge/Flutter-3.24.5-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![WebRTC](https://img.shields.io/badge/WebRTC-Audio%20%26%20Video-333333?style=for-the-badge&logo=webrtc&logoColor=white)](https://webrtc.org)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%2015-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/Firebase-Cloud%20Messaging-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-Proprietary%20Enterprise-blue?style=for-the-badge)](#-lisans-ve-kurumsal-kullanım-şartları)

</div>

---

<!-- 🚀 ENTERPRISE_STATUS_START -->
### 📊 Canlı Dağıtım ve Otomasyon Göstergeleri

<div align="center">

[![APK İndir](https://img.shields.io/badge/📥_DOĞRUDAN_APK_İNDİR-Juzzio--latest.apk_(v8.1.0)-2ea44f?style=for-the-badge&logo=android&logoColor=white)](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk) [![Sürüm Sayfası](https://img.shields.io/badge/🚀_TÜM_SÜRÜMLER-Releases_(Son_2_Upgrade)-0284c7?style=for-the-badge&logo=github&logoColor=white)](https://github.com/engiincr/Juzzio-Chat/releases)

</div>

[![Actions Workflow](https://github.com/engiincr/Juzzio-Chat/actions/workflows/apk.yml/badge.svg?branch=main)](https://github.com/engiincr/Juzzio-Chat/actions) [![Sürüm](https://img.shields.io/badge/Sürüm-v8.1.0-blue.svg?style=flat-square)](CHANGELOG.md) [![Derleme](https://img.shields.io/badge/Android_Build-SUCCESS-brightgreen?style=flat-square)](https://github.com/engiincr/Juzzio-Chat/actions) [![Test](https://img.shields.io/badge/Unit_Tests-SUCCESS-brightgreen?style=flat-square)](https://github.com/engiincr/Juzzio-Chat/actions) [![Güvenlik](https://img.shields.io/badge/Security_Scan-PASSED-brightgreen?style=flat-square)](https://github.com/engiincr/Juzzio-Chat/actions) [![DB Vault](https://img.shields.io/badge/DB_Schema_Vault-VERIFIED-brightgreen?style=flat-square)](#-veritabanı-şeması-ve-kalıcı-şema-kasası-immutable-db-vault) [![Pipeline Audit](https://img.shields.io/badge/Pipeline_Audit-Verified_%E2%9C%94-0ea5e9?style=flat-square&logo=git&logoColor=white)](#-doğrulama-ve-bütünlük-güvencesi)

| Metrik | Durum / Değer | Doğrulama Bağlantısı |
| :--- | :--- | :--- |
| **En Son Commit** | `843427a` | [Commit İncele](https://github.com/engiincr/Juzzio-Chat/commit/843427a) |
| **Aktif Branch** | `main` | [Tüm Branch'ler](https://github.com/engiincr/Juzzio-Chat/branches) |
| **Son Pipeline Doğrulaması** | `2026-10-24 10:22 UTC` | [Çalıştırma Kayıtları](https://github.com/engiincr/Juzzio-Chat/actions) |
| **Son APK Dağıtımı** | [📦 **Juzzio-latest.apk İndir (v8.1.0)**](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk) | [Releases (Son 2 Sürüm)](https://github.com/engiincr/Juzzio-Chat/releases) |

<!-- 🚀 ENTERPRISE_STATUS_END -->

---

## 📢 Son Güncelleme Özeti (Changelog & Teknik Detaylar)

> ### 🚀 Sürüm v1.0.1 - CI/CD Hata Çözümü, AndroidX Entegrasyonu ve WebRTC Canlı Altyazı
> Bu güncellemede projenin GitHub Actions üzerindeki derleme engelleri kaldırılmış, altyapı hızlandırılmış ve görüntülü arama çeviri motoru devreye alınmıştır:
> 
> 1. **`actions/setup-python` Bağımlılık Hatasının Çözümü:**
>    * **Hata:** `No file matched to [**/requirements.txt or **/pyproject.toml]` hatasıyla pipeline duruyordu.
>    * **Çözüm & Neden:** `.github/workflows/apk.yml` içerisindeki `cache: "pip"` direktifi kaldırıldı ve standart kütüphane odaklı `requirements.txt` dosyası eklendi. Python adımı artık paket arayarak vakit kaybetmeden 1 saniyede güvenle tamamlanıyor.
> 2. **Flutter 3.24 Gradle Eklenti Çakışması (`dev.flutter.flutter-gradle-plugin`):**
>    * **Hata:** Eski `settings.gradle` bildirimsel (declarative) DSL yapısını tanımıyordu.
>    * **Çözüm:** `settings.gradle` dosyasına `pluginManagement { includeBuild(...) }` mimarisi eklendi; eklenti sürümü Gradle 8.5 standartlarına eşitlendi.
> 3. **Eksik Android Derleme Katmanları:**
>    * Projede eksik olan `MainActivity.kt`, `android/gradle.properties` (`android.useAndroidX=true` ve `multiDexEnabled=true`) ile tema kaynakları (`styles.xml`, `launch_background.xml`) projeye eklendi. Android'in 64k metot sınırına takılması ve stil bulunamadı hataları engellendi.
> 4. **WebRTC Canlı Altyazı HUD Katmanı:**
>    * `webrtc_call_service.dart` üzerinden açılan DataChannel kanalı, `translation_service.dart` konuşma tanıma motoruyla bağlandı. Türkçe konuşmalar milisaniyeler içinde İngilizceye çevrilip karşı tarafın ekranına canlı altyazı olarak yansıtıldı.
> 5. **Termux Tek Tuşla Dağıtım (`deploy.sh`):**
>    * Termux kullanıcıları için `0`, `push` veya `juzzio` yazarak otomatik önbellek temizliği yapıp 3 saniyede GitHub'a gönderen akıllı dağıtım motoru kodlandı.

---

## 🛡️ Güvenlik ve Sunucu Altyapı Durumu (SERVER STATUS & SECURITY)

Sistem mimarisi, kullanıcı gizliliğini korumak amacıyla sunucu kimlik bilgilerini kod tabanında asla açık metin olarak barındırmaz. Tüm bağlantılar şifrelenmiş tüneller ve izole sağlayıcılar üzerinden yürütülür:

```
[Kullanıcı A] ──── (WebRTC Şifreli Medya / SRTP) ──── [Kullanıcı B]
      │                                                     │
      ├───► [ExpressTURN Relay (STUN:3478 / TURN:3478)] ────┤
      │                                                     │
      └───► [Supabase Realtime (WSS / PostgreSQL RLS)] ◄────┘
```

| Sunucu / Altyapı Bileşeni | Durum | Güvenlik Düzeyi | Doğrulama & Rol |
| :--- | :---: | :---: | :--- |
| **ExpressTURN Relay Cluster** | 🟢 Aktif | `TLS / SRTP Şifreli` | NAT arkasındaki cihazlar için ses/video aktarımı (`free.expressturn.com:3478`) ✔ |
| **Supabase Realtime Engine** | 🟢 Aktif | `Row Level Security (RLS)` | Çağrı sinyalleşmesi (SDP/ICE) ve çift dilli mesaj veritabanı ✔ |
| **Firebase Cloud Messaging** | 🟢 Aktif | `OAuth2 / Service Account` | Arka planda arama uyandırma, zil sesi ve anlık bildirim iletimi ✔ |
| **Google ML Kit Translate** | 🟢 Aktif | `On-Device (Cihaz İçi)` | Konuşmalar sunucuya gitmez; tamamen telefondaki NPU/CPU üzerinde çevrilir ✔ |
| **Otomatik Çağrı Temizliği** | 🟢 Aktif | `PostgreSQL Trigger` | Görüşme sonlandığı anda çağrı ve sinyal kayıtları DB'den anında silinir ✔ |

> 🔒 **Gizlilik Güvencesi:** ExpressTURN ve Supabase şifreleri GitHub Actions ortamında ve yerel cihazda şifreli değişken olarak saklanır. Depoda açık şifre tespit edildiğinde CI/CD boru hattı (`security_scan.py`) derlemeyi otomatik olarak iptal eder.

---

## 🛡️ Doğrulama ve Bütünlük Güvencesi (Blue Check Badge)

> ⚠️ **Şeffaflık Beyanı:** Yukarıdaki mavi tik onay göstergesi (`Pipeline_Audit: Verified ✔`), **resmî bir GitHub Kuruluş veya Kimlik Doğrulaması (Official GitHub Org Verification) DEĞİLDİR.**
> 
> Bu rozet, projenin kurumsal açık standartlara tabi olduğunu ve her bir commit'te aşağıdaki 4 katmanlı bütünlük denetiminin başarıyla tamamlandığını temsil eder:
> 1. **Statik ve Gizli Veri Denetimi:** Kod tabanında açık API anahtarı, özel anahtar veya parola bulunmadığının teyidi.
> 2. **Kalıcı Şema Doğrulaması:** SQL migration dosyalarının SHA-256 parmak izlerinin kasanın (`db_schema_vault.json`) geçmiş kayıtlarıyla uyuştuğunun ve geçmiş migration'ların tahrif edilmediğinin kanıtı.
> 3. **Temiz Derleme ve Test Kanıtı:** Gradle Wrapper ve Flutter 3.24 ile izole ortamda derleme ve testlerin hatasız geçtiği; kodlar henüz eklenmemişse sahte başarı üretilmeden dürüstçe `SKIPPED` olarak raporlandığı.
> 4. **Semantik Sürüm Bütünlüğü:** Sürüm çakışmalarının engellendiği ve içeriği değiştirilmiş APK'ların aynı sürüm altında mükerrer yayımlanmasının kilitlendiği.

---

<!-- 🔒 PERMANENT_DB_SCHEMA_START -->
### 🔒 Veritabanı Şeması ve Kalıcı Şema Kasası (Immutable DB Vault)

> **Doğrulama Modu:** `static_ast_parse` (Statik DDL Ayrıştırma) | **Canlı DB Bağlantısı:** `False`
> **Son Güncelleme:** `2026-10-25T16:20:33.852483+00:00` | **İzlenen Migration:** `1`

#### Şema: `public`
- **Tablo:** `audit_log` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `action` | `VARCHAR(80)` | **Hayır** | - | - |
  | `admin_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `entity_type` | `VARCHAR(40)` | **Hayır** | `'profile'` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `ip_address` | `VARCHAR(45)` | Evet | - | - |
  | `new_value` | `JSONB` | Evet | `'{}'::jsonb` | - |
  | `old_value` | `JSONB` | Evet | `'{}'::jsonb` | - |
  | `target_user_id` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `audit_log_admin` (`ALL`)

- **Tablo:** `blocked_users` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `blocked_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `blocker_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `reason` | `TEXT` | Evet | - | - |
  | `restriction_type` | `VARCHAR(20)` | **Hayır** | `'blocked'` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `blocked_users_all` (`ALL`)

- **Tablo:** `call_records` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `avg_latency_ms` | `INT` | Evet | `45` | - |
  | `call_type` | `VARCHAR(20)` | **Hayır** | `'video'` | - |
  | `caller_id` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `direction_status` | `VARCHAR(20)` | **Hayır** | `'completed'` | - |
  | `duration_seconds` | `INT` | **Hayır** | `0` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `receiver_id` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `translated_utterances_count` | `INT` | Evet | `0` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `call_records_select` (`SELECT`)
    - 🛡️ `call_records_all` (`ALL`)

- **Tablo:** `call_signals` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `call_id` | `UUID` | **Hayır** | - | ↳ `public.calls(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `payload` | `JSONB` | **Hayır** | - | - |
  | `receiver_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `sender_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `type` | `VARCHAR(30)` | **Hayır** | - | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `call_signals_all` (`ALL`)

- **Tablo:** `calls` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `call_type` | `VARCHAR(20)` | **Hayır** | `'video'` | - |
  | `caller_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `duration_seconds` | `INT` | **Hayır** | `0` | - |
  | `ended_at` | `TIMESTAMP` | Evet | - | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `live_subtitles_enabled` | `BOOLEAN` | **Hayır** | `true` | - |
  | `network_quality` | `VARCHAR(20)` | Evet | `'excellent'` | - |
  | `receiver_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `started_at` | `TIMESTAMP` | Evet | - | - |
  | `status` | `VARCHAR(20)` | **Hayır** | `'ringing'` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `calls_all` (`ALL`)

- **Tablo:** `chat_participants` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `chat_id` | `UUID` | **Hayır** | - | ↳ `public.chats(id)` |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_archived` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_locked` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_muted` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_pinned` | `BOOLEAN` | **Hayır** | `false` | - |
  | `joined_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `role` | `VARCHAR(20)` | **Hayır** | `'member'` | - |
  | `unread_count` | `INT` | **Hayır** | `0` | - |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `chat_participants_all` (`ALL`)

- **Tablo:** `chat_theme_settings` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `chat_id` | `UUID` | **Hayır** | - | ↳ `public.chats(id)` |
  | `custom_bg_bottom` | `VARCHAR(15)` | Evet | - | - |
  | `custom_bg_top` | `VARCHAR(15)` | Evet | - | - |
  | `custom_bubble_color` | `VARCHAR(15)` | Evet | - | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `media_visibility` | `BOOLEAN` | **Hayır** | `true` | - |
  | `notifications_enabled` | `BOOLEAN` | **Hayır** | `true` | - |
  | `theme_key` | `VARCHAR(30)` | **Hayır** | `'warm_glass'` | - |
  | `updated_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |

- **Tablo:** `chats` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `auto_translate` | `BOOLEAN` | **Hayır** | `true` | - |
  | `avatar_url` | `TEXT` | Evet | - | - |
  | `category` | `VARCHAR(30)` | **Hayır** | `'all'` | - |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `created_by` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `disappearing_seconds` | `INT` | Evet | `0` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_archived` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_group` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_locked` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_muted` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_pinned` | `BOOLEAN` | **Hayır** | `false` | - |
  | `last_message_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `last_message_sender` | `VARCHAR(100)` | Evet | - | - |
  | `last_message_text` | `TEXT` | Evet | - | - |
  | `subtitle` | `VARCHAR(255)` | Evet | - | - |
  | `title` | `VARCHAR(120)` | Evet | - | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `chats_select` (`SELECT`)
    - 🛡️ `chats_all` (`ALL`)

- **Tablo:** `friend_requests` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `message` | `TEXT` | Evet | - | - |
  | `receiver_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `sender_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `status` | `VARCHAR(20)` | **Hayır** | `'pending'` | - |
  | `updated_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `friend_requests_select` (`SELECT`)
    - 🛡️ `friend_requests_insert` (`INSERT`)
    - 🛡️ `friend_requests_update` (`UPDATE`)
    - 🛡️ `friend_requests_all` (`ALL`)

- **Tablo:** `friends` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `friend_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_favorite` | `BOOLEAN` | **Hayır** | `false` | - |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `friends_all` (`ALL`)

- **Tablo:** `messages` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `attachment_type` | `VARCHAR(30)` | **Hayır** | `'text'` | - |
  | `attachment_url` | `TEXT` | Evet | - | - |
  | `chat_id` | `UUID` | **Hayır** | - | ↳ `public.chats(id)` |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `delivery_status` | `VARCHAR(20)` | **Hayır** | `'sent'` | - |
  | `expires_at` | `TIMESTAMP` | Evet | - | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_bookmarked` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_deleted` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_edited` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_read` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_view_once` | `BOOLEAN` | **Hayır** | `false` | - |
  | `media_urls` | `JSONB` | Evet | `'[]'::jsonb` | - |
  | `mentions` | `JSONB` | Evet | `'[]'::jsonb` | - |
  | `original_text` | `TEXT` | **Hayır** | `''` | - |
  | `reactions` | `JSONB` | Evet | `'{}'::jsonb` | - |
  | `read_at` | `TIMESTAMP` | Evet | - | - |
  | `reply_to_id` | `UUID` | Evet | - | ↳ `public.messages(id)` |
  | `sender_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `sender_name` | `VARCHAR(100)` | Evet | - | - |
  | `source_language` | `VARCHAR(10)` | **Hayır** | `'tr'` | - |
  | `target_language` | `VARCHAR(10)` | **Hayır** | `'en'` | - |
  | `translated_text` | `TEXT` | Evet | - | - |
  | `viewed_by` | `JSONB` | Evet | `'[]'::jsonb` | - |
  | `voice_duration_sec` | `INT` | Evet | `0` | - |
  | `voice_transcript` | `TEXT` | Evet | - | - |
  | `voice_waveform` | `JSONB` | Evet | `'[]'::jsonb` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `messages_select` (`SELECT`)
    - 🛡️ `messages_insert` (`INSERT`)
    - 🛡️ `messages_all` (`ALL`)

- **Tablo:** `notifications` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `body` | `TEXT` | **Hayır** | - | - |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `data` | `JSONB` | Evet | `'{}'::jsonb` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_read` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_silent` | `BOOLEAN` | **Hayır** | `false` | - |
  | `receiver_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `sender_id` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `title` | `VARCHAR(150)` | **Hayır** | - | - |
  | `type` | `VARCHAR(30)` | **Hayır** | - | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `notifications_all` (`ALL`)

- **Tablo:** `profiles` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `app_language` | `VARCHAR(10)` | **Hayır** | `'tr'` | - |
  | `approx_city` | `VARCHAR(100)` | Evet | - | - |
  | `approx_country` | `VARCHAR(10)` | Evet | `'TR'` | - |
  | `approx_lat` | `DOUBLE` | Evet | - | - |
  | `approx_lng` | `DOUBLE` | Evet | - | - |
  | `auto_voice_translate` | `BOOLEAN` | **Hayır** | `true` | - |
  | `avatar_url` | `TEXT` | Evet | - | - |
  | `bio` | `TEXT` | Evet | `''` | - |
  | `bubble_style` | `VARCHAR(20)` | **Hayır** | `'dark_pill'` | - |
  | `camera_translate_enabled` | `BOOLEAN` | **Hayır** | `true` | - |
  | `can_call_audio` | `BOOLEAN` | **Hayır** | `true` | - |
  | `can_call_video` | `BOOLEAN` | **Hayır** | `true` | - |
  | `can_message` | `BOOLEAN` | **Hayır** | `true` | - |
  | `can_post_story` | `BOOLEAN` | **Hayır** | `true` | - |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `discoverable_on_map` | `BOOLEAN` | **Hayır** | `false` | - |
  | `display_id` | `VARCHAR(50)` | Evet | - | - |
  | `email` | `VARCHAR(255)` | Evet | - | - |
  | `full_name` | `VARCHAR(100)` | **Hayır** | - | - |
  | `group_count` | `INT` | **Hayır** | `0` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `is_banned` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_online` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_suspended` | `BOOLEAN` | **Hayır** | `false` | - |
  | `is_verified` | `BOOLEAN` | **Hayır** | `false` | - |
  | `last_seen` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `message_count` | `INT` | **Hayır** | `0` | - |
  | `native_language` | `VARCHAR(10)` | **Hayır** | `'tr'` | - |
  | `phone` | `VARCHAR(40)` | Evet | - | - |
  | `role` | `VARCHAR(20)` | **Hayır** | `'user'` | - |
  | `spaces_count` | `INT` | **Hayır** | `0` | - |
  | `target_language` | `VARCHAR(10)` | **Hayır** | `'en'` | - |
  | `theme` | `VARCHAR(30)` | **Hayır** | `'warm_glass'` | - |
  | `updated_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `username` | `VARCHAR(50)` | **Hayır** | - | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `profiles_select` (`SELECT`)
    - 🛡️ `profiles_insert` (`INSERT`)
    - 🛡️ `profiles_update` (`UPDATE`)
    - 🛡️ `profiles_delete` (`DELETE`)

- **Tablo:** `reports` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `admin_notes` | `TEXT` | Evet | - | - |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `details` | `TEXT` | Evet | - | - |
  | `evidence_urls` | `JSONB` | Evet | `'[]'::jsonb` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `reason` | `VARCHAR(60)` | **Hayır** | - | - |
  | `reported_message_id` | `UUID` | Evet | - | ↳ `public.messages(id)` |
  | `reported_story_id` | `UUID` | Evet | - | ↳ `public.stories(id)` |
  | `reported_user_id` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `reporter_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `resolved_by` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `status` | `VARCHAR(20)` | **Hayır** | `'new'` | - |
  | `updated_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `reports_insert` (`INSERT`)
    - 🛡️ `reports_admin` (`ALL`)

- **Tablo:** `stories` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `bg_gradient` | `VARCHAR(50)` | Evet | - | - |
  | `caption` | `TEXT` | Evet | - | - |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `expires_at` | `TIMESTAMP` | Evet | `(NOW() + INTERVAL '24 hours')` | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `media_type` | `VARCHAR(20)` | **Hayır** | `'image'` | - |
  | `media_url` | `TEXT` | **Hayır** | - | - |
  | `reactions` | `JSONB` | Evet | `'{}'::jsonb` | - |
  | `translated_caption` | `TEXT` | Evet | - | - |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  | `viewer_ids` | `JSONB` | Evet | `'[]'::jsonb` | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `stories_select` (`SELECT`)
    - 🛡️ `stories_insert` (`INSERT`)
    - 🛡️ `stories_all` (`ALL`)

- **Tablo:** `system_settings` — *🟢 RLS Aktif* (PK: `key`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `key` | `VARCHAR(60)` | **Hayır** | - | - |
  | `updated_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `updated_by` | `UUID` | Evet | - | ↳ `public.profiles(id)` |
  | `value` | `JSONB` | **Hayır** | - | - |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `system_settings_select` (`SELECT`)
    - 🛡️ `system_settings_admin` (`ALL`)

- **Tablo:** `user_devices` — *🟢 RLS Aktif* (PK: `id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `created_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `device_name` | `VARCHAR(100)` | **Hayır** | - | - |
  | `fcm_token` | `TEXT` | Evet | - | - |
  | `id` | `UUID` | **Hayır** | `gen_random_uuid()` | - |
  | `ip_address` | `VARCHAR(45)` | Evet | - | - |
  | `is_current` | `BOOLEAN` | **Hayır** | `true` | - |
  | `last_active_at` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `platform` | `VARCHAR(30)` | **Hayır** | - | - |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `user_devices_all` (`ALL`)

- **Tablo:** `user_presence` — *🟢 RLS Aktif* (PK: `user_id`)
  | Sütun | Tip | Boş Olabilir? (NULL) | Varsayılan | İlişkiler |
  | :--- | :--- | :---: | :--- | :--- |
  | `active_Locale` | `VARCHAR(10)` | Evet | `'tr'` | - |
  | `is_online` | `BOOLEAN` | **Hayır** | `false` | - |
  | `last_heartbeat` | `TIMESTAMP` | Evet | `NOW()` | - |
  | `typing_in_chat_id` | `UUID` | Evet | - | ↳ `public.chats(id)` |
  | `user_id` | `UUID` | **Hayır** | - | ↳ `public.profiles(id)` |
  - **RLS Güvenlik Politikaları:**
    - 🛡️ `user_presence_all` (`ALL`)

<details><summary>🔍 Çözümlenemeyen / Özel DDL İfadeleri (101)</summary>

| Dosya | İfade Önizleme |
| :--- | :--- |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `CREATE EXTENSION IF NOT EXISTS "pg_trgm"` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `CREATE SEQUENCE IF NOT EXISTS public.juzzio_id_seq START WITH 1 INCREMENT BY 1` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `CREATE INDEX IF NOT EXISTS idx_profiles_username_trgm ON public.profiles USING gin (username gin_trgm_ops)` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `CREATE INDEX IF NOT EXISTS idx_profiles_fullname_trgm ON public.profiles USING gin (full_name gin_trgm_ops)` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT (id) DO NOTHING` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `INSERT INTO storage.buckets (id, name, public) VALUES ('media', 'media', true) ON CONFLICT (id) DO NOTHING` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `END` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `$$ LANGUAGE plpgsql SECURITY DEFINER` |
| `supabase/migrations/20261024000000_juzzio_schema.sql` | `v_display_id VARCHAR(50)` |

</details>

<!-- 🔒 PERMANENT_DB_SCHEMA_END -->

---

## ⚡ Termux ile 3 Saniyede Otomatik Dağıtım (Deploy Panel)

Android telefonunuzdan Termux ile projeyi GitHub'a göndermek artık tek bir tuşla mümkündür:

```bash
# Proje klasörüne geçin
cd "/sdcard/Download/Juzzio Pack" 2>/dev/null || cd "/sdcard/Juzzio Pack"

# Süper Dağıtım Panelini Çalıştırın
./deploy.sh
```

### Kısayol Kurulumu (İster 0, ister push, ister juzzio yazın!)
Panel üzerinden **[2]** seçeneğini seçtiğinizde veya terminale `./deploy.sh setup` yazdığınızda Termux sisteminize kısayollar eklenir:
* Artık nerede olursanız olun Termux'a **`0`**, **`push`**, **`juzzio`** veya **`Juzzio`** yazıp Enter'a bastığınızda sistem otomatik olarak:
  1. Gereksiz `.dart_tool/` ve `build/` önbelleklerini temizler,
  2. Git indeksini hafifletir,
  3. Projeyi 3-4 saniye içinde doğrudan GitHub'a push eder!

---

## 🌐 Sosyal Medya ve İletişim

Geliştirici ekiple iletişime geçmek, öneri bildirmek veya topluluğa katılmak için:

<div align="center">

[![Telegram](https://img.shields.io/badge/Telegram-tugkancr0-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/tugkancr0)
[![Instagram](https://img.shields.io/badge/Instagram-@tugkancr-E4405F?style=for-the-badge&logo=instagram&logoColor=white)](https://instagram.com/tugkancr)

💬 **Telegram:** [@tugkancr0](https://t.me/tugkancr0)  
📸 **Instagram:** [@tugkancr](https://instagram.com/tugkancr)

</div>

---

## 📄 Lisans ve Kurumsal Kullanım Şartları

Bu yazılım ve beraberindeki tüm mimari bileşenler **Juzzio Proprietary & Enterprise Source-Available License** şartlarına tabidir.

### Hüküm ve Politikalar:
1. **Fikri Mülkiyet:** Juzzio uygulaması, arayüz tasarımları, WebRTC canlı çeviri entegrasyonu ve veritabanı şema kasası hakları saklıdır.
2. **Kullanım İzni:** Bu depodaki kodlar kişisel kullanım, inceleme, test ve yetkili kurumsal dağıtım için serbesttir.
3. **Ticari Kısıtlama:** Yazılımın kaynak kodları, yazılı izin alınmaksızın doğrudan üçüncü taraf ticari platformlarda izinsiz olarak yeniden satılamaz veya ücretli paket halinde dağıtılamaz.
4. **Sorumluluk Reddi (Disclaimer):** Yazılım "olduğu gibi" (as-is) sunulmaktadır. Çeviri motorunun üçüncü taraf diller arasındaki anlık doğruluğu veya ağ gecikmelerinden kaynaklı WebRTC paket kayıplarından doğabilecek durumlarda geliştirici ekip sorumlu tutulamaz.

Telif Hakkı © 2026 **Juzzio & Tuğkan**. Tüm Hakları Saklıdır.
