// =============================================================================
// JUZZIO v0.9.3 — Admin Paneli → "Juzzio Story"
//  Uygulama tanıtım (teaser) görsel/video hikâyelerini "Juzzio Official" (mavi tik) adına
//  paylaşır. Bu hikâyeler Durumlar şeridinde HERKESTE ilk sırada görünür (arkadaşlık gerekmez);
//  başlıktaki isme dokunulunca @tugkancr profiline gidilir.
//  Sunucu: admin_post_official_story / admin_delete_official_story (yalnız @tugkancr).
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

class JuzzioAdminStoryTab extends StatefulWidget {
  const JuzzioAdminStoryTab({super.key});

  @override
  State<JuzzioAdminStoryTab> createState() => _JuzzioAdminStoryTabState();
}

class _JuzzioAdminStoryTabState extends State<JuzzioAdminStoryTab> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  File? _file;
  bool _isVideo = false;
  double _videoSec = 30;
  int _hours = 24;
  bool _busy = false;
  bool _loading = true;
  List<JuzzioStory> _active = const [];

  String _l(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await SupabaseService.instance.client
          .from('stories')
          .select()
          .eq('is_official', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _active = (rows as List).map((e) => JuzzioStory.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String t, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(t), backgroundColor: error ? JuzzioColors.red500 : JuzzioColors.emerald500),
    );
  }

  Future<void> _pick(bool video) async {
    try {
      final x = video
          ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60))
          : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 2160);
      if (x == null || !mounted) return;
      setState(() {
        _file = File(x.path);
        _isVideo = video;
      });
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e), error: true);
    }
  }

  Future<void> _publish() async {
    final f = _file;
    if (f == null || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.instance.postOfficialStory(
        mediaFile: f,
        isVideo: _isVideo,
        caption: _caption.text,
        videoDurationSec: _videoSec.round(),
        hours: _hours,
      );
      if (!mounted) return;
      setState(() {
        _file = null;
        _caption.clear();
      });
      _snack(_l('Juzzio Official hikâyesi yayınlandı ✔', 'Juzzio Official story published ✔', 'Juzzio-Official-Story veröffentlicht ✔'));
      await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(JuzzioStory st) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l('Hikâye silinsin mi?', 'Delete story?', 'Story löschen?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_l('Vazgeç', 'Cancel', 'Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_l('Sil', 'Delete', 'Löschen'), style: const TextStyle(color: JuzzioColors.red500))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.deleteOfficialStory(st.id);
      await _load();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yetki sunucuda denetlenir (yalnız @tugkancr); diğer hesaplarda RPC 'not_allowed' döner.
    final tc = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    return JuzzioClothRefresh(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          JuzzioGlass(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF1D9BF0)),
                  const SizedBox(width: 8),
                  Text('Juzzio Story', style: TextStyle(color: tc, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, color: Color(0xFF1D9BF0), size: 18),
                ]),
                const SizedBox(height: 6),
                Text(
                  _l('Tanıtım görseli veya videosu "Juzzio Official" adına, Durumlar şeridinde herkeste ilk sırada görünür. İsme dokunan @tugkancr profiline gider.',
                      'Teaser image or video posted as "Juzzio Official" — shown first in everyone\'s Stories. Tapping the name opens @tugkancr.',
                      'Teaser-Bild oder -Video als „Juzzio Official" – bei allen zuerst in den Storys. Tippen auf den Namen öffnet @tugkancr.'),
                  style: TextStyle(color: t2, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(_l('Not: paylaşım için uygulamada @tugkancr hesabıyla oturum açık olmalı.', 'Note: you must be signed in as @tugkancr to post.', 'Hinweis: Zum Posten als @tugkancr angemeldet sein.'),
                    style: TextStyle(color: t2, fontSize: 12)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(false),
                      icon: const Icon(Icons.image_rounded),
                      label: Text(_l('Görsel seç', 'Pick image', 'Bild wählen')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(true),
                      icon: const Icon(Icons.videocam_rounded),
                      label: Text(_l('Video seç', 'Pick video', 'Video wählen')),
                    ),
                  ),
                ]),
                if (_file != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 9 / 12,
                      child: _isVideo
                          ? Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 56),
                                const SizedBox(height: 8),
                                Text(_file!.path.split('/').last, style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ]),
                            )
                          : Image.file(_file!, fit: BoxFit.cover),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _caption,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: _l('Açıklama (isteğe bağlı)', 'Caption (optional)', 'Beschreibung (optional)'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                if (_isVideo && _file != null) ...[
                  Text(_l('Video süresi: ${_videoSec.round()} sn', 'Video length: ${_videoSec.round()} s', 'Videolänge: ${_videoSec.round()} s'), style: TextStyle(color: tc)),
                  Slider(value: _videoSec, min: 3, max: 60, divisions: 57, onChanged: (v) => setState(() => _videoSec = v)),
                ],
                Text(_l('Yayında kalma süresi', 'Stays live for', 'Sichtbar für'), style: TextStyle(color: tc, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final h in const [24, 48, 72, 168])
                    ChoiceChip(
                      label: Text(h == 168 ? _l('7 gün', '7 days', '7 Tage') : '$h ${_l('saat', 'h', 'Std.')}'),
                      selected: _hours == h,
                      onSelected: (_) => setState(() => _hours = h),
                    ),
                ]),
                const SizedBox(height: 14),
                JuzzioGlassButton(
                  label: _l('Juzzio Official olarak paylaş', 'Post as Juzzio Official', 'Als Juzzio Official posten'),
                  icon: Icons.send_rounded,
                  expand: true,
                  loading: _busy,
                  onTap: _file == null ? null : _publish,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(_l('Yayındaki resmi hikâyeler', 'Live official stories', 'Aktive offizielle Storys'), style: TextStyle(color: tc, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_active.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(_l('Henüz yok.', 'None yet.', 'Noch keine.'), style: TextStyle(color: t2)))
          else
            for (final st in _active)
              Card(
                child: ListTile(
                  leading: Icon(st.mediaType == 'video' ? Icons.videocam_rounded : Icons.image_rounded, color: const Color(0xFF1D9BF0)),
                  title: Text(st.captionOriginal.isEmpty ? (st.mediaType == 'video' ? 'Video' : _l('Görsel', 'Image', 'Bild')) : st.captionOriginal, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('👁 ${st.viewsCount} · ♥ ${st.likesCount} · ${_l('bitiş', 'ends', 'endet')} ${st.expiresAt.toLocal().toString().substring(0, 16)}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: JuzzioColors.red500), onPressed: () => _delete(st)),
                ),
              ),
        ],
      ),
    );
  }
}
