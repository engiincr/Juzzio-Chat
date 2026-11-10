// =============================================================================
// JUZZIO v1.2.0 — Admin Paneli → "Juzzio Community"
//  Juzzio Topluluğu resmî kanalına "Juzzio Official" (uygulama logosu) adına paylaşım:
//  metin, bağlantı (URL), görsel, video, müzik veya herhangi bir dosya. "Paylaş" tüm
//  kullanıcılara (hepsi otomatik üye) bildirimle ulaşır. Sürüm duyuruları CI tarafından
//  otomatik gönderilir; bu sayfa elle duyurular içindir.
//  Sunucu: admin_community_post (yalnız Juzzio yöneticisi).
// =============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType, PlatformFile;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme_and_locale.dart';
import '../core/juzzio_community.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_motion.dart';

class JuzzioAdminCommunityTab extends StatefulWidget {
  const JuzzioAdminCommunityTab({super.key});

  @override
  State<JuzzioAdminCommunityTab> createState() => _JuzzioAdminCommunityTabState();
}

class _JuzzioAdminCommunityTabState extends State<JuzzioAdminCommunityTab> {
  final _text = TextEditingController();
  final _url = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _file;
  bool _busy = false;
  int _sent = 0;

  String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  void _snack(String t, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(t), backgroundColor: error ? JuzzioColors.red500 : JuzzioColors.emerald500),
    );
  }

  Future<void> _pickMedia(bool video) async {
    try {
      final x = video
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 2560);
      if (x == null || !mounted) return;
      setState(() => _file = File(x.path));
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e), error: true);
    }
  }

  Future<void> _pickFile({bool audio = false}) async {
    try {
      final PlatformFile? f = await FilePicker.pickFile(type: audio ? FileType.audio : FileType.any);
      if (f == null || !mounted) return;
      final path = f.path;
      if (path == null) {
        _snack(_l('Dosyaya erişilemedi.', 'Could not access the file.', 'Kein Zugriff auf die Datei.'), error: true);
        return;
      }
      setState(() => _file = File(path));
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e), error: true);
    }
  }

  String get _composed {
    final t = _text.text.trim();
    final u = _url.text.trim();
    if (u.isEmpty) return t;
    final link = u.startsWith('http') ? u : 'https://$u';
    return t.isEmpty ? link : '$t\n\n🔗 $link';
  }

  bool get _canSend => !_busy && (_composed.isNotEmpty || _file != null);

  Future<void> _share() async {
    if (!_canSend) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.instance.postCommunity(text: _composed, file: _file);
      if (!mounted) return;
      JuzzioHaptics.success();
      setState(() {
        _text.clear();
        _url.clear();
        _file = null;
        _sent++;
      });
      _snack(_l('Juzzio Topluluğu\'nda paylaşıldı ✔', 'Shared to Juzzio Community ✔', 'In der Juzzio Community geteilt ✔'));
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'image' => Icons.image_rounded,
        'video' => Icons.videocam_rounded,
        'audio' => Icons.music_note_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final tc = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    final kind = _file == null ? null : juzzioCommunityKindFor(_file!.path);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        JuzzioGlass(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(kJuzzioLogoAvatar.substring(6), width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(kJuzzioOfficialName, style: TextStyle(color: tc, fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 5),
                    const Icon(Icons.verified_rounded, color: Color(0xFF1D9BF0), size: 17),
                  ]),
                  Text('${juzzioCommunityDisplayTitle()} · ${_l('herkes üye', 'everyone is a member', 'alle sind Mitglied')}',
                      style: TextStyle(color: t2, fontSize: 12.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              _l('Buradan paylaştığın her şey Juzzio Topluluğu kanalında tüm kullanıcılara bildirimle ulaşır. Sürüm duyuruları her güncellemede otomatik gönderilir.',
                  'Everything you share here reaches every user in the Juzzio Community channel with a notification. Release announcements are posted automatically on every update.',
                  'Alles, was du hier teilst, erreicht alle Nutzer im Juzzio-Community-Kanal. Release-Ankündigungen werden automatisch gepostet.'),
              style: TextStyle(color: t2, fontSize: 13, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        JuzzioGlass(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 10,
              maxLength: 3500,
              style: TextStyle(color: tc, fontSize: 15, height: 1.4),
              decoration: InputDecoration(
                hintText: _l('Topluluğa ne duyurmak istersin?', 'What do you want to announce?', 'Was möchtest du ankündigen?'),
                hintStyle: TextStyle(color: t2),
                border: InputBorder.none,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: JuzzioGlassTokens.surface, borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                style: TextStyle(color: tc),
                decoration: InputDecoration(
                  icon: Icon(Icons.link_rounded, color: t2),
                  hintText: _l('Bağlantı (isteğe bağlı)', 'Link (optional)', 'Link (optional)'),
                  hintStyle: TextStyle(color: t2),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.image_rounded, _l('Görsel', 'Image', 'Bild'), () => _pickMedia(false)),
              _chip(Icons.videocam_rounded, 'Video', () => _pickMedia(true)),
              _chip(Icons.music_note_rounded, _l('Müzik', 'Music', 'Musik'), () => _pickFile(audio: true)),
              _chip(Icons.attach_file_rounded, _l('Dosya', 'File', 'Datei'), () => _pickFile()),
            ]),
            if (_file != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: JuzzioGlassTokens.surfaceStrong,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JuzzioGlassTokens.border),
                ),
                child: Row(children: [
                  if (kind == 'image')
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_file!, width: 54, height: 54, fit: BoxFit.cover))
                  else
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: JuzzioGlassTokens.glow.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                      child: Icon(_kindIcon(kind ?? 'document'), color: JuzzioGlassTokens.glowText),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_file!.path.split(Platform.pathSeparator).last,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: tc, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => setState(() => _file = null),
                    icon: Icon(Icons.close_rounded, color: t2),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            JuzzioGlassButton(
              label: _l('Paylaş', 'Share', 'Teilen'),
              icon: Icons.campaign_rounded,
              expand: true,
              loading: _busy,
              onTap: _canSend ? _share : null,
            ),
            if (_sent > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_l('Bu oturumda $_sent paylaşım yapıldı.', '$_sent post(s) shared this session.', '$_sent Beitrag/Beiträge geteilt.'),
                    textAlign: TextAlign.center, style: TextStyle(color: t2, fontSize: 12.5)),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: JuzzioGlassTokens.glowText),
        label: Text(label, style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700)),
        backgroundColor: JuzzioGlassTokens.surface,
        side: BorderSide(color: JuzzioGlassTokens.border),
        shape: const StadiumBorder(),
        onPressed: _busy ? null : onTap,
      );
}
