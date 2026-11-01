// =============================================================================
// JUZZIO v0.5.0 — Yönetici Paneli (@tugkancr) · nötr cam, kişisel karşılama
//  • Genel bakış + 14 günlük grafikler, kullanıcı yönetimi (mavi tik, rol, askıya alma,
//    şifre sıfırlama, uyarı), moderasyon, duyuru, OTA sürüm merkezi, bakım modu ve
//    özellik bayrakları, denetim kayıtları.
//  • Şifre sunucuda bcrypt hash olarak saklanır; uygulamada şifre tutulmaz.
//  • "Bu cihazda beni hatırla": yalnızca sunucunun verdiği oturum belirteci
//    cihazın güvenli deposunda (Keystore) saklanır.
//  • Şikâyet inceleme, kullanıcı arama, hazır sebeplerle hesap + cihaz engeli.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_aurora.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import '../services/juzzio_features_service.dart';
import 'admin_extra_tabs.dart';
import 'admin_theme_studio_page.dart';

const List<String> kJuzzioBanReasons = [
  'spam',
  'harassment',
  'hate_speech',
  'inappropriate_content',
  'fake_account',
  'scam',
  'violence',
  'underage',
  'impersonation',
  'other',
];

/// Paneli açar: kayıtlı geçerli belirteç varsa doğrudan, yoksa şifre sorar.
Future<void> openJuzzioAdminPanel(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final features = JuzzioFeaturesService.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  if (!await features.isAdmin()) {
    messenger?.showSnackBar(SnackBar(content: Text(app.t('err_not_allowed'))));
    return;
  }
  var token = await features.storedAdminToken();
  if (token == null) {
    if (!context.mounted) return;
    // v0.8.0: şifre penceresi yerine ayrı, tüm cam temalarla uyumlu giriş sayfası
    token = await navigator.push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _AdminUnlockDialog()),
    );
  }
  if (token == null) return;
  await navigator.push(MaterialPageRoute(builder: (_) => JuzzioAdminPanelScreen(token: token!)));
}

class _AdminUnlockDialog extends StatefulWidget {
  const _AdminUnlockDialog();

  @override
  State<_AdminUnlockDialog> createState() => _AdminUnlockDialogState();
}

class _AdminUnlockDialogState extends State<_AdminUnlockDialog> {
  final TextEditingController _pw = TextEditingController();
  bool _remember = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = JuzzioAppController.instance;
    if (_pw.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await JuzzioFeaturesService.instance.adminUnlock(password: _pw.text, remember: _remember);
      if (!mounted) return;
      if (res.token != null) {
        Navigator.of(context).pop(res.token);
        return;
      }
      setState(() => _error = app.t('admin_wrong_password').replaceAll('{n}', '${res.remaining}'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  JuzzioUserProfile? _me;

  @override
  void initState() {
    super.initState();
    final uid = SupabaseService.instance.currentUserId;
    SupabaseService.instance.loadCachedMyProfile().then((c) {
      if (mounted && c != null) setState(() => _me = c);
    });
    if (uid != null) {
      SupabaseService.instance.fetchUserProfile(uid).then((f) {
        if (mounted && f != null) setState(() => _me = f);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: JuzzioAuroraBackground(palette: app.glassPalette, dark: app.isDark)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: JuzzioGlassIconButton(
                          icon: Icons.close_rounded,
                          tooltip: app.t('common_cancel'),
                          onTap: _busy ? null : () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: kJuzzioStoryRing),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: JuzzioGlassTokens.surfaceSolid),
                            child: JuzzioGlassAvatar(imageUrl: _me?.avatarUrl, name: _me?.displayName ?? 'Engin', radius: 46),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Hoşgeldin Engin ÇIRPAN',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: t, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_rounded, size: 16, color: t2),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '@${(_me?.username ?? '').trim().isEmpty ? 'tugkancr' : _me!.username.trim()} · ${app.trEn('Kurucu · Yönetici', 'Founder · Administrator', 'Gründer · Administrator')}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: t2, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      JuzzioGlass(
                        radius: 28,
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Icon(Icons.admin_panel_settings_rounded, color: t),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(app.t('admin_title'),
                                    style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 17)),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _pw,
                              obscureText: _obscure,
                              autofocus: true,
                              onSubmitted: (_) => _submit(),
                              style: TextStyle(color: t),
                              decoration: InputDecoration(
                                labelText: app.t('admin_password'),
                                errorText: _error,
                                errorMaxLines: 3,
                                prefixIcon: Icon(Icons.lock_rounded, color: t2),
                                filled: true,
                                fillColor: JuzzioGlassTokens.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: JuzzioGlassTokens.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: JuzzioGlassTokens.border)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: JuzzioGlassTokens.borderStrong, width: 1.4)),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: t2),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _remember,
                              onChanged: (v) => setState(() => _remember = v ?? false),
                              title: Text(app.t('admin_remember_device'), style: TextStyle(color: t, fontSize: 13.5)),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            const SizedBox(height: 6),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: JuzzioGlassTokens.accentFill,
                                foregroundColor: JuzzioGlassTokens.onAccent,
                                minimumSize: const Size.fromHeight(52),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: JuzzioGlassTokens.onAccent))
                                  : const Icon(Icons.login_rounded),
                              label: Text(app.t('admin_unlock'), style: const TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        app.trEn('Şifre sunucuda bcrypt ile saklanır; hatalı denemeler sınırlıdır ve kaydedilir.',
                            'The password is stored as a bcrypt hash; failed attempts are limited and logged.',
                            'Passwort als bcrypt-Hash gespeichert; Fehlversuche sind begrenzt.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t2, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class JuzzioAdminPanelScreen extends StatefulWidget {
  final String token;
  const JuzzioAdminPanelScreen({super.key, required this.token});

  @override
  State<JuzzioAdminPanelScreen> createState() => _JuzzioAdminPanelScreenState();
}

String _al(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

class _JuzzioAdminPanelScreenState extends State<JuzzioAdminPanelScreen> with SingleTickerProviderStateMixin {
  final JuzzioFeaturesService _f = JuzzioFeaturesService.instance;
  late final TabController _tabs = TabController(length: 13, vsync: this);

  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _bans = const [];
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _releases = const [];
  List<Map<String, dynamic>> _audit = const [];
  JuzzioAppConfig _config = const JuzzioAppConfig();
  String _reportFilter = 'open';
  String _userFilter = 'all';
  bool _loading = true;
  bool _usersLoading = false;

  final TextEditingController _search = TextEditingController();
  final TextEditingController _bcTitle = TextEditingController();
  final TextEditingController _bcBody = TextEditingController();
  final TextEditingController _bcImage = TextEditingController();
  String _bcAudience = 'all';
  final TextEditingController _relName = TextEditingController();
  final TextEditingController _relCode = TextEditingController();
  final TextEditingController _relUrl = TextEditingController();
  final TextEditingController _relTr = TextEditingController();
  final TextEditingController _relEn = TextEditingController();
  final TextEditingController _relDe = TextEditingController();
  // v0.6.1 şeffaf sürüm notları: neden / özellikler / düzeltmeler / güvenlik
  final TextEditingController _relReason = TextEditingController();
  final TextEditingController _relFeatures = TextEditingController();
  final TextEditingController _relFixes = TextEditingController();
  final TextEditingController _relSecurity = TextEditingController();
  final TextEditingController _relReasonEn = TextEditingController();
  final TextEditingController _relFeaturesEn = TextEditingController();
  final TextEditingController _relFixesEn = TextEditingController();
  final TextEditingController _relSecurityEn = TextEditingController();
  bool _relMandatory = false;
  final TextEditingController _modId = TextEditingController();
  String _modType = 'post';
  final TextEditingController _maintMsg = TextEditingController();
  final TextEditingController _bannerMsg = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reloadAll();
    _loadMe();
    _loadHealth();
  }

  // Sistem durumu: sunucu verisi + istemciden canlı sağlık ölçümleri
  Map<String, dynamic>? _health;
  String? _healthError;
  int? _translateLatencyMs;
  bool? _translateOk;
  int? _dbLatencyMs;

  Future<void> _loadHealth() async {
    final sw = Stopwatch()..start();
    try {
      final h = await _f.adminSystemHealth(widget.token);
      sw.stop();
      if (mounted) {
        setState(() {
          _health = h;
          _healthError = null;
          _dbLatencyMs = sw.elapsedMilliseconds;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _healthError = SupabaseService.instance.friendlyError(e));
    }
    final tw = Stopwatch()..start();
    try {
      final t = await SupabaseService.instance.translateText(text: 'merhaba dünya', sourceLang: 'tr', targetLang: 'en');
      tw.stop();
      if (mounted) {
        setState(() {
          _translateOk = t.trim().isNotEmpty && t.trim().toLowerCase() != 'merhaba dünya';
          _translateLatencyMs = tw.elapsedMilliseconds;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _translateOk = false);
    }
  }

  Widget _buildHealthCard(bool isDark) {
    final h = _health;
    final fg = isDark ? Colors.white : JuzzioColors.ink;
    final sub = isDark ? JuzzioGlassTokens.textSecondary : JuzzioColors.slate600;
    Widget row(String label, String value, {Color? dot}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(label, style: TextStyle(color: sub, fontSize: 13))),
            Text(value, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13.5)),
          ],
        ),
      );
    }

    String n(String k) => h == null ? '–' : _num(h[k]);
    const ok = JuzzioColors.emerald400;
    const bad = JuzzioColors.red500;
    const warn = JuzzioColors.amber500;
    return _card(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(_al('Sistem durumu', 'System health', 'Systemstatus'), Icons.monitor_heart_rounded, isDark)),
              IconButton(
                tooltip: _al('Yenile', 'Refresh', 'Aktualisieren'),
                onPressed: _loadHealth,
                icon: Icon(Icons.refresh_rounded, color: sub, size: 20),
              ),
            ],
          ),
          row(
            _al('Veritabanı (Supabase)', 'Database (Supabase)', 'Datenbank (Supabase)'),
            _healthError != null ? _al('Hata', 'Error', 'Fehler') : (_dbLatencyMs == null ? '…' : '$_dbLatencyMs ms'),
            dot: _healthError != null ? bad : (_dbLatencyMs == null ? warn : ok),
          ),
          row(
            _al('Çeviri servisi', 'Translation service', 'Übersetzungsdienst'),
            _translateOk == null ? '…' : (_translateOk! ? '${_translateLatencyMs ?? 0} ms' : _al('Yanıt yok', 'No response', 'Keine Antwort')),
            dot: _translateOk == null ? warn : (_translateOk! ? ok : bad),
          ),
          row(_al('Aktif FCM cihazı', 'Active FCM devices', 'Aktive FCM-Geräte'), n('push_tokens_active'),
              dot: h != null && ((h['push_tokens_active'] as num?) ?? 0) > 0 ? ok : warn),
          row(_al('Geçersiz FCM jetonu', 'Invalid FCM tokens', 'Ungültige FCM-Token'), n('push_tokens_invalid')),
          const Divider(height: 18),
          row(_al('Aktif sesli arama', 'Active voice calls', 'Aktive Sprachanrufe'), n('active_voice_calls')),
          row(_al('Aktif görüntülü arama', 'Active video calls', 'Aktive Videoanrufe'), n('active_video_calls')),
          row(_al('Aktif konferans', 'Active conferences', 'Aktive Konferenzen'), n('active_conferences')),
          const Divider(height: 18),
          row(_al('Çeviri isteği (bugün)', 'Translation requests (today)', 'Übersetzungen (heute)'), n('translation_requests_today')),
          row(_al('Önbellekten (bugün)', 'Cache hits (today)', 'Cache-Treffer (heute)'), n('translation_cache_hits_today')),
          row(_al('Başarısız çeviri (bugün)', 'Failed translations (today)', 'Fehlgeschlagen (heute)'), n('translation_failures_today'),
              dot: h != null && ((h['translation_failures_today'] as num?) ?? 0) > 0 ? warn : null),
          row(_al('Çeviri önbelleği', 'Translation cache', 'Übersetzungs-Cache'), n('translation_cache_size')),
          const Divider(height: 18),
          row(_al('Topluluk gönderisi', 'Community posts', 'Community-Beiträge'), n('community_posts')),
          row(_al('Hikâye (24 sa)', 'Stories (24h)', 'Storys (24 Std.)'), n('stories_24h')),
          row(_al('Yönetici işlemi (24 sa)', 'Admin actions (24h)', 'Admin-Aktionen (24 Std.)'), n('admin_actions_24h')),
          if (_healthError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _al('Sistem durumu alınamadı (v0.5 SQL dosyası uygulanmamış olabilir): $_healthError',
                    'Could not load system health (the v0.5 SQL may not be applied yet): $_healthError',
                    'Systemstatus nicht verfügbar (v0.5-SQL evtl. nicht angewendet): $_healthError'),
                style: const TextStyle(color: JuzzioColors.red500, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Karşılama için oturumdaki yöneticinin gerçek profili (fotoğraf + ad)
  JuzzioUserProfile? _me;
  Future<void> _loadMe() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final cached = await SupabaseService.instance.loadCachedMyProfile();
      if (mounted && cached != null) setState(() => _me = cached);
      final fresh = await SupabaseService.instance.fetchUserProfile(uid);
      if (mounted && fresh != null) setState(() => _me = fresh);
    } catch (_) {}
  }

  String get _welcomeName {
    final dn = (_me?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn.split(RegExp(r'\s+')).first;
    final un = (_me?.username ?? '').trim();
    return un.isNotEmpty ? un : 'Admin';
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_search, _bcTitle, _bcBody, _bcImage, _relName, _relCode, _relUrl, _relTr, _relEn, _relDe, _relReason, _relFeatures, _relFixes, _relSecurity, _relReasonEn, _relFeaturesEn, _relFixesEn, _relSecurityEn, _modId, _maintMsg, _bannerMsg]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        backgroundColor: error ? JuzzioColors.red500 : JuzzioColors.emerald500,
      ),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString(), error: true);
      if (e.toString() == JuzzioAppController.instance.t('err_admin_session')) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _reloadAll() async {
    setState(() => _loading = true);
    await _guard(() async {
      final results = await Future.wait<Object>([
        _f.adminStats(widget.token),
        _f.adminListReports(widget.token, status: _reportFilter),
        _f.adminListBans(widget.token),
        _f.adminListReleases(widget.token),
        _f.adminAudit(widget.token),
        _f.fetchAppConfig(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _reports = results[1] as List<Map<String, dynamic>>;
        _bans = results[2] as List<Map<String, dynamic>>;
        _releases = results[3] as List<Map<String, dynamic>>;
        _audit = results[4] as List<Map<String, dynamic>>;
        _config = results[5] as JuzzioAppConfig;
        if (_maintMsg.text.isEmpty) _maintMsg.text = _config.maintenanceMessage;
        if (_bannerMsg.text.isEmpty) _bannerMsg.text = _config.announcementBanner;
      });
      if (_relCode.text.isEmpty) {
        var maxCode = JuzzioConfig.appVersionCode;
        for (final r in _releases) {
          final c = (r['version_code'] as num?)?.toInt() ?? 0;
          if (c > maxCode) maxCode = c;
        }
        _relCode.text = '${maxCode + 1}';
      }
    });
    if (mounted) setState(() => _loading = false);
    if (_users.isEmpty) _searchUsers(allowEmpty: true);
  }

  Future<void> _searchUsers({bool allowEmpty = false}) async {
    final q = _search.text.trim();
    if (q.isEmpty && !allowEmpty) return;
    setState(() => _usersLoading = true);
    await _guard(() async {
      final res = await _f.adminSearchUsers(widget.token, q);
      if (mounted) setState(() => _users = res);
    });
    if (mounted) setState(() => _usersLoading = false);
  }

  List<Map<String, dynamic>> get _filteredUsers {
    switch (_userFilter) {
      case 'online':
        return _users.where((u) => u['is_online'] == true).toList();
      case 'verified':
        return _users.where((u) => u['is_verified'] == true).toList();
      case 'banned':
        return _users.where((u) => u['is_banned'] == true).toList();
      case 'reported':
        return _users.where((u) => ((u['open_reports'] as num?) ?? 0) > 0).toList();
      case 'moderator':
        return _users.where((u) => u['app_role'] == 'moderator').toList();
      default:
        return _users;
    }
  }

  // ---------------------------------------------------------------------------
  // Kullanıcı işlemleri
  // ---------------------------------------------------------------------------
  Future<void> _banFlow(String userId, String handle) async {
    final app = JuzzioAppController.instance;
    String reason = kJuzzioBanReasons.first;
    bool banDevices = true;
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(app.t('admin_ban_title').replaceAll('{user}', handle)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.t('admin_ban_reason'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in kJuzzioBanReasons)
                      ChoiceChip(
                        label: Text(app.t('ban_reason_$r')),
                        selected: reason == r,
                        onSelected: (_) => setLocal(() => reason = r),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLength: 300,
                  decoration: InputDecoration(labelText: app.t('admin_ban_note')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: banDevices,
                  onChanged: (v) => setLocal(() => banDevices = v),
                  title: Text(app.t('admin_ban_devices')),
                  subtitle: Text(app.t('admin_ban_devices_desc')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(app.t('admin_ban')),
            ),
          ],
        ),
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirmed != true) return;
    await _guard(() async {
      final devices = await _f.adminBanUser(widget.token, userId, reason, note: note, banDevices: banDevices);
      _snack(app.t('admin_banned_ok').replaceAll('{n}', '$devices'));
      await _reloadAll();
      await _searchUsers(allowEmpty: true);
    });
  }

  Future<void> _unban(String userId) async {
    final app = JuzzioAppController.instance;
    await _guard(() async {
      await _f.adminUnbanUser(widget.token, userId);
      _snack(app.t('admin_unbanned_ok'));
      await _reloadAll();
      await _searchUsers(allowEmpty: true);
    });
  }

  Future<void> _suspendFlow(String userId, String handle) async {
    final app = JuzzioAppController.instance;
    int hours = 24;
    String reason = kJuzzioBanReasons.first;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_al('$handle askıya al', 'Suspend $handle', '$handle sperren')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_al('Süre', 'Duration', 'Dauer'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final h in const [1, 6, 24, 72, 168, 720])
                      ChoiceChip(
                        label: Text(h < 24 ? '$h ${_al('saat', 'h', 'Std.')}' : '${h ~/ 24} ${_al('gün', 'd', 'T.')}'),
                        selected: hours == h,
                        onSelected: (_) => setLocal(() => hours = h),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(app.t('admin_ban_reason'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in kJuzzioBanReasons)
                      ChoiceChip(
                        label: Text(app.t('ban_reason_$r')),
                        selected: reason == r,
                        onSelected: (_) => setLocal(() => reason = r),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: noteCtrl, maxLength: 300, decoration: InputDecoration(labelText: app.t('admin_ban_note'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: JuzzioColors.amber600),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_al('Askıya al', 'Suspend', 'Sperren')),
            ),
          ],
        ),
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true) return;
    await _guard(() async {
      await _f.adminSuspendUser(widget.token, userId, hours, reason, note: note);
      _snack(_al('Hesap $hours saat askıya alındı.', 'Account suspended for $hours h.', 'Konto für $hours Std. gesperrt.'));
      await _reloadAll();
      await _searchUsers(allowEmpty: true);
    });
  }

  Future<void> _warnFlow(String userId, String handle) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_al('$handle kullanıcısına uyarı', 'Warn $handle', '$handle verwarnen')),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 500,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _al('Uyarı mesajı (kullanıcıya bildirim olarak gider)', 'Warning message (sent as a notification)',
                'Warnhinweis (wird als Benachrichtigung gesendet)'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(JuzzioAppController.instance.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_al('Gönder', 'Send', 'Senden'))),
        ],
      ),
    );
    final msg = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || msg.isEmpty) return;
    await _guard(() async {
      await _f.adminWarnUser(widget.token, userId, msg);
      _snack(_al('Uyarı gönderildi.', 'Warning sent.', 'Verwarnung gesendet.'));
    });
  }

  Future<void> _openUserDetail(String userId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AdminUserDetailSheet(
        token: widget.token,
        userId: userId,
        onBan: (handle) async {
          Navigator.of(ctx).pop();
          await _banFlow(userId, handle);
        },
        onUnban: () async {
          Navigator.of(ctx).pop();
          await _unban(userId);
        },
        onSuspend: (handle) async {
          Navigator.of(ctx).pop();
          await _suspendFlow(userId, handle);
        },
        onWarn: (handle) => _warnFlow(userId, handle),
      ),
    );
    await _searchUsers(allowEmpty: true);
  }

  // ---------------------------------------------------------------------------
  // İçerik, duyuru, sürüm, ayarlar
  // ---------------------------------------------------------------------------
  Future<bool> _confirm(String title, String body, {String? action, Color color = JuzzioColors.red500}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(JuzzioAppController.instance.t('common_cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action ?? _al('Onayla', 'Confirm', 'Bestätigen')),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _deleteContent(String type, String id) async {
    if (id.trim().isEmpty) return;
    final ok = await _confirm(
      _al('İçerik silinsin mi?', 'Delete content?', 'Inhalt löschen?'),
      _al('Bu işlem geri alınamaz. İlgili açık şikâyetler çözüldü olarak işaretlenir.',
          'This cannot be undone. Related open reports will be marked as resolved.',
          'Dies kann nicht rückgängig gemacht werden. Zugehörige offene Meldungen werden als erledigt markiert.'),
      action: _al('Sil', 'Delete', 'Löschen'),
    );
    if (!ok) return;
    await _guard(() async {
      final deleted = await _f.adminDeleteContent(widget.token, type, id.trim());
      _snack(deleted
          ? _al('İçerik silindi.', 'Content deleted.', 'Inhalt gelöscht.')
          : _al('İçerik bulunamadı (zaten silinmiş olabilir).', 'Content not found (it may already be deleted).',
              'Inhalt nicht gefunden (evtl. bereits gelöscht).'));
      _modId.clear();
      await _reloadAll();
    });
  }

  Future<void> _sendBroadcast() async {
    final title = _bcTitle.text.trim();
    final body = _bcBody.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack(_al('Başlık ve mesaj gerekli.', 'Title and message are required.', 'Titel und Nachricht sind erforderlich.'), error: true);
      return;
    }
    final ok = await _confirm(
      _al('Duyuru gönderilsin mi?', 'Send announcement?', 'Ankündigung senden?'),
      _al('Seçilen kitledeki herkese anlık bildirim gönderilecek.', 'Everyone in the selected audience will get a push notification.',
          'Alle in der gewählten Zielgruppe erhalten eine Push-Benachrichtigung.'),
      action: _al('Gönder', 'Send', 'Senden'),
      color: JuzzioColors.blue600,
    );
    if (!ok) return;
    await _guard(() async {
      final n = await _f.adminBroadcast(widget.token, title: title, body: body, imageUrl: _bcImage.text.trim(), audience: _bcAudience);
      _snack(_al('Duyuru $n kişiye gönderildi.', 'Announcement sent to $n people.', 'Ankündigung an $n Personen gesendet.'));
      _bcTitle.clear();
      _bcBody.clear();
      _bcImage.clear();
      await _reloadAll();
    });
  }

  void _fillReleaseFromGithub() {
    final name = _relName.text.trim().replaceFirst(RegExp(r'^v'), '');
    if (name.isEmpty) {
      _snack(_al('Önce sürüm adını yazın (ör. 0.4.1).', 'Enter the version name first (e.g. 0.4.1).',
          'Gib zuerst den Versionsnamen ein (z. B. 0.4.1).'), error: true);
      return;
    }
    setState(() {
      _relUrl.text =
          'https://github.com/${JuzzioConfig.githubOwner}/${JuzzioConfig.githubRepo}/releases/download/v$name/juzzio-v$name-release.apk';
    });
  }

  Map<String, dynamic> _releaseDetails() {
    List<String> lines(TextEditingController c) => c.text
        .split('\n')
        .map((l) => l.trim().replaceFirst(RegExp(r'^[-•*]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    Map<String, dynamic> section(TextEditingController r, TextEditingController f, TextEditingController x, TextEditingController s) =>
        <String, dynamic>{'reason': r.text.trim(), 'features': lines(f), 'fixes': lines(x), 'security': lines(s)};
    final out = <String, dynamic>{'tr': section(_relReason, _relFeatures, _relFixes, _relSecurity)};
    if (_relReasonEn.text.trim().isNotEmpty || _relFeaturesEn.text.trim().isNotEmpty || _relFixesEn.text.trim().isNotEmpty) {
      out['en'] = section(_relReasonEn, _relFeaturesEn, _relFixesEn, _relSecurityEn);
    }
    return out;
  }

  Future<void> _publishRelease() async {
    final name = _relName.text.trim().replaceFirst(RegExp(r'^v'), '');
    final code = int.tryParse(_relCode.text.trim()) ?? 0;
    final url = _relUrl.text.trim();
    // v0.7.0: Notlar boşsa GitHub sürüm sayfasından otomatik doldurulur (elle yazmak gerekmez)
    Map<String, dynamic> autoDetails = const {};
    if (_relReason.text.trim().isEmpty && name.isNotEmpty) {
      autoDetails = await JuzzioAppController.instance.fetchGithubReleaseDetails(name);
      final tr = autoDetails['tr'];
      if (tr is Map && '${tr['reason'] ?? ''}'.trim().isNotEmpty) {
        _relReason.text = '${tr['reason']}'.trim();
        _relFeatures.text = (tr['features'] is List ? (tr['features'] as List).join('\n') : '');
        _relFixes.text = (tr['fixes'] is List ? (tr['fixes'] as List).join('\n') : '');
        _relSecurity.text = (tr['security'] is List ? (tr['security'] as List).join('\n') : '');
      }
    }
    if (_relReason.text.trim().isEmpty) _relReason.text = _relTr.text.trim().isNotEmpty ? _relTr.text.trim() : 'Juzzio v$name';
    if (_relTr.text.trim().isEmpty) _relTr.text = _relReason.text.trim();
    if (name.isEmpty || code <= 0 || !url.startsWith('https://') || _relTr.text.trim().isEmpty) {
      _snack(
        _al('Sürüm adı, sürüm kodu, https APK bağlantısı ve Türkçe notlar zorunlu.',
            'Version name, version code, an https APK link and Turkish notes are required.',
            'Versionsname, Versionscode, https-APK-Link und türkische Notizen sind erforderlich.'),
        error: true,
      );
      return;
    }
    final ok = await _confirm(
      _al('v$name yayınlansın mı?', 'Publish v$name?', 'v$name veröffentlichen?'),
      _al('Tüm kullanıcılara "Güncelleme geldi" bildirimi gider ve uygulama içinden indirip kurabilirler.',
          'All users get an "Update available" notification and can install it inside the app.',
          'Alle Nutzer erhalten eine Update-Benachrichtigung und können direkt in der App installieren.'),
      action: _al('Yayınla', 'Publish', 'Veröffentlichen'),
      color: JuzzioColors.blue600,
    );
    if (!ok) return;
    await _guard(() async {
      await _f.adminPublishRelease(
        widget.token,
        versionName: name,
        versionCode: code,
        apkUrl: url,
        notesTr: _relTr.text.trim(),
        notesEn: _relEn.text.trim(),
        notesDe: _relDe.text.trim(),
        mandatory: _relMandatory,
        details: _releaseDetails(),
      );
      _snack(_al('v$name yayınlandı.', 'v$name published.', 'v$name veröffentlicht.'));
      _relName.clear();
      _relCode.clear();
      _relUrl.clear();
      _relTr.clear();
      _relEn.clear();
      _relDe.clear();
      for (final c in [_relReason, _relFeatures, _relFixes, _relSecurity, _relReasonEn, _relFeaturesEn, _relFixesEn, _relSecurityEn]) {
        c.clear();
      }
      await _reloadAll();
    });
  }

  Future<void> _setFlag(String key, Object value) async {
    await _guard(() async {
      await _f.adminSetSetting(widget.token, key, value);
      final cfg = await _f.fetchAppConfig();
      if (mounted) setState(() => _config = cfg);
      _snack(_al('Ayar kaydedildi.', 'Setting saved.', 'Einstellung gespeichert.'));
    });
  }

  // ---------------------------------------------------------------------------
  // ARAYÜZ
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    // Glassmorphism: sayfa saydam, arkada seçili aurora cam teması; üst çubuk buzlu cam
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0x66101117) : const Color(0x99FFFFFF),
        surfaceTintColor: Colors.transparent,
        foregroundColor: JuzzioGlassTokens.textPrimary,
        elevation: 0,
        toolbarHeight: 68,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
              ),
              child: JuzzioGlassAvatar(
                imageUrl: _me?.avatarUrl,
                name: _me?.displayName ?? 'tugkancr',
                radius: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _al('Hoşgeldin, $_welcomeName!', 'Welcome, $_welcomeName!', 'Willkommen, $_welcomeName!'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900, fontSize: 19, color: JuzzioGlassTokens.textPrimary),
                  ),
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded, size: 13, color: JuzzioGlassTokens.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          app.t('admin_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: JuzzioGlassTokens.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: app.t('common_refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _reloadAll),
          IconButton(
            tooltip: app.t('admin_logout'),
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final nav = Navigator.of(context);
              await _f.adminLogout(widget.token);
              nav.pop();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // v0.7.0: aydınlık ve karanlık temada net okunan sekmeler
          labelColor: JuzzioGlassTokens.textPrimary,
          unselectedLabelColor: JuzzioGlassTokens.textSecondary,
          indicatorColor: JuzzioGlassTokens.textPrimary,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(icon: const Icon(Icons.insights_rounded, size: 20), text: _al('Genel', 'Overview', 'Übersicht')),
            Tab(icon: const Icon(Icons.people_alt_rounded, size: 20), text: app.t('admin_tab_users')),
            Tab(
              icon: Badge(
                isLabelVisible: ((_stats['open_reports'] as num?) ?? 0) > 0,
                label: Text('${_stats['open_reports'] ?? 0}'),
                child: const Icon(Icons.flag_rounded, size: 20),
              ),
              text: app.t('admin_tab_reports'),
            ),
            Tab(icon: const Icon(Icons.block_rounded, size: 20), text: app.t('admin_tab_bans')),
            Tab(icon: const Icon(Icons.shield_rounded, size: 20), text: _al('Denetim', 'Safety', 'Sicherheit')),
            Tab(icon: const Icon(Icons.delete_sweep_rounded, size: 20), text: _al('Moderasyon', 'Moderation', 'Moderation')),
            Tab(icon: const Icon(Icons.groups_2_rounded, size: 20), text: _al('Gruplar', 'Groups', 'Gruppen')),
            Tab(icon: const Icon(Icons.sensors_rounded, size: 20), text: _al('Canlı', 'Live', 'Live')),
            Tab(icon: const Icon(Icons.campaign_rounded, size: 20), text: _al('Duyuru', 'Announce', 'Ankündigung')),
            Tab(icon: const Icon(Icons.system_update_rounded, size: 20), text: _al('Güncelleme', 'Updates', 'Updates')),
            Tab(icon: const Icon(Icons.tune_rounded, size: 20), text: _al('Ayarlar', 'Settings', 'Einstellungen')),
            Tab(icon: const Icon(Icons.bug_report_rounded, size: 20), text: _al('Hata bildirimleri', 'Bug reports', 'Fehlermeldungen')),
            Tab(icon: const Icon(Icons.history_rounded, size: 20), text: _al('Kayıtlar', 'Audit', 'Protokoll')),
          ],
        ),
      ),
      body: _loading && _stats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildOverview(isDark),
                _buildUsers(app, isDark),
                _buildReports(app),
                _buildBans(app),
                JuzzioAdminModerationTab(token: widget.token),
                _buildModeration(isDark),
                JuzzioAdminGroupsTab(token: widget.token),
                JuzzioAdminLiveTab(token: widget.token),
                _buildBroadcast(isDark),
                _buildReleases(isDark),
                _buildSettings(isDark),
                JuzzioAdminFeedbackTab(token: widget.token),
                _buildAudit(isDark),
              ],
            ),
    );
  }

  Widget _card({required Widget child, required bool isDark, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? null : JuzzioGlassTokens.surfaceSolid,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JuzzioGlassTokens.border),
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
              )
            : null,
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white70 : JuzzioColors.ink),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : JuzzioColors.ink)),
        ],
      ),
    );
  }

  String _num(Object? v) {
    final n = (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _bytes(Object? v) {
    final b = (v is num) ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
    if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toInt()} B';
  }

  Widget _buildOverview(bool isDark) {
    final s = _stats;
    final storage = s['storage'] is Map ? Map<String, dynamic>.from(s['storage'] as Map) : const <String, dynamic>{};
    final series = s['series'] is List
        ? (s['series'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : <Map<String, dynamic>>[];
    final tiles = <_StatTileData>[
      _StatTileData(_al('Kullanıcı', 'Users', 'Nutzer'), _num(s['users']), Icons.people_alt_rounded, JuzzioColors.blue500),
      _StatTileData(_al('Çevrimiçi', 'Online', 'Online'), _num(s['online_now']), Icons.wifi_rounded, JuzzioColors.emerald500),
      _StatTileData(_al('Günlük aktif', 'Daily active', 'Täglich aktiv'), _num(s['dau']), Icons.today_rounded, JuzzioColors.sky500),
      _StatTileData(_al('Aylık aktif', 'Monthly active', 'Monatlich aktiv'), _num(s['mau']), Icons.calendar_month_rounded, JuzzioColors.indigo500),
      _StatTileData(_al('Mesaj (24s)', 'Messages (24h)', 'Nachrichten (24h)'), _num(s['messages_today']), Icons.chat_rounded, JuzzioColors.pink500),
      _StatTileData(_al('Toplam mesaj', 'Total messages', 'Nachrichten gesamt'), _num(s['messages_total']), Icons.forum_rounded, JuzzioColors.purple400),
      _StatTileData(_al('Arama', 'Calls', 'Anrufe'), _num(s['calls_total']), Icons.call_rounded, JuzzioColors.emerald400),
      _StatTileData(_al('Sesli dk', 'Voice min', 'Sprach-Min.'), _num(s['voice_minutes']), Icons.mic_rounded, JuzzioColors.amber500),
      _StatTileData(_al('Görüntülü dk', 'Video min', 'Video-Min.'), _num(s['video_minutes']), Icons.videocam_rounded, JuzzioColors.red500),
      _StatTileData(_al('Gönderi', 'Posts', 'Beiträge'), _num(s['posts']), Icons.grid_on_rounded, JuzzioColors.blue400),
      _StatTileData(_al('Hikâye (24s)', 'Stories (24h)', 'Storys (24h)'), _num(s['stories_active']), Icons.auto_awesome_motion_rounded, JuzzioColors.pink400),
      _StatTileData(_al('Grup', 'Groups', 'Gruppen'), _num(s['groups']), Icons.groups_rounded, JuzzioColors.sky400),
      _StatTileData(_al('Mavi tik', 'Verified', 'Verifiziert'), _num(s['verified']), Icons.verified_rounded, JuzzioColors.blue600),
      _StatTileData(_al('Açık şikâyet', 'Open reports', 'Offene Meldungen'), _num(s['open_reports']), Icons.flag_rounded, JuzzioColors.amber600),
      _StatTileData(_al('Engelli hesap', 'Banned', 'Gesperrt'), _num(s['banned_users']), Icons.block_rounded, JuzzioColors.red500),
      _StatTileData(_al('Engelli cihaz', 'Banned devices', 'Gesperrte Geräte'), _num(s['banned_devices']), Icons.phonelink_lock_rounded, JuzzioColors.redDark),
      _StatTileData(_al('Civciv (canlı)', 'Chicks alive', 'Küken lebend'), _num(s['chick_alive']), Icons.egg_rounded, JuzzioColors.amber500),
      _StatTileData(_al('Depolama', 'Storage', 'Speicher'), _bytes(storage['bytes']), Icons.cloud_rounded, JuzzioColors.slate500),
    ];
    return RefreshIndicator(
      onRefresh: () async {
        await _reloadAll();
        await _loadHealth();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth > 700 ? 6 : (box.maxWidth > 420 ? 3 : 2);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [for (final t in tiles) _StatTile(data: t, isDark: isDark)],
              );
            },
          ),
          const SizedBox(height: 14),
          _buildHealthCard(isDark),
          _card(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(_al('Son 14 gün', 'Last 14 days', 'Letzte 14 Tage'), Icons.show_chart_rounded, isDark),
                _LegendRow(isDark: isDark),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: series.isEmpty
                      ? Center(child: Text(_al('Veri yok', 'No data', 'Keine Daten')))
                      : _SeriesChart(series: series, isDark: isDark),
                ),
              ],
            ),
          ),
          _card(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(_al('Yeni kayıtlar', 'Sign-ups', 'Registrierungen'), Icons.person_add_alt_1_rounded, isDark),
                SizedBox(
                  height: 120,
                  child: series.isEmpty ? const SizedBox.shrink() : _BarChart(series: series, field: 'signups', isDark: isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsers(JuzzioAppController app, bool isDark) {
    final list = _filteredUsers;
    final filters = <List<String>>[
      ['all', _al('Tümü', 'All', 'Alle')],
      ['online', _al('Çevrimiçi', 'Online', 'Online')],
      ['verified', _al('Mavi tikli', 'Verified', 'Verifiziert')],
      ['reported', _al('Şikâyetli', 'Reported', 'Gemeldet')],
      ['banned', _al('Engelli', 'Banned', 'Gesperrt')],
      ['moderator', _al('Moderatör', 'Moderators', 'Moderatoren')],
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchUsers(allowEmpty: true),
            decoration: InputDecoration(
              hintText: app.t('admin_search_hint'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _searchUsers(allowEmpty: true)),
              filled: true,
              fillColor: isDark ? JuzzioColors.surface1E2029 : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f[1]),
                    selected: _userFilter == f[0],
                    onSelected: (_) => setState(() => _userFilter = f[0]),
                  ),
                ),
            ],
          ),
        ),
        if (_usersLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(_al('Kullanıcı bulunamadı', 'No users found', 'Keine Nutzer gefunden')))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final u = list[i];
                    final banned = u['is_banned'] == true;
                    final verified = u['is_verified'] == true;
                    final online = u['is_online'] == true;
                    final avatar = (u['avatar_url'] ?? '').toString();
                    final reports = ((u['open_reports'] as num?) ?? 0).toInt();
                    return Material(
                      color: isDark ? JuzzioColors.surface1E2029 : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onTap: () => _openUserDetail(u['id'].toString()),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                              child: avatar.isEmpty ? Text(_initial((u['display_name'] ?? '').toString())) : null,
                            ),
                            if (online)
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: JuzzioColors.emerald500,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isDark ? JuzzioColors.surface1E2029 : Colors.white, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text('${u['display_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            if (verified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, size: 16, color: JuzzioColors.sky500),
                            ],
                            if (u['app_role'] == 'moderator') ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.shield_rounded, size: 15, color: JuzzioColors.emerald500),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          app
                              .t('admin_user_line')
                              .replaceAll('{user}', '@${u['username'] ?? ''}')
                              .replaceAll('{devices}', '${u['device_count'] ?? 0}')
                              .replaceAll('{reports}', '$reports'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: banned
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: JuzzioColors.red500.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  u['banned_until'] != null ? _al('Askıda', 'Suspended', 'Gesperrt') : _al('Engelli', 'Banned', 'Gebannt'),
                                  style: const TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w800, fontSize: 12),
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReports(JuzzioAppController app) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'open', label: Text(app.t('admin_reports_open'))),
              ButtonSegment(value: 'all', label: Text(app.t('admin_reports_all'))),
            ],
            selected: {_reportFilter},
            onSelectionChanged: (v) {
              setState(() => _reportFilter = v.first);
              _reloadAll();
            },
          ),
        ),
        Expanded(
          child: _reports.isEmpty
              ? Center(child: Text(app.t('admin_reports_empty')))
              : ListView.builder(
                  itemCount: _reports.length,
                  itemBuilder: (_, i) {
                    final r = _reports[i];
                    final target = (r['target_username'] ?? '').toString();
                    final status = (r['status'] ?? 'open').toString();
                    final type = (r['target_type'] ?? 'user').toString();
                    final targetId = (r['target_id'] ?? '').toString();
                    final deletable = const ['post', 'story', 'comment', 'message'].contains(type) && targetId.isNotEmpty;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Chip(label: Text(app.t('ban_reason_${_reportReasonToBan(r['reason_code'])}'))),
                                const SizedBox(width: 6),
                                Chip(label: Text(app.t('report_target_$type'))),
                                const Spacer(),
                                Text(app.t('report_status_$status'),
                                    style: TextStyle(
                                        color: status == 'open' ? JuzzioColors.amber600 : JuzzioColors.emerald500,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                            Text(
                              app
                                  .t('admin_report_line')
                                  .replaceAll('{reporter}', '@${r['reporter_username'] ?? '?'}')
                                  .replaceAll('{target}', target.isEmpty ? '—' : '@$target'),
                            ),
                            if ((r['details'] ?? '').toString().trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('“${r['details']}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                              ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (status == 'open')
                                  OutlinedButton(
                                    onPressed: () => _guard(() async {
                                      await _f.adminSetReportStatus(widget.token, r['id'].toString(), 'resolved');
                                      await _reloadAll();
                                    }),
                                    child: Text(app.t('admin_mark_resolved')),
                                  ),
                                if (status == 'open')
                                  OutlinedButton(
                                    onPressed: () => _guard(() async {
                                      await _f.adminSetReportStatus(widget.token, r['id'].toString(), 'dismissed');
                                      await _reloadAll();
                                    }),
                                    child: Text(app.t('admin_dismiss')),
                                  ),
                                if (deletable)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(foregroundColor: JuzzioColors.red500),
                                    onPressed: () => _deleteContent(type, targetId),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    label: Text(_al('İçeriği sil', 'Delete content', 'Inhalt löschen')),
                                  ),
                                if (r['target_owner_id'] != null)
                                  OutlinedButton.icon(
                                    onPressed: () => _openUserDetail(r['target_owner_id'].toString()),
                                    icon: const Icon(Icons.person_search_rounded, size: 18),
                                    label: Text(_al('Kullanıcı', 'User', 'Nutzer')),
                                  ),
                                if (r['target_owner_id'] != null && r['target_banned'] != true)
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500),
                                    onPressed: () => _banFlow(r['target_owner_id'].toString(), '@$target'),
                                    child: Text(app.t('admin_ban')),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
  }

  String _reportReasonToBan(dynamic code) {
    final c = (code ?? 'other').toString();
    if (c == 'inappropriate') return 'inappropriate_content';
    return kJuzzioBanReasons.contains(c) ? c : 'other';
  }

  Widget _buildBans(JuzzioAppController app) {
    if (_bans.isEmpty) return Center(child: Text(app.t('admin_bans_empty')));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _bans.length,
      itemBuilder: (_, i) {
        final b = _bans[i];
        final until = DateTime.tryParse((b['expires_at'] ?? '').toString());
        return ListTile(
          leading: Icon(until != null ? Icons.timer_rounded : Icons.block_rounded,
              color: until != null ? JuzzioColors.amber600 : JuzzioColors.red500),
          title: Text('@${b['username'] ?? '?'}'),
          subtitle: Text(
            '${app.t('ban_reason_${kJuzzioBanReasons.contains(b['reason_code']) ? b['reason_code'] : 'other'}')}'
            ' • ${app.t('admin_banned_devices').replaceAll('{n}', '${b['banned_devices'] ?? 0}')}'
            '${until != null ? ' • ${_al('bitiş', 'until', 'bis')} ${_fmtDate(until)}' : ''}',
          ),
          onTap: b['user_id'] != null ? () => _openUserDetail(b['user_id'].toString()) : null,
          trailing: TextButton(onPressed: () => _unban(b['user_id'].toString()), child: Text(app.t('admin_unban'))),
        );
      },
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _buildModeration(bool isDark) {
    final types = <List<String>>[
      ['post', _al('Gönderi', 'Post', 'Beitrag')],
      ['story', _al('Hikâye', 'Story', 'Story')],
      ['comment', _al('Yorum', 'Comment', 'Kommentar')],
      ['message', _al('Mesaj', 'Message', 'Nachricht')],
    ];
    final openContentReports = _reports
        .where((r) => (r['status'] ?? '') == 'open' && const ['post', 'story', 'comment', 'message'].contains(r['target_type']))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Kimliğe göre içerik sil', 'Delete content by ID', 'Inhalt per ID löschen'), Icons.delete_forever_rounded, isDark),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in types)
                    ChoiceChip(label: Text(t[1]), selected: _modType == t[0], onSelected: (_) => setState(() => _modType = t[0])),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modId,
                decoration: InputDecoration(
                  labelText: _al('İçerik kimliği (UUID)', 'Content ID (UUID)', 'Inhalts-ID (UUID)'),
                  prefixIcon: const Icon(Icons.fingerprint_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500),
                onPressed: () => _deleteContent(_modType, _modId.text),
                icon: const Icon(Icons.delete_rounded),
                label: Text(_al('Sil', 'Delete', 'Löschen')),
              ),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Şikâyet edilen içerikler', 'Reported content', 'Gemeldete Inhalte'), Icons.report_rounded, isDark),
              if (openContentReports.isEmpty)
                Text(_al('Bekleyen içerik şikâyeti yok 🎉', 'No pending content reports 🎉', 'Keine offenen Inhaltsmeldungen 🎉')),
              for (final r in openContentReports)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_rounded, color: JuzzioColors.amber600),
                  title: Text('${JuzzioAppController.instance.t('report_target_${r['target_type']}')} • @${r['target_username'] ?? '?'}'),
                  subtitle: Text((r['details'] ?? '').toString().isEmpty ? '${r['target_id']}' : '${r['details']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500),
                    onPressed: () => _deleteContent(r['target_type'].toString(), (r['target_id'] ?? '').toString()),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBroadcast(bool isDark) {
    final audiences = <List<String>>[
      ['all', _al('Herkes', 'Everyone', 'Alle')],
      ['online', _al('Şu an çevrimiçi', 'Online now', 'Gerade online')],
      ['active_week', _al('Son 7 gün aktif', 'Active last 7 days', 'Letzte 7 Tage aktiv')],
      ['verified', _al('Mavi tikliler', 'Verified', 'Verifizierte')],
    ];
    InputDecoration deco(String l, IconData i) => InputDecoration(
          labelText: l,
          prefixIcon: Icon(i),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        );
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Anlık bildirim / duyuru', 'Push / announcement', 'Push / Ankündigung'), Icons.campaign_rounded, isDark),
              TextField(controller: _bcTitle, maxLength: 80, decoration: deco(_al('Başlık', 'Title', 'Titel'), Icons.title_rounded)),
              const SizedBox(height: 6),
              TextField(
                controller: _bcBody,
                maxLength: 400,
                minLines: 3,
                maxLines: 6,
                decoration: deco(_al('Mesaj', 'Message', 'Nachricht'), Icons.notes_rounded),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bcImage,
                keyboardType: TextInputType.url,
                decoration: deco(_al('Görsel bağlantısı (isteğe bağlı, https)', 'Image link (optional, https)', 'Bildlink (optional, https)'),
                    Icons.image_rounded),
              ),
              const SizedBox(height: 12),
              Text(_al('Kitle', 'Audience', 'Zielgruppe'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in audiences)
                    ChoiceChip(label: Text(a[1]), selected: _bcAudience == a[0], onSelected: (_) => setState(() => _bcAudience = a[0])),
                ],
              ),
              const SizedBox(height: 14),
              // Önizleme
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : JuzzioColors.slate100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF636366), Color(0xFF3A3A3C)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_bcTitle, _bcBody]),
                        builder: (_, __) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_bcTitle.text.isEmpty ? 'Juzzio' : _bcTitle.text, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(_bcBody.text.isEmpty ? _al('Önizleme', 'Preview', 'Vorschau') : _bcBody.text,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sendBroadcast,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(_al('Gönder', 'Send', 'Senden')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReleases(bool isDark) {
    InputDecoration deco(String l, IconData i) => InputDecoration(
          labelText: l,
          prefixIcon: Icon(i),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        );
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Yeni sürüm yayınla (OTA)', 'Publish new version (OTA)', 'Neue Version veröffentlichen (OTA)'),
                  Icons.rocket_launch_rounded, isDark),
              Text(
                _al(
                  'Önce GitHub Actions ile APK\'yı derleyip sürüme ekleyin. Burada yayınladığınızda kullanıcılara bildirim gider ve uygulama içinden indirip kurarlar.',
                  'Build the APK with GitHub Actions and attach it to a release first. Publishing here notifies users, who install it in-app.',
                  'Erstelle zuerst die APK mit GitHub Actions. Beim Veröffentlichen werden Nutzer benachrichtigt und installieren in der App.',
                ),
                style: const TextStyle(fontSize: 12.5, color: JuzzioColors.slate500, height: 1.35),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _relName, decoration: deco(_al('Sürüm (0.4.1)', 'Version (0.4.1)', 'Version (0.4.1)'), Icons.tag_rounded))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _relCode,
                      keyboardType: TextInputType.number,
                      decoration: deco(_al('Kod', 'Code', 'Code'), Icons.numbers_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _relUrl,
                keyboardType: TextInputType.url,
                decoration: deco(_al('APK bağlantısı (https)', 'APK link (https)', 'APK-Link (https)'), Icons.link_rounded).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _al('GitHub bağlantısını oluştur', 'Build GitHub link', 'GitHub-Link erzeugen'),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    onPressed: _fillReleaseFromGithub,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _al('Boş bırakırsan notlar GitHub sürüm sayfasından otomatik çekilir.',
                    'Leave empty to fetch notes automatically from the GitHub release.',
                    'Leer lassen: Hinweise werden automatisch von GitHub geladen.'),
                style: const TextStyle(fontSize: 12, color: JuzzioColors.slate500),
              ),
              const SizedBox(height: 6),
              TextField(controller: _relReason, minLines: 2, maxLines: 4, decoration: deco(_al('Neden getirildi? (boşsa GitHub\'dan)', 'Why? (empty = from GitHub)', 'Warum? (leer = GitHub)'), Icons.help_outline_rounded)),
              const SizedBox(height: 8),
              TextField(controller: _relFeatures, minLines: 2, maxLines: 8, decoration: deco(_al('Yeni özellikler (her satıra bir tane)', 'New features (one per line)', 'Neue Funktionen (eine pro Zeile)'), Icons.auto_awesome_rounded)),
              const SizedBox(height: 8),
              TextField(controller: _relFixes, minLines: 2, maxLines: 8, decoration: deco(_al('Düzeltilen hatalar (her satıra bir tane)', 'Fixed bugs (one per line)', 'Behobene Fehler (eine pro Zeile)'), Icons.build_circle_rounded)),
              const SizedBox(height: 8),
              TextField(controller: _relSecurity, minLines: 1, maxLines: 6, decoration: deco(_al('Güvenlik ve gizlilik (her satıra bir tane)', 'Security and privacy (one per line)', 'Sicherheit und Datenschutz (eine pro Zeile)'), Icons.verified_user_rounded)),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(_al('İngilizce ayrıntılar (isteğe bağlı)', 'English details (optional)', 'Englische Details (optional)')),
                children: [
                  TextField(controller: _relReasonEn, minLines: 1, maxLines: 4, decoration: deco('Why (EN)', Icons.help_outline_rounded)),
                  const SizedBox(height: 8),
                  TextField(controller: _relFeaturesEn, minLines: 1, maxLines: 8, decoration: deco('Features (EN)', Icons.auto_awesome_rounded)),
                  const SizedBox(height: 8),
                  TextField(controller: _relFixesEn, minLines: 1, maxLines: 8, decoration: deco('Fixes (EN)', Icons.build_circle_rounded)),
                  const SizedBox(height: 8),
                  TextField(controller: _relSecurityEn, minLines: 1, maxLines: 6, decoration: deco('Security (EN)', Icons.verified_user_rounded)),
                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 8),
              TextField(controller: _relTr, minLines: 2, maxLines: 5, decoration: deco(_al('Notlar (Türkçe)', 'Notes (Turkish)', 'Notizen (Türkisch)'), Icons.notes_rounded)),
              const SizedBox(height: 8),
              TextField(controller: _relEn, minLines: 2, maxLines: 5, decoration: deco(_al('Notlar (İngilizce)', 'Notes (English)', 'Notizen (Englisch)'), Icons.notes_rounded)),
              const SizedBox(height: 8),
              TextField(controller: _relDe, minLines: 2, maxLines: 5, decoration: deco(_al('Notlar (Almanca)', 'Notes (German)', 'Notizen (Deutsch)'), Icons.notes_rounded)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _relMandatory,
                onChanged: (v) => setState(() => _relMandatory = v),
                title: Text(_al('Zorunlu güncelleme', 'Mandatory update', 'Pflicht-Update')),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _publishRelease,
                  icon: const Icon(Icons.publish_rounded),
                  label: Text(_al('Yayınla', 'Publish', 'Veröffentlichen')),
                ),
              ),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Yayınlanan sürümler', 'Published versions', 'Veröffentlichte Versionen'), Icons.history_rounded, isDark),
              if (_releases.isEmpty) Text(_al('Henüz sürüm yok.', 'No versions yet.', 'Noch keine Versionen.')),
              for (final r in _releases)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: JuzzioColors.indigo500.withOpacity(0.15),
                    child: Icon(r['is_mandatory'] == true ? Icons.priority_high_rounded : Icons.android_rounded, color: JuzzioColors.indigo500),
                  ),
                  title: Text('v${r['version_name']} (${r['version_code']})', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text((r['notes_tr'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500),
                    onPressed: () async {
                      final name = (r['version_name'] ?? '').toString();
                      final ok = await _confirm(_al('v$name silinsin mi?', 'Delete v$name?', 'v$name löschen?'),
                          _al('Kullanıcılar bu sürüm için artık bildirim almaz.', 'Users will no longer be notified about this version.',
                              'Nutzer werden für diese Version nicht mehr benachrichtigt.'));
                      if (!ok) return;
                      await _guard(() async {
                        await _f.adminDeleteRelease(widget.token, name);
                        await _reloadAll();
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(bool isDark) {
    Widget flag(String key, bool value, String title, String sub, IconData icon) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: (v) => _setFlag(key, v),
        secondary: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(sub),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Bakım modu', 'Maintenance mode', 'Wartungsmodus'), Icons.construction_rounded, isDark),
              flag(
                'maintenance_mode',
                _config.maintenanceMode,
                _al('Uygulamayı bakıma al', 'Put the app in maintenance', 'App in Wartung versetzen'),
                _al('Yöneticiler hariç herkes bakım ekranını görür.', 'Everyone except admins sees the maintenance screen.',
                    'Alle außer Admins sehen den Wartungsbildschirm.'),
                Icons.power_settings_new_rounded,
              ),
              TextField(
                controller: _maintMsg,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _al('Bakım mesajı', 'Maintenance message', 'Wartungsnachricht'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save_rounded),
                    onPressed: () => _setFlag('maintenance_message', _maintMsg.text.trim()),
                  ),
                ),
              ),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Özellik bayrakları', 'Feature flags', 'Feature-Flags'), Icons.flag_circle_rounded, isDark),
              flag('signups_enabled', _config.signupsEnabled, _al('Yeni kayıtlar', 'New sign-ups', 'Neue Registrierungen'),
                  _al('Kapalıyken yeni hesap açılamaz.', 'When off, no new accounts can be created.', 'Wenn aus, keine neuen Konten.'),
                  Icons.person_add_rounded),
              flag('stories_enabled', _config.storiesEnabled, _al('Hikâyeler', 'Stories', 'Storys'),
                  _al('Hikâye paylaşımını aç/kapat.', 'Enable or disable story sharing.', 'Story-Teilen ein-/ausschalten.'),
                  Icons.auto_awesome_motion_rounded),
              flag('live_translation_enabled', _config.liveTranslationEnabled, _al('Canlı çeviri', 'Live translation', 'Live-Übersetzung'),
                  _al('Aramalarda canlı altyazı/çeviri.', 'Live captions/translation in calls.', 'Live-Untertitel in Anrufen.'),
                  Icons.translate_rounded),
              flag('beauty_filter_enabled', _config.beautyFilterEnabled, _al('Güzellik filtresi', 'Beauty filter', 'Beauty-Filter'),
                  _al('Görüntülü aramada güzelleştirme.', 'Beautification in video calls.', 'Verschönerung in Videoanrufen.'),
                  Icons.face_retouching_natural_rounded),
              flag('chick_game_enabled', _config.chickGameEnabled, _al('Civciv oyunu', 'Chick game', 'Küken-Spiel'),
                  _al('Sohbetlerdeki civciv yumurtası.', 'The chick egg in chats.', 'Das Küken-Ei in Chats.'),
                  Icons.egg_alt_rounded),
              flag('posts_enabled', _config.postsEnabled, _al('Gönderiler', 'Posts', 'Beiträge'),
                  _al('Fotoğraf/video/yazı paylaşımı.', 'Photo/video/text posting.', 'Foto-/Video-/Text-Beiträge.'),
                  Icons.post_add_rounded),
              flag('global_feed_enabled', _config.globalFeedEnabled, _al('Küresel akış', 'Global feed', 'Globaler Feed'),
                  _al('Dünyadan paylaşımlar sekmesi.', 'The world posts tab.', 'Der Welt-Beiträge-Tab.'),
                  Icons.public_rounded),
              flag('calls_enabled', _config.callsEnabled, _al('Aramalar', 'Calls', 'Anrufe'),
                  _al('Sesli/görüntülü arama başlatma.', 'Starting voice/video calls.', 'Sprach-/Videoanrufe starten.'),
                  Icons.call_rounded),
              flag('group_creation_enabled', _config.groupCreationEnabled, _al('Grup oluşturma', 'Group creation', 'Gruppen erstellen'),
                  _al('Yeni grup kurulabilir.', 'New groups can be created.', 'Neue Gruppen können erstellt werden.'),
                  Icons.group_add_rounded),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('İçerik denetimi', 'Content safety', 'Inhaltssicherheit'), Icons.shield_rounded, isDark),
              flag('call_moderation_enabled', _config.callModerationEnabled,
                  _al('Görüntülü aramada müstehcenlik denetimi', 'Explicit video detection in calls', 'Erkennung anstößiger Videos'),
                  _al('Kişinin kendi kamerasından belirli aralıklarla kare denetlenir; ihlalde arama kapanır.',
                      'Frames from the user\'s own camera are checked periodically; violations end the call.',
                      'Bilder der eigenen Kamera werden regelmäßig geprüft; Verstöße beenden den Anruf.'),
                  Icons.videocam_off_rounded),
              flag('speech_moderation_enabled', _config.speechModerationEnabled,
                  _al('Aramada ağır argo denetimi', 'Abusive speech detection in calls', 'Erkennung beleidigender Sprache'),
                  _al('Aynı aramada ikinci ağır ifadede ceza uygulanır.', 'A strike is applied on the second abusive phrase in a call.',
                      'Beim zweiten beleidigenden Ausdruck im Anruf gilt ein Verstoß.'),
                  Icons.record_voice_over_rounded),
              flag('avatar_moderation_enabled', _config.avatarModerationEnabled,
                  _al('Profil fotoğrafı denetimi', 'Profile photo review', 'Profilfoto-Prüfung'),
                  _al('Müstehcen fotoğraflar profile eklenemez.', 'Explicit photos cannot be used as profile photos.',
                      'Anstößige Fotos können nicht als Profilfoto verwendet werden.'),
                  Icons.no_photography_rounded),
              const SizedBox(height: 6),
              Text(
                _al('Kare denetim aralığı: ${_config.callModerationIntervalSec} sn', 'Frame check interval: ${_config.callModerationIntervalSec} s',
                    'Prüfintervall: ${_config.callModerationIntervalSec} s'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: _config.callModerationIntervalSec.toDouble(),
                min: 3,
                max: 30,
                divisions: 27,
                label: '${_config.callModerationIntervalSec}',
                onChanged: (_) {},
                onChangeEnd: (v) => _setFlag('call_moderation_interval_sec', v.round()),
              ),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Varsayılan cam teması', 'Default glass theme', 'Standard-Glasdesign'), Icons.blur_on_rounded, isDark),
              Text(
                _al('Yalnızca uygulamayı ilk kez açan yeni kullanıcılara bir kez uygulanır; tema seçmiş kimse etkilenmez. Aynı temalar herkesin Ayarlar → Görünüm → Cam teması listesinde de var.', 'Applied once to brand-new users only; nobody who picked a theme is affected. The same themes are in everyone\'s Settings → Appearance.',
                    'Gilt für alle Nutzer ohne eigenes Design.'),
                style: TextStyle(color: isDark ? JuzzioGlassTokens.textSecondary : JuzzioColors.slate600, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final pal in kJuzzioAuroraPalettes)
                    GestureDetector(
                      onTap: () => _setFlag('default_glass_palette', pal.id),
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [pal.swatchA, pal.swatchB]),
                              border: Border.all(
                                color: _config.defaultGlassPalette == pal.id ? Colors.white : Colors.white24,
                                width: _config.defaultGlassPalette == pal.id ? 3 : 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(pal.label(JuzzioAppController.instance.uiLang), style: const TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    ),
                ],
              ),
              // v0.8.3: küresel tema stüdyosu ve personel rolleri (RBAC)
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => JuzzioAdminThemeStudioPage(token: widget.token))),
                  icon: const Icon(Icons.brush_rounded),
                  label: Text(_al('Küresel Tema Stüdyosu', 'Global Theme Studio', 'Globales Design-Studio')),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => JuzzioAdminStaffPage(token: widget.token))),
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: Text(_al('Personel rolleri', 'Staff roles', 'Mitarbeiterrollen')),
                ),
              ]),
            ],
          ),
        ),
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_al('Duyuru bandı', 'Announcement banner', 'Ankündigungsbanner'), Icons.campaign_rounded, isDark),
              TextField(
                controller: _bannerMsg,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _al('Ana ekranın üstünde gösterilir (boş = kapalı)', 'Shown on top of the home screen (empty = off)',
                      'Oben auf dem Startbildschirm (leer = aus)'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save_rounded),
                    onPressed: () => _setFlag('announcement_banner', _bannerMsg.text.trim()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudit(bool isDark) {
    if (_audit.isEmpty) return Center(child: Text(_al('Kayıt yok', 'No entries', 'Keine Einträge')));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _audit.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = _audit[i];
        final when = DateTime.tryParse((a['created_at'] ?? '').toString());
        final details = a['details'];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.bolt_rounded, color: JuzzioColors.indigo500),
          title: Text('${a['action']} • ${a['target'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '@${a['admin_username'] ?? '?'}${when != null ? ' • ${_fmtDate(when)}' : ''}'
            '${details is Map && details.isNotEmpty ? '\n$details' : ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

// =============================================================================
// Kullanıcı ayrıntı sayfası
// =============================================================================
class _AdminUserDetailSheet extends StatefulWidget {
  final String token;
  final String userId;
  final Future<void> Function(String handle) onBan;
  final Future<void> Function() onUnban;
  final Future<void> Function(String handle) onSuspend;
  final Future<void> Function(String handle) onWarn;

  const _AdminUserDetailSheet({
    required this.token,
    required this.userId,
    required this.onBan,
    required this.onUnban,
    required this.onSuspend,
    required this.onWarn,
  });

  @override
  State<_AdminUserDetailSheet> createState() => _AdminUserDetailSheetState();
}

class _AdminUserDetailSheetState extends State<_AdminUserDetailSheet> {
  final JuzzioFeaturesService _f = JuzzioFeaturesService.instance;
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _f.adminUserDetail(widget.token, widget.userId);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() action, String okText) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(okText), backgroundColor: JuzzioColors.emerald500),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: JuzzioColors.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final h = MediaQuery.of(context).size.height;
    if (d == null) {
      return SizedBox(
        height: 260,
        child: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final handle = '@${d['username'] ?? ''}';
    final avatar = (d['avatar_url'] ?? '').toString();
    final verified = d['is_verified'] == true;
    final banned = d['banned'] == true;
    final role = (d['app_role'] ?? 'user').toString();
    final email = (d['email'] ?? '').toString();
    final ban = d['ban'] is Map ? Map<String, dynamic>.from(d['ban'] as Map) : null;
    final created = DateTime.tryParse((d['created_at'] ?? '').toString());
    final lastSeen = DateTime.tryParse((d['last_seen'] ?? '').toString());
    String fmt(DateTime? t) {
      if (t == null) return '—';
      final l = t.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
    }

    Widget metric(String label, Object? v) => Expanded(
          child: Column(
            children: [
              Text('${v ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: JuzzioColors.slate500)),
            ],
          ),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.88),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty ? const Icon(Icons.person_rounded, size: 30) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('${d['display_name'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded, color: JuzzioColors.sky500, size: 20),
                        ],
                      ],
                    ),
                    Text(handle, style: const TextStyle(color: JuzzioColors.slate500)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 9, color: d['is_online'] == true ? JuzzioColors.emerald500 : JuzzioColors.slate400),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            d['is_online'] == true ? _al('Çevrimiçi', 'Online', 'Online') : '${_al('Son görülme', 'Last seen', 'Zuletzt gesehen')}: ${fmt(lastSeen)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (email.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email_rounded),
              title: Text(email),
              subtitle: Text('${_al('Kayıt', 'Joined', 'Beigetreten')}: ${fmt(created)}'),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: email));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_al('Kopyalandı', 'Copied', 'Kopiert'))));
                },
              ),
            ),
          Row(
            children: [
              metric(_al('Arkadaş', 'Friends', 'Freunde'), d['friends']),
              metric(_al('Mesaj', 'Messages', 'Nachrichten'), d['messages']),
              metric(_al('Gönderi', 'Posts', 'Beiträge'), d['posts']),
              metric(_al('Cihaz', 'Devices', 'Geräte'), d['devices']),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              metric(_al('Sesli dk', 'Voice min', 'Sprach-Min.'), d['voice_minutes']),
              metric(_al('Görüntülü dk', 'Video min', 'Video-Min.'), d['video_minutes']),
              metric(_al('Şikâyet', 'Reports', 'Meldungen'), d['reports_against']),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.admin_panel_settings_rounded),
            label: Text(_al('Güç araçları: düzenle · ihlal · oturum · sil', 'Power tools: edit · strike · sessions · delete',
                'Werkzeuge: bearbeiten · Verstoß · Sitzungen · löschen')),
            onPressed: () async {
              await showJuzzioAdminUserPowerSheet(
                context,
                token: widget.token,
                userId: widget.userId,
                username: '${d['username'] ?? ''}',
                displayName: '${d['display_name'] ?? ''}',
              );
              if (mounted) await _load();
            },
          ),
          if (banned && ban != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JuzzioColors.red500.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
              child: Text(
                '${_al('Engel', 'Ban', 'Sperre')}: ${ban['reason_code'] ?? ''}'
                '${ban['expires_at'] != null ? ' • ${_al('bitiş', 'until', 'bis')} ${fmt(DateTime.tryParse(ban['expires_at'].toString()))}' : ' • ${_al('süresiz', 'permanent', 'dauerhaft')}'}',
                style: const TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const Divider(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.verified_rounded, color: JuzzioColors.sky500),
            title: Text(_al('Mavi tik', 'Blue tick', 'Blauer Haken'), style: const TextStyle(fontWeight: FontWeight.w800)),
            value: verified,
            onChanged: _busy
                ? null
                : (v) => _run(
                      () => _f.adminSetVerified(widget.token, widget.userId, v),
                      v ? _al('Mavi tik verildi.', 'Blue tick granted.', 'Blauer Haken vergeben.') : _al('Mavi tik kaldırıldı.', 'Blue tick removed.', 'Blauer Haken entfernt.'),
                    ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_rounded, color: JuzzioColors.emerald500),
            title: Text(_al('Rol', 'Role', 'Rolle'), style: const TextStyle(fontWeight: FontWeight.w800)),
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'user', label: Text(_al('Kullanıcı', 'User', 'Nutzer'))),
                ButtonSegment(value: 'moderator', label: Text(_al('Moderatör', 'Moderator', 'Moderator'))),
              ],
              selected: {role == 'moderator' ? 'moderator' : 'user'},
              onSelectionChanged: _busy
                  ? null
                  : (v) => _run(() => _f.adminSetAppRole(widget.token, widget.userId, v.first),
                      _al('Rol güncellendi.', 'Role updated.', 'Rolle aktualisiert.')),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => widget.onWarn(handle),
                icon: const Icon(Icons.warning_amber_rounded),
                label: Text(_al('Uyarı gönder', 'Send warning', 'Verwarnen')),
              ),
              OutlinedButton.icon(
                onPressed: _busy || email.isEmpty
                    ? null
                    : () => _run(() => _f.adminSendPasswordReset(widget.token, widget.userId),
                        _al('Şifre sıfırlama e-postası gönderildi.', 'Password reset email sent.', 'E-Mail zum Zurücksetzen gesendet.')),
                icon: const Icon(Icons.lock_reset_rounded),
                label: Text(_al('Şifre sıfırla', 'Reset password', 'Passwort zurücksetzen')),
              ),
              if (!banned)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: JuzzioColors.amber700),
                  onPressed: _busy ? null : () => widget.onSuspend(handle),
                  icon: const Icon(Icons.timer_rounded),
                  label: Text(_al('Süreli askıya al', 'Suspend', 'Zeitweise sperren')),
                ),
              if (!banned)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500),
                  onPressed: _busy ? null : () => widget.onBan(handle),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(JuzzioAppController.instance.t('admin_ban')),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: JuzzioColors.emerald500),
                  onPressed: _busy ? null : widget.onUnban,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(JuzzioAppController.instance.t('admin_unban')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Grafikler ve kutucuklar
// =============================================================================
class _StatTileData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatTileData(this.label, this.value, this.icon, this.color);
}

class _StatTile extends StatelessWidget {
  final _StatTileData data;
  final bool isDark;
  const _StatTile({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // v0.8.0: cam istatistik karosu, cam ikon kapsülü (renk lekesi yok)
    return JuzzioGlass(
      radius: 20,
      blur: false,
      color: JuzzioGlassTokens.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: isDark ? 0.22 : 0.85), Colors.white.withValues(alpha: isDark ? 0.06 : 0.35)],
              ),
              border: Border.all(color: JuzzioGlassTokens.borderStrong),
            ),
            child: Icon(data.icon, color: Color.lerp(data.color, JuzzioGlassTokens.textPrimary, 0.35), size: 18),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(data.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: JuzzioGlassTokens.textPrimary)),
          ),
          Text(data.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: JuzzioGlassTokens.textSecondary)),
        ],
      ),
    );
  }
}

const Color _kMsgColor = JuzzioColors.indigo500;
const Color _kCallColor = JuzzioColors.emerald500;

class _LegendRow extends StatelessWidget {
  final bool isDark;
  const _LegendRow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(t, style: const TextStyle(fontSize: 12)),
          ],
        );
    return Wrap(
      spacing: 14,
      children: [
        dot(_kMsgColor, _al('Mesajlar', 'Messages', 'Nachrichten')),
        dot(_kCallColor, _al('Aramalar', 'Calls', 'Anrufe')),
      ],
    );
  }
}

class _SeriesChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  final bool isDark;
  const _SeriesChart({required this.series, required this.isDark});

  @override
  Widget build(BuildContext context) {
    List<double> pick(String k) => series.map((m) => ((m[k] as num?) ?? 0).toDouble()).toList();
    return CustomPaint(
      size: Size.infinite,
      painter: _LinePainter(
        lines: [pick('messages'), pick('calls')],
        colors: const [_kMsgColor, _kCallColor],
        labels: series.map((m) => (m['day'] ?? '').toString()).toList(),
        gridColor: isDark ? Colors.white12 : JuzzioColors.slate200,
        textColor: isDark ? Colors.white60 : JuzzioColors.slate500,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<List<double>> lines;
  final List<Color> colors;
  final List<String> labels;
  final Color gridColor;
  final Color textColor;

  _LinePainter({
    required this.lines,
    required this.colors,
    required this.labels,
    required this.gridColor,
    required this.textColor,
  });

  void _text(Canvas canvas, String t, Offset at, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: textColor, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (align == TextAlign.center) dx -= tp.width / 2;
    if (align == TextAlign.right) dx -= tp.width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 20.0, top = 6.0;
    final w = size.width - left - 6;
    final h = size.height - bottom - top;
    if (w <= 0 || h <= 0) return;
    var maxV = 1.0;
    for (final l in lines) {
      for (final v in l) {
        if (v > maxV) maxV = v;
      }
    }
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      final v = maxV * (4 - i) / 4;
      _text(canvas, v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.round().toString(), Offset(left - 4, y - 6),
          align: TextAlign.right);
    }
    final n = lines.isEmpty ? 0 : lines.first.length;
    if (n < 2) return;
    double xAt(int i) => left + w * i / (n - 1);
    double yAt(double v) => top + h - (v / maxV) * h;
    for (var li = 0; li < lines.length; li++) {
      final data = lines[li];
      final color = colors[li % colors.length];
      final path = Path();
      final fill = Path();
      for (var i = 0; i < data.length; i++) {
        final p = Offset(xAt(i), yAt(data[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
          fill.moveTo(p.dx, top + h);
          fill.lineTo(p.dx, p.dy);
        } else {
          final prev = Offset(xAt(i - 1), yAt(data[i - 1]));
          final cx = (prev.dx + p.dx) / 2;
          path.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
          fill.cubicTo(cx, prev.dy, cx, p.dy, p.dx, p.dy);
        }
      }
      fill
        ..lineTo(xAt(data.length - 1), top + h)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withOpacity(0.28), color.withOpacity(0.0)],
          ).createShader(Rect.fromLTWH(left, top, w, h)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < labels.length; i += 3) {
      final raw = labels[i];
      final short = raw.length >= 10 ? '${raw.substring(8, 10)}.${raw.substring(5, 7)}' : raw;
      _text(canvas, short, Offset(xAt(i), top + h + 5), align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.lines != lines || old.gridColor != gridColor || old.textColor != textColor;
}

class _BarChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  final String field;
  final bool isDark;
  const _BarChart({required this.series, required this.field, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final values = series.map((m) => ((m[field] as num?) ?? 0).toDouble()).toList();
    var maxV = 1.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (values[i] > 0)
                    Text(values[i].round().toString(), style: const TextStyle(fontSize: 9, color: JuzzioColors.slate500)),
                  const SizedBox(height: 2),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: (values[i] / maxV).clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFF8E8E93), Color(0xFFF2F2F7)],
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
