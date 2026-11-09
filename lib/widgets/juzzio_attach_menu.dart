// =============================================================================
// JUZZIO v0.9.4 — Sohbet eklenti menüsü (ataş), belge balonu, etkinlik kartı
//  • Kamera düğmesi yalnız doğrudan çekim yapar; diğer her şey ataş menüsündedir:
//    Belge · Galeri · Video · Konum · Kişi kartı · Anket (grup) · Etkinlik (grup) · Zamanla.
//  • Birebir sohbette belge ve dosya adı uçtan uca şifrelidir; açarken cihazda çözülür.
//  • Etkinlik: grup sohbetinde tarih/saat + hatırlatma; üyeler Katılıyorum/Belki/Katılmıyorum der.
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_media_cache.dart';
import '../services/supabase_service.dart';
import 'juzzio_encrypted_image.dart';

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
    if (isGroup) _AttachItem('poll', Icons.poll_rounded, app.trEn('Anket', 'Poll', 'Umfrage'), const [Color(0xFFFFCA28), Color(0xFFFFA000)]),
    if (isGroup) _AttachItem('event', Icons.event_rounded, app.trEn('Etkinlik', 'Event', 'Termin'), const [Color(0xFF66BB6A), Color(0xFF43A047)]),
    _AttachItem('schedule', Icons.schedule_send_rounded, app.trEn('Zamanla', 'Schedule', 'Planen'), const [Color(0xFF78909C), Color(0xFF546E7A)]),
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final p = JuzzioPalette(app.isDark);
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            color: p.sheetBg.withValues(alpha: 0.92),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: p.textMuted, borderRadius: BorderRadius.circular(9))),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.82,
                  children: [
                    for (final it in items)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(ctx, it.id);
                        },
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: it.colors),
                              boxShadow: [BoxShadow(color: it.colors.last.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
                            ),
                            child: Icon(it.icon, color: Colors.white, size: 27),
                          ),
                          const SizedBox(height: 7),
                          Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      );
    },
  );
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
  const JuzzioDocumentBubble({super.key, required this.message, required this.isMe});
  final JuzzioMessage message;
  final bool isMe;

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
    setState(() => _busy = true);
    try {
      final encrypted = JuzzioEncryptedMedia.isEncrypted(m.metadata);
      final bytes = encrypted ? await JuzzioEncryptedMedia.load(m.id, url, keepInMemory: false) : await JuzzioMediaDiskCache.instance.loadBytes(url);
      if (bytes == null) throw Exception('download_failed');
      final dir = await getTemporaryDirectory();
      final folder = Directory('${dir.path}/juzzio_docs/${m.id}');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final f = File('${folder.path}/${juzzioSafeFileName(_name)}');
      await f.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(f.path, type: juzzioDocumentMime(_name));
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
                ? Padding(padding: const EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
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
