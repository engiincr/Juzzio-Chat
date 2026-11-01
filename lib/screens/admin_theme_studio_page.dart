// =============================================================================
// JUZZIO v0.8.3 — Yönetici Tema Stüdyosu (küresel) + Personel rolleri (RBAC)
//  • Taslak oluştur (aynı canlı önizlemeli düzenleyici), sürüm geçmişi
//  • Hemen yayınla veya ileri tarihe zamanla, arşivle, eski sürüme geri al
//  • Erişilebilirlik raporu: metin/arka plan kontrastı (WCAG AA 4.5:1)
//  • Yetki sunucuda denetlenir (theme.publish); rol verme yalnızca süper yönetici
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_custom_theme.dart';
import '../core/theme/juzzio_glass.dart';
import '../core/widgets/glass_components.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';
import 'theme_studio_page.dart';

String _t(String tr, String en) => JuzzioAppController.instance.trEn(tr, en);

String _fmt(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class JuzzioAdminThemeStudioPage extends StatefulWidget {
  final String token;
  const JuzzioAdminThemeStudioPage({super.key, required this.token});

  @override
  State<JuzzioAdminThemeStudioPage> createState() => _JuzzioAdminThemeStudioPageState();
}

class _JuzzioAdminThemeStudioPageState extends State<JuzzioAdminThemeStudioPage> {
  final _f = JuzzioFeaturesService.instance;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _f.adminThemeList(widget.token);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // canlı yayın değiştiyse bu cihaz da güncellensin
    JuzzioAppController.instance.setGlobalThemeFromServer(await _f.activeGlobalTheme());
  }

  Future<void> _run(Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) showGlassToast(context, ok, icon: Icons.check_circle_rounded);
    } catch (e) {
      if (mounted) showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
    }
    await _load();
  }

  Future<bool> _submitDraft(JuzzioCustomTheme t) async {
    try {
      final v = await _f.adminThemeSaveDraft(widget.token, t.name, t.toJson());
      if (mounted) showGlassToast(context, _t('Taslak kaydedildi: v$v', 'Draft saved: v$v'), icon: Icons.check_circle_rounded);
      await _load();
      return true;
    } catch (e) {
      if (mounted) showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
      return false;
    }
  }

  Future<void> _newDraft({JuzzioCustomTheme? from}) async {
    final app = JuzzioAppController.instance;
    final base = from ?? app.draftFromCurrent();
    await JuzzioThemeEditorPage.open(context, base.copyWith(id: app.newCustomThemeId()),
        isNew: true, onSubmit: _submitDraft, submitLabel: _t('Taslak olarak kaydet', 'Save as draft'));
  }

  Future<void> _schedule(int version) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (at.isBefore(now)) {
      if (mounted) showGlassToast(context, _t('Geçmiş bir zaman seçilemez', 'Cannot schedule in the past'), icon: Icons.warning_amber_rounded);
      return;
    }
    await _run(() => _f.adminThemePublish(widget.token, version, at: at), _t('Zamanlandı: ${_fmt(at.toIso8601String())}', 'Scheduled'));
  }

  @override
  Widget build(BuildContext context) {
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t('Küresel Tema Stüdyosu', 'Global Theme Studio'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: _t('Yenile', 'Refresh'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: JuzzioGlassTokens.accentFill,
        foregroundColor: JuzzioGlassTokens.onAccent,
        onPressed: () => _newDraft(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_t('Yeni taslak', 'New draft'), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _t('Yayınlanan tema yalnızca kendi temasını seçmemiş kullanıcılara uygulanır; kullanıcılar Ayarlar → Görünüm\'den kapatabilir. '
                        'Geri alma, eski sürümü yeni bir sürüm olarak yayınlar; geçmiş silinmez.',
                        'Published themes apply only to users without their own theme choice. Rollback republishes an old version as a new one.'),
                    style: TextStyle(color: t2, fontSize: 12.5, height: 1.4),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(SupabaseService.instance.friendlyError(_error!),
                        style: const TextStyle(color: Color(0xFFFF647B), fontWeight: FontWeight.w800)),
                  ),
                if (_rows.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(_t('Henüz sürüm yok. "Yeni taslak" ile başlayın.', 'No versions yet.'),
                        textAlign: TextAlign.center, style: TextStyle(color: t2)),
                  ),
                for (final r in _rows) _versionCard(r, t, t2),
              ],
            ),
    );
  }

  Widget _versionCard(Map<String, dynamic> r, Color t, Color t2) {
    final v = (r['version'] as num).toInt();
    final status = '${r['status']}';
    final live = r['live'] == true;
    final parsed = r['payload'] is Map
        ? JuzzioCustomTheme.fromMap(Map<String, dynamic>.from(r['payload'] as Map), newId: 'ct_admin_v$v').theme
        : null;
    final scheduled = status == 'published' && !live && DateTime.tryParse('${r['publish_at']}')?.isAfter(DateTime.now()) == true;
    final label = live
        ? _t('YAYINDA', 'LIVE')
        : scheduled
            ? _t('ZAMANLANDI', 'SCHEDULED')
            : status == 'draft'
                ? _t('TASLAK', 'DRAFT')
                : status == 'archived'
                    ? _t('ARŞİV', 'ARCHIVED')
                    : _t('ÖNCEKİ YAYIN', 'PREVIOUS');
    final ratio = parsed == null ? null : JuzzioCustomTheme.contrastRatio(parsed.text, parsed.background);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassContainer(
        enableBlur: false,
        iridescentBorder: live,
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: parsed == null
                    ? null
                    : LinearGradient(colors: [parsed.c('gradientA'), parsed.background, parsed.c('gradientB')]),
                border: Border.all(color: JuzzioGlassTokens.borderStrong),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('v$v · ${r['name']}', style: TextStyle(color: t, fontWeight: FontWeight.w900)),
                Text(
                  '$label · ${scheduled ? _fmt('${r['publish_at']}') : _fmt('${r['created_at']}')}'
                  '${'${r['note'] ?? ''}'.isEmpty ? '' : ' · ${r['note']}'}',
                  style: TextStyle(color: live ? const Color(0xFF34C759) : t2, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                if (ratio != null)
                  Text(
                    '${_t('Kontrast', 'Contrast')} ${ratio.toStringAsFixed(1)}:1 ${ratio >= 4.5 ? '✓ AA' : '⚠ ${_t('düşük', 'low')}'}',
                    style: TextStyle(color: ratio >= 4.5 ? t2 : const Color(0xFFFF647B), fontSize: 11.5),
                  ),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (a) async {
                switch (a) {
                  case 'publish':
                    await _run(() => _f.adminThemePublish(widget.token, v), _t('v$v yayınlandı', 'v$v published'));
                  case 'schedule':
                    await _schedule(v);
                  case 'rollback':
                    await _run(() async {
                      await _f.adminThemeRollback(widget.token, v);
                    }, _t('v$v yeniden yayınlandı', 'v$v restored'));
                  case 'archive':
                    await _run(() => _f.adminThemeArchive(widget.token, v), _t('v$v arşivlendi', 'v$v archived'));
                  case 'edit':
                    if (parsed != null) await _newDraft(from: parsed);
                }
              },
              itemBuilder: (_) => [
                if (status == 'draft' || status == 'archived')
                  PopupMenuItem(value: 'publish', child: Text(_t('Hemen yayınla', 'Publish now'))),
                if (status == 'draft' || status == 'archived')
                  PopupMenuItem(value: 'schedule', child: Text(_t('Zamanla…', 'Schedule…'))),
                if (status != 'draft' && !live)
                  PopupMenuItem(value: 'rollback', child: Text(_t('Bu sürüme geri al', 'Roll back to this'))),
                if (status != 'archived') PopupMenuItem(value: 'archive', child: Text(_t('Arşivle / yayından kaldır', 'Archive'))),
                PopupMenuItem(value: 'edit', child: Text(_t('Kopyasından yeni taslak', 'New draft from this'))),
              ],
            ),
          ]),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PERSONEL ROLLERİ (RBAC)
// -----------------------------------------------------------------------------
const Map<String, String> kJuzzioStaffRoleLabels = {
  'admin': 'Yönetici',
  'moderator': 'Moderatör',
  'support': 'Destek',
  'analyst': 'Analist',
  'content_manager': 'İçerik yöneticisi',
  'auditor': 'Denetçi (salt okunur)',
};

class JuzzioAdminStaffPage extends StatefulWidget {
  final String token;
  const JuzzioAdminStaffPage({super.key, required this.token});

  @override
  State<JuzzioAdminStaffPage> createState() => _JuzzioAdminStaffPageState();
}

class _JuzzioAdminStaffPageState extends State<JuzzioAdminStaffPage> {
  final _f = JuzzioFeaturesService.instance;
  final _q = TextEditingController();
  List<Map<String, dynamic>> _staff = const [];
  List<Map<String, dynamic>> _found = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await _f.adminListStaff(widget.token);
      if (mounted) setState(() => _staff = s);
    } catch (e) {
      if (mounted) showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.length < 2) return;
    try {
      final r = await SupabaseService.instance.client.rpc('admin_search_users', params: {'p_token': widget.token, 'p_query': q});
      if (mounted) {
        setState(() => _found = r is List ? r.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const []);
      }
    } catch (e) {
      if (mounted) showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _grant(String userId, String name) async {
    final role = await showGlassBottomSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in kJuzzioStaffRoleLabels.entries)
            ListTile(title: Text(e.value), subtitle: Text(e.key), onTap: () => Navigator.of(ctx).pop(e.key)),
        ]),
      ),
    );
    if (role == null) return;
    try {
      await _f.adminGrantRole(widget.token, userId, role);
      if (mounted) showGlassToast(context, _t('$name → ${kJuzzioStaffRoleLabels[role]}', '$name → $role'), icon: Icons.check_circle_rounded);
    } catch (e) {
      if (mounted) showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_t('Personel rolleri', 'Staff roles'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          GlassTextField(
            controller: _q,
            hintText: _t('Kullanıcı ara (en az 2 harf)', 'Search users'),
            prefixIcon: Icons.search_rounded,
            onSubmitted: (_) => _search(),
          ),
          for (final u in _found)
            ListTile(
              title: Text('${u['display_name'] ?? u['username'] ?? ''}', style: TextStyle(color: t, fontWeight: FontWeight.w800)),
              subtitle: Text('@${u['username'] ?? ''}', style: TextStyle(color: t2)),
              trailing: TextButton(
                onPressed: () => _grant('${u['id']}', '@${u['username']}'),
                child: Text(_t('Rol ver', 'Grant role')),
              ),
            ),
          const SizedBox(height: 16),
          Text(_t('Rolü olanlar', 'Staff'), style: TextStyle(color: JuzzioGlassTokens.heading, fontWeight: FontWeight.w900, fontSize: 16)),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _staff.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_t('Henüz personel rolü yok.', 'No staff roles yet.'), style: TextStyle(color: t2)),
            ),
          for (final s in _staff)
            ListTile(
              title: Text('@${s['username']}', style: TextStyle(color: t, fontWeight: FontWeight.w800)),
              subtitle: Text('${kJuzzioStaffRoleLabels[s['role']] ?? s['role']} · ${_fmt('${s['granted_at']}')}',
                  style: TextStyle(color: t2)),
              trailing: IconButton(
                tooltip: _t('Rolü kaldır', 'Revoke'),
                icon: const Icon(Icons.person_remove_rounded, color: Color(0xFFFF647B)),
                onPressed: () async {
                  try {
                    await _f.adminRevokeRole(widget.token, '${s['user_id']}');
                  } catch (e) {
                    if (context.mounted) {
                      showGlassToast(context, SupabaseService.instance.friendlyError(e), icon: Icons.error_outline_rounded);
                    }
                  }
                  await _load();
                },
              ),
            ),
        ],
      ),
    );
  }
}
