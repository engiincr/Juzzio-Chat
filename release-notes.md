# Juzzio v0.9.2 — Çevrimdışı Sohbetler ve Medya

## Neden bu güncelleme?

İnternet yokken de sohbetlerin, fotoğrafların, sesli mesajların ve profillerin WhatsApp'taki gibi açılabilmesi için getirildi.

## ✨ Yeni özellikler

- Çevrimdışı sohbet: her sohbetin son 300 mesajı cihazda saklanır, internet yokken okunabilir
- Görüntülenen fotoğraflar ve profil resimleri cihazda saklanır, internetsiz görünür
- Dinlenen sesli mesajlar internetsiz tekrar çalınabilir
- Kişi profilleri internet yokken son görülen hâliyle açılır
- Bağlantı gelince sohbet kendiliğinden yenilenir (5 sn arayla yeniden bağlanır)

## 🛠️ Düzeltilen hatalar

- İnternet yokken şifreli mesajlar 'kilitli' görünmüyor; anahtarlar cihazdan okunur
- Hesap silindiğinde cihazdaki önbellek de siliniyor

## 🔒 Güvenlik ve gizlilik

- Şifreli mesajlar ve şifreli fotoğraflar cihazda da şifreli hâliyle saklanır; çözme yalnız bellekte
- Önbellek hesaba özeldir; çıkışta ve hesap silmede silinir
- Medya önbelleği en fazla 300 MB; Ayarlar > Depolama > Önbelleği Temizle ile silinebilir (mesajlar silinmez)

---

<details><summary>English</summary>

## Why this update?

Lets chats, photos, voice messages and profiles open without internet, like WhatsApp.

## ✨ New features

- Offline chats: the last 300 messages of each chat are kept on the device and readable without internet
- Viewed photos and profile pictures are stored on the device and shown offline
- Played voice messages can be replayed offline
- Contact profiles open offline with their last seen data
- Chats refresh automatically when the connection returns (reconnects every 5 s)

## 🛠️ Fixed bugs

- Encrypted messages no longer show as locked while offline; keys are read from the device
- Deleting the account also deletes the on-device cache

## 🔒 Security and privacy

- Encrypted messages and photos are stored encrypted on the device too; decryption happens only in memory
- The cache is per account and is deleted on sign-out and account deletion
- Media cache is capped at 300 MB and can be cleared in Settings > Storage > Clear cache (messages are kept)

</details>

## İndirme

- Son sürüm: [Juzzio-latest.apk](https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk)
- Bu sürüm: `juzzio-v0.9.2-release.apk` (100.30 MB)

## APK doğrulama

```bash
sha256sum Juzzio-latest.apk
# 7e1be1db21b0520d7c8b0964486c5b69e39aea1777bf29772e9fd2a18be6d3d0  Juzzio-latest.apk
```

Derleme zamanı: 2026-11-02 09:28 UTC — GitHub Actions
