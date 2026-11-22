// =============================================================================
// JUZZIO v1.2.0 — Modern mesaj kartları
//  • JuzzioReactionBadge: balonun altındaki tepki rozeti (büyük renkli emoji, sayaç,
//    tema duyarlı cam; kırpılmaz)
//  • JuzzioCardShell: kişi kartı / tek seferlik / hikâye / vardiya kartlarının ortak
//    cam kabuğu (giden balonda beyaz, gelen balonda tema metin renkleri)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import 'social_common_widgets.dart';
import 'juzzio_motion.dart';

class JuzzioReactionBadge extends StatelessWidget {
  const JuzzioReactionBadge({
    super.key,
    required this.messageId,
    required this.counts,
    this.popKeys = const <String>{},
    this.inBubble = false,
    this.onMine = false,
  });

  final String messageId;
  final Map<String, int> counts;

  /// v1.2.9: balonun içinde (saatin yanında) küçük cam hap olarak çizilir — gölge/kenar taşması yok
  final bool inBubble;
  final bool onMine;

  /// '<mesajId>|<emoji>' — yalnız yeni eklenen tepki yaylı belirir
  final Set<String> popKeys;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final shown = entries.take(4).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: inBubble
          ? BoxDecoration(
              color: onMine ? Colors.white.withValues(alpha: 0.16) : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: onMine ? Colors.white.withValues(alpha: 0.22) : JuzzioGlassTokens.border),
            )
          : BoxDecoration(
              color: dark ? const Color(0xF21E2028) : const Color(0xF7FFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: JuzzioGlassTokens.borderStrong),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in shown)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: JuzzioPopIn(
                  key: ValueKey('rx_${messageId}_${e.key}'),
                  play: popKeys.contains('$messageId|${e.key}'),
                  // emoji kendi yazı tipiyle, kalın ağırlık olmadan → küçülme/bozulma olmaz
                  child: Text(e.key, style: juzzioEmojiStyle(inBubble ? 16 : 19), textScaler: TextScaler.noScaling),
                ),
              ),
            if (total > 1) ...[
              const SizedBox(width: 4),
              JuzzioBounceOnChange(
                value: total,
                child: Text(
                  '$total',
                  style: TextStyle(color: inBubble && onMine ? Colors.white : JuzzioGlassTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mesaj içi kartların ortak cam kabuğu
class JuzzioCardShell extends StatelessWidget {
  const JuzzioCardShell({super.key, required this.isMe, required this.child, this.onTap, this.padding = const EdgeInsets.all(12), this.width = 248});

  final bool isMe;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? const Color(0x24FFFFFF) : JuzzioGlassTokens.surfaceStrong;
    final border = isMe ? const Color(0x38FFFFFF) : JuzzioGlassTokens.border;
    return SizedBox(
      width: width,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Kart içi metin renkleri (giden balon → beyaz tonlar)
class JuzzioCardInk {
  const JuzzioCardInk(this.isMe);
  final bool isMe;
  Color get primary => isMe ? Colors.white : JuzzioGlassTokens.textPrimary;
  Color get secondary => isMe ? Colors.white70 : JuzzioGlassTokens.textSecondary;
  Color get accent => isMe ? Colors.white : JuzzioGlassTokens.glowText;
  Color get buttonBg => isMe ? const Color(0x33FFFFFF) : JuzzioGlassTokens.glow.withValues(alpha: 0.16);
}

/// Kartın alt eylem düğmesi ("Profili Görüntüle", "Planı aç" …)
class JuzzioCardButton extends StatelessWidget {
  const JuzzioCardButton({super.key, required this.isMe, required this.label, required this.icon, this.onTap});
  final bool isMe;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = JuzzioCardInk(isMe);
    return Material(
      color: ink.buttonBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: ink.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink.accent, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Kişi kartı ("👤 Kişi kartı\nAd\n@kullanici")
// -----------------------------------------------------------------------------

/// Paylaşılan kişi kartı metnini çözer → (ad, kullanıcı adı) ya da null (saf; test edilir)
(String, String)? juzzioParseContactCard(String text) {
  final lines = text.trim().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.length < 2 || !lines.first.startsWith('👤')) return null;
  final handle = lines.last;
  if (!handle.startsWith('@') || handle.length < 2 || handle.contains(' ')) return null;
  final name = lines.length >= 3 ? lines[lines.length - 2] : handle.substring(1);
  return (name, handle.substring(1));
}

class JuzzioContactCard extends StatefulWidget {
  const JuzzioContactCard({super.key, required this.isMe, required this.name, required this.username, required this.onOpenProfile});
  final bool isMe;
  final String name;
  final String username;
  final void Function(String userId) onOpenProfile;

  @override
  State<JuzzioContactCard> createState() => _JuzzioContactCardState();
}

class _JuzzioContactCardState extends State<JuzzioContactCard> {
  static final Map<String, JuzzioUserProfile?> _cache = <String, JuzzioUserProfile?>{};
  JuzzioUserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = widget.username.toLowerCase();
    if (_cache.containsKey(key)) {
      _profile = _cache[key];
      _loading = false;
      return;
    }
    try {
      final id = await SupabaseService.instance.fetchUserIdByUsername(widget.username);
      final p = id == null ? null : await SupabaseService.instance.cachedUserProfile(id);
      _cache[key] = p;
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // çevrimdışı: kart yine ad/kullanıcı adıyla görünür
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open() {
    final p = _profile;
    if (p != null) {
      widget.onOpenProfile(p.id);
      return;
    }
    if (_loading) return;
    JuzzioHud.show(context, icon: Icons.person_off_rounded,
        text: JuzzioAppController.instance.trEn('Profil bulunamadı', 'Profile not found', 'Profil nicht gefunden'));
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final ink = JuzzioCardInk(widget.isMe);
    final p = _profile;
    final name = (p?.displayName.trim().isNotEmpty ?? false) ? p!.displayName : widget.name;
    // GM-024 (v2.2.0): modern, köşeli liquid-glass kişi kartı
    final glow = JuzzioGlassTokens.glow;
    return SizedBox(
      width: 252,
      child: JuzzioLiquidGlass(
        key: const ValueKey('gm024-contact-card'),
        radius: 14,
        blur: 16,
        glowBorder: true,
        tint: widget.isMe ? const Color(0x1FFFFFFF) : null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: glow.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: glow.withValues(alpha: 0.45)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.contact_page_rounded, size: 12, color: ink.accent),
                          const SizedBox(width: 4),
                          Text(app.trEn('Kişi kartı', 'Contact', 'Kontakt').toUpperCase(),
                              style: TextStyle(color: ink.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        ]),
                      ),
                      const Spacer(),
                      if (_loading) const SizedBox(width: 14, height: 14, child: JuzzioOrbitLoader(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(colors: JuzzioGlassTokens.accentPair),
                          boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.30), blurRadius: 12, spreadRadius: -3)],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: JuzzioUserAvatar(imageUrl: p?.avatarUrl, displayName: name, radius: 23),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: ink.primary, fontSize: 15.5, fontWeight: FontWeight.w800)),
                              ),
                              if (p?.isVerified ?? false) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.verified_rounded, size: 15, color: ink.accent),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text('@${widget.username}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink.secondary, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: glow,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _open,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.person_search_rounded, size: 16, color: JuzzioGlassTokens.onGlow),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(app.trEn('Profili Görüntüle', 'View profile', 'Profil ansehen'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: JuzzioGlassTokens.onGlow, fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// v1.2.4: tepkileri emojiye göre gruplar (en çok verilen önce). Kullanıcı başına TEK tepki
/// olduğu için her kullanıcı yalnız bir grupta yer alır. Saf; test edilir.
Map<String, List<String>> juzzioGroupReactions(Map<String, String> byUser) {
  final out = <String, List<String>>{};
  byUser.forEach((uid, emoji) {
    if (emoji.isEmpty) return;
    (out[emoji] ??= <String>[]).add(uid);
  });
  final sorted = out.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
  return {for (final e in sorted) e.key: e.value};
}

/// v1.2.4: mesajdaki iletilmiş gönderi/hikâye bağlantısı → ('post' | 'story', kimlik). Yoksa null.
(String, String)? juzzioSharedRef(String text) {
  final m = RegExp(r'juzzio://(post|story)/([0-9a-fA-F-]{8,64})').firstMatch(text);
  if (m == null) return null;
  return (m.group(1)!, m.group(2)!);
}
