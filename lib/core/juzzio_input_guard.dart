// =============================================================================
// JUZZIO v1.2.1 — İstemci tarafı girdi doğrulama (sunucudaki doğrulamanın ÖNÜNDE ikinci kat)
//
//  Kural: kullanıcıdan gelen hiçbir metne doğrudan güvenilmez.
//   • juzzioCleanText: görünmez kontrol karakterleri, NUL, yön değiştirme (bidi override — "Trojan
//     Source" / ad sahteciliği) ve sıfır genişlikli birleşik karakterler dışındaki görünmezler temizlenir;
//     satır sonu ve sekme korunur; uzunluk sınırlanır.
//   • juzzioSafeSearchTerm: PostgREST filtre sözdizimine (virgül, parantez, nokta-operatör, %, *, \, ")
//     sızamayacak arama terimi — "filter injection" önlenir.
//   • juzzioSafeUrl: yalnız http/https; javascript:, data:, file: vb. reddedilir.
//  Sunucu (SQL) aynı kuralları tetikleyicilerle ayrıca zorunlu kılar; istemci yalnız erken uyarıdır.
// =============================================================================

/// Yön değiştirme / görünmez biçim karakterleri (ZWJ ‍ emojiler için korunur)
final RegExp _kBidiAndInvisible = RegExp('[‪-‮⁦-⁩​‎‏⁠﻿]');

/// C0/C1 kontrol karakterleri (\n ve \t hariç)
final RegExp _kControl = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]');

/// Kullanıcı metnini temizler ve [maxLength] karakterle sınırlar.
String juzzioCleanText(String input, {int maxLength = 4000, bool singleLine = false}) {
  var s = input.replaceAll(_kControl, '').replaceAll(_kBidiAndInvisible, '');
  if (singleLine) s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  s = s.replaceAll('\r\n', '\n');
  // 3'ten fazla boş satır tek boşluğa iner (görsel taşma/spam)
  s = s.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  s = s.trim();
  if (s.runes.length > maxLength) s = String.fromCharCodes(s.runes.take(maxLength));
  return s;
}

/// Görünen ad: tek satır, 1–60 karakter
String juzzioCleanDisplayName(String input) => juzzioCleanText(input, maxLength: 60, singleLine: true);

/// PostgREST `or()/ilike` filtresine güvenle konabilecek arama terimi (yalnız harf, rakam, _ . - boşluk)
String juzzioSafeSearchTerm(String input, {int maxLength = 40}) {
  final s = juzzioCleanText(input, maxLength: maxLength, singleLine: true)
      .replaceAll('@', '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}_ \-]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s;
}

/// Yalnız http(s) bağlantılarına izin verir; diğerlerinde null
String? juzzioSafeUrl(String input, {int maxLength = 1024}) {
  final s = juzzioCleanText(input, maxLength: maxLength, singleLine: true);
  if (s.isEmpty || s.contains(' ')) return null;
  // http(s) dışında açık bir şema (javascript:, data:, file:, intent: …) varsa reddet
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(s);
  if (scheme != null && !RegExp(r'^https?$', caseSensitive: false).hasMatch(scheme.group(1)!)) {
    // "alan.com:8080" gibi port içeren yalın adresler şema sayılmaz
    if (!RegExp(r'^[a-zA-Z0-9.\-]+:\d+(/|$)').hasMatch(s)) return null;
  }
  final u = Uri.tryParse(s.startsWith('http') ? s : 'https://$s');
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return null;
  return u.toString();
}
