# Juzzio Gizlilik Politikası ve KVKK Aydınlatma Metni

Son güncelleme: 1 Kasım 2026 · Uygulama sürümü: v0.8.0 (BETA · Erken Erişim)

Bu metin, Juzzio mobil uygulamasının hangi kişisel verileri hangi amaçla işlediğini, kimlerle paylaştığını ve haklarınızı **olduğu gibi** açıklar. Uygulamanın kaynak kodu GitHub'da açıktır; buradaki her ifade koddan doğrulanabilir.

## 1. Veri sorumlusu

- Juzzio, bağımsız bir geliştirici (Engin ÇIRPAN) tarafından geliştirilen bir BETA uygulamadır.
- İletişim ve başvurular: engiincr@pm.me
- Uygulama içinden: Ayarlar → Yardım ve Destek → Hata bildir / Geri bildirim

## 2. Kısa özet (en çok sorulanlar)

- **Kişisel verilerinizi satmıyoruz**, kiralamıyoruz, reklam ağlarıyla paylaşmıyoruz. Uygulamada reklam veya analitik/izleme kütüphanesi yoktur.
- **Kart veya banka bilginize erişimimiz yoktur.** Uygulamada ödeme, kart, banka veya cüzdan ile ilgili tek satır kod yoktur; bu bilgileri isteyen bir ekran da yoktur.
- **Kamera ve mikrofon izinsiz kullanılmaz.** Yalnızca Android izni verdikten sonra ve yalnızca şu durumlarda açılır: sizin başlattığınız veya kabul ettiğiniz arama, hikâye/gönderi kamerası, sesli mesaj kaydı. Aramalar kaydedilmez.
- **Rehberiniz, SMS'leriniz ve konumunuz okunmaz.** Konum izni v0.6.1'de uygulamadan tamamen kaldırıldı.
- **1'e 1 yazılı mesajlar uçtan uca şifrelidir** ve v0.8.0'dan itibaren kuantum sonrası (post-quantum) hibrit şifreleme kullanır. Sunucu ve yöneticiler bu mesajların içeriğini göremez.
- **Sohbet yedeği isteğe bağlıdır** ve kendi Google Drive hesabınızda, sizin belirlediğiniz şifreyle şifrelenmiş olarak durur. Biz yedeği okuyamayız.

## 3. İşlenen veriler ve amaçları

| Veri | Amaç | Hukuki sebep (KVKK m.5) |
| :-- | :-- | :-- |
| E-posta, kullanıcı adı, ad, profil fotoğrafı, biyografi | Hesap oluşturma, giriş, profil | Sözleşmenin ifası |
| Mesajlar, fotoğraflar, videolar, sesli mesajlar, hikâyeler, gönderiler | Mesajlaşma ve paylaşım hizmeti | Sözleşmenin ifası |
| Arama kayıtları (kim, ne zaman, süre, durum) | Arama geçmişi, cevapsız arama bildirimi | Sözleşmenin ifası |
| Bildirim (FCM) belirteci, cihaz kimliği | Bildirim gönderme, kötüye kullanım ve yasak kontrolü | Meşru menfaat |
| Dil, tema, gizlilik ve ses tercihleri | Uygulama ayarları | Sözleşmenin ifası |
| İhlal kayıtları (müstehcen görüntü tespiti) | Topluluk güvenliği | Meşru menfaat |
| Hata bildirimleri (metin, isteğe bağlı ekran görüntüsü, sürüm, işletim sistemi) | Hataları düzeltmek | Açık rıza (siz gönderirsiniz) |

## 4. Uçtan uca şifreleme (v0.8.0 · kuantum sonrası hibrit)

- 1'e 1 yazılı mesajlar cihazınızda **X25519 + ML-KEM-768 (NIST FIPS 203)** hibrit anahtar değişimiyle oluşturulan anahtarla, **HKDF-SHA256** ve **AES-256-GCM** ile şifrelenir. Klasik ve kuantum sonrası yöntemin ikisi birden kırılmadıkça mesaj açılamaz; bu, bugün kaydedilip gelecekte kuantum bilgisayarla çözülme ("Harvest Now, Decrypt Later") riskine karşı korur.
- **Anahtar yenileme:** her 50 mesajda veya 24 saatte bir yeni oturum anahtarı, her 30 günde bir yeni kimlik anahtarı üretilir. Her mesaj kendi anahtarıyla şifrelenir.
- Özel anahtarlar yalnızca telefonunuzdaki güvenli depoda (Android Keystore) durur, sunucuya gönderilmez.
- Sunucuda yalnızca şifreli metin ve açık anahtarlar bulunur; bildirim önizlemesi "🔒 Şifreli mesaj" olarak gider.
- Güncelleme dosyalarının bütünlüğü SHA-256 ile; yayın imzası için ML-DSA (FIPS 204) doğrulama altyapısı uygulamada bulunur.
- **Sınırlar:** grup mesajları, fotoğraf/video/sesli mesajlar henüz uçtan uca şifreli değildir (aktarımda TLS ile şifrelenir, sunucuda saklanır). Otomatik çeviri açıkken mesaj metni çeviri için cihazınızdan çeviri hizmetine gönderilir. Kimlik doğrulama (giriş) Supabase'in standart oturum belirteçleriyle yapılır.

## 4a. Sohbet yedeği (Google Drive)

- Ayarlar → Mesajları / Sohbetleri yedekle bölümünden isteğe bağlı olarak yedek alabilirsiniz.
- Yedek, sizin seçtiğiniz Google hesabının Drive'ındaki **gizli uygulama klasörüne** (appDataFolder) yazılır. Juzzio yalnızca bu klasöre erişim ister; Drive'daki diğer dosyalarınızı göremez.
- İçerik, belirlediğiniz en az 8 karakterlik şifreden **Argon2id** ile türetilen anahtarla **AES-256-GCM** ile şifrelenir. Şifre hiçbir yere gönderilmez ve saklanmaz; unutulursa yedek açılamaz.
- Yedek hesap kimliğinize bağlıdır; hesap silinip yeniden açılırsa eski yedek yüklenmez.

## 5. Verilerin aktarıldığı hizmet sağlayıcılar

Juzzio'nun çalışması için aşağıdaki hizmetler kullanılır. Bunların bir kısmı yurt dışında bulunduğundan veriler yurt dışına aktarılabilir (KVKK m.9).

- **Supabase** (veritabanı, dosya depolama, kimlik doğrulama): hesap, mesaj ve medya verileri.
- **LiveKit Cloud** (sesli/görüntülü arama sunucusu): arama sırasında ses ve görüntü akışı. Kayıt yapılmaz.
- **Deepgram** (konuşmadan yazıya): yalnızca aramada **farklı dil konuşan** biri olduğunda veya canlı çeviriyi kendiniz açtığınızda, kendi sesiniz altyazı için gönderilir. Aynı dili konuşanlar arasında ses gönderilmez.
- **Google** – Firebase Cloud Messaging (bildirimler); Google Çeviri (otomatik çeviri, cihazdan); isteğe bağlı Google Cloud Vision (yalnızca görüntülü aramada müstehcen görüntü denetimi; kareler saklanmaz).
- **MyMemory** (Google çevirisi çalışmazsa yedek çeviri).
- **Apple iTunes Search** (müzik ekle ekranında yazdığınız şarkı adı aranır, 30 sn önizleme dinletilir).
- **GitHub** (uygulama güncellemeleri ve sürüm notları).

## 6. Yöneticinin görebildikleri ve göremedikleri

- Görebilir: kullanıcı listesi ve e-postalar, arama kayıtlarının özeti, şikâyetler, hata bildirimleri; içerik silme, hesap kapatma ve ceza verme yetkisi vardır.
- Göremez: uçtan uca şifreli mesaj içerikleri, şifreniz, kart/banka bilgisi (zaten yok).
- Şifresiz içerikler (grup mesajları, medya) teknik olarak veritabanında okunabilir durumdadır; yönetici panelinde mesaj içeriğini gösteren bir işlev yoktur.

## 7. Saklama süreleri

- Hesabınız açık olduğu sürece veriler saklanır. Süreli mesajları açarsanız mesajlar seçtiğiniz süre sonunda silinir.
- Hikâyeler 24 saat sonra görünmez olur.
- Hesabınızı silebilirsiniz (Ayarlar → Hesap). Not: yüklediğiniz medya dosyalarının depodan silinmesi için e-postayla başvurabilirsiniz; otomatik silme geliştirme aşamasındadır.

## 8. Güvenlik önlemleri

- Tüm bağlantılar HTTPS/TLS ile şifrelidir.
- Veritabanında satır düzeyi güvenlik (RLS): kullanıcı yalnızca üyesi olduğu sohbetleri görebilir.
- Medya klasörleri artık herkes tarafından listelenemez (v0.6.1).
- Güncellemeler yalnızca resmi GitHub sürümünden iner; Android farklı imzalı bir APK'nın üzerine kurulmasına izin vermez.
- Kaynak kodda gizli anahtar bulunmaz; GitHub üzerinde her gönderimde otomatik sır taraması yapılır.
- Yetkisiz erişim, saldırı ve tersine mühendislik girişimleri kayıt altına alınır ve yasal yollara başvurulur (bkz. Kullanım Koşulları madde 8).

## 9. KVKK m.11 kapsamındaki haklarınız

Kişisel verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, amacını öğrenme, aktarıldığı kişileri bilme, eksik/yanlış verinin düzeltilmesini, silinmesini veya yok edilmesini isteme, itiraz etme ve zarara uğramanız hâlinde zararın giderilmesini talep etme haklarına sahipsiniz. Başvurularınızı engiincr@pm.me adresine iletebilirsiniz; en geç 30 gün içinde yanıtlanır. Avrupa Birliği'ndeyseniz GDPR kapsamındaki erişim, düzeltme, silme, taşınabilirlik ve itiraz haklarınız da geçerlidir.

## 10. Çocuklar

Juzzio 13 yaşından küçükler için tasarlanmamıştır.

## 11. Değişiklikler

Bu politika değiştiğinde uygulamadaki "Güncelleme notları" bölümünde ve GitHub'da duyurulur.
