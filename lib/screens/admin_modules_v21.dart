// Juzzio 2.1 — Yönetici Paneli modül ızgarası (Faz 10–16)
//
// Tasarımdaki 34 numaralı modül kartı. Her kart ya mevcut bir yönetici sekmesini açar
// ya da sunucudaki admin_module_stats(token, modül) ile GERÇEK sayıları gösterir.
// Kurulumu dış hesap gerektiren modüller (Reklam: AdMob, Ödeme: Google Play Billing)
// sahte veri göstermez; "kurulmadı" bilgisini ve gerekenleri yazar.
// Hiçbir modül mesaj içeriği, e-posta, IP veya gizli ayar değeri göstermez.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/native_bridge.dart';
import '../services/juzzio_legal_pdf.dart' show kJuzzioPdfFontRegular, kJuzzioPdfFontBold, juzzioPdfSafeText;
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_features_service.dart';
import '../widgets/juzzio_brand.dart';
import '../widgets/juzzio_neon_kit.dart';

/// Bir yönetici modülü: [tab] mevcut sekme kimliği, [stats] sunucu modülü, [info] yalnız bilgi
class JuzzioAdminModule {
  const JuzzioAdminModule(this.no, this.icon, this.tr, this.en, {this.tab, this.stats, this.info, this.page});
  final int no;
  final IconData icon;
  final String tr;
  final String en;
  final int? tab;
  final String? stats;
  final String? info;

  /// v2.1: kendi ekranı olan modül ('verification')
  final String? page;
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
  JuzzioAdminModule(19, Icons.verified_rounded, 'Hesap Doğrulama', 'Account Verification', page: 'verification'),
  JuzzioAdminModule(20, Icons.smart_toy_outlined, 'Spam ve Bot Koruması', 'Spam & Bot Protection', stats: 'quota'),
  JuzzioAdminModule(21, Icons.sensors_rounded, 'Canlı Oturum İzleme', 'Live Sessions', stats: 'live'),
  JuzzioAdminModule(22, Icons.network_check_rounded, 'WebRTC Tanılama', 'WebRTC Diagnostics', stats: 'calls'),
  JuzzioAdminModule(23, Icons.fact_check_rounded, 'Çeviri Kalite Kontrolü', 'Translation Quality', stats: 'translation'),
  JuzzioAdminModule(24, Icons.perm_media_rounded, 'Medya ve Dosya Yönetimi', 'Media & Files', stats: 'media'),
  JuzzioAdminModule(25, Icons.privacy_tip_rounded, 'Gizlilik ve KVKK Merkezi', 'Privacy & KVKK', stats: 'lifecycle'),
  JuzzioAdminModule(26, Icons.speed_rounded, 'API ve Kota Yönetimi', 'API & Quotas', stats: 'quota'),
  JuzzioAdminModule(27, Icons.flag_rounded, 'Özellik Yayınlama ve A/B Testi', 'Feature Rollout & A/B Tests', page: 'flags'),
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
                      } else if (m.page == 'verification') {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioAdminVerificationPage(token: token)));
                      } else if (m.page == 'flags') {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioAdminFlagsPage(token: token)));
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
                        m.page != null
                            ? app.trEn('Başvurular', 'Requests', 'Anträge')
                            : m.tab != null
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

/// v2.1 (Faz 13.2): modül verisini PDF rapora çevirir (Türkçe karakterler gömülü yazı tipiyle)
Future<Uint8List> juzzioAdminModulePdf({
  required String title,
  required Map<String, dynamic> data,
  required bool english,
  ByteData? fontRegular,
  ByteData? fontBold,
}) async {
  final regular = pw.Font.ttf(fontRegular ?? await rootBundle.load(kJuzzioPdfFontRegular));
  final bold = pw.Font.ttf(fontBold ?? await rootBundle.load(kJuzzioPdfFontBold));
  final rows = juzzioFlattenForCsv(data).skip(1).toList();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: 'Juzzio — $title', author: 'Juzzio');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(juzzioPdfSafeText('Juzzio · $title'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.Text('${english ? 'Page' : 'Sayfa'} ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
      ]),
    ),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Text(
          juzzioPdfSafeText('${english ? 'Generated (UTC)' : 'Oluşturulma (UTC)'}: ${data['generated_at'] ?? DateTime.now().toUtc().toIso8601String()}'),
          style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: [english ? 'Metric' : 'Ölçüm', english ? 'Value' : 'Değer'],
        data: [for (final r in rows) [juzzioPdfSafeText(r[0]), juzzioPdfSafeText(r[1])]],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
      ),
      pw.SizedBox(height: 10),
      pw.Text(
          english
              ? 'Contains only aggregate numbers; no message content, e-mail, IP or secret setting values.'
              : 'Yalnız toplu sayılar içerir; mesaj içeriği, e-posta, IP veya gizli ayar değeri yoktur.',
          style: const pw.TextStyle(fontSize: 8)),
    ],
  ));
  return doc.save();
}

/// PDF'i kaydeder: Android → İndirilenler/Juzzio, masaüstü → İndirilenler. Kaydedilen yol ya da null.
Future<String?> juzzioSaveAdminPdf(String name, Uint8List bytes) async {
  if (kIsWeb) return null;
  if (Platform.isAndroid) {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    final ok = await JuzzioNative.saveToGallery(path: f.path, mime: 'application/pdf', name: name, kind: 'document');
    try {
      await f.delete();
    } catch (_) {}
    return ok ? 'Download/Juzzio/$name' : null;
  }
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
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
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        JuzzioHeaderCircleButton(
                          icon: Icons.table_chart_outlined,
                          tooltip: app.trEn('CSV olarak kopyala', 'Copy as CSV', 'Als CSV kopieren'),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: juzzioCsvEncode(juzzioFlattenForCsv(d))));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(app.trEn('CSV panoya kopyalandı', 'CSV copied', 'CSV kopiert'))));
                          },
                        ),
                        const SizedBox(width: 8),
                        // v2.1 (Faz 13.2): PDF rapor
                        JuzzioHeaderCircleButton(
                          icon: Icons.picture_as_pdf_outlined,
                          tooltip: app.trEn('PDF rapor indir', 'Download PDF report', 'PDF-Bericht laden'),
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final english = app.uiLang != 'tr';
                            try {
                              final bytes = await juzzioAdminModulePdf(
                                  title: '${m.no}. ${english ? m.en : m.tr}', data: d, english: english);
                              final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 10);
                              final saved = await juzzioSaveAdminPdf('Juzzio_modul_${m.no}_$stamp.pdf', bytes);
                              messenger.showSnackBar(SnackBar(
                                  content: Text(saved == null
                                      ? app.trEn('PDF kaydedilemedi', 'Could not save the PDF', 'PDF nicht gespeichert')
                                      : app.trEn('PDF kaydedildi: $saved', 'PDF saved: $saved', 'PDF gespeichert: $saved'))));
                            } catch (_) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text(app.trEn('PDF oluşturulamadı', 'Could not create the PDF', 'PDF-Fehler'))));
                            }
                          },
                        ),
                      ]),
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

/// v2.1 — Yönetici panel şifresini değiştirme. [forced]: varsayılan şifreyle girildi, değiştirmeden
/// panel açılmaz (sunucu da tüm yönetici işlemlerini kilitli tutar). Başarılıysa true döner.
class JuzzioAdminChangePasswordPage extends StatefulWidget {
  const JuzzioAdminChangePasswordPage({super.key, required this.token, this.forced = false, this.initialOld = ''});
  final String token;
  final bool forced;
  final String initialOld;

  @override
  State<JuzzioAdminChangePasswordPage> createState() => _JuzzioAdminChangePasswordPageState();
}

/// Yeni yönetici şifresi kuralı (sunucuyla aynı): en az 8 karakter, harf ve rakam (saf; test edilir)
bool juzzioAdminPasswordOk(String p) => p.length >= 8 && RegExp('[A-Za-z]').hasMatch(p) && RegExp('[0-9]').hasMatch(p);

class _JuzzioAdminChangePasswordPageState extends State<JuzzioAdminChangePasswordPage> {
  late final TextEditingController _old = TextEditingController(text: widget.initialOld);
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = JuzzioAppController.instance;
    final n = _new.text;
    if (!juzzioAdminPasswordOk(n)) {
      setState(() => _error = app.trEn('Yeni şifre en az 8 karakter olmalı ve harf ile rakam içermeli.',
          'The new password must be at least 8 characters and contain letters and numbers.', 'Mind. 8 Zeichen mit Buchstaben und Ziffern.'));
      return;
    }
    if (n != _again.text) {
      setState(() => _error = app.trEn('Yeni şifreler aynı değil.', 'The new passwords do not match.', 'Die Passwörter stimmen nicht überein.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await JuzzioFeaturesService.instance.adminChangePassword(token: widget.token, oldPassword: _old.text, newPassword: n);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(app.trEn('Yönetici şifren değiştirildi.', 'Your admin password was changed.', 'Admin-Passwort geändert.'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      final m = e.toString();
      if (!mounted) return;
      setState(() => _error = m == 'wrong_password'
          ? app.trEn('Mevcut şifre hatalı.', 'The current password is wrong.', 'Aktuelles Passwort falsch.')
          : m == 'password_same'
              ? app.trEn('Yeni şifre eskisiyle aynı olamaz.', 'The new password must differ from the old one.', 'Neues Passwort muss sich unterscheiden.')
              : m == 'password_too_weak'
                  ? app.trEn('Yeni şifre çok zayıf.', 'The new password is too weak.', 'Neues Passwort zu schwach.')
                  : m);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(color: JuzzioGlassTokens.heading),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return PopScope(
      canPop: !widget.forced || !_busy,
      child: Scaffold(
        backgroundColor: JuzzioGlassTokens.space.depth.last,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              JuzzioScreenHeader(
                title: app.trEn('Yönetici şifresini değiştir', 'Change admin password', 'Admin-Passwort ändern'),
                subtitle: widget.forced
                    ? app.trEn('İlk girişte varsayılan şifreyi değiştirmen gerekiyor. Değiştirmeden panel açılmaz.',
                        'You must change the default password on first sign-in. The panel stays locked until you do.',
                        'Beim ersten Login muss das Standardpasswort geändert werden.')
                    : app.trEn('Bu şifre yalnız yönetici paneline giriş içindir.', 'This password is only for the admin panel.',
                        'Nur für das Admin-Panel.'),
              ),
              JuzzioNeonCard(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _field(_old, app.trEn('Mevcut şifre', 'Current password', 'Aktuelles Passwort')),
                  _field(_new, app.trEn('Yeni şifre', 'New password', 'Neues Passwort')),
                  _field(_again, app.trEn('Yeni şifre (tekrar)', 'New password (again)', 'Neues Passwort (wiederholen)')),
                  Text(
                    app.trEn('En az 8 karakter; harf ve rakam içermeli.', 'At least 8 characters; must contain letters and numbers.',
                        'Mind. 8 Zeichen; Buchstaben und Ziffern.'),
                    style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFFF5A6A))),
                    ),
                  const SizedBox(height: 14),
                  JuzzioLimeButton(
                    label: app.trEn('Şifreyi değiştir', 'Change password', 'Passwort ändern'),
                    icon: Icons.key_rounded,
                    busy: _busy,
                    onPressed: _busy ? null : _save,
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// v2.1 (Faz 14.1) — Mavi tik başvuruları: onayla / reddet
class JuzzioAdminVerificationPage extends StatefulWidget {
  const JuzzioAdminVerificationPage({super.key, required this.token});
  final String token;

  @override
  State<JuzzioAdminVerificationPage> createState() => _JuzzioAdminVerificationPageState();
}

class _JuzzioAdminVerificationPageState extends State<JuzzioAdminVerificationPage> {
  List<Map<String, dynamic>>? _rows;
  String _status = 'pending';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await Supabase.instance.client.rpc('admin_verification_list', params: {'p_token': widget.token, 'p_status': _status});
      if (!mounted) return;
      setState(() => _rows = res is List ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const []);
    } catch (_) {
      if (mounted) {
        setState(() => _error = JuzzioAppController.instance.trEn('Başvurular alınamadı (veritabanı güncellemesi 10.49 gerekli olabilir).',
            'Could not load requests (database update 10.49 may be required).', 'Anträge nicht verfügbar.'));
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final app = JuzzioAppController.instance;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.rpc('admin_verification_decide',
          params: {'p_token': widget.token, 'p_id': r['id'], 'p_approve': approve, 'p_note': ''});
      messenger.showSnackBar(SnackBar(
          content: Text(approve
              ? app.trEn('@${r['username']} doğrulandı', '@${r['username']} verified', '@${r['username']} verifiziert')
              : app.trEn('Başvuru reddedildi', 'Request rejected', 'Antrag abgelehnt'))));
      await _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(app.trEn('İşlem yapılamadı', 'Action failed', 'Fehlgeschlagen'))));
    }
  }

  String _cat(String c) {
    final app = JuzzioAppController.instance;
    return switch (c) {
      'creator' => app.trEn('İçerik üreticisi', 'Creator', 'Creator'),
      'public_figure' => app.trEn('Tanınmış kişi', 'Public figure', 'Person des öffentlichen Lebens'),
      'business' => app.trEn('İşletme / marka', 'Business / brand', 'Unternehmen'),
      'journalist' => app.trEn('Gazeteci', 'Journalist', 'Journalist'),
      _ => app.trEn('Diğer', 'Other', 'Sonstiges'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final rows = _rows;
    const statuses = ['pending', 'approved', 'rejected', 'all'];
    return Scaffold(
      backgroundColor: JuzzioGlassTokens.space.depth.last,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              JuzzioScreenHeader(title: '19. ${app.trEn('Hesap Doğrulama', 'Account Verification', 'Verifizierung')}'),
              JuzzioNeonChips(
                labels: [
                  app.trEn('Bekleyen', 'Pending', 'Offen'),
                  app.trEn('Onaylanan', 'Approved', 'Genehmigt'),
                  app.trEn('Reddedilen', 'Rejected', 'Abgelehnt'),
                  app.trEn('Tümü', 'All', 'Alle'),
                ],
                selected: statuses.indexOf(_status),
                onChanged: (k) {
                  setState(() {
                    _status = statuses[k];
                    _rows = null;
                  });
                  _load();
                },
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF5A6A)))
              else if (rows == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (rows.isEmpty)
                Text(app.trEn('Başvuru yok.', 'No requests.', 'Keine Anträge.'), style: TextStyle(color: JuzzioGlassTokens.textSecondary))
              else
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: JuzzioNeonCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('@${r['username'] ?? ''} · ${r['display_name'] ?? ''}',
                            style: TextStyle(color: JuzzioGlassTokens.heading, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${_cat('${r['category'] ?? ''}')} · ${(r['created_at'] ?? '').toString().split('T').first} · ${r['status']}',
                            style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text('${r['reason'] ?? ''}', style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 13.5)),
                        if ('${r['links'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          SelectableText('${r['links']}', style: const TextStyle(color: JuzzioBrandColors.lime, fontSize: 12.5)),
                        ],
                        if (r['status'] == 'pending') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: JuzzioLimeButton(
                                label: app.trEn('Onayla', 'Approve', 'Genehmigen'),
                                icon: Icons.verified_rounded,
                                height: 42,
                                onPressed: () => _decide(r, true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: JuzzioLimeButton(
                                label: app.trEn('Reddet', 'Reject', 'Ablehnen'),
                                style: JuzzioLimeButtonStyle.outline,
                                height: 42,
                                onPressed: () => _decide(r, false),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}


/// v2.1 (Faz 15.4) — Özellik yayınlama (kademeli %) ve A/B testi
class JuzzioAdminFlagsPage extends StatefulWidget {
  const JuzzioAdminFlagsPage({super.key, required this.token});
  final String token;

  @override
  State<JuzzioAdminFlagsPage> createState() => _JuzzioAdminFlagsPageState();
}

class _JuzzioAdminFlagsPageState extends State<JuzzioAdminFlagsPage> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('admin_flags_list', params: {'p_token': widget.token});
      if (!mounted) return;
      setState(() {
        _error = null;
        _rows = r is List ? r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = JuzzioAppController.instance.trEn('Bayraklar alınamadı (veritabanı güncellemesi 10.50 gerekli olabilir).',
            'Could not load flags (database update 10.50 may be required).', 'Flags nicht verfügbar.'));
      }
    }
  }

  Future<void> _save(String key, String desc, bool enabled, int pct, List<String> variants) async {
    final app = JuzzioAppController.instance;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.rpc('admin_flag_upsert', params: {
        'p_token': widget.token,
        'p_key': key,
        'p_description': desc,
        'p_enabled': enabled,
        'p_rollout': pct,
        'p_variants': variants,
      });
      await _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(app.trEn('Kaydedilemedi (anahtar: küçük harf, rakam, _ ; en çok 6 varyant)',
              'Could not save (key: lowercase, digits, _; max 6 variants)', 'Speichern fehlgeschlagen'))));
    }
  }

  Future<void> _edit([Map<String, dynamic>? f]) async {
    final app = JuzzioAppController.instance;
    final key = TextEditingController(text: '${f?['key'] ?? ''}');
    final desc = TextEditingController(text: '${f?['description'] ?? ''}');
    final vars = TextEditingController(text: (f?['variants'] is List ? (f!['variants'] as List).join(', ') : ''));
    var enabled = f?['enabled'] == true;
    var pct = ((f?['rollout_pct'] as num?) ?? 100).toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(f == null ? app.trEn('Yeni özellik', 'New feature flag', 'Neues Flag') : '${f['key']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (f == null)
                TextField(controller: key, decoration: InputDecoration(labelText: app.trEn('Anahtar (ör. yeni_sohbet)', 'Key (e.g. new_chat)', 'Schlüssel'))),
              TextField(controller: desc, decoration: InputDecoration(labelText: app.trEn('Açıklama', 'Description', 'Beschreibung'))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(app.trEn('Açık', 'Enabled', 'Aktiv')),
                value: enabled,
                onChanged: (v) => setD(() => enabled = v),
              ),
              Text('${app.trEn('Kullanıcıların', 'Rollout to', 'Rollout')} %${pct.round()}'),
              Slider(value: pct, min: 0, max: 100, divisions: 20, onChanged: (v) => setD(() => pct = v)),
              TextField(
                controller: vars,
                decoration: InputDecoration(
                    labelText: app.trEn('A/B varyantları (virgülle, ör. a, b)', 'A/B variants (comma-separated, e.g. a, b)', 'A/B-Varianten')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.trEn('Kaydet', 'Save', 'Speichern'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      final variants = vars.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await _save((f?['key'] ?? key.text).toString().trim().toLowerCase(), desc.text.trim(), enabled, pct.round(), variants);
    }
  }

  Future<void> _delete(String key) async {
    final app = JuzzioAppController.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.trEn('“$key” silinsin mi?', 'Delete “$key”?', '„$key“ löschen?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.trEn('Sil', 'Delete', 'Löschen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('admin_flag_delete', params: {'p_token': widget.token, 'p_key': key});
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final rows = _rows;
    return Scaffold(
      backgroundColor: JuzzioGlassTokens.space.depth.last,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: JuzzioBrandColors.lime,
        foregroundColor: const Color(0xFF111113),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: Text(app.trEn('Yeni', 'New', 'Neu')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            children: [
              JuzzioScreenHeader(
                title: '27. ${app.trEn('Özellik Yayınlama ve A/B', 'Feature Rollout & A/B', 'Rollout & A/B')}',
                subtitle: app.trEn('Kademeli yüzde ve A/B varyantı; aynı kişi hep aynı gruptadır.',
                    'Gradual percentage and A/B variants; each person always stays in the same group.', 'Schrittweise und A/B.'),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF5A6A)))
              else if (rows == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (rows.isEmpty)
                Text(app.trEn('Henüz özellik bayrağı yok.', 'No feature flags yet.', 'Noch keine Flags.'),
                    style: TextStyle(color: JuzzioGlassTokens.textSecondary))
              else
                JuzzioNeonGroup(children: [
                  for (final f in rows)
                    JuzzioNeonRow(
                      icon: f['enabled'] == true ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                      title: '${f['key']}',
                      subtitle: '${f['enabled'] == true ? app.trEn('Açık', 'On', 'An') : app.trEn('Kapalı', 'Off', 'Aus')} · %${f['rollout_pct']}'
                          '${(f['variants'] is List && (f['variants'] as List).isNotEmpty) ? ' · A/B: ${(f['variants'] as List).join('/')}' : ''}'
                          '${'${f['description'] ?? ''}'.isEmpty ? '' : ' · ${f['description']}'}',
                      onTap: () => _edit(f),
                    ),
                ]),
              if (rows != null && rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(app.trEn('Silmek için aşağıdaki çipe dokun.', 'Tap a chip below to delete that flag.', 'Zum Löschen Chip antippen.'),
                    style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
                Wrap(spacing: 8, children: [
                  for (final f in rows)
                    ActionChip(
                      avatar: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: Text('${f['key']}'),
                      onPressed: () => _delete('${f['key']}'),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
