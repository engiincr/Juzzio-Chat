// =============================================================================
// JUZZIO v0.3.0 — Grup üyeleri ve roller
//  • Yönetici (tek kişi): moderatör atar/alır, üye çıkarır, yöneticiliği devreder
//  • Moderatör: normal üyeleri susturur
//  • Rol yalnızca grup içinde görünür (profilde "Yönetici" rozeti YOKTUR)
// v1.2.6
//  • Grup ve kanal logosu: yönetici/moderatör başlıktaki fotoğrafa dokunup galeriden ya da
//    kameradan logo koyar veya kaldırır (sunucu denetimi: set_room_avatar).
//  • Juzzio Community resmî duyuru kanalıdır: logo sabit (uygulama logosu), üyeler
//    birbirini göremez (liste yalnız yetkiliye açık), tek yetkili @tugkancr.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/content_filter.dart';
import '../core/juzzio_community.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';
import 'chat_notification_prefs.dart';
import 'chat_lock_ui.dart';
import '../screens/saved_messages_page.dart';
import 'juzzio_motion.dart';
import 'juzzio_space_kit.dart' show JuzzioSpacePhoto;

Future<void> showJuzzioGroupManagementSheet(
  BuildContext context, {
  required String roomId,
  required String groupTitle,
  String groupType = 'general',
  String groupPurpose = '',
  String? avatarUrl,
  bool isCommunity = false,
  bool isChannel = false,
  VoidCallback? onChanged,
}) {
  return showJuzzioSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioAppController.instance.isDark ? JuzzioColors.surface141519 : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _GroupManagementSheet(
      roomId: roomId,
      groupTitle: groupTitle,
      groupType: groupType,
      groupPurpose: groupPurpose,
      avatarUrl: avatarUrl,
      isCommunity: isCommunity,
      isChannel: isChannel || isCommunity,
      onChanged: onChanged,
    ),
  );
}

class _GroupManagementSheet extends StatefulWidget {
  final String roomId;
  final String groupTitle;
  final String groupType;
  final String groupPurpose;
  final String? avatarUrl;
  final bool isCommunity;
  final bool isChannel;
  final VoidCallback? onChanged;

  const _GroupManagementSheet({
    required this.roomId,
    required this.groupTitle,
    required this.groupType,
    required this.groupPurpose,
    this.avatarUrl,
    this.isCommunity = false,
    this.isChannel = false,
    this.onChanged,
  });

  @override
  State<_GroupManagementSheet> createState() => _GroupManagementSheetState();
}

class _GroupManagementSheetState extends State<_GroupManagementSheet> {
  final JuzzioFeaturesService _f = JuzzioFeaturesService.instance;
  List<JuzzioGroupMember> _members = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _avatar;

  String get _myId => SupabaseService.instance.currentUserId ?? '';
  String get _myRole => _members.firstWhere((m) => m.userId == _myId,
      orElse: () => const JuzzioGroupMember(userId: '', username: '', displayName: '')).role;
  bool get _iAmOwner => _myRole == 'owner';
  bool get _iAmStaff => _myRole == 'owner' || _myRole == 'moderator';

  @override
  void initState() {
    super.initState();
    final a = (widget.avatarUrl ?? '').trim();
    _avatar = a.isEmpty || a.startsWith('asset:') ? null : a;
    _load();
  }

  /// Logo değiştirilebilir mi: yalnız yönetici/moderatör ve Juzzio Community DEĞİL
  bool get _canEditLogo => _iAmStaff && !widget.isCommunity;

  Future<void> _logoFlow() async {
    if (!_canEditLogo || _busy) return;
    final app = JuzzioAppController.instance;
    final pick = await showJuzzioSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                widget.isChannel
                    ? app.trEn('Kanal logosu', 'Channel logo', 'Kanallogo')
                    : app.trEn('Grup logosu', 'Group logo', 'Gruppenlogo'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(app.trEn('Tüm üyeler bu logoyu görür.', 'All members see this logo.', 'Alle Mitglieder sehen dieses Logo.')),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(app.trEn('Galeriden seç', 'Choose from gallery', 'Aus Galerie wählen')),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(app.trEn('Fotoğraf çek', 'Take a photo', 'Foto aufnehmen')),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (_avatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500),
                title: Text(app.trEn('Logoyu kaldır', 'Remove logo', 'Logo entfernen'), style: const TextStyle(color: JuzzioColors.red500)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    File? file;
    if (pick != 'remove') {
      try {
        final x = await ImagePicker().pickImage(
          source: pick == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 88,
        );
        if (x == null) return;
        file = File(x.path);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(app.trEn('Fotoğraf açılamadı. İzinleri kontrol edin.', 'The photo could not be opened. Check permissions.',
              'Das Foto konnte nicht geöffnet werden. Prüfe die Berechtigungen.')),
        ));
        return;
      }
    }
    if (!mounted) return;
    final chosen = file;
    await _act(
      () async {
        final url = await _f.setRoomAvatar(roomId: widget.roomId, file: chosen);
        if (mounted) setState(() => _avatar = url);
      },
      chosen == null
          ? app.trEn('Logo kaldırıldı.', 'Logo removed.', 'Logo entfernt.')
          : app.trEn('Logo güncellendi.', 'Logo updated.', 'Logo aktualisiert.'),
    );
  }

  Widget _logo(bool isDark) {
    final app = JuzzioAppController.instance;
    const double size = 52;
    final Widget photo = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: JuzzioSpacePhoto(
          url: widget.isCommunity ? kJuzzioLogoAvatar : _avatar,
          name: widget.groupTitle,
          size: size,
        ),
      ),
    );
    if (!_canEditLogo) return photo;
    return Semantics(
      button: true,
      label: app.trEn('Logoyu değiştir', 'Change logo', 'Logo ändern'),
      child: GestureDetector(
        onTap: _logoFlow,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            photo,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: JuzzioColors.indigo500,
                  shape: BoxShape.circle,
                  border: Border.all(color: isDark ? JuzzioColors.surface141519 : Colors.white, width: 2),
                ),
                child: _busy
                    ? const Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final list = await _f.fetchGroupMembers(widget.roomId);
      if (!mounted) return;
      setState(() {
        _members = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _act(Future<void> Function() action, String okText) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(okText), backgroundColor: JuzzioColors.emerald500));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: JuzzioColors.red500));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _muteFlow(JuzzioGroupMember m) async {
    final app = JuzzioAppController.instance;
    final minutes = await showJuzzioSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(app.t('group_mute_title').replaceAll('{name}', m.displayName))),
            for (final opt in const [15, 60, 480, 1440, 10080])
              ListTile(
                leading: const Icon(Icons.volume_off_rounded),
                title: Text(app.t('group_mute_$opt')),
                onTap: () => Navigator.pop(ctx, opt),
              ),
            if (m.isMuted)
              ListTile(
                leading: const Icon(Icons.volume_up_rounded, color: JuzzioColors.emerald500),
                title: Text(app.t('group_unmute')),
                onTap: () => Navigator.pop(ctx, 0),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    await _act(
      () => _f.muteMember(roomId: widget.roomId, userId: m.userId, minutes: minutes),
      minutes == 0 ? app.t('group_unmuted_ok') : app.t('group_muted_ok').replaceAll('{name}', m.displayName),
    );
  }

  Future<void> _confirm(String title, String body, Future<void> Function() action, String okText) async {
    final app = JuzzioAppController.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.t('common_confirm'))),
        ],
      ),
    );
    if (ok == true) await _act(action, okText);
  }

  void _memberActions(JuzzioGroupMember m) {
    final app = JuzzioAppController.instance;
    if (m.userId == _myId) return;
    final roles = !widget.isCommunity; // toplulukta tek yetkili: rol atama/devretme yok
    final canMute = _iAmOwner ? !m.isOwner : (_myRole == 'moderator' && m.role == 'member');
    showJuzzioSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('@${m.username} • ${app.t('group_role_${m.role}')}'),
            ),
            if (roles && _iAmOwner && m.role == 'member')
              ListTile(
                leading: const Icon(Icons.shield_rounded, color: JuzzioColors.indigo500),
                title: Text(app.t('group_make_moderator')),
                onTap: () {
                  Navigator.pop(ctx);
                  _act(() => _f.setMemberRole(roomId: widget.roomId, userId: m.userId, role: 'moderator'),
                      app.t('group_role_changed'));
                },
              ),
            if (roles && _iAmOwner && m.role == 'moderator')
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(app.t('group_remove_moderator')),
                onTap: () {
                  Navigator.pop(ctx);
                  _act(() => _f.setMemberRole(roomId: widget.roomId, userId: m.userId, role: 'member'),
                      app.t('group_role_changed'));
                },
              ),
            if (roles && _iAmOwner && !m.isOwner)
              ListTile(
                leading: const Icon(Icons.workspace_premium_rounded, color: JuzzioColors.amber500),
                title: Text(app.t('group_transfer_owner')),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(
                    app.t('group_transfer_owner'),
                    app.t('group_transfer_owner_confirm').replaceAll('{name}', m.displayName),
                    () => _f.setMemberRole(roomId: widget.roomId, userId: m.userId, role: 'owner'),
                    app.t('group_role_changed'),
                  );
                },
              ),
            if (canMute)
              ListTile(
                leading: Icon(m.isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                title: Text(m.isMuted ? app.t('group_mute_change') : app.t('group_mute')),
                onTap: () {
                  Navigator.pop(ctx);
                  _muteFlow(m);
                },
              ),
            if (_iAmOwner && !m.isOwner)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded, color: JuzzioColors.red500),
                title: Text(app.t('group_remove_member'), style: const TextStyle(color: JuzzioColors.red500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(
                    app.t('group_remove_member'),
                    app.t('group_remove_member_confirm').replaceAll('{name}', m.displayName),
                    () => _f.removeMember(roomId: widget.roomId, userId: m.userId),
                    app.t('group_member_removed'),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editInfo() async {
    final app = JuzzioAppController.instance;
    final titleCtrl = TextEditingController(text: widget.groupTitle);
    final purposeCtrl = TextEditingController(text: widget.groupPurpose);
    String type = kJuzzioGroupTypes.contains(widget.groupType) ? widget.groupType : 'group_work';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(app.t('group_edit_info')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, maxLength: 80, decoration: InputDecoration(labelText: app.t('group_name_label'))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in kJuzzioGroupTypes)
                      ChoiceChip(
                        label: Text(app.t('group_type_$t')),
                        selected: type == t,
                        onSelected: (_) => setLocal(() => type = t),
                      ),
                  ],
                ),
                if (type == 'custom')
                  TextField(
                    controller: purposeCtrl,
                    maxLength: 60,
                    decoration: InputDecoration(labelText: app.t('group_custom_purpose')),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.t('common_save'))),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final purpose = purposeCtrl.text.trim();
    titleCtrl.dispose();
    purposeCtrl.dispose();
    if (saved != true) return;
    if (title.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(app.t('err_group_title'))));
      return;
    }
    if (!JuzzioContentFilter.isClean(title, requireLetters: true) || !JuzzioContentFilter.isClean(purpose)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(app.t('err_inappropriate'))));
      return;
    }
    await _act(
      () => _f.updateGroupInfo(
        roomId: widget.roomId,
        title: title,
        groupType: type,
        groupPurpose: type == 'custom' ? purpose : '',
      ),
      app.t('group_info_saved'),
    );
  }

  /// Toplulukta üye listesi yalnız yetkiliye açıktır (üyeler birbirini göremez; sunucu da
  /// yalnız yetkiliyi döndürür). Diğer grup/kanallarda liste herkese görünür.
  bool get _showMemberList => !widget.isCommunity || _iAmStaff;

  Widget _communityInfo(bool isDark) {
    final app = JuzzioAppController.instance;
    final owner = _members.where((m) => m.isOwner).toList();
    final adminName = owner.isNotEmpty && owner.first.username.isNotEmpty ? owner.first.username : kJuzzioCommunityAdminUsername;
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: JuzzioColors.indigo500),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white70 : JuzzioColors.ink))),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JuzzioColors.indigo500.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(Icons.campaign_rounded, app.trEn('Yalnız sürüm güncellemesi duyuruları bu kanala düşer.',
              'Only app update announcements are posted in this channel.', 'In diesem Kanal erscheinen nur App-Update-Ankündigungen.')),
          row(Icons.visibility_off_rounded, app.trEn('Üyeler birbirini göremez; üye listesi gizlidir.',
              'Members cannot see each other; the member list is hidden.', 'Mitglieder sehen einander nicht; die Mitgliederliste ist verborgen.')),
          row(Icons.do_not_disturb_on_rounded, app.trEn('Kanala mesaj veya tepki gönderilemez.',
              'Messages and reactions cannot be sent to this channel.', 'In diesem Kanal können keine Nachrichten oder Reaktionen gesendet werden.')),
          row(Icons.verified_user_rounded, app.trEn('Kanalın tek yetkilisi: @{name}', 'The only admin of this channel: @{name}',
              'Einziger Admin dieses Kanals: @{name}').replaceAll('{name}', adminName)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(4))),
            ListTile(
              leading: _logo(isDark),
              minLeadingWidth: 52,
              title: Text(
                widget.groupTitle,
                style: TextStyle(
                  fontFamily: JuzzioConfig.fontRegularBold,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: isDark ? Colors.white : JuzzioColors.ink,
                ),
              ),
              subtitle: Text(
                widget.isCommunity
                    ? app.trEn('Resmî duyuru kanalı', 'Official announcement channel', 'Offizieller Ankündigungskanal')
                    : widget.isChannel
                        ? app.trEn('Kanal', 'Channel', 'Kanal')
                        : widget.groupType == 'custom' && widget.groupPurpose.isNotEmpty
                            ? widget.groupPurpose
                            : app.t('group_type_${kJuzzioGroupTypes.contains(widget.groupType) ? widget.groupType : 'general'}'),
              ),
              trailing: _iAmStaff && !widget.isCommunity
                  ? IconButton(tooltip: app.t('group_edit_info'), icon: const Icon(Icons.edit_rounded), onPressed: _editInfo)
                  : null,
            ),
            if (widget.isCommunity) _communityInfo(isDark),
            // v0.9.0 §6.4: Sohbet Bilgileri > Bildirimleri Özelleştir (her üye kendisi için)
            JuzzioChatNotificationPrefsTile(roomId: widget.roomId),
            JuzzioChatLockTile(roomId: widget.roomId),
            // v0.9.0 §4.3: Kayıtlı mesajlar
            ListTile(
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(JuzzioAppController.instance.trEn('Kayıtlı mesajlar', 'Saved messages', 'Gespeicherte Nachrichten')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => JuzzioSavedMessagesPage.open(context, roomId: widget.roomId, title: widget.groupTitle),
            ),
            if (_showMemberList)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  app.t('group_members_count').replaceAll('{n}', '${_members.length}'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: JuzzioOrbitLoader()),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (!_loading && _showMemberList)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  itemBuilder: (_, i) {
                    final m = _members[i];
                    final roleColor = m.isOwner
                        ? JuzzioColors.amber500
                        : m.isModerator
                            ? JuzzioColors.indigo500
                            : Colors.grey;
                    return ListTile(
                      onTap: _iAmStaff ? () => _memberActions(m) : null,
                      leading: CircleAvatar(
                        backgroundImage: m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
                        child: m.avatarUrl == null
                            ? Text(m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?')
                            : null,
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(m.userId == _myId ? '${m.displayName} (${app.t('common_you')})' : m.displayName)),
                          if (m.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, color: JuzzioColors.sky500, size: 16),
                          ],
                        ],
                      ),
                      subtitle: Text(m.isMuted
                          ? '${app.t('group_role_${m.role}')} • ${app.t('group_muted_label')}'
                          : app.t('group_role_${m.role}')),
                      trailing: m.role == 'member'
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: roleColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                app.t('group_role_${m.role}'),
                                style: TextStyle(color: roleColor, fontWeight: FontWeight.w800, fontSize: 11.5),
                              ),
                            ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
