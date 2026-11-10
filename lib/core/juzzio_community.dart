// =============================================================================
// JUZZIO v1.2.0 — Juzzio Topluluğu (resmî duyuru kanalı)
//  • Sunucuda tek bir kanal odası (rooms.is_community) vardır; adı "Juzzio Community"
//    olarak saklanır ve istemcide uygulama diline göre gösterilir
//    (TR "Juzzio Topluluğu", EN/DE/diğer "Juzzio Community").
//  • Tüm mevcut kullanıcılar ve her yeni kayıt otomatik üye olur (SQL tetikleyicisi).
//  • Paylaşımlar "Juzzio Official" adıyla ve uygulama logosuyla görünür; kanala yalnız
//    yöneticiler yazabilir (RLS). Her sürüm yayınında CI otomatik duyuru gönderir.
//  • Ad sunucuda rezervedir: başka bir oda "Juzzio Community/Topluluğu" adını alamaz.
//  • v1.2.6: logo sabittir (uygulama logosu). Üyeler birbirini göremez, mesaj/tepki
//    gönderemez; kanala yalnız sürüm güncellemesi duyuruları düşer. Tek yetkili @tugkancr.
// =============================================================================

import 'app_theme_and_locale.dart';

/// Sunucuda saklanan kanonik ad
const String kJuzzioCommunityTitle = 'Juzzio Community';

/// Kanaldaki paylaşımların gönderen adı
const String kJuzzioOfficialName = 'Juzzio Official';

/// v1.2.6: kanalın tek yetkilisi (sunucu da yalnız bu hesabı sahip yapar)
const String kJuzzioCommunityAdminUsername = 'tugkancr';

/// Avatar olarak uygulama logosu (JuzzioSpacePhoto / JuzzioUserAvatar "asset:" önekini tanır)
const String kJuzzioLogoAvatar = 'asset:assets/logo/juzzio_logo.png';

/// Oda adı Juzzio Topluluğu mu? (sunucu bu adı yalnız topluluk kanalına verir)
bool juzzioIsCommunityTitle(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  return t == 'juzzio community' || t == 'juzzio topluluğu';
}

/// Uygulama diline göre topluluk adı
String juzzioCommunityDisplayTitle([String? lang]) {
  final l = (lang ?? JuzzioAppController.instance.uiLang).toLowerCase();
  return l.startsWith('tr') ? 'Juzzio Topluluğu' : kJuzzioCommunityTitle;
}

/// Oda başlığını gösterime çevirir (yalnız topluluk kanalı yerelleştirilir)
String juzzioLocalizedRoomTitle(String raw) => juzzioIsCommunityTitle(raw) ? juzzioCommunityDisplayTitle() : raw;

/// v1.2.6: oda için gösterilecek gerçek bir logo var mı (http(s) adresi veya uygulama varlığı)
bool juzzioHasRoomLogo(String? url) {
  final u = (url ?? '').trim();
  return u.startsWith('https://') || u.startsWith('http://') || u.startsWith('asset:');
}
