// =============================================================================
// JUZZIO 2.1 — Keşfet (yeni insanlarla tanış) servis katmanı
//  Sunucu: discover_set_enabled · discover_candidates · discover_act · discover_list (SQL 10.45)
//  Kartta yalnız kişinin "herkese" açtığı bilgiler bulunur; konum/yaş kullanılmaz.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'supabase_service.dart';

class JuzzioDiscoverCard {
  const JuzzioDiscoverCard({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.coverUrl,
    this.bio = '',
    this.lang = '',
    this.isVerified = false,
    this.online = false,
    this.superLike = false,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? coverUrl;
  final String bio;
  final String lang;
  final bool isVerified;
  final bool online;
  final bool superLike;

  static JuzzioDiscoverCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    String? url(Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return JuzzioDiscoverCard(
      id: id,
      username: (raw['username'] ?? '').toString(),
      displayName: (raw['display_name'] ?? '').toString(),
      avatarUrl: url(raw['avatar_url']),
      coverUrl: url(raw['cover_url']),
      bio: (raw['bio'] ?? '').toString(),
      lang: (raw['lang'] ?? '').toString(),
      isVerified: raw['is_verified'] == true,
      online: raw['online'] == true,
      superLike: raw['super'] == true,
    );
  }

  static List<JuzzioDiscoverCard> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(fromJson).whereType<JuzzioDiscoverCard>().toList(growable: false);
  }
}

class JuzzioDiscoverService {
  JuzzioDiscoverService._();
  static final JuzzioDiscoverService instance = JuzzioDiscoverService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  Future<bool> isEnabled() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return false;
    try {
      final row = await _client.from('profiles').select('discoverable').eq('id', uid).maybeSingle();
      return row != null && row['discoverable'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool on) async {
    final r = await _client.rpc('discover_set_enabled', params: {'p_on': on});
    return r == true;
  }

  Future<List<JuzzioDiscoverCard>> candidates({int limit = 20}) async {
    final r = await _client.rpc('discover_candidates', params: {'p_limit': limit});
    return JuzzioDiscoverCard.listFrom(r);
  }

  /// [action]: like · super · pass · undo — eşleşme olursa true döner
  Future<bool> act(String targetId, String action) async {
    final r = await _client.rpc('discover_act', params: {'p_target': targetId, 'p_action': action});
    return r is Map && r['matched'] == true;
  }

  Future<List<JuzzioDiscoverCard>> matches() async => JuzzioDiscoverCard.listFrom(await _client.rpc('discover_list', params: {'p_kind': 'matches'}));

  Future<List<JuzzioDiscoverCard>> likesMe() async => JuzzioDiscoverCard.listFrom(await _client.rpc('discover_list', params: {'p_kind': 'likes'}));
}
