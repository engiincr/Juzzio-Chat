// =============================================================================
// JUZZIO v0.1.0 — Ortak Sosyal Medya Tasarım Sistemi Bileşenleri (Bölüm 4, 15, 16, 20)
// Koyu Orman Yeşili Başlık (#07120C), Avatar + Hikâye Halkası, Skeleton/Boş/Hata
// Kartları, Filtre Hapları, Etkileşimli Gönderi Kartı, Paylaşım ve Şikâyet Sheet'leri
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_theme_and_locale.dart';
import '../models/social_models.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../core/theme/juzzio_colors.dart';
import 'juzzio_video_kit.dart';

class JuzzioSocialTokens {
  JuzzioSocialTokens._();

  static const Color darkForestHeader = JuzzioColors.deepForest;
  static const Color darkForestHeaderDeep = JuzzioColors.surface060D09;
  static const Color royalBlue = JuzzioColors.blue600;
  static const Color activeIndigo = JuzzioColors.brandIndigo;
  static const Color onlineEmerald = JuzzioColors.emerald500;
  static const Color dangerRed = JuzzioColors.red500;

  // v0.6 Glassmorphism: sayfa zemini saydam (aurora görünür), kartlar buzlu cam
  static Color pageBg(bool isDark) => Colors.transparent;
  static Color cardBg(bool isDark) =>
      isDark ? const Color(0xD914151A) : const Color(0xEBFFFFFF);
  static Color subtleSurface(bool isDark) =>
      isDark ? const Color(0x1FFFFFFF) : const Color(0x99FFFFFF);
  static Color textPrimary(bool isDark) =>
      isDark ? JuzzioColors.slate50 : JuzzioColors.surface141519;
  static Color textSecondary(bool isDark) =>
      isDark ? JuzzioColors.slate400 : JuzzioColors.surface686D78;
  static Color borderSubtle(bool isDark) =>
      isDark ? JuzzioColors.slate800 : JuzzioColors.surfaceE7E9F0;

  static String formatRelativeTime(DateTime dt, JuzzioAppController app) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 45) return app.loc('Az önce', 'Just now', 'Gerade eben');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${app.loc("dk", "m", "Min.")}';
    if (diff.inHours < 24) return '${diff.inHours} ${app.loc("sa", "h", "Std.")}';
    if (diff.inDays < 7) return '${diff.inDays} ${app.loc("gün", "d", "T.")}';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}';
  }

  static String formatAbsoluteTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year} '
        '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
  }
}

/// Ortak `#07120C` Koyu Orman Yeşili Başlık Çubuğu (Bölüm 4.1, 4.3, 16.2)
class JuzzioDarkHeaderBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottomChild;

  const JuzzioDarkHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.bottomChild,
  });

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioAppController.instance.isDark;
    return Container(
      // v0.6 Glassmorphism: buzlu cam başlık (gündüz modunda beyaz yazı için koyu cam)
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0x29FFFFFF), Color(0x0FFFFFFF)]
              : const [Color(0xD91C1D24), Color(0xBF111216)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(bottom: BorderSide(color: Color(0x2EFFFFFF))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    Semantics(
                      button: true,
                      label: JuzzioAppController.instance.trEn('Geri', 'Back', 'Zurück'),
                      child: IconButton(
                        onPressed: onBack,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        tooltip: JuzzioAppController.instance.trEn('Geri', 'Back', 'Zurück'),
                      ),
                    )
                  else
                    const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.74),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
              if (bottomChild != null) ...[
                const SizedBox(height: 10),
                bottomChild!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Yükleniyor/Hata/Baş Harf Fallback'li Ortak Avatar ve Hikâye Halkası (Bölüm 4.3, 18.1)
class JuzzioUserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String displayName;
  final double radius;
  final bool isOnline;
  final bool showOnlineDot;
  final bool hasActiveStory;
  final bool isStorySeen;
  final VoidCallback? onTap;

  const JuzzioUserAvatar({
    super.key,
    required this.imageUrl,
    required this.displayName,
    this.radius = 24,
    this.isOnline = false,
    this.showOnlineDot = false,
    this.hasActiveStory = false,
    this.isStorySeen = false,
    this.onTap,
  });

  String get _initials {
    final clean = displayName.trim().replaceAll('@', '');
    if (clean.isEmpty) return 'J';
    final parts = clean.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return clean[0].toUpperCase();
  }

  Widget _buildInnerAvatar(bool isDark) {
    final url = imageUrl?.trim() ?? '';
    final isLocalFile = url.isNotEmpty && !url.startsWith('http') && File(url).existsSync();

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? JuzzioColors.slate800 : JuzzioColors.slate200,
      ),
      clipBehavior: Clip.antiAlias,
      child: isLocalFile
          ? Image.file(
              File(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackText(isDark),
            )
          : (url.startsWith('http')
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: radius * 0.7,
                        height: radius * 0.7,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: JuzzioSocialTokens.royalBlue,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => _buildFallbackText(isDark),
                )
              : _buildFallbackText(isDark)),
    );
  }

  Widget _buildFallbackText(bool isDark) {
    return Center(
      child: Text(
        _initials,
        style: TextStyle(
          color: isDark ? Colors.white : JuzzioColors.slate800,
          fontSize: (radius * 0.72).clamp(11, 28),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    final canShowOnline = showOnlineDot &&
        isOnline &&
        JuzzioAppController.instance.canViewOthersLastSeenAndOnline;

    Widget avatar = _buildInnerAvatar(isDark);

    if (hasActiveStory) {
      avatar = Container(
        padding: const EdgeInsets.all(2.4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isStorySeen
              ? LinearGradient(
                  colors: [
                    Colors.grey.shade400,
                    Colors.grey.shade500,
                  ],
                )
              : const LinearGradient(
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFF9A9AA0),
                    Color(0xFFE5E5EA),
                    Color(0xFF7C7C82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JuzzioSocialTokens.cardBg(isDark),
          ),
          child: avatar,
        ),
      );
    }

    Widget stacked = Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (canShowOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: (radius * 0.48).clamp(10.0, 15.0),
              height: (radius * 0.48).clamp(10.0, 15.0),
              decoration: BoxDecoration(
                color: JuzzioSocialTokens.onlineEmerald,
                shape: BoxShape.circle,
                border: Border.all(
                  color: JuzzioSocialTokens.cardBg(isDark),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );

    if (onTap == null) return stacked;
    return Semantics(
      button: true,
      label: JuzzioAppController.instance.trEn("$displayName profili", "$displayName's profile", "Profil von $displayName"),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: stacked,
      ),
    );
  }
}

/// Yatay Filtre Hapları Çubuğu (Bölüm 4.3, 23.1)
class JuzzioFilterPillBar extends StatelessWidget {
  final List<MapEntry<String, String>> items;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  const JuzzioFilterPillBar({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final entry = items[idx];
          final active = entry.key == selectedKey;
          return Semantics(
            button: true,
            selected: active,
            label: entry.value,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                if (!active) onSelected(entry.key);
              },
              child: AnimatedContainer(
                duration: JuzzioAppController.instance.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? JuzzioSocialTokens.royalBlue
                      : JuzzioSocialTokens.cardBg(isDark),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? JuzzioSocialTokens.royalBlue
                        : JuzzioSocialTokens.borderSubtle(isDark),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : JuzzioSocialTokens.textPrimary(isDark),
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ortak Boş Durum Görünümü (Bölüm 15.2)
class JuzzioEmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const JuzzioEmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: JuzzioSocialTokens.royalBlue.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 34,
                color: JuzzioSocialTokens.royalBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JuzzioSocialTokens.textPrimary(isDark),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JuzzioSocialTokens.textSecondary(isDark),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: JuzzioSocialTokens.royalBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(180, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ortak Hata ve Tekrar Dene Görünümü (Bölüm 15.2)
class JuzzioErrorRetryView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const JuzzioErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: JuzzioSocialTokens.cardBg(isDark),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: JuzzioSocialTokens.borderSubtle(isDark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: JuzzioSocialTokens.dangerRed,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: JuzzioSocialTokens.textPrimary(isDark),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: JuzzioSocialTokens.royalBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(150, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(app.loc('Tekrar Dene', 'Retry', 'Erneut versuchen')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ortak Yükleme Skeleton Listesi (Bölüm 15.2)
class JuzzioSkeletonListView extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const JuzzioSkeletonListView({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 96,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = JuzzioAppController.instance.isDark;
    final baseColor = isDark ? JuzzioColors.surface1A2433 : JuzzioColors.surfaceE8ECF4;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: itemHeight,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

/// Gönderi / Kullanıcı / Yorum Şikâyet Etme Bottom Sheet (Bölüm 20.4)
Future<bool?> showJuzzioReportModalSheet({
  required BuildContext context,
  required String targetType,
  required String targetId,
  String? targetOwnerId,
}) async {
  final app = JuzzioAppController.instance;
  final isDark = app.isDark;
  String selectedReason = 'spam';
  final detailsCtrl = TextEditingController();
  bool submitting = false;
  String? errorText;

  final reasons = <MapEntry<String, String>>[
    MapEntry('spam', app.loc('Spam veya yanıltıcı içerik', 'Spam or misleading', 'Spam oder irreführend')),
    MapEntry('harassment', app.loc('Taciz veya nefret söylemi', 'Harassment or hate speech', 'Belästigung oder Hassrede')),
    MapEntry('inappropriate', app.loc('Uygunsuz içerik', 'Inappropriate content', 'Unangemessene Inhalte')),
    MapEntry('fake_account', app.loc('Sahte hesap veya taklit', 'Fake account or impersonation', 'Fake-Konto oder Identitätsmissbrauch')),
    MapEntry('other', app.loc('Diğer', 'Other', 'Sonstiges')),
  ];

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioSocialTokens.cardBg(isDark),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x59FFFFFF) : const Color(0x40000000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  app.loc('Şikâyet Et', 'Report Content', 'Inhalt melden'),
                  style: TextStyle(
                    color: JuzzioSocialTokens.textPrimary(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  app.loc(
                    'Lütfen şikâyet nedeninizi seçin. Bildiriminiz karşı tarafa açıklanmaz.',
                    'Please select a reason. Your report remains anonymous.', 'Bitte wähle einen Grund. Deine Meldung bleibt anonym.',
                  ),
                  style: TextStyle(
                    color: JuzzioSocialTokens.textSecondary(isDark),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ...reasons.map(
                  (r) => RadioListTile<String>(
                    value: r.key,
                    groupValue: selectedReason,
                    activeColor: JuzzioSocialTokens.royalBlue,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      r.value,
                      style: TextStyle(
                        color: JuzzioSocialTokens.textPrimary(isDark),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: submitting
                        ? null
                        : (val) {
                            if (val != null) {
                              setModalState(() => selectedReason = val);
                            }
                          },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsCtrl,
                  enabled: !submitting,
                  maxLines: 2,
                  maxLength: 300,
                  style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
                  decoration: InputDecoration(
                    hintText: app.loc('Ek açıklama (isteğe bağlı)...', 'Additional details (optional)...', 'Weitere Details (optional)...'),
                    hintStyle: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
                    filled: true,
                    fillColor: JuzzioSocialTokens.subtleSurface(isDark),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorText!,
                    style: const TextStyle(color: JuzzioSocialTokens.dangerRed, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(app.loc('Vazgeç', 'Cancel', 'Abbrechen')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                setModalState(() {
                                  submitting = true;
                                  errorText = null;
                                });
                                try {
                                  await JuzzioSocialService.instance.submitReport(
                                    targetType: targetType,
                                    targetId: targetId,
                                    targetOwnerId: targetOwnerId,
                                    reasonCode: selectedReason,
                                    details: detailsCtrl.text,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } catch (e) {
                                  setModalState(() {
                                    submitting = false;
                                    errorText = app.loc(
                                      'Şikâyet gönderilemedi. Lütfen tekrar deneyin.',
                                      'Could not submit report. Please retry.', 'Meldung konnte nicht gesendet werden. Bitte versuche es erneut.',
                                    );
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JuzzioSocialTokens.dangerRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(app.loc('Şikâyeti Gönder', 'Submit Report', 'Meldung senden')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Gönderi Paylaşım Bottom Sheet (Sohbete Gönder & Bağlantıyı Kopyala - Bölüm 20.2)
Future<void> showJuzzioSharePostModalSheet({
  required BuildContext context,
  required JuzzioPost post,
  required JuzzioUserProfile currentUser,
}) async {
  final app = JuzzioAppController.instance;
  final isDark = app.isDark;
  // Yalnızca arkadaşlar ve mevcut sohbet ortakları (eskiden tüm kayıtlı kullanıcılar listeleniyordu)
  final recipientIds = <String>{};
  try {
    final rows = await SupabaseService.instance.client.from('friendships').select().eq('status', 'accepted');
    for (final r in (rows as List)) {
      final f = JuzzioFriendship.fromMap(r as Map<String, dynamic>);
      recipientIds.add(f.otherUserId(currentUser.id));
    }
  } catch (_) {}
  try {
    final convs = await SupabaseService.instance.fetchMyConversations();
    for (final c in convs) {
      if (!c.isGroup && c.partnerId != null) recipientIds.add(c.partnerId!);
    }
  } catch (_) {}
  final allUsers = await SupabaseService.instance.fetchProfilesByIds(recipientIds);
  final recipients = allUsers
      .where((u) => u.id != currentUser.id && !JuzzioSocialService.instance.blockedUserIds.contains(u.id))
      .toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  final selectedIds = <String>{};
  bool sending = false;
  String? errorMsg;

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuzzioSocialTokens.cardBg(isDark),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x59FFFFFF) : const Color(0x40000000),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    app.loc('Gönderiyi Paylaş', 'Share Post', 'Beitrag teilen'),
                    style: TextStyle(
                      color: JuzzioSocialTokens.textPrimary(isDark),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: JuzzioSocialTokens.royalBlue.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link_rounded, color: JuzzioSocialTokens.royalBlue),
                    ),
                    title: Text(
                      app.loc('Bağlantıyı Kopyala', 'Copy Link', 'Link kopieren'),
                      style: TextStyle(
                        color: JuzzioSocialTokens.textPrimary(isDark),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'juzzio://post/${post.id}',
                      style: TextStyle(
                        color: JuzzioSocialTokens.textSecondary(isDark),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: 'juzzio://post/${post.id}'));
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(app.loc('Gönderi bağlantısı kopyalandı.', 'Post link copied.', 'Beitragslink kopiert.')),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(),
                  Text(
                    app.loc('Sohbete Gönder', 'Send to Chat', 'An Chat senden'),
                    style: TextStyle(
                      color: JuzzioSocialTokens.textSecondary(isDark),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (recipients.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        app.loc('Gönderilecek kişi bulunamadı.', 'No contacts available.', 'Keine Kontakte verfügbar.'),
                        style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: recipients.length,
                        itemBuilder: (_, i) {
                          final u = recipients[i];
                          final checked = selectedIds.contains(u.id);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: JuzzioSocialTokens.royalBlue,
                            contentPadding: EdgeInsets.zero,
                            secondary: JuzzioUserAvatar(
                              imageUrl: u.avatarUrl,
                              displayName: u.displayName,
                              radius: 20,
                            ),
                            title: Text(
                              u.displayName,
                              style: TextStyle(
                                color: JuzzioSocialTokens.textPrimary(isDark),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '@${u.username}',
                              style: TextStyle(
                                color: JuzzioSocialTokens.textSecondary(isDark),
                                fontSize: 12,
                              ),
                            ),
                            onChanged: sending
                                ? null
                                : (val) {
                                    setModalState(() {
                                      if (val == true) {
                                        selectedIds.add(u.id);
                                      } else {
                                        selectedIds.remove(u.id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: JuzzioSocialTokens.dangerRed, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: sending ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(app.loc('Vazgeç', 'Cancel', 'Abbrechen')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (sending || selectedIds.isEmpty)
                              ? null
                              : () async {
                                  setModalState(() {
                                    sending = true;
                                    errorMsg = null;
                                  });
                                  try {
                                    for (final targetUid in selectedIds) {
                                      final targetUser = recipients.firstWhere((r) => r.id == targetUid);
                                      final roomId = await SupabaseService.instance.ensureDirectRoomWithFriend(
                                        friendId: targetUser.id,
                                        friendName: targetUser.displayName,
                                      );
                                      final shareText = '📌 @${post.authorUsername}: ${post.caption.isEmpty ? "Gönderi" : post.caption} (juzzio://post/${post.id})';
                                      await SupabaseService.instance.sendTextMessage(
                                        text: shareText,
                                        senderName: currentUser.displayName,
                                        targetRoomId: roomId,
                                        receiverId: targetUser.id,
                                      );
                                    }
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            app.loc('Gönderi seçilen sohbetlere iletildi.', 'Post shared to selected chats.', 'Beitrag an die ausgewählten Chats gesendet.'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    setModalState(() {
                                      sending = false;
                                      errorMsg = app.loc(
                                        'Paylaşım başarısız oldu. Seçiminiz korundu, tekrar deneyebilirsiniz.',
                                        'Share failed. Your selection is preserved, please retry.', 'Teilen fehlgeschlagen. Deine Auswahl bleibt erhalten, bitte versuche es erneut.',
                                      );
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JuzzioSocialTokens.royalBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text('${app.loc("Gönder", "Send", "Senden")} (${selectedIds.length})'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Etkileşimli Sosyal Gönderi Kartı (Bölüm 6.1, 20.1, 20.2, 20.3, 20.4)
class JuzzioPostCardWidget extends StatefulWidget {
  final JuzzioPost post;
  final JuzzioUserProfile currentUser;
  final ValueChanged<JuzzioPost> onPostUpdated;
  final ValueChanged<String> onPostDeleted;
  final ValueChanged<String> onOpenProfile;
  final ValueChanged<JuzzioPost> onOpenPostDetail;
  final ValueChanged<JuzzioPost> onOpenComments;
  final ValueChanged<String>? onTapHashtag;

  const JuzzioPostCardWidget({
    super.key,
    required this.post,
    required this.currentUser,
    required this.onPostUpdated,
    required this.onPostDeleted,
    required this.onOpenProfile,
    required this.onOpenPostDetail,
    required this.onOpenComments,
    this.onTapHashtag,
  });

  @override
  State<JuzzioPostCardWidget> createState() => _JuzzioPostCardWidgetState();
}

class _JuzzioPostCardWidgetState extends State<JuzzioPostCardWidget> {
  // v0.5: açıklama okuyucunun diline otomatik çevrilir (sunucu önbellekli)
  String? _captionTr;
  String _captionTrFor = '';
  bool _captionOriginal = false;

  void _ensureCaptionTranslation(JuzzioPost post) {
    final key = '${post.id}|${post.caption}';
    if (post.caption.trim().isEmpty || _captionTrFor == key) return;
    _captionTrFor = key;
    _captionTr = null;
    final lang = JuzzioAppController.instance.uiLang;
    SupabaseService.instance
        .translateContentBatch(kind: 'post', ids: [post.id], targetLang: lang)
        .then((res) async {
      final r = res[post.id];
      // v0.7.0: sunucu çevirisi başarısızsa cihazdan çeviri denenir; "çevrilemedi" hatası
      // gösterilmez, orijinal metin olduğu gibi kalır.
      String? text = (r != null && r.ok) ? r.text : null;
      text ??= await SupabaseService.instance.translateText(text: post.caption, targetLang: lang);
      if (text.trim().isEmpty || text.trim() == post.caption.trim()) text = null;
      if (mounted && _captionTrFor == key) setState(() => _captionTr = text);
    }).catchError((_) {});
  }

  bool _likeBusy = false;
  bool _saveBusy = false;
  bool _showDoubleTapHeart = false;
  int _carouselIndex = 0;

  Future<void> _handleLikeToggle({bool forceLikeOnly = false}) async {
    if (_likeBusy) return;
    if (forceLikeOnly && widget.post.isLikedByMe) {
      _triggerHeartOverlay();
      return;
    }
    setState(() => _likeBusy = true);
    if (forceLikeOnly) _triggerHeartOverlay();

    final prev = widget.post;
    final optimisticLiked = forceLikeOnly ? true : !prev.isLikedByMe;
    final optimisticCount = optimisticLiked
        ? prev.likesCount + 1
        : (prev.likesCount - 1).clamp(0, 1 << 30);
    widget.onPostUpdated(prev.copyWith(
      isLikedByMe: optimisticLiked,
      likesCount: optimisticCount,
    ));

    try {
      final updated = await JuzzioSocialService.instance.togglePostLike(
        post: prev,
        currentUser: widget.currentUser,
        forceLikeOnly: forceLikeOnly,
      );
      if (mounted) widget.onPostUpdated(updated);
    } catch (_) {
      if (mounted) {
        widget.onPostUpdated(prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              JuzzioAppController.instance.loc(
                'Beğeni işlemi tamamlanamadı.',
                'Could not update like status.', 'Like-Status konnte nicht aktualisiert werden.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  void _triggerHeartOverlay() {
    if (JuzzioAppController.instance.reduceMotion) return;
    setState(() => _showDoubleTapHeart = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showDoubleTapHeart = false);
    });
  }

  Future<void> _handleSaveToggle() async {
    if (_saveBusy) return;
    setState(() => _saveBusy = true);
    final prev = widget.post;
    final optimisticSaved = !prev.isSavedByMe;
    widget.onPostUpdated(prev.copyWith(isSavedByMe: optimisticSaved));
    try {
      final updated = await JuzzioSocialService.instance.toggleSavePost(prev);
      if (mounted) widget.onPostUpdated(updated);
    } catch (_) {
      if (mounted) {
        widget.onPostUpdated(prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              JuzzioAppController.instance.loc(
                'Kaydetme işlemi başarısız oldu.',
                'Could not save post.', 'Beitrag konnte nicht gespeichert werden.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  Future<void> _openContextMenu() async {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final isMine = widget.post.authorId == widget.currentUser.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuzzioSocialTokens.cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x59FFFFFF) : const Color(0x40000000),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.link_rounded, color: JuzzioSocialTokens.royalBlue),
                title: Text(app.loc('Bağlantıyı Kopyala', 'Copy Link', 'Link kopieren')),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: 'juzzio://post/${widget.post.id}'));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(app.loc('Bağlantı kopyalandı.', 'Link copied.', 'Link kopiert.'))),
                    );
                  }
                },
              ),
              if (isMine) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: JuzzioSocialTokens.royalBlue),
                  title: Text(app.loc('Gönderiyi Düzenle', 'Edit Post', 'Beitrag bearbeiten')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditPostDialog();
                  },
                ),
                ListTile(
                  leading: Icon(
                    widget.post.commentsEnabled
                        ? Icons.comments_disabled_outlined
                        : Icons.comment_outlined,
                    color: JuzzioSocialTokens.textPrimary(isDark),
                  ),
                  title: Text(
                    widget.post.commentsEnabled
                        ? app.loc('Yorumları Kapat', 'Turn Off Comments', 'Kommentare deaktivieren')
                        : app.loc('Yorumları Aç', 'Turn On Comments', 'Kommentare aktivieren'),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final updated = await JuzzioSocialService.instance.updatePost(
                        postId: widget.post.id,
                        caption: widget.post.caption,
                        locationName: widget.post.locationName,
                        visibility: widget.post.visibility,
                        commentsEnabled: !widget.post.commentsEnabled,
                      );
                      if (mounted) widget.onPostUpdated(updated);
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: JuzzioSocialTokens.dangerRed),
                  title: Text(
                    app.loc('Gönderiyi Sil', 'Delete Post', 'Beitrag löschen'),
                    style: const TextStyle(
                      color: JuzzioSocialTokens.dangerRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeletePost();
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.share_outlined, color: JuzzioSocialTokens.royalBlue),
                  title: Text(app.loc('Gönderiyi Paylaş', 'Share Post', 'Beitrag teilen')),
                  onTap: () {
                    Navigator.pop(ctx);
                    showJuzzioSharePostModalSheet(
                      context: context,
                      post: widget.post,
                      currentUser: widget.currentUser,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.volume_off_outlined,
                    color: JuzzioSocialTokens.textPrimary(isDark),
                  ),
                  title: Text(app.loc('Kullanıcıyı Sessize Al', 'Mute User', 'Nutzer stummschalten')),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await JuzzioSocialService.instance.toggleMuteUser(
                        widget.post.authorId,
                        mute: true,
                      );
                      if (mounted) {
                        widget.onPostDeleted(widget.post.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              app.loc(
                                '@${widget.post.authorUsername} sessize alındı.',
                                '@${widget.post.authorUsername} muted.', '@${widget.post.authorUsername} stummgeschaltet.',
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: JuzzioSocialTokens.textPrimary(isDark),
                  ),
                  title: Text(app.loc('Takibi Bırak', 'Unfollow', 'Nicht mehr folgen')),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await JuzzioSocialService.instance.unfollowOrCancelRequest(
                        targetUserId: widget.post.authorId,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              app.loc(
                                '@${widget.post.authorUsername} takipten çıkarıldı.',
                                'Unfollowed @${widget.post.authorUsername}.', 'Du folgst @${widget.post.authorUsername} nicht mehr.',
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: JuzzioSocialTokens.dangerRed),
                  title: Text(app.loc('Şikâyet Et', 'Report', 'Melden')),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final reported = await showJuzzioReportModalSheet(
                      context: context,
                      targetType: 'post',
                      targetId: widget.post.id,
                      targetOwnerId: widget.post.authorId,
                    );
                    if (reported == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            app.loc('Şikâyetiniz alındı. Teşekkür ederiz.', 'Report submitted. Thank you.', 'Meldung gesendet. Danke.'),
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: JuzzioSocialTokens.dangerRed),
                  title: Text(
                    app.loc('Kullanıcıyı Engelle', 'Block User', 'Nutzer blockieren'),
                    style: const TextStyle(
                      color: JuzzioSocialTokens.dangerRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmBlockAuthor();
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditPostDialog() async {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final captionCtrl = TextEditingController(text: widget.post.caption);
    final locCtrl = TextEditingController(text: widget.post.locationName);
    String vis = widget.post.visibility;
    bool commentsOn = widget.post.commentsEnabled;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: JuzzioSocialTokens.cardBg(isDark),
          title: Text(
            app.loc('Gönderiyi Düzenle', 'Edit Post', 'Beitrag bearbeiten'),
            style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: captionCtrl,
                  maxLines: 3,
                  style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
                  decoration: InputDecoration(
                    labelText: app.loc('Açıklama', 'Caption', 'Beschriftung'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locCtrl,
                  style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
                  decoration: InputDecoration(
                    labelText: app.loc('Konum (İsteğe bağlı)', 'Location (Optional)', 'Ort (optional)'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: vis,
                  dropdownColor: JuzzioSocialTokens.cardBg(isDark),
                  items: [
                    DropdownMenuItem(value: 'public', child: Text(app.loc('Herkese Açık', 'Public', 'Öffentlich'))),
                    DropdownMenuItem(value: 'followers', child: Text(app.loc('Takipçilerim', 'Followers', 'Follower'))),
                    DropdownMenuItem(value: 'friends', child: Text(app.loc('Arkadaşlarım', 'Friends', 'Meine Freunde'))),
                    DropdownMenuItem(value: 'private', child: Text(app.loc('Yalnızca Ben', 'Only Me', 'Nur ich'))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => vis = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: commentsOn,
                  title: Text(
                    app.loc('Yorumlara İzin Ver', 'Allow Comments', 'Kommentare erlauben'),
                    style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark), fontSize: 14),
                  ),
                  onChanged: (v) => setDlgState(() => commentsOn = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(app.loc('Vazgeç', 'Cancel', 'Abbrechen')),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDlgState(() => saving = true);
                      try {
                        final updated = await JuzzioSocialService.instance.updatePost(
                          postId: widget.post.id,
                          caption: captionCtrl.text,
                          locationName: locCtrl.text,
                          visibility: vis,
                          commentsEnabled: commentsOn,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) widget.onPostUpdated(updated);
                      } catch (_) {
                        setDlgState(() => saving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: JuzzioSocialTokens.royalBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(app.loc('Kaydet', 'Save', 'Speichern')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost() async {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuzzioSocialTokens.cardBg(isDark),
        title: Text(
          app.loc('Gönderiyi Sil', 'Delete Post', 'Beitrag löschen'),
          style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
        ),
        content: Text(
          app.loc(
            'Bu gönderiyi kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
            'Are you sure you want to permanently delete this post? This action cannot be undone.', 'Möchtest du diesen Beitrag wirklich endgültig löschen? Das kann nicht rückgängig gemacht werden.',
          ),
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
            child: Text(app.loc('Gönderiyi Sil', 'Delete Post', 'Beitrag löschen')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await JuzzioSocialService.instance.deletePost(widget.post);
        if (mounted) {
          widget.onPostDeleted(widget.post.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(app.loc('Gönderi silindi.', 'Post deleted.', 'Beitrag gelöscht.'))),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(app.loc('Gönderi silinemedi.', 'Could not delete post.', 'Beitrag konnte nicht gelöscht werden.'))),
          );
        }
      }
    }
  }

  Future<void> _confirmBlockAuthor() async {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuzzioSocialTokens.cardBg(isDark),
        title: Text(
          app.loc('Kullanıcıyı Engelle', 'Block User', 'Nutzer blockieren'),
          style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
        ),
        content: Text(
          app.loc(
            '@${widget.post.authorUsername} adlı kullanıcıyı engellemek istiyor musunuz? Birbirinizin profilini, gönderilerini ve mesajlarını göremezsiniz.',
            'Do you want to block @${widget.post.authorUsername}? You will no longer see each other\'s posts, profile, or messages.', 'Möchtest du @${widget.post.authorUsername} blockieren? Ihr seht dann gegenseitig keine Beiträge, Profile oder Nachrichten mehr.',
          ),
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
            child: Text(app.loc('Engelle', 'Block', 'Blockieren')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await JuzzioSocialService.instance.blockUser(
          targetUser: JuzzioUserProfile(
            id: widget.post.authorId,
            username: widget.post.authorUsername,
            displayName: widget.post.authorDisplayName,
            email: '',
            bio: '',
            preferredLang: 'tr',
            avatarUrl: widget.post.authorAvatarUrl,
          ),
        );
        app.blockUsername(widget.post.authorUsername);
        if (mounted) {
          widget.onPostDeleted(widget.post.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                app.loc('@${widget.post.authorUsername} engellendi.', '@${widget.post.authorUsername} blocked.', '@${widget.post.authorUsername} blockiert.'),
              ),
            ),
          );
        }
      } catch (_) {}
    }
  }

  bool _isTextOnlyPost(JuzzioPost p) =>
      p.mediaUrls.isEmpty && (p.coverUrl == null || p.coverUrl!.isEmpty);

  Widget _buildMediaArea(bool isDark) {
    final urls = widget.post.mediaUrls.isNotEmpty
        ? widget.post.mediaUrls
        : (widget.post.coverUrl != null && widget.post.coverUrl!.isNotEmpty
            ? [widget.post.coverUrl!]
            : <String>[]);
    if (urls.isEmpty) {
      // v0.7.0: yalnızca yazı paylaşımı — sabit tipografili cam kart; çeviri geldiğinde
      // metin zıplamadan yumuşakça değişir (kayma ve boyut sorunu giderildi).
      final post = widget.post;
      if (post.caption.trim().isEmpty) return const SizedBox.shrink();
      _ensureCaptionTranslation(post);
      final app = JuzzioAppController.instance;
      final showTr = _captionTr != null && !_captionOriginal;
      final len = post.caption.trim().length;
      final size = len < 80 ? 21.0 : (len < 220 ? 17.5 : 15.5);
      return GestureDetector(
        onTap: () => widget.onOpenPostDetail(post),
        onDoubleTap: () => _handleLikeToggle(forceLikeOnly: true),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x14FFFFFF) : const Color(0x0A000000),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isDark ? const Color(0x24FFFFFF) : const Color(0x14000000)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // v0.8.0: AnimatedSize kaldırıldı (yazı kayması/titreme kökten çözüldü)
              SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, if (cur != null) cur]),
                  child: Text(
                    juzzioTidyText(showTr ? _captionTr! : post.caption),
                    key: ValueKey(showTr),
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.start,
                    softWrap: true,
                    style: TextStyle(
                      color: JuzzioSocialTokens.textPrimary(isDark),
                      fontSize: size * app.messageFontScale,
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: const ['JuzzioEmoji'],
                    ),
                  ),
                ),
              ),
              if (_captionTr != null)
                GestureDetector(
                  onTap: () => setState(() => _captionOriginal = !_captionOriginal),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _captionOriginal
                          ? app.loc('Çeviriyi gör', 'Show translation', 'Übersetzung zeigen')
                          : app.loc('Çevrildi · Orijinali gör', 'Translated · Show original', 'Übersetzt · Original zeigen'),
                      style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final ratio = widget.post.aspectRatio.clamp(0.75, 1.91);
    return GestureDetector(
      onTap: () => widget.onOpenPostDetail(widget.post),
      onDoubleTap: () => _handleLikeToggle(forceLikeOnly: true),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (idx) => setState(() => _carouselIndex = idx),
              itemBuilder: (_, idx) {
                final url = urls[idx];
                final isLocal = !url.startsWith('http') && File(url).existsSync();
                final isVideoItem = JuzzioPost.looksLikeVideoUrl(url) ||
                    (widget.post.isVideo && widget.post.mediaUrls.length == 1 && url == widget.post.mediaUrls.first);
                if (isVideoItem) {
                  final trim = widget.post.trimForMedia(idx);
                  return JuzzioInlineVideo(
                    key: ValueKey('${widget.post.id}#$idx'),
                    source: url,
                    coverUrl: idx == 0 ? widget.post.coverUrl : null,
                    trimStartMs: trim.startMs,
                    trimEndMs: trim.endMs,
                    speed: widget.post.playbackSpeed,
                    startMuted: true,
                    filterPreset: widget.post.filterPreset,
                    showBadge: false,
                    musicUrl: widget.post.musicUrl,
                    musicStartSec: widget.post.musicStartSec,
                  );
                }
                return JuzzioMediaFilters.apply(widget.post.filterPreset, Container(
                  color: isDark ? JuzzioColors.slate900 : JuzzioColors.slate200,
                  child: isLocal
                      ? Image.file(
                          File(url),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _mediaErrorFallback(isDark),
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (ctx, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: JuzzioSocialTokens.royalBlue,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => _mediaErrorFallback(isDark),
                        ),
                ));
              },
            ),
            if (widget.post.isVideo)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.62),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Video',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (urls.length > 1)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.62),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_carouselIndex + 1}/${urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (_showDoubleTapHeart)
              const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 86,
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaErrorFallback(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: JuzzioSocialTokens.textSecondary(isDark),
          ),
          const SizedBox(height: 6),
          Text(
            JuzzioAppController.instance.loc('Medya yüklenemedi', 'Media unavailable', 'Medien nicht verfügbar'),
            style: TextStyle(
              color: JuzzioSocialTokens.textSecondary(isDark),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final post = widget.post;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: JuzzioSocialTokens.cardBg(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: JuzzioSocialTokens.borderSubtle(isDark)),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst yazar satırı
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                JuzzioUserAvatar(
                  imageUrl: post.authorAvatarUrl,
                  displayName: post.authorDisplayName,
                  radius: 20,
                  onTap: () => widget.onOpenProfile(post.authorId),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onOpenProfile(post.authorId),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.authorDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: JuzzioSocialTokens.textPrimary(isDark),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (post.authorIsVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                color: JuzzioSocialTokens.royalBlue,
                                size: 15,
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.locationName.isNotEmpty
                                    ? '${post.locationName} • '
                                    : '@${post.authorUsername} • ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: JuzzioSocialTokens.textSecondary(isDark),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Tooltip(
                              message: JuzzioSocialTokens.formatAbsoluteTime(post.createdAt),
                              child: Text(
                                JuzzioSocialTokens.formatRelativeTime(post.createdAt, app),
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
                ),
                Semantics(
                  button: true,
                  label: app.loc('Gönderi seçenekleri', 'Post options', 'Beitragsoptionen'),
                  child: IconButton(
                    onPressed: _openContextMenu,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: JuzzioSocialTokens.textSecondary(isDark),
                    ),
                    tooltip: app.loc('Seçenekler', 'Options', 'Optionen'),
                  ),
                ),
              ],
            ),
          ),

          // Medya alanı
          _buildMediaArea(isDark),

          // Etkileşim satırı (Kalp, Yorum, Paylaş, Kaydet)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: app.loc('Beğen', 'Like', 'Gefällt mir'),
                  child: IconButton(
                    onPressed: () => _handleLikeToggle(),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      post.isLikedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: post.isLikedByMe
                          ? JuzzioSocialTokens.dangerRed
                          : JuzzioSocialTokens.textPrimary(isDark),
                      size: 24,
                    ),
                    tooltip: app.loc('Beğen', 'Like', 'Gefällt mir'),
                  ),
                ),
                Text(
                  '${post.likesCount}',
                  style: TextStyle(
                    color: JuzzioSocialTokens.textPrimary(isDark),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: app.loc('Yorumlar', 'Comments', 'Kommentare'),
                  child: IconButton(
                    onPressed: () => widget.onOpenComments(post),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      Icons.mode_comment_outlined,
                      color: JuzzioSocialTokens.textPrimary(isDark),
                      size: 22,
                    ),
                    tooltip: app.loc('Yorumlar', 'Comments', 'Kommentare'),
                  ),
                ),
                Text(
                  '${post.commentsCount}',
                  style: TextStyle(
                    color: JuzzioSocialTokens.textPrimary(isDark),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: app.loc('Paylaş', 'Share', 'Teilen'),
                  child: IconButton(
                    onPressed: () => showJuzzioSharePostModalSheet(
                      context: context,
                      post: post,
                      currentUser: widget.currentUser,
                    ),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      Icons.send_rounded,
                      color: JuzzioSocialTokens.textPrimary(isDark),
                      size: 21,
                    ),
                    tooltip: app.loc('Paylaş', 'Share', 'Teilen'),
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: app.loc('Kaydet', 'Save', 'Speichern'),
                  child: IconButton(
                    onPressed: _handleSaveToggle,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      post.isSavedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: post.isSavedByMe
                          ? JuzzioSocialTokens.royalBlue
                          : JuzzioSocialTokens.textPrimary(isDark),
                      size: 24,
                    ),
                    tooltip: app.loc('Kaydet', 'Save', 'Speichern'),
                  ),
                ),
              ],
            ),
          ),

          // Açıklama ve Etiketler
          if (post.caption.trim().isNotEmpty || post.hashtags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.caption.trim().isNotEmpty && !_isTextOnlyPost(post)) ...[
                    Builder(builder: (_) {
                      _ensureCaptionTranslation(post);
                      return const SizedBox.shrink();
                    }),
                    GestureDetector(
                      onTap: () => widget.onOpenPostDetail(post),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: JuzzioSocialTokens.textPrimary(isDark),
                            fontSize: 13.8 * app.messageFontScale,
                            height: 1.4,
                            fontFamilyFallback: const ['JuzzioEmoji'],
                          ),
                          children: [
                            TextSpan(
                              text: '${post.authorUsername} ',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: juzzioTidyText(_captionTr != null && !_captionOriginal ? _captionTr! : post.caption),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_captionTr != null && _captionTr!.trim() != post.caption.trim())
                      GestureDetector(
                        onTap: () => setState(() => _captionOriginal = !_captionOriginal),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _captionOriginal
                                ? app.loc('Çeviriyi gör', 'Show translation', 'Übersetzung zeigen')
                                : app.loc('Çevrildi · Orijinali gör', 'Translated · Show original', 'Übersetzt · Original zeigen'),
                            style: TextStyle(
                              color: JuzzioSocialTokens.textSecondary(isDark),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (post.hashtags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: post.hashtags.map((tag) {
                        return InkWell(
                          onTap: widget.onTapHashtag != null
                              ? () => widget.onTapHashtag!(tag)
                              : null,
                          child: Text(
                            '#$tag',
                            style: const TextStyle(
                              color: JuzzioSocialTokens.royalBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}


/// v0.8.0: paylaşım metnindeki ardışık boşlukları ve görünmez ayırıcıları
/// sadeleştirir (yazı aralarının açılması / iki yana yaslanmış görünmesi düzeltildi)
String juzzioTidyText(String s) => s
    .replaceAll(RegExp(r'[\u00A0\u2000-\u200B\u202F\u205F\u3000]'), ' ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
