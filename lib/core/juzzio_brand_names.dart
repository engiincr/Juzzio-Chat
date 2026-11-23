// =============================================================================
// TRAWAVE (GM-055) — Tescilli marka adları kullanıcı adı olamaz
//  Kullanıcı adındaki . ve _ atılarak bakılır; markanın kendisi ve yaygın taklit kalıpları
//  (resmi, official, support, destek, tr, app, hq, the…) reddedilir. Sunucuda aynı liste SQL 10.58'de.
// =============================================================================

const List<String> kJuzzioBrandNames = [
  // uygulamanın kendi adları
  'trawave', 'juzzio',
  // teknoloji ve sosyal platformlar
  'apple', 'iphone', 'icloud', 'google', 'gmail', 'youtube', 'android', 'microsoft', 'windows', 'xbox', 'linkedin',
  'meta', 'facebook', 'instagram', 'whatsapp', 'messenger', 'threads', 'twitter', 'xcorp', 'tiktok', 'snapchat',
  'telegram', 'signal', 'discord', 'reddit', 'pinterest', 'tumblr', 'twitch', 'kick', 'skype', 'zoom', 'viber', 'wechat',
  'line', 'kakaotalk', 'tinder', 'bumble', 'hinge', 'badoo', 'grindr', 'happn', 'okcupid', 'match',
  'amazon', 'netflix', 'spotify', 'disney', 'hbo', 'primevideo', 'openai', 'chatgpt', 'anthropic', 'claude', 'gemini',
  'samsung', 'xiaomi', 'huawei', 'oppo', 'vivo', 'oneplus', 'sony', 'playstation', 'nintendo', 'steam', 'valve',
  'nvidia', 'amd', 'intel', 'tesla', 'spacex', 'paypal', 'visa', 'mastercard', 'revolut', 'binance', 'coinbase',
  'uber', 'airbnb', 'booking', 'ebay', 'aliexpress', 'alibaba', 'temu', 'shein', 'yandex', 'proton', 'protonmail',
  'supabase', 'livekit', 'deepgram', 'firebase', 'github', 'gitlab',
  // Türkiye'de yaygın markalar
  'trendyol', 'hepsiburada', 'getir', 'yemeksepeti', 'turkcell', 'vodafone', 'turktelekom', 'garanti', 'akbank',
  'ziraat', 'isbankasi', 'yapikredi', 'papara', 'thy', 'turkishairlines', 'pegasus', 'aselsan', 'baykar', 'bim', 'migros',
  // diğer büyük markalar
  'cocacola', 'pepsi', 'nike', 'adidas', 'puma', 'mcdonalds', 'starbucks', 'burgerking', 'redbull', 'bmw', 'mercedes',
  'audi', 'toyota', 'ferrari', 'porsche', 'gucci', 'prada', 'zara', 'ikea', 'lego', 'pokemon', 'marvel', 'nasa', 'fifa', 'uefa',
];

const List<String> _kAffixes = ['official', 'resmi', 'support', 'destek', 'help', 'team', 'tr', 'turkiye', 'app', 'hq', 'inc', 'real', 'the', 'global'];

/// Kullanıcı adı bir markanın kendisi ya da taklidi mi?
bool juzzioUsernameIsBrand(String username) {
  final v = username.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '').replaceAll(RegExp(r'[._]'), '');
  if (v.isEmpty) return false;
  for (final b in kJuzzioBrandNames) {
    if (v == b) return true;
    for (final a in _kAffixes) {
      if (v == '$b$a' || v == '$a$b') return true;
    }
  }
  return false;
}
