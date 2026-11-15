// =============================================================================
// JUZZIO v1.2.9 — UTF-16 güvenli metin yardımcıları
//  Hata: "ArgumentError: string is not well-formed UTF-16" (TextPainter.layout).
//  Kök neden: emoji gibi iki UTF-16 birimli (vekil çift) karakterlerin `substring(0, n)` ile
//  ortadan kesilmesi (ör. adı emojiyle başlayan birinin baş harfi, kısaltılmış önizlemeler).
//  Yarım kalan "yalnız vekil" karakter Flutter'ın metin motorunu çökertir.
//  Çözüm: kesme işlemleri vekil çiftini bölmez; dışarıdan gelen metinlerdeki yalnız vekiller
//  � (U+FFFD) ile değiştirilir.
// =============================================================================

bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;

/// Metin iyi biçimli UTF-16 mı? (saf; test edilir)
bool juzzioIsWellFormed(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isHigh(c)) {
      if (i + 1 >= s.length || !_isLow(s.codeUnitAt(i + 1))) return false;
      i++;
    } else if (_isLow(c)) {
      return false;
    }
  }
  return true;
}

/// Yalnız kalmış vekil karakterleri U+FFFD ile değiştirir (iyi biçimliyse aynı nesne döner)
String juzzioWellFormed(String s) {
  if (juzzioIsWellFormed(s)) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isHigh(c)) {
      if (i + 1 < s.length && _isLow(s.codeUnitAt(i + 1))) {
        b.writeCharCode(c);
        b.writeCharCode(s.codeUnitAt(i + 1));
        i++;
      } else {
        b.writeCharCode(0xFFFD);
      }
    } else if (_isLow(c)) {
      b.writeCharCode(0xFFFD);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// Vekil çiftini ve ZWJ birleşimini bölmeden en çok [max] UTF-16 birimine kısaltır
String juzzioSafeCut(String s, int max) {
  if (max <= 0) return '';
  if (s.length <= max) return s;
  var end = max;
  if (_isHigh(s.codeUnitAt(end - 1))) end--; // çiftin ilk yarısında kesilmesin
  // emoji sonu birleştiricilerini (ZWJ, varyasyon seçici) sondan temizle
  while (end > 0) {
    final c = s.codeUnitAt(end - 1);
    if (c == 0x200D || c == 0xFE0F || c == 0xFE0E) {
      end--;
    } else {
      break;
    }
  }
  return s.substring(0, end);
}

/// "…" ile kısaltma (vekil güvenli)
String juzzioEllipsize(String s, int max) => s.length <= max ? s : '${juzzioSafeCut(s, max - 1)}…';

/// Ad baş harfi (emoji/vekil güvenli; boşsa ?)
String juzzioInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  final it = t.runes.iterator;
  if (!it.moveNext()) return '?';
  return String.fromCharCode(it.current).toUpperCase();
}
