# Juzzio Gizlilik Politikası ve KVKK Aydınlatma Metni

Son güncelleme: 9 Kasım 2026 · Uygulama sürümü: v1.1.1 (BETA · Erken Erişim)

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
- **Deepgram** (konuşmadan yazıya): yalnızca aramada **farklı dil konuşan** biri olduğunda veya canlı çeviriyi kendiniz açtığınızda, kendi sesiniz altyazı için gönderilir. Aynı dili konuşanlar arasında ses gönderilmez. Gönderildiğinde de yalnız gerçekten konuştuğunuz anların sesi gider: sessizlik ve oda sesi gönderilmeden önce cihazınızda dijital sessizlikle değiştirilir.
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
