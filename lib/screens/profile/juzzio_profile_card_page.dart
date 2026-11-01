// =============================================================================
// JUZZIO v0.4.0 — Çift yüzlü profil kartı
//  Ön yüz: büyük profil fotoğrafı, @kullanıcıadı etiketi, ad, biyografi, müzik hapı
//  Arka yüz: özelleştirilebilir arka plan üzerinde QR kod
//  Kalem menüsü: Profili düzenle / Arka planı değiştir / Arka planı kaldır / Rengi değiştir
//  Alt düğmeler: Paylaş / Gönder / Davet et / Bağlantıyı kopyala
// =============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/native_bridge.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../services/juzzio_features_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/profile_extras.dart';

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

/// Kart renk seçenekleri (#RRGGBB)
const List<String> kJuzzioCardColors = [
  '#2563EB', '#7C3AED', '#DB2777', '#0891B2', '#16A34A', '#0D9488', '#0F172A', '#4338CA',
];

Color _hex(String hex, Color fallback) {
  final clean = hex.replaceAll('#', '').toUpperCase();
  final v = int.tryParse(clean, radix: 16);
  if (clean.length != 6 || v == null) return fallback;
  // Eski sürümlerde seçilmiş turuncu / amber kart renkleri artık cam mavisine çevrilir
  if (clean == 'EA580C' || clean == 'F59E0B' || clean == 'F97316') return const Color(0xFF0891B2);
  return Color(0xFF000000 | v);
}

class JuzzioProfileCardPage extends StatefulWidget {
  final JuzzioUserProfile profile;
  final JuzzioUserProfile currentUser;
  final bool isOwn;
  final Future<void> Function()? onEditProfile;

  const JuzzioProfileCardPage({
    super.key,
    required this.profile,
    required this.currentUser,
    required this.isOwn,
    this.onEditProfile,
  });

  @override
  State<JuzzioProfileCardPage> createState() => _JuzzioProfileCardPageState();
}

class _JuzzioProfileCardPageState extends State<JuzzioProfileCardPage> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late String _color = widget.profile.cardBgColor;
  late String _bgUrl = widget.profile.cardBgUrl;
  bool _busy = false;

  String get _link => JuzzioNative.profileLink(widget.profile.username);

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_flip.isAnimating) return;
    if (_flip.value < 0.5) {
      _flip.forward();
    } else {
      _flip.reverse();
    }
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveCard({String? color, String? bgUrl}) async {
    setState(() => _busy = true);
    try {
      await JuzzioFeaturesService.instance.updateProfileCard(cardBgColor: color, cardBgUrl: bgUrl);
      setState(() {
        if (color != null) _color = color;
        if (bgUrl != null) _bgUrl = bgUrl;
      });
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeBackground() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final url = await SupabaseService.instance.uploadPublicImage(File(picked.path), prefix: 'card');
      await _saveCard(bgUrl: url);
      if (_flip.value < 0.5) _flip.forward();
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickColor() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: JuzzioAppController.instance.isDark ? JuzzioColors.surface141519 : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_l('Kart rengi', 'Card color', 'Kartenfarbe'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final c in kJuzzioCardColors)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, c),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _hex(c, JuzzioColors.blue600),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) await _saveCard(color: chosen);
  }

  Future<void> _openEditMenu() async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width - 260, 90, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      items: [
        if (widget.onEditProfile != null)
          _menuItem('edit', _l('Profili düzenle', 'Edit profile', 'Profil bearbeiten'), Icons.account_circle_outlined),
        _menuItem('bg', _l('Arka planı değiştir', 'Change background', 'Hintergrund ändern'), Icons.image_outlined),
        if (_bgUrl.isNotEmpty)
          _menuItem('bg_remove', _l('Arka planı kaldır', 'Remove background', 'Hintergrund entfernen'), Icons.restart_alt_rounded),
        _menuItem('color', _l('Rengi değiştir', 'Change color', 'Farbe ändern'), Icons.colorize_rounded),
      ],
    );
    switch (value) {
      case 'edit':
        await widget.onEditProfile?.call();
        break;
      case 'bg':
        await _changeBackground();
        break;
      case 'bg_remove':
        await _saveCard(bgUrl: '');
        break;
      case 'color':
        await _pickColor();
        break;
    }
  }

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Icon(icon, size: 20),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final ok = await JuzzioNative.shareText(
      _l('Juzzio\'da beni ekle: $_link', 'Add me on Juzzio: $_link', 'Füge mich auf Juzzio hinzu: $_link'),
      title: _l('Profili paylaş', 'Share profile', 'Profil teilen'),
    );
    if (!ok) await _copy();
  }

  Future<void> _invite() async {
    final ok = await JuzzioNative.shareText(
      _l(
        'Juzzio\'yu dene! Canlı çeviriyle her dilde sohbet et ve görüntülü konuş. Beni ekle: $_link',
        'Try Juzzio! Chat and video call in any language with live translation. Add me: $_link',
        'Probier Juzzio! Chatte und telefoniere per Video in jeder Sprache mit Live-Übersetzung. Füge mich hinzu: $_link',
      ),
      title: _l('Davet et', 'Invite', 'Einladen'),
    );
    if (!ok) await _copy();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link));
    _snack(_l('Bağlantı kopyalandı.', 'Link copied.', 'Link kopiert.'));
  }

  Future<void> _sendToFriend() async {
    final svc = SupabaseService.instance;
    final friends = await svc.fetchAcceptedFriendProfiles();
    if (!mounted) return;
    if (friends.isEmpty) {
      _snack(_l('Önce bir arkadaş ekleyin.', 'Add a friend first.', 'Füge zuerst einen Freund hinzu.'));
      return;
    }
    final target = await showModalBottomSheet<JuzzioUserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuzzioAppController.instance.isDark ? JuzzioColors.surface141519 : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Text(_l('Gönder', 'Send', 'Senden'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in friends)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundImage: (f.avatarUrl ?? '').startsWith('http') ? NetworkImage(f.avatarUrl!) : null,
                          child: (f.avatarUrl ?? '').startsWith('http') ? null : const Icon(Icons.person_rounded),
                        ),
                        title: Text(f.displayName),
                        subtitle: Text('@${f.username}'),
                        trailing: const Icon(Icons.send_rounded),
                        onTap: () => Navigator.pop(ctx, f),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    try {
      final roomId = await svc.getOrCreateDirectRoomId(target.id);
      await svc.sendTextMessage(
        text: '${widget.profile.displayName} (@${widget.profile.username}) • $_link',
        targetRoomId: roomId,
        receiverId: target.id,
      );
      _snack(_l('Gönderildi.', 'Sent.', 'Gesendet.'));
    } catch (e) {
      _snack(svc.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _hex(_color, JuzzioColors.blue600);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cardColor.withValues(alpha: 0.92), JuzzioColors.ink.withValues(alpha: 0.96)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ),
                  if (widget.isOwn)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 25),
                      onPressed: _openEditMenu,
                    ),
                ],
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _toggleFlip,
                    child: AnimatedBuilder(
                      animation: _flip,
                      builder: (_, __) {
                        final angle = _flip.value * math.pi;
                        final showBack = angle > math.pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateY(angle),
                          child: showBack
                              ? Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  child: _buildBack(cardColor),
                                )
                              : _buildFront(),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Text(
                _l('Kartı çevirmek için dokunun', 'Tap the card to flip it', 'Tippe auf die Karte, um sie umzudrehen'),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundAction(Icons.ios_share_rounded, _l('Paylaş', 'Share', 'Teilen'), _share),
                    _roundAction(Icons.send_rounded, _l('Gönder', 'Send', 'Senden'), _sendToFriend),
                    _roundAction(Icons.contact_page_outlined, _l('Davet et', 'Invite', 'Einladen'), _invite),
                    _roundAction(Icons.link_rounded, _l('Bağlantıyı kopyala', 'Copy link', 'Link kopieren'), _copy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundAction(IconData icon, String label, Future<void> Function() onTap) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          InkResponse(
            onTap: () => onTap(),
            radius: 32,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15),
          ),
        ],
      ),
    );
  }

  Widget _usernameSticker({bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? JuzzioColors.ink : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alternate_email_rounded, size: 18, color: dark ? Colors.white : JuzzioColors.ink),
          const SizedBox(width: 3),
          Text(
            widget.profile.username.toUpperCase(),
            style: TextStyle(
              fontFamily: JuzzioConfig.fontRegularBold,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: 0.4,
              color: dark ? Colors.white : JuzzioColors.ink,
            ),
          ),
          if (widget.profile.isVerified) ...[
            const SizedBox(width: 4),
            const JuzzioVerifiedTick(size: 17),
          ],
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child, Color? color, DecorationImage? image}) {
    final w = math.min(MediaQuery.of(context).size.width * 0.82, 360.0);
    return Container(
      width: w,
      height: w * 1.32,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        image: image,
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 30, offset: Offset(0, 14))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildFront() {
    final p = widget.profile;
    final url = p.avatarUrl ?? '';
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Positioned.fill(
                      child: ClipOval(
                        child: url.startsWith('http')
                            ? Image.network(url, fit: BoxFit.cover)
                            : Container(
                                color: JuzzioColors.slate200,
                                child: const Icon(Icons.person_rounded, size: 90, color: JuzzioColors.slate400),
                              ),
                      ),
                    ),
                    Positioned(bottom: -14, child: _usernameSticker()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(
              p.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: JuzzioColors.ink),
            ),
            if (p.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                p.bio.trim(),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: JuzzioColors.slate700, fontSize: 13.5, height: 1.3),
              ),
            ],
            const SizedBox(height: 12),
            if (p.hasProfileMusic)
              JuzzioMusicPill(
                videoId: p.musicVideoId,
                startSec: p.musicStartSec,
                title: p.musicTitle,
                artist: p.musicArtist,
                coverUrl: p.musicCoverUrl,
                musicUrl: p.musicUrl,
                isDark: false,
                maxWidth: 230,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(Color cardColor) {
    final image = _bgUrl.isNotEmpty ? DecorationImage(image: NetworkImage(_bgUrl), fit: BoxFit.cover) : null;
    return _cardShell(
      color: cardColor,
      image: image,
      child: Stack(
        children: [
          if (image == null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cardColor, Color.lerp(cardColor, JuzzioColors.ink, 0.45) ?? cardColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18)],
                  ),
                  child: QrImageView(
                    data: _link,
                    version: QrVersions.auto,
                    size: 190,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: cardColor),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: JuzzioColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _usernameSticker(dark: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
