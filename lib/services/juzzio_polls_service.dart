// =============================================================================
// JUZZIO v0.9.0 — G26 anketler + G27 zamanlanmış mesajlar (SQL 10.23)
//  Birebir sohbette zamanlanmış mesaj CİHAZDA E2EE ile şifrelenip öyle saklanır; şifreleme
//  yapılamazsa zamanlanmaz (fail-closed). Anketler yalnız grup sohbetlerinde.
// =============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import 'juzzio_e2ee.dart';

class JuzzioPollResults {
  const JuzzioPollResults({
    required this.question,
    required this.options,
    required this.counts,
    required this.myVotes,
    required this.multi,
    required this.anonymous,
    required this.closed,
    required this.isCreator,
    required this.voters,
    required this.byOption,
  });
  final String question;
  final List<String> options;
  final List<int> counts;
  final Set<int> myVotes;
  final bool multi;
  final bool anonymous;
  final bool closed;
  final bool isCreator;
  final int voters;
  final Map<int, List<String>>? byOption; // gizli ankette null

  int get totalVotes => counts.fold(0, (a, b) => a + b);

  /// 0..1 arası oran (toplam oy 0 ise 0).
  double share(int i) => totalVotes == 0 || i >= counts.length ? 0 : counts[i] / totalVotes;

  static JuzzioPollResults fromMap(Map<String, dynamic> m) {
    final opts = [for (final o in (m['options'] is List ? m['options'] as List : const [])) o.toString()];
    final counts = [for (final c in (m['counts'] is List ? m['counts'] as List : const [])) int.tryParse('$c') ?? 0];
    Map<int, List<String>>? by;
    final raw = m['by_option'];
    if (raw is Map) {
      by = {
        for (final e in raw.entries)
          if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): [for (final n in (e.value is List ? e.value as List : const [])) n.toString()],
      };
    }
    return JuzzioPollResults(
      question: (m['question'] ?? '').toString(),
      options: opts,
      counts: List<int>.generate(opts.length, (i) => i < counts.length ? counts[i] : 0),
      myVotes: {for (final v in (m['my_votes'] is List ? m['my_votes'] as List : const [])) int.tryParse('$v') ?? -1}..remove(-1),
      multi: m['multi'] == true,
      anonymous: m['anonymous'] == true,
      closed: m['closed'] == true,
      isCreator: m['mine_creator'] == true,
      voters: int.tryParse('${m['voters']}') ?? 0,
      byOption: m['anonymous'] == true ? null : by,
    );
  }

  /// Bir seçeneğe dokununca gönderilecek yeni oy kümesi.
  static List<int> nextVotes({required Set<int> current, required int tapped, required bool multi}) {
    if (multi) {
      final s = {...current};
      if (!s.remove(tapped)) s.add(tapped);
      return s.toList()..sort();
    }
    return current.length == 1 && current.contains(tapped) ? <int>[] : <int>[tapped];
  }
}

class JuzzioScheduledMessage {
  const JuzzioScheduledMessage({required this.id, required this.roomId, required this.sendAt, required this.preview, required this.encrypted});
  final String id;
  final String roomId;
  final DateTime sendAt;
  final String preview;
  final bool encrypted;

  static JuzzioScheduledMessage fromMap(Map<String, dynamic> m) => JuzzioScheduledMessage(
        id: (m['id'] ?? '').toString(),
        roomId: (m['room_id'] ?? '').toString(),
        sendAt: DateTime.tryParse((m['send_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
        preview: (m['preview'] ?? '').toString(),
        encrypted: m['e2ee'] != null,
      );
}

class JuzzioPollsService {
  JuzzioPollsService._();
  static final JuzzioPollsService instance = JuzzioPollsService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<String> createPoll({required String roomId, required String question, required List<String> options, bool multi = false, bool anonymous = false}) async {
    final r = await _db.rpc('create_poll', params: {
      'p_room': roomId,
      'p_question': question,
      'p_options': options,
      'p_multi': multi,
      'p_anonymous': anonymous,
    });
    return r.toString();
  }

  Future<JuzzioPollResults> results(String pollId) async {
    final r = await _db.rpc('poll_results', params: {'p_poll': pollId});
    return JuzzioPollResults.fromMap(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<void> vote(String pollId, List<int> options) => _db.rpc('vote_poll', params: {'p_poll': pollId, 'p_options': options});

  Future<bool> close(String pollId) async => (await _db.rpc('close_poll', params: {'p_poll': pollId})) == true;

  /// Birebir sohbette içerik cihazda şifrelenir; şifrelenemezse istisna (zamanlanmaz).
  Future<void> schedule({required String roomId, required DateTime sendAt, required String text}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('empty');
    final direct = await JuzzioE2ee.instance.isDirectRoom(roomId);
    if (direct == null) throw const JuzzioE2eeRequiredException(JuzzioE2eeStatus.unavailable);
    if (direct) {
      final out = await JuzzioE2ee.instance.encryptForRoomStrict(roomId, text: clean, translated: '');
      if (out.status != JuzzioE2eeStatus.encrypted || out.payload == null) {
        throw JuzzioE2eeRequiredException(out.status == JuzzioE2eeStatus.peerKeyMissing ? JuzzioE2eeStatus.peerKeyMissing : JuzzioE2eeStatus.unavailable);
      }
      await _db.rpc('schedule_message', params: {'p_room': roomId, 'p_send_at': sendAt.toUtc().toIso8601String(), 'p_body': '', 'p_e2ee': out.payload});
    } else {
      await _db.rpc('schedule_message', params: {'p_room': roomId, 'p_send_at': sendAt.toUtc().toIso8601String(), 'p_body': clean});
    }
  }

  Future<List<JuzzioScheduledMessage>> pending(String roomId) async {
    final rows = await _db.from('scheduled_messages').select().eq('room_id', roomId).eq('status', 'pending').order('send_at');
    return [for (final r in (rows as List).whereType<Map>()) JuzzioScheduledMessage.fromMap(Map<String, dynamic>.from(r))];
  }

  Future<bool> cancel(String id) async => (await _db.rpc('cancel_scheduled_message', params: {'p_id': id})) == true;
}
