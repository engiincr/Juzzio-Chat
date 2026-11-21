# Juzzio 2.1 — Yeniden Tasarım Yol Haritası

Kaynak: kullanıcının 21.11.2026'da gönderdiği 15 görsel + 3 PSD
(Kayıt/Giriş/Keşfet/Aramalar/Bildirimler/Profil, Ayarlar takımı, Sesli/Görüntülü arama,
Profil karekod, Hikâye oluştur, Arkadaşlık istekleri, Yönetici Paneli 24–34 modül,
Google Play yol haritası, RLS/yetki denetimleri, yeni logo).

Durum (21.11.2026 sabahı): **Juzzio 2.1.0** — Faz 1–6 tamamlandı (ekran paylaşımı ve kamerayla QR tarama dahil).
Tüm fazlar işlendi. Açık kalanlar ([~]): 3.3, 8.2 otomatik indirme, 10.1 biyometrik, 11.3/13.2/14.1/15.4 kısmi, 16.4–16.5 dış hesap, 17.2 Play derleme türü, 17.4 ekran görüntüleri, 17.5 Crashlytics, 18.1–18.2 cihaz ölçümü.

Kurallar
- Her fazda 5 iş. Faz bitince sormadan sonraki faza geçilir.
- "Kaldığın yerden devam et" → bu dosyadaki ilk `[ ]` iş.
- Görsellerdeki sayılar (128.436 kullanıcı vb.) örnektir: uygulamada **gerçek veri** gösterilir.
- Görsellerdeki kişi fotoğrafları kullanılmaz (telif/kişilik hakkı); tüm görseller kodla üretilir.
- Uçtan uca şifreleme ve güvenlik kuralları gevşetilmez; RLS zayıflatılmaz.
- Durum: `[x]` bitti · `[~]` kod hazır, canlıda adım bekliyor · `[ ]` sırada

## Faz 1 — Güvenlik ve veritabanı yetkileri (görseller: RLS / yetki analizleri)
- [~] 1.1 Tüm tablolarda anon/authenticated TRUNCATE·REFERENCES·TRIGGER yetkisini kaldır; anon yazmayı kapat (SQL 10.43) — **Supabase SQL Editor'de çalıştırılmalı**
- [x] 1.2 Görsellerdeki 3 politika denetlendi: `app_releases` ve `legal_documents` herkese okuma bilinçli (güncelleme kontrolü, girişten önce yasal metin); `business_audit_log` zaten yalnız ekip yöneticisine açık; yazma yetkisi yok
- [x] 1.3 Yönetici kimliği: yalnız @tugkancr (ayrılmış kullanıcı adı, değiştirilemez, oturum anahtarı) — doğrulandı
- [x] 1.4 CI kapısı: SQL dosyasında istemci rolüne TRUNCATE/ALL veya anon'a yazma verilirse derleme kırmızı
- [x] 1.5 Güvenlik Merkezi için `admin_security_privileges` denetim RPC'si (+ SQL testleri)

## Faz 2 — Marka ve tasarım sistemi "Neon Lime"
- [x] 2.1 Yeni logo: yeşil şerit "J" + "Juzzio" + yeşil nokta (kodla çizim, uygulama ikonu dahil)
- [x] 2.2 "Neon Lime" tema paleti (grafit siyah + #C6FF1A vurgu), varsayılan tema
- [x] 2.3 Bileşen kiti: neon cam kart, lime birincil buton, çip/segment, ikonlu liste satırı, lime anahtar
- [x] 2.4 Alt gezinme: Sohbetler · Keşfet · Aramalar · Bildirimler · Profil (lime seçili gösterge)
- [x] 2.5 Ortak ekran başlığı: geri · "J Juzzio" · başlık · menü

## Faz 3 — Giriş akışı
- [x] 3.1 Kayıt Ol ("Juzzio'ya Katıl", lime cam kart, kullanıcı adı/e-posta/şifre)
- [x] 3.2 Giriş Yap ("Tekrar Hoş Geldin!", e-posta veya kullanıcı adı, beni hatırla, şifremi unuttum)
- [~] 3.3 Sosyal giriş düğmeleri (Google · Apple · GitHub) — kod hazır; sağlayıcı Supabase'de açılıp `OAUTH_PROVIDERS` verilince görünür
- [x] 3.4 Kodla çizilen hero illüstrasyon (emoji balonları, ses dalgası rozeti)
- [x] 3.5 Hesap kurtarma ve şüpheli giriş uyarısı akışları

## Faz 4 — Ana sekmeler I
- [x] 4.1 Sohbet listesi: Neon Lime vurgu, logolu başlık, limon göstergeli alt menü
- [x] 4.2 Mesajlaşma: balon/tepki/çeviri balonu temaya bağlı → Neon Lime vurgusu uygulandı
- [x] 4.3 Arkadaşlık İstekleri: Gelen/Gönderilen, ortak arkadaş, Kabul/Reddet, Tümünü Kabul Et, Arkadaşlarımı Bul
- [x] 4.4 Keşfet: kart yığını, Keşfet/Eşleşmeler/Beğeniler, geri al · geç · süper · beğen · mesaj
- [x] 4.5 Aramalar: Sesli/Görüntülü arama düğmeleri, Tümü/Cevapsız/Gelen/Giden filtresi

## Faz 5 — Ana sekmeler II
- [x] 5.1 Bildirimler: Tümü/İstekler/Bahsetmeler/Sistem, satır içi Kabul/Reddet, "Tümünü okundu yap"
- [x] 5.2 Profil: kapak, istatistik, Profili Düzenle/Arkadaş Ekle, öne çıkan hikâyeler, ızgara (mevcut; Neon Lime + karekod düğmesi)
- [x] 5.3 Profil Düzenle (mevcut sayfa; Neon Lime vurgu)
- [x] 5.4 Profil Karekod (bağlantı kopyala · paylaş · indir · karekod tara)
- [x] 5.5 Hikâye Oluştur (İçerik Stüdyosu: yazı · çıkartma · filtre · müzik · kırp · süre · güzelleştir · gizlilik — mevcut)

## Faz 6 — Arama ekranları
- [x] 6.1 Sesli arama: dalga formlu avatar, canlı çeviri kartları
- [x] 6.2 Görüntülü arama: tam ekran karşı taraf, küçük önizleme, "Canlı Çeviri Aktif" rozeti
- [x] 6.3 Arama kontrol çubuğu: Kamera · Mikrofon · Hoparlör · Çeviri · Diğer · **Ekran Paylaşımı** (Android 14 mediaProjection ön plan servisi; masaüstü yerel seçici)
- [x] 6.4 Arama içi çeviri kartı (bayraklı iki dil)
- [x] 6.5 Arama başarımı: giden görüntü akıcılığı, düşük internet modu

## Faz 6B — Gökyüzü 2.1 (hava ambiyansı baştan tasarım)
- [x] 6B.1 Konumun gün doğumu/batımı + ülke saati (Open-Meteo timezone=auto), bulutluluk, yağış, rüzgâr
- [x] 6B.2 Gök rengi evreleri: gece · şafak · gündüz · altın saat · alacakaranlık
- [x] 6B.3 Yayda ilerleyen güneş, gerçek evreli ay (yalnız konumun gecesinde), göz kırpan yıldızlar, kayan yıldız
- [x] 6B.4 Parallaks bulutlar (bulutluluğa göre), rüzgârlı iki katmanlı yağmur + sıçramalar, kar, sis
- [x] 6B.5 Yeni şimşek: bulut içi parlama + dallanan çakım + ardıl ışıma

## Faz 7 — Ayarlar I
- [x] 7.1 Ayarlar ana sayfası (profil kartı + ikonlu satırlar + Çıkış Yap)
- [x] 7.2 Hesap ve Profil (merkez sayfa: profil, kullanıcı adı, e-posta, şifre, 2FA, verilerim, onaylar, hesabı sil)
- [x] 7.3 Gizlilik ve Güvenlik (2FA/TOTP — girişte ve açılışta kod, oturum açma bildirimleri, cihazlar)
- [x] 7.4 Bildirimler (tür anahtarları, ses, titreşim, zamanlanmış sessiz — Android'de aramalar hariç sessiz kanal)
- [x] 7.5 Çeviri ve Dil (kip: Gerçek Zamanlı/Hızlı/Yüksek Doğruluk → sunucu DeepL model_type, diller)

## Faz 8 — Ayarlar II
- [x] 8.1 Arama Ayarları (kalite, düşük veri, ekran paylaşımı, canlı çeviri, gürültü engelleme)
- [~] 8.2 Sohbet Ayarları (bağlantı önizlemesi, Enter ile gönder, veri tasarrufu, arka plan, yazı boyutu) — ayrı "otomatik indirme" kuralı yok
- [x] 8.3 Medya ve Depolama (halka grafik, tür dökümü, güvenli temizle)
- [x] 8.4 Görünüm (Sistem/Açık/Koyu/Zamanlı, Tema Stüdyosu ile vurgu rengi, sohbet arka planı, balon köşe yuvarlaklığı, cam yoğunluğu)
- [x] 8.5 Erişilebilirlik (yazı boyutu, kalın yazı, yüksek kontrast, hareket azalt, renk düzeltme)

## Faz 9 — Ayarlar III ve yasal
- [x] 9.1 Yardım ve Destek (SSS, sorun bildir/öneri ekran görüntüsüyle, yasal haklar)
- [x] 9.2 Hakkında (sürüm, sürüm notları, koşullar, gizlilik, açık kaynak lisansları)
- [x] 9.3 Çıkış onay penceresi
- [x] 9.4 KVKK: verilerimi indir (JSON, günde 3) + hesabımı sil
- [x] 9.5 Yaş sınırı (15+) ve onay yönetimi (geçmiş + isteğe bağlı izinler)

## Faz 10 — Yönetici Paneli I
- [~] 10.1 Yönetici girişi (yalnız @tugkancr, şifre + hesap 2FA) — biyometrik giriş eklenmedi (MainActivity'nin FragmentActivity'ye geçmesi gerekir)
- [x] 10.2 Genel Bakış panosu (mevcut Genel sekmesi + Aramalar/Canlı modülleri gerçek sayılar)
- [x] 10.3 Modül ızgarası gezinmesi (34 numaralı kart; üst çubuktaki ızgara düğmesi)
- [x] 10.4 Kullanıcı Yönetimi (mevcut Kullanıcılar sekmesi)
- [x] 10.5 Arkadaşlık ve Topluluklar (Gruplar + Topluluk sekmeleri)

## Faz 11 — Yönetici Paneli II
- [x] 11.1 İçerik Moderasyonu
- [x] 11.2 Mesajlaşma Yönetimi (teslimat hatası, spam tespiti)
- [~] 11.3 Sesli ve Görüntülü Aramalar (başarı oranı, ortalama süre, günlük dağılım) — TURN/STUN ayrıntısı LiveKit panelinde
- [x] 11.4 Canlı Çeviri Merkezi
- [x] 11.5 Bildirim Merkezi (FCM)

## Faz 12 — Yönetici Paneli III
- [x] 12.1 Keşfet Yönetimi
- [x] 12.2 Sinema Parti ve Civciv Oyunu
- [x] 12.3 Sürüm ve OTA Yönetimi
- [x] 12.4 Tema ve Uygulama Ayarları (mevcut Ayarlar sekmesi + ayar anahtarları)
- [x] 12.5 Güvenlik Merkezi (oturumlar, MFA, IP, yetki denetimi)

## Faz 13 — Yönetici Paneli IV
- [x] 13.1 Supabase ve Altyapı
- [~] 13.2 Analitik ve Raporlar (her modül CSV olarak kopyalanır) — PDF yok
- [x] 13.3 Destek Merkezi
- [x] 13.4 Sistem Ekstraları
- [x] 13.5 Yönetici Denetim Kayıtları

## Faz 14 — Yönetici Paneli V
- [~] 14.1 Hesap Doğrulama (Güven sekmesi + doğrulanmış sayısı) — ayrı başvuru formu yok
- [x] 14.2 Spam ve Bot Koruması
- [x] 14.3 Canlı Oturum İzleme
- [x] 14.4 WebRTC Tanılama
- [x] 14.5 Çeviri Kalite Kontrolü

## Faz 15 — Yönetici Paneli VI
- [x] 15.1 Medya ve Dosya Yönetimi
- [x] 15.2 Gizlilik ve KVKK Merkezi
- [x] 15.3 API ve Kota Yönetimi
- [~] 15.4 Özellik Yayınlama (ayar anahtarları listesi) — A/B testi yok
- [x] 15.5 Sistem Olayları ve Alarmlar

## Faz 16 — Yönetici Paneli VII
- [x] 16.1 Duyuru ve Kampanya
- [x] 16.2 Veri Yaşam Döngüsü
- [x] 16.3 Yedekleme ve Felaket Kurtarma
- [~] 16.4 Reklam ve Gelir — modül "kurulmadı" bilgisini gösterir; AdMob hesabı gerekir
- [~] 16.5 Ödeme ve Abonelikler — modül "kurulmadı" bilgisini gösterir; Google Play Billing gerekir

## Faz 17 — Google Play hazırlığı
- [x] 17.1 AAB derlemesi + imzalama (CI imzalı AAB artefaktı; Play App Signing adımları docs/GOOGLE_PLAY.md)
- [~] 17.2 Hedef SDK 36 / izin gerekçeleri yazıldı — Play paketi için REQUEST_INSTALL_PACKAGES'ı kaldıracak ayrı derleme türü henüz yok
- [x] 17.3 Veri Güvenliği formu metni + içerik derecelendirmesi (docs/GOOGLE_PLAY.md)
- [~] 17.4 Mağaza listesi (metinler, 512 ikon, 1024×500 görsel) — ekran görüntüleri gerçek cihazdan alınmalı
- [~] 17.5 Çökme izleme: uygulamanın kendi hata kaydı + Android vitals — Crashlytics eklenmedi

## Faz 18 — Kalite ve yayın
- [~] 18.1 Başarım hedefleri yazıldı — cihazda ölçülmedi
- [~] 18.2 Düşük internet senaryoları yazıldı — cihazda denenmedi
- [x] 18.3 Kapalı beta kontrol listesi
- [x] 18.4 Yayın öncesi son kontrol listesi (18 madde)
- [x] 18.5 Kademeli yayın planı
