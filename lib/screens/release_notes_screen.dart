// =============================================================================
// JUZZIO v0.6.1 — Güncelleme notları sayfası (şeffaflık)
//  Her sürüm için açılır cam kart: neden getirildi, yeni özellikler, düzeltilen
//  hatalar, güvenlik ve gizlilik değişiklikleri. En üstte bekleyen güncelleme
//  (varsa) ve "Şimdi güncelle" düğmesi; zorunlu güncellemeler açıkça işaretlenir.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/release_notes.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';

class JuzzioReleaseNotesPage extends StatefulWidget {
  /// Açılışta genişletilecek sürüm (ör. bildirimden gelinen sürüm)
  final String? focusVersion;

  const JuzzioReleaseNotesPage({super.key, this.focusVersion});

  static Future<void> open(BuildContext context, {String? focusVersion}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JuzzioReleaseNotesPage(focusVersion: focusVersion)),
    );
  }

  @override
  State<JuzzioReleaseNotesPage> createState() => _JuzzioReleaseNotesPageState();
}

class _JuzzioReleaseNotesPageState extends State<JuzzioReleaseNotesPage> {
  final JuzzioAppController _app = JuzzioAppController.instance;
  List<JuzzioReleaseNote> _notes = JuzzioReleaseNote.mergeAll(const <JuzzioReleaseNote>[]);
  bool _loading = true;
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.focusVersion ?? (_app.otaUpdateAvailable ? _app.otaRemoteVersion : JuzzioConfig.appVersion));
    _load();
  }

  Future<void> _load() async {
    final remote = <JuzzioReleaseNote>[];
    try {
      final rows = await SupabaseService.instance.client
          .from('app_releases')
          .select()
          .order('version_code', ascending: false)
          .limit(50);
      for (final r in rows) {
        remote.add(JuzzioReleaseNote.fromRow(Map<String, dynamic>.from(r)));
      }
    } catch (_) {
      // Çevrimdışı: uygulamaya gömülü geçmiş gösterilir
    }
    // version.json'dan gelen (henüz yönetici panelinde yayınlanmamış) bekleyen sürüm
    if (_app.otaUpdateAvailable && _app.otaDetails.isNotEmpty) {
      remote.add(JuzzioReleaseNote.fromRow(<String, dynamic>{
        'version_name': _app.otaRemoteVersion,
        'version_code': _app.otaRemoteCode,
        'is_mandatory': _app.otaMandatory,
        'details': _app.otaDetails,
      }));
    }
    if (!mounted) return;
    setState(() {
      _notes = JuzzioReleaseNote.mergeAll(remote);
      _loading = false;
    });
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  Widget _badge(String text, {Color color = Colors.white, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(text, style: TextStyle(color: fg ?? color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  Widget _group(String title, IconData icon, List<String> items, Color accent) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 9, left: 2),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text(item, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 13.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(JuzzioReleaseNote n) {
    final installed = JuzzioReleaseNote.compareSemver(n.versionName, JuzzioConfig.appVersion) == 0;
    final isNew = JuzzioReleaseNote.compareSemver(n.versionName, JuzzioConfig.appVersion) > 0;
    final open = _expanded.contains(n.versionName);
    final section = n.sectionFor(_app.uiLang);
    final reason = section.reason.isNotEmpty ? section.reason : _app.translateUiDynamic(n.legacyNotes);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JuzzioGlass(
        radius: 24,
        strongBorder: isNew,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => setState(() {
                if (open) {
                  _expanded.remove(n.versionName);
                } else {
                  _expanded.add(n.versionName);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: isNew ? 0.9 : 0.14),
                      ),
                      child: Icon(
                        isNew ? Icons.rocket_launch_rounded : Icons.history_rounded,
                        color: isNew ? const Color(0xFF111113) : Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Juzzio v${n.versionName}',
                              style: const TextStyle(
                                  fontFamily: JuzzioConfig.fontRegularBold,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16.5)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (n.publishedAt != null) _badge(_date(n.publishedAt), color: Colors.white70),
                              if (installed) _badge(_app.trEn('Yüklü sürüm', 'Installed', 'Installiert'), color: const Color(0xFF34C759)),
                              if (isNew) _badge(_app.trEn('Yeni', 'New', 'Neu'), color: const Color(0xFF64D2FF)),
                              if (n.mandatory) _badge(_app.trEn('Zorunlu', 'Mandatory', 'Pflicht'), color: JuzzioColors.red500),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: Color(0x2EFFFFFF)),
                    if (reason.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_app.trEn('Bu güncelleme neden getirildi?', 'Why this update?', 'Warum dieses Update?'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(height: 5),
                      Text(reason, style: const TextStyle(color: Colors.white70, height: 1.45, fontSize: 13.5)),
                    ],
                    _group(_app.trEn('Yeni özellikler', 'New features', 'Neue Funktionen'), Icons.auto_awesome_rounded,
                        section.features, const Color(0xFF64D2FF)),
                    _group(_app.trEn('Düzeltilen hatalar', 'Fixed bugs', 'Behobene Fehler'), Icons.build_circle_rounded,
                        section.fixes, const Color(0xFF34C759)),
                    _group(_app.trEn('Güvenlik ve gizlilik', 'Security and privacy', 'Sicherheit und Datenschutz'),
                        Icons.verified_user_rounded, section.security, const Color(0xFFBF5AF2)),
                    if (isNew && _app.otaUpdateAvailable &&
                        JuzzioReleaseNote.compareSemver(n.versionName, _app.otaRemoteVersion) == 0) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF111113),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: const StadiumBorder(),
                          ),
                          icon: Icon(_app.hasDownloadedOta ? Icons.install_mobile_rounded : Icons.download_rounded),
                          label: Text(
                            _app.hasDownloadedOta
                                ? _app.trEn('Kur', 'Install', 'Installieren')
                                : _app.trEn('Şimdi güncelle', 'Update now', 'Jetzt aktualisieren'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          onPressed: _app.isDownloadingOta
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.maybeOf(context);
                                  final msg = _app.hasDownloadedOta
                                      ? await _app.installDownloadedOta()
                                      : await _app.startOtaDownloadAndInstall();
                                  messenger?.showSnackBar(SnackBar(content: Text(msg)));
                                },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _app.trEn('Güncelleme notları', 'Release notes', 'Versionshinweise'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
            children: [
              JuzzioGlass(
                radius: 22,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _app.trEn(
                          'Her güncellemenin neden getirildiğini, hangi özellikleri eklediğini, hangi hataları düzelttiğini ve güvenlik/gizlilik değişikliklerini burada açıkça paylaşıyoruz. Yüklü sürümünüz: v${JuzzioConfig.appVersion}',
                          'Here we openly share why each update was released, what it added, which bugs it fixed and its security/privacy changes. Your version: v${JuzzioConfig.appVersion}',
                          'Hier erklären wir offen, warum jedes Update erschien, was es hinzufügt, welche Fehler es behebt und welche Sicherheits-/Datenschutzänderungen es enthält. Deine Version: v${JuzzioConfig.appVersion}',
                        ),
                        style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_app.isDownloadingOta) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _app.otaDownloadProgress <= 0 ? null : _app.otaDownloadProgress,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              for (final n in _notes) _card(n),
            ],
          ),
        ),
      ),
    );
  }
}

/// v0.7.0: Güncellemeden sonraki ilk açılışta "Sürüm X ile neler geldi?" cam penceresi.
/// İçerik otomatik gelir (uygulamaya gömülü notlar → app_releases → GitHub sürüm notu);
/// yöneticinin elle yazmasına gerek yoktur.
class JuzzioWhatsNewSheet {
  static bool _shown = false;

  static Future<void> showIfPending(BuildContext context) async {
    final app = JuzzioAppController.instance;
    await app.ensureOtaStateLoaded();
    if (_shown || !app.whatsNewPending || !context.mounted) return;
    _shown = true;
    final version = JuzzioConfig.appVersion;
    JuzzioReleaseNote? note;
    for (final n in JuzzioReleaseNote.mergeAll(const <JuzzioReleaseNote>[])) {
      if (JuzzioReleaseNote.compareSemver(n.versionName, version) == 0) note = n;
    }
    JuzzioReleaseSection section = note?.sectionFor(app.uiLang) ?? const JuzzioReleaseSection();
    if (section.isEmpty) {
      final gh = await app.fetchGithubReleaseDetails(version);
      if (gh.isNotEmpty) {
        section = JuzzioReleaseNote.fromRow(<String, dynamic>{'version_name': version, 'details': gh}).sectionFor(app.uiLang);
      }
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = JuzzioPalette(app.isDark);
        Widget group(String title, IconData icon, List<String> items) {
          if (items.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 18, color: p.textPrimary),
                  const SizedBox(width: 8),
                  Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                ]),
                const SizedBox(height: 6),
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(color: p.textSecondary, height: 1.4)),
                        Expanded(child: Text(i, style: TextStyle(color: p.textSecondary, height: 1.4, fontSize: 13.5))),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
              child: JuzzioGlass(
                radius: 30,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.coolButtonBg),
                          child: Icon(Icons.auto_awesome_rounded, color: p.coolButtonFg),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            app.trEn('Yenilikler: Sürüm $version ile neler geldi?', 'What\'s new in version $version?',
                                'Neu in Version $version'),
                            style: TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: p.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 17),
                          ),
                        ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (section.reason.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(section.reason, style: TextStyle(color: p.textSecondary, height: 1.45, fontSize: 13.5)),
                            ],
                            group(app.trEn('Yeni özellikler', 'New features', 'Neue Funktionen'), Icons.auto_awesome_rounded, section.features),
                            group(app.trEn('Düzeltilen hatalar', 'Fixed bugs', 'Behobene Fehler'), Icons.build_circle_rounded, section.fixes),
                            group(app.trEn('Güvenlik ve gizlilik', 'Security and privacy', 'Sicherheit und Datenschutz'),
                                Icons.verified_user_rounded, section.security),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.textPrimary,
                              side: BorderSide(color: p.glassBorder),
                              minimumSize: const Size.fromHeight(46),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              JuzzioReleaseNotesPage.open(context, focusVersion: version);
                            },
                            child: FittedBox(child: Text(app.trEn('Tüm notlar', 'All notes', 'Alle Hinweise'))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: p.coolButtonBg,
                              foregroundColor: p.coolButtonFg,
                              minimumSize: const Size.fromHeight(46),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: FittedBox(
                                child: Text(app.trEn('Harika!', 'Great!', 'Super!'), style: const TextStyle(fontWeight: FontWeight.w900))),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    app.markWhatsNewSeen();
  }
}
