// =============================================================================
// JUZZIO v0.9.0 — Sohbetler > Arama > Filtreler (son talimat §4.4)
//  Filtreler: metin, kişi (sohbet), tarih aralığı, fotoğraf, video, belge, bağlantı, ses kaydı,
//  kayıtlı mesaj. Uçtan uca şifreli mesajlar sunucuda aranamaz (içerik sunucuda yok) → sunucu
//  yalnız tür/tarih/sohbet/üyelik (RLS) ile daraltır; METİN ve BAĞLANTI eşleşmesi mesajlar
//  CİHAZDA çözüldükten sonra yapılır. Son [kScanLimit] uygun mesaj taranır (ekranda belirtilir).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_e2ee.dart';
import '../services/juzzio_life_service.dart';
import '../services/supabase_service.dart';

const int kScanLimit = 400;

/// Arama filtresi (saf; birim testli).
class JuzzioMessageSearchFilter {
  const JuzzioMessageSearchFilter({
    this.text = '',
    this.roomId,
    this.from,
    this.to,
    this.types = const <String>{},
    this.linksOnly = false,
    this.savedOnly = false,
  });

  final String text;
  final String? roomId;
  final DateTime? from;
  final DateTime? to;

  /// image | video | document | voice (boş = tümü)
  final Set<String> types;
  final bool linksOnly;
  final bool savedOnly;

  static final RegExp linkRe = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);

  JuzzioMessageSearchFilter copyWith({
    String? text,
    String? roomId,
    bool clearRoom = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    Set<String>? types,
    bool? linksOnly,
    bool? savedOnly,
  }) =>
      JuzzioMessageSearchFilter(
        text: text ?? this.text,
        roomId: clearRoom ? null : (roomId ?? this.roomId),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        types: types ?? this.types,
        linksOnly: linksOnly ?? this.linksOnly,
        savedOnly: savedOnly ?? this.savedOnly,
      );

  bool get isEmpty =>
      text.trim().isEmpty && roomId == null && from == null && to == null && types.isEmpty && !linksOnly && !savedOnly;

  /// Çözülmüş mesaja uygulanan istemci tarafı eşleşme (büyük/küçük harf ve Türkçe İ/ı duyarsız).
  bool matches(JuzzioMessage m, {required bool isSaved}) {
    if (m.isDeleted) return false;
    if (savedOnly && !isSaved) return false;
    if (types.isNotEmpty && !types.contains(m.messageType)) return false;
    final created = m.createdAt.toLocal();
    if (from != null && created.isBefore(from!)) return false;
    if (to != null && !created.isBefore(to!.add(const Duration(days: 1)))) return false;
    final body = '${m.originalText} ${m.documentName ?? ''}';
    if (linksOnly && !linkRe.hasMatch(body)) return false;
    final q = text.trim();
    if (q.isNotEmpty && !fold(body).contains(fold(q))) return false;
    return true;
  }

  static String fold(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('ı', 'i');
}

class JuzzioMessageSearchPage extends StatefulWidget {
  const JuzzioMessageSearchPage({super.key, required this.rooms, required this.onOpenRoom, this.initialRoomId});

  /// (oda kimliği, görünen ad) — kişi/sohbet filtresi için
  final List<(String, String)> rooms;
  final ValueChanged<String> onOpenRoom;
  final String? initialRoomId;

  @override
  State<JuzzioMessageSearchPage> createState() => _JuzzioMessageSearchPageState();
}

class _JuzzioMessageSearchPageState extends State<JuzzioMessageSearchPage> {
  final _app = JuzzioAppController.instance;
  final _q = TextEditingController();
  late JuzzioMessageSearchFilter _f = JuzzioMessageSearchFilter(roomId: widget.initialRoomId);
  List<JuzzioMessage> _scanned = const [];
  bool _loading = false;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Sunucu tarafı daraltma (tür, tarih, sohbet); metin cihazda süzülür.
  Future<void> _fetch() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = Supabase.instance.client.from('messages').select().eq('is_deleted', false);
      if (_f.roomId != null) query = query.eq('room_id', _f.roomId!);
      if (_f.types.isNotEmpty) query = query.inFilter('message_type', _f.types.toList());
      if (_f.from != null) query = query.gte('created_at', _f.from!.toUtc().toIso8601String());
      if (_f.to != null) query = query.lt('created_at', _f.to!.add(const Duration(days: 1)).toUtc().toIso8601String());
      final rows = await query.order('created_at', ascending: false).limit(kScanLimit);
      final list = [for (final r in (rows as List).whereType<Map>()) JuzzioMessage.fromMap(Map<String, dynamic>.from(r))];
      final dec = await JuzzioE2ee.instance.decryptAll(list);
      if (!mounted || gen != _gen) return;
      setState(() => _scanned = dec);
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e);
    }
    if (mounted && gen == _gen) setState(() => _loading = false);
  }

  void _update(JuzzioMessageSearchFilter f, {bool refetch = true}) {
    setState(() => _f = f);
    if (refetch) _fetch();
  }

  String _roomName(String id) {
    for (final r in widget.rooms) {
      if (r.$1 == id) return r.$2;
    }
    return _app.trEn('Sohbet', 'Chat', 'Chat');
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final life = JuzzioLifeService.instance;
    final results = _scanned.where((m) => _f.matches(m, isSaved: life.isMessageSaved(m.id))).toList();
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: FilterChip(label: Text(label), selected: on, onSelected: (_) => onTap()),
        );
    Set<String> toggled(String t) {
      final next = {..._f.types};
      if (!next.remove(t)) next.add(t);
      return next;
    }

    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: TextField(
          controller: _q,
          autofocus: true,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: _app.trEn('Mesajlarda ara…', 'Search messages…', 'Nachrichten durchsuchen…'),
            border: InputBorder.none,
          ),
          onChanged: (v) => _update(_f.copyWith(text: v), refetch: false),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                chip(_app.trEn('Fotoğraf', 'Photos', 'Fotos'), _f.types.contains('image'), () => _update(_f.copyWith(types: toggled('image')))),
                chip(_app.trEn('Video', 'Videos', 'Videos'), _f.types.contains('video'), () => _update(_f.copyWith(types: toggled('video')))),
                chip(_app.trEn('Belge', 'Documents', 'Dokumente'), _f.types.contains('document'), () => _update(_f.copyWith(types: toggled('document')))),
                chip(_app.trEn('Ses kaydı', 'Voice', 'Sprache'), _f.types.contains('voice'), () => _update(_f.copyWith(types: toggled('voice')))),
                chip(_app.trEn('Bağlantı', 'Links', 'Links'), _f.linksOnly, () => _update(_f.copyWith(linksOnly: !_f.linksOnly), refetch: false)),
                chip(_app.trEn('Kayıtlı', 'Saved', 'Gespeichert'), _f.savedOnly, () => _update(_f.copyWith(savedOnly: !_f.savedOnly), refetch: false)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _f.roomId,
                    dropdownColor: p.cardBg,
                    hint: Text(_app.trEn('Tüm sohbetler / kişiler', 'All chats / people', 'Alle Chats / Personen')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(_app.trEn('Tüm sohbetler', 'All chats', 'Alle Chats'))),
                      for (final r in widget.rooms)
                        DropdownMenuItem<String?>(value: r.$1, child: Text(r.$2, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => _update(v == null ? _f.copyWith(clearRoom: true) : _f.copyWith(roomId: v)),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(_f.from == null
                      ? _app.trEn('Tarih', 'Date', 'Datum')
                      : '${_f.from!.day}.${_f.from!.month}–${_f.to?.day ?? ''}.${_f.to?.month ?? ''}'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (r != null) _update(_f.copyWith(from: r.start, to: r.end));
                  },
                ),
                if (_f.from != null)
                  IconButton(
                    tooltip: _app.trEn('Tarihi temizle', 'Clear date', 'Datum löschen'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _update(_f.copyWith(clearDates: true)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _app.trEn(
                  'Şifreli mesajlar yalnızca bu cihazda aranır · son $kScanLimit mesaj tarandı',
                  'Encrypted messages are searched only on this device · last $kScanLimit messages scanned',
                  'Verschlüsselte Nachrichten werden nur auf diesem Gerät durchsucht · letzte $kScanLimit Nachrichten'),
              style: TextStyle(color: p.textMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: _loading && _scanned.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(SupabaseService.instance.friendlyError(_error!), style: TextStyle(color: p.textSecondary)),
                          FilledButton(onPressed: _fetch, child: Text(_app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'))),
                        ]),
                      )
                    : results.isEmpty
                        ? Center(
                            child: Text(_app.trEn('Sonuç yok', 'No results', 'Keine Ergebnisse'), style: TextStyle(color: p.textSecondary)),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final m = results[i];
                              final t = m.createdAt.toLocal();
                              return JuzzioGlass(
                                radius: 16,
                                child: ListTile(
                                  title: Text(
                                    m.originalText.isNotEmpty ? m.originalText : (m.documentName ?? m.messageType),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.textPrimary),
                                  ),
                                  subtitle: Text(
                                    '${_roomName(m.roomId)} · ${m.senderName} · ${t.day}.${t.month}.${t.year}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.textSecondary, fontSize: 12),
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onOpenRoom(m.roomId);
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
