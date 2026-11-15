// =============================================================================
// JUZZIO v1.2.9 — Sistem Sağlığı sayfası (Güvenlik Merkezi → Sistem Sağlığı)
//  Tasarım: buzlu cam kartlar, "● Etkin" nokta rozeti, büyük sayı + küçük birim,
//  beyaz hap biçimli ana düğme (gönderilen tasarım görsellerinden).
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/deepgram_livekit_service.dart';
import '../services/juzzio_health_monitor.dart';

class JuzzioSystemHealthPage extends StatefulWidget {
  const JuzzioSystemHealthPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioSystemHealthPage()));

  @override
  State<JuzzioSystemHealthPage> createState() => _JuzzioSystemHealthPageState();
}

class _JuzzioSystemHealthPageState extends State<JuzzioSystemHealthPage> {
  final _app = JuzzioAppController.instance;
  final _m = JuzzioHealthMonitor.instance;

  @override
  void initState() {
    super.initState();
    if (_m.lastRun == null || DateTime.now().difference(_m.lastRun!) > const Duration(minutes: 2)) {
      _m.runAll();
    }
  }

  String _title(String id) {
    switch (id) {
      case 'server':
        return _app.trEn('Sunucu', 'Server', 'Server');
      case 'translate':
        return _app.trEn('Sohbet çevirisi', 'Chat translation', 'Chat-Übersetzung');
      case 'provider':
        return _app.trEn('Çeviri sağlayıcısı', 'Translation provider', 'Übersetzungsdienst');
      case 'deepgram':
        return _app.trEn('Canlı altyazı · sesli mesaj', 'Live captions · voice notes', 'Live-Untertitel · Sprachnachrichten');
      case 'device_speech':
        return _app.trEn('Cihaz konuşma tanıyıcı (yedek)', 'Device speech recognizer (backup)', 'Geräte-Spracherkennung (Ersatz)');
      case 'livekit':
        return _app.trEn('Arama sunucusu', 'Call server', 'Anrufserver');
      case 'backup_turn':
        return _app.trEn('Yedek arama aktarıcısı (TURN)', 'Backup call relay (TURN)', 'Ersatz-Anrufrelais (TURN)');
    }
    return id;
  }

  IconData _icon(String id) {
    switch (id) {
      case 'server':
        return Icons.dns_rounded;
      case 'translate':
        return Icons.translate_rounded;
      case 'provider':
        return Icons.verified_rounded;
      case 'deepgram':
        return Icons.closed_caption_rounded;
      case 'device_speech':
        return Icons.record_voice_over_rounded;
      case 'livekit':
        return Icons.videocam_rounded;
      case 'backup_turn':
        return Icons.alt_route_rounded;
    }
    return Icons.circle;
  }

  String _detail(JuzzioHealthItem it) {
    final d = it.detail;
    switch (it.id) {
      case 'provider':
        if (d == 'google_cloud') return 'Google Cloud Translation (resmî)';
        if (d == 'deepl') return 'DeepL API (resmî)';
        if (d == 'bridge_unreachable') return _app.trEn('Sunucu köprüsüne ulaşılamadı', 'Bridge unreachable', 'Brücke nicht erreichbar');
        return _app.trEn('Ücretsiz uç nokta — sunucuya GOOGLE_TRANSLATE_API_KEY veya DEEPL_API_KEY ekleyin',
            'Free endpoint — add GOOGLE_TRANSLATE_API_KEY or DEEPL_API_KEY on the server', 'Kostenloser Endpunkt — offiziellen Schlüssel hinterlegen');
      case 'deepgram':
        if (d == 'ok') return _app.trEn('Deepgram anahtarı geçerli', 'Deepgram key valid', 'Deepgram-Schlüssel gültig');
        if (d == 'missing') {
          return _app.trEn('Sunucuda DEEPGRAM_API_KEY yok — aramalarda cihaz tanıyıcısı kullanılır',
              'DEEPGRAM_API_KEY missing — calls use the device recognizer', 'DEEPGRAM_API_KEY fehlt');
        }
        if (d == 'key_cannot_grant') {
          return _app.trEn('Deepgram anahtarı geçerli ama yetkisi yetersiz — "Member" rolünde yeni anahtar gerekli (canlı altyazı çalışmaz)',
              'Deepgram key is valid but lacks permission — a new key with the "Member" role is needed (live captions will not work)',
              'Deepgram-Schlüssel gültig, aber ohne Berechtigung — neuer Schlüssel mit Rolle „Member“ nötig');
        }
        if (d == 'invalid_key') return _app.trEn('Deepgram anahtarı geçersiz/iptal', 'Deepgram key invalid/revoked', 'Deepgram-Schlüssel ungültig');
        return d;
      case 'translate':
        return d == 'server'
            ? _app.trEn('Yol: sunucu köprüsü', 'Route: server bridge', 'Weg: Server')
            : _app.trEn('Yol: cihazdan', 'Route: from device', 'Weg: Gerät');
      case 'server':
        if (d.startsWith('file_blocks:')) {
          return _app.trEn('Son 24 saatte ${d.substring(12)} tehlikeli dosya engellendi', '${d.substring(12)} dangerous files blocked in 24 h',
              '${d.substring(12)} gefährliche Dateien blockiert');
        }
        return '';
    }
    return d;
  }

  Color _dot(JuzzioHealthState s) {
    switch (s) {
      case JuzzioHealthState.ok:
        return const Color(0xFFE4F25C);
      case JuzzioHealthState.degraded:
        return const Color(0xFFFFB020);
      case JuzzioHealthState.down:
        return const Color(0xFFFF453A);
      case JuzzioHealthState.checking:
        return Colors.white70;
      case JuzzioHealthState.unknown:
        return Colors.white24;
    }
  }

  String _stateText(JuzzioHealthState s) {
    switch (s) {
      case JuzzioHealthState.ok:
        return _app.trEn('Etkin', 'Active', 'Aktiv');
      case JuzzioHealthState.degraded:
        return _app.trEn('Kısıtlı', 'Limited', 'Eingeschränkt');
      case JuzzioHealthState.down:
        return _app.trEn('Çalışmıyor', 'Down', 'Ausgefallen');
      case JuzzioHealthState.checking:
        return _app.trEn('Denetleniyor', 'Checking', 'Prüfe');
      case JuzzioHealthState.unknown:
        return '—';
    }
  }

  Widget _glass({required Widget child, EdgeInsets padding = const EdgeInsets.all(18), double radius = 30}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.05)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _statusPill(JuzzioHealthState s) => Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: _dot(s), shape: BoxShape.circle)),
          ),
          const SizedBox(width: 6),
          Text(_stateText(s), style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14130F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_app.trEn('Sistem Sağlığı', 'System Health', 'Systemzustand'), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Stack(children: [
        // arka plan: sarı-yeşil bulanık ışık lekeleri (tasarım görsellerindeki gibi)
        Positioned(top: -80, right: -60, child: _blob(const Color(0xFFD8E33A), 260)),
        Positioned(bottom: 40, left: -90, child: _blob(const Color(0xFF8C7A3A), 300)),
        ListenableBuilder(
          listenable: _m,
          builder: (context, _) {
            final all = _m.items.values.toList();
            final okCount = all.where((e) => e.state == JuzzioHealthState.ok).length;
            final known = all.where((e) => e.state != JuzzioHealthState.unknown).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: [
                _glass(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(_app.trEn('GENEL', 'OVERALL', 'GESAMT'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 10),
                      _statusPill(_m.running ? JuzzioHealthState.checking : _m.overall),
                    ]),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$okCount', style: const TextStyle(color: Colors.white, fontSize: 64, height: 0.9, fontWeight: FontWeight.w300)),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('/ $known ${_app.trEn('çalışıyor', 'working', 'aktiv')}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 18)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.auto_fix_high_rounded, size: 15, color: Color(0xFFE4F25C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _m.fixLog.isEmpty
                              ? _app.trEn('Otomatik onarım hazır — sorun görülürse kendiliğinden düzeltilir',
                                  'Auto-repair ready — problems are fixed automatically', 'Automatische Reparatur bereit')
                              : _m.fixLog.first,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12.5),
                        ),
                      ),
                    ]),
                    if (DeepgramLiveKitController.preferBackupTurn) ...[
                      const SizedBox(height: 8),
                      Text(_app.trEn('Aramalar şu an yedek aktarıcıyla başlıyor', 'Calls currently start via the backup relay', 'Anrufe nutzen derzeit das Ersatzrelais'),
                          style: const TextStyle(color: Color(0xFFFFB020), fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                for (final it in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _glass(
                      radius: 24,
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), shape: BoxShape.circle),
                          child: Icon(_icon(it.id), color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_title(it.id), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                            if (_detail(it).isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(_detail(it), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5)),
                            ],
                            if (it.autoFix.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('↺ ${it.autoFix}', style: const TextStyle(color: Color(0xFFE4F25C), fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          _statusPill(it.state),
                          if (it.latencyMs > 0) ...[
                            const SizedBox(height: 4),
                            Text('${it.latencyMs} ms', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                          ],
                        ]),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: _m,
              builder: (context, _) => Material(
                color: Colors.white,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _m.running ? null : _m.runAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          _m.running ? _app.trEn('Denetleniyor…', 'Checking…', 'Prüfe…') : _app.trEn('Şimdi denetle', 'Check now', 'Jetzt prüfen'),
                          style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                      ),
                      _m.running
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF14130F)))
                          : const Icon(Icons.signal_cellular_alt_rounded, color: Color(0xFF14130F)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _blob(Color c, double size) => IgnorePointer(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(width: size, height: size, decoration: BoxDecoration(color: c.withValues(alpha: 0.55), shape: BoxShape.circle)),
        ),
      );
}
