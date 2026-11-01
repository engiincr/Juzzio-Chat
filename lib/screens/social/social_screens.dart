// =============================================================================
// JUZZIO v0.1.0 — Sosyal Medya Ekranları ve Uçtan Uca Etkileşim Akışları
// Bölüm 17 (+ Oluştur Menüsü, Gönderi Üretici, Basılı Tut Video Kaydı),
// Bölüm 21 (Gönderi Detayı & Yorumlar), Bölüm 23.2 (Birleşik Arama & Etiketler),
// Bölüm 24 (Kullanıcı Profili & Takip İlişkileri), Bölüm 25 (Arkadaşlar & İstekler)
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme_and_locale.dart';
import '../../models/social_models.dart';
import '../../services/social_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/social_common_widgets.dart';
import '../profile/juzzio_profile_view.dart';

/// Merkezdeki "+" Oluşturma Seçim Menüsü (Gönderi / Hikâye / İptal)
Future<String?> showJuzzioCreateContentBottomSheet(BuildContext context) async {
  final app = JuzzioAppController.instance;
  final isDark = app.isDark;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: JuzzioSocialTokens.cardBg(isDark),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) {
      Widget item({
        required String value,
        required IconData icon,
        required Color color,
        required String title,
        required String subtitle,
      }) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: JuzzioSocialTokens.textPrimary(isDark),
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: JuzzioSocialTokens.textSecondary(isDark),
              fontSize: 12.5,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: JuzzioSocialTokens.textSecondary(isDark),
          ),
          onTap: () => Navigator.pop(ctx, value),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x59FFFFFF) : const Color(0x40000000),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.loc('Ne paylaşmak istersin?', 'What would you like to share?', 'Was möchtest du teilen?'),
                        style: TextStyle(
                          color: JuzzioSocialTokens.textPrimary(isDark),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      icon: Icon(
                        Icons.close_rounded,
                        color: JuzzioSocialTokens.textSecondary(isDark),
                      ),
                      tooltip: app.loc('Kapat', 'Close', 'Schließen'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              item(
                value: 'post',
                icon: Icons.grid_on_rounded,
                color: JuzzioSocialTokens.royalBlue,
                title: app.loc('Gönderi', 'Post', 'Beitrag'),
                subtitle: app.loc(
                  'Profilinde ve ana akışta fotoğraf, video veya çoklu medya paylaş.',
                  'Share a photo, video, or multi-media post on your feed and profile.', 'Teile einen Foto-, Video- oder Multimedia-Beitrag in deinem Feed und Profil.',
                ),
              ),
              item(
                value: 'story',
                icon: Icons.auto_awesome_motion_rounded,
                color: JuzzioSocialTokens.onlineEmerald,
                title: app.loc('Hikâye / Durum', 'Story / Status', 'Story / Status'),
                subtitle: app.loc(
                  '24 saat sonra süresi dolan fotoğraf, video veya metin durumu paylaş.',
                  'Share a 24-hour photo, video, or text status update.', 'Teile ein 24-Stunden-Foto, -Video oder einen Text-Status.',
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(app.loc('İptal / Kapat', 'Cancel / Close', 'Abbrechen / Schließen')),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Gönderi Detayı ve Yorumlar Ekranı (Bölüm 6.11 & 21)
class JuzzioPostDetailAndCommentsPage extends StatefulWidget {
  final String postId;
  final JuzzioPost? initialPost;
  final JuzzioUserProfile currentUser;
  final bool focusCommentInput;
  final ValueChanged<String>? onOpenProfile;

  const JuzzioPostDetailAndCommentsPage({
    super.key,
    required this.postId,
    this.initialPost,
    required this.currentUser,
    this.focusCommentInput = false,
    this.onOpenProfile,
  });

  @override
  State<JuzzioPostDetailAndCommentsPage> createState() =>
      _JuzzioPostDetailAndCommentsPageState();
}

class _JuzzioPostDetailAndCommentsPageState
    extends State<JuzzioPostDetailAndCommentsPage> {
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  JuzzioPost? _post;
  JuzzioDataLoadState _postState = JuzzioDataLoadState.initialLoading;
  List<JuzzioComment> _comments = <JuzzioComment>[];
  JuzzioDataLoadState _commentsState = JuzzioDataLoadState.initialLoading;
  bool _newestCommentsFirst = false;
  bool _submittingComment = false;
  JuzzioComment? _replyingTo;

  // v0.5: yorumlar okuyucunun diline otomatik çevrilir (sunucu önbellekli)
  final Map<String, String> _commentTr = {};
  final Set<String> _commentOriginal = {};

  Future<void> _translateComments(List<JuzzioComment> list) async {
    final lang = JuzzioAppController.instance.uiLang;
    final pending = list.where((c) => c.content.trim().isNotEmpty && !_commentTr.containsKey(c.id)).toList();
    if (pending.isEmpty) return;
    final res = await SupabaseService.instance.translateContentBatch(
      kind: 'comment',
      ids: pending.map((c) => c.id).toList(),
      targetLang: lang,
    );
    if (!mounted) return;
    final missing = pending.where((c) => res[c.id] == null).toList();
    setState(() {
      res.forEach((id, r) {
        if (r.ok) _commentTr[id] = r.text;
      });
    });
    for (final c in missing) {
      final t = await SupabaseService.instance.translateText(text: c.content, targetLang: lang);
      if (!mounted) return;
      setState(() => _commentTr[c.id] = t);
    }
  }

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _loadPostAndComments();
    if (widget.focusCommentInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPostAndComments() async {
    setState(() {
      if (_post == null) _postState = JuzzioDataLoadState.initialLoading;
      _commentsState = JuzzioDataLoadState.initialLoading;
    });
    try {
      final verifiedPost = await JuzzioSocialService.instance.fetchPostById(widget.postId);
      if (!mounted) return;
      if (verifiedPost == null) {
        setState(() {
          _post = null;
          _postState = JuzzioDataLoadState.empty;
          _commentsState = JuzzioDataLoadState.empty;
        });
        return;
      }
      setState(() {
        _post = verifiedPost;
        _postState = JuzzioDataLoadState.loaded;
      });

      final comments = await JuzzioSocialService.instance.fetchPostComments(
        postId: verifiedPost.id,
        newestFirst: _newestCommentsFirst,
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _commentsState = comments.isEmpty
            ? JuzzioDataLoadState.empty
            : JuzzioDataLoadState.loaded;
      });
      _translateComments(comments);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_post == null) {
          _postState = JuzzioDataLoadState.error;
        }
        _commentsState = JuzzioDataLoadState.error;
      });
    }
  }

  Future<void> _submitComment() async {
    final post = _post;
    if (post == null || _submittingComment || !post.commentsEnabled) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _submittingComment = true);
    try {
      final created = await JuzzioSocialService.instance.addComment(
        post: post,
        author: widget.currentUser,
        content: text,
        parentCommentId: _replyingTo?.id,
        replyToUsername: _replyingTo?.authorUsername ?? '',
      );
      if (!mounted) return;
      _commentCtrl.clear();
      setState(() {
        _replyingTo = null;
        _submittingComment = false;
        if (_newestCommentsFirst) {
          _comments.insert(0, created);
        } else {
          _comments.add(created);
        }
        _commentsState = JuzzioDataLoadState.loaded;
        _post = post.copyWith(commentsCount: post.commentsCount + 1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            JuzzioAppController.instance.loc(
              'Yorum gönderilemedi. Metniniz korundu, tekrar deneyebilirsiniz.',
              'Could not post comment. Your text is preserved, please retry.', 'Kommentar konnte nicht gesendet werden. Dein Text bleibt erhalten, bitte versuche es erneut.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteComment(JuzzioComment comment) async {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuzzioSocialTokens.cardBg(isDark),
        title: Text(
          app.loc('Yorumu Sil', 'Delete Comment', 'Kommentar löschen'),
          style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
        ),
        content: Text(
          app.loc('Bu yorumu silmek istediğinizden emin misiniz?', 'Are you sure you want to delete this comment?', 'Möchtest du diesen Kommentar wirklich löschen?'),
          style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.loc('İptal', 'Cancel', 'Abbrechen')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: JuzzioSocialTokens.dangerRed,
              foregroundColor: Colors.white,
            ),
            child: Text(app.loc('Yorumu Sil', 'Delete Comment', 'Kommentar löschen')),
          ),
        ],
      ),
    );
    if (confirmed == true && _post != null) {
      try {
        await JuzzioSocialService.instance.deleteComment(
          commentId: comment.id,
          postId: _post!.id,
        );
        if (!mounted) return;
        setState(() {
          _comments.removeWhere((c) => c.id == comment.id);
          if (_comments.isEmpty) _commentsState = JuzzioDataLoadState.empty;
          _post = _post!.copyWith(
            commentsCount: (_post!.commentsCount - 1).clamp(0, 1 << 30),
          );
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;

    return Scaffold(
      backgroundColor: JuzzioSocialTokens.pageBg(isDark),
      body: Column(
        children: [
          JuzzioDarkHeaderBar(
            title: app.loc('Gönderi & Yorumlar', 'Post & Comments', 'Beitrag & Kommentare'),
            subtitle: _post != null
                ? '${_post!.commentsCount} ${app.loc("yorum", "comments", "Kommentare")}'
                : null,
            onBack: () {
              if (_commentFocus.hasFocus) {
                _commentFocus.unfocus();
                return;
              }
              Navigator.pop(context, _post);
            },
            actions: [
              if (_post != null)
                PopupMenuButton<bool>(
                  icon: const Icon(Icons.sort_rounded, color: Colors.white),
                  tooltip: app.loc('Yorum Sıralaması', 'Sort Comments', 'Kommentare sortieren'),
                  onSelected: (newest) {
                    setState(() => _newestCommentsFirst = newest);
                    _loadPostAndComments();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: false,
                      child: Text(app.loc('En İlgili / Kronolojik', 'Oldest First', 'Älteste zuerst')),
                    ),
                    PopupMenuItem(
                      value: true,
                      child: Text(app.loc('En Yeni Yorumlar', 'Newest First', 'Neueste zuerst')),
                    ),
                  ],
                ),
            ],
          ),
          Expanded(
            child: _postState == JuzzioDataLoadState.initialLoading
                ? const JuzzioSkeletonListView(itemCount: 3, itemHeight: 160)
                : (_postState == JuzzioDataLoadState.error
                    ? JuzzioErrorRetryView(
                        message: app.loc('Gönderi yüklenemedi.', 'Could not load post.', 'Beitrag konnte nicht geladen werden.'),
                        onRetry: _loadPostAndComments,
                      )
                    : (_post == null
                        ? JuzzioEmptyStateView(
                            icon: Icons.visibility_off_outlined,
                            title: app.loc(
                              'Bu gönderi artık görüntülenemiyor',
                              'This post is no longer available', 'Dieser Beitrag ist nicht mehr verfügbar',
                            ),
                            subtitle: app.loc(
                              'Gönderi silinmiş olabilir veya gizlilik ayarları nedeniyle erişiminiz bulunmuyor.',
                              'The post may have been deleted or restricted by privacy settings.', 'Der Beitrag wurde möglicherweise gelöscht oder durch Datenschutzeinstellungen eingeschränkt.',
                            ),
                            actionLabel: app.loc('Geri Dön', 'Go Back', 'Zurück'),
                            onAction: () => Navigator.pop(context),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadPostAndComments,
                            child: ListView(
                              padding: const EdgeInsets.only(top: 8, bottom: 20),
                              children: [
                                JuzzioPostCardWidget(
                                  post: _post!,
                                  currentUser: widget.currentUser,
                                  onPostUpdated: (updated) => setState(() => _post = updated),
                                  onPostDeleted: (_) => Navigator.pop(context),
                                  onOpenProfile: (uid) {
                                    if (widget.onOpenProfile != null) {
                                      widget.onOpenProfile!(uid);
                                    }
                                  },
                                  onOpenPostDetail: (_) {},
                                  onOpenComments: (_) => _commentFocus.requestFocus(),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                                  child: Text(
                                    '${app.loc("Yorumlar", "Comments", "Kommentare")} (${_post!.commentsCount})',
                                    style: TextStyle(
                                      color: JuzzioSocialTokens.textPrimary(isDark),
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (_commentsState == JuzzioDataLoadState.initialLoading)
                                  const JuzzioSkeletonListView(itemCount: 3, itemHeight: 68)
                                else if (_commentsState == JuzzioDataLoadState.empty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 28),
                                    child: Center(
                                      child: Text(
                                        app.loc(
                                          'Henüz yorum yok. İlk yorumu sen yaz!',
                                          'No comments yet. Be the first to comment!', 'Noch keine Kommentare. Schreib den ersten!',
                                        ),
                                        style: TextStyle(
                                          color: JuzzioSocialTokens.textSecondary(isDark),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ..._comments.map((c) {
                                    final canDelete = c.authorId == widget.currentUser.id ||
                                        _post!.authorId == widget.currentUser.id;
                                    return Container(
                                      margin: EdgeInsets.only(
                                        left: c.parentCommentId != null ? 42 : 14,
                                        right: 14,
                                        top: 5,
                                        bottom: 5,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: JuzzioSocialTokens.cardBg(isDark),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: JuzzioSocialTokens.borderSubtle(isDark),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          JuzzioUserAvatar(
                                            imageUrl: c.authorAvatarUrl,
                                            displayName: c.authorDisplayName,
                                            radius: 17,
                                            onTap: widget.onOpenProfile != null
                                                ? () => widget.onOpenProfile!(c.authorId)
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      c.authorDisplayName,
                                                      style: TextStyle(
                                                        color: JuzzioSocialTokens.textPrimary(isDark),
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 13.5,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      JuzzioSocialTokens.formatRelativeTime(c.createdAt, app),
                                                      style: TextStyle(
                                                        color: JuzzioSocialTokens.textSecondary(isDark),
                                                        fontSize: 11.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Builder(builder: (_) {
                                                  final tr = _commentTr[c.id];
                                                  final translated = tr != null && tr.trim() != c.content.trim();
                                                  final showOrig = _commentOriginal.contains(c.id);
                                                  final String body = (translated && !showOrig ? tr : null) ?? c.content;
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        c.replyToUsername.isNotEmpty ? '@${c.replyToUsername} $body' : body,
                                                        style: TextStyle(
                                                          color: JuzzioSocialTokens.textPrimary(isDark),
                                                          fontSize: 13.5 * app.messageFontScale,
                                                        ),
                                                      ),
                                                      if (translated)
                                                        GestureDetector(
                                                          onTap: () => setState(() {
                                                            if (showOrig) {
                                                              _commentOriginal.remove(c.id);
                                                            } else {
                                                              _commentOriginal.add(c.id);
                                                            }
                                                          }),
                                                          child: Padding(
                                                            padding: const EdgeInsets.only(top: 3),
                                                            child: Text(
                                                              showOrig
                                                                  ? app.loc('Çeviriyi gör', 'Show translation', 'Übersetzung zeigen')
                                                                  : app.loc('Çevrildi · Orijinali gör', 'Translated · Show original',
                                                                      'Übersetzt · Original zeigen'),
                                                              style: TextStyle(
                                                                color: JuzzioSocialTokens.textSecondary(isDark),
                                                                fontSize: 11.5,
                                                                fontWeight: FontWeight.w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                }),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    InkWell(
                                                      onTap: () {
                                                        setState(() => _replyingTo = c);
                                                        _commentFocus.requestFocus();
                                                      },
                                                      child: Text(
                                                        app.loc('Yanıtla', 'Reply', 'Antworten'),
                                                        style: TextStyle(
                                                          color: JuzzioSocialTokens.textSecondary(isDark),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    if (canDelete)
                                                      InkWell(
                                                        onTap: () => _confirmDeleteComment(c),
                                                        child: Text(
                                                          app.loc('Sil', 'Delete', 'Löschen'),
                                                          style: const TextStyle(
                                                            color: JuzzioSocialTokens.dangerRed,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      InkWell(
                                                        onTap: () => showJuzzioReportModalSheet(
                                                          context: context,
                                                          targetType: 'comment',
                                                          targetId: c.id,
                                                          targetOwnerId: c.authorId,
                                                        ),
                                                        child: Text(
                                                          app.loc('Şikâyet Et', 'Report', 'Melden'),
                                                          style: TextStyle(
                                                            color: JuzzioSocialTokens.textSecondary(isDark),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            children: [
                                              IconButton(
                                                onPressed: () async {
                                                  try {
                                                    final updated = await JuzzioSocialService.instance
                                                        .toggleCommentLike(c);
                                                    if (mounted) {
                                                      setState(() {
                                                        final idx = _comments.indexWhere((x) => x.id == c.id);
                                                        if (idx >= 0) _comments[idx] = updated;
                                                      });
                                                    }
                                                  } catch (_) {}
                                                },
                                                icon: Icon(
                                                  c.isLikedByMe
                                                      ? Icons.favorite_rounded
                                                      : Icons.favorite_border_rounded,
                                                  size: 18,
                                                  color: c.isLikedByMe
                                                      ? JuzzioSocialTokens.dangerRed
                                                      : JuzzioSocialTokens.textSecondary(isDark),
                                                ),
                                              ),
                                              Text(
                                                '${c.likesCount}',
                                                style: TextStyle(
                                                  color: JuzzioSocialTokens.textSecondary(isDark),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ))),
          ),

          // Alt Yorum Yazma Çubuğu (Bölüm 21.2)
          if (_post != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: JuzzioSocialTokens.cardBg(isDark),
                border: Border(
                  top: BorderSide(color: JuzzioSocialTokens.borderSubtle(isDark)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: !_post!.commentsEnabled
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Text(
                            app.loc(
                              'Bu gönderi için yorumlar kapatılmıştır.',
                              'Comments are turned off for this post.', 'Kommentare sind für diesen Beitrag deaktiviert.',
                            ),
                            style: TextStyle(
                              color: JuzzioSocialTokens.textSecondary(isDark),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_replyingTo != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: JuzzioSocialTokens.subtleSurface(isDark),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '@${_replyingTo!.authorUsername} ${app.loc("kullanıcısına yanıt veriliyor", "replying", "antwortet")}',
                                      style: TextStyle(
                                        color: JuzzioSocialTokens.textSecondary(isDark),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setState(() => _replyingTo = null),
                                    child: const Icon(Icons.close_rounded, size: 16),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              JuzzioUserAvatar(
                                imageUrl: widget.currentUser.avatarUrl,
                                displayName: widget.currentUser.displayName,
                                radius: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _commentCtrl,
                                  focusNode: _commentFocus,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
                                  decoration: InputDecoration(
                                    hintText: app.loc('Yorum ekle...', 'Add a comment...', 'Kommentar hinzufügen...'),
                                    hintStyle: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    filled: true,
                                    fillColor: JuzzioSocialTokens.subtleSurface(isDark),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(22),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: (_submittingComment || _commentCtrl.text.trim().isEmpty)
                                    ? null
                                    : _submitComment,
                                style: IconButton.styleFrom(
                                  backgroundColor: JuzzioSocialTokens.royalBlue,
                                  foregroundColor: Colors.white,
                                ),
                                icon: _submittingComment
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Birleşik Arama ve Hashtag Keşif Ekranı (Bölüm 6.4 & 23.2)
class JuzzioUnifiedSearchPage extends StatefulWidget {
  final JuzzioUserProfile currentUser;
  final String initialQuery;
  final String initialTab; // 'all' | 'users' | 'posts' | 'tags'
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<JuzzioPost> onOpenPost;

  const JuzzioUnifiedSearchPage({
    super.key,
    required this.currentUser,
    this.initialQuery = '',
    this.initialTab = 'all',
    required this.onOpenProfile,
    required this.onOpenPost,
  });

  @override
  State<JuzzioUnifiedSearchPage> createState() => _JuzzioUnifiedSearchPageState();
}

class _JuzzioUnifiedSearchPageState extends State<JuzzioUnifiedSearchPage> {
  late final TextEditingController _searchCtrl;
  Timer? _debounce;
  String _selectedTab = 'all';
  bool _loading = false;
  String? _errorMsg;
  List<String> _recentSearches = <String>[];
  List<JuzzioUserProfile> _users = <JuzzioUserProfile>[];
  List<JuzzioPost> _posts = <JuzzioPost>[];
  List<Map<String, dynamic>> _hashtags = <Map<String, dynamic>>[];
  final Map<String, JuzzioFollowRelationState> _followStates = <String, JuzzioFollowRelationState>{};
  final Set<String> _followBusyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    _loadRecent();
    if (widget.initialQuery.trim().isNotEmpty) {
      _executeSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final rec = await JuzzioSocialService.instance.loadRecentSearches();
    if (mounted) setState(() => _recentSearches = rec);
  }

  void _onQueryChanged(String val) {
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _loading = false;
        _errorMsg = null;
        _users = const [];
        _posts = const [];
        _hashtags = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _executeSearch(val);
    });
  }

  Future<void> _executeSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final res = await JuzzioSocialService.instance.searchUnified(q);
      final updatedRecent = await JuzzioSocialService.instance.addRecentSearch(q);
      if (!mounted) return;
      setState(() {
        _users = (res['users'] as List<JuzzioUserProfile>);
        _posts = (res['posts'] as List<JuzzioPost>);
        _hashtags = (res['hashtags'] as List<Map<String, dynamic>>);
        _recentSearches = updatedRecent;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = JuzzioAppController.instance.loc(
          'Arama sonuçları alınamadı.',
          'Could not fetch search results.', 'Suchergebnisse konnten nicht geladen werden.',
        );
      });
    }
  }

  Future<void> _toggleFollowUser(JuzzioUserProfile target) async {
    if (_followBusyIds.contains(target.id)) return;
    setState(() => _followBusyIds.add(target.id));
    try {
      final current = _followStates[target.id] ?? JuzzioFollowRelationState.none;
      if (current == JuzzioFollowRelationState.following ||
          current == JuzzioFollowRelationState.pending) {
        final next = await JuzzioSocialService.instance.unfollowOrCancelRequest(
          targetUserId: target.id,
        );
        if (mounted) setState(() => _followStates[target.id] = next);
      } else {
        final next = await JuzzioSocialService.instance.followOrRequestUser(
          myProfile: widget.currentUser,
          targetUser: target,
        );
        if (mounted) setState(() => _followStates[target.id] = next);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _followBusyIds.remove(target.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final query = _searchCtrl.text.trim();

    return Scaffold(
      backgroundColor: JuzzioSocialTokens.pageBg(isDark),
      body: Column(
        children: [
          JuzzioDarkHeaderBar(
            title: app.loc('Arama', 'Search', 'Suchen'),
            onBack: () {
              if (FocusScope.of(context).hasFocus) {
                FocusScope.of(context).unfocus();
                return;
              }
              Navigator.pop(context);
            },
            bottomChild: TextField(
              controller: _searchCtrl,
              autofocus: widget.initialQuery.isEmpty,
              onChanged: _onQueryChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                hintText: app.loc(
                  'Kişi, kullanıcı adı, gönderi veya #etiket ara...',
                  'Search people, username, posts, or #tags...', 'Personen, Benutzernamen, Beiträge oder #Tags suchen...',
                ),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        tooltip: app.loc('Temizle', 'Clear', 'Löschen'),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withOpacity(0.12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          JuzzioFilterPillBar(
            items: [
              MapEntry('all', app.loc('Tümü', 'All', 'Alle')),
              MapEntry('users', app.loc('Kişiler', 'People', 'Kontakte')),
              MapEntry('posts', app.loc('Gönderiler', 'Posts', 'Beiträge')),
              MapEntry('tags', app.loc('Etiketler', 'Tags', 'Tags')),
            ],
            selectedKey: _selectedTab,
            onSelected: (k) => setState(() => _selectedTab = k),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: query.isEmpty
                ? _buildRecentSearchesSection(isDark, app)
                : (_loading
                    ? const JuzzioSkeletonListView(itemCount: 4, itemHeight: 74)
                    : (_errorMsg != null
                        ? JuzzioErrorRetryView(
                            message: _errorMsg!,
                            onRetry: () => _executeSearch(query),
                          )
                        : _buildResultsList(isDark, app))),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearchesSection(bool isDark, JuzzioAppController app) {
    if (_recentSearches.isEmpty) {
      return JuzzioEmptyStateView(
        icon: Icons.manage_search_rounded,
        title: app.loc('Aramaya Başlayın', 'Start Searching', 'Suche starten'),
        subtitle: app.loc(
          'Kullanıcı adı, görünen ad, gönderi açıklaması veya #etiket yazarak arama yapabilirsiniz.',
          'Search by username, display name, post caption, or #hashtag.', 'Suche nach Benutzername, Anzeigename, Beitragstext oder #Hashtag.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              app.loc('Son Aramalar', 'Recent Searches', 'Letzte Suchen'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextButton(
              onPressed: () async {
                await JuzzioSocialService.instance.clearRecentSearches();
                if (mounted) setState(() => _recentSearches = const []);
              },
              child: Text(app.loc('Tümünü Temizle', 'Clear All', 'Alle löschen')),
            ),
          ],
        ),
        ..._recentSearches.map(
          (item) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded, color: JuzzioSocialTokens.royalBlue),
            title: Text(
              item,
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: IconButton(
              onPressed: () async {
                final updated = await JuzzioSocialService.instance.removeRecentSearch(item);
                if (mounted) setState(() => _recentSearches = updated);
              },
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: JuzzioSocialTokens.textSecondary(isDark),
              ),
            ),
            onTap: () {
              _searchCtrl.text = item;
              _executeSearch(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList(bool isDark, JuzzioAppController app) {
    final showUsers = _selectedTab == 'all' || _selectedTab == 'users';
    final showPosts = _selectedTab == 'all' || _selectedTab == 'posts';
    final showTags = _selectedTab == 'all' || _selectedTab == 'tags';

    final hasAny = (showUsers && _users.isNotEmpty) ||
        (showPosts && _posts.isNotEmpty) ||
        (showTags && _hashtags.isNotEmpty);

    if (!hasAny) {
      return JuzzioEmptyStateView(
        icon: Icons.search_off_rounded,
        title: app.loc('Sonuç Bulunamadı', 'No Results Found', 'Keine Ergebnisse gefunden'),
        subtitle: app.loc(
          '"${_searchCtrl.text.trim()}" aramasıyla eşleşen kullanıcı, gönderi veya etiket bulunamadı.',
          'No users, posts, or tags matched "${_searchCtrl.text.trim()}".', 'Keine Nutzer, Beiträge oder Tags passen zu „${_searchCtrl.text.trim()}“.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (showUsers && _users.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              app.loc('Kişiler', 'People', 'Kontakte'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ..._users.map((u) {
            final rel = _followStates[u.id] ?? JuzzioFollowRelationState.none;
            final busy = _followBusyIds.contains(u.id);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: JuzzioSocialTokens.cardBg(isDark),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: JuzzioSocialTokens.borderSubtle(isDark)),
              ),
              child: ListTile(
                onTap: () => widget.onOpenProfile(u.id),
                leading: JuzzioUserAvatar(
                  imageUrl: u.avatarUrl,
                  displayName: u.displayName,
                  radius: 22,
                  isOnline: u.isEffectivelyOnline,
                  showOnlineDot: true,
                ),
                title: Text(
                  u.displayName,
                  style: TextStyle(
                    color: JuzzioSocialTokens.textPrimary(isDark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '@${u.username}',
                  style: TextStyle(
                    color: JuzzioSocialTokens.textSecondary(isDark),
                    fontSize: 12.5,
                  ),
                ),
                trailing: ElevatedButton(
                  onPressed: busy ? null : () => _toggleFollowUser(u),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: rel == JuzzioFollowRelationState.none
                        ? JuzzioSocialTokens.royalBlue
                        : JuzzioSocialTokens.subtleSurface(isDark),
                    foregroundColor: rel == JuzzioFollowRelationState.none
                        ? Colors.white
                        : JuzzioSocialTokens.textPrimary(isDark),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    rel == JuzzioFollowRelationState.following
                        ? app.loc('Takiptesin', 'Following', 'Gefolgt')
                        : (rel == JuzzioFollowRelationState.pending
                            ? app.loc('İstek Gönderildi', 'Requested', 'Angefragt')
                            : app.loc('Takip Et', 'Follow', 'Folgen')),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            );
          }),
        ],
        if (showTags && _hashtags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              app.loc('Etiketler', 'Hashtags', 'Hashtags'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ..._hashtags.map((tagMap) {
            final tag = tagMap['tag'].toString();
            final count = tagMap['count'] as int;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: JuzzioSocialTokens.royalBlue.withOpacity(0.14),
                child: const Text(
                  '#',
                  style: TextStyle(
                    color: JuzzioSocialTokens.royalBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                '#$tag',
                style: TextStyle(
                  color: JuzzioSocialTokens.textPrimary(isDark),
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '$count ${app.loc("gönderi", "posts", "Beiträge")}',
                style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
              ),
              onTap: () {
                _searchCtrl.text = '#$tag';
                setState(() => _selectedTab = 'posts');
                _executeSearch('#$tag');
              },
            );
          }),
        ],
        if (showPosts && _posts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              app.loc('Gönderiler', 'Posts', 'Beiträge'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ..._posts.map(
            (p) => ListTile(
              onTap: () => widget.onOpenPost(p),
              leading: JuzzioUserAvatar(
                imageUrl: p.coverUrl ?? p.primaryMediaUrl,
                displayName: p.authorDisplayName,
                radius: 22,
              ),
              title: Text(
                p.caption.isEmpty ? '@${p.authorUsername}' : p.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: JuzzioSocialTokens.textPrimary(isDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '@${p.authorUsername} • ${p.likesCount} ${app.loc("beğeni", "likes", "Likes")}',
                style: TextStyle(
                  color: JuzzioSocialTokens.textSecondary(isDark),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Kullanıcı Profili Ekranı (Kendi Profili veya Ziyaret Edilen Profil - Bölüm 6.13 & 24)
class JuzzioUserProfilePage extends StatefulWidget {
  final String userId;
  final JuzzioUserProfile currentUser;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenEditProfile;
  final ValueChanged<JuzzioUserProfile>? onStartDirectChat;
  final void Function(JuzzioUserProfile target, bool isVideo)? onStartCall;

  const JuzzioUserProfilePage({
    super.key,
    required this.userId,
    required this.currentUser,
    this.onOpenSettings,
    this.onOpenEditProfile,
    this.onStartDirectChat,
    this.onStartCall,
  });

  @override
  State<JuzzioUserProfilePage> createState() => _JuzzioUserProfilePageState();
}

class _JuzzioUserProfilePageState extends State<JuzzioUserProfilePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: JuzzioProfileView(
          userId: widget.userId,
          currentUser: widget.currentUser,
          onBack: () => Navigator.of(context).maybePop(),
          onOpenSettings: widget.onOpenSettings,
          onEditProfile: widget.onOpenEditProfile == null
              ? null
              : () async {
                  widget.onOpenEditProfile!();
                  return null;
                },
          onStartChat: widget.onStartDirectChat,
          onStartCall: widget.onStartCall,
        ),
      ),
    );
  }
}

class JuzzioFriendsAndRelationsPage extends StatefulWidget {
  final JuzzioUserProfile currentUser;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<JuzzioUserProfile> onStartChat;
  final void Function(JuzzioUserProfile target, bool isVideo) onStartCall;

  const JuzzioFriendsAndRelationsPage({
    super.key,
    required this.currentUser,
    required this.onOpenProfile,
    required this.onStartChat,
    required this.onStartCall,
  });

  @override
  State<JuzzioFriendsAndRelationsPage> createState() =>
      _JuzzioFriendsAndRelationsPageState();
}

class _JuzzioFriendsAndRelationsPageState
    extends State<JuzzioFriendsAndRelationsPage> {
  String _selectedTab = 'friends'; // 'friends' | 'requests' | 'followers' | 'following' | 'suggested' | 'online'
  String _searchQuery = '';
  bool _loading = true;
  List<JuzzioUserProfile> _allProfiles = <JuzzioUserProfile>[];
  List<JuzzioFriendship> _friendships = <JuzzioFriendship>[];
  List<JuzzioFollowRecord> _followers = <JuzzioFollowRecord>[];
  List<JuzzioFollowRecord> _following = <JuzzioFollowRecord>[];
  List<JuzzioFollowRecord> _pendingFollowRequests = <JuzzioFollowRecord>[];

  @override
  void initState() {
    super.initState();
    _loadAllRelations();
  }

  Future<void> _loadAllRelations() async {
    setState(() => _loading = true);
    try {
      await JuzzioSocialService.instance.refreshMyInteractionSets();
      final profiles = await SupabaseService.instance.fetchAllProfiles();
      final followers = await JuzzioSocialService.instance.fetchFollowers(widget.currentUser.id);
      final following = await JuzzioSocialService.instance.fetchFollowing(widget.currentUser.id);
      final followReqs = await JuzzioSocialService.instance.fetchPendingFollowRequests();
      List<JuzzioFriendship> fships = const [];
      try {
        final rows = await SupabaseService.instance.client
            .from('friendships')
            .select()
            .or('requester_id.eq.${widget.currentUser.id},receiver_id.eq.${widget.currentUser.id}')
            .order('created_at', ascending: false);
        fships = (rows as List)
            .map((e) => JuzzioFriendship.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _allProfiles = profiles
            .where((u) =>
                u.id != widget.currentUser.id &&
                !JuzzioSocialService.instance.blockedUserIds.contains(u.id))
            .toList();
        _friendships = fships;
        _followers = followers;
        _following = following;
        _pendingFollowRequests = followReqs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;

    return Scaffold(
      backgroundColor: JuzzioSocialTokens.pageBg(isDark),
      body: Column(
        children: [
          JuzzioDarkHeaderBar(
            title: app.loc('Arkadaşlar & İlişkiler', 'Friends & Relations', 'Freunde & Beziehungen'),
            onBack: Navigator.canPop(context) ? () => Navigator.pop(context) : null,
            bottomChild: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: app.loc('Kişi ara...', 'Search people...', 'Personen suchen...'),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          JuzzioFilterPillBar(
            items: [
              MapEntry('friends', app.loc('Arkadaşlarım', 'My Friends', 'Meine Freunde')),
              MapEntry('requests', app.loc('İstekler', 'Requests', 'Anfragen')),
              MapEntry('followers', app.loc('Takipçiler', 'Followers', 'Follower')),
              MapEntry('following', app.loc('Takip Edilenler', 'Following', 'Gefolgt')),
              MapEntry('suggested', app.loc('Önerilenler', 'Suggested', 'Vorgeschlagen')),
              if (app.canViewOthersLastSeenAndOnline)
                MapEntry('online', app.loc('Çevrimiçi', 'Online', 'Online')),
            ],
            selectedKey: _selectedTab,
            onSelected: (k) => setState(() => _selectedTab = k),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const JuzzioSkeletonListView(itemCount: 4, itemHeight: 74)
                : RefreshIndicator(
                    onRefresh: _loadAllRelations,
                    child: _buildTabContent(isDark, app),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(bool isDark, JuzzioAppController app) {
    final myUid = widget.currentUser.id;
    final acceptedFriendIds = _friendships
        .where((f) => f.status == 'accepted')
        .map((f) => f.requesterId == myUid ? f.receiverId : f.requesterId)
        .toSet();

    bool matchesSearch(String name, String username) {
      if (_searchQuery.trim().isEmpty) return true;
      return JuzzioTurkishNormalizer.matchesQuery(name, _searchQuery) ||
          JuzzioTurkishNormalizer.matchesQuery(username, _searchQuery);
    }

    if (_selectedTab == 'requests') {
      final incomingFriendReqs = _friendships
          .where((f) => f.status == 'pending' && f.receiverId == myUid)
          .toList();
      final outgoingFriendReqs = _friendships
          .where((f) => f.status == 'pending' && f.requesterId == myUid)
          .toList();

      if (incomingFriendReqs.isEmpty &&
          outgoingFriendReqs.isEmpty &&
          _pendingFollowRequests.isEmpty) {
        return JuzzioEmptyStateView(
          icon: Icons.person_add_disabled_rounded,
          title: app.loc('Bekleyen İstek Yok', 'No Pending Requests', 'Keine offenen Anfragen'),
          subtitle: app.loc(
            'Gelen veya gönderilen arkadaşlık ve takip istekleri burada görünür.',
            'Incoming and outgoing friend or follow requests appear here.', 'Ein- und ausgehende Freundschafts- oder Folgeanfragen erscheinen hier.',
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (incomingFriendReqs.isNotEmpty) ...[
            Text(
              app.loc('Gelen Arkadaşlık İstekleri', 'Incoming Friend Requests', 'Eingehende Freundschaftsanfragen'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...incomingFriendReqs.map(
              (req) => ListTile(
                leading: JuzzioUserAvatar(
                  imageUrl: req.requesterAvatar,
                  displayName: req.requesterName,
                  radius: 21,
                ),
                title: Text(req.requesterName),
                subtitle: Text('@${req.requesterUsername}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await SupabaseService.instance.respondToFriendRequest(
                            friendshipId: req.id,
                            accept: true,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
                          }
                        }
                        _loadAllRelations();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JuzzioSocialTokens.royalBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(app.loc('Kabul Et', 'Accept', 'Annehmen')),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await SupabaseService.instance.respondToFriendRequest(
                            friendshipId: req.id,
                            accept: false,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
                          }
                        }
                        _loadAllRelations();
                      },
                      child: Text(app.loc('Reddet', 'Decline', 'Ablehnen')),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_pendingFollowRequests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              app.loc('Gelen Takip İstekleri', 'Incoming Follow Requests', 'Eingehende Folgeanfragen'),
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ..._pendingFollowRequests.map(
              (fReq) => ListTile(
                leading: JuzzioUserAvatar(
                  imageUrl: fReq.followerAvatarUrl,
                  displayName: fReq.followerDisplayName,
                  radius: 21,
                ),
                title: Text(fReq.followerDisplayName),
                subtitle: Text('@${fReq.followerUsername}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await JuzzioSocialService.instance.respondToFollowRequest(
                          request: fReq,
                          myProfile: widget.currentUser,
                          accept: true,
                        );
                        _loadAllRelations();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JuzzioSocialTokens.royalBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(app.loc('Onayla', 'Approve', 'Bestätigen')),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () async {
                        await JuzzioSocialService.instance.respondToFollowRequest(
                          request: fReq,
                          myProfile: widget.currentUser,
                          accept: false,
                        );
                        _loadAllRelations();
                      },
                      child: Text(app.loc('Sil', 'Delete', 'Löschen')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    if (_selectedTab == 'followers' || _selectedTab == 'following') {
      final list = _selectedTab == 'followers' ? _followers : _following;
      final filtered = list.where((r) {
        final name = _selectedTab == 'followers' ? r.followerDisplayName : r.followingDisplayName;
        final uname = _selectedTab == 'followers' ? r.followerUsername : r.followingUsername;
        return matchesSearch(name, uname);
      }).toList();

      if (filtered.isEmpty) {
        return JuzzioEmptyStateView(
          icon: Icons.people_outline_rounded,
          title: _selectedTab == 'followers'
              ? app.loc('Henüz Takipçi Yok', 'No Followers Yet', 'Noch keine Follower')
              : app.loc('Henüz Kimseyi Takip Etmiyorsunuz', 'Not Following Anyone Yet', 'Du folgst noch niemandem'),
          subtitle: app.loc(
            'Önerilenler sekmesinden yeni kişileri keşfedebilirsiniz.',
            'Discover people from the Suggested tab.', 'Entdecke Personen im Tab „Vorgeschlagen“.',
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: filtered.length,
        itemBuilder: (_, idx) {
          final r = filtered[idx];
          final uid = _selectedTab == 'followers' ? r.followerId : r.followingId;
          final dname = _selectedTab == 'followers' ? r.followerDisplayName : r.followingDisplayName;
          final uname = _selectedTab == 'followers' ? r.followerUsername : r.followingUsername;
          final av = _selectedTab == 'followers' ? r.followerAvatarUrl : r.followingAvatarUrl;
          return ListTile(
            onTap: () => widget.onOpenProfile(uid),
            leading: JuzzioUserAvatar(imageUrl: av, displayName: dname, radius: 22),
            title: Text(dname, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@$uname'),
          );
        },
      );
    }

    // 'friends' | 'online' | 'suggested'
    final candidates = _allProfiles.where((u) {
      if (!matchesSearch(u.displayName, u.username)) return false;
      if (_selectedTab == 'friends') {
        return acceptedFriendIds.contains(u.id);
      }
      if (_selectedTab == 'online') {
        // Yalnızca çevrimiçi ARKADAŞLAR (eskiden tüm çevrimiçi kullanıcılar listeleniyordu)
        return acceptedFriendIds.contains(u.id) && u.isEffectivelyOnline;
      }
      // suggested: arkadaş olmayan ve bekleyen isteği bulunmayan kişiler
      final hasPending = _friendships.any((f) =>
          f.status == 'pending' && (f.requesterId == u.id || f.receiverId == u.id));
      return !acceptedFriendIds.contains(u.id) &&
          !hasPending &&
          !JuzzioSocialService.instance.isRecommendationHidden(u.id);
    }).toList();

    if (candidates.isEmpty) {
      return JuzzioEmptyStateView(
        icon: Icons.group_outlined,
        title: app.loc('Liste Boş', 'List is Empty', 'Liste ist leer'),
        subtitle: app.loc(
          'Bu filtreye uygun kullanıcı bulunamadı.',
          'No users matched this filter.', 'Keine Nutzer passen zu diesem Filter.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: candidates.length,
      itemBuilder: (_, idx) {
        final u = candidates[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: JuzzioSocialTokens.cardBg(isDark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JuzzioSocialTokens.borderSubtle(isDark)),
          ),
          child: ListTile(
            onTap: () => widget.onOpenProfile(u.id),
            leading: JuzzioUserAvatar(
              imageUrl: u.avatarUrl,
              displayName: u.displayName,
              radius: 22,
              isOnline: u.isEffectivelyOnline,
              showOnlineDot: true,
            ),
            title: Text(
              u.displayName,
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              u.formattedPresence(),
              style: TextStyle(
                color: JuzzioSocialTokens.textSecondary(isDark),
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => widget.onStartChat(u),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: JuzzioSocialTokens.royalBlue),
                  tooltip: app.loc('Mesaj Gönder', 'Send Message', 'Nachricht senden'),
                ),
                if (_selectedTab == 'suggested')
                  IconButton(
                    onPressed: () async {
                      try {
                        final status = await SupabaseService.instance.sendFriendRequest(
                          myProfile: widget.currentUser,
                          targetUser: u,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(status == 'accepted'
                                ? app.loc('Artık arkadaşsınız!', 'You are now friends!', 'Ihr seid jetzt Freunde!')
                                : app.loc('Arkadaşlık isteği gönderildi.', 'Friend request sent.', 'Freundschaftsanfrage gesendet.')),
                          ),
                        );
                        _loadAllRelations();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SupabaseService.instance.friendlyError(e))));
                      }
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: JuzzioSocialTokens.onlineEmerald),
                    tooltip: app.loc('Arkadaş Ekle', 'Add Friend', 'Freund hinzufügen'),
                  )
                else
                  IconButton(
                    onPressed: () => widget.onStartCall(u, false),
                    icon: const Icon(Icons.call_outlined, color: JuzzioSocialTokens.onlineEmerald),
                    tooltip: app.loc('Sesli Ara', 'Voice Call', 'Sprachanruf'),
                  ),
                if (_selectedTab == 'suggested')
                  IconButton(
                    onPressed: () {
                      setState(() {
                        JuzzioSocialService.instance.hideRecommendationForSession(u.id);
                      });
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: JuzzioSocialTokens.textSecondary(isDark),
                    ),
                    tooltip: app.loc('Öneriyi Gizle', 'Hide Suggestion', 'Vorschlag ausblenden'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
