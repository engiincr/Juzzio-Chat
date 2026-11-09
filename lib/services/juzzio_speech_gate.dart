// =============================================================================
// JUZZIO v1.1.0 — Arama altyazısı konuşma kapısı (hayalet metin düzeltmesi)
//
//  Sorun: altyazı için mikrofon ikinci bir dinleyiciyle (record) yankı engelleme ve
//  gürültü bastırma KAPALI, otomatik kazanç AÇIK okunuyor ve ses Deepgram'a kesintisiz
//  gidiyordu. Kimse konuşmazken yükseltilmiş oda gürültüsü ve hoparlörden gelen karşı
//  tarafın sesi tanıyıcıya ulaşıyor; tanıyıcı da sessizlik/gürültüden "Tamam aşkım"
//  gibi kullanıcının söylemediği kalıp ifadeler üretiyordu ("Sen: …" satırı).
//
//  Çözüm (üç katman, hepsi yerel ve saf):
//   1) [JuzzioSpeechGate]: uyarlanır gürültü tabanlı enerji kapısı. Kullanıcı gerçekten
//      konuşmadıkça tanıyıcıya GERÇEK ses yerine dijital sessizlik (sıfır) gönderilir.
//      Sıfırlar zaman çizgisini ve cümle sonu algılamayı korur ama metin üretmez.
//   2) [juzzioAcceptOwnTranscript]: düşük güvenli, son 3,5 sn'de yerel ses olmayan,
//      bilinen hayalet kalıplara uyan ya da karşı taraf konuşurken (ben konuşmuyorken)
//      gelen yankı sonuçları ekrana ve karşıya HİÇ gönderilmez.
//   3) Ekranda görünmüş ama sonra reddedilen ara satır geri çekilir (karşıda da).
// =============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

class JuzzioSpeechGate {
  JuzzioSpeechGate({
    this.minRms = 520,
    this.ratio = 2.8,
    this.attackMs = 90,
    this.hangoverMs = 700,
    this.preRollMs = 240,
    this.sampleRate = 16000,
  });

  /// Konuşma sayılması için en düşük mutlak RMS (PCM16)
  final double minRms;

  /// Gürültü tabanının kaç katı konuşma sayılır
  final double ratio;

  /// Kapının açılması için kesintisiz konuşma süresi
  final int attackMs;

  /// Son sesli parçadan sonra kapının açık kalma süresi (hece arası boşluklar)
  final int hangoverMs;

  /// Kapı açılınca başa eklenen geçmiş (ilk hece kesilmesin)
  final int preRollMs;

  final int sampleRate;

  double _floor = 180;
  int _voicedRunMs = 0;
  bool _open = false;
  DateTime? _lastVoiceAt;
  final List<Uint8List> _preRoll = <Uint8List>[];
  int _preRollHeldMs = 0;

  bool get isOpen => _open;
  double get noiseFloor => _floor;
  DateTime? get lastVoiceAt => _lastVoiceAt;

  int chunkMs(Uint8List pcm) => ((pcm.length ~/ 2) * 1000 / sampleRate).round();

  /// Son [window] içinde yerel konuşma enerjisi var mıydı?
  bool voicedWithin(Duration window, DateTime now) {
    final t = _lastVoiceAt;
    return t != null && now.difference(t) <= window;
  }

  void reset() {
    _floor = 180;
    _voicedRunMs = 0;
    _open = false;
    _lastVoiceAt = null;
    _preRoll.clear();
    _preRollHeldMs = 0;
  }

  static double rmsOf(Uint8List pcm) {
    final n = pcm.length ~/ 2;
    if (n == 0) return 0;
    final bd = ByteData.sublistView(pcm);
    double sum = 0;
    for (var i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little).toDouble();
      sum += s * s;
    }
    return math.sqrt(sum / n);
  }

  /// Bir PCM16 parçasını işler; tanıyıcıya gönderilecek parçaları döndürür.
  /// Kapı kapalıyken aynı uzunlukta dijital sessizlik döner.
  List<Uint8List> process(Uint8List pcm, DateTime now) {
    final dur = chunkMs(pcm);
    final rms = rmsOf(pcm);
    final threshold = math.max(minRms, _floor * ratio);
    final voiced = rms > threshold;

    if (voiced) {
      _voicedRunMs += dur;
    } else {
      _voicedRunMs = 0;
      // gürültü tabanı yalnız sessiz parçalardan öğrenilir (konuşma tabanı yükseltmez)
      _floor = (_floor * 0.94 + rms * 0.06).clamp(40.0, 4000.0);
    }

    if (_open) {
      if (voiced) _lastVoiceAt = now;
      final last = _lastVoiceAt;
      if (last == null || now.difference(last).inMilliseconds > hangoverMs) {
        _open = false;
        _voicedRunMs = 0;
        return [Uint8List(pcm.length)];
      }
      return [pcm];
    }

    if (voiced && _voicedRunMs >= attackMs) {
      _open = true;
      _lastVoiceAt = now;
      final out = <Uint8List>[..._preRoll, pcm];
      _preRoll.clear();
      _preRollHeldMs = 0;
      return out;
    }

    _preRoll.add(pcm);
    _preRollHeldMs += dur;
    while (_preRoll.length > 1 && _preRollHeldMs - chunkMs(_preRoll.first) >= preRollMs) {
      _preRollHeldMs -= chunkMs(_preRoll.removeAt(0));
    }
    return [Uint8List(pcm.length)];
  }
}

/// Tanıyıcıların sessizlik/gürültüden sık ürettiği kalıp ifadeler (normalize edilmiş)
const Set<String> kJuzzioPhantomPhrases = {
  'tamam aşkım', 'tamam aşkım tamam', 'aşkım', 'tamam', 'tamam tamam', 'hı hı', 'hıhı', 'he',
  'evet', 'peki', 'teşekkürler', 'teşekkür ederim', 'çok teşekkürler',
  'izlediğiniz için teşekkürler', 'abone olmayı unutmayın', 'altyazı', 'altyazı mk',
  'thank you', 'thanks', 'thanks for watching', 'thank you for watching', 'you', 'bye', 'okay',
  'ok', 'yeah', 'yes', 'hmm', 'mm', 'uh', 'um', 'oh',
  'danke', 'vielen dank', 'untertitel', 'tschüss', 'ja',
};

String juzzioNormalizeTranscript(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[\.\,\!\?\;\:\"\…\-–—\(\)\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Kendi konuşma sonucumun ekrana/karşıya gidip gitmeyeceğine karar verir.
///  [localVoiceRecent]: konuşma kapısı son ~3,5 sn içinde yerel ses gördü mü (sonuç gecikmesi dahil)
///  [remoteSpeaking]: karşı taraf şu an konuşuyor mu (LiveKit)
///  [localSpeaking]: LiveKit yankısı temizlenmiş yerel izde konuşma görüyor mu
bool juzzioAcceptOwnTranscript({
  required String text,
  double? confidence,
  required bool localVoiceRecent,
  bool remoteSpeaking = false,
  bool localSpeaking = true,
}) {
  final norm = juzzioNormalizeTranscript(text);
  if (norm.isEmpty) return false;
  if (!localVoiceRecent) return false;
  final c = (confidence ?? 1.0).clamp(0.0, 1.0);
  if (c < 0.5) return false;
  final words = norm.split(' ').where((w) => w.isNotEmpty).length;
  if (words <= 3 && c < 0.75) return false;
  if (kJuzzioPhantomPhrases.contains(norm) && c < 0.9) return false;
  // yankı: karşı taraf konuşurken yankısı temizlenmiş izimde konuşma yoksa bu ses benim değil
  if (remoteSpeaking && !localSpeaking && c < 0.92) return false;
  return true;
}
