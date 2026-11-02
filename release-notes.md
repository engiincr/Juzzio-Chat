# Juzzio v0.9.0 — Ürün Konsolidasyonu, Business ve Güvenlik Merkezi

## Neden bu güncelleme?

Uygulamayı tek bir sade ürüne toplamak (Personal 5 sekme, Business hesabı), bildirim ve aramaları sağlamlaştırmak, güvenliği sertleştirmek ve uçtan uca şifrelemeyi fotoğraflara genişletmek için getirildi.

## ✨ Yeni özellikler

- Yeni ana gezinme: Ana Sayfa, Sohbetler, Keşfet, Bildirimler, Profil; geri tuşu önce paneli/sohbeti kapatır, çıkıştan önce uyarır
- Business hesabı: Genel Bakış, Gelen Kutusu (atama, otomatik yanıt), Müşteriler (CRM, not, takip), İş Alanı (randevu, ekip, görev, analiz)
- Yaşam Merkezi: görevler ve mesaj hatırlatıcıları; kayıtlı mesajlar; gelişmiş mesaj arama
- Mesaj düzenleme (15 dk) ve düzenleme geçmişi; sohbet kilidi; @etiketleme ve 'beni kim etiketleyebilir'
- Güvenlik Merkezi: cihazlar, diğer oturumları kapat, doğrulanabilir güvenlik uyarıları, şifreli yedek durumu
- Dosya Merkezi: sohbetlerdeki medya, belge ve sesli mesajlar
- Grup anketleri (tekli/çoklu, gizli oylama) ve zamanlanmış mesajlar
- Sesli mesajda 1x / 1.5x / 2x oynatma hızı
- Bildirimden yanıtla, gelen aramayı bildirimden reddet; sohbet başına bildirim ayarları; yazıyor göstergesi

## 🛠️ Düzeltilen hatalar

- Sohbet içindeyken geri tuşu artık uygulamadan çıkmıyor
- Keşfet metin rengi açık temalarda okunur
- Tepki bildirimi şifreli metni önizlemeye kopyalamıyor
- Gelen arama tam ekran izni eklendi

## 🔒 Güvenlik ve gizlilik

- Birebir sohbet fotoğrafları uçtan uca şifreli (AES-256-GCM + SHA-256 bütünlük); şifrelenemezse gönderilmez
- Kilit ekranında mesaj bildirimleri gizli; önizleme modu seçilebilir
- Zamanlanmış birebir mesajlar sunucuda yalnız şifreli saklanır
- Tüm yeni tablolarda satır düzeyi güvenlik (RLS); güvenlik olaylarını istemci yazamaz

---

<details><summary>English</summary>

## Why this update?

Consolidates the app into one focused product (5 Personal tabs, Business account), hardens notifications, calls and security, and extends end-to-end encryption to photos.

## ✨ New features

- New navigation: Home, Chats, Explore, Notifications, Profile; back button closes panels/chat first and warns before exit
- Business account: Overview, Inbox (assignment, auto replies), Customers (CRM, notes, follow-ups), Workspace (appointments, team, tasks, analytics)
- Life Center: tasks and message reminders; saved messages; advanced message search
- Message editing (15 min) with edit history; chat lock; @mentions and 'who can mention me'
- Security Center: devices, sign out other sessions, verifiable security alerts, encrypted backup status
- File Center: media, documents and voice messages from your chats
- Group polls (single/multiple choice, anonymous) and scheduled messages
- Voice message playback speed 1x / 1.5x / 2x
- Reply from notification, decline incoming calls from notification; per-chat notification settings; typing indicator

## 🛠️ Fixed bugs

- Back button inside a chat no longer exits the app
- Explore text colour readable on light themes
- Reaction notifications no longer copy encrypted text into previews
- Full-screen intent permission added for incoming calls

## 🔒 Security and privacy

- Direct-chat photos are end-to-end encrypted (AES-256-GCM + SHA-256 integrity); never sent unencrypted
- Message notifications are private on the lock screen; preview mode selectable
- Scheduled direct messages are stored server-side only in encrypted form
- Row-level security on all new tables; clients cannot write security events

</details>

