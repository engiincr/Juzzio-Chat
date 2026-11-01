// v0.8.0 — Görülen hikâyeler: halka izlendikten sonra kaybolur (cihazda kalıcı)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class JuzzioStorySeen extends ChangeNotifier {
  JuzzioStorySeen._();
  static final JuzzioStorySeen instance = JuzzioStorySeen._();

  final Map<String, int> _seen = {};
  bool _loaded = false;

  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/juzzio_story_seen.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) m.forEach((k, v) => _seen['$k'] = (v as num).toInt());
      }
      final cutoff = DateTime.now().subtract(const Duration(hours: 48)).millisecondsSinceEpoch;
      _seen.removeWhere((_, v) => v < cutoff);
      notifyListeners();
    } catch (_) {}
  }

  bool isSeen(String storyId) => _seen.containsKey(storyId);

  /// Kişinin tüm aktif hikâyeleri görüldüyse true
  bool allSeen(Iterable<String> storyIds) => storyIds.isNotEmpty && storyIds.every(isSeen);

  Future<void> markSeen(String storyId) async {
    if (storyId.isEmpty || _seen.containsKey(storyId)) return;
    _seen[storyId] = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    try {
      await (await _file()).writeAsString(jsonEncode(_seen));
    } catch (_) {}
  }
}
