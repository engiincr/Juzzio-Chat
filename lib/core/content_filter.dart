// =============================================================================
// JUZZIO — İstemci tarafı içerik filtresi (anında geri bildirim için).
// Asıl yetkili kontrol veritabanındadır (public.juzzio_text_is_clean); bu liste
// kullanıcı yazarken hızlı uyarı vermek için sunucudakiyle aynı mantığı izler.
// =============================================================================

/// Grup türleri (sunucudaki rooms.group_type ile aynı)
const List<String> kJuzzioGroupTypes = [
  'group_work',
  'team_relationship',
  'friends',
  'family',
  'study',
  'custom',
];

class JuzzioContentFilter {
  JuzzioContentFilter._();

  static const List<String> _containsTerms = [
    'orospu', 'siktir', 'sikerim', 'sikis', 'sikik', 'yarrak', 'pezevenk', 'kahpe', 'gavat',
    'surtuk', 'kaltak', 'yavsak', 'aminakoy', 'ananisikim', 'godos', 'ibne', 'kerhane', 'fahise',
    'porno', 'fuck', 'shit', 'bitch', 'porn', 'pussy', 'cunt', 'whore', 'slut', 'nigger', 'nigga',
    'hentai', 'onlyfans', 'nsfw', 'scheisse', 'hurensohn', 'fotze', 'wichser', 'aminakoyim',
    // v0.6: müstehcen / ağır argo (ad, kullanıcı adı, grup adı)
    'amcik', 'amcuk', 'dalyarak', 'dallama', 'gotveren', 'gotlek', 'kancik', 'sikici', 'sikiyim',
    'siktim', 'sikeyim', 'yarram', 'yarragi', 'orospucocugu', 'ibnelik', 'vajina', 'penis', 'memeler',
    'ciplak', 'erotik', 'azgin', 'escort', 'sokus', 'blowjob', 'handjob', 'boobs', 'horny', 'xvideos',
    'xnxx', 'pornhub', 'brazzers', 'naked', 'motherfucker', 'asshole', 'bastard', 'dildo', 'vagina',
    'stripper', 'arschloch', 'schlampe', 'ficken', 'nutte', 'muschi',
  ];

  static const List<String> _wordTerms = [
    'amk', 'aq', 'sik', 'yarak', 'seks', 'sex', 'xxx', 'sikim', 'dick', 'cock', 'fag', 'rape', 'nude', 'nudes',
    'pezo', 'seksi', 'tits', 'milf', 'anal', 'cum', 'sexy', 'schwanz',
  ];

  /// Görüntülü/sesli aramada ceza sayılan ağır ifadeler (sunucudaki speech_strike listesi).
  static const List<String> _speechTerms = [
    'orospu', 'siktir', 'sikerim', 'sikis', 'yarrak', 'aminakoy', 'ananisikim', 'amcik', 'amcuk',
    'aminakoydugum', 'sikiyim', 'sikeyim', 'yarram', 'yarragi', 'porno', 'fuck', 'pussy', 'cunt',
    'whore', 'slut', 'blowjob', 'handjob', 'dildo', 'hurensohn', 'fotze', 'ficken', 'nigger', 'nigga',
  ];

  /// Konuşma metninde ağır ifade var mı? (sunucu ayrıca doğrular; bu yalnızca ön elemedir)
  static bool speechLooksExplicit(String text) {
    final folded = _fold(text);
    final words = ' ${folded.replaceAll(RegExp(r'[^a-z]+'), ' ')} ';
    final joined = folded.replaceAll(RegExp(r'[^a-z]+'), '');
    for (final t in _speechTerms) {
      if (words.contains(t) || joined.contains(t)) return true;
    }
    return false;
  }

  static String _fold(String input) {
    const from = 'çğıöşüâîû0134578@\$!|';
    const to = 'cgiosuaiuoieastbasii';
    final lower = input.toLowerCase();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf.toString();
  }

  /// Metin uygun mu? requireLetters=true ad alanları içindir (en az 2 harf, anlamsız tekrar yok).
  static bool isClean(String text, {bool requireLetters = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return !requireLetters;
    final folded = _fold(trimmed);
    final words = ' ${folded.replaceAll(RegExp(r'[^a-z]+'), ' ')} ';
    if (requireLetters) {
      final letters = trimmed.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '').length;
      if (letters < 2) return false;
      if (RegExp(r'(.)\1{5,}').hasMatch(trimmed)) return false;
    }
    // Sunucudaki gibi: "contains" terimleri kelime kelime aranır; harf harf
    // ayrılmış yazımlar ("o r o s p u") birleştirilip ayrıca kontrol edilir.
    final targets = <String>[];
    var run = '';
    for (final tok in words.trim().split(' ')) {
      if (tok.isEmpty) continue;
      targets.add(tok);
      if (tok.length == 1) {
        run += tok;
      } else {
        if (run.length > 1) targets.add(run);
        run = '';
      }
    }
    if (run.length > 1) targets.add(run);
    for (final t in _containsTerms) {
      if (targets.any((w) => w.contains(t))) return false;
    }
    for (final t in _wordTerms) {
      if (words.contains(' $t ')) return false;
    }
    return true;
  }
}
