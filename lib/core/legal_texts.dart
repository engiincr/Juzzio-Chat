// Otomatik üretildi: scripts/gen_legal.py — elle düzenlemeyin.

const String kJuzzioPrivacyMd = r'''# Juzzio Gizlilik Politikası ve KVKK Aydınlatma Metni

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
''';

const String kJuzzioTermsMd = r'''# Juzzio Kullanım Koşulları

Son güncelleme: 1 Kasım 2026 · v0.7.0 (BETA · Erken Erişim)

## 1. Kabul

Juzzio'yu kullanarak bu koşulları kabul etmiş olursunuz. Juzzio bir **BETA (Erken Erişim)** uygulamasıdır; özellikler değişebilir, hatalar olabilir.

## 2. Hesap

- Kayıt olurken doğru bilgi vermelisiniz; hesabınızın güvenliğinden siz sorumlusunuz.
- Uygunsuz kullanıcı adı, ad veya profil fotoğrafı kullanılamaz; sahte veya trol hesap açmak yasaktır.

## 3. Topluluk kuralları

- Sohbetlerde ve aramalarda argo ve küfür kullanmak tek başına yasak sebebi değildir.
- Görüntülü aramada çıplaklık ve cinsel organ gösterimi yasaktır ve otomatik olarak tespit edilebilir. Ceza basamağı: 1. ihlal 1 saat, 2. ihlal 4 saat, 3. ihlal kalıcı engel (cihaz ve e-posta dahil).
- Taciz, tehdit, nefret söylemi, dolandırıcılık, başkasının kişisel verilerini izinsiz paylaşma ve yasa dışı içerik yasaktır.

## 4. İçerik

- Paylaştığınız içerikten siz sorumlusunuz. İçeriğinizin hakları sizde kalır; hizmetin çalışması için gereken ölçüde (saklama, iletme, gösterme) işlenmesine izin vermiş olursunuz.
- Kurallara aykırı içerikler kaldırılabilir, hesaplar askıya alınabilir.

## 5. Tüketici hakları

- Juzzio ücretsizdir; uygulama içi satın alma, abonelik veya ödeme yoktur.
- 6502 sayılı Tüketicinin Korunması Hakkında Kanun ve ilgili mevzuattan doğan haklarınız saklıdır.

## 6. Sorumluluğun sınırlandırılması

Hizmet "olduğu gibi" sunulur. Kesintisiz veya hatasız çalışacağı garanti edilmez. Yürürlükteki hukukun izin verdiği ölçüde dolaylı zararlardan sorumluluk kabul edilmez.

## 7. Fikri mülkiyet

Juzzio'nun kaynak kodu, tasarımı, adı ve logosu telif hakkıyla korunur. Kopyalanması, çoğaltılması, dağıtılması, satılması ve türev uygulama yapılması yazılı izin olmadan yasaktır. Ayrıntılar: `LICENSE`.

## 8. Güvenlik ihlalleri, saldırılar ve izinsiz erişim

Aşağıdaki eylemler kesinlikle yasaktır ve tespit edildiğinde hesap ve cihaz kalıcı olarak engellenir, kayıtlar (IP, cihaz kimliği, zaman damgası) delil olarak saklanır ve yetkili makamlara suç duyurusunda bulunulur:

- Juzzio sunucularına, veritabanına, depolama alanına veya diğer kullanıcıların hesaplarına izinsiz erişmek ya da erişmeye çalışmak (**TCK m.243 – bilişim sistemine girme**),
- Sistemin işleyişini engellemek, bozmak, verileri silmek, değiştirmek veya erişilmez kılmak; hizmet engelleme (DoS/DDoS), otomatik istek bombardımanı, kaba kuvvet denemeleri (**TCK m.244**),
- Başkasına ait kimlik, oturum belirteci veya anahtarları kullanmak; kimlik avı (phishing) yapmak (**TCK m.245** ve **TCK m.158/1-f**),
- Kişisel verileri hukuka aykırı olarak ele geçirmek, kaydetmek, yaymak (**TCK m.135–136**, **6698 sayılı KVKK m.12 ve m.17**),
- Haberleşmenin gizliliğini ihlal etmek, aramaları veya mesajları gizlice dinlemek/kaydetmek (**TCK m.132–133**),
- Uygulamayı kaynak koda dönüştürmek (decompile), değiştirilmiş/korsan sürümünü dağıtmak, güvenlik önlemlerini aşmak (**5846 sayılı Fikir ve Sanat Eserleri Kanunu m.71–72**),
- Zararlı yazılım, istismar kodu veya otomasyon araçlarıyla hizmete müdahale etmek (**5651 sayılı Kanun** kapsamındaki yükümlülükler saklıdır).

Bu eylemlerden doğan her türlü maddi ve manevi zararın tazmini hukuk yoluyla talep edilir. Güvenlik açığı bulduysanız sorumlu bildirim için lütfen **engiincr@pm.me** adresine yazın; iyi niyetli ve zarar vermeden yapılan bildirimler için yasal yola başvurulmaz.

## 9. Uygulanacak hukuk

Bu koşullar Türkiye Cumhuriyeti hukukuna tabidir. Uyuşmazlıklarda İstanbul (Merkez) Mahkemeleri ve İcra Daireleri yetkilidir; tüketiciler için 6502 sayılı Kanun'daki tüketici hakem heyeti ve tüketici mahkemesi hakları saklıdır.

## 10. İletişim

engiincr@pm.me
''';

const String kJuzzioLicenseText = r'''JUZZIO TESCİLLİ YAZILIM LİSANSI (Tüm Hakları Saklıdır)
Juzzio Proprietary Software License (All Rights Reserved)

Telif Hakkı (c) 2026 Engin (@tugkancr) — Juzzio. Tüm hakları saklıdır.
Copyright (c) 2026 Engin (@tugkancr) — Juzzio. All rights reserved.

1. KAPSAM
Bu lisans; Juzzio uygulamasının kaynak kodunu, derlenmiş uygulama paketlerini (APK
dahil), veritabanı şemasını, sunucu fonksiyonlarını, tasarımını, arayüzünü, ses ve
görsel varlıklarını, "Juzzio" adını ve logosunu ("Yazılım") kapsar. Yazılım 5846
sayılı Fikir ve Sanat Eserleri Kanunu ve uluslararası telif hakkı anlaşmalarıyla
korunmaktadır.

2. İZİN VERİLENLER
a) Resmi kanaldan (GitHub sürüm sayfası) indirilen uygulamanın kişisel ve ticari
   olmayan amaçla cihazınıza kurulup kullanılması.
b) Kaynak kodun yalnızca şeffaflık, güvenlik incelemesi ve eğitim amacıyla
   GitHub üzerinde görüntülenmesi.

3. YASAK OLANLAR (yazılı izin olmadan)
a) Yazılımın tamamının veya bir bölümünün kopyalanması, çoğaltılması, yeniden
   yayımlanması veya dağıtılması (çatallanmış depolar ve aynalar dahil).
b) Yazılımın satılması, kiralanması, lisanslanması, ücret karşılığı sunulması veya
   ticari bir ürün ya da hizmette kullanılması.
c) Yazılıma dayalı türev çalışma, klon veya benzer uygulama üretilmesi; adının,
   logosunun veya tasarımının başka bir üründe kullanılması.
d) Lisans, telif hakkı veya kaynak bildirimlerinin kaldırılması ya da değiştirilmesi.
e) Yazılımın imzasının değiştirilerek yeniden paketlenmesi veya resmi olmayan
   kanallardan dağıtılması.

4. KATKILAR
Depoya gönderilen katkılar (pull request vb.), gönderen tarafından Yazılım sahibine
süresiz, dünya çapında ve münhasır olmayan kullanım hakkıyla devredilmiş sayılır.

5. GARANTİ REDDİ
Yazılım "OLDUĞU GİBİ" sunulur. Açık veya zımni hiçbir garanti verilmez. Yürürlükteki
hukukun izin verdiği azami ölçüde Yazılım sahibi, kullanımdan doğan zararlardan
sorumlu tutulamaz.

6. FESİH
Bu koşulların ihlali hâlinde verilen kullanım izni kendiliğinden sona erer; ihlal
eden taraf Yazılımın tüm kopyalarını silmekle yükümlüdür. Yazılım sahibinin yasal
yollara başvurma hakkı saklıdır.

7. GÜVENLİK VE İZİNSİZ ERİŞİM
Yazılımın, sunucularının veya veritabanının güvenlik önlemlerini aşmak, izinsiz erişim,
hizmet engelleme, veri ele geçirme, değiştirilmiş/korsan sürüm dağıtma ve tersine
mühendislik; 5237 sayılı TCK m.132-136 ve m.243-245, 6698 sayılı KVKK, 5846 sayılı
FSEK m.71-72 ve 5651 sayılı Kanun kapsamında suçtur. Tespit edilen girişimler kayıt
altına alınır, delil olarak saklanır ve suç duyurusunda bulunulur; doğan zararlar
tazmin ettirilir. İyi niyetli güvenlik bildirimleri: engiincr@pm.me

8. UYGULANACAK HUKUK
Bu lisans Türkiye Cumhuriyeti hukukuna tabidir. Yetkili yer: İstanbul (Merkez)
Mahkemeleri ve İcra Daireleri.

İzin ve iletişim: engiincr@pm.me

-------------------------------------------------------------------------------
ENGLISH SUMMARY: This software is proprietary. You may install and use the official
release for personal, non-commercial purposes and view the source for transparency
and security review only. Copying, redistributing, selling, sublicensing, creating
derivative works or clones, or reusing the name, logo or design without prior written
permission is prohibited. Unauthorized access, attacks, tampering and reverse
engineering are criminal offences under Turkish law and will be prosecuted. Provided "AS IS" without warranty. Governed by the laws of
the Republic of Türkiye.
''';
