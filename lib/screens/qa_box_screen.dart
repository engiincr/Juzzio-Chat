// =============================================================================
// JUZZIO v0.9.5 — Anonim soru kutusu
//  • Kendi kutun: başlık, anonim soruya izin, gelen sorular → yanıtla / reddet.
//  • Başkasının profili: soru sor (anonim veya adınla) + yanıtlanmış sorular.
//  • Anonim gönderenin kimliği kutu sahibine ASLA gönderilmez (sunucu RPC'si NULL döner).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';
import '../widgets/juzzio_ui_kit.dart';
import '../widgets/juzzio_motion.dart';

class JuzzioQaInboxScreen extends StatefulWidget {
  const JuzzioQaInboxScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioQaInboxScreen()));

  @override
  State<JuzzioQaInboxScreen> createState() => _JuzzioQaInboxScreenState();
}

class _JuzzioQaInboxScreenState extends State<JuzzioQaInboxScreen> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  final _title = TextEditingController();
  bool _anon = true;
  bool _active = false;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final box = await _db.from('qa_boxes').select().eq('owner_id', uid).maybeSingle();
      final inbox = await _db.rpc('qa_inbox');
      if (!mounted) return;
      setState(() {
        _active = box?['is_active'] == true;
        _anon = box == null || box['allow_anonymous'] == true;
        if (_title.text.isEmpty) _title.text = (box?['title'] ?? _app.trEn('Bana bir şey sor', 'Ask me anything', 'Frag mich was')).toString();
        _items = [for (final r in (inbox is List ? inbox : const [])) Map<String, dynamic>.from(r as Map)];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = SupabaseService.instance.friendlyError(e);
        });
      }
    }
  }

  Future<void> _saveBox(bool active) async {
    try {
      await _db.rpc('qa_setup_box', params: {'p_title': _title.text.trim(), 'p_allow_anonymous': _anon, 'p_active': active});
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _answer(Map<String, dynamic> q) async {
    final ctrl = TextEditingController(text: (q['answer'] ?? '').toString());
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((q['question'] ?? '').toString()),
        content: TextField(controller: ctrl, maxLength: 1000, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: _app.trEn('Yanıtın', 'Your answer', 'Deine Antwort'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reject'), child: Text(_app.trEn('Sil', 'Delete', 'Löschen'), style: const TextStyle(color: Colors.redAccent))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'answer'), child: Text(_app.trEn('Yanıtla', 'Answer', 'Antworten'))),
        ],
      ),
    );
    if (res == null) return;
    try {
      await _db.rpc('qa_answer', params: {'p_id': q['id'], 'p_answer': ctrl.text.trim(), 'p_reject': res == 'reject'});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(title: Text(_app.trEn('Soru kutum', 'My question box', 'Mein Fragekasten'))),
      body: _loading
          ? const JuzzioListSkeleton()
          : JuzzioClothRefresh(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextField(controller: _title, maxLength: 120, decoration: InputDecoration(labelText: _app.trEn('Kutu başlığı', 'Box title', 'Titel'))),
                JuzzioSwitchListTile(style: JuzzioToggleStyle.check,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_app.trEn('Anonim sorulara izin ver', 'Allow anonymous questions', 'Anonyme Fragen erlauben')),
                  subtitle: Text(_app.trEn('Anonim soranın kimliği sana hiçbir zaman gösterilmez.', 'You never see who asked anonymously.', 'Du siehst nie, wer anonym fragt.')),
                  value: _anon,
                  onChanged: (v) => setState(() => _anon = v),
                ),
                JuzzioSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_app.trEn('Kutu açık (profilimde görünsün)', 'Box open (show on my profile)', 'Kasten offen')),
                  value: _active,
                  onChanged: (v) => _saveBox(v),
                ),
                FilledButton(onPressed: () => _saveBox(_active), child: Text(_app.trEn('Kaydet', 'Save', 'Speichern'))),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                const SizedBox(height: 18),
                Text(_app.trEn('Gelen sorular', 'Questions', 'Fragen'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (_items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_app.trEn('Henüz soru yok.', 'No questions yet.', 'Noch keine Fragen.'), style: TextStyle(color: p.textSecondary))),
                for (final q in _items)
                  Card(
                    child: ListTile(
                      leading: Icon(q['status'] == 'answered' ? Icons.mark_chat_read_rounded : Icons.help_outline_rounded),
                      title: Text((q['question'] ?? '').toString()),
                      subtitle: Text(q['status'] == 'answered'
                          ? '↳ ${q['answer']}'
                          : (q['is_anonymous'] == true ? _app.trEn('Anonim', 'Anonymous', 'Anonym') : (q['sender_name'] ?? '').toString())),
                      onTap: () => _answer(q),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// Başkasının profilinde: soru sor + yanıtlanmış sorular.
class JuzzioQaProfileSection extends StatefulWidget {
  const JuzzioQaProfileSection({super.key, required this.ownerId});
  final String ownerId;

  @override
  State<JuzzioQaProfileSection> createState() => _JuzzioQaProfileSectionState();
}

class _JuzzioQaProfileSectionState extends State<JuzzioQaProfileSection> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  Map<String, dynamic>? _box;
  List<Map<String, dynamic>> _answers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await _db.from('qa_boxes').select().eq('owner_id', widget.ownerId).eq('is_active', true).maybeSingle();
      final pub = box == null ? const [] : await _db.rpc('qa_public', params: {'p_owner': widget.ownerId});
      if (!mounted) return;
      setState(() {
        _box = box;
        _answers = [for (final r in (pub is List ? pub : const [])) Map<String, dynamic>.from(r as Map)];
      });
    } catch (_) {}
  }

  Future<void> _ask() async {
    final ctrl = TextEditingController();
    var anon = _box?['allow_anonymous'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text((_box?['title'] ?? '').toString()),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, maxLength: 500, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: _app.trEn('Sorun', 'Your question', 'Deine Frage'))),
            if (_box?['allow_anonymous'] == true)
              JuzzioSwitchListTile(contentPadding: EdgeInsets.zero, title: Text(_app.trEn('Anonim sor', 'Ask anonymously', 'Anonym fragen')), value: anon, onChanged: (v) => setS(() => anon = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_app.trEn('Gönder', 'Send', 'Senden'))),
          ],
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await _db.rpc('qa_ask', params: {'p_owner': widget.ownerId, 'p_text': ctrl.text.trim(), 'p_anonymous': anon});
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_app.trEn('Sorun gönderildi', 'Question sent', 'Frage gesendet'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_box == null) return const SizedBox.shrink();
    final p = JuzzioPalette(_app.isDark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(onPressed: _ask, icon: const Icon(Icons.help_outline_rounded), label: Text((_box?['title'] ?? '').toString())),
        for (final a in _answers.take(5))
          ListTile(
            dense: true,
            title: Text((a['question'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text((a['answer'] ?? '').toString(), style: TextStyle(color: p.textSecondary)),
          ),
      ]),
    );
  }
}
