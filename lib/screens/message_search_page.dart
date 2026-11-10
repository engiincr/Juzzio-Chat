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
import '../widgets/juzzio_motion.dart';
import '../widgets/juzzio_ui_kit.dart';

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
  const JuzzioMessageSearchPage({
    super.key,
    required this.rooms,
    required this.onOpenRoom,
    this.initialRoomId,
    this.onOpenMessage,
  });

  /// (oda kimliği, görünen ad) — kişi/sohbet filtresi için
  final List<(String, String)> rooms;
  final ValueChanged<String> onOpenRoom;

  /// v1.2.0: bir sohbetin içinden açıldığında arama YALNIZ bu sohbette yapılır
  /// (kapsam çipinden "Tüm sohbetler"e geçilebilir).
  final String? initialRoomId;

  /// v1.2.0: sonuca dokununca sohbet açılır ve o mesaja kaydırılıp vurgulanır
  final void Function(String roomId, String messageId)? onOpenMessage;

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
    _q.addListener(() => setState(() {}));
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

  IconData _typeIcon(String t) => switch (t) {
        'image' => Icons.photo_rounded,
        'video' => Icons.videocam_rounded,
        'document' => Icons.description_rounded,
        'voice' => Icons.mic_rounded,
        _ => Icons.chat_bubble_rounded,
      };

  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(t, now)) return _app.trEn('Bugün', 'Today', 'Heute');
    if (DateUtils.isSameDay(t, now.subtract(const Duration(days: 1)))) return _app.trEn('Dün', 'Yesterday', 'Gestern');
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }

  /// Eşleşen kısmı vurgulayan metin (Türkçe İ/ı duyarsız)
  Widget _highlight(String text, String q, TextStyle base, Color hl) {
    if (q.trim().isEmpty) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: base);
    final ft = JuzzioMessageSearchFilter.fold(text);
    final fq = JuzzioMessageSearchFilter.fold(q.trim());
    final i = ft.length == text.length ? ft.indexOf(fq) : -1;
    if (i < 0) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: base);
    final start = (i - 40).clamp(0, text.length);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: '${start > 0 ? '…' : ''}${text.substring(start, i)}'),
        TextSpan(
          text: text.substring(i, i + fq.length),
          style: TextStyle(fontWeight: FontWeight.w900, backgroundColor: hl.withValues(alpha: 0.28)),
        ),
        TextSpan(text: text.substring(i + fq.length)),
      ]),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final life = JuzzioLifeService.instance;
    final results = _scanned.where((m) => _f.matches(m, isSaved: life.isMessageSaved(m.id))).toList();
    final accent = JuzzioGlassTokens.glow;
    final scoped = _f.roomId != null;
    Set<String> toggled(String t) {
      final next = {..._f.types};
      if (!next.remove(t)) next.add(t);
      return next;
    }

    Widget chip(IconData icon, String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilterChip(
            showCheckmark: false,
            avatar: Icon(icon, size: 16, color: on ? JuzzioGlassTokens.onAccent : p.textSecondary),
            label: Text(label),
            labelStyle: TextStyle(color: on ? JuzzioGlassTokens.onAccent : p.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5),
            selected: on,
            selectedColor: accent,
            backgroundColor: JuzzioGlassTokens.surfaceStrong,
            side: BorderSide(color: on ? accent : JuzzioGlassTokens.border),
            shape: const StadiumBorder(),
            onSelected: (_) => onTap(),
          ),
        );

    // tarih başlıklı liste
    final items = <Widget>[];
    String? lastDay;
    for (final m in results) {
      final t = m.createdAt.toLocal();
      final day = _dayLabel(t);
      if (day != lastDay) {
        lastDay = day;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
          child: Text(day, style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ));
      }
      final body = m.originalText.isNotEmpty ? m.originalText : (m.documentName ?? '');
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: JuzzioGlassTokens.surfaceStrong,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: JuzzioGlassTokens.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).pop();
              if (widget.onOpenMessage != null) {
                widget.onOpenMessage!(m.roomId, m.id);
              } else {
                widget.onOpenRoom(m.roomId);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: Icon(_typeIcon(m.messageType), size: 18, color: JuzzioGlassTokens.glowText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          scoped ? (m.senderName.isNotEmpty ? m.senderName : _roomName(m.roomId)) : '${_roomName(m.roomId)}${m.senderName.isNotEmpty ? ' · ${m.senderName}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                      Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
                    ]),
                    const SizedBox(height: 3),
                    if (body.isNotEmpty)
                      _highlight(body, _f.text, TextStyle(color: p.textSecondary, fontSize: 13.5, height: 1.35), accent)
                    else
                      Text(_app.trEn('Medya', 'Media', 'Medien'), style: TextStyle(color: p.textSecondary, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ---- cam arama kutusu ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
              child: Row(children: [
                IconButton(icon: Icon(Icons.arrow_back_rounded, color: p.textPrimary), onPressed: () => Navigator.of(context).pop()),
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: JuzzioGlassTokens.surfaceStrong,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: JuzzioGlassTokens.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.search_rounded, color: p.textSecondary, size: 21),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _q,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(color: p.textPrimary, fontSize: 15.5),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: scoped
                                ? _app.trEn('${_roomName(_f.roomId!)} içinde ara…', 'Search in ${_roomName(_f.roomId!)}…', 'In ${_roomName(_f.roomId!)} suchen…')
                                : _app.trEn('Tüm mesajlarda ara…', 'Search all messages…', 'Alle Nachrichten durchsuchen…'),
                            hintStyle: TextStyle(color: p.textSecondary),
                            border: InputBorder.none,
                          ),
                          onChanged: (v) => _update(_f.copyWith(text: v), refetch: false),
                        ),
                      ),
                      if (_q.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _q.clear();
                            _update(_f.copyWith(text: ''), refetch: false);
                          },
                          child: Icon(Icons.cancel_rounded, color: p.textSecondary, size: 19),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
            // ---- kapsam: bu sohbet / tüm sohbetler ----
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                children: [
                  if (widget.initialRoomId != null)
                    chip(Icons.chat_rounded, _roomName(widget.initialRoomId!), _f.roomId == widget.initialRoomId,
                        () => _update(_f.copyWith(roomId: widget.initialRoomId))),
                  chip(Icons.forum_rounded, _app.trEn('Tüm sohbetler', 'All chats', 'Alle Chats'), _f.roomId == null,
                      () => _update(_f.copyWith(clearRoom: true))),
                  if (widget.initialRoomId == null && widget.rooms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ActionChip(
                        avatar: Icon(Icons.person_search_rounded, size: 16, color: p.textSecondary),
                        label: Text(_f.roomId == null ? _app.trEn('Kişi / sohbet seç', 'Pick a chat', 'Chat wählen') : _roomName(_f.roomId!)),
                        labelStyle: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5),
                        backgroundColor: JuzzioGlassTokens.surfaceStrong,
                        side: BorderSide(color: _f.roomId != null ? accent : JuzzioGlassTokens.border),
                        shape: const StadiumBorder(),
                        onPressed: _pickRoom,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ActionChip(
                      avatar: Icon(Icons.date_range_rounded, size: 16, color: p.textSecondary),
                      label: Text(_f.from == null
                          ? _app.trEn('Tarih', 'Date', 'Datum')
                          : '${_f.from!.day}.${_f.from!.month}–${_f.to?.day ?? ''}.${_f.to?.month ?? ''}'),
                      labelStyle: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5),
                      backgroundColor: JuzzioGlassTokens.surfaceStrong,
                      side: BorderSide(color: _f.from != null ? accent : JuzzioGlassTokens.border),
                      shape: const StadiumBorder(),
                      onPressed: () async {
                        if (_f.from != null) {
                          _update(_f.copyWith(clearDates: true));
                          return;
                        }
                        final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (r != null) _update(_f.copyWith(from: r.start, to: r.end));
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                children: [
                  chip(Icons.photo_rounded, _app.trEn('Fotoğraf', 'Photos', 'Fotos'), _f.types.contains('image'), () => _update(_f.copyWith(types: toggled('image')))),
                  chip(Icons.videocam_rounded, _app.trEn('Video', 'Videos', 'Videos'), _f.types.contains('video'), () => _update(_f.copyWith(types: toggled('video')))),
                  chip(Icons.description_rounded, _app.trEn('Belge', 'Documents', 'Dokumente'), _f.types.contains('document'), () => _update(_f.copyWith(types: toggled('document')))),
                  chip(Icons.mic_rounded, _app.trEn('Ses kaydı', 'Voice', 'Sprache'), _f.types.contains('voice'), () => _update(_f.copyWith(types: toggled('voice')))),
                  chip(Icons.link_rounded, _app.trEn('Bağlantı', 'Links', 'Links'), _f.linksOnly, () => _update(_f.copyWith(linksOnly: !_f.linksOnly), refetch: false)),
                  chip(Icons.star_rounded, _app.trEn('Kayıtlı', 'Saved', 'Gespeichert'), _f.savedOnly, () => _update(_f.copyWith(savedOnly: !_f.savedOnly), refetch: false)),
                ],
              ),
            ),
            if (_loading && _scanned.isNotEmpty) const JuzzioSparklerBar(minHeight: 2),
            Expanded(
              child: _loading && _scanned.isEmpty
                  ? const JuzzioListSkeleton()
                  : _error != null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(SupabaseService.instance.friendlyError(_error!), style: TextStyle(color: p.textSecondary)),
                            const SizedBox(height: 10),
                            FilledButton(onPressed: _fetch, child: Text(_app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'))),
                          ]),
                        )
                      : results.isEmpty
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.manage_search_rounded, size: 56, color: p.textSecondary.withValues(alpha: 0.5)),
                                const SizedBox(height: 10),
                                Text(
                                  _f.text.trim().isEmpty
                                      ? _app.trEn('Aramak için yazmaya başla', 'Start typing to search', 'Tippe, um zu suchen')
                                      : _app.trEn('"${_f.text.trim()}" için sonuç yok', 'No results for "${_f.text.trim()}"', 'Keine Ergebnisse für „${_f.text.trim()}“'),
                                  style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600),
                                ),
                              ]),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                                  child: Text(
                                    _app.trEn('${results.length} sonuç', '${results.length} results', '${results.length} Ergebnisse'),
                                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 14),
                                  ),
                                ),
                                ...items,
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _app.trEn(
                                        '🔒 Şifreli mesajlar yalnızca bu cihazda aranır · son $kScanLimit mesaj tarandı',
                                        '🔒 Encrypted messages are searched only on this device · last $kScanLimit messages scanned',
                                        '🔒 Verschlüsselte Nachrichten werden nur auf diesem Gerät durchsucht'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: p.textMuted, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRoom() async {
    final p = JuzzioPalette(_app.isDark);
    final picked = await showJuzzioSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.sheetBg,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final r in widget.rooms)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(Icons.chat_bubble_outline_rounded, color: p.textSecondary),
                title: Text(r.$2, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
                trailing: _f.roomId == r.$1 ? Icon(Icons.check_rounded, color: JuzzioGlassTokens.glowText) : null,
                onTap: () => Navigator.pop(ctx, r.$1),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) _update(_f.copyWith(roomId: picked));
  }
}
