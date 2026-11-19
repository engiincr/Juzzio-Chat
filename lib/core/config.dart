// =============================================================================
// JUZZIO v0.2.0 - Uygulama Yapılandırması
//
// GÜVENLİK: Mobil uygulama (APK) içine HİÇBİR gizli anahtar gömülmez.
//  • LiveKit API anahtarı/secret'ı yalnızca Supabase Secrets'ta durur; token'ı
//    `get-livekit-token` Edge Function üretir.
//  • Deepgram anahtarı yalnızca Supabase Secrets'ta durur; canlı altyazı için
//    `translate-bridge` (mode=deepgram_token) kısa ömürlü token verir.
//  • Supabase URL ve "publishable/anon" anahtarı tasarım gereği herkese açıktır
//    (yetki RLS ile korunur); GitHub Secrets ile --dart-define üzerinden
//    değiştirilebilir.
// =============================================================================

class JuzzioConfig {
  JuzzioConfig._();

  // Uygulama Sürüm ve OTA Güncelleme Sabitleri
  static const String appVersion = '1.3.1';
  /// CI her derlemede artan sürüm kodunu APP_BUILD olarak verir
  /// (`scripts/release_meta.py build-number`). Yerel derlemede pubspec.yaml'daki
  /// +N değeri kullanılır; `release_meta.py check` ikisinin aynı olmasını zorunlu kılar.
  static const int appVersionCode = int.fromEnvironment('APP_BUILD', defaultValue: 131);
  /// v0.8.0: yayın imzası doğrulama anahtarı (ML-DSA-65, FIPS 204). Boşsa imza
  /// kontrolü yapılmaz; CI'da GitHub değişkeni ML_DSA_PUBLIC_KEY ile verilir.
  static const String mlDsaPublicKey = String.fromEnvironment('ML_DSA_PUBLIC_KEY');
  static const String githubOwner = 'engiincr';
  static const String githubRepo = 'Juzzio-Chat';
  static const String supabaseRegion = 'ap-south-1';

  // Yazı tipi aileleri (sistem sans-serif)
  static const String fontRegularBold = 'sans-serif';
  static const String fontBoldItalic = 'sans-serif';

  static const String otaVersionJsonUrl =
      'https://raw.githubusercontent.com/engiincr/Juzzio-Chat/main/version.json';
  static const String otaLatestReleaseApiUrl =
      'https://api.github.com/repos/engiincr/Juzzio-Chat/releases/latest';
  static const String otaDirectApkUrl =
      'https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk';

  static const String _defaultSupabaseUrl = 'https://hzoerzgbyklrutvifbrg.supabase.co';
  static const String _defaultSupabaseAnonKey = 'sb_publishable_7vQpeX8-Vpl4j28NOwZ2Ng_5hpBuKwQ';
  static const String _defaultLiveKitUrl = 'wss://juzzio-hbmkorss.livekit.cloud';

  static String _env(String value, String fallback) {
    final v = value.trim();
    return v.isNotEmpty ? v : fallback;
  }

  static String get supabaseUrl =>
      _env(const String.fromEnvironment('SUPABASE_URL'), _defaultSupabaseUrl);

  static String get supabaseAnonKey =>
      _env(const String.fromEnvironment('SUPABASE_ANON_KEY'), _defaultSupabaseAnonKey);

  /// LiveKit sunucu adresi (gizli değildir). Edge Function yanıtındaki wsUrl önceliklidir.
  static String get liveKitUrl =>
      _env(const String.fromEnvironment('LIVEKIT_URL'), _defaultLiveKitUrl);

  /// Yalnızca yerel geliştirme için isteğe bağlı (--dart-define=DEEPGRAM_API_KEY=...).
  /// Yayın derlemelerinde boş bırakılır; token Edge Function'dan alınır.
  static String get deepgramDevApiKey => const String.fromEnvironment('DEEPGRAM_API_KEY').trim();

  // v1.2.9 — YEDEK TURN (ExpressTURN). Ana LiveKit bağlantısı kurulamazsa / koparsa arama bu
  // aktarıcı üzerinden yeniden denenir. Değerler derlemede --dart-define ile değiştirilebilir;
  // sunucu (get-livekit-token, BACKUP_TURN_* sırları) kendi listesini verirse o önceliklidir.
  // Not: ses/görüntü DTLS-SRTP ile uçtan uca şifrelidir; aktarıcı içeriği çözemez.
  static const String backupTurnHost = String.fromEnvironment('BACKUP_TURN_HOST', defaultValue: 'free.expressturn.com');
  static const int backupTurnPort = int.fromEnvironment('BACKUP_TURN_PORT', defaultValue: 3478);
  static const String backupTurnUsername = String.fromEnvironment('BACKUP_TURN_USERNAME', defaultValue: '000000002108137542');
  static const String backupTurnCredential = String.fromEnvironment('BACKUP_TURN_CREDENTIAL', defaultValue: 'ddfQ8zpEanGDan4FFlQfkzn3U3w=');

  /// Yedek TURN adresleri (UDP + TCP) — saf; test edilir
  static List<String> get backupTurnUrls => backupTurnHost.isEmpty
      ? const <String>[]
      : <String>['turn:$backupTurnHost:$backupTurnPort?transport=udp', 'turn:$backupTurnHost:$backupTurnPort?transport=tcp'];

  // Storage Bucket'ları (her dosya yolu kullanıcının kendi klasörüyle başlar: <uid>/...)
  static const String voiceNoteBucket = 'voice-notes';
  static const String avatarBucket = 'avatars';
  static const String storiesBucket = 'stories';
  static const String chatMediaBucket = 'chat-media';
  static const String postsBucket = 'posts';

  // Hikâye süre limiti
  static const int maxStoryVideoDurationSec = 15;

  /// v0.9.3: fotoğraf/metin durumunun ekranda kalma süresi (video kendi süresi kadar, en çok 60 sn).
  static const int storyImageDisplayMs = 30000;

  static String buildDeepgramWsUrl(String languageCode, {bool batterySaver = false}) {
    final code = languageCode.toLowerCase();
    const supported = {
      'tr', 'en', 'de', 'es', 'fr', 'it', 'pt', 'ru', 'ja', 'ko',
      'nl', 'hi', 'zh', 'uk', 'pl', 'sv', 'da', 'no', 'fi', 'id',
    };
    final dgLang = supported.contains(code) ? code : 'multi';
    // v0.9.4: 180 ms çok kısaydı — konuşmacı nefes alırken cümle ikiye bölünüyordu.
    // Bölüt yalnız konuşma gerçekten bitince (speech_final / UtteranceEnd) kapanır.
    final endpointMs = batterySaver ? 700 : 550;
    // v1.2.8: listede olmayan diller için çok dilli nova-3 (otomatik dil), diğerleri nova-2
    final model = dgLang == 'multi' ? 'nova-3' : 'nova-2';
    return 'wss://api.deepgram.com/v1/listen'
        '?model=$model'
        '&language=$dgLang'
        '&encoding=linear16'
        '&sample_rate=16000'
        '&channels=1'
        '&interim_results=true'
        '&endpointing=$endpointMs'
        '&utterance_end_ms=1200'
        '&vad_events=true'
        '&smart_format=true'
        '&punctuate=true';
  }
}
