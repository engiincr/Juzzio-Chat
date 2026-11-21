// Juzzio 2.1 — Yönetici Paneli modül ızgarası (Faz 10–16)
//
// Tasarımdaki 34 numaralı modül kartı. Her kart ya mevcut bir yönetici sekmesini açar
// ya da sunucudaki admin_module_stats(token, modül) ile GERÇEK sayıları gösterir.
// Kurulumu dış hesap gerektiren modüller (Reklam: AdMob, Ödeme: Google Play Billing)
// sahte veri göstermez; "kurulmadı" bilgisini ve gerekenleri yazar.
// Hiçbir modül mesaj içeriği, e-posta, IP veya gizli ayar değeri göstermez.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../widgets/juzzio_brand.dart';
import '../widgets/juzzio_neon_kit.dart';

/// Bir yönetici modülü: [tab] mevcut sekme kimliği, [stats] sunucu modülü, [info] yalnız bilgi
class JuzzioAdminModule {
  const JuzzioAdminModule(this.no, this.icon, this.tr, this.en, {this.tab, this.stats, this.info});
  final int no;
  final IconData icon;
  final String tr;
  final String en;
  final int? tab;
  final String? stats;
  final String? info;
}

/// Sekme kimlikleri admin_panel_screen.dart'taki _allTabs sırasıdır.
const List<JuzzioAdminModule> kJuzzioAdminModules = [
  JuzzioAdminModule(1, Icons.insights_rounded, 'Genel Bakış', 'Overview', tab: 0),
  JuzzioAdminModule(2, Icons.people_alt_rounded, 'Kullanıcı Yönetimi', 'User Management', tab: 1),
  JuzzioAdminModule(3, Icons.groups_2_rounded, 'Arkadaşlık ve Topluluklar', 'Friends & Communities', tab: 6),
  JuzzioAdminModule(4, Icons.delete_sweep_rounded, 'İçerik Moderasyonu', 'Content Moderation', tab: 5),
  JuzzioAdminModule(5, Icons.forum_rounded, 'Mesajlaşma Yönetimi', 'Messaging', stats: 'messaging'),
  JuzzioAdminModule(6, Icons.call_rounded, 'Sesli ve Görüntülü Aramalar', 'Voice & Video Calls', stats: 'calls'),
  JuzzioAdminModule(7, Icons.translate_rounded, 'Canlı Çeviri Merkezi', 'Live Translation', stats: 'translation'),
  JuzzioAdminModule(8, Icons.notifications_active_rounded, 'Bildirim Merkezi', 'Notification Center', stats: 'notifications'),
  JuzzioAdminModule(9, Icons.explore_rounded, 'Keşfet Yönetimi', 'Explore', stats: 'discover'),
  JuzzioAdminModule(10, Icons.movie_rounded, 'Sinema Parti ve Civciv', 'Watch Party & Chick', stats: 'watch_chick'),
  JuzzioAdminModule(11, Icons.system_update_rounded, 'Sürüm ve OTA', 'Releases & OTA', tab: 9),
  JuzzioAdminModule(12, Icons.tune_rounded, 'Tema ve Uygulama Ayarları', 'Theme & App Settings', tab: 10),
  JuzzioAdminModule(13, Icons.security_rounded, 'Güvenlik Merkezi', 'Security Center', stats: 'security'),
  JuzzioAdminModule(14, Icons.storage_rounded, 'Supabase ve Altyapı', 'Supabase & Infrastructure', stats: 'infra'),
  JuzzioAdminModule(15, Icons.bar_chart_rounded, 'Analitik ve Raporlar', 'Analytics & Reports', tab: 0),
  JuzzioAdminModule(16, Icons.support_agent_rounded, 'Destek Merkezi', 'Support Center', stats: 'feedback'),
  JuzzioAdminModule(17, Icons.admin_panel_settings_rounded, 'Sistem Ekstraları', 'System Extras', tab: 15),
  JuzzioAdminModule(18, Icons.history_rounded, 'Yönetici Denetim Kayıtları', 'Admin Audit Log', tab: 12),
  JuzzioAdminModule(19, Icons.verified_rounded, 'Hesap Doğrulama', 'Account Verification', tab: 14),
  JuzzioAdminModule(20, Icons.smart_toy_outlined, 'Spam ve Bot Koruması', 'Spam & Bot Protection', stats: 'quota'),
  JuzzioAdminModule(21, Icons.sensors_rounded, 'Canlı Oturum İzleme', 'Live Sessions', stats: 'live'),
  JuzzioAdminModule(22, Icons.network_check_rounded, 'WebRTC Tanılama', 'WebRTC Diagnostics', stats: 'calls'),
  JuzzioAdminModule(23, Icons.fact_check_rounded, 'Çeviri Kalite Kontrolü', 'Translation Quality', stats: 'translation'),
  JuzzioAdminModule(24, Icons.perm_media_rounded, 'Medya ve Dosya Yönetimi', 'Media & Files', stats: 'media'),
  JuzzioAdminModule(25, Icons.privacy_tip_rounded, 'Gizlilik ve KVKK Merkezi', 'Privacy & KVKK', stats: 'lifecycle'),
  JuzzioAdminModule(26, Icons.speed_rounded, 'API ve Kota Yönetimi', 'API & Quotas', stats: 'quota'),
  JuzzioAdminModule(27, Icons.flag_rounded, 'Özellik Yayınlama', 'Feature Rollout', stats: 'flags'),
  JuzzioAdminModule(28, Icons.warning_amber_rounded, 'Sistem Olayları ve Alarmlar', 'System Events & Alerts', stats: 'errors'),
  JuzzioAdminModule(29, Icons.campaign_rounded, 'Duyuru ve Kampanya', 'Announcements', tab: 8),
  JuzzioAdminModule(30, Icons.autorenew_rounded, 'Veri Yaşam Döngüsü', 'Data Lifecycle', stats: 'lifecycle'),
  JuzzioAdminModule(31, Icons.backup_rounded, 'Yedekleme ve Felaket Kurtarma', 'Backup & Recovery', info: 'backup'),
  JuzzioAdminModule(32, Icons.ads_click_rounded, 'Reklam ve Gelir', 'Ads & Revenue', info: 'ads'),
  JuzzioAdminModule(33, Icons.payments_rounded, 'Ödeme ve Abonelikler', 'Payments & Subscriptions', info: 'billing'),
  JuzzioAdminModule(34, Icons.auto_awesome_rounded, 'Juzzio Story', 'Juzzio Story', tab: 13),
];

class JuzzioAdminModulesPage extends StatelessWidget {
  const JuzzioAdminModulesPage({super.key, required this.token, required this.visibleTabs, required this.onOpenTab});
  final String token;
  final List<int> visibleTabs;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final mods = kJuzzioAdminModules.where((m) => m.tab == null || visibleTabs.contains(m.tab)).toList();
    return Scaffold(
      backgroundColor: JuzzioGlassTokens.space.depth.last,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: JuzzioScreenHeader(
                title: app.trEn('Yönetici Modülleri', 'Admin Modules', 'Admin-Module'),
                subtitle: app.trEn('${mods.length} modül · gerçek veriler', '${mods.length} modules · live data', '${mods.length} Module'),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final m = mods[i];
                  return JuzzioNeonCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () {
                      if (m.tab != null) {
                        Navigator.of(context).pop();
                        onOpenTab(m.tab!);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => JuzzioAdminModuleStatsPage(token: token, module: m),
                        ));
                      }
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: JuzzioBrandColors.lime.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${m.no}',
                              style: const TextStyle(color: JuzzioBrandColors.lime, fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                        const Spacer(),
                        Icon(m.icon, color: JuzzioBrandColors.lime, size: 22),
                      ]),
                      const Spacer(),
                      Text(app.trEn(m.tr, m.en, m.en),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 14, fontWeight: FontWeight.w800, height: 1.2)),
                      const SizedBox(height: 4),
                      Text(
                        m.tab != null
                            ? app.trEn('Sekmeyi aç', 'Open tab', 'Tab öffnen')
                            : m.info != null
                                ? app.trEn('Bilgi', 'Info', 'Info')
                                : app.trEn('Canlı sayılar', 'Live numbers', 'Live-Zahlen'),
                        style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5),
                      ),
                    ]),
                  );
                },
                childCount: mods.length,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Modül verisini düz CSV satırlarına çevirir (saf; test edilir). İç içe değerler "a.b" anahtarıyla.
List<List<String>> juzzioFlattenForCsv(Map<String, dynamic> data) {
  final rows = <List<String>>[
    ['key', 'value'],
  ];
  void walk(String prefix, Object? v) {
    if (v is Map) {
      v.forEach((k, x) => walk(prefix.isEmpty ? '$k' : '$prefix.$k', x));
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        walk('$prefix[$i]', v[i]);
      }
    } else {
      rows.add([prefix, '${v ?? ''}']);
    }
  }

  data.forEach((k, v) => walk(k, v));
  return rows;
}

String juzzioCsvEncode(List<List<String>> rows) => rows
    .map((r) => r.map((c) => (c.contains(',') || c.contains('"') || c.contains('\n')) ? '"${c.replaceAll('"', '""')}"' : c).join(','))
    .join('\n');

class JuzzioAdminModuleStatsPage extends StatefulWidget {
  const JuzzioAdminModuleStatsPage({super.key, required this.token, required this.module});
  final String token;
  final JuzzioAdminModule module;

  @override
  State<JuzzioAdminModuleStatsPage> createState() => _JuzzioAdminModuleStatsPageState();
}

class _JuzzioAdminModuleStatsPageState extends State<JuzzioAdminModuleStatsPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = widget.module.stats;
    if (key == null) return;
    setState(() {
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('admin_module_stats', params: {'p_token': widget.token, 'p_module': key});
      if (!mounted) return;
      setState(() => _data = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{});
    } catch (_) {
      if (mounted) {
        setState(() => _error = JuzzioAppController.instance.trEn(
            'Veriler alınamadı. Veritabanı güncellemesi (10.47) uygulanmamış olabilir.',
            'Could not load data. Database update 10.47 may not be applied yet.',
            'Daten nicht verfügbar. Datenbank-Update 10.47 fehlt evtl.'));
      }
    }
  }

  String _label(String k) {
    final app = JuzzioAppController.instance;
    const tr = <String, String>{
      'total_30d': 'Toplam (30 gün)', 'answered_30d': 'Yanıtlanan', 'missed_30d': 'Cevapsız', 'rejected_30d': 'Reddedilen',
      'video_30d': 'Görüntülü', 'avg_duration_sec': 'Ort. süre (sn)', 'success_rate': 'Başarı oranı %',
      'messages_24h': 'Mesaj (24 sa)', 'messages_7d': 'Mesaj (7 gün)', 'active_rooms_7d': 'Etkin sohbet (7 gün)',
      'group_rooms': 'Grup', 'scheduled_pending': 'Zamanlanmış (bekleyen)', 'scheduled_failed_7d': 'Zamanlanmış hata',
      'rate_limited_1h': 'Hız sınırı olayı (1 sa)', 'total_7d': 'Toplam (7 gün)', 'accepted_7d': 'FCM kabul',
      'failed_7d': 'Başarısız', 'no_tokens_7d': 'Jetonsuz', 'skipped_7d': 'Tercihle atlanan', 'active_tokens': 'Kayıtlı cihaz jetonu',
      'visible_users': 'Keşfet\'te görünen', 'hidden_users': 'Gizli', 'matches': 'Eşleşme', 'watch_active': 'Etkin sinema',
      'watch_30d': 'Sinema (30 gün)', 'chicks_alive': 'Yaşayan civciv', 'chicks_total': 'Toplam civciv', 'chicks_ended_30d': 'Biten civciv (30 gün)',
      'mfa_users': '2FA açık kullanıcı', 'admin_login_failed_7d': 'Başarısız yönetici girişi', 'admin_login_ok_7d': 'Yönetici girişi',
      'banned_users': 'Yasaklı', 'strikes_30d': 'İhlal (30 gün)', 'password_changes_30d': 'Şifre değişimi (30 gün)',
      'db_bytes': 'Veritabanı boyutu', 'cleanup_pending': 'Temizlik kuyruğu', 'cleanup_failed': 'Temizlik hatası',
      'online_now': 'Şu an çevrimiçi', 'seen_1h': 'Son 1 saat', 'seen_24h': 'Son 24 saat', 'calls_ringing': 'Çalan arama',
      'active_call_rooms': 'Süren arama', 'review_pending': 'İnceleme bekleyen', 'open': 'Açık hata', 'fatal_open': 'Çökme (açık)',
      'ai_users_today': 'Bugün yapay zekâ kullanan', 'verified': 'Doğrulanmış', 'users': 'Kullanıcı', 'private_accounts': 'Gizli hesap',
      'new_users_30d': 'Yeni kullanıcı (30 gün)', 'cleanup_done_30d': 'Silinen dosya (30 gün)',
    };
    return app.uiLang == 'tr' ? (tr[k] ?? k) : k.replaceAll('_', ' ');
  }

  String _fmt(String k, Object? v) {
    if (k == 'db_bytes' && v is num) return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (k == 'bytes' && v is num) return '${(v / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${v ?? '—'}';
  }

  Widget _info(String kind) {
    final app = JuzzioAppController.instance;
    final text = switch (kind) {
      'backup' => app.trEn(
          'Veritabanı yedeklerini Supabase alır (günlük yedek; Pro planda zamana geri dönüş/PITR). Kurtarma Supabase panelinden yapılır. '
              'Kod GitHub\'da, sürümler GitHub Releases\'ta saklanır. Uçtan uca şifreli mesajların anahtarları cihazlardadır; sunucu yedeğinden mesaj içeriği çözülemez.',
          'Supabase takes database backups (daily; PITR on Pro). Restore from the Supabase dashboard. Code lives on GitHub and builds on GitHub Releases. '
              'E2EE message keys live on devices; message contents cannot be decrypted from server backups.',
          'Supabase erstellt Datenbank-Backups; Wiederherstellung im Supabase-Dashboard.'),
      'ads' => app.trEn(
          'Reklam kurulmadı. Gerekenler: AdMob hesabı, uygulama kimliği ve Google Play "Reklam içerir" beyanı. Kurulana kadar uygulamada reklam gösterilmez ve burada sahte gelir verisi gösterilmez.',
          'Ads are not set up. Needed: an AdMob account, app ID and the Play "Contains ads" declaration. Until then no ads are shown and no fake revenue is displayed.',
          'Werbung nicht eingerichtet (AdMob-Konto nötig).'),
      _ => app.trEn(
          'Ödeme/abonelik kurulmadı. Gerekenler: Google Play Console ödeme profili, Play Billing ürünleri ve sunucu tarafı makbuz doğrulaması. Kurulana kadar uygulamada ücretli özellik yoktur.',
          'Payments are not set up. Needed: a Play Console payments profile, Play Billing products and server-side receipt validation. Until then there are no paid features.',
          'Zahlungen nicht eingerichtet (Play Billing nötig).'),
    };
    return JuzzioNeonCard(
      padding: const EdgeInsets.all(18),
      child: Text(text, style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 14, height: 1.45)),
    );
  }

  Widget _tiles(Map<String, dynamic> d) {
    final nums = d.entries.where((e) => e.value is num).toList();
    if (nums.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final e in nums)
        SizedBox(
          width: 160,
          child: JuzzioNeonCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmt(e.key, e.value),
                  style: const TextStyle(color: JuzzioBrandColors.lime, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(_label(e.key), style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }

  Widget _section(String k, Object? v) {
    Widget body;
    if (v is Map) {
      final entries = v.entries.toList();
      final max = entries.fold<num>(1, (a, e) => e.value is num && e.value as num > a ? e.value as num : a);
      body = Column(children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 130,
                child: Text('${e.key}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 12.5)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: e.value is num ? ((e.value as num) / max).toDouble() : 0,
                    minHeight: 8,
                    color: JuzzioBrandColors.lime,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value}', style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
            ]),
          ),
      ]);
    } else if (v is List) {
      if (v.isEmpty) {
        body = Text(JuzzioAppController.instance.trEn('Kayıt yok', 'No records', 'Keine Einträge'),
            style: TextStyle(color: JuzzioGlassTokens.textSecondary));
      } else {
        body = Column(children: [
          for (final row in v.take(30))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                row is Map ? row.entries.map((e) => '${e.key}: ${_fmt(e.key.toString(), e.value)}').join(' · ') : '$row',
                style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 12.5),
              ),
            ),
        ]);
      }
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: JuzzioNeonCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_label(k), style: TextStyle(color: JuzzioGlassTokens.heading, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          body,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final m = widget.module;
    final d = _data;
    return Scaffold(
      backgroundColor: JuzzioGlassTokens.space.depth.last,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              JuzzioScreenHeader(
                title: '${m.no}. ${app.trEn(m.tr, m.en, m.en)}',
                trailing: m.stats == null || d == null
                    ? null
                    : JuzzioHeaderCircleButton(
                        icon: Icons.file_download_outlined,
                        tooltip: app.trEn('CSV olarak kopyala', 'Copy as CSV', 'Als CSV kopieren'),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: juzzioCsvEncode(juzzioFlattenForCsv(d))));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(app.trEn('CSV panoya kopyalandı', 'CSV copied', 'CSV kopiert'))));
                        },
                      ),
              ),
              if (m.info != null)
                _info(m.info!)
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF5A6A)))
              else if (d == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else ...[
                _tiles(d),
                for (final e in d.entries)
                  if (e.value is Map || e.value is List) _section(e.key, e.value),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
