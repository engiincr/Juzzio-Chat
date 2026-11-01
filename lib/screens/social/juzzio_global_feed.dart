// =============================================================================
// JUZZIO v0.5.0 — Küresel Akış (Keşfet'in yerine)
//  X / Reddit tarzı, yazı öncelikli akış. Dünyanın her yerinden paylaşımlar
//  okuyan kişinin kendi diline OTOMATİK çevrilir; "Orijinali gör" ile asıl
//  metin açılır. Yazı paylaşımı doğrudan buradan yapılır; fotoğraf / video
//  paylaşımı için içerik stüdyosu açılır. Tamamı nötr cam tasarım dilindedir.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_colors.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../models/social_models.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/social_common_widgets.dart';

class JuzzioGlobalFeedView extends StatefulWidget {
  final JuzzioUserProfile currentUser;
  final void Function(String userId) onOpenProfile;
  final void Function(JuzzioPost post, {bool focusComments}) onOpenPost;
  final VoidCallback onOpenSearch;
  final VoidCallback onCreateMedia;
  final VoidCallback onAddFriend;

  const JuzzioGlobalFeedView({
    super.key,
    required this.currentUser,
    required this.onOpenProfile,
    required this.onOpenPost,
    required this.onOpenSearch,
    required this.onCreateMedia,
    required this.onAddFriend,
  });

  @override
  State<JuzzioGlobalFeedView> createState() => _JuzzioGlobalFeedViewState();
}

class _JuzzioGlobalFeedViewState extends State<JuzzioGlobalFeedView> {
  final JuzzioAppController _app = JuzzioAppController.instance;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String _tab = 'all'; // 'all' | 'following'
  String _topic = 'all'; // 'all' veya kJuzzioFeedTopics öğesi (sunucu filtresi)
  String _composeTopic = 'general';
  RealtimeChannel? _channel;
  int _pendingNew = 0;
  String _translatedLang = '';
  List<JuzzioPost> _posts = <JuzzioPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _posting = false;
  String? _error;

  // postId -> çeviri; orijinali açık olanlar
  final Map<String, String> _translated = {};
  final Set<String> _translating = {};
  final Set<String> _showOriginal = {};
  final Set<String> _translationFailed = {};

  String get _targetLang => _app.uiLang.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _subscribeRealtime();
  }

  @override
  void dispose() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch).catchError((_) => 'error');
    }
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Yeni paylaşımlar canlı gelir: listeyi zıplatmadan üstte "N yeni paylaşım" balonu gösterilir.
  void _subscribeRealtime() {
    try {
      _channel = Supabase.instance.client
          .channel('juzzio-global-feed-${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'posts',
            callback: _onRealtimeInsert,
          )
          .subscribe();
    } catch (_) {
      _channel = null;
    }
  }

  void _onRealtimeInsert(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty || row['is_deleted'] == true) return;
    if ((row['author_id'] ?? '').toString() == widget.currentUser.id) return;
    if ((row['visibility'] ?? 'public').toString() != 'public') return;
    if (_tab == 'following') return;
    if (_topic != 'all' && (row['topic'] ?? 'general').toString() != _topic) return;
    if (_posts.any((p) => p.id == id)) return;
    setState(() => _pendingNew++);
  }

  Future<void> _showNewPosts() async {
    HapticFeedback.selectionClick();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
    await _load();
  }

  String _topicLabel(String t) {
    switch (t) {
      case 'all':
        return _app.trEn('Tümü', 'All', 'Alle');
      case 'general':
        return _app.trEn('Genel', 'General', 'Allgemein');
      case 'news':
        return _app.trEn('Haberler', 'News', 'Nachrichten');
      case 'technology':
        return _app.trEn('Teknoloji', 'Technology', 'Technik');
      case 'science':
        return _app.trEn('Bilim', 'Science', 'Wissenschaft');
      case 'sports':
        return _app.trEn('Spor', 'Sports', 'Sport');
      case 'entertainment':
        return _app.trEn('Eğlence', 'Entertainment', 'Unterhaltung');
      case 'music':
        return _app.trEn('Müzik', 'Music', 'Musik');
      case 'gaming':
        return _app.trEn('Oyun', 'Gaming', 'Gaming');
      case 'travel':
        return _app.trEn('Seyahat', 'Travel', 'Reisen');
      case 'food':
        return _app.trEn('Yemek', 'Food', 'Essen');
      case 'art':
        return _app.trEn('Sanat', 'Art', 'Kunst');
      case 'humor':
        return _app.trEn('Mizah', 'Humor', 'Humor');
    }
    return t;
  }

  String? get _topicFilter => _topic == 'all' ? null : _topic;

  Future<void> _load() async {
    // Uygulama dili değiştiyse eski çeviriler atılır; yenileme ve sayfalamada hep okuyucunun dili korunur
    if (_translatedLang != _targetLang) {
      _translated.clear();
      _translating.clear();
      _translationFailed.clear();
      _showOriginal.clear();
      _translatedLang = _targetLang;
    }
    setState(() {
      _loading = true;
      _error = null;
      _pendingNew = 0;
    });
    try {
      final list = await JuzzioSocialService.instance.fetchFeedPosts(filter: _tab, limit: 25, topic: _topicFilter);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _hasMore = list.length >= 25;
        _loading = false;
      });
      _translateBatch(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final more = await JuzzioSocialService.instance.fetchFeedPosts(
        filter: _tab,
        limit: 25,
        beforeCreatedAt: _posts.last.createdAt,
        topic: _topicFilter,
      );
      if (!mounted) return;
      final known = _posts.map((e) => e.id).toSet();
      final fresh = more.where((p) => !known.contains(p.id)).toList();
      setState(() {
        _posts.addAll(fresh);
        _hasMore = more.length >= 25;
      });
      _translateBatch(fresh);
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  /// Görünen gönderileri tek istekte okuyucunun diline çevirir. Sunucu çeviriyi
  /// (içerik, dil, metin karması) anahtarıyla önbelleğe alır; aynı gönderi her
  /// okuyucu için yeniden çevrilmez. Sunucu yanıt vermezse tek tek çeviriye düşülür.
  Future<void> _translateBatch(List<JuzzioPost> posts) async {
    final pending = posts
        .where((p) => p.caption.trim().isNotEmpty && !_translated.containsKey(p.id) && !_translating.contains(p.id))
        .toList();
    if (pending.isEmpty) return;
    _translating.addAll(pending.map((p) => p.id));
    final res = await SupabaseService.instance.translateContentBatch(
      kind: 'post',
      ids: pending.map((p) => p.id).toList(),
      targetLang: _targetLang,
    );
    if (!mounted) return;
    final missing = <JuzzioPost>[];
    setState(() {
      for (final p in pending) {
        final r = res[p.id];
        if (r == null) {
          missing.add(p);
          continue;
        }
        _translating.remove(p.id);
        _translated[p.id] = r.text;
        if (!r.ok) _translationFailed.add(p.id);
      }
    });
    for (final p in missing) {
      SupabaseService.instance.translateText(text: p.caption, targetLang: _targetLang).then((t) {
        if (!mounted) return;
        setState(() {
          _translating.remove(p.id);
          _translated[p.id] = t;
        });
      }).catchError((_) {
        _translating.remove(p.id);
      });
    }
  }

  Future<void> _publishText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final post = await JuzzioSocialService.instance
          .createTextPost(author: widget.currentUser, text: text, topic: _composeTopic);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _composer.clear();
      FocusScope.of(context).unfocus();
      setState(() {
        if (_topic == 'all' || _topic == post.topic) _posts.insert(0, post);
        _translated[post.id] = text;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleLike(int i) async {
    final cur = _posts[i];
    HapticFeedback.lightImpact();
    try {
      final updated = await JuzzioSocialService.instance.togglePostLike(post: cur, currentUser: widget.currentUser);
      if (mounted) setState(() => _posts[i] = updated);
    } catch (_) {}
  }

  Future<void> _toggleSave(int i) async {
    try {
      final updated = await JuzzioSocialService.instance.toggleSavePost(_posts[i]);
      if (mounted) setState(() => _posts[i] = updated);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: JuzzioGlassTokens.backdrop,
      child: Stack(
        children: [
          Positioned.fill(child: _feedScroll()),
          if (_pendingNew > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _showNewPosts,
                  child: JuzzioGlass(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 16, color: JuzzioGlassTokens.textPrimary),
                        const SizedBox(width: 6),
                        Text(
                          _app.trEn('$_pendingNew yeni paylaşım', '$_pendingNew new posts', '$_pendingNew neue Beiträge'),
                          style: TextStyle(
                            color: JuzzioGlassTokens.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _feedScroll() {
    return RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _composerCard()),
            SliverToBoxAdapter(child: _tabs()),
            SliverToBoxAdapter(child: _topicChips()),
            if (_loading && _posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.textSecondary)),
                        const SizedBox(height: 12),
                        JuzzioGlassButton(label: _app.trEn('Tekrar dene', 'Retry', 'Erneut versuchen'), onTap: _load),
                      ],
                    ),
                  ),
                ),
              )
            else if (_posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _app.trEn('Henüz paylaşım yok. İlk sözü sen söyle!', 'No posts yet. Say the first word!',
                          'Noch keine Beiträge. Sag das erste Wort!'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 15),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                sliver: SliverList.separated(
                  itemCount: _posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _postCard(i),
                ),
              ),
          ],
        ),
    );
  }

  Widget _topicChips() {
    final topics = <String>['all', ...kJuzzioFeedTopics];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        itemCount: topics.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final t = topics[i];
          final sel = _topic == t;
          return GestureDetector(
            onTap: () {
              if (sel) return;
              HapticFeedback.selectionClick();
              setState(() => _topic = t);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? JuzzioGlassTokens.surfaceStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: sel ? JuzzioGlassTokens.textSecondary : JuzzioGlassTokens.border),
              ),
              alignment: Alignment.center,
              child: Text(
                _topicLabel(t),
                style: TextStyle(
                  color: sel ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickComposeTopic() async {
    final picked = await showJuzzioGlassSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _app.trEn('Konu seç', 'Choose a topic', 'Thema wählen'),
              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kJuzzioFeedTopics)
                  ChoiceChip(
                    label: Text(_topicLabel(t)),
                    selected: _composeTopic == t,
                    onSelected: (_) => Navigator.of(ctx).pop(t),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _composeTopic = picked);
  }

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 14, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _app.trEn('Küresel', 'Global', 'Global'),
                    style: TextStyle(
                      color: JuzzioGlassTokens.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  Text(
                    _app.trEn('Dünyadan paylaşımlar, senin dilinde', 'Posts from the world, in your language',
                        'Beiträge aus aller Welt, in deiner Sprache'),
                    style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            JuzzioGlassIconButton(
              icon: Icons.person_add_alt_1_rounded,
              tooltip: _app.trEn('Arkadaş ekle', 'Add friend', 'Freund hinzufügen'),
              onTap: widget.onAddFriend,
            ),
            const SizedBox(width: 8),
            JuzzioGlassIconButton(
              icon: Icons.search_rounded,
              tooltip: _app.trEn('Ara', 'Search', 'Suchen'),
              onTap: widget.onOpenSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: JuzzioGlass(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JuzzioGlassAvatar(
                  imageUrl: widget.currentUser.avatarUrl,
                  name: widget.currentUser.displayName,
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: 1000,
                    style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 16),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: _app.trEn('Dünyaya ne söylemek istersin?', 'What do you want to tell the world?',
                          'Was möchtest du der Welt sagen?'),
                      hintStyle: TextStyle(color: JuzzioGlassTokens.textMuted),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 46),
                JuzzioGlassIconButton(
                  icon: Icons.add_photo_alternate_outlined,
                  size: 36,
                  tooltip: _app.trEn('Fotoğraf / video', 'Photo / video', 'Foto / Video'),
                  onTap: widget.onCreateMedia,
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickComposeTopic,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: JuzzioGlassTokens.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: JuzzioGlassTokens.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tag_rounded, size: 14, color: JuzzioGlassTokens.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          _topicLabel(_composeTopic),
                          style: TextStyle(
                              color: JuzzioGlassTokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.translate_rounded, size: 15, color: JuzzioGlassTokens.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _app.trEn('Herkes kendi dilinde okur', 'Everyone reads it in their language',
                        'Jeder liest es in seiner Sprache'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 11.5),
                  ),
                ),
                const SizedBox(width: 8),
                JuzzioGlassButton(
                  label: _posting ? '...' : _app.trEn('Paylaş', 'Post', 'Posten'),
                  height: 36,
                  onTap: _composer.text.trim().isEmpty || _posting ? null : _publishText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String key, String label) {
      final sel = _tab == key;
      return GestureDetector(
        onTap: () {
          if (sel) return;
          HapticFeedback.selectionClick();
          setState(() => _tab = key);
          _load();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? JuzzioGlassTokens.accent : JuzzioGlassTokens.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: sel ? Colors.transparent : JuzzioGlassTokens.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: sel ? JuzzioGlassTokens.onAccent : JuzzioGlassTokens.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Row(
        children: [
          tab('all', _app.trEn('Dünya', 'World', 'Welt')),
          const SizedBox(width: 8),
          tab('following', _app.trEn('Takip ettiklerim', 'Following', 'Gefolgt')),
        ],
      ),
    );
  }

  Widget _postCard(int i) {
    final post = _posts[i];
    final original = post.caption.trim();
    final translated = _translated[post.id];
    final showOriginal = _showOriginal.contains(post.id);
    final wasTranslated = translated != null && translated.trim() != original;
    final body = showOriginal || translated == null ? original : translated;
    final media = post.isText ? null : (post.isVideo ? (post.coverUrl ?? post.primaryMediaUrl) : post.primaryMediaUrl);

    return GestureDetector(
      onTap: () => widget.onOpenPost(post),
      child: JuzzioGlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => widget.onOpenProfile(post.authorId),
                  child: JuzzioGlassAvatar(imageUrl: post.authorAvatarUrl, name: post.authorDisplayName, radius: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onOpenProfile(post.authorId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorDisplayName.isEmpty ? post.authorUsername : post.authorDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: JuzzioGlassTokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (post.authorIsVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded, color: JuzzioColors.sky500, size: 16),
                            ],
                          ],
                        ),
                        Text(
                          '@${post.authorUsername} · ${JuzzioSocialTokens.formatRelativeTime(post.createdAt, _app)}'
                          '${post.topic != 'general' ? ' · #${_topicLabel(post.topic)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                body,
                style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 15.5, height: 1.4),
              ),
            ],
            if (_translationFailed.contains(post.id))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                _app.trEn('Çevrilemedi, orijinal gösteriliyor', 'Translation unavailable, showing original',
                    'Übersetzung nicht verfügbar, Original wird angezeigt'),
                style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12),
                ),
              ),
            if (wasTranslated && !_translationFailed.contains(post.id))
              GestureDetector(
                onTap: () => setState(() {
                  if (showOriginal) {
                    _showOriginal.remove(post.id);
                  } else {
                    _showOriginal.add(post.id);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate_rounded, size: 14, color: JuzzioGlassTokens.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        showOriginal
                            ? _app.trEn('Çeviriyi gör', 'Show translation', 'Übersetzung zeigen')
                            : _app.trEn('Otomatik çevrildi · Orijinali gör', 'Auto-translated · Show original',
                                'Automatisch übersetzt · Original zeigen'),
                        style: TextStyle(color: JuzzioGlassTokens.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            if (media != null && media.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: post.aspectRatio > 0 ? post.aspectRatio.clamp(0.8, 1.91).toDouble() : 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        media,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: JuzzioColors.obsidianElevated),
                      ),
                      if (post.isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _action(
                  post.isLikedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  post.likesCount,
                  () => _toggleLike(i),
                  color: post.isLikedByMe ? const Color(0xFFFF3B30) : null,
                ),
                _action(Icons.mode_comment_outlined, post.commentsCount,
                    () => widget.onOpenPost(post, focusComments: true)),
                IconButton(
                  tooltip: _app.trEn('Paylaş', 'Share', 'Teilen'),
                  onPressed: () => showJuzzioSharePostModalSheet(context: context, post: post, currentUser: widget.currentUser),
                  icon: Icon(Icons.ios_share_rounded, color: JuzzioGlassTokens.textSecondary, size: 20),
                ),
                const Spacer(),
                if (post.authorId != widget.currentUser.id)
                  IconButton(
                    tooltip: _app.trEn('Şikâyet et', 'Report', 'Melden'),
                    onPressed: () => showJuzzioReportModalSheet(
                      context: context,
                      targetType: 'post',
                      targetId: post.id,
                      targetOwnerId: post.authorId,
                    ),
                    icon: Icon(Icons.outlined_flag_rounded, color: JuzzioGlassTokens.textMuted, size: 20),
                  ),
                IconButton(
                  onPressed: () => _toggleSave(i),
                  icon: Icon(
                    post.isSavedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: post.isSavedByMe ? JuzzioGlassTokens.textPrimary : JuzzioGlassTokens.textSecondary,
                    size: 21,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, int count, VoidCallback onTap, {Color? color}) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color ?? JuzzioGlassTokens.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      icon: Icon(icon, size: 20, color: color ?? JuzzioGlassTokens.textSecondary),
      label: Text(count > 0 ? '$count' : '', style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
