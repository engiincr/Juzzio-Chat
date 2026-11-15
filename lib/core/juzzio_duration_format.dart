// =============================================================================
// JUZZIO v1.2.9 — Süre yazımı (arama süreleri) her dilde kendi birim kısaltmasıyla
//  Hata: arama süreleri her dilde Türkçe "dk / sn" ile görünüyordu (ör. İngilizce kullanan @ari'de).
//  Çözüm: "dk/sn/sa" YALNIZ Türkçede; diğer dillerde o dilin yaygın kısaltması
//  (min/s/h, Min./Sek./Std., мин/с/ч, 分/秒/時間 …). Listede olmayan dillerde evrensel saat
//  biçimi kullanılır (2:05 veya 1:02:05) — yanlış çeviri riski yoktur.
// =============================================================================

class _DurUnits {
  const _DurUnits(this.h, this.m, this.s, {this.space = true});
  final String h, m, s;
  final bool space; // sayı ile birim arasında boşluk (Çince/Japonca/Korecede yok)
}

const Map<String, _DurUnits> _kDurUnits = <String, _DurUnits>{
  'tr': _DurUnits('sa', 'dk', 'sn'),
  'az': _DurUnits('saat', 'dəq', 'san'),
  'en': _DurUnits('h', 'min', 's'),
  'de': _DurUnits('Std.', 'Min.', 'Sek.'),
  'fr': _DurUnits('h', 'min', 's'),
  'es': _DurUnits('h', 'min', 's'),
  'it': _DurUnits('h', 'min', 's'),
  'pt': _DurUnits('h', 'min', 's'),
  'nl': _DurUnits('u', 'min', 'sec'),
  'sv': _DurUnits('h', 'min', 's'),
  'da': _DurUnits('t', 'min', 'sek'),
  'nb': _DurUnits('t', 'min', 'sek'),
  'no': _DurUnits('t', 'min', 'sek'),
  'fi': _DurUnits('h', 'min', 's'),
  'pl': _DurUnits('godz.', 'min', 's'),
  'cs': _DurUnits('h', 'min', 's'),
  'sk': _DurUnits('h', 'min', 's'),
  'hu': _DurUnits('ó', 'p', 'mp'),
  'ro': _DurUnits('h', 'min', 's'),
  'el': _DurUnits('ώ', 'λ', 'δ'),
  'bg': _DurUnits('ч', 'мин', 'с'),
  'ru': _DurUnits('ч', 'мин', 'с'),
  'uk': _DurUnits('год', 'хв', 'с'),
  'sr': _DurUnits('ч', 'мин', 'с'),
  'hr': _DurUnits('h', 'min', 's'),
  'ar': _DurUnits('س', 'د', 'ث'),
  'fa': _DurUnits('ساعت', 'دقیقه', 'ثانیه'),
  'he': _DurUnits('שע׳', 'דק׳', 'שנ׳'),
  'hi': _DurUnits('घं', 'मि', 'से'),
  'id': _DurUnits('j', 'mnt', 'dtk'),
  'ms': _DurUnits('j', 'min', 'saat'),
  'vi': _DurUnits('giờ', 'phút', 'giây'),
  'th': _DurUnits('ชม.', 'น.', 'วิ'),
  'ja': _DurUnits('時間', '分', '秒', space: false),
  'zh': _DurUnits('小时', '分', '秒', space: false),
  'ko': _DurUnits('시간', '분', '초', space: false),
};

/// Dilin birim kısaltması var mı? (saf)
bool juzzioHasDurationUnits(String lang) => _kDurUnits.containsKey(lang.toLowerCase().split(RegExp('[-_]')).first);

/// Süreyi dile göre yazar. Örnekler: tr "2 dk 05 sn", en "2 min 05 s", de "2 Min. 05 Sek.",
/// ja "2分05秒", bilinmeyen dil "2:05". Saf; test edilir.
String juzzioFormatDuration(int seconds, String lang) {
  final total = seconds < 0 ? 0 : seconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final u = _kDurUnits[lang.toLowerCase().split(RegExp('[-_]')).first];
  String two(int v) => v.toString().padLeft(2, '0');
  if (u == null) {
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
  final sp = u.space ? ' ' : '';
  final gap = u.space ? ' ' : '';
  if (h > 0) return '$h$sp${u.h}$gap${two(m)}$sp${u.m}';
  if (m > 0) return '$m$sp${u.m}$gap${two(s)}$sp${u.s}';
  return '$s$sp${u.s}';
}

/// Yalnız saniye birimi ("10 sn" / "10 s" / "10秒"); bilinmeyen dilde "s". Saf.
String juzzioSecondsLabel(String number, String lang) {
  final u = _kDurUnits[lang.toLowerCase().split(RegExp('[-_]')).first];
  if (u == null) return '$number s';
  return u.space ? '$number ${u.s}' : '$number${u.s}';
}
