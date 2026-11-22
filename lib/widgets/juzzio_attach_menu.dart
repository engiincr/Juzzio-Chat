// =============================================================================
// JUZZIO v0.9.4 — Sohbet eklenti menüsü (ataş), belge balonu, etkinlik kartı
//  • Kamera düğmesi yalnız doğrudan çekim yapar; diğer her şey ataş menüsündedir:
//    Belge · Galeri · Video · Konum · Kişi kartı · Anket (grup) · Etkinlik (grup) · Zamanla.
//  • Birebir sohbette belge ve dosya adı uçtan uca şifrelidir; açarken cihazda çözülür.
//  • Etkinlik: grup sohbetinde tarih/saat + hatırlatma; üyeler Katılıyorum/Belki/Katılmıyorum der.
// =============================================================================

import 'dart:async';
import 'dart:io';

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
  final String hint;
  final Color color;
  const _AttachItem(this.id, this.icon, this.label, this.hint, this.color);
}

/// GM-020: kart yüksekliği sabit (simge + ad + açıklama sığar; Windows yazı tipinde de taşmaz)
const double kJuzzioAttachTileHeight = 118;

/// v2.2.0: ek menüsü renkleri — her temada uyumlu, yumuşak ve birbirinden ayırt edilir (saf; test edilir)
const Map<String, Color> kJuzzioAttachColors = {
  'document': Color(0xFF8B7CF6),
  'gallery_photo': Color(0xFFF472B6),
  'gallery_video': Color(0xFFFB923C),
  'view_once': Color(0xFF2DD4BF),
  'location': Color(0xFF34D399),
  'contact': Color(0xFF60A5FA),
  'music': Color(0xFFF87171),
  'poll': Color(0xFFFBBF24),
  'event': Color(0xFFA3E635),
  'schedule': Color(0xFF94A3B8),
  'watch_party': Color(0xFFC6F135),
};

/// Seçilen eklenti kimliğini döner: document, gallery_photo, gallery_video, view_once, location, contact, poll, event, schedule.
/// v2.2.0: yeniden tasarlandı — tema camında başlıklı pano, her seçenek kendi renginde yumuşak bir
/// cam kart (renkli simge dairesi + ad + kısa açıklama). Belge / Video / Tek seferlik öne çıkar.
Future<String?> showJuzzioAttachMenu(BuildContext context, {required bool isGroup, bool watchParty = false}) {
  final app = JuzzioAppController.instance;
  Color c(String id) => kJuzzioAttachColors[id]!;
  final items = <_AttachItem>[
    _AttachItem('document', Icons.description_outlined, app.trEn('Belge', 'Document', 'Dokument'),
        app.trEn('PDF, Word, ZIP', 'PDF, Word, ZIP', 'PDF, Word, ZIP'), c('document')),
    _AttachItem('gallery_photo', Icons.photo_outlined, app.trEn('Fotoğraf', 'Photo', 'Foto'),
        app.trEn('Galeriden', 'From gallery', 'Aus Galerie'), c('gallery_photo')),
    _AttachItem('gallery_video', Icons.videocam_outlined, app.trEn('Video', 'Video', 'Video'),
        app.trEn('Galeriden', 'From gallery', 'Aus Galerie'), c('gallery_video')),
    _AttachItem('view_once', Icons.looks_one_outlined, app.trEn('Tek gösterim', 'View once', 'Einmal ansehen'),
        app.trEn('Bir kez açılır', 'Opens once', 'Einmal öffnen'), c('view_once')),
    _AttachItem('location', Icons.location_on_outlined, app.trEn('Konum', 'Location', 'Standort'),
        app.trEn('Şu anki yerin', 'Where you are', 'Dein Standort'), c('location')),
    _AttachItem('contact', Icons.contact_page_outlined, app.trEn('Kişi kartı', 'Contact', 'Kontakt'),
        app.trEn('Arkadaşını paylaş', 'Share a friend', 'Freund teilen'), c('contact')),
    // v1.2.9: sohbette müzik paylaş (30 sn önizleme + Apple Music'te tamamı)
    if (JuzzioFeaturesService.instance.lastAppConfig.itunesPreviewsEnabled)
      _AttachItem('music', Icons.music_note_outlined, app.trEn('Müzik', 'Music', 'Musik'),
          app.trEn('30 sn önizleme', '30 s preview', '30 s Vorschau'), c('music')),
    if (isGroup)
      _AttachItem('poll', Icons.poll_outlined, app.trEn('Anket', 'Poll', 'Umfrage'), app.trEn('Oylama', 'Vote', 'Abstimmung'), c('poll')),
    if (isGroup)
      _AttachItem('event', Icons.event_outlined, app.trEn('Etkinlik', 'Event', 'Termin'), app.trEn('Tarih + hatırlatma', 'Date + reminder', 'Datum + Erinnerung'), c('event')),
    // GM-018: Sinema Parti sohbet üst menüsünden buraya taşındı
    if (watchParty)
      _AttachItem('watch_party', Icons.movie_filter_outlined, app.trEn('Sinema Parti', 'Cinema Party', 'Kino-Party'),
          app.trEn('Birlikte izleyin', 'Watch together', 'Zusammen schauen'), c('watch_party')),
    _AttachItem('schedule', Icons.schedule_send_outlined, app.trEn('Zamanla', 'Schedule', 'Planen'),
        app.trEn('Sonra gönder', 'Send later', 'Später senden'), c('schedule')),
  ];
  return showJuzzioSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      // GM-020: tek katman liquid glass pano (çift çerçeve yok), ızgara satır yüksekliği sabit → taşma yok
      final panel = JuzzioLiquidGlass(
        radius: 30,
        strong: true,
        blur: 24,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(color: JuzzioGlassTokens.textMuted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(app.trEn('Paylaş', 'Share', 'Teilen'),
                style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, box) {
            // dar ekranda 3, normalde 4 sütun → etiketler taşmaz
            final cols = box.maxWidth < 330 ? 3 : 4;
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: kJuzzioAttachTileHeight,
              ),
              children: [
                for (final it in items)
                  _JuzzioAttachTile(item: it, onTap: () {
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
          child: panel,
        ),
      );
    },
  );
}

/// v2.2.0: tek seçenek kartı — kendi renginde yumuşak cam zemin, renkli simge dairesi, ad ve açıklama
class _JuzzioAttachTile extends StatefulWidget {
  const _JuzzioAttachTile({required this.item, required this.onTap});
  final _AttachItem item;
  final VoidCallback onTap;

  @override
  State<_JuzzioAttachTile> createState() => _JuzzioAttachTileState();
}

class _JuzzioAttachTileState extends State<_JuzzioAttachTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final dark = JuzzioGlassTokens.isDarkResolver();
    // açık zeminde simge rengi okunur kalsın diye koyulaştırılır
    final ink = dark ? it.color : Color.lerp(it.color, const Color(0xFF000000), 0.28)!;
    return Semantics(
      button: true,
      label: it.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 110),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: it.color.withValues(alpha: dark ? 0.12 : 0.10),
              border: Border.all(color: it.color.withValues(alpha: dark ? 0.30 : 0.35)),
            ),
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: it.color.withValues(alpha: dark ? 0.22 : 0.18),
                ),
                child: Icon(it.icon, color: ink, size: 24),
              ),
              const SizedBox(height: 8),
              Text(it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(it.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ]),
          ),
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
