// =============================================================================
// JUZZIO v0.9.0 — Profil > Ayarlar > Depolama > Dosya Merkezi (C-A5)
//  Üyesi olduğum sohbetlerdeki medya / belge / ses mesajlarının listesi (RLS ile).
//  Yalnızca listeler; hiçbir mesajı, anahtarı veya dosyayı SİLMEZ. Önbellek temizliği
//  Depolama sayfasındaki onaylı "Önbelleği Temizle" ile yapılır.
//  Açıklamalar E2EE ise cihazda çözülür; şifreli medya ham URL ile AÇILMAZ (sohbet içinde açılır).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_e2ee.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

enum JuzzioFileKind { media, documents, voice }

class JuzzioFileCenterFilter {
  static const Map<JuzzioFileKind, List<String>> types = {
    JuzzioFileKind.media: ['image', 'video'],
    JuzzioFileKind.documents: ['document'],
    JuzzioFileKind.voice: ['voice'],
  };

  static JuzzioFileKind? kindOf(String messageType) {
    for (final e in types.entries) {
      if (e.value.contains(messageType)) return e.key;
    }
    return null;
  }

  static Map<JuzzioFileKind, int> counts(Iterable<String> messageTypes) {
    final out = {for (final k in JuzzioFileKind.values) k: 0};
    for (final t in messageTypes) {
      final k = kindOf(t);
      if (k != null) out[k] = out[k]! + 1;
    }
    return out;
  }
}

class JuzzioFileCenterPage extends StatefulWidget {
  const JuzzioFileCenterPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioFileCenterPage()));

  @override
  State<JuzzioFileCenterPage> createState() => _JuzzioFileCenterPageState();
}

class _JuzzioFileCenterPageState extends State<JuzzioFileCenterPage> {
  static const int _limit = 300;
  final _app = JuzzioAppController.instance;
  List<JuzzioMessage> _items = const [];
  JuzzioFileKind _kind = JuzzioFileKind.media;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = JuzzioFileCenterFilter.types.values.expand((e) => e).toList();
      final rows = await Supabase.instance.client
          .from('messages')
          .select()
          .inFilter('message_type', all)
          .order('created_at', ascending: false)
          .limit(_limit);
      final msgs = [
        for (final r in (rows as List).whereType<Map>()) JuzzioMessage.fromMap(Map<String, dynamic>.from(r)),
      ].where((m) => !m.isDeleted).toList();
      _items = await JuzzioE2ee.instance.decryptAll(msgs);
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  String _kindLabel(JuzzioFileKind k) => switch (k) {
        JuzzioFileKind.media => _app.trEn('Medya', 'Media', 'Medien'),
        JuzzioFileKind.documents => _app.trEn('Belgeler', 'Documents', 'Dokumente'),
        JuzzioFileKind.voice => _app.trEn('Ses', 'Voice', 'Sprache'),
      };

  IconData _icon(String t) => switch (t) {
        'image' => Icons.image_rounded,
        'video' => Icons.movie_rounded,
        'document' => Icons.description_rounded,
        _ => Icons.mic_rounded,
      };

  String _title(JuzzioMessage m) {
    if (m.messageType == 'document') return m.documentName ?? _app.trEn('Belge', 'Document', 'Dokument');
    if (m.messageType == 'voice') {
      final s = (m.audioDurationMs / 1000).round();
      return '${_app.trEn('Sesli mesaj', 'Voice message', 'Sprachnachricht')} · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    if (m.originalText.isNotEmpty) return m.originalText;
    return m.messageType == 'image' ? _app.trEn('Fotoğraf', 'Photo', 'Foto') : 'Video';
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final counts = JuzzioFileCenterFilter.counts(_items.map((m) => m.messageType));
    final visible = _items.where((m) => JuzzioFileCenterFilter.kindOf(m.messageType) == _kind).toList();
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(SupabaseService.instance.friendlyError(_error!), style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: Text(_app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'))),
        ]),
      );
    } else {
      body = Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(spacing: 8, children: [
            for (final k in JuzzioFileKind.values)
              ChoiceChip(
                label: Text('${_kindLabel(k)} (${counts[k]})'),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _app.trEn('Son $_limit dosya mesajı gösterilir. Açmak için ilgili sohbete git.',
                'Shows the latest $_limit file messages. Open them from the chat.',
                'Zeigt die letzten $_limit Dateinachrichten. Im Chat öffnen.'),
            style: TextStyle(color: p.textMuted, fontSize: 12),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(_app.trEn('Bu kategoride dosya yok', 'No files in this category', 'Keine Dateien'), style: TextStyle(color: p.textSecondary)))
              : JuzzioClothRefresh(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = visible[i];
                      final t = m.createdAt.toLocal();
                      return JuzzioGlass(
                        radius: 18,
                        child: ListTile(
                          leading: Icon(_icon(m.messageType), color: p.amberGlow),
                          title: Text(_title(m), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textPrimary)),
                          subtitle: Text('${m.senderName.isNotEmpty ? '${m.senderName} · ' : ''}${t.day}.${t.month}.${t.year}',
                              style: TextStyle(color: p.textSecondary, fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ]);
    }
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Dosya Merkezi', 'File Center', 'Dateizentrale')),
      ),
      body: body,
    );
  }
}
