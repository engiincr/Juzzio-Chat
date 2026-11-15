// =============================================================================
// JUZZIO v1.2.8 — Kalıcı çeviri hafızası (cihazda, hesaba özel)
//  • Çevrilen her cümle/kelime "kaynak|hedef|metin" anahtarıyla cihazda saklanır; aynı
//    metin bir daha ağa gitmez (anında çeviri, daha az veri, sağlayıcı sınırına takılmaz).
//  • Sinema Parti'de izlenen film/dizinin altyazı ve sohbet kelimeleri buraya önceden
//    eklenir: izlerken çeviri hızlanır ve zamanla gelişir (kelime önbelleği).
//  • En çok 6000 kayıt; en eski kullanılanlar düşer (LRU). Yazma 4 sn'de bir toplu yapılır.
// =============================================================================

import 'dart:async';
import 'dart:collection';

import 'supabase_service.dart';

/// Hafıza anahtarı (saf; test edilir): küçük harf, fazla boşluk temizlenmiş
String juzzioTmKey(String source, String target, String text) =>
    '${source.toLowerCase()}|${target.toLowerCase()}|${text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase()}';

/// Metinden önbelleğe alınmaya değer kelime/öbekleri çıkarır (saf; test edilir).
/// 2–24 harfli kelimeler, rakam/bağlantı içermeyenler; en sık geçen [limit] tanesi.
List<String> juzzioVocabularyFrom(Iterable<String> lines, {int limit = 300}) {
  final counts = <String, int>{};
  final word = RegExp(r"[\p{L}][\p{L}'’-]{1,23}", unicode: true);
  for (final line in lines) {
    for (final m in word.allMatches(line)) {
      final w = m.group(0)!.toLowerCase();
      counts[w] = (counts[w] ?? 0) + 1;
    }
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(limit).map((e) => e.key).toList();
}

class JuzzioTranslationMemory {
  JuzzioTranslationMemory._();
  static final JuzzioTranslationMemory instance = JuzzioTranslationMemory._();

  static const int maxEntries = 6000;
  static const String _cacheName = 'translation_memory_v1';

  final LinkedHashMap<String, String> _map = LinkedHashMap<String, String>();
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _flush;

  int get length => _map.length;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= () async {
      try {
        final raw = await SupabaseService.instance.readLocalCache(_cacheName);
        if (raw is Map) {
          raw.forEach((k, v) {
            if (k is String && v is String && v.isNotEmpty) _map[k] = v;
          });
        }
      } catch (_) {}
      _loaded = true;
    }();
  }

  /// Hafızada varsa çeviriyi döndürür (ve "son kullanılan" yapar)
  Future<String?> lookup(String source, String target, String text) async {
    await _ensureLoaded();
    final k = juzzioTmKey(source, target, text);
    final v = _map.remove(k);
    if (v == null) return null;
    _map[k] = v;
    return v;
  }

  /// Senkron bakış (yüklüyse) — kaydırırken anında çeviri için
  String? peek(String source, String target, String text) => _loaded ? _map[juzzioTmKey(source, target, text)] : null;

  Future<void> put(String source, String target, String text, String translated) async {
    final t = translated.trim();
    if (t.isEmpty || t == text.trim()) return;
    await _ensureLoaded();
    final k = juzzioTmKey(source, target, text);
    _map.remove(k);
    _map[k] = t;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
    _flush ??= Timer(const Duration(seconds: 4), _save);
  }

  Future<void> _save() async {
    _flush = null;
    try {
      await SupabaseService.instance.writeLocalCache(_cacheName, Map<String, String>.from(_map));
    } catch (_) {}
  }

  /// Bir kelime listesini arka planda (yavaşça, sağlayıcıyı yormadan) hedef dile çevirip
  /// hafızaya ekler. Zaten bilinenler atlanır. Eklenen kayıt sayısını döndürür.
  Future<int> warmUp(Iterable<String> words, String target, {int maxNew = 120}) async {
    await _ensureLoaded();
    var added = 0;
    for (final w in words) {
      if (added >= maxNew) break;
      if (_map.containsKey(juzzioTmKey('auto', target, w))) continue;
      try {
        final tr = await SupabaseService.instance.translateText(text: w, sourceLang: 'auto', targetLang: target);
        if (tr.trim().isNotEmpty && tr.trim().toLowerCase() != w.toLowerCase()) added++;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return added;
  }
}
