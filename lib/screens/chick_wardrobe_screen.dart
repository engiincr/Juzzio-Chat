// =============================================================================
// JUZZIO v0.9.4 — Civciv gardırobu: şapka, gözlük, kıyafet, ayakkabı, tema ve renk
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_chick_wardrobe.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_chick_art.dart';

class JuzzioChickWardrobeScreen extends StatefulWidget {
  const JuzzioChickWardrobeScreen({super.key, required this.mood});
  final String mood;

  @override
  State<JuzzioChickWardrobeScreen> createState() => _JuzzioChickWardrobeScreenState();
}

const List<String> _kSlots = ['hat', 'glasses', 'outfit', 'shoes', 'theme', 'color'];
const List<String> _kColors = ['#FFD43B', '#FF8A65', '#F06292', '#BA68C8', '#64B5F6', '#4DB6AC', '#AED581', '#FFFFFF', '#A1887F'];

class _JuzzioChickWardrobeScreenState extends State<JuzzioChickWardrobeScreen> {
  final _svc = JuzzioChickWardrobeService.instance;
  final _app = JuzzioAppController.instance;
  JuzzioChickWardrobeState? _st;
  String _slot = 'hat';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _st = _svc.last;
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await _svc.fetch();
      if (mounted) setState(() => _st = st);
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _run(Future<JuzzioChickWardrobeState> Function() op) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final st = await op();
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _st = st);
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _slotLabel(String s) {
    switch (s) {
      case 'hat':
        return _app.trEn('Şapka', 'Hats', 'Hüte');
      case 'glasses':
        return _app.trEn('Gözlük', 'Glasses', 'Brillen');
      case 'outfit':
        return _app.trEn('Kıyafet', 'Outfits', 'Outfits');
      case 'shoes':
        return _app.trEn('Ayakkabı', 'Shoes', 'Schuhe');
      case 'theme':
        return _app.trEn('Tema', 'Themes', 'Themen');
      default:
        return _app.trEn('Renk', 'Color', 'Farbe');
    }
  }

  String _itemLabel(String code) {
    const tr = {
      'party_hat': 'Parti şapkası', 'crown': 'Taç', 'beanie': 'Bere', 'cowboy_hat': 'Kovboy şapkası',
      'round_glasses': 'Yuvarlak gözlük', 'sunglasses': 'Güneş gözlüğü', 'heart_glasses': 'Kalp gözlük',
      'bow_tie': 'Papyon', 'scarf': 'Atkı', 'cape': 'Pelerin', 'sneakers': 'Spor ayakkabı', 'boots': 'Bot',
      'theme_meadow': 'Çayır', 'theme_night': 'Gece', 'theme_beach': 'Plaj', 'theme_snow': 'Kar',
      'tiara': 'Prenses tacı', 'flower_crown': 'Çiçek taç', 'wizard_hat': 'Büyücü şapkası', 'star_glasses': 'Yıldız gözlük',
      'tutu': 'Prenses tütüsü', 'necklace': 'İnci kolye', 'ballet_shoes': 'Bale pabucu',
      'theme_castle': 'Şato', 'theme_space': 'Uzay', 'theme_sakura': 'Sakura',
    };
    const en = {
      'party_hat': 'Party hat', 'crown': 'Crown', 'beanie': 'Beanie', 'cowboy_hat': 'Cowboy hat',
      'round_glasses': 'Round glasses', 'sunglasses': 'Sunglasses', 'heart_glasses': 'Heart glasses',
      'bow_tie': 'Bow tie', 'scarf': 'Scarf', 'cape': 'Cape', 'sneakers': 'Sneakers', 'boots': 'Boots',
      'theme_meadow': 'Meadow', 'theme_night': 'Night', 'theme_beach': 'Beach', 'theme_snow': 'Snow',
      'tiara': 'Princess tiara', 'flower_crown': 'Flower crown', 'wizard_hat': 'Wizard hat', 'star_glasses': 'Star glasses',
      'tutu': 'Princess tutu', 'necklace': 'Pearl necklace', 'ballet_shoes': 'Ballet shoes',
      'theme_castle': 'Castle', 'theme_space': 'Space', 'theme_sakura': 'Sakura',
    };
    return _app.uiLang.startsWith('tr') ? (tr[code] ?? code) : (en[code] ?? code);
  }

  Widget _preview(Map<String, String> style, {double size = 220}) {
    final colors = juzzioChickThemeColors(style['theme'], _app.isDark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
      ),
      child: CustomPaint(painter: JuzzioChickPainter(stage: (_st?.stage ?? 1).clamp(1, 3), mood: widget.mood, style: style)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final st = _st;
    return Scaffold(
      appBar: AppBar(
        title: Text(_app.trEn('Gardırop', 'Wardrobe', 'Garderobe')),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('🪙 ${st?.coins ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ],
      ),
      body: st == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : !st.hasChick
              ? Center(child: Text(_app.trEn('Önce bir civcivin olmalı.', 'You need a chick first.', 'Du brauchst zuerst ein Küken.')))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Center(child: _preview(st.style)),
                  const SizedBox(height: 8),
                  Text(
                    _app.trEn('Civcivi besledikçe jeton kazanırsınız (her besleme 4, her evre 30). Ortak civcivin cüzdanı ikinizindir.',
                        'Earn coins by feeding (4 per feed, 30 per stage). Both owners share the wallet.',
                        'Münzen durch Füttern (4 pro Fütterung, 30 pro Stufe). Beide teilen die Geldbörse.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final s in _kSlots)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(_slotLabel(s)), selected: _slot == s, onSelected: (_) => setState(() => _slot = s)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (_slot == 'color')
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      GestureDetector(
                        onTap: () => _run(() => _svc.setColor(null)),
                        child: CircleAvatar(radius: 24, backgroundColor: p.textMuted.withValues(alpha: 0.2), child: const Icon(Icons.refresh_rounded)),
                      ),
                      for (final c in _kColors)
                        GestureDetector(
                          onTap: () => _run(() => _svc.setColor(c)),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: juzzioParseHexColor(c),
                              border: Border.all(color: st.style['color'] == c ? JuzzioColors.blue600 : Colors.black12, width: st.style['color'] == c ? 3 : 1),
                            ),
                          ),
                        ),
                    ])
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                      children: [
                        for (final a in st.catalog.where((a) => a.slot == _slot)) _itemTile(st, a, p),
                      ],
                    ),
                ]),
    );
  }

  Widget _itemTile(JuzzioChickWardrobeState st, JuzzioChickAccessory a, JuzzioPalette p) {
    final equipped = st.style[a.slot] == a.code;
    final owned = st.owns(a);
    final locked = st.stage < a.minStage;
    final style = {...st.style, a.slot: a.code};
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _busy
          ? null
          : () {
              if (equipped) {
                _run(() => _svc.setSlot(a.slot, null));
              } else if (owned) {
                _run(() => _svc.setSlot(a.slot, a.code));
              } else {
                _run(() async {
                  await _svc.buy(a.code);
                  return _svc.setSlot(a.slot, a.code);
                });
              }
            },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: equipped ? JuzzioColors.blue600 : p.textMuted.withValues(alpha: 0.25), width: equipped ? 2.5 : 1),
        ),
        child: Column(children: [
          Expanded(child: FittedBox(child: _preview(style, size: 110))),
          const SizedBox(height: 4),
          Text(_itemLabel(a.code), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          Text(
            equipped
                ? _app.trEn('Giyili', 'Equipped', 'Getragen')
                : owned
                    ? _app.trEn('Giydir', 'Wear', 'Anziehen')
                    : locked
                        ? '🔒 ${_app.trEn('Evre', 'Stage', 'Stufe')} ${a.minStage}'
                        : '🪙 ${a.price}',
            style: TextStyle(color: p.textSecondary, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
