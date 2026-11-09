// =============================================================================
// JUZZIO v0.9.5 — Seriler, rozetler ve "Bugün geçmişte" anıları
//  Rozetler sunucuda gerçek veriden hesaplanır (istemci rozet yazamaz).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_ui_kit.dart';

class JuzzioBadgeInfo {
  final String code;
  final String emoji;
  final String title;
  final String hint;
  const JuzzioBadgeInfo(this.code, this.emoji, this.title, this.hint);
}

List<JuzzioBadgeInfo> juzzioBadgeCatalog(JuzzioAppController app) => [
      JuzzioBadgeInfo('streak_7', '🔥', app.trEn('7 günlük seri', '7-day streak', '7-Tage-Serie'), app.trEn('7 gün üst üste uygulamayı aç', 'Open the app 7 days in a row', '7 Tage in Folge')),
      JuzzioBadgeInfo('streak_30', '⚡', app.trEn('30 günlük seri', '30-day streak', '30-Tage-Serie'), app.trEn('30 gün üst üste', '30 days in a row', '30 Tage in Folge')),
      JuzzioBadgeInfo('streak_100', '🏆', app.trEn('100 günlük seri', '100-day streak', '100-Tage-Serie'), app.trEn('100 gün üst üste', '100 days in a row', '100 Tage in Folge')),
      JuzzioBadgeInfo('chick_carer', '🐥', app.trEn('Özenli bakıcı', 'Caring keeper', 'Fürsorglich'), app.trEn('Civcivi 7 gün üst üste besle', 'Feed your chick 7 days in a row', 'Küken 7 Tage füttern')),
      JuzzioBadgeInfo('chick_adult', '🐔', app.trEn('Tavuk büyüttü', 'Raised a hen', 'Huhn großgezogen'), app.trEn('Civcivi yetişkin evreye ulaştır', 'Grow your chick to adult', 'Küken erwachsen')),
      JuzzioBadgeInfo('social_10', '🤝', app.trEn('Sosyal', 'Social', 'Sozial'), app.trEn('10 arkadaş', '10 friends', '10 Freunde')),
      JuzzioBadgeInfo('social_50', '🌍', app.trEn('Topluluk yıldızı', 'Community star', 'Community-Star'), app.trEn('50 arkadaş', '50 friends', '50 Freunde')),
      JuzzioBadgeInfo('first_post', '✨', app.trEn('İlk paylaşım', 'First post', 'Erster Beitrag'), app.trEn('İlk gönderini paylaş', 'Share your first post', 'Ersten Beitrag teilen')),
      JuzzioBadgeInfo('creator_25', '🎨', app.trEn('İçerik üreticisi', 'Creator', 'Creator'), app.trEn('25 gönderi', '25 posts', '25 Beiträge')),
      JuzzioBadgeInfo('veteran', '🎖️', app.trEn('Kıdemli', 'Veteran', 'Veteran'), app.trEn('1 yıldır Juzzio\'da', '1 year on Juzzio', '1 Jahr dabei')),
    ];

class JuzzioBadgesScreen extends StatefulWidget {
  const JuzzioBadgesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioBadgesScreen()));

  @override
  State<JuzzioBadgesScreen> createState() => _JuzzioBadgesScreenState();
}

class _JuzzioBadgesScreenState extends State<JuzzioBadgesScreen> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  Set<String> _earned = {};
  Map<String, dynamic> _streaks = {};
  List<Map<String, dynamic>> _memories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _db.rpc('user_badges');
      final s = await _db.rpc('my_streaks');
      final m = await _db.rpc('my_memories');
      if (!mounted) return;
      setState(() {
        _earned = {for (final x in (b is List ? b : const [])) x.toString()};
        _streaks = s is Map ? Map<String, dynamic>.from(s) : {};
        _memories = [for (final r in (m is List ? m : const [])) Map<String, dynamic>.from(r as Map)];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _streak(String kind, String field) => int.tryParse('${(_streaks[kind] as Map?)?[field] ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final catalog = juzzioBadgeCatalog(_app);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(title: Text(_app.trEn('Rozetler ve seriler', 'Badges & streaks', 'Abzeichen & Serien'))),
      body: _loading
          ? const JuzzioListSkeleton()
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: _streakCard(p, '🔥', _app.trEn('Günlük seri', 'Daily streak', 'Tagesserie'), _streak('daily_app', 'current'), _streak('daily_app', 'longest'))),
                const SizedBox(width: 10),
                Expanded(child: _streakCard(p, '🐥', _app.trEn('Civciv bakımı', 'Chick care', 'Kükenpflege'), _streak('chick_care', 'current'), _streak('chick_care', 'longest'))),
              ]),
              const SizedBox(height: 18),
              Text('${_app.trEn('Rozetler', 'Badges', 'Abzeichen')} · ${_earned.length}/${catalog.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
                children: [
                  for (final b in catalog)
                    Tooltip(
                      message: b.hint,
                      child: Opacity(
                        opacity: _earned.contains(b.code) ? 1 : 0.35,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: p.textMuted.withValues(alpha: 0.1)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(b.emoji, style: const TextStyle(fontSize: 34)),
                            const SizedBox(height: 6),
                            Text(b.title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
              if (_memories.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(_app.trEn('Bugün geçmişte', 'On this day', 'An diesem Tag'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                for (final m in _memories)
                  ListTile(
                    leading: const Text('📸', style: TextStyle(fontSize: 24)),
                    title: Text((m['caption'] ?? '').toString().isEmpty ? _app.trEn('Gönderin', 'Your post', 'Dein Beitrag') : m['caption'].toString()),
                    subtitle: Text('${DateTime.tryParse('${m['created_at']}')?.year ?? ''}'),
                  ),
              ],
            ]),
    );
  }

  Widget _streakCard(JuzzioPalette p, String emoji, String title, int current, int longest) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: p.textMuted.withValues(alpha: 0.1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$emoji $title', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('$current', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          Text('${_app.trEn('En uzun', 'Best', 'Bestwert')}: $longest', style: TextStyle(color: p.textSecondary, fontSize: 12)),
        ]),
      );
}
