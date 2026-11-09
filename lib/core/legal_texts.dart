// Otomatik üretildi: scripts/gen_legal.py — elle düzenlemeyin.

const String kJuzzioPrivacyMd = r'''# Juzzio Gizlilik Politikası ve KVKK Aydınlatma Metni

Son güncelleme: 9 Kasım 2026 · Uygulama sürümü: v0.9.9 (BETA · Erken Erişim)

Bu metin, Juzzio mobil uygulamasının hangi kişisel verileri hangi amaçla işlediğini, kimlerle paylaştığını ve haklarınızı **olduğu gibi** açıklar. Uygulamanın kaynak kodu GitHub'da açıktır; buradaki her ifade koddan doğrulanabilir.

## 1. Veri sorumlusu

- Juzzio, bağımsız bir geliştirici (Engin ÇIRPAN) tarafından geliştirilen bir BETA uygulamadır.
- İletişim ve başvurular: engiincr@pm.me
- Uygulama içinden: Ayarlar → Yardım ve Destek → Hata bildir / Geri bildirim

## 2. Kısa özet (en çok sorulanlar)

- **Kişisel verilerinizi satmıyoruz**, kiralamıyoruz, reklam ağlarıyla paylaşmıyoruz. Uygulamada reklam veya analitik/izleme kütüphanesi yoktur.
- **Kart veya banka bilginize erişimimiz yoktur.** Uygulamada ödeme, kart, banka veya cüzdan ile ilgili tek satır kod yoktur; bu bilgileri isteyen bir ekran da yoktur.
- **Kamera ve mikrofon izinsiz kullanılmaz.** Yalnızca Android izni verdikten sonra ve yalnızca şu durumlarda açılır: sizin başlattığınız veya kabul ettiğiniz arama, hikâye/gönderi kamerası, sesli mesaj kaydı. Aramalar kaydedilmez.
- **Rehberiniz ve SMS'leriniz okunmaz.** Konum yalnızca sizin başlattığınız işlemlerde, izninizle okunur: sohbette konum gönderme, güvenli takip (SOS) ve Göz Konforu'nun gün batımı modu. Arka planda konum izlenmez.
- **1'e 1 sohbetlerde mesajlar, fotoğraflar, videolar, sesli mesajlar, belgeler, konum ve hikâye yanıtları uçtan uca şifrelidir**; v0.8.0'dan itibaren kuantum sonrası (post-quantum) hibrit şifreleme kullanılır. Sunucu ve yöneticiler bu içerikleri göremez.
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
| Otomatik çökme raporları (hata türü, maskelenmiş yığın izi, sürüm, işletim sistemi) | Uygulama kararlılığı | Meşru menfaat (Ayarlar'dan kapatılabilir) |
| Günlük çeviri/döküm sayısı (içerik değil, yalnız adet) | Maliyet ve kötüye kullanım kontrolü | Meşru menfaat |

## 4. Uçtan uca şifreleme (v0.8.0 · kuantum sonrası hibrit)

- 1'e 1 yazılı mesajlar cihazınızda **X25519 + ML-KEM-768 (NIST FIPS 203)** hibrit anahtar değişimiyle oluşturulan anahtarla, **HKDF-SHA256** ve **AES-256-GCM** ile şifrelenir. Klasik ve kuantum sonrası yöntemin ikisi birden kırılmadıkça mesaj açılamaz; bu, bugün kaydedilip gelecekte kuantum bilgisayarla çözülme ("Harvest Now, Decrypt Later") riskine karşı korur.
- **Anahtar yenileme:** her 50 mesajda veya 24 saatte bir yeni oturum anahtarı, her 30 günde bir yeni kimlik anahtarı üretilir. Her mesaj kendi anahtarıyla şifrelenir.
- Özel anahtarlar yalnızca telefonunuzdaki güvenli depoda (Android Keystore) durur, sunucuya gönderilmez.
- Sunucuda yalnızca şifreli metin ve açık anahtarlar bulunur; bildirim önizlemesi "🔒 Şifreli mesaj" olarak gider.
- Güncelleme dosyalarının bütünlüğü SHA-256 ile; yayın imzası için ML-DSA (FIPS 204) doğrulama altyapısı uygulamada bulunur.
- **Fotoğraflar (v0.9.0):** 1'e 1 sohbette gönderilen fotoğraf cihazınızda, dosyaya özel rastgele anahtarla **AES-256-GCM** ile şifrelenir; anahtar ve **SHA-256** bütünlük özeti şifreli mesajın içinde taşınır. Sunucuda yalnızca şifreli dosya bulunur. Şifreleme yapılamazsa fotoğraf gönderilmez; bütünlük doğrulaması tutmazsa fotoğraf gösterilmez.
- **Zamanlanmış mesajlar (v0.9.0):** 1'e 1 sohbette zamanlanan mesaj cihazınızda şifrelenir ve sunucuda gönderim zamanına kadar yalnızca şifreli hâliyle bekler.
- **Sınırlar:** grup mesajları, grup anketleri ve grup sohbetlerindeki medya henüz uçtan uca şifreli değildir (aktarımda TLS ile şifrelenir, sunucuda yalnız grup üyelerinin erişebildiği özel depoda saklanır). 1'e 1 sohbetlerde videolar (40 MB'a kadar), sesli mesajlar, belgeler ve hikâye yanıtları v0.9.4–v0.9.6 ile uçtan uca şifrelidir. Otomatik çeviri **varsayılan olarak açıktır**; açıkken birebir sohbetlerdeki mesaj metni de çeviri için cihazınızdan çeviri hizmetine (Google Translate) gönderilir, sunucuda ise şifreli saklanmaya devam eder. Ayarlar → Gizlilik'ten kapatabilirsiniz. Kimlik doğrulama (giriş) Supabase'in standart oturum belirteçleriyle yapılır.

## 4a. Güvenlik Merkezi, cihazlar ve güvenlik olayları (v0.9.0)

- Hesabınıza bağlanan cihazlar, cihaz kimliğinin yalnızca son 6 hanesi ile size gösterilir; yeni cihaz girişi, cihaz kaldırma ve şifreleme anahtarı değişimi sunucu tarafından **güvenlik olayı** olarak kaydedilir. Bu kayıtları yalnızca siz görebilirsiniz; uygulama (istemci) bu kayıtları yazamaz veya değiştiremez.
- Kayıtlar hesabınız silindiğinde silinir.

## 4h. Yerel SQLite önbelleği, medya önbelleği ve arayüz (v0.9.7)

- **Anında açılış için yerel veritabanı:** Sohbet listesi, profiller ve her sohbetin son 300 mesajı cihazınızdaki, hesabınıza ayrılmış bir SQLite veritabanında (Drift) tutulur. Uçtan uca şifreli mesajlar bu veritabanına da **şifreli** yazılır; çözme yalnızca ekranda gösterilirken yapılır. Veritabanı oturumu kapattığınızda silinir.
- **Medya önbelleği:** Görüntülediğiniz medyanın cihazdaki önbellek sınırı (varsayılan 300 MB) ve azami dosya yaşı (varsayılan 60 gün) yönetici tarafından belirlenir; aşılınca en uzun süredir açılmayan dosyalar cihazınızdan otomatik silinir. Bu ayar sunucuya hiçbir kişisel veri göndermez.
- **Bildirim yığını, tema geçişleri ve kumaş yenileme** tamamen cihazda çalışır; yeni bir veri toplamaz.
- **Arama güç profili:** Arka planda veya zayıf ağda görüntü kalitesi geçici olarak 360p'ye düşürülür; bunun için ek veri işlenmez.

## 4g. Hata raporları, göz konforu, uçtan uca şifreli medya (v0.9.6)

- **Otomatik hata raporları:** Uygulama çöktüğünde veya bir hata oluştuğunda hata türü, yığın izi (kodun hangi satırında olduğu), uygulama sürümü, platform ve işletim sistemi sürümü sunucuya gönderilir. Mesaj içerikleri gönderilmez; e-posta adresleri, telefon numaraları, uzun sayı dizileri, oturum belirteçleri ve bağlantı parametreleri gönderilmeden önce cihazda maskelenir. Yalnız yetkili yönetici personeli görür; kayıtlar 90 gün sonra silinir. Ayarlar'dan "Hata raporlarını otomatik gönder" kapatılabilir.
- **Göz Konforu:** "Gün batımından gün doğumuna" modunda konumunuz yalnız bir kez, şehir düzeyine (~1 km) yuvarlanarak okunur ve yalnız cihazınızda saklanır; sunucuya gönderilmez.
- **Birebir sohbetlerde sesli mesaj, video ve hikâye yanıtları** artık uçtan uca şifrelidir. Sesli mesaj yazıya dökümü yalnız "şifreli sohbetlerde çeviri" tercihini açtıysanız, döküm süresince geçici olarak sunucuya yüklenen ve hemen silinen bir kopya üzerinden yapılır.
- **Yapay zekâ kullanım sayacı:** Maliyet kontrolü için günlük çeviri/döküm sayınız (içerik değil, yalnız adet) tutulur.
- **Yasal talepler:** Resmî bir talep olduğunda yalnız süper yönetici; profil, cihaz, gönderi, şikâyet ve denetim kayıtlarınızı gerekçesiyle birlikte kayıt altına alınarak dışa aktarabilir. Uçtan uca şifreli mesaj içerikleri sunucuda bulunmadığından bu pakete giremez.

## 4f. Güvenli takip, tek seferlik medya, soru kutusu, rozetler (v0.9.5)

- **Güvenli takip (SOS):** Yalnız siz başlattığınızda, uygulama açıkken dakikada bir konumunuz ve pil seviyeniz sunucuya yazılır ve yalnız seçtiğiniz sohbetin üyeleri görür. Takip bitince yeni konum yazılmaz. Uyarı bildirimleri son konum bağlantısını içerir. Acil durumlarda resmî acil çağrı numarasını arayın; Juzzio bir acil durum hizmeti değildir.
- **Tek seferlik medya:** Alıcı açıp kapattığında (veya açıldıktan 5 dakika sonra, açılmazsa 14 gün sonra) dosya sunucudan kalıcı olarak silinir. Görüntülerken Android'de ekran görüntüsü engellenir; başka bir cihazla fotoğrafının çekilmesi engellenemez.
- **Anonim soru kutusu:** Anonim soranın kimliği kutu sahibine gösterilmez. Kötüye kullanım şikâyetinde yalnız yetkili personel, erişimi kayıt altına alınarak gönderen kimliğini görebilir.
- **Rozetler, seriler ve güven puanı:** Uygulamayı açtığınız günler ve civciv besleme günleri seri için sayılır. Güven puanı; hesap yaşı, son 30 gündeki farklı şikâyetçi sayısı ve son 90 gündeki ihlallerden şeffaf kurallarla hesaplanır, yalnız moderasyon için kullanılır.
- **Watch Party:** Paylaştığınız video bağlantısı ve oynatma konumu yalnız o sohbetin üyelerine görünür.

## 4e. Konum, belgeler ve vardiyalar (v0.9.4)

- **Konum** yalnızca sohbette "Konum"a dokunduğunuzda, izninizle bir kez okunur ve mesaj olarak gönderilir; arka planda konum izlenmez. Birebir sohbette konum mesajı uçtan uca şifrelidir.
- **Belgeler** (PDF, ZIP, DOCX …) birebir sohbette dosya adıyla birlikte uçtan uca şifrelenerek saklanır; sunucu içeriği ve adı göremez. Grup sohbetlerindeki belgeler yalnız grup üyelerinin erişebildiği özel depoda tutulur.
- **Vardiya planı** yalnız size görünür; bir grupla paylaşırsanız yalnız o grubun üyeleri görür.
- Uygulama, cihaz saatini doğrulamak için sunucu saatini okur; bu işlem kişisel veri göndermez.

## 4d. Bildirim çevirisi ve güzelleştirme (v0.9.3)

- Gelen mesaj bildirimleri uygulama dilinize çevrilir. Uçtan uca şifreli mesajlarda metin önce **cihazınızda** çözülür; çeviri, sohbet içi çeviride olduğu gibi çeviri hizmetine (Google Çeviri) yalnızca o metin gönderilerek yapılır. Ayarlar → Bildirimler'den bildirim önizlemesini kapatırsanız içerik gösterilmez ve çevrilmez.
- Görüntülü arama ve hikâye fotoğraflarındaki güzelleştirme tamamen **cihazda** uygulanır; yüz verisi çıkarılmaz, saklanmaz veya gönderilmez.

## 4c. Cihazdaki çevrimdışı önbellek (v0.9.2)

- İnternet yokken okuyabilmeniz için her sohbetin son 300 mesajı, görüntülediğiniz fotoğraflar, profil resimleri ve dinlediğiniz sesli mesajlar **yalnızca bu cihazda**, hesabınıza ayrılmış uygulama klasöründe saklanır.
- Uçtan uca şifreli mesajlar ve fotoğraflar cihazda da **şifreli** saklanır; yalnızca ekranda gösterilirken bellekte çözülür.
- Önbellek oturumu kapattığınızda ve hesabınızı sildiğinizde silinir. Medya önbelleği sınırı v0.9.7'den itibaren yönetici tarafından belirlenir (varsayılan 300 MB); Ayarlar → Depolama → Önbelleği Temizle ile silebilirsiniz (mesajlarınız ve hesabınız silinmez).

## 4b. Sohbet yedeği (Google Drive)

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
- Göremez: uçtan uca şifreli mesaj ve medya içerikleri, şifreniz, kart/banka bilgisi (zaten yok). Yönetici panelinde serbest SQL konsolu yoktur; yasal dışa aktarım ve tüm oturumları kapatma gibi kritik işlemler yalnız süper yöneticiye açıktır ve denetim kaydına yazılır.
- Şifresiz içerikler (grup mesajları, medya) teknik olarak veritabanında okunabilir durumdadır; yönetici panelinde mesaj içeriğini gösteren bir işlev yoktur.

## 7. Saklama süreleri

- Hesabınız açık olduğu sürece veriler saklanır. Süreli mesajları açarsanız mesajlar seçtiğiniz süre sonunda silinir.
- Hikâyeler 24 saat sonra görünmez olur.
- Hesabınızı silebilirsiniz (Ayarlar → Hesap). Silinen mesaj, hikâye ve hesaplara ait medya dosyaları otomatik silme kuyruğuna alınır ve sunucu tarafında depodan silinir. Otomatik çökme raporları 90 gün sonra silinir.

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

const String kJuzzioPrivacyMdEn = r'''# 🔐 Juzzio Privacy Policy

Last updated: November 9, 2026 · App version: v0.9.9 (BETA · Early Access)

> 🇹🇷 The legally binding Turkish version (Privacy Policy and KVKK Disclosure Notice) is in [docs/legal/tr/PRIVACY.md](docs/legal/tr/PRIVACY.md). In the app, the Turkish text is shown when the app language is Turkish.

This document explains, **exactly as it is**, which personal data the Juzzio mobile app processes, why, who it is shared with, and what your rights are. The source code is public on GitHub, so every statement here can be verified against the code.

## 1. Data controller

- Juzzio is a BETA app built by an independent developer (Engin ÇIRPAN).
- Contact and requests: engiincr@pm.me
- In the app: Settings → Help & Support → Report a bug / Feedback

## 2. Short summary (most asked)

- **We do not sell, rent or share your personal data** with ad networks. The app contains no advertising, analytics or tracking libraries.
- **We have no access to your card or bank details.** The app contains no payment, card, bank or wallet code, and no screen asks for such information.
- **The camera and microphone are never used without permission.** They are only used after you grant the Android permission, and only for calls you start or accept, the story/post camera and voice message recording. Calls are not recorded.
- **Your contacts and SMS are never read.** Location is read only for actions you start, with your permission: sending your location in a chat, Safety Check (SOS) and the sunset mode of Eye Comfort. Location is never tracked in the background.
- **In 1:1 chats, messages, photos, videos, voice messages, documents, locations and story replies are end-to-end encrypted**, using post-quantum hybrid encryption since v0.8.0. The server and administrators cannot see this content.
- **Chat backup is optional** and lives in your own Google Drive account, encrypted with a password only you know. We cannot read it.

## 3. Data processed and purposes

| Data | Purpose | Legal basis (KVKK Art. 5 / GDPR Art. 6) |
| :-- | :-- | :-- |
| Email, username, name, profile photo, bio | Account creation, sign-in, profile | Performance of contract |
| Messages, photos, videos, voice messages, stories, posts | Messaging and sharing | Performance of contract |
| Call records (who, when, duration, status) | Call history, missed call notifications | Performance of contract |
| Notification (FCM) token, device ID | Sending notifications, abuse and ban enforcement | Legitimate interest |
| Language, theme, privacy and sound preferences | App settings | Performance of contract |
| Violation records (explicit content detection) | Community safety | Legitimate interest |
| Bug reports (text, optional screenshot, version, OS) | Fixing bugs | Explicit consent (you send them) |
| Automatic crash reports (error type, masked stack trace, version, OS) | App stability | Legitimate interest (can be turned off in Settings) |
| Daily translation/transcription count (a number only, never content) | Cost and abuse control | Legitimate interest |

## 4. End-to-end encryption (v0.8.0 · post-quantum hybrid)

- 1:1 messages are encrypted on your device with a key derived from a **X25519 + ML-KEM-768 (NIST FIPS 203)** hybrid key exchange, using **HKDF-SHA256** and **AES-256-GCM**. A message can only be opened if both the classical and the post-quantum method are broken, which protects against "Harvest Now, Decrypt Later" attacks.
- **Key rotation:** a new session key every 50 messages or 24 hours, and a new identity key every 30 days. Every message is encrypted with its own key.
- Private keys stay only in your phone's secure storage (Android Keystore) and are never sent to the server.
- The server only stores ciphertext and public keys; notification previews are sent as "🔒 Encrypted message".
- Update files are integrity-checked with SHA-256; the app contains ML-DSA (FIPS 204) release signature verification.
- **Media:** in 1:1 chats, photos, videos (up to 40 MB), voice messages, documents (including the file name) and story replies are encrypted on your device with a random per-file key using **AES-256-GCM**. The key and a **SHA-256** integrity hash travel inside the encrypted message. If encryption fails, nothing is sent; if the integrity check fails, nothing is shown.
- **Scheduled messages:** in 1:1 chats, scheduled messages are encrypted on your device and wait on the server only in encrypted form.
- **Limits:** group messages, group polls and media in group chats are not yet end-to-end encrypted (they are encrypted in transit with TLS and stored in private storage that only group members can access). Automatic translation is **on by default**; while it is on, the text of a message is sent from your device to the translation service (Google Translate) for translation, while it remains encrypted on the server. You can turn it off in Settings → Privacy. Sign-in uses Supabase's standard session tokens.

## 4a. Security Center, devices and security events (v0.9.0)

- Devices linked to your account are shown to you with only the last 6 characters of the device ID. New device sign-ins, device removals and encryption key changes are recorded by the server as **security events**. Only you can see these records; the app cannot write or change them.
- These records are deleted when your account is deleted.

## 4b. Chat backup (Google Drive)

- You can optionally create a backup from Settings → Back up messages / chats.
- The backup is written to the **hidden app folder** (appDataFolder) in the Google Drive of the account you choose. Juzzio only requests access to this folder and cannot see your other Drive files.
- The content is encrypted with **AES-256-GCM** using a key derived with **Argon2id** from a password of at least 8 characters that you choose. The password is never sent or stored anywhere; if you forget it, the backup cannot be opened.
- The backup is tied to your account ID; if the account is deleted and recreated, the old backup will not load.

## 4c. Offline cache on your device (v0.9.2)

- So you can read without internet, the last 300 messages of each chat, photos you viewed, profile pictures and voice messages you listened to are stored **only on this device**, in an app folder reserved for your account.
- End-to-end encrypted messages and media stay **encrypted** on the device and are only decrypted in memory while shown.
- The cache is deleted when you sign out or delete your account. Since v0.9.7 the media cache limit is set by the administrator (default 300 MB); you can clear it in Settings → Storage → Clear cache (your messages and account are not deleted).

## 4d. Notification translation and beauty filter (v0.9.3)

- Incoming message notifications are translated into your app language. For end-to-end encrypted messages, the text is first decrypted **on your device**; translation works like in-chat translation, sending only that text to the translation service (Google Translate). If you turn off notification previews in Settings → Notifications, content is neither shown nor translated.
- Beautification in video calls and story photos runs entirely **on your device**; no face data is extracted, stored or sent.

## 4e. Location, documents and shifts (v0.9.4)

- **Location** is read once, with your permission, only when you tap "Location" in a chat, and is sent as a message; it is never tracked in the background. In 1:1 chats, location messages are end-to-end encrypted.
- **Documents** (PDF, ZIP, DOCX …) in 1:1 chats are stored end-to-end encrypted together with their file name; the server cannot see the content or the name. Documents in group chats are kept in private storage accessible only to group members.
- Your **shift plan** is visible only to you; if you share it with a group, only that group's members can see it.
- The app reads the server time to verify your device clock; this sends no personal data.

## 4f. Safety Check, view-once media, question box, badges (v0.9.5)

- **Safety Check (SOS):** only when you start it, and while the app is open, your location and battery level are written to the server once a minute and are visible only to members of the chat you selected. No new location is written once it ends. Alert notifications include the last location link. In an emergency, call your official emergency number; Juzzio is not an emergency service.
- **View-once media:** once the recipient opens and closes it (or 5 minutes after opening, or 14 days if never opened) the file is permanently deleted from the server. Screenshots are blocked on Android while viewing; photographing the screen with another device cannot be prevented.
- **Anonymous question box:** the identity of an anonymous asker is never shown to the box owner. In an abuse report, only authorized staff can see the sender, and that access is logged.
- **Badges, streaks and trust score:** the days you open the app and the days you feed your chick count toward streaks. The trust score is calculated with transparent rules from account age, distinct reporters in the last 30 days and violations in the last 90 days, and is used only for moderation.
- **Watch Party:** the video link you share and the playback position are visible only to members of that chat.

## 4g. Crash reports, Eye Comfort, encrypted media (v0.9.6)

- **Automatic crash reports:** when the app crashes or an error occurs, the error type, stack trace (where in the code it happened), app version, platform and OS version are sent to the server. Message content is never sent; email addresses, phone numbers, long digit sequences, session tokens and link parameters are masked on the device before sending. Only authorized administrators can see them; records are deleted after 90 days. You can turn off "Send crash reports automatically" in Settings.
- **Eye Comfort:** in "Sunset to sunrise" mode your location is read once, rounded to city level (~1 km), and stored only on your device; it is never sent to the server.
- **Voice messages, videos and story replies in 1:1 chats** are end-to-end encrypted. Voice message transcription happens only if you turned on "translation in encrypted chats", using a temporary copy that is uploaded for the transcription and deleted immediately.
- **AI usage counter:** for cost control, the number of your daily translations/transcriptions is counted (a number only, not content).
- **Legal requests:** when there is an official request, only the super administrator can export your profile, device, post, report and audit records, together with the reason, and this export is logged. End-to-end encrypted message content does not exist on the server and therefore cannot be included.

## 4h. Local SQLite cache, media cache and interface (v0.9.7)

- **Local database for instant launch:** the chat list, profiles and the last 300 messages of each chat are kept in an SQLite database (Drift) on your device, reserved for your account. End-to-end encrypted messages are written to this database **encrypted** as well and are only decrypted while shown on screen. The database is deleted when you sign out.
- **Media cache:** the on-device cache limit for media you viewed (default 300 MB) and the maximum file age (default 60 days) are set by the administrator; when exceeded, the files you have not opened for the longest time are removed automatically from your device. This setting sends no personal data to the server.
- **Notification stack, theme transitions and cloth refresh** run entirely on your device and collect no new data.
- **Call power profile:** in the background or on a weak network, video quality is temporarily reduced to 360p; no additional data is processed for this.

## 5. Service providers that receive data

The following services are used to run Juzzio. Some are located abroad, so data may be transferred abroad (KVKK Art. 9).

- **Supabase** (database, file storage, authentication): account, message and media data.
- **LiveKit Cloud** (voice/video call server): audio and video streams during calls. Nothing is recorded.
- **Deepgram** (speech-to-text): your own voice is sent for captions only when someone **speaking a different language** is in the call or when you turn on live translation yourself. No audio is sent between people speaking the same language.
- **Google** – Firebase Cloud Messaging (notifications); Google Translate (automatic translation, from the device); optional Google Cloud Vision (only for explicit content checks in video calls; frames are not stored).
- **MyMemory** (fallback translation if Google Translate fails).
- **Apple iTunes Search** (the song name you type in the add-music screen is searched and a 30-second preview is played).
- **GitHub** (app updates and release notes).

## 6. What administrators can and cannot see

- Can see: the user list and emails, call record summaries, reports, bug and crash reports; they can delete content, close accounts and issue penalties.
- Cannot see: end-to-end encrypted message and media content, your password, card/bank details (there are none). There is no free-form SQL console in the admin panel; critical actions such as legal export and signing everyone out are limited to the super administrator and recorded in the audit log.
- Unencrypted content (group messages, group media) is technically readable in the database; the admin panel has no feature that displays message content.

## 7. Retention periods

- Data is kept while your account is open. If you turn on disappearing messages, messages are deleted after the period you choose.
- Stories disappear after 24 hours.
- You can delete your account (Settings → Account). Media files of deleted messages, stories and accounts are queued for automatic deletion and removed from storage on the server. Automatic crash reports are deleted after 90 days.

## 8. Security measures

- All connections are encrypted with HTTPS/TLS.
- Row-level security (RLS) in the database: users can only see chats they are a member of.
- Media folders can no longer be listed by anyone (v0.6.1).
- Updates are downloaded only from the official GitHub release; Android does not allow installing an APK with a different signature over the app.
- The source code contains no secret keys; an automatic secret scan runs on every push to GitHub, and a strict `.gitignore` keeps keys, certificates, local databases and build outputs out of the repository.
- Unauthorized access, attacks and reverse engineering attempts are logged and legal action is taken (see Terms of Use, section 8).

## 9. Your rights (KVKK Art. 11 and GDPR)

You have the right to learn whether your personal data is processed, request information about it, learn its purpose, know who it is transferred to, request correction of incomplete or inaccurate data, request its deletion or destruction, object, and claim compensation for damages. Send your requests to engiincr@pm.me; they are answered within 30 days at the latest. If you are in the European Union, your GDPR rights of access, rectification, erasure, portability and objection also apply.

## 10. Children

Juzzio is not designed for children under 13.

## 11. Changes

Changes to this policy are announced in the in-app "Release notes" section and on GitHub.
''';

const String kJuzzioTermsMdEn = r'''# 📜 Juzzio Terms of Use

Last updated: November 9, 2026 · v0.9.7 (BETA · Early Access)

> 🇹🇷 The legally binding Turkish version is in [docs/legal/tr/TERMS.md](docs/legal/tr/TERMS.md). In the app, the Turkish text is shown when the app language is Turkish.

## 1. Acceptance

By using Juzzio you accept these terms. Juzzio is a **BETA (Early Access)** app; features may change and bugs may occur.

## 2. Account

- You must provide accurate information when signing up; you are responsible for the security of your account.
- Inappropriate usernames, names or profile photos may not be used; creating fake or troll accounts is prohibited.

## 3. Community rules

- Slang and swearing in chats and calls are not, on their own, grounds for a ban.
- Nudity and showing genitals in video calls are prohibited and may be detected automatically. Penalty ladder: 1st violation 1 hour, 2nd violation 4 hours, 3rd violation permanent ban (including device and email).
- Harassment, threats, hate speech, fraud, sharing other people's personal data without permission and illegal content are prohibited.

## 4. Content

- You are responsible for the content you share. You keep the rights to your content and allow it to be processed to the extent needed to run the service (storing, delivering, displaying).
- Content that violates the rules may be removed and accounts may be suspended.

## 5. Consumer rights

- Juzzio is free; there are no in-app purchases, subscriptions or payments.
- Your rights under Turkish Consumer Protection Law No. 6502 and related legislation are reserved.

## 6. Limitation of liability

The service is provided "as is". Uninterrupted or error-free operation is not guaranteed. To the extent permitted by applicable law, no liability is accepted for indirect damages.

## 7. Intellectual property

Juzzio's source code, design, name and logo are protected by copyright. Copying, reproducing, distributing, selling or creating derivative apps without written permission is prohibited. Details: `LICENSE`.

## 8. Security breaches, attacks and unauthorized access

The following actions are strictly prohibited. When detected, the account and device are permanently banned, records (IP, device ID, timestamp) are kept as evidence and a criminal complaint is filed with the competent authorities:

- Accessing or attempting to access Juzzio servers, the database, storage or other users' accounts without authorization (**Turkish Penal Code Art. 243 – unauthorized access to an information system**),
- Obstructing or disrupting the system, deleting, altering or making data inaccessible; denial of service (DoS/DDoS), automated request flooding, brute-force attempts (**Turkish Penal Code Art. 244**),
- Using someone else's identity, session token or keys; phishing (**Turkish Penal Code Art. 245** and **Art. 158/1-f**),
- Unlawfully obtaining, recording or disseminating personal data (**Turkish Penal Code Art. 135–136**, **Personal Data Protection Law No. 6698 Art. 12 and 17**),
- Violating the confidentiality of communications, secretly listening to or recording calls or messages (**Turkish Penal Code Art. 132–133**),
- Decompiling the app, distributing modified/pirated versions, bypassing security measures (**Law on Intellectual and Artistic Works No. 5846 Art. 71–72**),
- Interfering with the service using malware, exploit code or automation tools (obligations under **Law No. 5651** are reserved).

Compensation for all material and moral damages arising from these actions will be claimed through legal means. If you found a security vulnerability, please write to **engiincr@pm.me** for responsible disclosure; no legal action is taken for good-faith reports made without causing harm.

## 9. Governing law

These terms are governed by the laws of the Republic of Türkiye. Istanbul (Central) Courts and Enforcement Offices have jurisdiction; consumers' rights to consumer arbitration committees and consumer courts under Law No. 6502 are reserved.

## 10. Contact

engiincr@pm.me
''';

const String kJuzzioLicenseTextEn = r'''JUZZIO PROPRIETARY SOFTWARE LICENSE (All Rights Reserved)

Copyright (c) 2026 Engin (@tugkancr) — Juzzio. All rights reserved.

The legally binding Turkish version of this license is in docs/legal/tr/LICENSE.txt.

1. SCOPE
This license covers the source code of the Juzzio application, compiled application
packages (including APKs), the database schema, server functions, design, user
interface, audio and visual assets, and the "Juzzio" name and logo (the "Software").
The Software is protected by Turkish Law No. 5846 on Intellectual and Artistic Works
and by international copyright treaties.

2. PERMITTED
a) Installing and using the app downloaded from the official channel (the GitHub
   releases page) on your device for personal, non-commercial purposes.
b) Viewing the source code on GitHub solely for transparency, security review and
   educational purposes.

3. PROHIBITED (without prior written permission)
a) Copying, reproducing, republishing or distributing all or part of the Software
   (including forked repositories and mirrors).
b) Selling, renting, licensing, offering for a fee, or using the Software in a
   commercial product or service.
c) Creating derivative works, clones or similar apps based on the Software; using its
   name, logo or design in another product.
d) Removing or altering license, copyright or attribution notices.
e) Repackaging the Software with a changed signature or distributing it through
   unofficial channels.

4. CONTRIBUTIONS
Contributions submitted to the repository (pull requests, etc.) are deemed to grant
the owner of the Software a perpetual, worldwide, non-exclusive right of use.

5. DISCLAIMER OF WARRANTY
The Software is provided "AS IS". No express or implied warranty is given. To the
maximum extent permitted by applicable law, the owner of the Software cannot be held
liable for damages arising from its use.

6. TERMINATION
If these terms are violated, the permission to use ends automatically, and the
violating party must delete all copies of the Software. The owner's right to take
legal action is reserved.

7. SECURITY AND UNAUTHORIZED ACCESS
Bypassing the security measures of the Software, its servers or its database,
unauthorized access, denial of service, data theft, distributing modified/pirated
versions and reverse engineering are criminal offences under Turkish Penal Code
No. 5237 Art. 132-136 and 243-245, Personal Data Protection Law No. 6698, Law No. 5846
Art. 71-72 and Law No. 5651. Detected attempts are logged, kept as evidence and
reported to the authorities; resulting damages will be claimed. Good-faith security
reports: engiincr@pm.me

8. GOVERNING LAW
This license is governed by the laws of the Republic of Türkiye. Place of
jurisdiction: Istanbul (Central) Courts and Enforcement Offices.

Permissions and contact: engiincr@pm.me
''';
