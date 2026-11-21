// Juzzio 2.1 (Faz 15.4) — Özellik bayrakları ve A/B testi (istemci)
// Sunucu kullanıcıya göre deterministik atama yapar (my_feature_flags); burada yalnız önbellek.
//   if (JuzzioFeatureFlags.instance.isOn('yeni_ozellik')) { ... }
//   final v = JuzzioFeatureFlags.instance.variant('deney'); // 'a' | 'b' | null

import 'package:supabase_flutter/supabase_flutter.dart';

class JuzzioFeatureFlags {
  JuzzioFeatureFlags._();
  static final JuzzioFeatureFlags instance = JuzzioFeatureFlags._();

  Map<String, dynamic> _flags = const {};
  DateTime? _at;

  /// Sunucudan yeniler (en çok 10 dk'da bir; [force] ile hemen)
  Future<void> refresh({bool force = false}) async {
    if (!force && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 10)) return;
    try {
      final r = await Supabase.instance.client.rpc('my_feature_flags');
      if (r is Map) {
        _flags = Map<String, dynamic>.from(r);
        _at = DateTime.now();
      }
    } catch (_) {}
  }

  bool isOn(String key) {
    final f = _flags[key];
    return f is Map && f['on'] == true;
  }

  String? variant(String key) {
    final f = _flags[key];
    if (f is! Map || f['on'] != true) return null;
    final v = f['variant'];
    return v is String && v.isNotEmpty ? v : null;
  }
}
