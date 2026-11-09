// =============================================================================
// JUZZIO v0.9.6 — Yönetici "Tanrı modu": Sistem sekmesi
//  Sağlık · Hatalar (otomatik çökme merkezi) · Depolama bakımı · Çoklu hesap ·
//  AI maliyeti/kotası · Sınırlar (ses/medya, minimum sürüm, kaba kuvvet) ·
//  Acil durum (yasal dışa aktarım, tüm oturumları kapat).
//  Kritik işlemler sunucuda YALNIZ şifreli süper yönetici oturumuyla çalışır ve
//  her biri denetim kaydına yazılır. Serbest SQL konsolu bilinçli olarak YOKTUR:
//  istemciden keyfi SQL çalıştırmak RLS ve denetim kaydını delip geçerdi; bunun
//  yerine önceden tanımlı, sınırlandırılmış bakım işlemleri sunulur.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

String _t(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

String _fmtBytes(num b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _when(Object? raw) {
  final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

class JuzzioAdminGodTab extends StatefulWidget {
  const JuzzioAdminGodTab({super.key, required this.token});
  final String token;

  @override
  State<JuzzioAdminGodTab> createState() => _JuzzioAdminGodTabState();
}

class _JuzzioAdminGodTabState extends State<JuzzioAdminGodTab> {
  final _db = SupabaseService.instance.client;
  String _section = 'health';
  bool _loading = false;
  String? _error;

  Map<String, dynamic> _health = const {};
  List<Map<String, dynamic>> _errors = const [];
  String _errorFilter = 'open';
  List<Map<String, dynamic>> _queue = const [];
  List<Map<String, dynamic>> _multi = const [];
  List<Map<String, dynamic>> _ai = const [];
  JuzzioAppConfig _cfg = const JuzzioAppConfig();
  Map<String, dynamic> _raw = const {};
  final Map<String, TextEditingController> _num = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _num.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _list(Object? r) => [for (final x in (r is List ? r : const [])) Map<String, dynamic>.from(x as Map)];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tk = widget.token;
      switch (_section) {
        case 'health':
          final r = await _db.rpc('admin_god_overview', params: {'p_token': tk});
          _health = r is Map ? Map<String, dynamic>.from(r) : {};
        case 'errors':
          _errors = _list(await _db.rpc('admin_list_app_errors', params: {'p_token': tk, 'p_status': _errorFilter, 'p_limit': 200}));
        case 'storage':
          _queue = _list(await _db.rpc('admin_storage_queue', params: {'p_token': tk, 'p_failed_only': false, 'p_limit': 200}));
        case 'multi':
          _multi = _list(await _db.rpc('admin_multi_accounts', params: {'p_token': tk, 'p_limit': 200}));
        case 'ai':
          _ai = _list(await _db.rpc('admin_ai_usage', params: {'p_token': tk, 'p_days': 1, 'p_limit': 100}));
          await _loadConfig();
        case 'limits':
          await _loadConfig();
      }
    } catch (e) {
      _error = SupabaseService.instance.friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadConfig() async {
    final r = await _db.rpc('get_app_config');
    _raw = r is Map ? Map<String, dynamic>.from(r) : {};
    _cfg = JuzzioAppConfig.fromMap(_raw);
  }

  void _snack(String text, {bool error = false}) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? JuzzioColors.red500 : null));

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null) _snack(ok);
      await _load();
    } catch (e) {
      final t = e.toString();
      _snack(
        t.contains('super_admin_required')
            ? _t('Bu işlem yalnız süper yönetici (şifreli oturum) ile yapılabilir.', 'Super admin (password session) required.', 'Nur Super-Admin.')
            : SupabaseService.instance.friendlyError(e),
        error: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    final fg = isDark ? Colors.white : JuzzioColors.ink;
    final sections = <(String, IconData, String)>[
      ('health', Icons.monitor_heart_rounded, _t('Sağlık', 'Health', 'Status')),
      ('errors', Icons.bug_report_rounded, _t('Hatalar', 'Crashes', 'Abstürze')),
      ('storage', Icons.cleaning_services_rounded, _t('Depolama', 'Storage', 'Speicher')),
      ('multi', Icons.devices_other_rounded, _t('Çoklu hesap', 'Multi-account', 'Mehrfachkonten')),
      ('ai', Icons.psychology_rounded, _t('AI kotası', 'AI quota', 'KI-Kontingent')),
      ('limits', Icons.tune_rounded, _t('Sınırlar', 'Limits', 'Grenzen')),
      ('danger', Icons.gpp_maybe_rounded, _t('Acil durum', 'Emergency', 'Notfall')),
    ];
    return JuzzioClothRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in sections)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(s.$2, size: 16),
                  label: Text(s.$3),
                  selected: _section == s.$1,
                  onSelected: (_) {
                    setState(() => _section = s.$1);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ...switch (_section) {
          'health' => _buildHealth(fg),
          'errors' => _buildErrors(fg),
          'storage' => _buildStorage(fg),
          'multi' => _buildMulti(fg),
          'ai' => _buildAi(fg),
          'limits' => _buildLimits(fg),
          _ => _buildDanger(fg),
        },
      ]),
    );
  }

  Widget _card(Widget child) => Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(12), child: child));

  Widget _metric(String label, Object? v, {Color? color}) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: (color ?? JuzzioColors.blue600).withValues(alpha: 0.12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${v ?? '—'}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ]),
      );

  List<Widget> _buildHealth(Color fg) {
    final h = _health;
    num n(String k) => (h[k] as num?) ?? 0;
    final warn = const Color(0xFFE11D48);
    return [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _metric(_t('Şu an çevrimiçi', 'Online now', 'Online'), h['online_now'], color: JuzzioColors.emerald400),
        _metric(_t('Aktif (24 sa)', 'Active (24h)', 'Aktiv (24h)'), h['active_24h']),
        _metric(_t('Aktif (7 gün)', 'Active (7d)', 'Aktiv (7T)'), h['active_7d']),
        _metric(_t('Toplam kullanıcı', 'Total users', 'Nutzer gesamt'), h['total_users']),
        _metric(_t('Yeni (24 sa)', 'New (24h)', 'Neu (24h)'), h['new_users_24h']),
        _metric(_t('Mesaj (24 sa)', 'Messages (24h)', 'Nachrichten (24h)'), h['messages_24h']),
        _metric(_t('Açık hata', 'Open crashes', 'Offene Abstürze'), h['errors_open'], color: n('errors_open') > 0 ? warn : null),
        _metric(_t('Ölümcül hata (24 sa)', 'Fatal (24h)', 'Fatal (24h)'), h['errors_fatal_24h'], color: n('errors_fatal_24h') > 0 ? warn : null),
        _metric(_t('Güvenlik olayı (24 sa)', 'Security events (24h)', 'Sicherheit (24h)'), h['security_events_24h']),
        _metric(_t('Yönetici giriş hatası (24 sa)', 'Admin login fails (24h)', 'Admin-Fehlversuche'), h['admin_login_fails_24h'],
            color: n('admin_login_fails_24h') > 3 ? warn : null),
        _metric(_t('Depolama kuyruğu', 'Storage queue', 'Speicher-Warteschlange'), h['storage_queue_pending']),
        _metric(_t('Kuyruk hatalı', 'Queue failed', 'Fehlgeschlagen'), h['storage_queue_failed'], color: n('storage_queue_failed') > 0 ? warn : null),
        _metric(_t('Ortak cihaz', 'Shared devices', 'Geteilte Geräte'), h['shared_devices']),
        _metric(_t('AI birimi (bugün)', 'AI units (today)', 'KI-Einheiten'), h['ai_units_today']),
        _metric(_t('Çeviri isteği (bugün)', 'Translations (today)', 'Übersetzungen'), h['translation_requests_today']),
        _metric(_t('Yönetici işlemi (24 sa)', 'Admin actions (24h)', 'Admin-Aktionen'), h['admin_actions_24h']),
        _metric(_t('Veritabanı boyutu', 'Database size', 'DB-Größe'), _fmtBytes(n('db_size_bytes'))),
      ]),
      const SizedBox(height: 14),
      Text(_t('En büyük tablolar (ölü satır = şişme göstergesi)', 'Largest tables (dead rows = bloat)', 'Größte Tabellen'),
          style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
      for (final t in _list(h['largest_tables']))
        ListTile(
          dense: true,
          leading: const Icon(Icons.table_chart_rounded),
          title: Text('${t['table']}'),
          subtitle: Text('${t['live_rows']} ${_t('satır', 'rows', 'Zeilen')} · ${t['dead_rows']} ${_t('ölü', 'dead', 'tot')}'),
          trailing: Text(_fmtBytes((t['bytes'] as num?) ?? 0)),
        ),
    ];
  }

  List<Widget> _buildErrors(Color fg) => [
        Wrap(spacing: 8, children: [
          for (final f in const ['open', 'resolved', 'ignored', 'all'])
            ChoiceChip(
              label: Text(switch (f) {
                'open' => _t('Açık', 'Open', 'Offen'),
                'resolved' => _t('Çözüldü', 'Resolved', 'Gelöst'),
                'ignored' => _t('Yok sayıldı', 'Ignored', 'Ignoriert'),
                _ => _t('Tümü', 'All', 'Alle'),
              }),
              selected: _errorFilter == f,
              onSelected: (_) {
                setState(() => _errorFilter = f);
                _load();
              },
            ),
        ]),
        const SizedBox(height: 8),
        if (!_loading && _errors.isEmpty) Text(_t('Kayıtlı hata yok 🎉', 'No crashes recorded 🎉', 'Keine Abstürze 🎉')),
        for (final e in _errors)
          _card(ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(e['is_fatal'] == true ? Icons.error_rounded : Icons.warning_amber_rounded,
                color: e['is_fatal'] == true ? JuzzioColors.red500 : const Color(0xFFFFA000)),
            title: Text('${e['error_type']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${e['app_version']} · ${e['platform']} · ×${e['occurrences']} · ${e['affected_users']} ${_t('kişi', 'users', 'Nutzer')} · ${_when(e['last_seen'])}'),
            children: [
              Align(alignment: Alignment.centerLeft, child: SelectableText('${e['message']}', style: const TextStyle(fontWeight: FontWeight.w600))),
              if ('${e['context']}'.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('↳ ${e['context']}')),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
                child: SelectableText('${e['stack']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(_t('Kopyala', 'Copy', 'Kopieren')),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${e['error_type']}: ${e['message']}\n${e['stack']}'));
                    _snack(_t('Kopyalandı', 'Copied', 'Kopiert'));
                  },
                ),
                if (e['status'] != 'resolved')
                  FilledButton.tonal(
                    onPressed: () => _run(() => _db.rpc('admin_set_app_error_status', params: {'p_token': widget.token, 'p_id': e['id'], 'p_status': 'resolved'})),
                    child: Text(_t('Çözüldü', 'Resolved', 'Gelöst')),
                  ),
                if (e['status'] != 'ignored')
                  TextButton(
                    onPressed: () => _run(() => _db.rpc('admin_set_app_error_status', params: {'p_token': widget.token, 'p_id': e['id'], 'p_status': 'ignored'})),
                    child: Text(_t('Yok say', 'Ignore', 'Ignorieren')),
                  ),
              ]),
            ],
          )),
      ];

  List<Widget> _buildStorage(Color fg) => [
        Text(
          _t('Silinen içeriklerin dosyaları kuyruğa girer ve "storage-cleanup" Edge Function\'ı tarafından silinir. 8 denemede silinemeyenler "hatalı" görünür.',
              'Files of deleted content are queued and removed by the "storage-cleanup" Edge Function. Items failing 8 times are marked failed.',
              'Dateien gelöschter Inhalte werden von storage-cleanup entfernt.'),
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            icon: const Icon(Icons.replay_rounded),
            label: Text(_t('Hatalıları yeniden dene', 'Retry failed', 'Erneut versuchen')),
            onPressed: () => _run(() => _db.rpc('admin_storage_queue_retry', params: {'p_token': widget.token}),
                ok: _t('Hatalı kalemler kuyruğa geri alındı', 'Failed items re-queued', 'Erneut eingereiht')),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.travel_explore_rounded),
            label: Text(_t('Öksüz medya tara', 'Scan orphan media', 'Verwaiste Medien suchen')),
            onPressed: () => _run(() async {
              final n = await _db.rpc('admin_enqueue_orphan_media', params: {'p_token': widget.token});
              _snack('${_t('Kuyruğa eklenen', 'Queued', 'Eingereiht')}: $n');
            }),
          ),
        ]),
        const SizedBox(height: 8),
        if (!_loading && _queue.isEmpty) Text(_t('Kuyruk boş', 'Queue empty', 'Leer')),
        for (final q in _queue)
          ListTile(
            dense: true,
            leading: Icon(((q['attempts'] as num?) ?? 0) >= 8 ? Icons.error_outline_rounded : Icons.hourglass_bottom_rounded,
                color: ((q['attempts'] as num?) ?? 0) >= 8 ? JuzzioColors.red500 : null),
            title: Text('${q['bucket']}/${q['object_name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${q['reason']} · ${_t('deneme', 'attempts', 'Versuche')} ${q['attempts']} · ${_when(q['enqueued_at'])}'
                '${'${q['last_error']}'.isNotEmpty ? ' · ${q['last_error']}' : ''}'),
          ),
      ];

  List<Widget> _buildMulti(Color fg) => [
        Text(
          _t('Aynı cihazda oturum açmış birden fazla hesap. IP adresi saklanmaz; tespit cihaz kimliğiyle yapılır ve kimlik maskelenir.',
              'Multiple accounts signed in on the same device. No IP addresses are stored; detection uses a masked device ID.',
              'Mehrere Konten auf demselben Gerät (keine IP-Speicherung).'),
          style: const TextStyle(fontSize: 12.5),
        ),
        if (!_loading && _multi.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_t('Ortak cihaz yok', 'No shared devices', 'Keine'))),
        for (final m in _multi)
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.smartphone_rounded),
              const SizedBox(width: 8),
              Expanded(child: Text('${m['device']} · ${m['accounts']} ${_t('hesap', 'accounts', 'Konten')}', style: const TextStyle(fontWeight: FontWeight.w800))),
              if (m['device_banned'] == true) Text(_t('cihaz yasaklı', 'device banned', 'gesperrt'), style: TextStyle(color: JuzzioColors.red500)),
            ]),
            for (final u in _list(m['users'])) Text('• ${u['display_name']} (@${u['username']}) · ${u['platform']} · ${_when(u['last_seen'])}'),
          ])),
      ];

  List<Widget> _buildAi(Color fg) => [
        Text(
          '${_t('Kullanıcı başına günlük kota', 'Daily quota per user', 'Tageskontingent')}: '
          '${_numValue('ai_daily_quota_per_user')}  (0 = ${_t('sınırsız', 'unlimited', 'unbegrenzt')})',
          style: TextStyle(fontWeight: FontWeight.w800, color: fg),
        ),
        _numberField('ai_daily_quota_per_user', _t('Günlük AI birimi (çeviri=1, sesli döküm=5)', 'Daily AI units (translation=1, transcription=5)', 'KI-Einheiten pro Tag'), 0, 100000),
        const SizedBox(height: 10),
        Text(_t('Bugün en çok AI kullananlar', 'Top AI users today', 'Top-KI-Nutzer heute'), style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        if (!_loading && _ai.isEmpty) Text(_t('Bugün kullanım yok', 'No usage today', 'Keine Nutzung')),
        for (final r in _ai)
          ListTile(
            dense: true,
            leading: CircleAvatar(child: Text('${r['units']}', style: const TextStyle(fontSize: 11))),
            title: Text('${r['display_name']} (@${r['username']})'),
            subtitle: Text((r['by_kind'] is Map ? (r['by_kind'] as Map).entries.map((e) => '${e.key}: ${e.value}').join(' · ') : '')),
          ),
      ];

  String _numValue(String key) => (_num[key]?.text.isNotEmpty ?? false) ? _num[key]!.text : '${_cfgValue(key)}';

  int _cfgValue(String key) {
    final v = _raw[key];
    if (v is num) return v.toInt();
    return switch (key) {
      'voice_max_seconds' => _cfg.voiceMaxSeconds,
      'audio_bitrate_kbps' => _cfg.audioBitrateKbps,
      'video_max_seconds' => _cfg.videoMaxSeconds,
      'min_supported_build' => _cfg.minSupportedBuild,
      'media_cache_max_mb' => _cfg.mediaCacheMaxMb,
      'media_cache_max_age_days' => _cfg.mediaCacheMaxAgeDays,
      'admin_bruteforce_max_fails' => 5,
      'admin_bruteforce_window_min' => 15,
      _ => 0,
    };
  }

  Widget _numberField(String key, String label, int min, int max) {
    final c = _num.putIfAbsent(key, () => TextEditingController());
    if (c.text.isEmpty && _raw.isNotEmpty) c.text = '${_cfgValue(key)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: label, helperText: '$min – $max'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(c.text.trim());
            if (v == null || v < min || v > max) {
              _snack('$min – $max', error: true);
              return;
            }
            _run(() => JuzzioFeaturesService.instance.adminSetSetting(widget.token, key, v), ok: _t('Kaydedildi', 'Saved', 'Gespeichert'));
          },
          child: Text(_t('Kaydet', 'Save', 'Speichern')),
        ),
      ]),
    );
  }

  List<Widget> _buildLimits(Color fg) => [
        Text(_t('Ses ve medya', 'Voice & media', 'Sprache & Medien'), style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        _numberField('voice_max_seconds', _t('Sesli mesaj azami süresi (sn)', 'Max voice message length (s)', 'Max. Sprachnachricht (s)'), 15, 900),
        _numberField('audio_bitrate_kbps', _t('Ses kalitesi (kbps, audio_bitrate)', 'Audio bitrate (kbps)', 'Audio-Bitrate (kbps)'), 16, 256),
        _numberField('video_max_seconds', _t('Video azami süresi (sn)', 'Max video length (s)', 'Max. Videolänge (s)'), 10, 600),
        const SizedBox(height: 16),
        Text(_t('Cihaz medya önbelleği', 'On-device media cache', 'Medien-Cache auf dem Gerät'), style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        Text(
          _t('Kullanıcıların cihazında saklanan fotoğraf/ses/video önbelleğinin üst sınırı. Aşılınca en uzun süredir açılmayan dosyalar silinir.',
              'Upper limit of the photo/voice/video cache on users\' devices. When exceeded, the least recently opened files are removed.',
              'Obergrenze des Medien-Caches auf den Geräten.'),
          style: const TextStyle(fontSize: 12),
        ),
        _numberField('media_cache_max_mb', _t('Önbellek sınırı (MB)', 'Cache limit (MB)', 'Cache-Grenze (MB)'), 50, 4096),
        _numberField('media_cache_max_age_days', _t('Dosya azami yaşı (gün, 0 = sınırsız)', 'Max file age (days, 0 = unlimited)', 'Max. Alter (Tage)'), 0, 365),
        const SizedBox(height: 16),
        Text(_t('Güvenlik', 'Security', 'Sicherheit'), style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
        Text(
          _t('Minimum sürüm: bu derleme numarasının altındaki uygulamalar "Güncelleme gerekli" ekranında bekler (yöneticiler hariç). Yalnız süper yönetici değiştirebilir.',
              'Minimum build: apps below this build number see an "Update required" screen (admins excepted). Super admin only.',
              'Mindest-Build: ältere Apps müssen aktualisieren.'),
          style: const TextStyle(fontSize: 12),
        ),
        _numberField('min_supported_build', _t('Minimum desteklenen derleme', 'Minimum supported build', 'Mindest-Build'), 0, 100000),
        _numberField('admin_bruteforce_max_fails', _t('Yönetici girişi: hatalı deneme sınırı', 'Admin login: max failed attempts', 'Max. Fehlversuche'), 3, 20),
        _numberField('admin_bruteforce_window_min', _t('Yönetici girişi: kilit penceresi (dk)', 'Admin login: lock window (min)', 'Sperrfenster (min)'), 5, 1440),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_t('Otomatik hata raporlama', 'Automatic crash reporting', 'Automatische Absturzberichte')),
          subtitle: Text(_t('Kapalıysa uygulamalar hata göndermez (kill switch)', 'When off, apps send no crash reports (kill switch)', 'Aus = keine Berichte')),
          value: _cfg.errorReportingEnabled,
          onChanged: (v) => _run(() => JuzzioFeaturesService.instance.adminSetSetting(widget.token, 'error_reporting_enabled', v)),
        ),
        const SizedBox(height: 8),
        Text(
          _t('Not: 2 adımlı doğrulama (2FA) için Supabase Auth → MFA ayarının panelden açılması gerekir; uygulama içi 2FA bu sürümde yoktur.',
              'Note: two-factor auth requires enabling Supabase Auth → MFA in the dashboard; in-app 2FA is not part of this version.',
              'Hinweis: 2FA erfordert Supabase-MFA.'),
          style: const TextStyle(fontSize: 11.5),
        ),
      ];

  Future<void> _legalExport() async {
    final userCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(_t('Yasal dışa aktarım', 'Legal export', 'Rechtlicher Export')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: userCtrl, decoration: InputDecoration(labelText: _t('Kullanıcı adı', 'Username', 'Benutzername'), prefixText: '@')),
          TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: _t('Gerekçe (resmî yazı no vb.)', 'Reason (official request no.)', 'Begründung')),
          ),
          const SizedBox(height: 8),
          Text(
            _t('Uçtan uca şifreli mesaj içerikleri pakete giremez (sunucuda yoktur). İşlem denetim kaydına yazılır.',
                'End-to-end encrypted content cannot be included (not on the server). The export is audit-logged.', 'E2EE-Inhalte sind nicht enthalten.'),
            style: const TextStyle(fontSize: 11.5),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(_t('Dışa aktar', 'Export', 'Exportieren'))),
        ],
      ),
    );
    if (ok != true) return;
    final uname = userCtrl.text.trim().replaceAll('@', '').toLowerCase();
    if (uname.isEmpty) return;
    await _run(() async {
      final row = await _db.from('profiles').select('id').eq('username', uname).maybeSingle();
      if (row == null) throw Exception('user_not_found');
      final res = await _db.rpc('admin_legal_export', params: {'p_token': widget.token, 'p_user': row['id'], 'p_reason': reasonCtrl.text.trim()});
      final json = const JsonEncoder.withIndent('  ').convert(res);
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/juzzio_legal_${uname}_${DateTime.now().millisecondsSinceEpoch}.json');
      await f.writeAsString(json, flush: true);
      await Clipboard.setData(ClipboardData(text: json));
      _snack(_t('Paket oluşturuldu ve panoya kopyalandı', 'Bundle created and copied', 'Paket erstellt'));
      await OpenFilex.open(f.path, type: 'application/json');
    });
  }

  Future<void> _killAll() async {
    final ctrl = TextEditingController();
    const phrase = 'TUM OTURUMLARI KAPAT';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(_t('Tüm oturumları kapat', 'Sign everyone out', 'Alle abmelden')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_t('Senin dışındaki TÜM kullanıcıların oturumu kapanır ve yeniden giriş yapmaları gerekir. Yalnız güvenlik ihlali gibi acil durumlarda kullan.',
              'ALL users except you are signed out and must sign in again. Use only in emergencies such as a security breach.', 'Alle Nutzer werden abgemeldet.')),
          const SizedBox(height: 8),
          Text('${_t('Onaylamak için yaz', 'Type to confirm', 'Zur Bestätigung eingeben')}: $phrase', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextField(controller: ctrl),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(_t('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: JuzzioColors.red500, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, ctrl.text.trim() == phrase),
            child: Text(_t('Kapat', 'Sign out all', 'Abmelden')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final n = await _db.rpc('admin_kill_all_sessions', params: {'p_token': widget.token, 'p_confirm': phrase});
      _snack('${_t('Kapatılan oturum', 'Sessions closed', 'Sitzungen beendet')}: $n');
    });
  }

  List<Widget> _buildDanger(Color fg) => [
        _card(ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_rounded),
          title: Text(_t('Yasal paket (Legal Bundle Vault)', 'Legal bundle vault', 'Rechtspaket')),
          subtitle: Text(_t('Bir kullanıcının profil, cihaz, gönderi, şikâyet, ihlal ve denetim kayıtlarını JSON olarak dışa aktarır.',
              'Exports a user\'s profile, devices, posts, reports, strikes and audit records as JSON.', 'Exportiert Nutzerdaten als JSON.')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _legalExport,
        )),
        _card(ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout_rounded, color: JuzzioColors.red500),
          title: Text(_t('Tüm oturumları kapat (global session kill)', 'Global session kill', 'Alle Sitzungen beenden'),
              style: TextStyle(color: JuzzioColors.red500, fontWeight: FontWeight.w800)),
          subtitle: Text(_t('Acil durum. Tek bir kullanıcı için Kullanıcılar → kullanıcı → "Oturumları kapat"ı kullan.',
              'Emergency only. For one user use Users → user → "Sign out".', 'Nur im Notfall.')),
          onTap: _killAll,
        )),
        _card(Text(
          _t('Serbest SQL konsolu güvenlik nedeniyle yoktur: istemciden keyfi SQL çalıştırmak satır düzeyi güvenliği (RLS) ve denetim kaydını devre dışı bırakırdı. Bakım işlemleri bu sekmedeki tanımlı araçlarla yapılır; gerektiğinde Supabase SQL Editor kullanılmalıdır.',
              'There is no free-form SQL console by design: running arbitrary SQL from the app would bypass row-level security and the audit log. Use the predefined tools here, or the Supabase SQL Editor when needed.',
              'Kein freier SQL-Konsole (Sicherheit).'),
          style: const TextStyle(fontSize: 12),
        )),
      ];
}
