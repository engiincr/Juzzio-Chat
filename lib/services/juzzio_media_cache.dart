// =============================================================================
// JUZZIO v0.9.2 — Çevrimdışı medya önbelleği (WhatsApp benzeri)
//  * Görüntülenen fotoğraf, profil resmi ve sesli mesajlar cihazda saklanır; internet
//    yokken aynı dosyadan gösterilir/oynatılır.
//  * Konum: <uygulama destek klasörü>/juzzio_cache/<kullanıcı>/media — hesaba özeldir,
//    oturum kapatılınca (clearLocalCacheForCurrentUser) birlikte silinir.
//  * Anahtar: Storage nesnesinin KİMLİĞİ (bucket/yol) — imzalı adresin değişen token'ı
//    aynı dosyaya düşer. Dış adreslerde tam adres.
//  * Uçtan uca şifreli fotoğraflar diske ŞİFRELİ hâliyle yazılır (çözme bellekte).
//  * Sınır: 300 MB; aşılınca en eski kullanılanlar silinerek 240 MB'a inilir.
//  * v0.9.7: sınır ve azami dosya yaşı YÖNETİCİ PANELİNDEN yönetilir
//    (media_cache_max_mb, media_cache_max_age_days). Açılışta ve her 20 indirmede
//    akıllı temizlik: önce süresi geçenler, sonra en uzun süredir kullanılmayanlar
//    (LRU) %80 hedefine kadar; yarım kalan .part ve geçici çözülmüş dosyalar da silinir.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import 'juzzio_media_url.dart';

class JuzzioMediaDiskCache {
  JuzzioMediaDiskCache._();
  static final JuzzioMediaDiskCache instance = JuzzioMediaDiskCache._();

  static const int maxBytes = 300 * 1024 * 1024;
  static const int pruneTarget = 240 * 1024 * 1024;
  static const int maxItemBytes = 30 * 1024 * 1024;

  /// v0.9.7: yönetici ayarlarından gelen etkin sınırlar.
  int limitBytes = maxBytes;
  int maxAgeDays = 60;

  /// Yönetici ayarı (MB, gün) uygulanır; sınır küçüldüyse hemen temizlenir.
  void applyLimits({required int maxMb, required int ageDays}) {
    final newLimit = maxMb.clamp(50, 4096) * 1024 * 1024;
    final newAge = ageDays.clamp(0, 365);
    final shrink = newLimit < limitBytes || (newAge > 0 && (maxAgeDays == 0 || newAge < maxAgeDays));
    limitBytes = newLimit;
    maxAgeDays = newAge;
    if (shrink) unawaited(prune());
  }

  /// Saf karar fonksiyonu (test edilir): hangi dosyalar silinmeli?
  /// [files]: (ad, boyut, son kullanım). Önce yaşı geçenler, sonra LRU ile hedefe inilir.
  static List<String> planPrune(List<(String, int, DateTime)> files,
      {required int limit, required int target, required int maxAgeDays, required DateTime now}) {
    final out = <String>[];
    var total = files.fold<int>(0, (a, f) => a + f.$2);
    final rest = <(String, int, DateTime)>[];
    for (final f in files) {
      if (maxAgeDays > 0 && now.difference(f.$3).inDays >= maxAgeDays) {
        out.add(f.$1);
        total -= f.$2;
      } else {
        rest.add(f);
      }
    }
    if (total <= limit) return out;
    rest.sort((a, b) => a.$3.compareTo(b.$3));
    for (final f in rest) {
      if (total <= target) break;
      out.add(f.$1);
      total -= f.$2;
    }
    return out;
  }

  Directory? _dir;
  String _owner = '';
  int _writesSincePrune = 0;
  final Map<String, Future<File?>> _inFlight = {};

  /// Önbellek anahtarı (test edilebilir, saf).
  static String keyFor(String url) {
    final ref = JuzzioMediaUrl.parse(url);
    final canonical = ref != null ? '${ref.bucket}/${ref.path}' : url.split('#').first;
    return sha256Hex(canonical);
  }

  static String sha256Hex(String s) =>
      const DartSha256().hashSync(utf8.encode(s)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Oturum açan kullanıcının klasörünü hazırlar. Kullanıcı değişince klasör de değişir.
  Future<void> init(String? userId) async {
    final uid = (userId ?? '').trim();
    if (uid.isEmpty) {
      _dir = null;
      _owner = '';
      return;
    }
    if (uid == _owner && _dir != null) return;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/juzzio_cache/$uid/media');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
      _owner = uid;
      // Açılışta, ilk kareyi yavaşlatmadan arka planda temizlik
      Timer(const Duration(seconds: 8), () => unawaited(prune()));
    } catch (_) {
      _dir = null;
      _owner = '';
    }
  }

  /// Önbellekte varsa dosyayı HEMEN döndürür (ağ yok); yoksa null.
  File? cachedFile(String url) {
    final d = _dir;
    if (d == null || url.isEmpty) return null;
    final f = File('${d.path}/${keyFor(url)}');
    try {
      return f.existsSync() && f.lengthSync() > 0 ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Önbellekten ya da ağdan (indirip saklayarak) dosya. Ulaşılamazsa null.
  /// [resolvedUrl] verilirse o adresten indirilir (önceden imzalanmış adres).
  Future<File?> loadFile(String url, {String? resolvedUrl}) {
    final hit = cachedFile(url);
    if (hit != null) {
      _touch(hit);
      return Future.value(hit);
    }
    final k = keyFor(url);
    return _inFlight[k] ??= _download(url, k, resolvedUrl).whenComplete(() {
      _inFlight.remove(k);
    });
  }

  Future<Uint8List?> loadBytes(String url, {String? resolvedUrl}) async {
    final f = await loadFile(url, resolvedUrl: resolvedUrl);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<File?> _download(String url, String key, String? resolvedUrl) async {
    try {
      final target = resolvedUrl ?? await JuzzioMediaUrl.resolve(url);
      // Zaman aşımı dart:io bağlantı düzeyinde (test ortamında bekleyen Timer bırakmaz)
      final client = IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 20));
      final http.Response res;
      try {
        res = await client.get(Uri.parse(target));
      } finally {
        client.close();
      }
      if (res.statusCode != 200 || res.bodyBytes.isEmpty || res.bodyBytes.length > maxItemBytes) return null;
      final d = _dir;
      if (d == null) {
        // Klasör yoksa (oturum yok / test) yalnız geçici dosya: yine de gösterilebilsin
        final tmp = File('${Directory.systemTemp.path}/juzzio_media_$key');
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        return tmp;
      }
      final f = File('${d.path}/$key');
      final part = File('${f.path}.part');
      await part.writeAsBytes(res.bodyBytes, flush: true);
      await part.rename(f.path);
      if (++_writesSincePrune >= 20) {
        _writesSincePrune = 0;
        unawaited(prune());
      }
      return f;
    } catch (_) {
      return null;
    }
  }

  void _touch(File f) {
    try {
      f.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  Future<int> sizeBytes() async {
    final d = _dir;
    if (d == null || !d.existsSync()) return 0;
    var sum = 0;
    for (final e in d.listSync(followLinks: false)) {
      if (e is File) {
        try {
          sum += e.lengthSync();
        } catch (_) {}
      }
    }
    return sum;
  }

  /// Akıllı temizlik: süresi geçenler + LRU ile sınırın %80'ine iner.
  Future<void> prune({int? limit, int? target}) async {
    final d = _dir;
    if (d == null || !d.existsSync()) return;
    final lim = limit ?? limitBytes;
    final tgt = target ?? (lim * 0.8).round();
    final now = DateTime.now();
    final files = <(String, int, DateTime)>[];
    for (final e in d.listSync(followLinks: false)) {
      if (e is! File) continue;
      try {
        final mod = e.lastModifiedSync();
        // Yarım kalmış indirmeler (1 saatten eski) her zaman silinir
        if (e.path.endsWith('.part')) {
          if (now.difference(mod).inHours >= 1) e.deleteSync();
          continue;
        }
        files.add((e.path, e.lengthSync(), mod));
      } catch (_) {}
    }
    for (final path in planPrune(files, limit: lim, target: tgt, maxAgeDays: maxAgeDays, now: now)) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    unawaited(_pruneTempDecrypted());
  }

  /// Cihazda çözülüp açılan geçici dosyalar (sesli mesaj, belge, video) 1 günden eskiyse silinir.
  Future<void> _pruneTempDecrypted() async {
    try {
      final tmp = await getTemporaryDirectory();
      final now = DateTime.now();
      for (final e in tmp.listSync(followLinks: false)) {
        final name = e.path.split(Platform.pathSeparator).last;
        final ours = name.startsWith('jvn_') || name.startsWith('juzzio_docs') || name.startsWith('juzzio_media_') || name.startsWith('jv_');
        if (!ours) continue;
        try {
          if (now.difference(e.statSync().modified).inHours >= 24) e.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Yalnız medya önbelleğini siler (mesajlar, anahtarlar, hesap verisi silinmez).
  Future<int> clear() async {
    final d = _dir;
    if (d == null || !d.existsSync()) return 0;
    final freed = await sizeBytes();
    try {
      for (final e in d.listSync(followLinks: false)) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }
}

/// Çevrimdışı çalışan görsel sağlayıcı: önce disk önbelleği, yoksa indirip saklar.
@immutable
class JuzzioCachedImageProvider extends ImageProvider<JuzzioCachedImageProvider> {
  const JuzzioCachedImageProvider(this.url, {this.resolvedUrl, this.scale = 1.0});

  final String url;
  final String? resolvedUrl;
  final double scale;

  @override
  Future<JuzzioCachedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<JuzzioCachedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(JuzzioCachedImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: key.scale);

  static Future<ui.Codec> _load(JuzzioCachedImageProvider key, ImageDecoderCallback decode) async {
    final bytes = await JuzzioMediaDiskCache.instance.loadBytes(key.url, resolvedUrl: key.resolvedUrl);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('juzzio_image_unavailable');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  // Aynı nesne kimliği → aynı görsel (imzalı adres token'ı farklı olsa bile)
  @override
  bool operator ==(Object other) =>
      other is JuzzioCachedImageProvider && JuzzioMediaDiskCache.keyFor(other.url) == JuzzioMediaDiskCache.keyFor(url) && other.scale == scale;

  @override
  int get hashCode => Object.hash(JuzzioMediaDiskCache.keyFor(url), scale);
}
