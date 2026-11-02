// =============================================================================
// JUZZIO v0.9.0 — @etiketleme istemci tarafı (ek paket N-B)
//  • JuzzioMentionParser: SQL'deki juzzio_extract_mentions ile AYNI kural (3–30 karakter,
//    harf/rakam/_/. ; e-posta içindeki @ etiket değildir; sondaki nokta alınmaz).
//  • JuzzioMentionText: metindeki @ad belirteçlerini tıklanabilir yapar → profil.
//  • JuzzioMentionSuggestions: yazarken "@ab" için sunucudan (suggest_mentions; engel ve
//    etiketlenme tercihi sunucuda uygulanır) öneri getirir, seçilince metne ekler.
// Etiket kaydı ve bildirim SUNUCUDA (tetikleyici) yapılır; istemci yalnız gösterir/önerir.
// =============================================================================

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme_and_locale.dart';

class JuzzioMentionSegment {
  const JuzzioMentionSegment(this.text, [this.username]);
  final String text;

  /// Etiketse küçük harfli kullanıcı adı, değilse null.
  final String? username;
  bool get isMention => username != null;
}

class JuzzioMentionParser {
  JuzzioMentionParser._();

  static final RegExp _re = RegExp(r'(^|[^A-Za-z0-9_.@])@([A-Za-z0-9_.]{3,30})(?![A-Za-z0-9_.])');

  /// Metni düz metin ve etiket parçalarına böler (sıra korunur).
  static List<JuzzioMentionSegment> segments(String text) {
    final out = <JuzzioMentionSegment>[];
    var last = 0;
    for (final m in _re.allMatches(text)) {
      final raw = m.group(2)!;
      final name = raw.replaceAll(RegExp(r'\.+$'), '');
      if (name.length < 3) continue;
      final atIndex = m.start + m.group(1)!.length;
      final end = atIndex + 1 + name.length;
      if (atIndex > last) out.add(JuzzioMentionSegment(text.substring(last, atIndex)));
      out.add(JuzzioMentionSegment(text.substring(atIndex, end), name.toLowerCase()));
      last = end;
    }
    if (last < text.length) out.add(JuzzioMentionSegment(text.substring(last)));
    return out;
  }

  /// Benzersiz etiketler (en fazla 10, ilk görülme sırası) — sunucu kuralıyla aynı.
  static List<String> usernames(String text) {
    final seen = <String>{};
    for (final s in segments(text)) {
      if (s.isMention && seen.length < 10) seen.add(s.username!);
    }
    return seen.toList();
  }

  /// İmlecin hemen önündeki yazılmakta olan "@ab" sorgusu (yoksa null).
  static ({int start, String query})? activeQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    final m = RegExp(r'(^|[^A-Za-z0-9_.@])@([A-Za-z0-9_.]{0,30})$').firstMatch(before);
    if (m == null) return null;
    final start = m.start + m.group(1)!.length;
    return (start: start, query: m.group(2)!);
  }

  /// Sorguyu seçilen kullanıcı adıyla değiştirir; yeni metin ve imleç konumu.
  static ({String text, int cursor}) insert(String text, int cursor, String username) {
    final q = activeQuery(text, cursor);
    if (q == null) return (text: text, cursor: cursor);
    final replacement = '@$username ';
    final after = text.substring(cursor);
    final next = text.substring(0, q.start) + replacement + after;
    return (text: next, cursor: q.start + replacement.length);
  }
}

/// Etiketleri tıklanabilir gösteren metin.
class JuzzioMentionText extends StatefulWidget {
  const JuzzioMentionText(this.text, {super.key, required this.style, this.onTapUsername, this.mentionColor});
  final String text;
  final TextStyle style;
  final Color? mentionColor;
  final ValueChanged<String>? onTapUsername;

  @override
  State<JuzzioMentionText> createState() => _JuzzioMentionTextState();
}

class _JuzzioMentionTextState extends State<JuzzioMentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final color = widget.mentionColor ?? Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    for (final seg in JuzzioMentionParser.segments(widget.text)) {
      if (!seg.isMention || widget.onTapUsername == null) {
        spans.add(TextSpan(
          text: seg.text,
          style: seg.isMention ? TextStyle(color: color, fontWeight: FontWeight.w700) : null,
        ));
        continue;
      }
      final r = TapGestureRecognizer()..onTap = () => widget.onTapUsername!(seg.username!);
      _recognizers.add(r);
      spans.add(TextSpan(
        text: seg.text,
        recognizer: r,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
        semanticsLabel: seg.text,
      ));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

class JuzzioMentionCandidate {
  const JuzzioMentionCandidate({required this.userId, required this.username, required this.displayName, this.avatarUrl});
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
}

/// TextField'ın üstüne/altına konan öneri şeridi. Sorgu yokken yer kaplamaz.
class JuzzioMentionSuggestions extends StatefulWidget {
  const JuzzioMentionSuggestions({super.key, required this.controller, this.fetcher});
  final TextEditingController controller;

  /// Test için; varsayılan suggest_mentions RPC.
  final Future<List<JuzzioMentionCandidate>> Function(String query)? fetcher;

  @override
  State<JuzzioMentionSuggestions> createState() => _JuzzioMentionSuggestionsState();
}

class _JuzzioMentionSuggestionsState extends State<JuzzioMentionSuggestions> {
  Timer? _debounce;
  String? _query;
  List<JuzzioMentionCandidate> _items = const [];
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  static Future<List<JuzzioMentionCandidate>> _rpc(String q) async {
    final res = await Supabase.instance.client.rpc('suggest_mentions', params: {'p_query': q, 'p_limit': 8});
    if (res is! List) return const [];
    return [
      for (final r in res.whereType<Map>())
        JuzzioMentionCandidate(
          userId: r['user_id'].toString(),
          username: (r['username'] ?? '').toString(),
          displayName: (r['display_name'] ?? '').toString(),
          avatarUrl: r['avatar_url']?.toString(),
        ),
    ];
  }

  void _onChanged() {
    final v = widget.controller.value;
    final q = JuzzioMentionParser.activeQuery(v.text, v.selection.baseOffset);
    final query = (q == null || q.query.isEmpty) ? null : q.query;
    if (query == _query) return;
    _query = query;
    _debounce?.cancel();
    if (query == null) {
      if (_items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    final gen = ++_gen;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = await (widget.fetcher ?? _rpc)(query);
        if (!mounted || gen != _gen) return;
        setState(() => _items = list);
      } catch (_) {
        if (mounted && gen == _gen) setState(() => _items = const []);
      }
    });
  }

  void _pick(JuzzioMentionCandidate c) {
    final v = widget.controller.value;
    final r = JuzzioMentionParser.insert(v.text, v.selection.baseOffset, c.username);
    widget.controller.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
    setState(() => _items = const []);
    _query = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return Semantics(
      container: true,
      label: app.trEn('Etiket önerileri', 'Mention suggestions', 'Erwähnungsvorschläge'),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final c = _items[i];
            return ActionChip(
              avatar: CircleAvatar(
                backgroundColor: p.cardBg,
                child: Text(c.username.isEmpty ? '?' : c.username[0].toUpperCase(),
                    style: TextStyle(color: p.textPrimary, fontSize: 11)),
              ),
              label: Text('@${c.username}', style: TextStyle(color: p.textPrimary)),
              backgroundColor: p.cardBg,
              tooltip: c.displayName,
              onPressed: () => _pick(c),
            );
          },
        ),
      ),
    );
  }
}
