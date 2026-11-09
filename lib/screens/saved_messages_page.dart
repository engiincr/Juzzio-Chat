// =============================================================================
// JUZZIO v0.9.0 — Sohbet > Kayıtlı mesajlar (son talimat §4.3)
//  Yalnız bu sohbette benim kaydettiklerim. Mesajlar oda üyeliği (RLS) ile okunur ve E2EE ise
//  CİHAZDA çözülür. Kaydı kaldır; mesaja dokununca sohbete dönülür. Karşı taraf bilgilendirilmez.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_e2ee.dart';
import '../services/juzzio_life_service.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

class JuzzioSavedMessagesPage extends StatefulWidget {
  const JuzzioSavedMessagesPage({super.key, required this.roomId, required this.title});
  final String roomId;
  final String title;

  static Future<void> open(BuildContext context, {required String roomId, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioSavedMessagesPage(roomId: roomId, title: title)));

  @override
  State<JuzzioSavedMessagesPage> createState() => _JuzzioSavedMessagesPageState();
}

class _JuzzioSavedMessagesPageState extends State<JuzzioSavedMessagesPage> {
  final _app = JuzzioAppController.instance;
  List<JuzzioMessage> _items = const [];
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
      final ids = await JuzzioLifeService.instance.savedMessageIdsForRoom(widget.roomId);
      if (ids.isEmpty) {
        _items = const [];
      } else {
        final rows = await Supabase.instance.client.from('messages').select().inFilter('id', ids).eq('room_id', widget.roomId);
        final byId = {
          for (final r in (rows as List).whereType<Map>()) r['id'].toString(): JuzzioMessage.fromMap(Map<String, dynamic>.from(r)),
        };
        final ordered = [for (final id in ids) if (byId[id] != null && !byId[id]!.isDeleted) byId[id]!];
        _items = await JuzzioE2ee.instance.decryptAll(ordered);
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unsave(JuzzioMessage m) async {
    try {
      await JuzzioLifeService.instance.toggleSaved(roomId: m.roomId, messageId: m.id);
      setState(() => _items = _items.where((x) => x.id != m.id).toList());
    } catch (e) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  String _label(JuzzioMessage m) {
    switch (m.messageType) {
      case 'voice':
        return '🎤 ${_app.trEn('Sesli mesaj', 'Voice message', 'Sprachnachricht')}';
      case 'image':
        return '📷 ${m.originalText.isNotEmpty ? m.originalText : _app.trEn('Fotoğraf', 'Photo', 'Foto')}';
      case 'video':
        return '🎬 ${m.originalText.isNotEmpty ? m.originalText : 'Video'}';
      case 'document':
        return '📄 ${m.documentName ?? _app.trEn('Belge', 'Document', 'Dokument')}';
      default:
        return m.originalText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
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
    } else if (_items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _app.trEn('Bu sohbette kayıtlı mesaj yok. Bir mesaja uzun basıp "Kaydet"i seç.',
                'No saved messages in this chat. Long-press a message and choose "Save".',
                'Keine gespeicherten Nachrichten. Nachricht lange drücken und „Speichern“ wählen.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = _items[i];
          final t = m.createdAt.toLocal();
          return JuzzioGlass(
            radius: 18,
            child: ListTile(
              leading: const Icon(Icons.bookmark_rounded, color: Color(0xFFFFD60A)),
              title: Text(_label(m), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textPrimary)),
              subtitle: Text('${m.senderName.isNotEmpty ? '${m.senderName} · ' : ''}${t.day}.${t.month}.${t.year}',
                  style: TextStyle(color: p.textSecondary, fontSize: 12)),
              trailing: IconButton(
                tooltip: _app.trEn('Kaydı kaldır', 'Unsave', 'Nicht mehr speichern'),
                icon: Icon(Icons.bookmark_remove_rounded, color: p.textSecondary),
                onPressed: () => _unsave(m),
              ),
              // İlgili sohbete git: bu sayfa sohbet bilgilerinden açılır → sohbete geri dön
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Kayıtlı mesajlar', 'Saved messages', 'Gespeicherte Nachrichten')),
      ),
      body: JuzzioClothRefresh(onRefresh: _load, child: body),
    );
  }
}
