// =============================================================================
// JUZZIO v0.3.0 — Grup üyeleri ve roller
//  • Yönetici (tek kişi): moderatör atar/alır, üye çıkarır, yöneticiliği devreder
//  • Moderatör: normal üyeleri susturur
//  • Rol yalnızca grup içinde görünür (profilde "Yönetici" rozeti YOKTUR)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/content_filter.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';

Future<void> showJuzzioGroupManagementSheet(
  BuildContext context, {
  required String roomId,
  required String groupTitle,
  String groupType = 'general',
  String groupPurpose = '',
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioAppController.instance.isDark ? JuzzioColors.surface141519 : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _GroupManagementSheet(
      roomId: roomId,
      groupTitle: groupTitle,
      groupType: groupType,
      groupPurpose: groupPurpose,
      onChanged: onChanged,
    ),
  );
}

class _GroupManagementSheet extends StatefulWidget {
  final String roomId;
  final String groupTitle;
  final String groupType;
  final String groupPurpose;
  final VoidCallback? onChanged;

  const _GroupManagementSheet({
    required this.roomId,
    required this.groupTitle,
    required this.groupType,
    required this.groupPurpose,
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

  String get _myId => SupabaseService.instance.currentUserId ?? '';
  String get _myRole => _members.firstWhere((m) => m.userId == _myId,
      orElse: () => const JuzzioGroupMember(userId: '', username: '', displayName: '')).role;
  bool get _iAmOwner => _myRole == 'owner';
  bool get _iAmStaff => _myRole == 'owner' || _myRole == 'moderator';

  @override
  void initState() {
    super.initState();
    _load();
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
    final minutes = await showModalBottomSheet<int>(
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
    final canMute = _iAmOwner ? !m.isOwner : (_myRole == 'moderator' && m.role == 'member');
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('@${m.username} • ${app.t('group_role_${m.role}')}'),
            ),
            if (_iAmOwner && m.role == 'member')
              ListTile(
                leading: const Icon(Icons.shield_rounded, color: JuzzioColors.indigo500),
                title: Text(app.t('group_make_moderator')),
                onTap: () {
                  Navigator.pop(ctx);
                  _act(() => _f.setMemberRole(roomId: widget.roomId, userId: m.userId, role: 'moderator'),
                      app.t('group_role_changed'));
                },
              ),
            if (_iAmOwner && m.role == 'moderator')
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(app.t('group_remove_moderator')),
                onTap: () {
                  Navigator.pop(ctx);
                  _act(() => _f.setMemberRole(roomId: widget.roomId, userId: m.userId, role: 'member'),
                      app.t('group_role_changed'));
                },
              ),
            if (_iAmOwner && !m.isOwner)
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
                widget.groupType == 'custom' && widget.groupPurpose.isNotEmpty
                    ? widget.groupPurpose
                    : app.t('group_type_${kJuzzioGroupTypes.contains(widget.groupType) ? widget.groupType : 'general'}'),
              ),
              trailing: _iAmStaff
                  ? IconButton(tooltip: app.t('group_edit_info'), icon: const Icon(Icons.edit_rounded), onPressed: _editInfo)
                  : null,
            ),
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
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (!_loading)
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
                                color: roleColor.withOpacity(0.15),
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
