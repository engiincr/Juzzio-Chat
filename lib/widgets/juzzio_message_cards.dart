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
  const JuzzioReactionBadge({super.key, required this.messageId, required this.counts, this.popKeys = const <String>{}});

  final String messageId;
  final Map<String, int> counts;

  /// '<mesajId>|<emoji>' — yalnız yeni eklenen tepki yaylı belirir
  final Set<String> popKeys;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final shown = entries.take(4).toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
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
                  child: Text(e.key, style: juzzioEmojiStyle(19), textScaler: TextScaler.noScaling),
                ),
              ),
            if (total > 1) ...[
              const SizedBox(width: 4),
              JuzzioBounceOnChange(
                value: total,
                child: Text(
                  '$total',
                  style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
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
    return JuzzioCardShell(
      isMe: widget.isMe,
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.contact_page_rounded, size: 14, color: ink.secondary),
              const SizedBox(width: 5),
              Text(app.trEn('Kişi kartı', 'Contact', 'Kontakt'),
                  style: TextStyle(color: ink.secondary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              JuzzioUserAvatar(imageUrl: p?.avatarUrl, displayName: name, radius: 24),
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
              if (_loading) const SizedBox(width: 18, height: 18, child: JuzzioOrbitLoader(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          JuzzioCardButton(
            isMe: widget.isMe,
            icon: Icons.person_search_rounded,
            label: app.trEn('Profili Görüntüle', 'View profile', 'Profil ansehen'),
            onTap: _open,
          ),
        ],
      ),
    );
  }
}
