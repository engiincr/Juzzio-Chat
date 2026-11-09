// =============================================================================
// JUZZIO v0.9.7 — Drift (SQLite) yerel önbellek
//  • Stale-While-Revalidate: uygulama açılır açılmaz sohbet listesi, profiller ve
//    her sohbetin son mesajları SQLite'tan ANINDA okunur; ağ senkronizasyonu arka
//    planda sürer ve kullanıcıyı asla bekletmez.
//  • Hesaba özel veritabanı dosyası (…/juzzio_cache/<uid>/juzzio_local.sqlite);
//    çıkışta dosya silinir — hesaplar arası veri sızmaz.
//  • Şifreli (E2EE) mesajlar diske SUNUCUDAKİ şifreli hâliyle yazılır; çözme her
//    açılışta cihazda yapılır (önbellek düz metin içermez).
//  • Drift'in kod üretimi (build_runner) kullanılmaz: şema el ile tanımlanır ve
//    customStatement / customSelect ile çalışılır. Böylece CI'da ek adım gerekmez.
//  • Sorgular arka plan izolatında çalışır (NativeDatabase.createInBackground):
//    ana iş parçacığı (UI) hiç bloklanmaz.
//  • Drift açılamazsa (ör. test ortamı) çağıran eski JSON dosya önbelleğine düşer.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Kod üretimsiz Drift veritabanı.
class JuzzioLocalDb extends GeneratedDatabase {
  JuzzioLocalDb(super.executor);

  /// Şema sürümü: tablo yapısı değişirse artırılır (onUpgrade önbelleği yeniden kurar).
  static const int kSchemaVersion = 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  @override
  int get schemaVersion => kSchemaVersion;

  static const List<String> _ddl = [
    'CREATE TABLE IF NOT EXISTS cached_messages ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'room_id TEXT NOT NULL, '
        'created_at TEXT NOT NULL, '
        'row_json TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS idx_cached_messages_room ON cached_messages (room_id, created_at)',
    'CREATE TABLE IF NOT EXISTS kv_cache ('
        'name TEXT NOT NULL PRIMARY KEY, '
        'json TEXT NOT NULL, '
        'updated_at INTEGER NOT NULL)',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final s in _ddl) {
            await customStatement(s);
          }
        },
        onUpgrade: (m, from, to) async {
          // Önbellek yeniden üretilebilir veridir: şema değişince temiz kurulum
          await customStatement('DROP TABLE IF EXISTS cached_messages');
          await customStatement('DROP TABLE IF EXISTS kv_cache');
          for (final s in _ddl) {
            await customStatement(s);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
        },
      );

  // ---------------------------------------------------------------------------
  // Anahtar–değer (sohbet listesi, profiller, bekleyen işlemler…)
  // ---------------------------------------------------------------------------
  Future<void> putJson(String name, Object data) => customStatement(
        'INSERT INTO kv_cache (name, json, updated_at) VALUES (?, ?, ?) '
        'ON CONFLICT(name) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at',
        [name, jsonEncode(data), DateTime.now().millisecondsSinceEpoch],
      );

  Future<Object?> getJson(String name) async {
    final rows = await customSelect('SELECT json FROM kv_cache WHERE name = ?', variables: [Variable.withString(name)]).get();
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first.data['json'] as String);
  }

  Future<void> deleteJson(String name) => customStatement('DELETE FROM kv_cache WHERE name = ?', [name]);

  // ---------------------------------------------------------------------------
  // Mesajlar
  // ---------------------------------------------------------------------------

  /// Canlı akıştan gelen pencereyi yazar. Penceredeki en eski mesajdan yeni olup
  /// artık sunucuda bulunmayan (silinmiş) satırlar da kaldırılır. Oda başına en
  /// fazla [keep] mesaj saklanır.
  Future<void> upsertRoomWindow(String roomId, List<Map<String, dynamic>> rowsAsc, {int keep = 300}) async {
    if (rowsAsc.isEmpty) return;
    await transaction(() async {
      final ids = <String>[];
      for (final r in rowsAsc) {
        final id = '${r['id'] ?? ''}';
        if (id.isEmpty) continue;
        ids.add(id);
        await customStatement(
          'INSERT INTO cached_messages (id, room_id, created_at, row_json) VALUES (?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET room_id = excluded.room_id, created_at = excluded.created_at, row_json = excluded.row_json',
          [id, roomId, '${r['created_at'] ?? ''}', jsonEncode(r)],
        );
      }
      final oldest = '${rowsAsc.first['created_at'] ?? ''}';
      if (oldest.isNotEmpty && ids.isNotEmpty) {
        final marks = List.filled(ids.length, '?').join(',');
        await customStatement(
          'DELETE FROM cached_messages WHERE room_id = ? AND created_at >= ? AND id NOT IN ($marks)',
          [roomId, oldest, ...ids],
        );
      }
      await customStatement(
        'DELETE FROM cached_messages WHERE room_id = ? AND id NOT IN '
        '(SELECT id FROM cached_messages WHERE room_id = ? ORDER BY created_at DESC LIMIT ?)',
        [roomId, roomId, keep],
      );
    });
  }

  /// Odanın en yeni [limit] mesajı (eskiden yeniye sıralı).
  Future<List<Map<String, dynamic>>> roomMessages(String roomId, {int limit = 50}) async {
    final rows = await customSelect(
      'SELECT row_json FROM cached_messages WHERE room_id = ? ORDER BY created_at DESC LIMIT ?',
      variables: [Variable.withString(roomId), Variable.withInt(limit)],
    ).get();
    final out = <Map<String, dynamic>>[];
    for (final r in rows.reversed) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(r.data['row_json'] as String) as Map));
      } catch (_) {}
    }
    return out;
  }

  /// Odanın son mesajı (sohbet listesi önizlemesi için).
  Future<Map<String, dynamic>?> lastRoomMessage(String roomId) async {
    final list = await roomMessages(roomId, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  Future<int> cachedMessageCount() async {
    final rows = await customSelect('SELECT COUNT(*) AS n FROM cached_messages').get();
    return rows.isEmpty ? 0 : (rows.first.data['n'] as int? ?? 0);
  }

  Future<void> clearAll() async {
    await customStatement('DELETE FROM cached_messages');
    await customStatement('DELETE FROM kv_cache');
  }
}

/// Hesap başına tek bağlantı.
class JuzzioLocalStore {
  JuzzioLocalStore._();
  static final JuzzioLocalStore instance = JuzzioLocalStore._();

  JuzzioLocalDb? _db;
  String? _dbPath;
  Future<JuzzioLocalDb?>? _opening;

  /// Testlerde veya Drift'in yüklenemediği ortamlarda kapatılır.
  static bool enabled = true;

  /// [folder]: hesaba özel önbellek klasörü.
  Future<JuzzioLocalDb?> open(Directory folder) {
    if (!enabled) return Future.value(null);
    final path = '${folder.path}/juzzio_local.sqlite';
    if (_db != null && _dbPath == path) return Future.value(_db);
    final pending = _opening;
    if (pending != null && _dbPath == path) return pending;
    _dbPath = path;
    final f = () async {
      try {
        await _db?.close();
        if (!folder.existsSync()) folder.createSync(recursive: true);
        final db = JuzzioLocalDb(NativeDatabase.createInBackground(File(path)));
        // Bağlantıyı hemen dene; başarısızsa JSON önbelleğe düşülür
        await db.customSelect('SELECT 1').get();
        _db = db;
        return db;
      } catch (_) {
        _db = null;
        return null;
      } finally {
        _opening = null;
      }
    }();
    _opening = f;
    return f;
  }

  /// Çıkışta: bağlantıyı kapatıp dosyayı siler.
  Future<void> closeAndDelete() async {
    final path = _dbPath;
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _dbPath = null;
    if (path == null) return;
    for (final suffix in const ['', '-wal', '-shm']) {
      try {
        final f = File('$path$suffix');
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }
}
