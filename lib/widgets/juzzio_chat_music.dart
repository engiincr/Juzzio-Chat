// =============================================================================
// JUZZIO v1.2.9 — Sohbette müzik paylaşımı
//  • Ataş menüsü → "Müzik" → parça ara → seç → sohbete müzik kartı gider.
//  • Kart: kapak, şarkı, sanatçı, oynat/durdur, ilerleme, "Apple Music'te aç" atfı ve ⋮ menüsü
//    (Şikâyet et · Profil müziği yap · Bağlantıyı kopyala).
//  • DÜRÜSTLÜK / TELİF: Juzzio'nun müzik kaynağı Apple'ın herkese açık 30 sn ÖNİZLEME servisidir.
//    Instagram'ın müzik kütüphanesi plak şirketleriyle yapılmış özel lisanslara dayanır ve
//    üçüncü taraf uygulamalara açık bir API'si yoktur; o katalog kullanılamaz. Şarkının tamamı
//    yalnız lisanslı platformda (Apple Music) dinlenebilir — kart oraya yönlendirir.
//    Önizleme cihaza indirilmez/önbelleğe alınmaz (yalnız akış).
//  • Otomatik durma: arama gelince/başlatılınca, uygulama arka plana alınınca, başka uygulama
//    ses çalınca, kulaklık çıkınca (JuzzioAudioGuard) ve sohbetten çıkınca durur.
//  • Mesaj biçimi: "[[jmusic:<base64url JSON>]]" (uçtan uca şifreli metin olarak gider).
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme_and_locale.dart';
import '../core/juzzio_text_safety.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_features_service.dart';
import 'juzzio_copy_feedback.dart';
import 'profile_extras.dart';

class JuzzioSharedTrack {
  const JuzzioSharedTrack({required this.url, required this.title, this.artist = '', this.coverUrl = '', this.storeUrl = '', this.startSec = 0});
  final String url;
  final String title;
  final String artist;
  final String coverUrl;
  final String storeUrl;
  final int startSec;

  Map<String, dynamic> toJson() => {
        'u': url,
        't': juzzioSafeCut(title, 120),
        if (artist.isNotEmpty) 'a': juzzioSafeCut(artist, 120),
        if (coverUrl.isNotEmpty) 'c': coverUrl,
        if (storeUrl.isNotEmpty) 's': storeUrl,
        if (startSec > 0) 'o': startSec,
      };
}

bool _httpsOk(String u) => u.isEmpty || (u.startsWith('https://') && Uri.tryParse(u)?.host.isNotEmpty == true);

/// Müzik belirteci üret (saf; test edilir)
String juzzioMusicToken(JuzzioSharedTrack t) => '[[jmusic:${base64Url.encode(utf8.encode(jsonEncode(t.toJson()))).replaceAll('=', '')}]]';

final RegExp _musicRe = RegExp(r'^\[\[jmusic:([A-Za-z0-9_-]{8,2400})\]\]$');

/// Metin bir müzik kartı mı? Yalnız https ve Apple önizleme adresleri kabul edilir (saf; test edilir)
JuzzioSharedTrack? juzzioMusicFromText(String text) {
  final m = _musicRe.firstMatch(text.trim());
  if (m == null) return null;
  try {
    var b = m.group(1)!;
    while (b.length % 4 != 0) {
      b += '=';
    }
    final j = jsonDecode(utf8.decode(base64Url.decode(b)));
    if (j is! Map) return null;
    final url = (j['u'] ?? '').toString();
    final cover = (j['c'] ?? '').toString();
    final store = (j['s'] ?? '').toString();
    if (!url.startsWith('https://') || !juzzioIsApplePreview(url)) return null;
    if (!_httpsOk(cover) || !_httpsOk(store)) return null;
    final title = juzzioWellFormed((j['t'] ?? '').toString()).trim();
    if (title.isEmpty) return null;
    return JuzzioSharedTrack(
      url: url,
      title: title,
      artist: juzzioWellFormed((j['a'] ?? '').toString()).trim(),
      coverUrl: cover,
      storeUrl: store,
      startSec: (j['o'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return null;
  }
}

/// Sohbet listesi önizlemesi: "🎵 Şarkı · Sanatçı"
String juzzioMusicPreview(String text) {
  final t = juzzioMusicFromText(text);
  if (t == null) return text;
  return '🎵 ${[t.title, if (t.artist.isNotEmpty) t.artist].join(' · ')}';
}

class JuzzioChatMusicCard extends StatelessWidget {
  const JuzzioChatMusicCard({super.key, required this.track, required this.isMe, this.onReport});
  final JuzzioSharedTrack track;
  final bool isMe;
  final VoidCallback? onReport;

  Future<void> _menu(BuildContext context) async {
    final app = JuzzioAppController.instance;
    final choice = await showJuzzioGlassSheet<String>(
      context: context,
      builder: (ctx) {
        Widget row(String id, IconData icon, String label, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? JuzzioGlassTokens.textPrimary),
              title: Text(label, style: TextStyle(color: color ?? JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, id),
            );
        return Column(mainAxisSize: MainAxisSize.min, children: [
          row('profile', Icons.account_circle_outlined, app.trEn('Profil müziği yap', 'Set as profile music')),
          row('open', Icons.apple, app.trEn("Tamamını Apple Music'te dinle", 'Listen to the full song on Apple Music')),
          row('copy', Icons.link_rounded, app.trEn('Bağlantıyı kopyala', 'Copy link')),
          if (onReport != null) row('report', Icons.flag_outlined, app.trEn('Şikâyet et', 'Report'), color: const Color(0xFFFF453A)),
          const SizedBox(height: 6),
        ]);
      },
    );
    if (!context.mounted || choice == null) return;
    final link = juzzioAppleMusicLink(storeUrl: track.storeUrl, title: track.title, artist: track.artist);
    switch (choice) {
      case 'profile':
        try {
          await JuzzioFeaturesService.instance.updateProfileMusic(
            musicUrl: track.url,
            startSec: track.startSec,
            title: track.title,
            artist: track.artist,
            coverUrl: track.coverUrl,
          );
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(app.trEn('Profil müziğin güncellendi', 'Your profile music was updated'))));
          }
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.toString())));
        }
      case 'open':
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      case 'copy':
        if (context.mounted) await juzzioCopy(context, link, label: app.trEn('Bağlantı kopyalandı', 'Link copied'));
      case 'report':
        onReport?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final fg = isMe ? Colors.white : JuzzioGlassTokens.textPrimary;
    final sub = fg.withValues(alpha: 0.7);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      child: ValueListenableBuilder<String>(
        valueListenable: JuzzioMusicPlayer.instance.nowPlaying,
        builder: (context, now, _) {
          final playing = now == track.url;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: track.coverUrl.isEmpty
                      ? Container(color: Colors.black26, child: Icon(Icons.music_note_rounded, color: fg))
                      : Image.network(track.coverUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.black26, child: Icon(Icons.music_note_rounded, color: fg))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (track.artist.isNotEmpty)
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(
                      playing ? app.trEn('Önizleme çalıyor · 30 sn', 'Preview playing · 30 s') : app.trEn('30 sn önizleme', '30 s preview'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: JuzzioMusicPlayer.instance.loading,
                builder: (_, loading, __) => IconButton(
                  tooltip: playing ? app.trEn('Durdur', 'Stop') : app.trEn('Oynat', 'Play'),
                  onPressed: () => JuzzioMusicPlayer.instance.toggle(track.url),
                  icon: loading && playing
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                      : Icon(playing ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, color: fg, size: 34),
                ),
              ),
              IconButton(
                tooltip: app.trEn('Diğer', 'More'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _menu(context),
                icon: Icon(Icons.more_vert_rounded, color: sub),
              ),
            ],
          );
        },
      ),
    );
  }
}
