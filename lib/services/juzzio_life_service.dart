// =============================================================================
// JUZZIO v0.9.0 — Yaşam Merkezi servisi (son talimat §4.1–§4.3)
//  • Görevler + hatırlatmalar: public.life_tasks (kind = task)
//  • Mesaja hatırlatıcı: aynı tablo (kind = message_reminder) — mesaj METNİ sunucuya yazılmaz
//  • Kayıtlı mesajlar: public.saved_messages (karşı tarafa bildirilmez)
// Yetki ve sahiplik sunucuda (RLS + tetikleyici). Hatırlatma bildirimi sunucu zamanlayıcısıyla
// (pg_cron → juzzio_fire_due_reminders → push) gelir; uygulama kapalı olsa da çalışır.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JuzzioLifeTask {
  const JuzzioLifeTask({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    this.dueAt,
    this.remindAt,
    this.doneAt,
    this.roomId,
    this.messageId,
    required this.createdAt,
  });

  final String id;
  final String kind; // task | message_reminder
  final String title;
  final String description;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final DateTime? doneAt;
  final String? roomId;
  final String? messageId;
  final DateTime createdAt;

  bool get isDone => doneAt != null;
  bool get isMessageReminder => kind == 'message_reminder';

  /// Takvimde ve listede kullanılan tarih (son tarih yoksa hatırlatma zamanı).
  DateTime? get when => dueAt ?? remindAt;

  static DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory JuzzioLifeTask.fromMap(Map<String, dynamic> m) => JuzzioLifeTask(
        id: m['id'].toString(),
        kind: (m['kind'] ?? 'task').toString(),
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        dueAt: _d(m['due_at']),
        remindAt: _d(m['remind_at']),
        doneAt: _d(m['done_at']),
        roomId: m['room_id']?.toString(),
        messageId: m['message_id']?.toString(),
        createdAt: _d(m['created_at']) ?? DateTime.now(),
      );
}

/// Saf yardımcılar (birim testli).
class JuzzioLifeMath {
  JuzzioLifeMath._();

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Hatırlatma seçeneği → zaman. 'none' | 'at' | '10m' | '1h' | '1d' (son tarihten önce).
  static DateTime? remindFor(DateTime? due, String option) {
    if (due == null) return null;
    switch (option) {
      case 'at':
        return due;
      case '10m':
        return due.subtract(const Duration(minutes: 10));
      case '1h':
        return due.subtract(const Duration(hours: 1));
      case '1d':
        return due.subtract(const Duration(days: 1));
      default:
        return null;
    }
  }

  /// Bugün / gecikmiş / yaklaşan / tamamlanan gruplaması.
  static ({List<JuzzioLifeTask> overdue, List<JuzzioLifeTask> today, List<JuzzioLifeTask> upcoming, List<JuzzioLifeTask> undated, List<JuzzioLifeTask> done})
      group(List<JuzzioLifeTask> all, DateTime now) {
    final overdue = <JuzzioLifeTask>[], today = <JuzzioLifeTask>[], upcoming = <JuzzioLifeTask>[];
    final undated = <JuzzioLifeTask>[], done = <JuzzioLifeTask>[];
    for (final t in all) {
      final w = t.when;
      if (t.isDone) {
        done.add(t);
      } else if (w == null) {
        undated.add(t);
      } else if (sameDay(w, now)) {
        today.add(t);
      } else if (w.isBefore(now)) {
        overdue.add(t);
      } else {
        upcoming.add(t);
      }
    }
    int byWhen(JuzzioLifeTask a, JuzzioLifeTask b) => a.when!.compareTo(b.when!);
    overdue.sort(byWhen);
    today.sort(byWhen);
    upcoming.sort(byWhen);
    done.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return (overdue: overdue, today: today, upcoming: upcoming, undated: undated, done: done);
  }

  static String requestId() {
    final r = math.Random.secure();
    return 'lt_${List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }
}

class JuzzioLifeService extends ChangeNotifier {
  JuzzioLifeService._();
  static final JuzzioLifeService instance = JuzzioLifeService._();

  SupabaseClient get _c => Supabase.instance.client;

  List<JuzzioLifeTask> _tasks = const [];
  final Set<String> _savedMessageIds = <String>{};
  bool _loaded = false;

  List<JuzzioLifeTask> get tasks => _tasks;
  bool get loaded => _loaded;
  bool isMessageSaved(String messageId) => _savedMessageIds.contains(messageId);

  /// Hata durumunda istisna fırlatır (ekran hata durumunu gösterir).
  Future<List<JuzzioLifeTask>> refresh() async {
    final rows = await _c.from('life_tasks').select().order('created_at', ascending: false).limit(1000);
    _tasks = [for (final r in (rows as List).whereType<Map>()) JuzzioLifeTask.fromMap(Map<String, dynamic>.from(r))];
    _loaded = true;
    notifyListeners();
    return _tasks;
  }

  Future<void> createTask({
    required String title,
    String description = '',
    DateTime? dueAt,
    DateTime? remindAt,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('empty_title');
    await _c.from('life_tasks').insert({
      'title': t.length > 200 ? t.substring(0, 200) : t,
      'description': description.trim(),
      'due_at': dueAt?.toUtc().toIso8601String(),
      'remind_at': remindAt?.toUtc().toIso8601String(),
      'client_request_id': JuzzioLifeMath.requestId(),
    });
    await refresh();
  }

  Future<void> updateTask(String id, {String? title, String? description, DateTime? dueAt, DateTime? remindAt, bool clearDates = false}) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title.trim();
    if (description != null) patch['description'] = description.trim();
    if (clearDates || dueAt != null) patch['due_at'] = dueAt?.toUtc().toIso8601String();
    if (clearDates || remindAt != null) patch['remind_at'] = remindAt?.toUtc().toIso8601String();
    if (patch.isEmpty) return;
    await _c.from('life_tasks').update(patch).eq('id', id);
    await refresh();
  }

  Future<void> setDone(String id, bool done) async {
    await _c.from('life_tasks').update({'done_at': done ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', id);
    await refresh();
  }

  Future<void> deleteTask(String id) async {
    await _c.from('life_tasks').delete().eq('id', id);
    await refresh();
  }

  /// Mesaja hatırlatıcı (yalnız kimlikler gönderilir; metin sunucuya yazılmaz).
  Future<void> remindMessage({required String roomId, required String messageId, required DateTime at}) async {
    await _c.from('life_tasks').insert({
      'kind': 'message_reminder',
      'room_id': roomId,
      'message_id': messageId,
      'remind_at': at.toUtc().toIso8601String(),
      'client_request_id': JuzzioLifeMath.requestId(),
    });
    await refresh();
  }

  JuzzioLifeTask? reminderForMessage(String messageId) {
    for (final t in _tasks) {
      if (t.isMessageReminder && t.messageId == messageId && !t.isDone) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Kayıtlı mesajlar
  // ---------------------------------------------------------------------------
  Future<void> loadSavedIds() async {
    try {
      final rows = await _c.from('saved_messages').select('message_id').limit(2000);
      _savedMessageIds
        ..clear()
        ..addAll([for (final r in (rows as List).whereType<Map>()) r['message_id'].toString()]);
      notifyListeners();
    } catch (_) {}
  }

  /// Yeni durumu döndürür. Hata → istisna (arayüz eski duruma döner).
  Future<bool> toggleSaved({required String roomId, required String messageId}) async {
    if (_savedMessageIds.contains(messageId)) {
      await _c.from('saved_messages').delete().eq('message_id', messageId);
      _savedMessageIds.remove(messageId);
      notifyListeners();
      return false;
    }
    try {
      await _c.from('saved_messages').insert({'room_id': roomId, 'message_id': messageId});
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // zaten kayıtlı (başka cihaz) → başarı
    }
    _savedMessageIds.add(messageId);
    notifyListeners();
    return true;
  }

  /// Bir sohbetin kayıtlı mesaj kimlikleri (yeniden eskiye).
  Future<List<String>> savedMessageIdsForRoom(String roomId) async {
    final rows = await _c.from('saved_messages').select('message_id').eq('room_id', roomId).order('created_at', ascending: false);
    return [for (final r in (rows as List).whereType<Map>()) r['message_id'].toString()];
  }
}
