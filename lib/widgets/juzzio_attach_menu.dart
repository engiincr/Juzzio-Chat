// =============================================================================
// JUZZIO v0.9.4 — Sohbet eklenti menüsü (ataş), belge balonu, etkinlik kartı
//  • Kamera düğmesi yalnız doğrudan çekim yapar; diğer her şey ataş menüsündedir:
//    Belge · Galeri · Video · Konum · Kişi kartı · Anket (grup) · Etkinlik (grup) · Zamanla.
//  • Birebir sohbette belge ve dosya adı uçtan uca şifrelidir; açarken cihazda çözülür.
//  • Etkinlik: grup sohbetinde tarih/saat + hatırlatma; üyeler Katılıyorum/Belki/Katılmıyorum der.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_features_service.dart';
import '../services/juzzio_file_guard.dart';
import '../services/juzzio_media_cache.dart';
import '../services/supabase_service.dart';
import 'juzzio_encrypted_image.dart';
import 'juzzio_motion.dart';
import '../core/juzzio_temp_dir.dart';

class _AttachItem {
  final String id;
  final IconData icon;
  final String label;
  final List<Color> colors;
  const _AttachItem(this.id, this.icon, this.label, this.colors);
}

/// Seçilen eklenti kimliğini döner: document, gallery_photo, gallery_video, view_once, location, contact, poll, event, schedule.
Future<String?> showJuzzioAttachMenu(BuildContext context, {required bool isGroup}) {
  final app = JuzzioAppController.instance;
  final items = <_AttachItem>[
    _AttachItem('document', Icons.description_rounded, app.trEn('Belge', 'Document', 'Dokument'), const [Color(0xFF7C4DFF), Color(0xFF536DFE)]),
    _AttachItem('gallery_photo', Icons.photo_library_rounded, app.trEn('Galeri', 'Gallery', 'Galerie'), const [Color(0xFFEC407A), Color(0xFFAB47BC)]),
    _AttachItem('gallery_video', Icons.video_library_rounded, app.trEn('Video', 'Video', 'Video'), const [Color(0xFFFF7043), Color(0xFFF4511E)]),
    _AttachItem('view_once', Icons.looks_one_rounded, app.trEn('Tek seferlik', 'View once', 'Einmalig'), const [Color(0xFF00BFA5), Color(0xFF00897B)]),
    _AttachItem('location', Icons.location_on_rounded, app.trEn('Konum', 'Location', 'Standort'), const [Color(0xFF26A69A), Color(0xFF00897B)]),
    _AttachItem('contact', Icons.contact_page_rounded, app.trEn('Kişi kartı', 'Contact', 'Kontakt'), const [Color(0xFF42A5F5), Color(0xFF1E88E5)]),
    // v1.2.9: sohbette müzik paylaş (30 sn önizleme + Apple Music'te tamamı)
    if (JuzzioFeaturesService.instance.lastAppConfig.itunesPreviewsEnabled)
      _AttachItem('music', Icons.music_note_rounded, app.trEn('Müzik', 'Music', 'Musik'), const [Color(0xFFFF5E7E), Color(0xFFE53964)]),
    if (isGroup) _AttachItem('poll', Icons.poll_rounded, app.trEn('Anket', 'Poll', 'Umfrage'), const [Color(0xFFFFCA28), Color(0xFFFFA000)]),
    if (isGroup) _AttachItem('event', Icons.event_rounded, app.trEn('Etkinlik', 'Event', 'Termin'), const [Color(0xFF66BB6A), Color(0xFF43A047)]),
    _AttachItem('schedule', Icons.schedule_send_rounded, app.trEn('Zamanla', 'Schedule', 'Planen'), const [Color(0xFF78909C), Color(0xFF546E7A)]),
  ];
  return showJuzzioSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final dark = app.isDark;
      final p = JuzzioPalette(dark);
      final reduced = JuzzioGlassTokens.reducedEffects;
      // v1.2.9: Liquid Glass — buzlu cam pano, ışık kenarı (specular rim) ve renkli cam simge kuyuları
      final panel = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.05)]
                : [Colors.white.withValues(alpha: 0.78), Colors.white.withValues(alpha: 0.55)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.22 : 0.7), width: 1.1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.45 : 0.15), blurRadius: 30, offset: const Offset(0, 14))],
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(9))),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            // dar ekranda 3, normalde 4 sütun → etiketler taşmaz
            final cols = c.maxWidth < 300 ? 3 : 4;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 8,
              childAspectRatio: 0.84,
              children: [
                for (final it in items) _JuzzioGlassAttachTile(item: it, dark: dark, textColor: p.textPrimary, onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(ctx, it.id);
                }),
              ],
            );
          }),
        ]),
      );
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: reduced ? Container(color: p.sheetBg, child: panel) : BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26), child: panel),
          ),
        ),
      );
    },
  );
}

class _JuzzioGlassAttachTile extends StatefulWidget {
  const _JuzzioGlassAttachTile({required this.item, required this.dark, required this.textColor, required this.onTap});
  final _AttachItem item;
  final bool dark;
  final Color textColor;
  final VoidCallback onTap;

  @override
  State<_JuzzioGlassAttachTile> createState() => _JuzzioGlassAttachTileState();
}

class _JuzzioGlassAttachTileState extends State<_JuzzioGlassAttachTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final tint = it.colors.first;
    return Semantics(
      button: true,
      label: it.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                // renkli cam kuyu: üstte parlak, altta tonlu
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tint.withValues(alpha: 0.55), it.colors.last.withValues(alpha: 0.85)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
                boxShadow: [BoxShadow(color: it.colors.last.withValues(alpha: 0.38), blurRadius: 14, offset: const Offset(0, 6))],
              ),
              child: Stack(children: [
                // üst ışık yansıması
                Positioned(
                  left: 6,
                  right: 6,
                  top: 4,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0.0)],
                      ),
                    ),
                  ),
                ),
                Center(child: Icon(it.icon, color: Colors.white, size: 27)),
              ]),
            ),
            const SizedBox(height: 7),
            Text(it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.textColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

IconData juzzioDocumentIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_rounded;
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
    case 'txt':
      return Icons.article_rounded;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_rounded;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_rounded;
    case 'mp3':
    case 'm4a':
      return Icons.audio_file_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

/// Belge balonu: simge + ad + boyut; dokununca indirir (şifreliyse cihazda çözer) ve açar.
class JuzzioDocumentBubble extends StatefulWidget {
  const JuzzioDocumentBubble({super.key, required this.message, required this.isMe, this.fromStranger = false});
  final JuzzioMessage message;
  final bool isMe;

  /// v1.2.9: mesaj isteğinden (tanımadığın biri) gelen dosya → indirmeden önce risk uyarısı
  final bool fromStranger;

  @override
  State<JuzzioDocumentBubble> createState() => _JuzzioDocumentBubbleState();
}

class _JuzzioDocumentBubbleState extends State<JuzzioDocumentBubble> {
  bool _busy = false;

  String get _name {
    final m = widget.message;
    final n = (m.documentName ?? '').trim();
    if (n.isNotEmpty) return n;
    final t = m.originalText.trim();
    return t.isNotEmpty && t != '🔒' ? t : JuzzioAppController.instance.trEn('Belge', 'Document', 'Dokument');
  }

  Future<void> _open() async {
    final m = widget.message;
    final url = m.documentUrl;
    if (url == null || url.isEmpty || _busy) return;
    final app = JuzzioAppController.instance;
    if (widget.fromStranger && !widget.isMe) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB020), size: 34),
          title: Text(app.trEn('Riskli dosya uyarısı', 'Risky file warning', 'Warnung: riskante Datei')),
          content: Text(app.trEn(
            'Bu dosya, mesaj isteğini henüz kabul etmediğin, tanımadığın birinden geldi. Juzzio dosyayı açmadan önce otomatik olarak denetler; ancak hiçbir denetim tüm riskleri ortadan kaldıramaz. Dosyayı indirip açmanın sorumluluğu sana aittir.',
            'This file comes from someone you do not know and whose message request you have not accepted yet. Juzzio checks files automatically before opening them, but no check can remove every risk. Downloading and opening the file is your own responsibility.',
            'Diese Datei stammt von einer unbekannten Person, deren Nachrichtenanfrage du noch nicht angenommen hast. Juzzio prüft Dateien automatisch vor dem Öffnen, aber keine Prüfung schließt alle Risiken aus. Herunterladen und Öffnen geschieht auf eigene Verantwortung.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.trEn('Riski kabul ediyorum, indir', 'I accept the risk, download', 'Risiko akzeptieren, herunterladen'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final encrypted = JuzzioEncryptedMedia.isEncrypted(m.metadata);
      final bytes = encrypted ? await JuzzioEncryptedMedia.load(m.id, url, keepInMemory: false) : await JuzzioMediaDiskCache.instance.loadBytes(url);
      if (bytes == null) throw Exception('download_failed');
      // v1.2.9: gelen dosya şifresi çözüldükten sonra, açılmadan ÖNCE cihazda denetlenir
      final check = juzzioInspectBytes(bytes, name: _name, kind: JuzzioUploadKind.document);
      if (!check.ok) {
        unawaited(SupabaseService.instance.logFileGuardEvent(direction: 'in', verdict: check.verdict.name, detail: check.detail));
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.gpp_bad_rounded, color: Color(0xFFFF453A), size: 34),
              title: Text(app.trEn('Tehlikeli dosya engellendi', 'Dangerous file blocked', 'Gefährliche Datei blockiert')),
              content: Text('${juzzioFileVerdictMessage(check, app.trEn)}\n\n${app.trEn('Dosya açılmadı ve cihazına kaydedilmedi. Göndereni tanımıyorsan sohbeti şikâyet et.', 'The file was not opened or saved. If you do not know the sender, report the chat.', 'Die Datei wurde weder geöffnet noch gespeichert.')}'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(app.trEn('Tamam', 'OK', 'OK')))],
            ),
          );
        }
        return;
      }
      final dir = await juzzioTempDir();
      final folder = Directory('${dir.path}/juzzio_docs/${m.id}');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final f = File('${folder.path}/${juzzioCleanFileName(juzzioSafeFileName(_name))}');
      await f.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(f.path, type: juzzioSafeUploadMime(juzzioDocumentMime(_name)));
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(app.trEn('Bu dosyayı açacak uygulama bulunamadı.', 'No app found to open this file.', 'Keine App zum Öffnen dieser Datei gefunden.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(app.trEn('Dosya indirilemedi. Bağlantınızı kontrol edin.', 'The file could not be downloaded. Check your connection.',
              'Die Datei konnte nicht heruntergeladen werden. Prüfe deine Verbindung.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    final fg = widget.isMe ? Colors.white : p.textPrimary;
    final size = widget.message.documentSize;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: _busy
                ? Padding(padding: const EdgeInsets.all(11), child: JuzzioOrbitLoader(strokeWidth: 2, color: fg))
                : Icon(juzzioDocumentIcon(_name), color: fg),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                [
                  if (size > 0) juzzioFormatBytes(size),
                  if (JuzzioEncryptedMedia.isEncrypted(widget.message.metadata)) '🔒',
                ].join(' · '),
                style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11.5),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Icon(Icons.download_rounded, color: fg.withValues(alpha: 0.8), size: 20),
        ]),
      ),
    );
  }
}

/// Konum metnini ("📍 … https://maps.google.com/?q=lat,lng") tanır.
({double lat, double lng})? juzzioParseLocationText(String text) {
  final m = RegExp(r'maps\.google\.com/\?q=(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)').firstMatch(text);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
  return (lat: lat, lng: lng);
}

String juzzioLocationMessageText(double lat, double lng, JuzzioAppController app) =>
    '📍 ${app.trEn('Konumum', 'My location', 'Mein Standort')}\nhttps://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

String juzzioContactCardText(JuzzioUserProfile u, JuzzioAppController app) =>
    '👤 ${app.trEn('Kişi kartı', 'Contact card', 'Kontaktkarte')}\n${u.displayName.isNotEmpty ? u.displayName : u.username}\n@${u.username}';
