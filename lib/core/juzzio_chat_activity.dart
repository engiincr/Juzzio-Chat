// =============================================================================
// JUZZIO v0.9.0 — Sohbet etkinlik durumu (ek paket N-A)
//
// Tek merkezi öncelik çözümleyici. Öncelik: Ses kaydediliyor > Yazıyor > Çevrimiçi > Son görülme.
// Uzak etkinlik olayı en fazla [ttl] (3 sn) geçerlidir; gönderen etkin kaldıkça [keepAlive]
// (2 sn) aralıkla yeniler. Olay gelmezse durum kendiliğinden düşer (ağ kopsa bile "yazıyor"
// takılı kalmaz). Saf Dart; saat enjekte edilir → birim testlenir.
// =============================================================================

/// Bir kullanıcının sohbetteki anlık etkinliği.
enum JuzzioActivityState { idle, typing, recording }

/// Sohbet başlığında gösterilecek tek durum.
enum JuzzioHeaderStatusKind { recording, typing, online, lastSeen, none }

class JuzzioHeaderStatus {
  const JuzzioHeaderStatus(this.kind, {this.userIds = const <String>[], this.lastSeen});
  final JuzzioHeaderStatusKind kind;

  /// Yazan / kaydeden kullanıcılar (grup başlığında isim göstermek için), en yeni önce.
  final List<String> userIds;
  final DateTime? lastSeen;
}

JuzzioActivityState juzzioActivityFromWire(Object? v) {
  switch (v) {
    case 'typing':
      return JuzzioActivityState.typing;
    case 'recording':
      return JuzzioActivityState.recording;
    default:
      return JuzzioActivityState.idle;
  }
}

/// Alıcı tarafı: gelen olayları tutar ve başlık durumunu hesaplar.
class JuzzioChatActivityResolver {
  JuzzioChatActivityResolver({DateTime Function()? clock, this.ttl = const Duration(seconds: 3)})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration ttl;
  final Map<String, (JuzzioActivityState, DateTime)> _events = {};

  /// Uzak olay. [allowedUserIds] verilirse odada olmayan kimlik yok sayılır (sahte kimlik koruması),
  /// kendi kimliğimiz ([selfId]) de yok sayılır. Durum değiştiyse true döner.
  bool onRemote(String userId, JuzzioActivityState state, {String? selfId, Set<String>? allowedUserIds}) {
    if (userId.isEmpty || userId == selfId) return false;
    if (allowedUserIds != null && !allowedUserIds.contains(userId)) return false;
    final prev = _events[userId]?.$1;
    if (state == JuzzioActivityState.idle) {
      return _events.remove(userId) != null;
    }
    _events[userId] = (state, _clock());
    return prev != state;
  }

  /// Süresi dolan olayları siler; bir şey silindiyse true.
  bool prune() {
    final now = _clock();
    final before = _events.length;
    _events.removeWhere((_, v) => now.difference(v.$2) > ttl);
    return _events.length != before;
  }

  void clear() => _events.clear();

  bool get hasActive {
    prune();
    return _events.isNotEmpty;
  }

  JuzzioHeaderStatus resolve({bool isOnline = false, DateTime? lastSeen}) {
    prune();
    List<String> who(JuzzioActivityState s) {
      final list = _events.entries.where((e) => e.value.$1 == s).toList()
        ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
      return [for (final e in list) e.key];
    }

    final rec = who(JuzzioActivityState.recording);
    if (rec.isNotEmpty) return JuzzioHeaderStatus(JuzzioHeaderStatusKind.recording, userIds: rec);
    final typ = who(JuzzioActivityState.typing);
    if (typ.isNotEmpty) return JuzzioHeaderStatus(JuzzioHeaderStatusKind.typing, userIds: typ);
    if (isOnline) return const JuzzioHeaderStatus(JuzzioHeaderStatusKind.online);
    if (lastSeen != null) return JuzzioHeaderStatus(JuzzioHeaderStatusKind.lastSeen, lastSeen: lastSeen);
    return const JuzzioHeaderStatus(JuzzioHeaderStatusKind.none);
  }
}

/// Gönderen tarafı: ne zaman yayın yapılacağına karar verir (ağ trafiğini sınırlar).
class JuzzioActivitySender {
  JuzzioActivitySender({
    DateTime Function()? clock,
    this.keepAlive = const Duration(seconds: 2),
    this.typingIdleAfter = const Duration(seconds: 4),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration keepAlive;

  /// Son tuş vuruşundan bu kadar sonra "yazıyor" kendiliğinden biter.
  final Duration typingIdleAfter;

  JuzzioActivityState _state = JuzzioActivityState.idle;
  DateTime? _lastSent;
  DateTime? _lastKeystroke;

  JuzzioActivityState get state => _state;

  /// Yerel durum değişti; yayınlanması gereken durum varsa onu döndürür (yoksa null).
  JuzzioActivityState? set(JuzzioActivityState next) {
    final now = _clock();
    if (next == JuzzioActivityState.typing) _lastKeystroke = now;
    // Kayıt sürerken yazma olayı kaydı ezmez
    if (_state == JuzzioActivityState.recording && next == JuzzioActivityState.typing) return null;
    if (next == _state) {
      if (next == JuzzioActivityState.idle) return null;
      if (_lastSent != null && now.difference(_lastSent!) < keepAlive) return null;
    }
    _state = next;
    _lastSent = now;
    return next;
  }

  /// Periyodik çağrılır: etkin durumu canlı tutar, bayat yazmayı bitirir.
  JuzzioActivityState? tick() {
    final now = _clock();
    if (_state == JuzzioActivityState.typing &&
        _lastKeystroke != null &&
        now.difference(_lastKeystroke!) >= typingIdleAfter) {
      _state = JuzzioActivityState.idle;
      _lastSent = now;
      return JuzzioActivityState.idle;
    }
    if (_state != JuzzioActivityState.idle && (_lastSent == null || now.difference(_lastSent!) >= keepAlive)) {
      _lastSent = now;
      return _state;
    }
    return null;
  }
}
