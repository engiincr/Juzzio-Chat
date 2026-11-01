// =============================================================================
// JUZZIO v0.5.0 — Özgün "Kimlik Kartı" profil sayfası (nötr cam)
//  • Ortalanmış büyük profil fotoğrafı, altında ad + mavi tik ve @kullanıcıadı
//    (uzun adlar kesilmez: iki satıra iner / sığacak kadar küçülür)
//  • Biyografi, web sitesi, cam müzik kapsülü, rozetler
//  • Sayaçlar tek bir cam kapsülde (Gönderi · Arkadaş · Ekleyen)
//  • Kendi profilin: Profili düzenle / Profili paylaş; başkası: Arkadaş ekle / Mesaj
//  • Gönderiler / Kaydedilenler: yuvarlatılmış cam karolar (yazı paylaşımları dahil)
// Hem alttaki "Profil" sekmesinde hem başka kullanıcıların profilinde kullanılır.
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/config.dart';
import '../../core/native_bridge.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../models/social_models.dart';
import '../../services/juzzio_features_service.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/profile_extras.dart';
import '../../widgets/social_common_widgets.dart';
import '../social/social_screens.dart';
import 'juzzio_profile_card_page.dart';

String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

class JuzzioProfileView extends StatefulWidget {
  final String userId;
  final JuzzioUserProfile currentUser;

  /// Alt sekme olarak gösteriliyorsa geri tuşu yerine oluştur / bildirim / menü görünür.
  final bool asHomeTab;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onCreate;
  final VoidCallback? onOpenNotifications;
  final Future<JuzzioUserProfile?> Function()? onEditProfile;
  final Future<void> Function()? onChangeAvatar;
  final ValueChanged<JuzzioUserProfile>? onStartChat;
  final void Function(JuzzioUserProfile target, bool isVideo)? onStartCall;

  /// Değiştiğinde profil yeniden yüklenir (ör. profil düzenlendikten sonra).
  final int refreshToken;

  const JuzzioProfileView({
    super.key,
    required this.userId,
    required this.currentUser,
    this.asHomeTab = false,
    this.onBack,
    this.onOpenSettings,
    this.onCreate,
    this.onOpenNotifications,
    this.onEditProfile,
    this.onChangeAvatar,
    this.onStartChat,
    this.onStartCall,
    this.refreshToken = 0,
  });

  @override
  State<JuzzioProfileView> createState() => _JuzzioProfileViewState();
}

class _JuzzioProfileViewState extends State<JuzzioProfileView> {
  JuzzioUserProfile? _profile;
  JuzzioProfileSocialCounts _counts = const JuzzioProfileSocialCounts();
  JuzzioRelationship _relation = const JuzzioRelationship();
  List<JuzzioPost> _posts = const [];
  List<JuzzioPost> _saved = const [];
  int _tab = 0; // 0 gönderiler, 1 kaydedilenler (yalnızca kendi profilinde)
  bool _loading = true;
  bool _busy = false;

  bool get _isOwn => widget.userId == widget.currentUser.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JuzzioProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken || oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final social = JuzzioSocialService.instance;
    try {
      final results = await Future.wait<Object?>([
        SupabaseService.instance.fetchUserProfile(widget.userId),
        social.fetchProfileSocialCounts(widget.userId),
        social.fetchFeedPosts(authorId: widget.userId, limit: 90),
        _isOwn ? social.fetchMySavedPosts(limit: 90) : Future<List<JuzzioPost>>.value(const []),
        _isOwn
            ? Future<JuzzioRelationship>.value(const JuzzioRelationship())
            : JuzzioFeaturesService.instance.fetchRelationship(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = (results[0] as JuzzioUserProfile?) ?? (_isOwn ? widget.currentUser : null);
        _counts = results[1] as JuzzioProfileSocialCounts;
        _posts = results[2] as List<JuzzioPost>;
        _saved = results[3] as List<JuzzioPost>;
        _relation = results[4] as JuzzioRelationship;
        _loading = false;
      });
      if (_isOwn) {
        // Arkadaş sayısı kendi profilde de gösterilir
        final rel = await JuzzioFeaturesService.instance.fetchRelationship(widget.userId);
        if (mounted) setState(() => _relation = rel);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile ??= _isOwn ? widget.currentUser : null;
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------
  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onFriendButton() async {
    final prof = _profile;
    if (prof == null || _busy) return;
    if (_relation.friendStatus == 'friends' || _relation.friendStatus == 'outgoing') {
      final remove = await _confirmSheet(
        title: '@${prof.username}',
        actionLabel: _relation.friendStatus == 'friends'
            ? _l('Arkadaşlıktan çıkar', 'Remove friend', 'Freund entfernen')
            : _l('İsteği geri çek', 'Cancel request', 'Anfrage zurückziehen'),
      );
      if (remove != true) return;
      setState(() => _busy = true);
      try {
        await SupabaseService.instance.removeFriend(prof.id);
        try {
          await JuzzioSocialService.instance.unfollowOrCancelRequest(targetUserId: prof.id);
        } catch (_) {}
      } catch (e) {
        _snack(SupabaseService.instance.friendlyError(e));
      }
    } else {
      setState(() => _busy = true);
      try {
        final res = await JuzzioFeaturesService.instance.addFriend(prof.id);
        if (res == 'friends') {
          _snack(_l('Artık arkadaşsınız 🎉', 'You are now friends 🎉', 'Ihr seid jetzt befreundet 🎉'));
        } else if (_relation.isPrivate) {
          _snack(_l('Arkadaşlık isteği gönderildi.', 'Friend request sent.', 'Freundschaftsanfrage gesendet.'));
        } else {
          _snack(_l(
            'Eklendi. Karşılıklı arkadaş olmak için onun da sizi eklemesi gerekir.',
            'Added. They also need to add you to become mutual friends.',
            'Hinzugefügt. Für eine gegenseitige Freundschaft muss die Person dich auch hinzufügen.',
          ));
        }
      } catch (e) {
        _snack(SupabaseService.instance.friendlyError(e));
      }
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<bool?> _confirmSheet({required String title, required String actionLabel}) {
    final isDark = JuzzioAppController.instance.isDark;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: JuzzioGlassTokens.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isDark ? Colors.white : JuzzioColors.ink)),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: JuzzioColors.red500),
              title: Text(actionLabel, style: const TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(JuzzioAppController.instance.t('common_cancel')),
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _openMoreMenu() async {
    final prof = _profile;
    if (prof == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: JuzzioGlassTokens.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _sheetTile(ctx, 'card', Icons.qr_code_2_rounded, _l('Profil kartı', 'Profile card', 'Profilkarte')),
            _sheetTile(ctx, 'copy', Icons.link_rounded, _l('Profil bağlantısını kopyala', 'Copy profile link', 'Profillink kopieren')),
            _sheetTile(
              ctx,
              'mute',
              _counts.isMutedByMe ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              _counts.isMutedByMe
                  ? _l('Sessizden çıkar', 'Unmute', 'Stummschaltung aufheben')
                  : _l('Sessize al', 'Mute', 'Stummschalten'),
            ),
            _sheetTile(ctx, 'report', Icons.flag_outlined, _l('Şikâyet et', 'Report', 'Melden')),
            _sheetTile(ctx, 'block', Icons.block_rounded, _l('Engelle', 'Block', 'Blockieren'), danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'card':
        _openProfileCard();
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: JuzzioNative.profileLink(prof.username)));
        _snack(_l('Bağlantı kopyalandı.', 'Link copied.', 'Link kopiert.'));
        break;
      case 'mute':
        await JuzzioSocialService.instance.toggleMuteUser(prof.id, mute: !_counts.isMutedByMe);
        await _load();
        break;
      case 'report':
        await showJuzzioReportModalSheet(
          context: context,
          targetType: 'user',
          targetId: prof.id,
          targetOwnerId: prof.id,
        );
        break;
      case 'block':
        try {
          await JuzzioSocialService.instance.blockUser(targetUser: prof);
          if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        } catch (e) {
          _snack(SupabaseService.instance.friendlyError(e));
        }
        break;
    }
  }

  Widget _sheetTile(BuildContext ctx, String value, IconData icon, String label, {bool danger = false}) {
    final color = danger ? JuzzioColors.red500 : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  void _openProfileCard() {
    final prof = _profile;
    if (prof == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => JuzzioProfileCardPage(
          profile: prof,
          isOwn: _isOwn,
          currentUser: widget.currentUser,
          onEditProfile: widget.onEditProfile == null
              ? null
              : () async {
                  final updated = await widget.onEditProfile!();
                  if (updated != null) await _load();
                },
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) => _load());
  }

  void _openAvatarZoom() {
    final prof = _profile;
    if (prof == null) return;
    if (!_isOwn && !prof.profileZoomEnabled) return;
    final isDark = JuzzioAppController.instance.isDark;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'avatar',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        final size = MediaQuery.of(ctx).size.width * 0.72;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Hero(
                      tag: 'juzzio_avatar_${prof.id}',
                      child: InteractiveViewer(
                        maxScale: 4,
                        child: ClipOval(
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: _avatarImage(prof, size / 2),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          prof.displayName,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        if (prof.isVerified) ...[
                          const SizedBox(width: 6),
                          const JuzzioVerifiedTick(size: 20),
                        ],
                      ],
                    ),
                    Text('@${prof.username}', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _glassAction(
                          icon: Icons.qr_code_2_rounded,
                          label: _l('Profil kartı', 'Profile card', 'Profilkarte'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openProfileCard();
                          },
                        ),
                        if (_isOwn && widget.onChangeAvatar != null)
                          _glassAction(
                            icon: Icons.photo_camera_rounded,
                            label: _l('Fotoğrafı değiştir', 'Change photo', 'Foto ändern'),
                            onTap: () async {
                              Navigator.of(ctx).pop();
                              await widget.onChangeAvatar!();
                              await _load();
                            },
                          ),
                        if (_isOwn)
                          _glassAction(
                            icon: prof.profileZoomEnabled ? Icons.zoom_out_map_rounded : Icons.block_rounded,
                            label: prof.profileZoomEnabled
                                ? _l('Yakınlaştırma açık', 'Zoom on', 'Zoom an')
                                : _l('Başkalarına kapalı', 'Off for others', 'Für andere aus'),
                            onTap: () async {
                              Navigator.of(ctx).pop();
                              await _toggleZoom();
                            },
                          ),
                      ],
                    ),
                    if (isDark) const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleZoom() async {
    final prof = _profile;
    if (prof == null) return;
    final next = !prof.profileZoomEnabled;
    try {
      await JuzzioFeaturesService.instance.setProfileZoomEnabled(next);
      setState(() => _profile = prof.copyWith(profileZoomEnabled: next));
      _snack(next
          ? _l('Profil fotoğrafı yakınlaştırma açıldı.', 'Profile photo zoom turned on.', 'Profilfoto-Zoom aktiviert.')
          : _l('Başkaları artık profil fotoğrafınızı yakınlaştıramaz.', 'Others can no longer zoom your profile photo.',
              'Andere können dein Profilfoto nicht mehr vergrößern.'));
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e));
    }
  }

  Widget _glassAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _avatarImage(JuzzioUserProfile prof, double radius) {
    final url = prof.avatarUrl ?? '';
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsAvatar(prof, radius));
    }
    return _initialsAvatar(prof, radius);
  }

  Widget _initialsAvatar(JuzzioUserProfile prof, double radius) {
    final name = prof.displayName.trim();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [JuzzioColors.blue600, JuzzioColors.violet500]),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'J' : String.fromCharCode(name.runes.first).toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _openFriends() async {
    if (widget.onStartChat == null || widget.onStartCall == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JuzzioFriendsAndRelationsPage(
          currentUser: widget.currentUser,
          onOpenProfile: (id) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => JuzzioUserProfilePage(
                userId: id,
                currentUser: widget.currentUser,
                onStartDirectChat: widget.onStartChat,
                onStartCall: widget.onStartCall,
              ),
            ),
          ),
          onStartChat: widget.onStartChat!,
          onStartCall: widget.onStartCall!,
        ),
      ),
    );
  }

  Future<void> _openPost(JuzzioPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JuzzioPostDetailAndCommentsPage(
          postId: post.id,
          initialPost: post,
          currentUser: widget.currentUser,
        ),
      ),
    );
    await _load();
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final fg = isDark ? Colors.white : JuzzioColors.ink;
    final prof = _profile;

    return DecoratedBox(
      decoration: JuzzioGlassTokens.backdrop,
      child: Column(
        children: [
          _buildTopBar(fg, prof),
          Expanded(
            child: _loading && prof == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                : prof == null || _relation.blocked || _counts.isBlockedBetween
                    ? JuzzioEmptyStateView(
                        icon: Icons.person_off_outlined,
                        title: _l('Profil görüntülenemiyor', 'Profile unavailable', 'Profil nicht verfügbar'),
                        subtitle: _l('Bu kullanıcıya şu anda ulaşılamıyor.', 'This user is currently unavailable.',
                            'Dieser Nutzer ist derzeit nicht verfügbar.'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(child: _buildHeader(prof, fg, isDark)),
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _TabsHeader(
                                child: _buildTabs(fg, isDark, JuzzioGlassTokens.surface),
                              ),
                            ),
                            ..._buildGrid(prof, isDark),
                            const SliverToBoxAdapter(child: SizedBox(height: 40)),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Color fg, JuzzioUserProfile? prof) {
    // Kullanıcı adı artık kimlik kartında tam görünür; üst çubuk yalnızca eylemleri taşır.
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 12),
            if (!widget.asHomeTab)
              JuzzioGlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                size: 40,
                onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
              )
            else
              Text(
                _l('Profil', 'Profile', 'Profil'),
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: fg,
                  letterSpacing: -0.4,
                ),
              ),
            const Spacer(),
            if (_isOwn) ...[
              if (widget.onCreate != null) ...[
                JuzzioGlassIconButton(
                  icon: Icons.add_rounded,
                  size: 40,
                  tooltip: _l('Oluştur', 'Create', 'Erstellen'),
                  onTap: widget.onCreate,
                ),
                const SizedBox(width: 8),
              ],
              if (widget.onOpenNotifications != null) ...[
                JuzzioGlassIconButton(
                  icon: Icons.notifications_none_rounded,
                  size: 40,
                  tooltip: _l('Bildirimler', 'Notifications', 'Benachrichtigungen'),
                  onTap: widget.onOpenNotifications,
                ),
                const SizedBox(width: 8),
              ],
              if (widget.onOpenSettings != null)
                JuzzioGlassIconButton(
                  icon: Icons.settings_outlined,
                  size: 40,
                  tooltip: _l('Ayarlar', 'Settings', 'Einstellungen'),
                  onTap: widget.onOpenSettings,
                ),
            ] else
              JuzzioGlassIconButton(icon: Icons.more_horiz_rounded, size: 40, onTap: _openMoreMenu),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(JuzzioUserProfile prof, Color fg, bool isDark) {
    final secondary = isDark ? JuzzioGlassTokens.textSecondary : JuzzioColors.slate600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: JuzzioGlass(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _openAvatarZoom,
            onLongPress: _isOwn && widget.onChangeAvatar != null
                ? () async {
                    await widget.onChangeAvatar!();
                    await _load();
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Hero(
                tag: 'juzzio_avatar_${prof.id}',
                child: ClipOval(
                  child: SizedBox(width: 108, height: 108, child: _avatarImage(prof, 54)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Ad: kesilmez, gerekirse iki satıra iner
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  prof.displayName.trim().isEmpty ? prof.username : prof.displayName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    height: 1.15,
                    letterSpacing: -0.3,
                    color: fg,
                  ),
                ),
              ),
              if (prof.isVerified) ...[
                const SizedBox(width: 5),
                const JuzzioVerifiedTick(size: 19),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Kullanıcı adı: tek satıra sığacak kadar küçülür (asla kesilmez)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (prof.isPrivateAccount) ...[
                Icon(Icons.lock_outline_rounded, size: 14, color: secondary),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '@${prof.username}',
                    maxLines: 1,
                    style: TextStyle(color: secondary, fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          // Konuştuğu dil (Juzzio kimliği: iletişim ve dil)
          Builder(builder: (_) {
            final code = prof.preferredLang.trim().toLowerCase();
            final match = kJuzzioSupportedLanguages.where((l) => l.code == code);
            if (code.isEmpty) return const SizedBox.shrink();
            final label = match.isEmpty ? code.toUpperCase() : '${match.first.flag}  ${match.first.nativeName}';
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: isDark ? JuzzioGlassTokens.border : JuzzioColors.slate200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.record_voice_over_rounded, size: 15, color: secondary),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
          // Sayaçlar: tek cam kapsül
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? JuzzioGlassTokens.border : JuzzioColors.slate200),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: _stat(fg, secondary, _counts.postsCount, _l('gönderi', 'posts', 'Beiträge'))),
                  VerticalDivider(width: 1, color: isDark ? JuzzioGlassTokens.border : JuzzioColors.slate200),
                  Expanded(
                    child: _stat(fg, secondary, _relation.friendCount, _l('arkadaş', 'friends', 'Freunde'),
                        onTap: _openFriends),
                  ),
                  if (_isOwn) ...[
                    VerticalDivider(width: 1, color: isDark ? JuzzioGlassTokens.border : JuzzioColors.slate200),
                    Expanded(child: _stat(fg, secondary, _counts.followersCount, _l('ekleyen', 'added you', 'hinzugefügt'))),
                  ],
                ],
              ),
            ),
          ),
          if (prof.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            const SizedBox(height: 8),
            Text(prof.bio.trim(), textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 14.5, height: 1.4)),
          ],
          if (prof.websiteUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            JuzzioWebsiteChip(url: prof.websiteUrl, isDark: isDark),
          ],
          if (prof.hasProfileMusic) ...[
            const SizedBox(height: 8),
            JuzzioMusicPill(
              videoId: prof.musicVideoId,
              startSec: prof.musicStartSec,
              title: prof.musicTitle,
              artist: prof.musicArtist,
              coverUrl: prof.musicCoverUrl,
              musicUrl: prof.musicUrl,
              isDark: isDark,
            ),
          ] else if (_isOwn) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _openMusicPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: isDark ? Colors.white24 : JuzzioColors.slate300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: fg),
                    const SizedBox(width: 4),
                    Icon(Icons.music_note_rounded, size: 15, color: fg),
                    const SizedBox(width: 4),
                    Text(_l('Müzik ekle', 'Add music', 'Musik hinzufügen'),
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          JuzzioBadgeRow(userId: prof.id, isDark: isDark, alignStart: false),
          const SizedBox(height: 14),
          _buildActionButtons(prof, fg, isDark),
        ],
        ),
      ),
    );
  }

  Future<void> _openMusicPicker() async {
    final prof = _profile;
    if (prof == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => JuzzioMusicPickerPage(
          initialUrl: prof.musicUrl,
          initialStartSec: prof.musicStartSec,
          initialTitle: prof.musicTitle,
          initialArtist: prof.musicArtist,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Widget _stat(Color fg, Color secondary, int value, String label, {VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Text(
              _compact(value),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 18, fontWeight: FontWeight.w800, color: fg),
            ),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 13, color: secondary)),
          ],
        ),
      ),
    );
  }

  String _compact(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  Widget _buildActionButtons(JuzzioUserProfile prof, Color fg, bool isDark) {
    final grey = isDark ? Colors.white.withValues(alpha: 0.10) : JuzzioColors.surfaceECEFF5;
    Widget pill(String label, VoidCallback? onTap, {Color? bg, Color? color, IconData? icon}) {
      return Expanded(
        child: SizedBox(
          height: 42,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: bg ?? grey,
              foregroundColor: color ?? fg,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isOwn) {
      return Row(
        children: [
          pill(_l('Profili düzenle', 'Edit profile', 'Profil bearbeiten'), widget.onEditProfile == null
              ? null
              : () async {
                  final updated = await widget.onEditProfile!();
                  if (updated != null) await _load();
                }),
          const SizedBox(width: 6),
          pill(_l('Profili paylaş', 'Share profile', 'Profil teilen'), _openProfileCard),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: grey,
                shape: const CircleBorder(),
              ),
              padding: EdgeInsets.zero,
              tooltip: _l('Arkadaşlar', 'Friends', 'Freunde'),
              icon: Icon(Icons.person_add_alt_1_rounded, size: 18, color: fg),
              onPressed: _openFriends,
            ),
          ),
        ],
      );
    }

    final status = _relation.friendStatus;
    final String friendLabel;
    IconData? friendIcon;
    Color? friendBg;
    Color? friendFg;
    switch (status) {
      case 'friends':
        friendLabel = _l('Arkadaşsınız', 'Friends', 'Befreundet');
        friendIcon = Icons.how_to_reg_rounded;
        break;
      case 'outgoing':
        friendLabel = _relation.isPrivate
            ? _l('İstek gönderildi', 'Requested', 'Angefragt')
            : _l('Eklendi', 'Added', 'Hinzugefügt');
        friendIcon = Icons.schedule_rounded;
        break;
      case 'incoming':
        friendLabel = _l('Geri ekle', 'Add back', 'Zurück hinzufügen');
        friendBg = Colors.white;
        friendFg = const Color(0xFF111113);
        break;
      default:
        friendLabel = _l('Arkadaş ekle', 'Add friend', 'Freund hinzufügen');
        friendIcon = Icons.person_add_alt_1_rounded;
        friendBg = Colors.white;
        friendFg = const Color(0xFF111113);
    }
    return Row(
      children: [
        pill(friendLabel, _busy ? null : _onFriendButton, bg: friendBg, color: friendFg, icon: friendIcon),
        const SizedBox(width: 6),
        pill(
          _l('Mesaj', 'Message', 'Nachricht'),
          widget.onStartChat == null ? null : () => widget.onStartChat!(prof),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          height: 42,
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: grey,
              shape: const CircleBorder(),
            ),
            padding: EdgeInsets.zero,
            tooltip: _l('Profil kartı', 'Profile card', 'Profilkarte'),
            icon: Icon(Icons.qr_code_2_rounded, size: 18, color: fg),
            onPressed: _openProfileCard,
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(Color fg, bool isDark, Color bg) {
    final labels = <String>[
      _l('Gönderiler', 'Posts', 'Beiträge'),
      if (_isOwn) _l('Kaydedilenler', 'Saved', 'Gespeichert'),
    ];
    // v0.8.0: siyah şerit kaldırıldı — sekmeler zemin üstünde cam
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = _tab == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _tab = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? JuzzioGlassTokens.surfaceStrong : JuzzioGlassTokens.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: active ? JuzzioGlassTokens.borderStrong : JuzzioGlassTokens.border),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: active ? fg : fg.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    )));
  }

  List<Widget> _buildGrid(JuzzioUserProfile prof, bool isDark) {
    final hiddenPrivate = !_isOwn && prof.isPrivateAccount && !_relation.isFriend;
    if (hiddenPrivate) {
      return [
        SliverToBoxAdapter(
          child: JuzzioEmptyStateView(
            icon: Icons.lock_outline_rounded,
            title: _l('Bu hesap gizli', 'This account is private', 'Dieses Konto ist privat'),
            subtitle: _l(
              'Fotoğraf ve videolarını görmek için arkadaş ekleyin.',
              'Add them as a friend to see their photos and videos.',
              'Füge die Person als Freund hinzu, um Fotos und Videos zu sehen.',
            ),
          ),
        ),
      ];
    }
    final isSavedTab = _isOwn && _tab == 1;
    final list = isSavedTab ? _saved : _posts;
    if (list.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: JuzzioEmptyStateView(
            icon: isSavedTab ? Icons.bookmark_border_rounded : Icons.photo_camera_outlined,
            title: isSavedTab
                ? _l('Kaydedilen gönderi yok', 'No saved posts', 'Keine gespeicherten Beiträge')
                : _l('Henüz gönderi yok', 'No posts yet', 'Noch keine Beiträge'),
            subtitle: _isOwn && !isSavedTab
                ? _l('Paylaştığın fotoğraf ve videolar burada görünür.', 'Photos and videos you share appear here.',
                    'Fotos und Videos, die du teilst, erscheinen hier.')
                : '',
            actionLabel: _isOwn && !isSavedTab && widget.onCreate != null ? _l('Paylaş', 'Share', 'Teilen') : null,
            onAction: _isOwn && !isSavedTab ? widget.onCreate : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 3 / 4,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final post = list[i];
              final url = post.coverUrl ?? post.primaryMediaUrl ?? '';
              // v0.8.1: sıvı cam karo — seçili temanın aurorası arkadan görünür
              final tileBg = JuzzioGlassTokens.surfaceStrong;
              return GestureDetector(
                onTap: () => _openPost(post),
                child: CustomPaint(
                  foregroundPainter: JuzzioGlassBorderPainter(radius: 16, dark: isDark),
                  child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (post.isText)
                        Container(
                          decoration: BoxDecoration(color: tileBg, gradient: null),
                          foregroundDecoration: BoxDecoration(gradient: JuzzioGlassTokens.sheen),
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            post.caption,
                            maxLines: 7,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: JuzzioGlassTokens.textPrimary,
                              fontSize: 12.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (url.startsWith('http') && !JuzzioPost.looksLikeVideoUrl(url))
                        Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: tileBg))
                      else
                        ColoredBox(
                          color: tileBg,
                          child: Icon(post.isVideo ? Icons.play_arrow_rounded : Icons.image_outlined, color: JuzzioGlassTokens.textSecondary),
                        ),
                      if (post.isVideo)
                        const Positioned(
                          top: 7,
                          right: 7,
                          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 6)]),
                        )
                      else if (post.mediaUrls.length > 1)
                        const Positioned(
                          top: 7,
                          right: 7,
                          child: Icon(Icons.collections_rounded, color: Colors.white, size: 18, shadows: [Shadow(blurRadius: 6)]),
                        ),
                    ],
                  ),
                ),
                ),
              );
            },
            childCount: list.length,
          ),
        ),
      ),
    ];
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabsHeader({required this.child});

  @override
  double get minExtent => 46;
  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) => true;
}
