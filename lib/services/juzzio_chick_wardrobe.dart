// =============================================================================
// JUZZIO v0.9.4 — Civciv gardırobu istemcisi (chick_wardrobe / chick_buy_accessory / chick_set_style)
//  Jeton: her besleme +10, her evre +50; iki sahip ortak cüzdanı kullanır. Satın alma ve
//  giydirme yalnız sunucuda doğrulanır (istemci jeton/sahiplik yazamaz).
// =============================================================================

import 'supabase_service.dart';

class JuzzioChickAccessory {
  final String code;
  final String slot;
  final int price;
  final int minStage;
  const JuzzioChickAccessory({required this.code, required this.slot, required this.price, required this.minStage});
}

class JuzzioChickWardrobeState {
  final bool hasChick;
  final int stage;
  final int coins;
  final Set<String> owned;
  final Map<String, String> style;
  final List<JuzzioChickAccessory> catalog;

  const JuzzioChickWardrobeState({
    this.hasChick = false,
    this.stage = 0,
    this.coins = 0,
    this.owned = const {},
    this.style = const {},
    this.catalog = const [],
  });

  bool owns(JuzzioChickAccessory a) => a.price == 0 || owned.contains(a.code);
  bool canBuy(JuzzioChickAccessory a) => !owns(a) && stage >= a.minStage && coins >= a.price;

  static JuzzioChickWardrobeState fromMap(Object? raw) {
    if (raw is! Map) return const JuzzioChickWardrobeState();
    final st = raw['style'];
    return JuzzioChickWardrobeState(
      hasChick: raw['has_chick'] == true,
      stage: int.tryParse('${raw['stage'] ?? 0}') ?? 0,
      coins: int.tryParse('${raw['coins'] ?? 0}') ?? 0,
      owned: {for (final c in (raw['owned'] is List ? raw['owned'] as List : const [])) c.toString()},
      style: st is Map ? {for (final e in st.entries) e.key.toString(): e.value.toString()} : const {},
      catalog: [
        for (final c in (raw['catalog'] is List ? raw['catalog'] as List : const []))
          if (c is Map)
            JuzzioChickAccessory(
              code: (c['code'] ?? '').toString(),
              slot: (c['slot'] ?? '').toString(),
              price: int.tryParse('${c['price'] ?? 0}') ?? 0,
              minStage: int.tryParse('${c['min_stage'] ?? 0}') ?? 0,
            ),
      ],
    );
  }
}

class JuzzioChickWardrobeService {
  JuzzioChickWardrobeService._();
  static final JuzzioChickWardrobeService instance = JuzzioChickWardrobeService._();

  JuzzioChickWardrobeState? last;

  Future<JuzzioChickWardrobeState> fetch() async {
    final r = await SupabaseService.instance.client.rpc('chick_wardrobe');
    return last = JuzzioChickWardrobeState.fromMap(r);
  }

  Future<JuzzioChickWardrobeState> buy(String code) async {
    final r = await SupabaseService.instance.client.rpc('chick_buy_accessory', params: {'p_code': code});
    return last = JuzzioChickWardrobeState.fromMap(r);
  }

  Future<JuzzioChickWardrobeState> setSlot(String slot, String? code) async {
    final r = await SupabaseService.instance.client.rpc('chick_set_style', params: {'p_slot': slot, 'p_code': code});
    return last = JuzzioChickWardrobeState.fromMap(r);
  }

  Future<JuzzioChickWardrobeState> setColor(String? hex) async {
    final r = await SupabaseService.instance.client.rpc('chick_set_style', params: {'p_slot': 'color', 'p_code': null, 'p_color': hex ?? ''});
    return last = JuzzioChickWardrobeState.fromMap(r);
  }
}
