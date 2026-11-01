import 'dart:async';
// =============================================================================
// JUZZIO v0.1.0 - Eksiksiz Ayarlar Paketi (Görseldeki "Ayarlar", "Bildirimler"
// ve "Profili Düzenle" Tasarımı ile Birebir Uyumlu, Temiz 6 Ana Kategori Mimarisinde:
// 1. Hesap (Profili Düzenle, Şifre, E-Posta, Kullanıcı Adı, Güvenlik Bildirimleri, Bağlı Cihazlar QR, Hesabı Sil)
// 2. Gizlilik (Son Görülme/Çevrimiçi, Profil/Hakkında/Durum, Okundu Bilgisi, Süreli Mesajlar,
//    Gruplar, Aramalar & Kamera Güzelleştirme, Engellenenler, İzin Yöneticisi, Gelişmiş & Katı Hesap Koruması)
// 3. Bildirimler (Bildirim Merkezi, Yüksek Öncelikli Bildirimler, Sessiz Mod, Pil & FPS Optimizasyonu)
// 4. Görünüm (Gece/Gündüz/Sistem Modu, 10 Sohbet Teması, Yazı Tipi Boyutu, Sohbet Ayarları, Erişilebilirlik)
// 5. Dil (142+ Uygulama Dili & 142+ Canlı Altyazı Çeviri Dili)
// 6. Yardım & Destek (OTA Güncelleme Merkezi, Sohbet Yedekleme/Aktarma/Geçmiş, Depolama & Ağ, Davet, Yapımcı)
// + Çıkış Yap
// =============================================================================

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/notification_text.dart';
import '../main.dart';
import '../models/social_models.dart';
import '../services/fcm_push_service.dart';
import '../services/social_service.dart';
import '../services/supabase_service.dart';
import '../services/juzzio_features_service.dart';
import 'admin_panel_screen.dart';
import 'release_notes_screen.dart';
import 'close_friends_page.dart';
import 'sound_settings_page.dart';
import 'feedback_page.dart';
import 'backup_page.dart';
import 'theme_preview_page.dart';
import 'theme_studio_page.dart';
import '../widgets/glass/juzzio_theme_gallery.dart';
import 'legal_page.dart';
import '../core/release_notes.dart';
import '../widgets/social_common_widgets.dart';
import '../widgets/profile_extras.dart';
import 'social/social_screens.dart';

import '../core/theme/juzzio_aurora.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';

/// Üç dilli (tr/en/de) arayüz metni; diğer diller dil paketinden gelir.
String _l3(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

class JuzzioSettingsMainPage extends StatefulWidget {
  final JuzzioUserProfile? myProfile;
  final String fallbackDisplayName;
  final bool showBackButton;

  const JuzzioSettingsMainPage({
    super.key,
    required this.myProfile,
    required this.fallbackDisplayName,
    this.showBackButton = true,
  });

  @override
  State<JuzzioSettingsMainPage> createState() => _JuzzioSettingsMainPageState();
}

class _JuzzioSettingsMainPageState extends State<JuzzioSettingsMainPage> {
  JuzzioUserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.myProfile;
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<JuzzioUserProfile>(
      MaterialPageRoute(
        builder: (_) => JuzzioEditProfilePage(
          initialProfile: _profile,
          fallbackDisplayName: widget.fallbackDisplayName,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        final s = JuzzioStrings(appCtrl.uiLang);
        final uname = (_profile?.username ?? widget.fallbackDisplayName).replaceAll('@', '');
        final dname = _profile?.displayName ?? widget.fallbackDisplayName;
        final currentLangName = appCtrl.getLanguageOption(appCtrl.uiLang).nativeName;

        return Scaffold(
          backgroundColor: p.headerDarkForest,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Koyu Orman/Obsidyen Başlık ("Ayarlar" - Görsel ile Birebir!)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Row(
                    children: [
                      if (widget.showBackButton && Navigator.of(context).canPop()) ...[
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                        ),
                      ],
                      Text(
                        appCtrl.trEn('Ayarlar', 'Settings', 'Einstellungen'),
                        style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: appCtrl.trEn('QR Bağlantı Kodu', 'QR Sync Code', 'QR-Synchronisationscode'),
                        onPressed: () => _showQrSyncDialog(context, p, uname),
                        icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white70, size: 24),
                      ),
                    ],
                  ),
                ),

                // Yuvarlatılmış Beyaz / Gece Kart Gövdesi
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: p.cardBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
                      children: [
                        // 1. Üst Kullanıcı Kartı (Görseldeki "Kullanıcı / @kullanici / Hesap bilgilerini düzenle >")
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _openEditProfile,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: p.amberPrimary,
                                  backgroundImage: _profile?.avatarUrl != null &&
                                          _profile!.avatarUrl!.isNotEmpty
                                      ? NetworkImage(_profile!.avatarUrl!)
                                      : null,
                                  child: _profile?.avatarUrl == null ||
                                          _profile!.avatarUrl!.isEmpty
                                      ? Text(
                                          dname.isNotEmpty ? dname[0].toUpperCase() : 'J',
                                          style: const TextStyle(
                                            fontFamily: JuzzioConfig.fontRegularBold,
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              dname,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: p.textPrimary,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (_profile?.isVerified == true) ...[
                                            const SizedBox(width: 5),
                                            const JuzzioVerifiedTick(size: 17),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '@$uname',
                                        style: TextStyle(
                                          fontFamily: JuzzioConfig.fontRegularBold,
                                          color: p.textSecondary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        appCtrl.trEn(
                                          'Hesap bilgilerini düzenle',
                                          'Edit account information', 'Kontoinformationen bearbeiten',
                                        ),
                                        style: TextStyle(
                                          fontFamily: JuzzioConfig.fontRegularBold,
                                          color: p.textMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 24),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: p.glassBorder),
                        const SizedBox(height: 10),

                        // KATEGORİ 1: HESAP
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.person_outline_rounded,
                          title: appCtrl.trEn('Hesap', 'Account', 'Konto'),
                          subtitle: appCtrl.trEn(
                            'Hesap ayarları, güvenlik',
                            'Account settings, security', 'Kontoeinstellungen, Sicherheit',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => JuzzioAccountSettingsPage(
                                initialUsername: uname,
                                initialEmail: _profile?.email ??
                                    SupabaseService.instance.client.auth.currentUser?.email ??
                                    '',
                                myProfile: _profile,
                              ),
                            ),
                          ),
                        ),

                        // KATEGORİ 2: GİZLİLİK (İzinler, Kamera Güzelleştirme ve Katı Hesap Koruması dahil)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.lock_outline_rounded,
                          title: appCtrl.trEn('Gizlilik', 'Privacy', 'Datenschutz'),
                          subtitle: appCtrl.trEn(
                            'Gizlilik ayarları',
                            'Privacy settings', 'Datenschutzeinstellungen',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JuzzioPrivacySettingsPage()),
                          ),
                        ),

                        // KATEGORİ 3: BİLDİRİMLER (Bildirim Merkezi, Sessiz Mod ve Pil/Performans Optimizasyonu dahil)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.notifications_none_rounded,
                          title: appCtrl.trEn('Bildirimler', 'Notifications', 'Benachrichtigungen'),
                          subtitle: appCtrl.trEn(
                            'Bildirim tercihleri',
                            'Notification preferences', 'Benachrichtigungseinstellungen',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JuzzioNotificationsSettingsPage()),
                          ),
                        ),

                        // KATEGORİ 4: GÖRÜNÜM (Gece/Gündüz Modu, 10 Sohbet Teması, Yazı Tipi, Erişilebilirlik dahil)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.sentiment_satisfied_alt_rounded,
                          title: appCtrl.trEn('Görünüm', 'Appearance', 'Darstellung'),
                          subtitle: appCtrl.trEn(
                            'Tema, yazı tipi',
                            'Theme, font style', 'Design, Schriftart',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JuzzioAppearanceSettingsPage()),
                          ),
                        ),

                        // KATEGORİ 5: DİL (Uygulama Dili & Canlı Altyazı Çeviri Dili - 142+ Dil)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.language_rounded,
                          title: appCtrl.trEn('Dil', 'Language', 'Sprache'),
                          subtitle: currentLangName,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JuzzioLanguageSettingsPage()),
                          ),
                        ),

                        // KATEGORİ 6: YARDIM & DESTEK (OTA Güncelleme, Yedekleme/Geçmiş, Depolama, Davet, Yapımcı)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.help_outline_rounded,
                          title: appCtrl.trEn('Yardım & Destek', 'Help & Support', 'Hilfe & Support'),
                          subtitle: appCtrl.trEn(
                            'Sorular, geri bildirim',
                            'Questions, feedback & OTA updates', 'Fragen, Feedback & OTA-Updates',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => JuzzioHelpAndSupportPage(username: uname),
                            ),
                          ),
                        ),

                        // v0.8.0: KATEGORİ 7 — HAKKINDA (yapımcı, sürüm, yasal)
                        _cleanCategoryTile(
                          p: p,
                          icon: Icons.info_outline_rounded,
                          title: appCtrl.trEn('Hakkında', 'About', 'Über'),
                          subtitle: appCtrl.trEn('Yapımcı, sürüm, lisans', 'Creator, version, license', 'Entwickler, Version, Lizenz'),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JuzzioDeveloperPage()),
                          ),
                        ),

                        // YÖNETİCİ PANELİ: yalnızca @tugkancr hesabında görünür
                        if (uname.toLowerCase() == 'tugkancr')
                          _cleanCategoryTile(
                            p: p,
                            icon: Icons.admin_panel_settings_outlined,
                            title: appCtrl.t('admin_title'),
                            subtitle: appCtrl.t('admin_subtitle'),
                            onTap: () => openJuzzioAdminPanel(context),
                          ),

                        const SizedBox(height: 12),
                        Divider(height: 1, color: p.glassBorder),
                        const SizedBox(height: 14),

                        // ÇIKIŞ YAP (Görseldeki Kırmızı Çıkış Yap Satırı)
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await JuzzioFcmPushService.instance.deactivateCurrentDeviceToken();
                            await SupabaseService.instance.signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const JuzzioRootFlow()),
                              (route) => false,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: p.dangerRed.withOpacity(0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.logout_rounded,
                                    color: p.dangerRed,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  s.t('logout'),
                                  style: TextStyle(
                                    fontFamily: JuzzioConfig.fontRegularBold,
                                    color: p.dangerRed,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cleanCategoryTile({
    required JuzzioPalette p,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.pillBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: p.textPrimary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: JuzzioConfig.fontRegularBold,
                      color: p.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 22),
          ],
        ),
      ),
    );
  }

  static void _showQrSyncDialog(BuildContext context, JuzzioPalette p, String uname) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          _l3('Windows / Masaüstü QR Senkronizasyon', 'Windows / Desktop QR Sync', 'Windows-/Desktop-QR-Synchronisierung'),
          style: TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            color: p.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.qr_code_2_rounded, size: 150, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Text(
              _l3('Hesap: @$uname\nWindows için Juzzio uygulamasında QR kodunuzu okuttuğunuzda sohbetleriniz, kişileriniz ve engellenenler listeniz anında senkronize olur.', 'Account: @$uname\nWhen you scan your QR code in the Juzzio app for Windows, your chats, contacts and block list sync instantly.', 'Konto: @$uname\nWenn du deinen QR-Code in der Juzzio-App für Windows scannst, werden Chats, Kontakte und Blockierliste sofort synchronisiert.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: p.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              _l3('Kapat', 'Close', 'Schließen'),
              style: TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                color: p.amberGlow,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EKRAN 8: BİLDİRİMLER SAYFASI (Görseldeki "Bildirimler" Ekranı ile Birebir!)
// =============================================================================
class JuzzioNotificationsFeedPage extends StatefulWidget {
  final JuzzioUserProfile? currentUser;

  const JuzzioNotificationsFeedPage({
    super.key,
    this.currentUser,
  });

  @override
  State<JuzzioNotificationsFeedPage> createState() =>
      _JuzzioNotificationsFeedPageState();
}

class _JuzzioNotificationsFeedPageState
    extends State<JuzzioNotificationsFeedPage> {
  String _selectedCategory = 'all'; // 'all' | 'unread' | 'follow' | 'like' | 'comment' | 'message' | 'call'
  JuzzioDataLoadState _loadState = JuzzioDataLoadState.initialLoading;
  List<JuzzioNotificationItem> _items = <JuzzioNotificationItem>[];
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loadState = JuzzioDataLoadState.initialLoading);
    try {
      final list = await JuzzioSocialService.instance.fetchNotifications(
        unreadOnly: _selectedCategory == 'unread',
        eventCategory: (_selectedCategory == 'all' || _selectedCategory == 'unread')
            ? 'all'
            : _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loadState = list.isEmpty
            ? JuzzioDataLoadState.empty
            : JuzzioDataLoadState.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = JuzzioDataLoadState.error);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _items.every((n) => n.isRead)) return;
    setState(() => _markingAll = true);
    try {
      await JuzzioSocialService.instance.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((n) => n.copyWith(isRead: true)).toList();
        _markingAll = false;
      });
    } catch (_) {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _handleTapNotification(JuzzioNotificationItem item) async {
    if (!item.isRead) {
      try {
        await JuzzioSocialService.instance.markNotificationRead(item.id);
        if (mounted) {
          setState(() {
            final idx = _items.indexWhere((x) => x.id == item.id);
            if (idx >= 0) _items[idx] = item.copyWith(isRead: true);
          });
        }
      } catch (_) {}
    }
    if (!mounted) return;

    final uid = SupabaseService.instance.currentUserId ?? '';
    final fallbackUser = widget.currentUser ??
        JuzzioUserProfile(
          id: uid,
          username: 'kullanici',
          displayName: _l3('Kullanıcı', 'User', 'Nutzer'),
          email: '',
          bio: '',
          preferredLang: JuzzioAppController.instance.subtitleLang,
        );

    if (item.eventType == 'system') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JuzzioOtaUpdateSettingsPage()),
      );
      return;
    }

    if ((item.eventType == 'like' ||
            item.eventType == 'comment' ||
            item.eventType == 'reply') &&
        item.targetId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JuzzioPostDetailAndCommentsPage(
            postId: item.targetId,
            currentUser: fallbackUser,
            focusCommentInput: item.eventType != 'like',
          ),
        ),
      );
      return;
    }

    if (item.eventType.contains('follow') || item.eventType.contains('friend')) {
      final targetUid = item.actorId ?? item.targetId;
      if (targetUid.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JuzzioUserProfilePage(
              userId: targetUid,
              currentUser: fallbackUser,
            ),
          ),
        );
      }
      return;
    }

    Navigator.of(context).pop(item);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like':
      case 'story_like':
        return Icons.favorite_rounded;
      case 'comment':
      case 'reply':
      case 'story_reply':
        return Icons.mode_comment_rounded;
      case 'follow':
      case 'follow_request':
      case 'follow_accepted':
      case 'friend_request':
      case 'friend_accepted':
        return Icons.person_add_alt_1_rounded;
      case 'missed_call':
        return Icons.phone_missed_rounded;
      case 'group_activity':
        return Icons.groups_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'like':
      case 'story_like':
        return JuzzioColors.pink500;
      case 'comment':
      case 'reply':
      case 'story_reply':
        return JuzzioColors.blue600;
      case 'follow':
      case 'follow_request':
      case 'follow_accepted':
      case 'friend_request':
      case 'friend_accepted':
        return JuzzioColors.brandIndigo;
      case 'missed_call':
        return JuzzioColors.red500;
      case 'group_activity':
        return JuzzioColors.emerald500;
      default:
        return JuzzioColors.indigo500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final isDark = appCtrl.isDark;
        final unreadCount = _items.where((n) => !n.isRead).length;

        return Scaffold(
          backgroundColor: JuzzioSocialTokens.pageBg(isDark),
          body: Column(
            children: [
              JuzzioDarkHeaderBar(
                title: appCtrl.trEn('Bildirimler', 'Notifications', 'Benachrichtigungen'),
                subtitle: unreadCount > 0
                    ? '$unreadCount ${appCtrl.trEn("okunmamış bildirim", "unread notifications", "ungelesene Benachrichtigungen")}'
                    : appCtrl.trEn('Tüm bildirimler okundu', 'All caught up', 'Alles erledigt'),
                onBack: () => Navigator.of(context).pop(),
                actions: [
                  if (unreadCount > 0)
                    TextButton.icon(
                      onPressed: _markingAll ? null : _markAllRead,
                      icon: const Icon(Icons.done_all_rounded, color: Colors.white, size: 18),
                      label: Text(
                        appCtrl.trEn('Tümünü Okundu Yap', 'Mark All Read', 'Alle als gelesen markieren'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const JuzzioNotificationsSettingsPage(),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                    tooltip: appCtrl.trEn('Bildirim Ayarları', 'Notification Settings', 'Benachrichtigungseinstellungen'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              JuzzioFilterPillBar(
                items: [
                  MapEntry('all', appCtrl.trEn('Tümü', 'All', 'Alle')),
                  MapEntry('unread', appCtrl.trEn('Okunmamış', 'Unread', 'Ungelesen')),
                  MapEntry('follow', appCtrl.trEn('Takip & İstek', 'Follows', 'Follows')),
                  MapEntry('like', appCtrl.trEn('Beğeni', 'Likes', 'Likes')),
                  MapEntry('comment', appCtrl.trEn('Yorum', 'Comments', 'Kommentare')),
                  MapEntry('save', appCtrl.trEn('Kaydetme', 'Saves', 'Gespeichert')),
                ],
                selectedKey: _selectedCategory,
                onSelected: (key) {
                  setState(() => _selectedCategory = key);
                  _loadNotifications();
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadState == JuzzioDataLoadState.initialLoading
                    ? const JuzzioSkeletonListView(itemCount: 4, itemHeight: 74)
                    : (_loadState == JuzzioDataLoadState.error
                        ? JuzzioErrorRetryView(
                            message: appCtrl.trEn(
                              'Bildirimler yüklenemedi.',
                              'Could not load notifications.', 'Benachrichtigungen konnten nicht geladen werden.',
                            ),
                            onRetry: _loadNotifications,
                          )
                        : (_items.isEmpty
                            ? JuzzioEmptyStateView(
                                icon: Icons.notifications_none_rounded,
                                title: appCtrl.trEn(
                                  'Henüz Bildirim Yok',
                                  'No Notifications Yet', 'Noch keine Benachrichtigungen',
                                ),
                                subtitle: appCtrl.trEn(
                                  'Yeni beğeni, yorum, takip isteği, mesaj veya çağrı geldiğinde gerçek zamanlı olarak burada listelenir.',
                                  'Real-time likes, comments, follow requests, messages, and calls will appear here.', 'Likes, Kommentare, Folgeanfragen, Nachrichten und Anrufe erscheinen hier in Echtzeit.',
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadNotifications,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, idx) {
                                    final item = _items[idx];
                                    final badgeColor = _colorForType(item.eventType);
                                    return Dismissible(
                                      key: ValueKey('notif_${item.id}'),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: JuzzioSocialTokens.dangerRed,
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                      onDismissed: (_) async {
                                        final removed = item;
                                        setState(() {
                                          _items.removeAt(idx);
                                          if (_items.isEmpty) {
                                            _loadState = JuzzioDataLoadState.empty;
                                          }
                                        });
                                        try {
                                          await JuzzioSocialService.instance
                                              .deleteNotification(removed.id);
                                        } catch (_) {}
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: item.isRead
                                              ? JuzzioSocialTokens.cardBg(isDark)
                                              : JuzzioSocialTokens.royalBlue.withOpacity(isDark ? 0.14 : 0.07),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: item.isRead
                                                ? JuzzioSocialTokens.borderSubtle(isDark)
                                                : JuzzioSocialTokens.royalBlue.withOpacity(0.35),
                                          ),
                                        ),
                                        child: ListTile(
                                          onTap: () => _handleTapNotification(item),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                          leading: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              JuzzioUserAvatar(
                                                imageUrl: item.actorAvatarUrl,
                                                displayName: item.actorDisplayName,
                                                radius: 22,
                                              ),
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    color: badgeColor,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: JuzzioSocialTokens.cardBg(isDark),
                                                      width: 1.8,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _iconForType(item.eventType),
                                                    size: 11,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.actorDisplayName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: JuzzioSocialTokens.textPrimary(isDark),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14.5,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                JuzzioSocialTokens.formatRelativeTime(
                                                  item.createdAt,
                                                  appCtrl,
                                                ),
                                                style: TextStyle(
                                                  color: JuzzioSocialTokens.textSecondary(isDark),
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(
                                              juzzioLocalizedNotificationText(item),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: JuzzioSocialTokens.textSecondary(isDark),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          trailing: !item.isRead
                                              ? Container(
                                                  width: 9,
                                                  height: 9,
                                                  decoration: const BoxDecoration(
                                                    color: JuzzioSocialTokens.dangerRed,
                                                    shape: BoxShape.circle,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ))),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// EKRAN 9: PROFİLİ DÜZENLE SAYFASI (Bölüm 6.14 & 24.2 — Tam Doğrulama & Kırpma)
// =============================================================================
class JuzzioEditProfilePage extends StatefulWidget {
  final JuzzioUserProfile? initialProfile;
  final String fallbackDisplayName;

  const JuzzioEditProfilePage({
    super.key,
    required this.initialProfile,
    required this.fallbackDisplayName,
  });

  @override
  State<JuzzioEditProfilePage> createState() => _JuzzioEditProfilePageState();
}

class _JuzzioEditProfilePageState extends State<JuzzioEditProfilePage> {
  late TextEditingController _fullNameCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _musicUrlCtrl;
  late TextEditingController _musicTitleCtrl;
  late TextEditingController _musicStartCtrl;
  late bool _zoomEnabled = widget.initialProfile?.profileZoomEnabled ?? true;

  Future<void> _openMusicPicker() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => JuzzioMusicPickerPage(
          initialUrl: _musicUrlCtrl.text.trim(),
          initialStartSec: int.tryParse(_musicStartCtrl.text.trim()) ?? 0,
          initialTitle: _musicTitleCtrl.text.trim(),
          initialArtist: widget.initialProfile?.musicArtist ?? '',
        ),
      ),
    );
    if (changed != true || !mounted) return;
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    final fresh = await SupabaseService.instance.fetchUserProfile(uid);
    if (!mounted || fresh == null) return;
    setState(() {
      _musicUrlCtrl.text = fresh.musicUrl;
      _initialMusicUrl = fresh.musicUrl;
      _musicTitleCtrl.text = fresh.musicTitle;
      _musicStartCtrl.text = '${fresh.musicStartSec}';
    });
  }
  late String _initialWebsite;
  late String _initialMusicUrl;
  File? _pickedAvatarFile;
  bool _removeAvatarRequested = false;
  bool _isSaving = false;
  bool _checkingUsername = false;
  bool? _isUsernameAvailable;
  String? _validationError;
  Timer? _usernameDebounce;
  late String _initialFullName;
  late String _initialUsername;
  late String _initialBio;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final dname = widget.initialProfile?.displayName ?? widget.fallbackDisplayName;
    final uname = (widget.initialProfile?.username ?? widget.fallbackDisplayName).replaceAll('@', '');
    final bio = widget.initialProfile?.bio ?? '';
    _initialFullName = dname;
    _initialUsername = uname;
    _initialBio = bio;
    _fullNameCtrl = TextEditingController(text: dname);
    _usernameCtrl = TextEditingController(text: uname);
    _bioCtrl = TextEditingController(text: bio);
    _initialWebsite = widget.initialProfile?.websiteUrl ?? '';
    _initialMusicUrl = widget.initialProfile?.musicUrl ?? '';
    _websiteCtrl = TextEditingController(text: _initialWebsite);
    _musicUrlCtrl = TextEditingController(text: _initialMusicUrl);
    _musicTitleCtrl = TextEditingController(text: widget.initialProfile?.musicTitle ?? '');
    _musicStartCtrl = TextEditingController(text: '${widget.initialProfile?.musicStartSec ?? 0}');
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _websiteCtrl.dispose();
    _musicUrlCtrl.dispose();
    _musicTitleCtrl.dispose();
    _musicStartCtrl.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _pickedAvatarFile != null ||
      _removeAvatarRequested ||
      _fullNameCtrl.text.trim() != _initialFullName.trim() ||
      _usernameCtrl.text.trim().replaceAll('@', '') != _initialUsername.trim() ||
      _bioCtrl.text.trim() != _initialBio.trim() ||
      _websiteCtrl.text.trim() != _initialWebsite.trim() ||
      _musicUrlCtrl.text.trim() != _initialMusicUrl.trim();

  void _onUsernameChanged(String raw) {
    _usernameDebounce?.cancel();
    final clean = raw.trim().replaceAll('@', '');
    if (clean == _initialUsername) {
      setState(() {
        _checkingUsername = false;
        _isUsernameAvailable = true;
        _validationError = null;
      });
      return;
    }
    if (clean.length < 3 || !RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(clean)) {
      setState(() {
        _checkingUsername = false;
        _isUsernameAvailable = false;
      });
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 350), () async {
      final ok = await SupabaseService.instance.checkUsernameAvailability(clean);
      if (!mounted) return;
      setState(() {
        _checkingUsername = false;
        _isUsernameAvailable = ok;
      });
    });
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;
    final app = JuzzioAppController.instance;
    final isDark = app.isDark;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuzzioSocialTokens.cardBg(isDark),
        title: Text(
          app.loc('Değişiklikler Kaydedilmedi', 'Unsaved Changes', 'Nicht gespeicherte Änderungen'),
          style: TextStyle(color: JuzzioSocialTokens.textPrimary(isDark)),
        ),
        content: Text(
          app.loc(
            'Profilinizde yaptığınız değişiklikleri kaydetmeden çıkmak istiyor musunuz?',
            'Do you want to discard your profile changes?', 'Möchtest du deine Profiländerungen verwerfen?',
          ),
          style: TextStyle(color: JuzzioSocialTokens.textSecondary(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.loc('Düzenlemeye Dön', 'Keep Editing', 'Weiter bearbeiten')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: JuzzioSocialTokens.dangerRed,
              foregroundColor: Colors.white,
            ),
            child: Text(app.loc('Değişiklikleri At', 'Discard Changes', 'Änderungen verwerfen')),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _pickAndCropAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1400,
      );
      if (picked == null || !mounted) return;
      final cropped = await JuzzioImageCropperModal.show(
        context,
        sourceFile: File(picked.path),
        isCircular: true,
        aspectRatio: 1.0,
      );
      if (cropped != null && mounted) {
        setState(() {
          _pickedAvatarFile = cropped;
          _removeAvatarRequested = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _checkingUsername) return;
    final app = JuzzioAppController.instance;
    final cleanUname = _usernameCtrl.text.trim().replaceAll('@', '');
    final cleanDname = _fullNameCtrl.text.trim().isEmpty
        ? cleanUname
        : _fullNameCtrl.text.trim();
    final cleanBio = _bioCtrl.text.trim();
    final cleanWeb = _websiteCtrl.text.trim();

    if (cleanUname.length < 3 || !RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(cleanUname)) {
      setState(() {
        _validationError = app.loc(
          'Kullanıcı adı en az 3 karakter olmalı ve yalnızca harf, rakam, nokta veya alt çizgi içermelidir.',
          'Username must be at least 3 characters and contain only letters, digits, dots, or underscores.', 'Der Benutzername muss mindestens 3 Zeichen lang sein und darf nur Buchstaben, Ziffern, Punkte oder Unterstriche enthalten.',
        );
      });
      return;
    }

    if (_isUsernameAvailable == false) {
      setState(() {
        _validationError = app.loc(
          'Bu kullanıcı adı başka bir hesap tarafından kullanılıyor.',
          'This username is already taken.', 'Dieser Benutzername ist bereits vergeben.',
        );
      });
      return;
    }

    if (cleanWeb.isNotEmpty) {
      final normalized = cleanWeb.startsWith(RegExp(r'https?://', caseSensitive: false)) ? cleanWeb : 'https://$cleanWeb';
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
        setState(() => _validationError = app.t('err_website_invalid'));
        return;
      }
    }
    // v0.7.0: müzik isimle seçilir; eski YouTube bağlantısı kaydedilmez (temizlenir)
    final rawMusic = _musicUrlCtrl.text.trim();
    final cleanMusic = juzzioIsPlayableMusic(rawMusic) ? rawMusic : '';
    if (cleanBio.length > 180) {
      setState(() => _validationError = app.t('err_bio_too_long'));
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    try {
      final uid = SupabaseService.instance.currentUserId;
      if (uid != null) {
        final available = await SupabaseService.instance.checkUsernameAvailability(cleanUname);
        if (!available) {
          setState(() {
            _isSaving = false;
            _isUsernameAvailable = false;
            _validationError = app.loc(
              'Bu kullanıcı adı zaten alınmış. Lütfen farklı bir kullanıcı adı seçin.',
              'This username is already taken. Please choose another.', 'Dieser Benutzername ist bereits vergeben. Bitte wähle einen anderen.',
            );
          });
          return;
        }

        await SupabaseService.instance.updatePersonalInformation(
          newUsername: cleanUname,
          newDisplayName: cleanDname,
          newBio: cleanBio,
        );
        if (_zoomEnabled != (widget.initialProfile?.profileZoomEnabled ?? true)) {
          await JuzzioFeaturesService.instance.setProfileZoomEnabled(_zoomEnabled);
        }
        await JuzzioFeaturesService.instance.updateProfileExtras(
          websiteUrl: cleanWeb,
          musicUrl: cleanMusic,
          musicStartSec: int.tryParse(_musicStartCtrl.text.trim()) ?? 0,
          musicTitle: _musicTitleCtrl.text.trim(),
        );
        final updated = await SupabaseService.instance.uploadAvatarAndSaveProfile(
          userId: uid,
          displayName: cleanDname,
          bio: cleanBio,
          preferredLang: app.subtitleLang,
          newAvatarFile: _pickedAvatarFile,
          existingAvatarUrl: _removeAvatarRequested ? null : widget.initialProfile?.avatarUrl,
        );
        if (!mounted) return;
        Navigator.of(context).pop(
          updated ??
              JuzzioUserProfile(
                id: uid,
                username: cleanUname,
                displayName: cleanDname,
                email: widget.initialProfile?.email ?? '',
                bio: cleanBio,
                preferredLang: app.subtitleLang,
                avatarUrl: _removeAvatarRequested ? null : widget.initialProfile?.avatarUrl,
              ),
        );
      } else {
        Navigator.of(context).pop(
          JuzzioUserProfile(
            id: 'local_user',
            username: cleanUname,
            displayName: cleanDname,
            email: widget.initialProfile?.email ?? '',
            bio: cleanBio,
            preferredLang: app.subtitleLang,
            avatarUrl: _removeAvatarRequested ? null : widget.initialProfile?.avatarUrl,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _validationError = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final currentAvatar = _removeAvatarRequested ? null : widget.initialProfile?.avatarUrl;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canExit = await _confirmDiscardIfNeeded();
        if (canExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: p.headerDarkForest,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 18, 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        final canExit = await _confirmDiscardIfNeeded();
                        if (canExit && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        appCtrl.trEn('Profili Düzenle', 'Edit Profile', 'Profil bearbeiten'),
                        style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: (_isSaving || _checkingUsername) ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              appCtrl.trEn('Kaydet', 'Save', 'Speichern'),
                              style: const TextStyle(
                                fontFamily: JuzzioConfig.fontRegularBold,
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickAndCropAvatar,
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 50,
                                      backgroundColor: p.amberPrimary,
                                      backgroundImage: _pickedAvatarFile != null
                                          ? FileImage(_pickedAvatarFile!) as ImageProvider
                                          : (currentAvatar != null && currentAvatar.isNotEmpty
                                              ? NetworkImage(currentAvatar)
                                              : null),
                                      child: (_pickedAvatarFile == null &&
                                              (currentAvatar == null || currentAvatar.isEmpty))
                                          ? Text(
                                              _fullNameCtrl.text.isNotEmpty
                                                  ? _fullNameCtrl.text[0].toUpperCase()
                                                  : 'J',
                                              style: const TextStyle(
                                                fontFamily: JuzzioConfig.fontRegularBold,
                                                color: Colors.white,
                                                fontSize: 34,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: JuzzioColors.deepForest,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: p.cardBg, width: 2.2),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _pickAndCropAvatar,
                                    child: Text(appCtrl.trEn('Fotoğrafı Değiştir', 'Change Photo', 'Foto ändern')),
                                  ),
                                  if (_pickedAvatarFile != null ||
                                      (currentAvatar != null && currentAvatar.isNotEmpty))
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _pickedAvatarFile = null;
                                          _removeAvatarRequested = true;
                                        });
                                      },
                                      child: Text(
                                        appCtrl.trEn('Kaldır', 'Remove', 'Entfernen'),
                                        style: TextStyle(color: p.dangerRed),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_validationError != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: p.dangerRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: p.dangerRed.withOpacity(0.4)),
                            ),
                            child: Text(
                              _validationError!,
                              style: TextStyle(color: p.dangerRed, fontSize: 13),
                            ),
                          ),

                        Text(
                          appCtrl.trEn('Ad Soyad', 'Full Name', 'Vollständiger Name'),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _fullNameCtrl,
                          maxLength: 50,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: p.inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: p.glassBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          appCtrl.trEn('Kullanıcı Adı (@)', 'Username (@)', 'Benutzername (@)'),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameCtrl,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 30,
                          onChanged: _onUsernameChanged,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            prefixText: '@',
                            suffixIcon: _checkingUsername
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : (_isUsernameAvailable == null
                                    ? null
                                    : Icon(
                                        _isUsernameAvailable!
                                            ? Icons.check_circle_rounded
                                            : Icons.error_outline_rounded,
                                        color: _isUsernameAvailable!
                                            ? p.onlineGreen
                                            : p.dangerRed,
                                      )),
                            filled: true,
                            fillColor: p.inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: p.glassBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          appCtrl.trEn('Biyografi', 'Bio', 'Bio'),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bioCtrl,
                          maxLines: 3,
                          maxLength: 180,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 14.5,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: p.inputBg,
                            contentPadding: const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: p.glassBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          appCtrl.trEn('Bağlantı / Web Sitesi (İsteğe bağlı)', 'Website Link (Optional)', 'Website-Link (optional)'),
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _websiteCtrl,
                          keyboardType: TextInputType.url,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            color: p.textPrimary,
                            fontSize: 14.5,
                          ),
                          decoration: InputDecoration(
                            hintText: appCtrl.t('website_hint'),
                            filled: true,
                            fillColor: p.inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: p.glassBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Müzik: Instagram tarzı müzik ekleme sayfası açılır
                        Material(
                          color: p.inputBg,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: p.textPrimary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: p.glassBorder),
                              ),
                              child: Icon(Icons.music_note_rounded, color: p.textPrimary),
                            ),
                            title: Text(
                              _musicUrlCtrl.text.trim().isEmpty
                                  ? _l3('Müzik ekle', 'Add music', 'Musik hinzufügen')
                                  : (_musicTitleCtrl.text.trim().isNotEmpty ? _musicTitleCtrl.text.trim() : appCtrl.t('profile_music_title')),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              appCtrl.t('profile_music_help'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.textMuted, fontSize: 12),
                            ),
                            trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                            onTap: _openMusicPicker,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: p.amberGlow,
                          value: _zoomEnabled,
                          onChanged: (v) => setState(() => _zoomEnabled = v),
                          title: Text(
                            _l3('Profil fotoğrafı yakınlaştırma', 'Profile photo zoom', 'Profilfoto-Zoom'),
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            _l3('Kapalıysa başkaları profil fotoğrafınızı büyüterek göremez.',
                                'When off, others cannot enlarge your profile photo.',
                                'Wenn aus, können andere dein Profilfoto nicht vergrößern.'),
                            style: TextStyle(color: p.textSecondary, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 6),

                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: p.amberGlow,
                          value: appCtrl.isPrivateAccount,
                          title: Text(
                            appCtrl.trEn('Gizli Hesap', 'Private Account', 'Privates Konto'),
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: p.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            appCtrl.trEn(
                              'Etkinleştirildiğinde yalnızca onayladığınız takipçiler gönderilerinizi ve hikâyelerinizi görebilir.',
                              'When enabled, only approved followers can see your posts and stories.', 'Wenn aktiviert, können nur bestätigte Follower deine Beiträge und Storys sehen.',
                            ),
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: p.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          onChanged: (val) => setState(() => appCtrl.setPrivateAccount(val)),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (_isSaving || _checkingUsername) ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appCtrl.isDark ? Colors.white : JuzzioColors.ink,
                              foregroundColor: appCtrl.isDark ? JuzzioColors.ink : Colors.white,
                              shape: const StadiumBorder(),
                              elevation: 0,
                            ),
                            child: _isSaving
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: appCtrl.isDark ? JuzzioColors.ink : Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(
                                    appCtrl.trEn('Değişiklikleri Kaydet', 'Save Changes', 'Änderungen speichern'),
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class JuzzioAccountSettingsPage extends StatefulWidget {
  final String initialUsername;
  final String initialEmail;
  final JuzzioUserProfile? myProfile;

  const JuzzioAccountSettingsPage({
    super.key,
    required this.initialUsername,
    required this.initialEmail,
    this.myProfile,
  });

  @override
  State<JuzzioAccountSettingsPage> createState() => _JuzzioAccountSettingsPageState();
}

class _JuzzioAccountSettingsPageState extends State<JuzzioAccountSettingsPage> {
  late String _currentUsername;
  late String _currentEmail;

  @override
  void initState() {
    super.initState();
    _currentUsername = widget.initialUsername.replaceAll('@', '');
    _currentEmail = widget.initialEmail;
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final isTr = appCtrl.uiLang == 'tr';

    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(
          _l3('Hesap', 'Account', 'Konto'),
          style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // ÜST BAŞLIK: HESAP
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              _l3('Hesap', 'Account', 'Konto'),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.badge_outlined, color: p.amberGlow),
                  title: Text(
                    _l3('Profili ve Kişisel Bilgileri Düzenle', 'Edit Profile & Personal Info', 'Profil & persönliche Daten bearbeiten'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _l3('Ad soyad, biyografi ve profil fotoğrafı', 'Full name, bio, and profile photo', 'Name, Bio und Profilbild'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => JuzzioEditProfilePage(
                        initialProfile: widget.myProfile,
                        fallbackDisplayName: _currentUsername,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.qr_code_2_rounded, color: p.amberGlow),
                  title: Text(
                    _l3('Bağlı Cihazlar (Masaüstü QR Senkronizasyon)', 'Linked Devices (Desktop QR Sync)', 'Verknüpfte Geräte (Desktop-QR-Sync)'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _l3('Windows ve diğer cihazlarla anlık senkronizasyon', 'Instant sync with Windows & desktop devices', 'Sofortige Synchronisierung mit Windows & Desktop-Geräten'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () => _JuzzioSettingsMainPageState._showQrSyncDialog(context, p, _currentUsername),
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.password_rounded, color: p.amberGlow),
                  title: Text(
                    _l3('Şifre', 'Password', 'Passwort'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _l3('Mevcut şifrenizi doğrulayarak yeni şifre belirleyin', 'Verify current password and set a new one', 'Aktuelles Passwort bestätigen und neues festlegen'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JuzzioChangePasswordPage()),
                  ),
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.email_outlined, color: p.amberGlow),
                  title: Text(
                    _l3('E-Posta adresi', 'Email address', 'E-Mail-Adresse'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _currentEmail.isNotEmpty ? _currentEmail : _l3('E-posta tanımlı', 'Email set', 'E-Mail hinterlegt'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.verified_rounded, color: p.onlineGreen, size: 20),
                  onTap: () => _showEmailEditDialog(context, p, isTr),
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.security_rounded, color: p.amberGlow),
                  title: Text(
                    _l3('Güvenlik Bildirimleri', 'Security Notifications', 'Sicherheitsbenachrichtigungen'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _l3('Uçtan uca şifreleme ve güvenlik kodu bildirimleri', 'End-to-end encryption & security code alerts', 'Benachrichtigungen zu Ende-zu-Ende-Verschlüsselung & Sicherheitscode'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JuzzioSecurityNotificationsPage()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ALT BAŞLIK (Aynı Sayfa İçinde): HESABINIZ
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              _l3('Hesabınız', 'Your Account', 'Dein Konto'),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.alternate_email_rounded, color: p.amberGlow),
                  title: Text(
                    _l3('Kullanıcı adı', 'Username', 'Benutzername'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '@$_currentUsername',
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () async {
                    final updated = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => JuzzioUsernameSettingsPage(currentUsername: _currentUsername),
                      ),
                    );
                    if (updated != null && mounted) {
                      setState(() => _currentUsername = updated);
                    }
                  },
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: p.dangerRed),
                  title: Text(
                    _l3('Hesabımı Sil', 'Delete My Account', 'Mein Konto löschen'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _l3('Hesabınızı ve tüm verilerinizi kalıcı olarak silin', 'Permanently delete your account and all data', 'Konto und alle Daten dauerhaft löschen'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.dangerRed),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JuzzioDeleteAccountPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEmailEditDialog(BuildContext context, JuzzioPalette p, bool isTr) {
    final ctrl = TextEditingController(text: _currentEmail);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          _l3('E-Posta Adresi', 'Email Address', 'E-Mail-Adresse'),
          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: p.inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_l3('İptal', 'Cancel', 'Abbrechen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: p.amberPrimary, foregroundColor: Colors.white),
            onPressed: () {
              setState(() => _currentEmail = ctrl.text.trim());
              Navigator.of(ctx).pop();
            },
            child: Text(_l3('Kaydet', 'Save', 'Speichern')),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1A. ŞİFRE DEĞİŞTİRME SAYFASI (Eski şifre doğrulama + Yeni şifre 2 kez kontrol)
// -----------------------------------------------------------------------------
class JuzzioChangePasswordPage extends StatefulWidget {
  const JuzzioChangePasswordPage({super.key});

  @override
  State<JuzzioChangePasswordPage> createState() => _JuzzioChangePasswordPageState();
}

class _JuzzioChangePasswordPageState extends State<JuzzioChangePasswordPage> {
  final TextEditingController _oldPassCtrl = TextEditingController();
  final TextEditingController _newPass1Ctrl = TextEditingController();
  final TextEditingController _newPass2Ctrl = TextEditingController();
  bool _isSubmitting = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _oldPassCtrl.dispose();
    _newPass1Ctrl.dispose();
    _newPass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordChange() async {
    final oldPass = _oldPassCtrl.text;
    final new1 = _newPass1Ctrl.text;
    final new2 = _newPass2Ctrl.text;

    if (oldPass.isEmpty || new1.length < 6) {
      setState(() {
        _isSuccess = false;
        _statusMessage = _l3('Lütfen mevcut şifrenizi ve en az 6 karakterli yeni şifrenizi girin.', 'Please enter your current password and a new password of at least 6 characters.', 'Bitte gib dein aktuelles Passwort und ein neues Passwort mit mindestens 6 Zeichen ein.');
      });
      return;
    }

    if (new1 != new2) {
      setState(() {
        _isSuccess = false;
        _statusMessage = _l3('Yeni girilen iki şifre birbiriyle eşleşmiyor. Lütfen kontrol edin.', 'The two new passwords do not match. Please check.', 'Die beiden neuen Passwörter stimmen nicht überein. Bitte prüfen.');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
    });

    try {
      await SupabaseService.instance.verifyAndChangePassword(
        currentPassword: oldPass,
        newPassword: new1,
      );
      if (!mounted) return;
      setState(() {
        _isSuccess = true;
        _statusMessage = _l3('Şifre değişikliği yapıldı ve başarıyla onaylandı.', 'Your password was changed successfully.', 'Dein Passwort wurde erfolgreich geändert.');
      });
      _oldPassCtrl.clear();
      _newPass1Ctrl.clear();
      _newPass2Ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSuccess = false;
        _statusMessage = SupabaseService.instance.friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(JuzzioAppController.instance.loc('Şifre Değiştir', 'Change Password', 'Passwort ändern'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l3('Mevcut Şifreniz', 'Current Password', 'Aktuelles Passwort'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _oldPassCtrl,
                  obscureText: true,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: JuzzioAppController.instance.trEn('Kullandığınız mevcut şifreyi girin', 'Enter your current password', 'Gib dein aktuelles Passwort ein'),
                    hintStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted),
                    prefixIcon: Icon(Icons.lock_outline_rounded, color: p.amberGlow),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _l3('Yeni Şifre', 'New Password', 'Neues Passwort'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPass1Ctrl,
                  obscureText: true,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: JuzzioAppController.instance.trEn('Yeni şifrenizi girin', 'Enter your new password', 'Gib dein neues Passwort ein'),
                    hintStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted),
                    prefixIcon: Icon(Icons.key_rounded, color: p.amberGlow),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _l3('Yeni Şifreyi Doğrula (2. Kez)', 'Confirm New Password (2nd time)', 'Neues Passwort bestätigen (2. Mal)'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newPass2Ctrl,
                  obscureText: true,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: JuzzioAppController.instance.trEn('Yeni şifrenizi tekrar girin', 'Re-enter your new password', 'Gib dein neues Passwort erneut ein'),
                    hintStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted),
                    prefixIcon: Icon(Icons.verified_user_outlined, color: p.amberGlow),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_isSuccess ? p.onlineGreen : p.dangerRed).withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _isSuccess ? p.onlineGreen : p.dangerRed),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: _isSuccess ? p.onlineGreen : p.dangerRed,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: _isSuccess ? p.onlineGreen : p.dangerRed,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.amberPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _isSubmitting ? null : _handlePasswordChange,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      JuzzioAppController.instance.loc('Şifre Değişikliğini Onayla', 'Confirm Password Change', 'Passwortänderung bestätigen'),
                      style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1B. GÜVENLİK BİLDİRİMLERİ SAYFASI (Kilit Logosu + E2EE + 5 Uygulama İkonu + Cihaz Tiki)
// -----------------------------------------------------------------------------
class JuzzioSecurityNotificationsPage extends StatelessWidget {
  const JuzzioSecurityNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Güvenlik bildirimleri', 'Security notifications', 'Sicherheitsbenachrichtigungen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Kilit Logosu
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: p.amberButtonGradient,
                        boxShadow: [
                          BoxShadow(
                            color: p.amberPrimary.withOpacity(0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.lock_rounded, color: Colors.white, size: 42),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      JuzzioAppController.instance.loc('Sohbetleriniz ve aramalarınız gizlidir', 'Your chats and calls are private', 'Deine Chats und Anrufe sind privat'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      JuzzioAppController.instance.loc('Uçtan uca şifreleme özelliği sayesinde kişisel mesajlarınız ve aramalarınız seçtiğiniz kişilerle aranızda kalır. JUZZIO da dahil olmak üzere sohbet dışındaki hiç kimse bu içerikleri okuyamaz, dinleyemez veya paylaşamaz. Bu içerikler arasında aşağıdakiler bulunur:', 'End-to-end encryption keeps your personal messages and calls between you and the people you choose. Not even JUZZIO can read, listen to, or share them. This includes:', 'Ende-zu-Ende-Verschlüsselung hält deine persönlichen Nachrichten und Anrufe zwischen dir und den Personen, die du auswählst. Nicht einmal JUZZIO kann sie lesen, anhören oder weitergeben. Dazu gehören:'),
                      textAlign: TextAlign.left,
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary,
                        fontSize: 13.5,
                        height: 1.48,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _e2eeFeatureRow(p, Icons.chat_bubble_rounded, _l3('Yazılı ve sesli mesajlarınız', 'Your text and voice messages', 'Deine Text- und Sprachnachrichten')),
                    _e2eeFeatureRow(p, Icons.call_rounded, _l3('Sesli ve görüntülü aramalarınız', 'Your voice and video calls', 'Deine Sprach- und Videoanrufe')),
                    _e2eeFeatureRow(p, Icons.attach_file_rounded, _l3('Fotoğraf, video ve belgeleriniz', 'Your photos, videos and documents', 'Deine Fotos, Videos und Dokumente')),
                    _e2eeFeatureRow(p, Icons.location_on_rounded, _l3('Konum paylaşımlarınız', 'Your location shares', 'Deine geteilten Standorte')),
                    _e2eeFeatureRow(p, Icons.amp_stories_rounded, _l3('Durum güncellemeleriniz', 'Your status updates', 'Deine Status-Updates')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Bu cihazda güvenlik bildirimlerini göster', 'Show security notifications on this device', 'Sicherheitsbenachrichtigungen auf diesem Gerät anzeigen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      value: appCtrl.securityNotificationsOnDevice,
                      onChanged: appCtrl.setSecurityNotificationsOnDevice,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      JuzzioAppController.instance.loc('Uçtan uca şifrelenmiş bir sohbetteki herhangi bir kişinin telefonu için güvenlik kodunuz değiştiğinde bildirim alın. Birden fazla cihazınız varsa bildirim almak istediğiniz her cihazda bu ayarın etkinleştirilmesi gerekir.', 'Get notified when your security code changes for a contact in an end-to-end encrypted chat. If you have multiple devices, this setting must be enabled on each device where you want to receive notifications.', 'Werde benachrichtigt, wenn sich der Sicherheitscode eines Kontakts in einem Ende-zu-Ende-verschlüsselten Chat ändert. Wenn du mehrere Geräte hast, muss diese Einstellung auf jedem Gerät aktiviert werden, auf dem du Benachrichtigungen erhalten möchtest.'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _e2eeFeatureRow(JuzzioPalette p, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.amberPrimary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: p.amberGlow, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1C. KULLANICI ADI DÜZENLEME & ANLIK MÜSAİTLİK KONTROL SAYFASI
// -----------------------------------------------------------------------------
class JuzzioUsernameSettingsPage extends StatefulWidget {
  final String currentUsername;

  const JuzzioUsernameSettingsPage({super.key, required this.currentUsername});

  @override
  State<JuzzioUsernameSettingsPage> createState() => _JuzzioUsernameSettingsPageState();
}

class _JuzzioUsernameSettingsPageState extends State<JuzzioUsernameSettingsPage> {
  late TextEditingController _usernameCtrl;
  bool _isEditMode = false;
  bool _isChecking = false;
  bool? _isAvailable;
  String? _availabilityMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.currentUsername);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability(String val) async {
    final clean = val.trim().replaceAll('@', '');
    if (clean.length < 3) {
      setState(() {
        _isAvailable = false;
        _availabilityMessage = _l3('Kullanıcı adı en az 3 karakter olmalıdır.', 'Username must be at least 3 characters.', 'Der Benutzername muss mindestens 3 Zeichen lang sein.');
      });
      return;
    }
    setState(() => _isChecking = true);
    final available = await SupabaseService.instance.checkUsernameAvailability(clean);
    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _isAvailable = available;
      _availabilityMessage = available
          ? _l3('Bu kullanıcı adı müsait, kullanılabilir.', 'This username is available.', 'Dieser Benutzername ist verfügbar.')
          : _l3('Bu kullanıcı adı şu anda başka bir kullanıcıya aittir ve kullanılamaz.', 'This username belongs to another user and cannot be used.', 'Dieser Benutzername gehört einem anderen Nutzer und kann nicht verwendet werden.');
    });
  }

  void _openEditMenu(JuzzioPalette p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.bgSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: p.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_rounded, color: p.amberGlow),
              title: Text(
                _l3('Kullanıcı adını değiştir', 'Change username', 'Benutzernamen ändern'),
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _isEditMode = true;
                  _isAvailable = true;
                  _availabilityMessage = _l3('Bu kullanıcı adı müsait, kullanılabilir.', 'This username is available.', 'Dieser Benutzername ist verfügbar.');
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.dangerRed),
              title: Text(
                _l3('Kullanıcı adını sil', 'Delete username', 'Benutzernamen löschen'),
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w800),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                final fallback = 'user_${DateTime.now().millisecondsSinceEpoch % 10000}';
                await SupabaseService.instance.updateMyUsername(fallback);
                if (!mounted) return;
                Navigator.of(context).pop(fallback);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(JuzzioAppController.instance.loc('Kullanıcı adı', 'Username', 'Benutzername'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: () => _openEditMenu(p),
            child: Text(
              _l3('Düzenleyin', 'Edit', 'Bearbeiten'),
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l3('Mevcut Kullanıcı Adınız', 'Your Current Username', 'Dein aktueller Benutzername'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: _isEditMode,
                  onChanged: _checkAvailability,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    prefixText: '@',
                    prefixStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 17),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                if (_isChecking) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_availabilityMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_isAvailable == true ? p.onlineGreen : p.dangerRed).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _isAvailable == true ? p.onlineGreen : p.dangerRed),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAvailable == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: _isAvailable == true ? p.onlineGreen : p.dangerRed,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _availabilityMessage!,
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: _isAvailable == true ? p.onlineGreen : p.dangerRed,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isEditMode) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.amberPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      onPressed: (_isAvailable == true && !_isSaving)
                          ? () async {
                              setState(() => _isSaving = true);
                              final clean = _usernameCtrl.text.trim().replaceAll('@', '');
                              await SupabaseService.instance.updateMyUsername(clean);
                              if (!mounted) return;
                              Navigator.of(context).pop(clean);
                            }
                          : null,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(JuzzioAppController.instance.trEn('Kaydet', 'Save', 'Speichern'), style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
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

// -----------------------------------------------------------------------------
// 1D. HESABIMI SİL SAYFASI (Kırmızı Uyarı Başlığı + 2x Şifre Doğrulama + Son Onay + DB Silme)
// -----------------------------------------------------------------------------
class JuzzioDeleteAccountPage extends StatefulWidget {
  const JuzzioDeleteAccountPage({super.key});

  @override
  State<JuzzioDeleteAccountPage> createState() => _JuzzioDeleteAccountPageState();
}

class _JuzzioDeleteAccountPageState extends State<JuzzioDeleteAccountPage> {
  final TextEditingController _pass1Ctrl = TextEditingController();
  final TextEditingController _pass2Ctrl = TextEditingController();
  bool _isDeleting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _pass1Ctrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _initiateAccountDeletion(JuzzioPalette p) async {
    final p1 = _pass1Ctrl.text;
    final p2 = _pass2Ctrl.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _errorMsg = _l3('Lütfen şifrenizi her iki alana da eksiksiz girin.', 'Please enter your password in both fields.', 'Bitte gib dein Passwort in beide Felder ein.'));
      return;
    }
    if (p1 != p2) {
      setState(() => _errorMsg = _l3('Girdiğiniz iki şifre birbiriyle eşleşmiyor.', 'The two passwords do not match.', 'Die beiden Passwörter stimmen nicht überein.'));
      return;
    }

    setState(() => _errorMsg = null);

    // "Hesabınızı silmeyi onaylıyor musunuz" Onay Ekranı / Diyaloğu
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: p.dangerRed, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _l3('Hesabınızı silmeyi onaylıyor musunuz?', 'Do you confirm deleting your account?', 'Möchtest du dein Konto wirklich löschen?'),
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          _l3('Bu işlem geri alınamaz. Hesabınız, mesaj geçmişiniz, oluşturduğunuz gruplar ve kanallar veritabanından kalıcı olarak silinecektir.', 'This cannot be undone. Your account, message history, and the groups and channels you created will be permanently deleted from the database.', 'Dies kann nicht rückgängig gemacht werden. Dein Konto, dein Nachrichtenverlauf sowie von dir erstellte Gruppen und Kanäle werden dauerhaft aus der Datenbank gelöscht.'),
          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(JuzzioAppController.instance.loc('İptal', 'Cancel', 'Abbrechen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(JuzzioAppController.instance.loc('Onaylıyorum', 'I Confirm', 'Ich bestätige'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await SupabaseService.instance.deleteMyAccountCompletely(password: p1);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const JuzzioRootFlow()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMsg = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(JuzzioAppController.instance.loc('Hesabımı Sil', 'Delete My Account', 'Mein Konto löschen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.dangerRed.withOpacity(0.5), width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: p.dangerRed, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        JuzzioAppController.instance.loc('Bu hesabı silerseniz:', 'If you delete this account:', 'Wenn du dieses Konto löschst:'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _dangerBullet(p, _l3('Bu hesabı silerseniz hesap hem JUZZIO hem de tüm cihazlarınızdan silinir.', 'If you delete this account, it will be removed from JUZZIO and all your devices.', 'Wenn du dieses Konto löschst, wird es aus JUZZIO und von all deinen Geräten entfernt.')),
                _dangerBullet(p, _l3('Sohbet geçmişiniz silinecek.', 'Your chat history will be deleted.', 'Dein Chatverlauf wird gelöscht.')),
                _dangerBullet(p, _l3('Üyesi olduğunuz tüm JUZZIO gruplarından çıkarılırsınız.', 'You will be removed from all JUZZIO groups you belong to.', 'Du wirst aus allen JUZZIO-Gruppen entfernt, in denen du Mitglied bist.')),
                _dangerBullet(p, _l3('Oluşturduğunuz tüm grup ve tüm kanallar silinir.', 'All groups and channels you created will be deleted.', 'Alle von dir erstellten Gruppen und Kanäle werden gelöscht.')),
                const Divider(height: 28),
                Text(
                  _l3('Onaylamak için şifrenizi iki kez girin:', 'Enter your password twice to confirm:', 'Gib zur Bestätigung zweimal dein Passwort ein:'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass1Ctrl,
                  obscureText: true,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                  decoration: InputDecoration(
                    labelText: JuzzioAppController.instance.trEn('Şifreniz (1. Kez)', 'Your password (1st time)', 'Dein Passwort (1. Mal)'),
                    labelStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass2Ctrl,
                  obscureText: true,
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                  decoration: InputDecoration(
                    labelText: JuzzioAppController.instance.trEn('Şifrenizi Doğrulayın (2. Kez)', 'Confirm your password (2nd time)', 'Bestätige dein Passwort (2. Mal)'),
                    labelStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary),
                    filled: true,
                    fillColor: p.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMsg!,
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.dangerRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _isDeleting ? null : () => _initiateAccountDeletion(p),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: Text(
                      JuzzioAppController.instance.loc('Hesabımı Sil', 'Delete My Account', 'Mein Konto löschen'),
                      style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerBullet(JuzzioPalette p, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w900, fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 2. GİZLİLİK SAYFASI VE TÜM ALT SAYFALARI
// =============================================================================
class JuzzioPrivacySettingsPage extends StatelessWidget {
  const JuzzioPrivacySettingsPage({super.key});

  String _privacyLabel(String code) {
    if (code == 'nobody') return _l3('Hiç kimse', 'Nobody', 'Niemand');
    if (code == 'contacts' || code == 'friends') return _l3('Kişilerim', 'My contacts', 'Meine Kontakte');
    return _l3('Herkes', 'Everyone', 'Alle');
  }

  String _timerLabel(String code) {
    if (code == '90d') return _l3('90 gün', '90 days', '90 Tage');
    if (code == '7d') return _l3('7 gün', '7 days', '7 Tage');
    if (code == '24h') return _l3('24 saat', '24 hours', '24 Stunden');
    return _l3('Kapalı', 'Off', 'Aus');
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Gizlilik', 'Privacy', 'Datenschutz'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
            children: [
              // BÖLÜM 1: Kişisel bilgilerimi kimler görebilir
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Kişisel bilgilerimi kimler görebilir', 'Who can see my personal info', 'Wer meine persönlichen Infos sehen kann'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Son görülme ve çevrim içi', 'Last seen and online', 'Zuletzt online & Status'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_privacyLabel(appCtrl.lastSeenPrivacy)}, ${appCtrl.onlinePrivacy == "everyone" ? "Herkes" : "Son görülme ile aynı"}',
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioLastSeenOnlinePrivacyPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Profil resmi', 'Profile photo', 'Profilbild'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _privacyLabel(appCtrl.profilePhotoPrivacy),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => JuzzioSingleChoicePrivacyPage(
                            pageTitle: _l3('Profil resmi', 'Profile photo', 'Profilbild'),
                            questionTitle: _l3('Profil resmimi kimler görebilir?', 'Who can see my profile photo?', 'Wer kann mein Profilbild sehen?'),
                            currentValue: appCtrl.profilePhotoPrivacy,
                            onChanged: appCtrl.setProfilePhotoPrivacy,
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Hakkında', 'About (Bio)', 'Info (Biografie)'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _privacyLabel(appCtrl.aboutPrivacy),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => JuzzioSingleChoicePrivacyPage(
                            pageTitle: _l3('Hakkında', 'About', 'Info'),
                            questionTitle: _l3('Hakkında (biyografi) bilgilerimi kimler görebilir?', 'Who can see my About (bio)?', 'Wer kann meine Info (Bio) sehen?'),
                            currentValue: appCtrl.aboutPrivacy,
                            onChanged: appCtrl.setAboutPrivacy,
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Durum', 'Status', 'Status'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _privacyLabel(appCtrl.statusPrivacy),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => JuzzioSingleChoicePrivacyPage(
                            pageTitle: _l3('Durum', 'Status', 'Status'),
                            questionTitle: _l3('24 saatlik durum güncellemelerimi kimler görebilir?', 'Who can see my 24-hour status updates?', 'Wer kann meine 24-Stunden-Status-Updates sehen?'),
                            currentValue: appCtrl.statusPrivacy,
                            onChanged: appCtrl.setStatusPrivacy,
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: const Icon(Icons.stars_rounded, color: Color(0xFF34C759)),
                      title: Text(
                        _l3('Yakın arkadaşlar', 'Close friends', 'Enge Freunde'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _l3('Hikâyelerini yalnızca seçtiğin favori arkadaşlarınla paylaş', 'Share stories only with chosen favourites', 'Storys nur mit Favoriten teilen'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => JuzzioCloseFriendsPage.open(context),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Okundu Bilgisi', 'Read Receipts', 'Lesebestätigungen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Bu özelliği devre dışı bırakırsanız okundu bilgisi gönderemez veya alamazsınız. Grup sohbetleri için okundu bilgisi her zaman gönderilir.', 'If turned off, you will not send or receive read receipts. Read receipts are always sent for group chats.', 'Wenn deaktiviert, sendest und empfängst du keine Lesebestätigungen. In Gruppenchats werden Lesebestätigungen immer gesendet.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.readReceiptsEnabled,
                      onChanged: appCtrl.setReadReceiptsEnabled,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // BÖLÜM 2: Süreli mesajlar
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Süreli mesajlar', 'Disappearing messages', 'Selbstlöschende Nachrichten'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: ListTile(
                  title: Text(
                    _l3('Varsayılan mesaj süresi', 'Default message timer', 'Standard-Nachrichtentimer'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _l3('Yeni grupları ve sohbetleri ayarladığınız süre dolduğunda kaybolacak süreli mesajlarla başlatın (${_timerLabel(appCtrl.defaultMessageTimer)})', 'Start new groups and chats with disappearing messages that vanish after the set time (${_timerLabel(appCtrl.defaultMessageTimer)})', 'Neue Gruppen und Chats mit Nachrichten starten, die nach der eingestellten Zeit verschwinden (${_timerLabel(appCtrl.defaultMessageTimer)})'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JuzzioDefaultMessageTimerPage()),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // BÖLÜM 3: Gruplar, Aramalar, Kişiler ve Kamera
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Gruplar, Aramalar, Kişiler ve Kamera', 'Groups, Calls, Contacts & Camera', 'Gruppen, Anrufe, Kontakte & Kamera'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Gruplar (Beni gruba kimler ekleyebilir)', 'Groups (Who can add me to groups)', 'Gruppen (Wer mich zu Gruppen hinzufügen kann)'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        appCtrl.whoCanAddMeToGroups == 'nobody'
                            ? _l3('Hiç kimse (Yalnızca mesaj olarak davet bağlantısı gönderilebilir)', 'Nobody (only an invite link can be sent as a message)', 'Niemand (nur ein Einladungslink kann als Nachricht gesendet werden)')
                            : (appCtrl.whoCanAddMeToGroups == 'friends' ? _l3('Arkadaşlarım', 'My friends', 'Meine Freunde') : _l3('Herkes', 'Everyone', 'Alle')),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioGroupsPrivacyPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Aramalar: Bilinmeyen kullanıcıları sessize al', 'Calls: Silence unknown callers', 'Anrufe: Unbekannte Anrufer stummschalten'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Kişilerinizde olmayan numaralardan ve hesaplardan gelen aramaları sessize alır.', 'Silences calls from unknown accounts not in your contacts.', 'Schaltet Anrufe von unbekannten Konten, die nicht in deinen Kontakten sind, stumm.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.silenceUnknownCallers,
                      onChanged: appCtrl.setSilenceUnknownCallers,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Kişiler ve Engellenmiş Hesaplar', 'Contacts & Blocked Accounts', 'Kontakte & blockierte Konten'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _l3('${appCtrl.blockedUsernames.length} engellenmiş hesap • Cihazlar arası QR senkronizasyonu açık', '${appCtrl.blockedUsernames.length} blocked accounts • Cross-device QR sync on', '${appCtrl.blockedUsernames.length} blockierte Konten • Geräteübergreifende QR-Synchronisierung an'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioContactsAndBlockedPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Kamera efektlerine izin ver', 'Allow camera effects', 'Kameraeffekte erlauben'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Kamerada veya görüntülü aramalarda efekt kullan', 'Use effects in camera and video calls', 'Effekte in Kamera und Videoanrufen verwenden'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.allowCameraEffects,
                      onChanged: appCtrl.setAllowCameraEffects,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Kamerada güzelleştirme uygula', 'Apply camera beauty filter', 'Kamera-Beauty-Filter anwenden'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Görüntülü aramada yüz pürüzsüzleştirme, sivilce izi yumuşatma ve daha temiz/net görüntü aktarımını otomatik uygular (Varsayılan: Açık).', 'Automatically applies face smoothing, blemish softening, and clearer video quality during video calls (Default: On).', 'Glättet bei Videoanrufen automatisch die Haut, mildert Unreinheiten und sorgt für ein klareres Bild (Standard: An).'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.cameraBeautyEnabled,
                      onChanged: appCtrl.setCameraBeautyEnabled,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // BÖLÜM 4: İzin Yöneticisi & Gelişmiş Gizlilik
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.verified_user_outlined, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('İzin Yöneticisi (Kamera, Mikrofon, Konum)', 'Permissions Manager (Camera, Mic, Location)', 'Berechtigungen (Kamera, Mikrofon, Standort)'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Bildirim, kamera, mikrofon, galeri ve konum izinlerini yönetin', 'Manage notifications, camera, mic, gallery & location permissions', 'Berechtigungen für Benachrichtigungen, Kamera, Mikrofon, Galerie & Standort verwalten'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioPermissionsCenterPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.shield_outlined, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Gelişmiş & Katı Hesap Koruması', 'Advanced & Strict Account Protection', 'Erweiterter & strenger Kontoschutz'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Bilinmeyen mesaj engelleme, IP koruma, bağlantı önizlemeleri ve Katı hesap ayarları', 'Block unknown messages, protect IP in calls, link previews & Strict account settings', 'Unbekannte Nachrichten blockieren, IP in Anrufen schützen, Linkvorschauen & strenge Kontoeinstellungen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioAdvancedPrivacyPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2A. SON GÖRÜLME VE ÇEVRİM İÇİ GİZLİLİK SAYFASI
// -----------------------------------------------------------------------------
class JuzzioLastSeenOnlinePrivacyPage extends StatelessWidget {
  const JuzzioLastSeenOnlinePrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Son görülme ve çevrim içi', 'Last seen and online', 'Zuletzt online & Status'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      JuzzioAppController.instance.loc('Son görülme bilgimi kimler görebilir?', 'Who can see my last seen?', 'Wer kann meinen Zuletzt-online-Status sehen?'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _radioItem(p, _l3('Herkes', 'Everyone', 'Alle'), 'everyone', appCtrl.lastSeenPrivacy, appCtrl.setLastSeenPrivacy),
                    _radioItem(p, _l3('Kişilerim', 'My contacts', 'Meine Kontakte'), 'contacts', appCtrl.lastSeenPrivacy, appCtrl.setLastSeenPrivacy),
                    _radioItem(p, _l3('Hiç kimse', 'Nobody', 'Niemand'), 'nobody', appCtrl.lastSeenPrivacy, appCtrl.setLastSeenPrivacy),
                    const Divider(height: 24),
                    Text(
                      JuzzioAppController.instance.loc('Çevrimiçi olduğumu kimler görebilir?', 'Who can see when I am online?', 'Wer kann sehen, wann ich online bin?'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _radioItem(p, _l3('Herkes', 'Everyone', 'Alle'), 'everyone', appCtrl.onlinePrivacy, appCtrl.setOnlinePrivacy),
                    _radioItem(
                      p,
                      _l3('Son görülme bilgisi ile aynı', 'Same as last seen', 'Wie „Zuletzt online“'),
                      'same_as_last_seen',
                      appCtrl.onlinePrivacy,
                      appCtrl.setOnlinePrivacy,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      JuzzioAppController.instance.loc('Son görülme veya çevrim içi bilginizi paylaşmazsanız diğer kullanıcıların son görülme ve çevrim içi bilgisini de göremezsiniz.', 'If you do not share your last seen or online status, you will not be able to see other users last seen or online status.', 'Wenn du deinen Zuletzt-online- oder Online-Status nicht teilst, kannst du diesen Status bei anderen auch nicht sehen.'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _radioItem(
    JuzzioPalette p,
    String title,
    String value,
    String groupValue,
    ValueChanged<String> onChanged,
  ) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      activeColor: p.amberGlow,
      title: Text(title, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
      value: value,
      groupValue: groupValue,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2B. PROFİL RESMİ / HAKKINDA / DURUM SEÇİM SAYFASI
// -----------------------------------------------------------------------------
class JuzzioSingleChoicePrivacyPage extends StatelessWidget {
  final String pageTitle;
  final String questionTitle;
  final String currentValue;
  final ValueChanged<String> onChanged;

  const JuzzioSingleChoicePrivacyPage({
    super.key,
    required this.pageTitle,
    required this.questionTitle,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(pageTitle, style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    questionTitle,
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                  const SizedBox(height: 10),
                  for (final entry in [
                    MapEntry('everyone', _l3('Herkes', 'Everyone', 'Alle')),
                    MapEntry('contacts', _l3('Kişilerim', 'My contacts', 'Meine Kontakte')),
                    MapEntry('nobody', _l3('Hiç kimse', 'Nobody', 'Niemand')),
                  ])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      activeColor: p.amberGlow,
                      title: Text(
                        entry.value,
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: entry.key,
                      groupValue: currentValue,
                      onChanged: (v) {
                        if (v != null) onChanged(v);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2C. VARSAYILAN MESAJ SÜRESİ SAYFASI (Kapalı, 90 gün, 7 gün, 24 saat)
// -----------------------------------------------------------------------------
class JuzzioDefaultMessageTimerPage extends StatelessWidget {
  const JuzzioDefaultMessageTimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Varsayılan mesaj süresi', 'Default message timer', 'Standard-Nachrichtentimer'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _l3('Yeni sohbetlere şu süreli mesaj süresi ayarı ile başlayın:', 'Start new chats with this message timer:', 'Neue Chats mit diesem Nachrichtentimer starten:'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                  const SizedBox(height: 10),
                  for (final item in [
                    MapEntry('24h', _l3('24 saat', '24 hours', '24 Stunden')),
                    MapEntry('7d', _l3('7 gün', '7 days', '7 Tage')),
                    MapEntry('90d', _l3('90 gün', '90 days', '90 Tage')),
                    MapEntry('off', _l3('Kapalı', 'Off', 'Aus')),
                  ])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      activeColor: p.amberGlow,
                      title: Text(item.value, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
                      value: item.key,
                      groupValue: appCtrl.defaultMessageTimer,
                      onChanged: (v) {
                        if (v != null) appCtrl.setDefaultMessageTimer(v);
                      },
                    ),
                  const Divider(height: 20),
                  Text(
                    _l3('Bu özellik açıldığında tüm yeni bireysel sohbetler seçtiğiniz süre dolduğunda kaybolacak süreli mesajlarla başlatılır. Mevcut sohbetleriniz bu ayardan etkilenmez.', 'When enabled, all new one-to-one chats start with messages that disappear after the selected time. Your existing chats are not affected.', 'Wenn aktiviert, starten alle neuen Einzelchats mit Nachrichten, die nach der gewählten Zeit verschwinden. Bestehende Chats sind nicht betroffen.'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2D. GRUPLAR GİZLİLİĞİ SAYFASI (Beni gruba kimler ekleyebilir: Herkes, Arkadaşlarım, Hiç kimse)
// -----------------------------------------------------------------------------
class JuzzioGroupsPrivacyPage extends StatelessWidget {
  const JuzzioGroupsPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.trEn('Gruplar', 'Groups', 'Gruppen'), style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _l3('Beni gruba kimler ekleyebilir?', 'Who can add me to groups?', 'Wer kann mich zu Gruppen hinzufügen?'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                  const SizedBox(height: 10),
                  for (final item in [
                    MapEntry('everyone', _l3('Herkes', 'Everyone', 'Alle')),
                    MapEntry('friends', _l3('Arkadaşlarım', 'My friends', 'Meine Freunde')),
                    MapEntry('nobody', _l3('Hiç kimse (Yalnızca özel davet bağlantısı gönderilebilir)', 'Nobody (only a private invite link can be sent)', 'Niemand (nur ein privater Einladungslink kann gesendet werden)')),
                  ])
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      activeColor: p.amberGlow,
                      title: Text(item.value, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
                      value: item.key,
                      groupValue: appCtrl.whoCanAddMeToGroups,
                      onChanged: (v) {
                        if (v != null) appCtrl.setWhoCanAddMeToGroups(v);
                      },
                    ),
                  const Divider(height: 20),
                  Text(
                    _l3('Hiç kimse seçeneğini seçtiğinizde, sizi gruba eklemek isteyen yönetici yalnızca mesaj olarak grup davet bağlantısını gönderebilir. Bağlantıya tıkladığınızda kendi isteğiniz ile gruba katılım sağlayabilirsiniz.', 'If you choose Nobody, an admin who wants to add you can only send you the group invite link as a message. You can join the group yourself by tapping the link.', 'Wenn du „Niemand“ wählst, kann ein Admin dir nur den Gruppen-Einladungslink als Nachricht senden. Über den Link kannst du der Gruppe selbst beitreten.'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2E. KİŞİLER VE ENGELLENMİŞ HESAPLAR (WhatsApp / Windows QR Senkronizasyon)
// -----------------------------------------------------------------------------
class JuzzioContactsAndBlockedPage extends StatefulWidget {
  const JuzzioContactsAndBlockedPage({super.key});

  @override
  State<JuzzioContactsAndBlockedPage> createState() => _JuzzioContactsAndBlockedPageState();
}

class _JuzzioContactsAndBlockedPageState extends State<JuzzioContactsAndBlockedPage> {
  final TextEditingController _blockCtrl = TextEditingController();
  List<JuzzioBlockedUserItem> _dbBlocked = <JuzzioBlockedUserItem>[];

  @override
  void initState() {
    super.initState();
    _loadDbBlocked();
  }

  Future<void> _loadDbBlocked() async {
    try {
      final list = await JuzzioSocialService.instance.fetchBlockedUsers();
      if (!mounted) return;
      setState(() => _dbBlocked = list);
      for (final b in list) {
        if (b.blockedUsername.isNotEmpty) {
          JuzzioAppController.instance.blockUsername(b.blockedUsername);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _blockCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        final blocked = appCtrl.blockedUsernames;

        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Kişiler', 'Contacts', 'Kontakte'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('WhatsApp / Juzzio Kişileri', 'WhatsApp / Juzzio Contacts Sync', 'WhatsApp-/Juzzio-Kontaktsynchronisation'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Kişiler, cihazlar genelinde yönetebilmeniz için hesabınıza kaydedilir. Windows / Masaüstü uygulamasında QR kodunuzu okuttuğunuzda engellenen kişiler dahil tüm listeniz senkronize gelir.', 'Contacts and blocked accounts are saved to your account so they stay synced across all devices including Windows / Desktop via QR code.', 'Kontakte und blockierte Konten werden in deinem Konto gespeichert und bleiben auf allen Geräten synchron – auch unter Windows / Desktop per QR-Code.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                      value: appCtrl.syncContactsAcrossDevices,
                      onChanged: appCtrl.setSyncContactsAcrossDevices,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l3('Engellenmiş Hesaplar (${blocked.length})', 'Blocked Accounts (${blocked.length})', 'Blockierte Konten (${blocked.length})'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _blockCtrl,
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary),
                            decoration: InputDecoration(
                              hintText: JuzzioAppController.instance.trEn('Engellenecek @kullaniciadi', '@username to block', 'Zu blockierender @benutzername'),
                              hintStyle: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted),
                              filled: true,
                              fillColor: p.inputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: p.dangerRed,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (_blockCtrl.text.trim().isNotEmpty) {
                              appCtrl.blockUsername(_blockCtrl.text.trim());
                              _blockCtrl.clear();
                            }
                          },
                          child: Text(JuzzioAppController.instance.loc('Engelle', 'Block', 'Blockieren')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...blocked.map(
                      (uname) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: p.dangerRed.withOpacity(0.2),
                          child: Icon(Icons.block_rounded, color: p.dangerRed, size: 18),
                        ),
                        title: Text(
                          '@$uname',
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            appCtrl.unblockUsername(uname);
                            for (final b in _dbBlocked) {
                              if (b.blockedUsername.toLowerCase() == uname.toLowerCase()) {
                                try {
                                  await JuzzioSocialService.instance.unblockUser(b.blockedId);
                                } catch (_) {}
                              }
                            }
                            _loadDbBlocked();
                          },
                          child: Text(
                            _l3('Engeli Kaldır', 'Unblock', 'Blockierung aufheben'),
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.onlineGreen, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 2F. GİZLİLİK -> GELİŞMİŞ SAYFASI & KATI HESAP AYARLARI SİHİRBAZI
// -----------------------------------------------------------------------------
class JuzzioAdvancedPrivacyPage extends StatelessWidget {
  const JuzzioAdvancedPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Gelişmiş', 'Advanced', 'Erweitert'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Bilinmeyen hesaplardan gelen mesajları engelle', 'Block messages from unknown accounts', 'Nachrichten von unbekannten Konten blockieren'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Juzzio hesabınızı korumak ve cihazınızın performansını iyileştirmek için bilinmeyen hesaplardan belirli bir hacmin üzerine gelen mesajları engeller.', 'To protect your Juzzio account and device performance, blocks high-volume messages from unknown accounts.', 'Zum Schutz deines Juzzio-Kontos und der Geräteleistung werden massenhafte Nachrichten von unbekannten Konten blockiert.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.blockUnknownVolumeMessages,
                      onChanged: appCtrl.setBlockUnknownVolumeMessages,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Aramalarda IP adresini koru', 'Protect IP address in calls', 'IP-Adresse in Anrufen schützen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Konumunuzun başka kişiler tarafından tahmin edilmesini zorlaştırmak amacıyla bu cihazdan yapılan aramalar sunucuları üzerinden güvenli bir şekilde aktarılır. Bu işlem arama kalitesini düşürür.', 'To make it harder for others to infer your location, calls on this device are securely relayed through Juzzio servers. This reduces call quality.', 'Damit andere deinen Standort schwerer ermitteln können, werden Anrufe auf diesem Gerät sicher über Juzzio-Server geleitet. Dadurch sinkt die Anrufqualität.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.protectIpInCalls,
                      onChanged: appCtrl.setProtectIpInCalls,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Bağlantı önizlemelerini devre dışı bırak', 'Disable link previews', 'Linkvorschauen deaktivieren'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('IP adresinizi üçüncü taraf web siteleri tarafından anlaşılmaya karşı korumaya yardımcı olmak için bundan böyle sohbetlerde paylaştığınız bağlantıların önizlemelerini oluşturmayacağız.', 'To help protect your IP address from being inferred by third-party websites, previews will no longer be generated for links shared in chats.', 'Um deine IP-Adresse vor Drittanbieter-Websites zu schützen, werden für in Chats geteilte Links keine Vorschauen mehr erstellt.'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.disableLinkPreviews,
                      onChanged: appCtrl.setDisableLinkPreviews,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _l3('Katı hesap ayarları', 'Strict account settings', 'Strenge Kontoeinstellungen'),
                              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: appCtrl.strictAccountSettings
                                  ? p.onlineGreen.withOpacity(0.18)
                                  : p.inputBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              appCtrl.strictAccountSettings ? _l3('Açık', 'On', 'An') : _l3('Kapalı', 'Off', 'Aus'),
                              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: appCtrl.strictAccountSettings ? p.onlineGreen : p.textSecondary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _l3('Hedefli siber saldırı riski altında olma ihtimaliniz yüksekse hesabınızı korumaya yardımcı olmak için belirli ayarlar kilitlenir. Çoğu kullanıcının bu düzeyde bir korumaya ihtiyacı yoktur. Bu ayar mesajlaşma deneyiminizin ve aramalarınızın kalitesini düşürür.', 'If you are likely to be targeted by cyber attacks, certain settings are locked to help protect your account. Most users do not need this level of protection. This setting reduces the quality of your messaging and calls.', 'Wenn du wahrscheinlich Ziel von Cyberangriffen bist, werden bestimmte Einstellungen gesperrt, um dein Konto zu schützen. Die meisten Nutzer brauchen diesen Schutz nicht. Diese Einstellung verringert die Qualität von Nachrichten und Anrufen.'),
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioStrictAccountSettingsPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class JuzzioStrictAccountSettingsPage extends StatefulWidget {
  const JuzzioStrictAccountSettingsPage({super.key});

  @override
  State<JuzzioStrictAccountSettingsPage> createState() => _JuzzioStrictAccountSettingsPageState();
}

class _JuzzioStrictAccountSettingsPageState extends State<JuzzioStrictAccountSettingsPage> {
  // 0 = İlk tanıtım sayfası (Kilit + Onay tiki), 1 = İleri uyarı sayfası (Ünlem + İptal / Devam Et)
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);

    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(JuzzioAppController.instance.loc('Katı hesap ayarları', 'Strict account settings', 'Strenge Kontoeinstellungen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _step == 0 ? _buildStep1(context, p, appCtrl) : _buildStep2(context, p, appCtrl),
      ),
    );
  }

  Widget _buildStep1(BuildContext context, JuzzioPalette p, JuzzioAppController appCtrl) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Üst Kilit Simgesi + Yanında Onay Tiki
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: p.amberButtonGradient,
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 42),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: p.onlineGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bgPrimary, width: 2.5),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _l3('Bu çok yüksek koruma sağlayan bir ayardır ve yalnızca siber saldırı riskinin altında olduğunuzu düşünüyorsanız kullanılmalıdır.', 'This is a very high-protection setting and should only be used if you believe you are at risk of cyber attacks.', 'Dies ist eine Einstellung mit sehr hohem Schutz und sollte nur genutzt werden, wenn du glaubst, durch Cyberangriffe gefährdet zu sein.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),

          // 1. Sol tarafında engelleme butonu
          _strictItemRow(
            p: p,
            leading: Icon(Icons.block_rounded, color: p.dangerRed, size: 26),
            text: _l3('Bilinmeyen gönderenlerden gelen medya veya ek dosyalar engellenecek.', 'Media and attachments from unknown senders will be blocked.', 'Medien und Anhänge von unbekannten Absendern werden blockiert.'),
          ),
          const SizedBox(height: 14),

          // 2. Kalkan logolu + içinde onaylama tiki
          _strictItemRow(
            p: p,
            leading: Icon(Icons.verified_user_rounded, color: p.onlineGreen, size: 26),
            text: _l3('Sizi arayabilecek veya sizi gruplara ekleyebilecek kişileri sınırlamak için gizlilik ayarları güncellenir.', 'Privacy settings are updated to limit who can call you or add you to groups.', 'Die Datenschutzeinstellungen werden aktualisiert, um einzuschränken, wer dich anrufen oder zu Gruppen hinzufügen kann.'),
          ),
          const SizedBox(height: 14),

          // 3. Kilit simgesi + içerisinde onay tiki
          _strictItemRow(
            p: p,
            leading: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Icon(Icons.lock_rounded, color: p.amberGlow, size: 26),
                Icon(Icons.check_circle_rounded, color: p.onlineGreen, size: 13),
              ],
            ),
            text: _l3('Açıldığında bazı ayarlar kilitlenir. Katı hesap ayarlarını dilediğiniz zaman kapatabilirsiniz.', 'When enabled, some settings are locked. You can turn strict account settings off at any time.', 'Wenn aktiviert, werden einige Einstellungen gesperrt. Du kannst die strengen Kontoeinstellungen jederzeit ausschalten.'),
          ),

          const Spacer(),
          Text(
            _l3('Bu ayar arama kalitesini düşürür.', 'This setting reduces call quality.', 'Diese Einstellung verringert die Anrufqualität.'),
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          if (appCtrl.strictAccountSettings)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.dangerRed,
                  side: BorderSide(color: p.dangerRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () {
                  appCtrl.setStrictAccountSettings(false);
                  Navigator.of(context).pop();
                },
                child: Text(JuzzioAppController.instance.loc('Katı Hesap Ayarlarını Kapat', 'Turn Off Strict Account Settings', 'Strenge Kontoeinstellungen deaktivieren'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.amberPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () => setState(() => _step = 1),
                child: Text(JuzzioAppController.instance.loc('İleri', 'Next', 'Weiter'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep2(BuildContext context, JuzzioPalette p, JuzzioAppController appCtrl) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.amberGlow),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: p.amberPrimary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: p.amberGlow, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            _l3('Bu ayar sizinle iletişime geçmeyi sınırlandırabilir', 'This setting may limit how people can contact you', 'Diese Einstellung kann einschränken, wie andere dich kontaktieren können'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _l3('Katı hesap ayarları yeni arama ve mesaj gönderen kişilerin size mesaj göndermesini ve arama yapmasını zorlaştırabilir.', 'Strict account settings can make it harder for new people to message or call you.', 'Strenge Kontoeinstellungen können es neuen Personen erschweren, dir zu schreiben oder dich anzurufen.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.textPrimary,
                      side: BorderSide(color: p.glassBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(JuzzioAppController.instance.loc('İptal', 'Cancel', 'Abbrechen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.amberPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () {
                      appCtrl.setStrictAccountSettings(true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: p.onlineGreen,
                          content: Text(JuzzioAppController.instance.trEn('🛡️ Katı hesap modu açıldı: bilinmeyen kişilerin aramaları susturulur, mesaj istekleri sınırlanır, gruplara yalnızca arkadaşların ekleyebilir.', '🛡️ Strict mode on: unknown callers are silenced, message requests limited, only friends can add you to groups.', '🛡️ Strenger Modus an: Unbekannte Anrufer stumm, Anfragen begrenzt, nur Freunde fügen dich zu Gruppen hinzu.')),
                        ),
                      );
                      Navigator.of(context).pop();
                    },
                    child: Text(JuzzioAppController.instance.loc('Devam Et', 'Continue', 'Fortfahren'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _strictItemRow({
    required JuzzioPalette p,
    required Widget leading,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.inputBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: leading,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary,
              fontSize: 13.5,
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 3. SOHBETLER AYAR SAYFASI (Görüntüleme, 10 Sohbet Teması, Yedekleme, Aktarma, Geçmiş)
// =============================================================================
class JuzzioChatsSettingsPage extends StatelessWidget {
  const JuzzioChatsSettingsPage({super.key});


  String _fontSizeText(String code) {
    if (code == 'small') return _l3('Küçük', 'Small', 'Klein');
    if (code == 'large') return _l3('Büyük', 'Large', 'Groß');
    return _l3('Orta', 'Medium', 'Mittel');
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        final chatThemeName = appCtrl.chatPalette?.label(appCtrl.uiLang) ?? appCtrl.currentChatTheme.localizedName;
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Sohbetler', 'Chats', 'Chats'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
            children: [
              // GÖRÜNTÜLEME
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Görüntüleme', 'Display', 'Anzeige'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    // v0.7.0: modern üçlü tema seçici (Gündüz · Gece · Sistem)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: JuzzioThemeModeSelector(),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    // v0.8.3: yöneticinin yayınladığı Juzzio teması (isteğe bağlı)
                    if (appCtrl.globalTheme != null) ...[
                      SwitchListTile(
                        value: appCtrl.followGlobalTheme && appCtrl.activeCustomTheme == null,
                        onChanged: appCtrl.setFollowGlobalTheme,
                        secondary: Icon(Icons.public_rounded, color: p.amberGlow),
                        title: Text(
                          appCtrl.trEn('Juzzio\'nun önerdiği tema', 'Juzzio recommended theme', 'Empfohlenes Design'),
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${appCtrl.globalTheme!.name} · v${appCtrl.globalThemeVersion}',
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                        ),
                      ),
                      Divider(height: 1, color: p.glassBorder),
                    ],
                    // v0.8.1 tema motoru: cam yoğunluğu (güvenli 0.6–1.4 aralığı) + varsayılana dön
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(children: [
                        Icon(Icons.blur_linear_rounded, color: p.textPrimary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            appCtrl.trEn('Cam yoğunluğu', 'Glass intensity', 'Glasintensität'),
                            style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text('${(appCtrl.glassIntensity * 100).round()}%',
                            style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w800)),
                        IconButton(
                          tooltip: appCtrl.trEn('Varsayılana dön', 'Reset to default', 'Zurücksetzen'),
                          icon: Icon(Icons.restart_alt_rounded, color: p.textSecondary),
                          onPressed: appCtrl.glassIntensity == 1.0 ? null : () => appCtrl.setGlassIntensity(1.0),
                        ),
                      ]),
                    ),
                    Slider(
                      value: appCtrl.glassIntensity,
                      min: 0.6,
                      max: 1.4,
                      divisions: 8,
                      label: appCtrl.glassIntensity < 0.9
                          ? appCtrl.trEn('Sade', 'Subtle', 'Dezent')
                          : (appCtrl.glassIntensity > 1.1 ? appCtrl.trEn('Belirgin', 'Prominent', 'Ausgeprägt') : appCtrl.trEn('Standart', 'Standard', 'Standard')),
                      onChanged: (v) => appCtrl.setGlassIntensity(v, persist: false),
                      onChangeEnd: (v) => appCtrl.setGlassIntensity(v),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    // v0.8.1 şartname §16: performans modu
                    SwitchListTile(
                      value: appCtrl.reducedEffects,
                      onChanged: appCtrl.setReducedEffects,
                      secondary: Icon(Icons.bolt_rounded, color: p.textPrimary),
                      title: Text(
                        appCtrl.trEn('Performans modu', 'Performance mode', 'Leistungsmodus'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Cam bulanıklığını kapatır; pil ve akıcılık için', 'Turns off glass blur for battery and smoothness', 'Schaltet Glasunschärfe aus'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: JuzzioThemeSwatch(palette: appCtrl.glassPalette, size: 28),
                      title: Text(
                        _l3('Cam teması', 'Glass theme', 'Glas-Design'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        appCtrl.glassPalette.label(appCtrl.uiLang),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioGlassThemePage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.brush_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Tema Stüdyosu', 'Theme Studio', 'Design-Studio'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        appCtrl.activeCustomTheme != null
                            ? appCtrl.trEn('Etkin: ${appCtrl.activeCustomTheme!.name}', 'Active: ${appCtrl.activeCustomTheme!.name}', 'Aktiv')
                            : appCtrl.trEn('Kendi temanı oluştur, içe/dışa aktar', 'Create, import & export your own theme', 'Eigenes Design erstellen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => JuzzioThemeStudioPage.open(context),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [appCtrl.chatPalette?.swatchA ?? appCtrl.currentChatTheme.primaryColor, appCtrl.chatPalette?.swatchB ?? appCtrl.currentChatTheme.secondaryColor]),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                      title: Text(
                        JuzzioAppController.instance.loc('Varsayılan sohbet teması', 'Default chat theme', 'Standard-Chatdesign'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _l3('$chatThemeName • Parlaklık: ${(appCtrl.chatThemeIntensity * 100).round()}%', '$chatThemeName • Brightness: ${(appCtrl.chatThemeIntensity * 100).round()}%', '$chatThemeName • Helligkeit: ${(appCtrl.chatThemeIntensity * 100).round()}%'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatThemeCustomizerPage()),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // v0.8.4 TEMA GALERİSİ: tüm uygulama ve sohbet temaları
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Uygulama arayüz teması', 'App interface theme', 'App-Oberflächendesign'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: JuzzioAppThemeGallery(),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Sohbet teması', 'Chat theme', 'Chatdesign'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: JuzzioChatThemeGallery(),
                ),
              ),

              const SizedBox(height: 20),

              // SOHBET AYARLARI
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Sohbet ayarları', 'Chat settings', 'Chat-Einstellungen'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Enter tuşu mesajı gönderir', 'Enter is send', 'Enter zum Senden'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Enter tuşuna basıldığında mesajınız gönderilir', 'Enter key will send your message', 'Die Enter-Taste sendet deine Nachricht'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.enterSendsMessage,
                      onChanged: appCtrl.setEnterSendsMessage,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        _l3('Çift dokunuş tepkisi', 'Double-tap reaction', 'Doppeltipp-Reaktion'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _l3('Mesaja iki kez dokununca bu tepki bırakılır', 'Double-tap a message to leave this reaction',
                            'Doppeltippe auf eine Nachricht, um so zu reagieren'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in const ['❤️‍🔥', '🌸'])
                            GestureDetector(
                              onTap: () => appCtrl.setDoubleTapReaction(e),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: appCtrl.doubleTapReaction == e ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
                                  border: Border.all(color: appCtrl.doubleTapReaction == e ? Colors.white54 : p.glassBorder),
                                ),
                                child: Text(e, style: juzzioEmojiStyle(22)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        JuzzioAppController.instance.loc('Medya görünürlüğü', 'Media visibility', 'Mediensichtbarkeit'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Yeni indirilen medyaları cihazınızın galerisinde gösterir', 'Show newly downloaded media in your device gallery', 'Neu heruntergeladene Medien in der Galerie anzeigen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.mediaVisibility,
                      onChanged: appCtrl.setMediaVisibility,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      title: Text(
                        JuzzioAppController.instance.loc('Yazı tipi boyutu', 'Font size', 'Schriftgröße'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _fontSizeText(appCtrl.fontSizeOption),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      onTap: () => _showFontSizeDialog(context, p, appCtrl),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ARŞİVLENMİŞ SOHBETLER
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text(
                  _l3('Arşivlenmiş sohbetler', 'Archived chats', 'Archivierte Chats'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: SwitchListTile(
                  activeColor: p.amberGlow,
                  title: Text(
                    _l3('Sohbetleri arşivde tut', 'Keep chats archived', 'Chats archiviert lassen'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _l3('Arşivlenen sohbetler yeni mesaj aldığınızda arşivde kalır', 'Archived chats stay archived when you receive a new message', 'Archivierte Chats bleiben archiviert, wenn du eine neue Nachricht erhältst'),
                    style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                  ),
                  value: appCtrl.keepChatsArchived,
                  onChanged: appCtrl.setKeepChatsArchived,
                ),
              ),

              const SizedBox(height: 20),

              // YEDEKLEME, AKTARMA VE SOHBET GEÇMİŞİ
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.backup_outlined, color: p.amberGlow),
                      title: Text(
                        JuzzioAppController.instance.loc('Mesajları / Sohbetleri yedekle', 'Back up messages / chats', 'Chats sichern'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Google Drive\'a şifreli yedek al, yeni telefonda geri yükle', 'Encrypted Google Drive backup & restore', 'Verschlüsseltes Drive-Backup'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioBackupPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.phonelink_setup_rounded, color: p.amberGlow),
                      title: Text(
                        JuzzioAppController.instance.loc('Sohbetleri aktarma', 'Transfer chats', 'Chats übertragen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Sohbet geçmişinizi başka bir Android veya Windows cihaza aktarın', 'Transfer your chat history to another Android or Windows device', 'Chatverlauf auf ein anderes Android- oder Windows-Gerät übertragen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatTransferPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.history_rounded, color: p.amberGlow),
                      title: Text(
                        JuzzioAppController.instance.loc('Sohbet geçmişi', 'Chat history', 'Chatverlauf'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        JuzzioAppController.instance.loc('Dışa aktar, arşivle, içeriği temizle veya tüm sohbetleri sil', 'Export, archive, clear, or delete all chats', 'Alle Chats exportieren, archivieren, leeren oder löschen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatHistoryPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  void _showFontSizeDialog(BuildContext context, JuzzioPalette p, JuzzioAppController appCtrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(JuzzioAppController.instance.loc('Yazı tipi boyutu', 'Font size', 'Schriftgröße'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in [
              MapEntry('small', _l3('Küçük', 'Small', 'Klein')),
              MapEntry('medium', _l3('Orta', 'Medium', 'Mittel')),
              MapEntry('large', _l3('Büyük', 'Large', 'Groß')),
            ])
              RadioListTile<String>(
                activeColor: p.amberGlow,
                title: Text(item.value, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary)),
                value: item.key,
                groupValue: appCtrl.fontSizeOption,
                onChanged: (v) {
                  if (v != null) appCtrl.setFontSizeOption(v);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3A. 10 SOHBET TEMASI VE PARLAKLIK/VURGU ÖNİZLEME SAYFASI
// -----------------------------------------------------------------------------
/// Glassmorphism cam teması seçimi: her temanın canlı aurora önizlemesi
class JuzzioGlassThemePage extends StatelessWidget {
  const JuzzioGlassThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              _l3('Cam teması', 'Glass theme', 'Glas-Design'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
            ),
          ),
          body: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: kJuzzioAuroraPalettes.length,
            itemBuilder: (_, i) {
              final pal = kJuzzioAuroraPalettes[i];
              final selected = appCtrl.glassPaletteId == pal.id;
              return GestureDetector(
                // v0.8.1: dokununca önizleme açılır, "Uygula" ile seçilir
                onTap: () {
                  HapticFeedback.selectionClick();
                  JuzzioThemePreviewPage.open(context, pal.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        JuzzioAuroraBackground(palette: pal, dark: appCtrl.isDark),
                        Positioned(top: 10, right: 10, child: JuzzioThemeSwatch(palette: pal, size: 26, selected: selected)),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              JuzzioGlass(
                                radius: 18,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            pal.label(appCtrl.uiLang),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: appCtrl.isDark ? Colors.white : JuzzioColors.ink,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            juzzioCharacterText(pal),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: (appCtrl.isDark ? Colors.white : JuzzioColors.ink).withValues(alpha: 0.75),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      Icon(Icons.check_circle_rounded,
                                          size: 20, color: appCtrl.isDark ? Colors.white : JuzzioColors.ink),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class JuzzioChatThemeCustomizerPage extends StatelessWidget {
  const JuzzioChatThemeCustomizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Varsayılan sohbet teması', 'Default chat theme', 'Standard-Chatdesign'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Canlı Sohbet Önizleme Kutusu
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: JuzzioGlassTokens.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: JuzzioGlassTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l3('CANLI SOHBET ÖNİZLEMESİ', 'LIVE CHAT PREVIEW', 'LIVE-CHAT-VORSCHAU'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      // v0.8.0: önizleme balonları sohbetteki gerçek balonla birebir
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: p.incomingBubble,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20), topRight: Radius.circular(20),
                            bottomLeft: Radius.circular(6), bottomRight: Radius.circular(20)),
                          border: Border.all(color: p.glassBorder),
                        ),
                        child: Text(
                          _l3('Selam! Bu yeni tema nasıl görünüyor? ✨', 'Hey! How does this new theme look? ✨', 'Hey! Wie sieht das neue Design aus? ✨'),
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: p.outgoingBubble,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20), topRight: Radius.circular(20),
                            bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)),
                        ),
                        child: Text(
                          _l3('Harika görünüyor, renk vurgusu tam istediğim gibi! 🔥', 'Looks great, the accent color is exactly what I wanted! 🔥', 'Sieht super aus, die Akzentfarbe ist genau richtig! 🔥'),
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Parlaklık ve Vurgu Yoğunluğu Kaydırıcısı
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _l3('Tema Vurgu ve Parlaklık Yoğunluğu', 'Theme Accent & Brightness Intensity', 'Design-Akzent & Helligkeit'),
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${(appCtrl.chatThemeIntensity * 100).round()}%',
                          style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Slider(
                      value: appCtrl.chatThemeIntensity,
                      min: 0.65,
                      max: 1.35,
                      activeColor: p.amberGlow,
                      onChanged: appCtrl.setChatThemeIntensity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Text(
                _l3('${kJuzzioAuroraPalettes.length} Liquid Glass Tasarım Ailesi', '${kJuzzioAuroraPalettes.length} Liquid Glass Design Family', '${kJuzzioAuroraPalettes.length} Liquid-Glass-Designfamilie'),
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const JuzzioChatThemeGallery(),
              const SizedBox(height: 18),
              Text(
                _l3('${kJuzzioChatThemes.length} Sıvı Cam Sohbet Teması', '${kJuzzioChatThemes.length} Liquid Glass Chat Themes', '${kJuzzioChatThemes.length} Liquid-Glass-Chatdesigns'),
                style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 10),
              ...List.generate(kJuzzioChatThemes.length, (idx) {
                final preset = kJuzzioChatThemes[idx];
                final selected = appCtrl.chatPaletteId.isEmpty && appCtrl.selectedChatThemeIndex == idx;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? preset.secondaryColor : p.glassBorder,
                      width: selected ? 2.0 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    onTap: () => appCtrl.setChatTheme(idx),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [preset.primaryColor, preset.secondaryColor],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.95 : 0.5), width: selected ? 2 : 1),
                      ),
                      child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                    ),
                    trailing: Container(
                      width: 46,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(colors: [preset.primaryColor, preset.secondaryColor, preset.incomingDarkColor]),
                      ),
                    ),
                    title: Text(
                      preset.localizedName,
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 3B. SOHBET YEDEKLEMESİ, AKTARMA VE SOHBET GEÇMİŞİ SAYFALARI
// -----------------------------------------------------------------------------
/// v0.7.0 ŞEFFAFLIK: Önceki sürümlerdeki "Şimdi yedekle", "şifreli bulut yedeği" ve
/// "QR ile aktar" ekranları gerçekte işlem yapmayan göstermelik ekranlardı ve kaldırıldı.
/// Yerine verilerin gerçekte nasıl saklandığını açıklayan dürüst bir sayfa geldi.
class JuzzioChatBackupPage extends StatelessWidget {
  const JuzzioChatBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    Widget item(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: p.textPrimary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                  const SizedBox(height: 3),
                  Text(body, style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.42)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(app.trEn('Sohbet verileri ve cihaz değişikliği', 'Chat data & changing phones', 'Chatdaten & Gerätewechsel'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          JuzzioGlass(
            radius: 26,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                item(
                  Icons.cloud_rounded,
                  app.trEn('Mesajların nerede saklanır?', 'Where are messages stored?', 'Wo werden Nachrichten gespeichert?'),
                  app.trEn(
                    'Mesajlar, fotoğraflar ve sesli mesajlar Juzzio sunucusunda (Supabase) saklanır. Bu yüzden ayrıca "yedekle" demene gerek yoktur.',
                    'Messages, photos and voice notes are stored on the Juzzio server (Supabase), so there is no separate "back up" step.',
                    'Nachrichten, Fotos und Sprachnachrichten liegen auf dem Juzzio-Server (Supabase); ein separates Backup ist nicht nötig.',
                  ),
                ),
                item(
                  Icons.phone_android_rounded,
                  app.trEn('Telefon değiştirirsen', 'If you change phones', 'Beim Gerätewechsel'),
                  app.trEn(
                    'Yeni telefonda aynı hesapla giriş yapman yeterli; şifresiz mesaj geçmişi, gruplar ve medya geri gelir.',
                    'Sign in with the same account on the new phone; unencrypted history, groups and media come back.',
                    'Mit demselben Konto anmelden; unverschlüsselter Verlauf, Gruppen und Medien sind wieder da.',
                  ),
                ),
                item(
                  Icons.lock_rounded,
                  app.trEn('Uçtan uca şifreli mesajlar', 'End-to-end encrypted messages', 'Ende-zu-Ende-verschlüsselte Nachrichten'),
                  app.trEn(
                    '1\'e 1 yazılı mesajlar v0.7.0\'dan itibaren uçtan uca şifrelidir. Şifre çözme anahtarı yalnızca telefonunda durur; bu mesajlar yeni bir telefonda açılamaz ve sunucuda yedeklenemez. Bu, kimsenin (biz dahil) okuyamaması için bilinçli bir tercihtir.',
                    'Since v0.7.0, 1:1 text messages are end-to-end encrypted. The key stays only on your phone, so these messages cannot be opened on a new phone or backed up on the server — by design, so nobody (including us) can read them.',
                    'Seit v0.7.0 sind 1:1-Textnachrichten Ende-zu-Ende-verschlüsselt. Der Schlüssel bleibt nur auf deinem Handy.',
                  ),
                ),
                item(
                  Icons.info_outline_rounded,
                  app.trEn('Henüz olmayanlar', 'Not available yet', 'Noch nicht verfügbar'),
                  app.trEn(
                    'Dosyaya dışa aktarma ve şifreli anahtar yedeği henüz yok. Eklendiğinde güncelleme notlarında duyurulacak.',
                    'Export to file and encrypted key backup are not available yet; they will be announced in release notes.',
                    'Export und verschlüsseltes Schlüssel-Backup gibt es noch nicht.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JuzzioChatTransferPage extends StatelessWidget {
  const JuzzioChatTransferPage({super.key});

  @override
  Widget build(BuildContext context) => const JuzzioBackupPage();
}

class JuzzioChatHistoryPage extends StatelessWidget {
  const JuzzioChatHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(JuzzioAppController.instance.loc('Sohbet geçmişi', 'Chat history', 'Chatverlauf'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.cleaning_services_outlined, color: p.dangerRed),
                  title: Text(JuzzioAppController.instance.loc('Tüm sohbetlerin içeriğini temizle', 'Clear all chats', 'Alle Chats leeren'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w700)),
                  onTap: () async {
                    await SupabaseService.instance.clearAllMessagesInMainRoom();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: p.dangerRed, content: Text(JuzzioAppController.instance.trEn('Sohbet içerikleri temizlendi.', 'Chat contents cleared.', 'Chatinhalte geleert.'))),
                    );
                  },
                ),
                Divider(height: 1, color: p.glassBorder),
                ListTile(
                  leading: Icon(Icons.delete_sweep_outlined, color: p.dangerRed),
                  title: Text(JuzzioAppController.instance.loc('Tüm sohbetleri sil', 'Delete all chats', 'Alle Chats löschen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.dangerRed, fontWeight: FontWeight.w800)),
                  onTap: () async {
                    await SupabaseService.instance.clearAllMessagesInMainRoom();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: p.dangerRed, content: Text(JuzzioAppController.instance.trEn('Tüm sohbetler silindi.', 'All chats deleted.', 'Alle Chats gelöscht.'))),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4 - 8. GÖRÜNÜM, DEPOLAMA, BİLDİRİMLER VE ERİŞİLEBİLİRLİK SAYFALARI
// =============================================================================
class JuzzioAppearanceSettingsPage extends StatelessWidget {
  const JuzzioAppearanceSettingsPage({super.key});

  String _fontSizeText(String code, JuzzioAppController appCtrl) {
    if (code == 'small') return appCtrl.trEn('Küçük', 'Small', 'Klein');
    if (code == 'large') return appCtrl.trEn('Büyük', 'Large', 'Groß');
    return appCtrl.trEn('Orta', 'Medium', 'Mittel');
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.loc('Görünüm', 'Appearance', 'Darstellung'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const JuzzioModernThemeSelector(),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [appCtrl.chatPalette?.swatchA ?? appCtrl.currentChatTheme.primaryColor, appCtrl.chatPalette?.swatchB ?? appCtrl.currentChatTheme.secondaryColor]),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ),
                      title: Text(
                        appCtrl.trEn('Sohbet Temaları (${kJuzzioChatThemes.length} Sıvı Cam)', 'Chat Themes (${kJuzzioChatThemes.length} Liquid Glass)', 'Chatdesigns (${kJuzzioChatThemes.length} Liquid Glass)'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${appCtrl.currentChatTheme.localizedName} • ${(appCtrl.chatThemeIntensity * 100).round()}%',
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatThemeCustomizerPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.format_size_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.loc('Yazı tipi boyutu', 'Font size', 'Schriftgröße'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _fontSizeText(appCtrl.fontSizeOption, appCtrl),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatsSettingsPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.accessibility_new_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.loc('Erişilebilirlik', 'Accessibility', 'Barrierefreiheit'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Yüksek kontrast modu ve animasyon azaltma', 'High contrast mode & reduce motion', 'Hoher Kontrast & reduzierte Bewegung'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioAccessibilitySettingsPage()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class JuzzioStorageSettingsPage extends StatefulWidget {
  const JuzzioStorageSettingsPage({super.key});

  @override
  State<JuzzioStorageSettingsPage> createState() =>
      _JuzzioStorageSettingsPageState();
}

class _JuzzioStorageSettingsPageState extends State<JuzzioStorageSettingsPage> {
  bool _loading = true;
  bool _clearing = false;
  int _cacheBytes = 0;
  int _appDataBytes = 0;

  @override
  void initState() {
    super.initState();
    _measureStorage();
  }

  Future<void> _measureStorage() async {
    setState(() => _loading = true);
    final metrics = await JuzzioSocialService.instance.measureLocalStorageBytes();
    if (!mounted) return;
    setState(() {
      _cacheBytes = metrics['cacheBytes'] ?? 0;
      _appDataBytes = metrics['appDataBytes'] ?? 0;
      _loading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _confirmAndClearCache() async {
    if (_clearing) return;
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.cardBg,
        title: Text(
          app.trEn('Önbelleği Temizle', 'Clear Cache', 'Cache leeren'),
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
        ),
        content: Text(
          app.trEn(
            'Geçici medya ve görsel önbelleği (${_formatBytes(_cacheBytes)}) silinecek. Mesajlarınız, hesabınız ve kalıcı verileriniz silinmez.',
            'Temporary media cache (${_formatBytes(_cacheBytes)}) will be cleared. Your messages, account, and permanent data will not be deleted.', 'Der temporäre Mediencache (${_formatBytes(_cacheBytes)}) wird geleert. Deine Nachrichten, dein Konto und dauerhafte Daten werden nicht gelöscht.',
          ),
          style: TextStyle(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.trEn('İptal', 'Cancel', 'Abbrechen')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: p.dangerRed,
              foregroundColor: Colors.white,
            ),
            child: Text(app.trEn('Önbelleği Temizle', 'Clear Cache', 'Cache leeren')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    final freed = await JuzzioSocialService.instance.clearSafeTemporaryCache();
    await _measureStorage();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          app.trEn(
            'Önbellek temizlendi (${_formatBytes(freed)} boşaltıldı).',
            'Cache cleared (${_formatBytes(freed)} freed).', 'Cache geleert (${_formatBytes(freed)} freigegeben).',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(
          app.loc('Depolama ve veriler', 'Storage and data', 'Speicher und Daten'),
          style: const TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: p.glassBorder),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.folder_outlined, color: p.amberGlow),
                        title: Text(
                          app.trEn('Geçici Medya Önbelleği', 'Temporary Media Cache', 'Temporärer Mediencache'),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _formatBytes(_cacheBytes),
                          style: TextStyle(color: p.textSecondary, fontSize: 13),
                        ),
                        trailing: ElevatedButton(
                          onPressed: _clearing ? null : _confirmAndClearCache,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: p.amberPrimary,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(app.trEn('Temizle', 'Clear', 'Löschen')),
                        ),
                      ),
                      Divider(height: 1, color: p.glassBorder),
                      ListTile(
                        leading: Icon(Icons.storage_rounded, color: p.amberGlow),
                        title: Text(
                          app.trEn('Uygulama Tercihleri & Yerel Veri', 'App Preferences & Local Data', 'App-Einstellungen & lokale Daten'),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _formatBytes(_appDataBytes),
                          style: TextStyle(color: p.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class JuzzioNotificationsSettingsPage extends StatelessWidget {
  const JuzzioNotificationsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.loc('Bildirimler', 'Notifications', 'Benachrichtigungen'),
              style: const TextStyle(
                fontFamily: JuzzioConfig.fontRegularBold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    if (!JuzzioFcmPushService.instance.notificationsEnabledOnOs) ...[
                      ListTile(
                        leading: Icon(Icons.warning_amber_rounded, color: p.dangerRed),
                        title: Text(
                          appCtrl.trEn(
                            'Sistem Bildirim İzni Kapalı',
                            'System Notification Permission Disabled', 'System-Benachrichtigungsberechtigung deaktiviert',
                          ),
                          style: TextStyle(color: p.dangerRed, fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          appCtrl.trEn(
                            'Android sistem ayarlarından Juzzio için bildirim iznini açın.',
                            'Enable notification permission for Juzzio in Android system settings.', 'Aktiviere die Benachrichtigungsberechtigung für Juzzio in den Android-Systemeinstellungen.',
                          ),
                          style: TextStyle(color: p.textSecondary, fontSize: 12),
                        ),
                        trailing: OutlinedButton(
                          onPressed: () => JuzzioFcmPushService.instance.openSystemNotificationSettings(),
                          child: Text(appCtrl.trEn('İzni Aç', 'Enable', 'Aktivieren')),
                        ),
                      ),
                      Divider(height: 1, color: p.glassBorder),
                    ],
                    ListTile(
                      leading: Icon(Icons.notifications_active_outlined, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Bildirim Akışı (Son Bildirimler)', 'Notifications Feed', 'Benachrichtigungs-Feed'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'Yeni mesaj, beğeni, takipçi, yorum ve çağrı bildirimlerini görüntüle',
                          'View recent likes, comments, followers, messages, and call alerts', 'Neueste Likes, Kommentare, Follower, Nachrichten und Anrufhinweise ansehen',
                        ),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const JuzzioNotificationsFeedPage(),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Genel Push ve Uygulama İçi Bildirimler', 'General Push & In-App Notifications', 'Allgemeine Push- & In-App-Benachrichtigungen'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notificationsEnabled,
                      onChanged: (val) {
                        appCtrl.setNotificationsEnabled(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Birebir Mesaj Bildirimleri', 'Direct Message Notifications', 'Benachrichtigungen für Direktnachrichten'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyDirectMessages,
                      onChanged: (val) {
                        appCtrl.setNotifyDirectMessages(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Grup Sohbeti Bildirimleri', 'Group Chat Notifications', 'Benachrichtigungen für Gruppenchats'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyGroupMessages,
                      onChanged: (val) {
                        appCtrl.setNotifyGroupMessages(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Sesli & Görüntülü Arama Bildirimleri', 'Voice & Video Call Alerts', 'Hinweise für Sprach- & Videoanrufe'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyCalls,
                      onChanged: (val) {
                        appCtrl.setNotifyCalls(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Takip ve Arkadaşlık İstekleri', 'Follow & Friend Requests', 'Folge- & Freundschaftsanfragen'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyFollows,
                      onChanged: (val) {
                        appCtrl.setNotifyFollows(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Gönderi Beğeni ve Yorumları', 'Post Likes & Comments', 'Likes & Kommentare zu Beiträgen'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyLikesComments,
                      onChanged: (val) {
                        appCtrl.setNotifyLikesComments(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Hikâye / Durum Yanıtları', 'Story Replies & Reactions', 'Story-Antworten & Reaktionen'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifyStories,
                      onChanged: (val) {
                        appCtrl.setNotifyStories(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Sistem ve Güncelleme Bildirimleri', 'System & Update Alerts', 'System- & Update-Hinweise'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.notifySystem,
                      onChanged: (val) {
                        appCtrl.setNotifySystem(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn('Cihaz Sessiz Modu (Otomatik Meşgul)', 'Silent Mode (Auto-Busy Calls)', 'Lautlos-Modus (Anrufe automatisch besetzt)'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      value: appCtrl.isSilentMode,
                      onChanged: (val) {
                        appCtrl.setSilentMode(val);
                        JuzzioFcmPushService.instance.syncTokenAndPreferencesWithSupabase();
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.music_note_rounded, color: p.textPrimary),
                      title: Text(
                        appCtrl.trEn('Zil sesleri ve uyarı tonları', 'Ringtones & alert tones', 'Klingeltöne & Hinweistöne'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Mesaj bildirim tonu ve arama zil sesi', 'Message tone and call ringtone', 'Nachrichtenton und Klingelton'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => JuzzioSoundSettingsPage.open(context),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.battery_charging_full_rounded, color: p.onlineGreen),
                      title: Text(
                        appCtrl.trEn('Pil ve Bildirim Koruma Optimizasyonu', 'Battery & Push Guard Optimization', 'Akku- & Push-Schutz-Optimierung'),
                        style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const JuzzioBatteryOptimizationPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class JuzzioLanguageSettingsPage extends StatelessWidget {
  const JuzzioLanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        final s = JuzzioStrings(appCtrl.uiLang);
        final uiOpt = appCtrl.getLanguageOption(appCtrl.uiLang);
        final subOpt = appCtrl.getLanguageOption(appCtrl.subtitleLang);

        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.trEn('Dil', 'Language', 'Sprache'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Text(uiOpt.flag, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        s.t('app_lang_title'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${uiOpt.nativeName} (${uiOpt.turkishName}) • ${s.t("app_lang_sub")}',
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () {
                        JuzzioLanguagePickerSheet.show(
                          context,
                          title: s.t('app_lang_title'),
                          subtitle: s.t('app_lang_sub'),
                          currentCode: appCtrl.uiLang,
                          onSelected: (code) => juzzioSwitchUiLanguage(context, code),
                        );
                      },
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Text(subOpt.flag, style: const TextStyle(fontSize: 26)),
                      title: Text(
                        s.t('subtitle_lang_title'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${subOpt.nativeName} (${subOpt.turkishName}) • ${s.t("subtitle_lang_sub")}',
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () {
                        JuzzioLanguagePickerSheet.show(
                          context,
                          title: s.t('subtitle_lang_title'),
                          subtitle: s.t('subtitle_lang_sub'),
                          currentCode: appCtrl.subtitleLang,
                          onSelected: appCtrl.setSubtitleLanguage,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// KATEGORİ 6: YARDIM & DESTEK SAYFASI (OTA Güncelleme, Yedekleme/Geçmiş, Depolama, Davet, Yapımcı)
// =============================================================================
class JuzzioHelpAndSupportPage extends StatelessWidget {
  final String username;

  const JuzzioHelpAndSupportPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.trEn('Yardım & Destek', 'Help & Support', 'Hilfe & Support'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.system_update_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Yazılım Güncelleme Denetleme (OTA)', 'Software Update (OTA)', 'Software-Update (OTA)'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'Mevcut Sürüm: v${JuzzioConfig.appVersion} • Wi-Fi / Mobil Veri OTA İndirme',
                          'Current Version: v${JuzzioConfig.appVersion} • Wi-Fi / Mobile Data OTA', 'Aktuelle Version: v${JuzzioConfig.appVersion} • OTA über WLAN / mobile Daten',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioOtaUpdateSettingsPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.bug_report_rounded, color: p.textPrimary),
                      title: Text(
                        appCtrl.trEn('Hata bildir / Geri bildirim', 'Report a bug / Feedback', 'Fehler melden / Feedback'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Ekran görüntüsüyle hata veya önerini gönder', 'Send a bug or idea with a screenshot', 'Fehler oder Idee mit Screenshot senden'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => JuzzioFeedbackPage.open(context),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.policy_rounded, color: p.textPrimary),
                      title: Text(
                        appCtrl.trEn('Gizlilik, KVKK ve yasal haklar', 'Privacy, data rights & legal', 'Datenschutz & Rechtliches'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Gizlilik politikası, kullanım koşulları, lisans', 'Privacy policy, terms, license', 'Datenschutz, Bedingungen, Lizenz'),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => JuzzioLegalPage.open(context),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.backup_outlined, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Sohbet Yedekleme, Aktarma & Geçmiş', 'Chat Backup, Transfer & History', 'Chat-Backup, Übertragung & Verlauf'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'Verilerin nerede saklanır, telefon değişince ne olur, sohbet geçmişi',
                          'Where your data is stored, changing phones, chat history', 'Verschlüsseltes Cloud-Backup, Geräteübertragung & Chatverlauf',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioChatsSettingsPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.data_usage_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.loc('Depolama ve veriler', 'Storage and data', 'Speicher und Daten'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn('Ağ kullanımı ve ses/medya önbelleği yönetimi', 'Network usage & voice/media cache management', 'Netzwerknutzung & Verwaltung des Sprach-/Mediencaches'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const JuzzioStorageSettingsPage()),
                      ),
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    ListTile(
                      leading: Icon(Icons.person_add_alt_rounded, color: p.amberGlow),
                      title: Text(
                        appCtrl.trEn('Arkadaşlarını Davet Et', 'Invite Friends', 'Freunde einladen'),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '@$username',
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      trailing: Icon(Icons.copy_rounded, color: p.amberGlow, size: 19),
                      onTap: () {
                        final inviteText =
                            _l3('Juzzio uygulamasında beni @$username kullanıcı adımla ekle! Canlı çevirili görüntülü konuşalım. Uygulama: https://github.com/engiincr/Juzzio-Chat/releases/latest', 'Add me on Juzzio with my username @$username! Let\'s video chat with live translation. App: https://github.com/engiincr/Juzzio-Chat/releases/latest', 'Füge mich auf Juzzio mit meinem Benutzernamen @$username hinzu! Lass uns per Video mit Live-Übersetzung sprechen. App: https://github.com/engiincr/Juzzio-Chat/releases/latest');
                        Clipboard.setData(ClipboardData(text: inviteText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: p.amberPrimary,
                            content: Text(
                              appCtrl.trEn(
                                'Davet bağlantınız panoya kopyalandı: @$username',
                                'Invite link copied to clipboard: @$username', 'Einladungslink in die Zwischenablage kopiert: @$username',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class JuzzioAccessibilitySettingsPage extends StatelessWidget {
  const JuzzioAccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(JuzzioAppController.instance.loc('Erişilebilirlik', 'Accessibility', 'Barrierefreiheit'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(JuzzioAppController.instance.loc('Kontrastı artır', 'Increase contrast', 'Kontrast erhöhen'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
                      value: appCtrl.highContrastMode,
                      onChanged: appCtrl.setHighContrastMode,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(JuzzioAppController.instance.loc('Animasyonları azalt', 'Reduce motion', 'Bewegung reduzieren'), style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
                      value: appCtrl.reduceMotion,
                      onChanged: appCtrl.setReduceMotion,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// 10. YAPIMCI SAYFASI (Powered by Juzzio • Developer / Coder by Engin)
// =============================================================================
class JuzzioDeveloperPage extends StatelessWidget {
  const JuzzioDeveloperPage({super.key});

  // v0.8.0: Ayarlar → Hakkında. Portföy düzeni, Juzzio yumuşak cam stiliyle.
  static const String _ig = 'https://ig.me/tugkancr';
  static const String _tg = 'https://t.me/tugkancr0';
  static const String _mail = 'engiincr@pm.me';

  Future<void> _open(BuildContext context, String url, String copyValue) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      Clipboard.setData(ClipboardData(text: copyValue));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(JuzzioAppController.instance.trEn('Panoya kopyalandı: $copyValue', 'Copied: $copyValue', 'Kopiert: $copyValue')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    TextStyle h(double size) => TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: t, fontSize: size, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.4);

    Widget stat(String value, String label) => Expanded(
          child: JuzzioGlass(
            radius: 20,
            blur: false,
            color: JuzzioGlassTokens.surface,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(children: [
              FittedBox(child: Text(value, style: h(22))),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: t2, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        );

    Widget skill(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: JuzzioGlass(
            radius: 22,
            blur: false,
            color: JuzzioGlassTokens.surface,
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JuzzioGlassTokens.surfaceStrong,
                  border: Border.all(color: JuzzioGlassTokens.borderStrong),
                ),
                child: Icon(icon, color: t, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(body, style: TextStyle(color: t2, fontSize: 12.5, height: 1.35)),
                ]),
              ),
            ]),
          ),
        );

    Widget social(IconData icon, String label, String handle, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: JuzzioGlass(
              radius: 22,
              blur: false,
              color: JuzzioGlassTokens.surface,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(children: [
                Icon(icon, color: t, size: 24),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 12.5)),
                Text(handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t2, fontSize: 10.5)),
              ]),
            ),
          ),
        );

    Widget link(IconData icon, String title, VoidCallback onTap) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(icon, color: t),
          title: Text(title, style: TextStyle(color: t, fontWeight: FontWeight.w800)),
          trailing: Icon(Icons.chevron_right_rounded, color: t2),
          onTap: onTap,
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t,
        elevation: 0,
        title: Text(app.trEn('Hakkında', 'About', 'Über'), style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // HERO
          JuzzioGlass(
            radius: 30,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 4 / 4.4,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.asset('assets/creator/engin.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.55, 1],
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              color: Colors.white.withValues(alpha: 0.18),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text(app.trEn('Juzzio\'nun yapımcısı', 'Creator of Juzzio', 'Schöpfer von Juzzio'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Engin ÇIRPAN',
                              style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          Text(app.trEn('Tek yapımcı · Yazılım · Tasarım', 'Sole creator · Code · Design', 'Alleiniger Entwickler · Code · Design'),
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    app.trEn(
                      'Juzzio\'yu fikirden yayına tek başıma tasarladım, kodladım ve yayınlıyorum. Amacım dil engeli olmadan, reklamsız ve güvenli bir iletişim deneyimi.',
                      'I designed, coded and ship Juzzio on my own — from idea to release. The goal: ad-free, secure communication without language barriers.',
                      'Ich habe Juzzio allein entworfen, programmiert und veröffentlicht.'),
                    style: TextStyle(color: t2, fontSize: 13.5, height: 1.45),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            stat('v${JuzzioConfig.appVersion}', app.trEn('Sürüm (BETA)', 'Version (BETA)', 'Version (BETA)')),
            const SizedBox(width: 8),
            stat('1', app.trEn('Yapımcı', 'Creator', 'Entwickler')),
            const SizedBox(width: 8),
            stat('3', app.trEn('Uygulama dili', 'App languages', 'Sprachen')),
            const SizedBox(width: 8),
            stat('PQ', app.trEn('Kuantum sonrası şifre', 'Post-quantum crypto', 'Post-Quanten')),
          ]),
          const SizedBox(height: 18),
          Text(app.trEn('Uzmanlık', 'Specialist', 'Fachgebiete'), style: h(20)),
          const SizedBox(height: 10),
          skill(Icons.phone_iphone_rounded, app.trEn('Mobil uygulama', 'Mobile app', 'Mobile App'),
              app.trEn('Flutter ile Android; sesli/görüntülü arama, canlı çeviri, hikâye ve gönderi.', 'Flutter on Android: calls, live translation, stories and posts.', 'Flutter auf Android.')),
          skill(Icons.dns_rounded, app.trEn('Sunucu & veritabanı', 'Backend & database', 'Backend & Datenbank'),
              app.trEn('Supabase (PostgreSQL, RLS), Edge Functions, LiveKit.', 'Supabase (PostgreSQL, RLS), Edge Functions, LiveKit.', 'Supabase, Edge Functions, LiveKit.')),
          skill(Icons.auto_awesome_rounded, app.trEn('Arayüz & cam tasarım', 'UI & glass design', 'UI & Glas-Design'),
              app.trEn('Yumuşak glassmorphism, aurora temaları, erişilebilir tipografi.', 'Soft glassmorphism, aurora themes, accessible typography.', 'Glassmorphism & Aurora-Themen.')),
          skill(Icons.shield_moon_rounded, app.trEn('Güvenlik', 'Security', 'Sicherheit'),
              app.trEn('ML-KEM-768 + X25519 hibrit uçtan uca şifreleme, anahtar yenileme, ML-DSA imza doğrulama.', 'Hybrid ML-KEM-768 + X25519 end-to-end encryption, rekeying, ML-DSA verification.', 'Hybride Post-Quanten-Verschlüsselung.')),
          const SizedBox(height: 8),
          Text(app.trEn('İletişim', 'Contact', 'Kontakt'), style: h(20)),
          const SizedBox(height: 10),
          Row(children: [
            social(Icons.camera_alt_rounded, 'Instagram', '@tugkancr', () => _open(context, _ig, 'ig.me/tugkancr')),
            const SizedBox(width: 8),
            social(Icons.send_rounded, 'Telegram', '@tugkancr0', () => _open(context, _tg, 't.me/tugkancr0')),
            const SizedBox(width: 8),
            social(Icons.alternate_email_rounded, app.trEn('E-posta', 'Email', 'E-Mail'), _mail, () => _open(context, 'mailto:$_mail', _mail)),
          ]),
          const SizedBox(height: 16),
          JuzzioGlass(
            radius: 24,
            blur: false,
            color: JuzzioGlassTokens.surface,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(children: [
              link(Icons.new_releases_rounded, app.trEn('Güncelleme notları', 'Release notes', 'Versionshinweise'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioReleaseNotesPage()))),
              Divider(height: 1, color: JuzzioGlassTokens.border),
              link(Icons.gavel_rounded, app.trEn('Gizlilik, KVKK ve yasal', 'Privacy, KVKK & legal', 'Datenschutz & Recht'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioLegalPage()))),
              Divider(height: 1, color: JuzzioGlassTokens.border),
              link(Icons.bug_report_rounded, app.trEn('Hata bildir / Geri bildirim', 'Report a bug / Feedback', 'Feedback'),
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioFeedbackPage()))),
            ]),
          ),
          const SizedBox(height: 16),
          Text(
            app.trEn('BETA (Erken Erişim) · © ${DateTime.now().year} Engin ÇIRPAN · Tüm hakları saklıdır.',
                'BETA (Early Access) · © ${DateTime.now().year} Engin ÇIRPAN · All rights reserved.',
                'BETA · © ${DateTime.now().year} Engin ÇIRPAN'),
            textAlign: TextAlign.center,
            style: TextStyle(color: t2, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}



// =============================================================================
// 11. OTA GÜNCELLEME DENETLEME MERKEZİ VE ERTELEME (1 Saat, 4 Saat, 1 Gün) MODALI
// =============================================================================
class JuzzioOtaSnoozeDialog {
  static Future<void> show(BuildContext context) async {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);
    final options = <(Duration, String, IconData)>[
      (const Duration(hours: 1), appCtrl.trEn('1 saat', '1 hour', '1 Stunde'), Icons.access_time_rounded),
      (const Duration(hours: 4), appCtrl.trEn('4 saat', '4 hours', '4 Stunden'), Icons.timelapse_rounded),
      (const Duration(hours: 24), appCtrl.trEn('1 gün', '1 day', '1 Tag'), Icons.today_rounded),
      (const Duration(days: 3), appCtrl.trEn('3 gün', '3 days', '3 Tage'), Icons.date_range_rounded),
      (const Duration(days: 7), appCtrl.trEn('1 hafta', '1 week', '1 Woche'), Icons.calendar_month_rounded),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: JuzzioGlass(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: p.glassBorder, borderRadius: BorderRadius.circular(99)),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  appCtrl.trEn('Güncellemeyi ertele', 'Snooze update', 'Update aufschieben'),
                  style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  appCtrl.trEn(
                    'Seçtiğin süre boyunca güncelleme bildirimi ve şeridi hiç gösterilmez; uygulamayı kapatıp açsan da süre korunur.',
                    'During the chosen time no update notification or banner is shown, even if you restart the app.',
                    'Während der gewählten Zeit wird keine Update-Meldung angezeigt, auch nach einem Neustart.',
                  ),
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in options)
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          appCtrl.snoozeOtaUpdate(o.$1);
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: p.pillBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: p.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(o.$3, size: 17, color: p.textPrimary),
                              const SizedBox(width: 7),
                              Text(o.$2, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// v0.7.0: Yeniden tasarlanan güncelleme merkezi — tema uyumlu cam kartlar,
/// animasyonlu indirme ilerlemesi, "Yenilikleri gör" ve taşmayan butonlar.
class JuzzioOtaUpdateSettingsPage extends StatelessWidget {
  const JuzzioOtaUpdateSettingsPage({super.key});

  String _ago(JuzzioAppController app, DateTime? t) {
    if (t == null) return app.trEn('Henüz denetlenmedi', 'Not checked yet', 'Noch nicht geprüft');
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return app.trEn('Az önce', 'Just now', 'Gerade eben');
    if (d.inHours < 1) return app.trEn('${d.inMinutes} dk önce', '${d.inMinutes} min ago', 'vor ${d.inMinutes} Min.');
    if (d.inDays < 1) return app.trEn('${d.inHours} sa önce', '${d.inHours} h ago', 'vor ${d.inHours} Std.');
    return app.trEn('${d.inDays} gün önce', '${d.inDays} d ago', 'vor ${d.inDays} T.');
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        final hasUpdate = appCtrl.otaUpdateAvailable ||
            (appCtrl.isOtaSnoozed && JuzzioReleaseNote.compareSemver(appCtrl.otaRemoteVersion, JuzzioConfig.appVersion) > 0);
        final progress = appCtrl.otaDownloadProgress.clamp(0.0, 1.0);

        Widget channelTile(String value, IconData icon, String title, String sub) {
          final selected = appCtrl.otaDownloadChannel == value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                HapticFeedback.selectionClick();
                appCtrl.setOtaDownloadChannel(value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? p.coolButtonBg.withValues(alpha: appCtrl.isDark ? 0.14 : 0.08) : p.pillBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: selected ? p.textPrimary.withValues(alpha: 0.6) : p.glassBorder, width: selected ? 1.4 : 1),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: p.textPrimary, size: 21),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(sub, style: TextStyle(color: p.textSecondary, fontSize: 12, height: 1.3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: selected ? p.textPrimary : p.textMuted, size: 22),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.trEn('Güncellemeler', 'Updates', 'Updates'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900),
            ),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                // 1) Durum kartı
                JuzzioGlass(
                  radius: 28,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasUpdate ? p.coolButtonBg : p.pillBg,
                              border: Border.all(color: p.glassBorder),
                            ),
                            child: Icon(
                              hasUpdate ? Icons.rocket_launch_rounded : Icons.verified_rounded,
                              color: hasUpdate ? p.coolButtonFg : p.onlineGreen,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasUpdate
                                      ? appCtrl.trEn('Yeni sürüm hazır', 'New version ready', 'Neue Version bereit')
                                      : appCtrl.trEn('Uygulaman güncel', 'You are up to date', 'Du bist auf dem neuesten Stand'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: JuzzioConfig.fontRegularBold,
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  hasUpdate
                                      ? 'v${JuzzioConfig.appVersion}  →  v${appCtrl.otaRemoteVersion}'
                                      : 'v${JuzzioConfig.appVersion} · BETA',
                                  style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (hasUpdate && appCtrl.otaReason.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(appCtrl.otaReason, style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4)),
                      ],
                      if (appCtrl.isOtaSnoozed && appCtrl.otaSnoozedUntil != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.snooze_rounded, size: 16, color: p.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                appCtrl.trEn(
                                  'Ertelendi: ${TimeOfDay.fromDateTime(appCtrl.otaSnoozedUntil!).format(context)} sonrasına kadar bildirim yok',
                                  'Snoozed: no notifications until ${TimeOfDay.fromDateTime(appCtrl.otaSnoozedUntil!).format(context)}',
                                  'Aufgeschoben bis ${TimeOfDay.fromDateTime(appCtrl.otaSnoozedUntil!).format(context)}',
                                ),
                                style: TextStyle(color: p.textSecondary, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: appCtrl.isDownloadingOta
                            ? Column(
                                key: const ValueKey('dl'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: progress),
                                      duration: const Duration(milliseconds: 300),
                                      builder: (_, v, __) => LinearProgressIndicator(
                                        value: v <= 0 ? null : v,
                                        minHeight: 8,
                                        backgroundColor: p.pillBg,
                                        valueColor: AlwaysStoppedAnimation<Color>(p.textPrimary),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    appCtrl.trEn('İndiriliyor… %${(progress * 100).round()}', 'Downloading… ${(progress * 100).round()}%',
                                        'Wird geladen… ${(progress * 100).round()} %'),
                                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ],
                              )
                            : const SizedBox(key: ValueKey('idle'), width: double.infinity),
                      ),
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, c) {
                          final narrow = c.maxWidth < 330;
                          final primary = FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: p.coolButtonBg,
                              foregroundColor: p.coolButtonFg,
                              minimumSize: const Size.fromHeight(48),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: appCtrl.isCheckingUpdate || appCtrl.isDownloadingOta
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.maybeOf(context);
                                    if (hasUpdate) {
                                      final msg = appCtrl.hasDownloadedOta
                                          ? await appCtrl.installDownloadedOta()
                                          : await appCtrl.startOtaDownloadAndInstall();
                                      messenger?.showSnackBar(SnackBar(content: Text(msg)));
                                      return;
                                    }
                                    final found = await appCtrl.checkForOtaUpdate(manualCheck: true);
                                    messenger?.showSnackBar(SnackBar(
                                      content: Text(found
                                          ? appCtrl.trEn('Yeni sürüm v${appCtrl.otaRemoteVersion} bulundu!',
                                              'New version v${appCtrl.otaRemoteVersion} found!', 'Neue Version v${appCtrl.otaRemoteVersion} gefunden!')
                                          : appCtrl.trEn('Uygulaman güncel (v${JuzzioConfig.appVersion}).',
                                              'You are up to date (v${JuzzioConfig.appVersion}).', 'Aktuell (v${JuzzioConfig.appVersion}).')),
                                    ));
                                  },
                            icon: appCtrl.isCheckingUpdate
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: p.coolButtonFg),
                                  )
                                : Icon(hasUpdate
                                    ? (appCtrl.hasDownloadedOta ? Icons.install_mobile_rounded : Icons.download_rounded)
                                    : Icons.refresh_rounded),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                hasUpdate
                                    ? (appCtrl.hasDownloadedOta
                                        ? appCtrl.trEn('Kur', 'Install', 'Installieren')
                                        : appCtrl.trEn('Şimdi güncelle', 'Update now', 'Jetzt aktualisieren'))
                                    : appCtrl.trEn('Güncellemeleri denetle', 'Check for updates', 'Nach Updates suchen'),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          );
                          final secondary = OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.textPrimary,
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(color: p.glassBorder),
                              shape: const StadiumBorder(),
                            ),
                            onPressed: () => JuzzioReleaseNotesPage.open(
                                context, focusVersion: hasUpdate ? appCtrl.otaRemoteVersion : JuzzioConfig.appVersion),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(appCtrl.trEn('Yenilikleri gör', 'See what\'s new', 'Neuigkeiten'),
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          );
                          if (narrow) {
                            return Column(children: [primary, const SizedBox(height: 8), secondary]);
                          }
                          return Row(children: [
                            Expanded(child: primary),
                            const SizedBox(width: 8),
                            Expanded(child: secondary),
                          ]);
                        },
                      ),
                      if (hasUpdate && !appCtrl.isDownloadingOta) ...[
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: p.textSecondary),
                            onPressed: () => JuzzioOtaSnoozeDialog.show(context),
                            icon: const Icon(Icons.snooze_rounded, size: 18),
                            label: Text(appCtrl.trEn('Ertele', 'Snooze', 'Aufschieben')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2) Bilgi kartı
                JuzzioGlass(
                  radius: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    children: [
                      _infoRow(p, Icons.phone_android_rounded, appCtrl.trEn('Yüklü sürüm', 'Installed', 'Installiert'),
                          'v${JuzzioConfig.appVersion} (${JuzzioConfig.appVersionCode})'),
                      _infoRow(p, Icons.science_rounded, appCtrl.trEn('Yayın kanalı', 'Channel', 'Kanal'),
                          appCtrl.trEn('BETA · Erken Erişim', 'BETA · Early Access', 'BETA · Früher Zugang')),
                      _infoRow(p, Icons.history_rounded, appCtrl.trEn('Son denetim', 'Last check', 'Letzte Prüfung'),
                          _ago(appCtrl, appCtrl.lastUpdateCheckTime)),
                      _infoRow(p, Icons.bolt_rounded, appCtrl.trEn('Bildirim', 'Notification', 'Benachrichtigung'),
                          appCtrl.trEn('Yeni sürüm yayınlanınca anında', 'Instantly on release', 'Sofort bei Veröffentlichung')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 3) İndirme bağlantısı tercihi
                JuzzioGlass(
                  radius: 24,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                        child: Text(appCtrl.trEn('İndirme bağlantısı', 'Download over', 'Herunterladen über'),
                            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                      channelTile('both', Icons.swap_vert_circle_rounded, appCtrl.trEn('Wi-Fi ve mobil veri', 'Wi-Fi and mobile data', 'WLAN und mobile Daten'),
                          appCtrl.trEn('Her bağlantıda indir', 'Download on any connection', 'Über jede Verbindung')),
                      channelTile('wifi', Icons.wifi_rounded, appCtrl.trEn('Yalnızca Wi-Fi', 'Wi-Fi only', 'Nur WLAN'),
                          appCtrl.trEn('Mobil veriyi korur', 'Saves mobile data', 'Spart mobile Daten')),
                      channelTile('mobile', Icons.signal_cellular_alt_rounded, appCtrl.trEn('Yalnızca mobil veri', 'Mobile data only', 'Nur mobile Daten'),
                          appCtrl.trEn('Wi-Fi kullanılmaz', 'Wi-Fi is not used', 'WLAN wird nicht genutzt')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                JuzzioGlass(
                  radius: 24,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_rounded, color: p.textPrimary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appCtrl.trEn(
                            'Güncellemeler yalnızca resmi GitHub sürümünden indirilir. Android, farklı bir imzayla hazırlanmış APK\'nın bu uygulamanın üzerine kurulmasına izin vermez.',
                            'Updates are downloaded only from the official GitHub release. Android refuses to install an APK signed with a different key over this app.',
                            'Updates kommen nur vom offiziellen GitHub-Release. Android installiert keine APK mit fremder Signatur über diese App.',
                          ),
                          style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(JuzzioPalette p, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 19, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: p.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 12. PİL VE PERFORMANS OPTİMİZASYONU SAYFASI (Arama Pil Tasarrufu & Bildirim Koruma)
// =============================================================================
class JuzzioBatteryOptimizationPage extends StatelessWidget {
  const JuzzioBatteryOptimizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: appCtrl,
      builder: (context, _) {
        final p = JuzzioPalette(appCtrl.isDark);
        return Scaffold(
          backgroundColor: p.bgPrimary,
          appBar: AppBar(
            backgroundColor: p.sheetBg,
            foregroundColor: p.textPrimary,
            elevation: 0,
            title: Text(
              appCtrl.trEn('Pil ve Performans Optimizasyonu', 'Battery & Performance Optimization', 'Akku- & Leistungsoptimierung'),
              style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: p.onlineGreen,
                      title: Text(
                        appCtrl.trEn(
                          'Sesli/Görüntülü Aramada Akıllı Pil Tasarrufu',
                          'Smart Battery Saver During Audio/Video Calls', 'Intelligenter Akkusparmodus bei Audio-/Videoanrufen',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'Arama esnasında arka plan soket uyanmalarını ve GPU yükünü optimize ederek pil tüketimini %45 azaltır.',
                          'Reduces battery drain by 45% during calls by optimizing socket wakeups and GPU load.', 'Reduziert den Akkuverbrauch bei Anrufen um 45 %, indem Socket-Aufwachvorgänge und GPU-Last optimiert werden.',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.callBatterySaverEnabled,
                      onChanged: appCtrl.setCallBatterySaverEnabled,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.onlineGreen,
                      title: Text(
                        appCtrl.trEn(
                          'OLED Karanlık Piksel Güç Tasarrufu',
                          'OLED True-Black Pixel Power Saver', 'OLED-Echtschwarz-Energiesparmodus',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'AMOLED/OLED ekranlarda karanlık piksellerin güç tüketimini minimuma indirir.',
                          'Minimizes power consumption on AMOLED/OLED displays.', 'Minimiert den Stromverbrauch auf AMOLED-/OLED-Displays.',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.oledPixelSaverEnabled,
                      onChanged: appCtrl.setOledPixelSaverEnabled,
                    ),
                    Divider(height: 1, color: p.glassBorder),
                    SwitchListTile(
                      activeColor: p.amberGlow,
                      title: Text(
                        appCtrl.trEn(
                          'Kesintisiz Bildirim Koruma Kalkanı (Önerilen)',
                          'Uninterrupted Push Notification Guard (Recommended)', 'Ununterbrochener Push-Benachrichtigungsschutz (empfohlen)',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        appCtrl.trEn(
                          'Pil optimizasyonu aktifken arama, grup konferans, sesli mesaj ve OTA güncelleme bildirimlerinin gecikmesini %100 önler.',
                          'Guarantees 100% instant delivery for calls, group calls, voice notes, and OTA update notifications while battery saver is active.', 'Garantiert die sofortige Zustellung von Anrufen, Gruppenanrufen, Sprachnachrichten und OTA-Update-Hinweisen, auch wenn der Energiesparmodus aktiv ist.',
                        ),
                        style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12),
                      ),
                      value: appCtrl.backgroundPushGuardEnabled,
                      onChanged: appCtrl.setBackgroundPushGuardEnabled,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.amberGlow,
                          side: BorderSide(color: p.amberGlow),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        onPressed: appCtrl.requestAndroidBatteryExemption,
                        icon: const Icon(Icons.battery_saver_rounded),
                        label: Text(
                          appCtrl.trEn(
                            'Android Pil Kısıtlamasını Kaldır (Kesintisiz Bildirim İzni)',
                            'Allow Unrestricted Background Notifications', 'Uneingeschränkte Hintergrundbenachrichtigungen erlauben',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: p.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appCtrl.trEn('Görüntülü Arama Kare Hızı (FPS) ve Pil Dengesi', 'Video Call Frame Rate (FPS) & Battery Balance', 'Bildrate (FPS) bei Videoanrufen & Akkubalance'),
                      style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.amberGlow, fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    const SizedBox(height: 8),
                    for (final item in [
                      MapEntry('24fps', appCtrl.trEn('24 FPS (Maksimum Pil Tasarrufu)', '24 FPS (Maximum Battery Saving)', '24 FPS (maximale Akkuersparnis)')),
                      MapEntry('30fps', appCtrl.trEn('30 FPS (Dengeli HD & Pil Koruması)', '30 FPS (Balanced HD & Battery Saver)', '30 FPS (ausgewogenes HD & Akkusparen)')),
                      MapEntry('60fps', appCtrl.trEn('60 FPS (Ultra Akıcı Performans)', '60 FPS (Ultra Smooth Performance)', '60 FPS (ultraflüssige Leistung)')),
                    ])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        activeColor: p.amberGlow,
                        title: Text(item.value, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
                        value: item.key,
                        groupValue: appCtrl.callVideoFpsMode,
                        onChanged: (v) {
                          if (v != null) appCtrl.setCallVideoFpsMode(v);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// 13. UYGULAMA İZİNLERİ MERKEZİ (Bildirim, Kamera, Galeri, Mikrofon, Konum)
// =============================================================================
class JuzzioPermissionsCenterPage extends StatefulWidget {
  const JuzzioPermissionsCenterPage({super.key});

  @override
  State<JuzzioPermissionsCenterPage> createState() => _JuzzioPermissionsCenterPageState();
}

class _JuzzioPermissionsCenterPageState extends State<JuzzioPermissionsCenterPage> {
  Map<String, bool> _granted = {
    'notification': true,
    'camera': true,
    'microphone': true,
    'photos': true,
    'location': true,
  };

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    try {
      final n = await Permission.notification.isGranted;
      final c = await Permission.camera.isGranted;
      final m = await Permission.microphone.isGranted;
      final ph = await Permission.photos.isGranted;
      if (!mounted) return;
      setState(() {
        _granted = {
          'notification': n,
          'camera': c,
          'microphone': m,
          'photos': ph,
        };
      });
    } catch (_) {}
  }

  Future<void> _requestAll() async {
    try {
      await [
        Permission.notification,
        Permission.camera,
        Permission.microphone,
        Permission.photos,
        Permission.videos,
      ].request();
      await _refreshPermissions();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final p = JuzzioPalette(appCtrl.isDark);

    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.sheetBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(
          appCtrl.trEn('İzin Yöneticisi', 'Permissions Manager', 'Berechtigungsverwaltung'),
          style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.glassBorder),
            ),
            child: Column(
              children: [
                _permRow(
                  p,
                  Icons.notifications_active_rounded,
                  appCtrl.trEn('Bildirim İzni', 'Notifications Permission', 'Benachrichtigungsberechtigung'),
                  appCtrl.trEn('Arama, grup konferans, mesaj ve OTA bildirimleri', 'Calls, group calls, messages & OTA alerts', 'Anrufe, Gruppenanrufe, Nachrichten & OTA-Hinweise'),
                  _granted['notification'] == true,
                  () async {
                    await Permission.notification.request();
                    _refreshPermissions();
                  },
                ),
                Divider(height: 1, color: p.glassBorder),
                _permRow(
                  p,
                  Icons.videocam_rounded,
                  appCtrl.trEn('Kamera İzni', 'Camera Permission', 'Kameraberechtigung'),
                  appCtrl.trEn('HD görüntülü görüşme ve 24 saatlik hikaye çekimi', 'HD video calls & 24-hour story capture', 'HD-Videoanrufe & 24-Stunden-Storys'),
                  _granted['camera'] == true,
                  () async {
                    await Permission.camera.request();
                    _refreshPermissions();
                  },
                ),
                Divider(height: 1, color: p.glassBorder),
                _permRow(
                  p,
                  Icons.mic_rounded,
                  appCtrl.trEn('Mikrofon İzni', 'Microphone Permission', 'Mikrofonberechtigung'),
                  appCtrl.trEn('Canlı çeviri, sesli arama ve .m4a sesli mesaj kaydı', 'Live translation, voice calls & .m4a voice notes', 'Liveübersetzung, Sprachanrufe & .m4a-Sprachnachrichten'),
                  _granted['microphone'] == true,
                  () async {
                    await Permission.microphone.request();
                    _refreshPermissions();
                  },
                ),
                Divider(height: 1, color: p.glassBorder),
                _permRow(
                  p,
                  Icons.photo_library_rounded,
                  appCtrl.trEn('Galeri ve Medya İzni', 'Gallery & Media Permission', 'Galerie- & Medienberechtigung'),
                  appCtrl.trEn('Profil fotoğrafı kırpma ve görsel/video paylaşımı', 'Profile photo cropping & media sharing', 'Zuschneiden des Profilbilds & Teilen von Medien'),
                  _granted['photos'] == true,
                  () async {
                    await Permission.photos.request();
                    _refreshPermissions();
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.amberPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: _requestAll,
                    icon: const Icon(Icons.done_all_rounded),
                    label: Text(
                      appCtrl.trEn('Tüm İzinleri Doğrula ve Etkinleştir', 'Verify & Grant All Permissions', 'Alle Berechtigungen prüfen & erteilen'),
                      style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(
    JuzzioPalette p,
    IconData icon,
    String title,
    String subtitle,
    bool isGranted,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: p.amberGlow),
      title: Text(title, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textPrimary, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(fontFamily: JuzzioConfig.fontRegularBold, color: p.textSecondary, fontSize: 12)),
      trailing: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isGranted ? p.onlineGreen : p.amberPrimary,
          foregroundColor: Colors.white,
        ),
        onPressed: onTap,
        child: Text(isGranted ? _l3('Aktif', 'Active', 'Aktiv') : _l3('İzin Ver', 'Allow', 'Erlauben'), style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }
}


/// v0.7.0: Eski iki düğmeli gri seçici yerine yüksek kontrastlı, animasyonlu ve dokunsal
/// geri bildirimli üçlü tema kartı.
class JuzzioThemeModeSelector extends StatelessWidget {
  const JuzzioThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = JuzzioPalette(app.isDark);
        final items = <(String, IconData, String)>[
          ('light', Icons.light_mode_rounded, _l3('Gündüz', 'Light', 'Hell')),
          ('dark', Icons.dark_mode_rounded, _l3('Gece', 'Dark', 'Dunkel')),
          ('system', Icons.brightness_auto_rounded, _l3('Sistem', 'System', 'System')),
          ('scheduled', Icons.schedule_rounded, _l3('Zamanlı', 'Scheduled', 'Zeitplan')),
        ];
        String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
        Future<void> pickTime(bool start) async {
          final cur = start ? app.darkStartMinutes : app.darkEndMinutes;
          final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
          if (r == null) return;
          final m = r.hour * 60 + r.minute;
          start ? app.setThemeSchedule(startMinutes: m) : app.setThemeSchedule(endMinutes: m);
        }
        // v0.8.2: özel tema etkinken açık/koyu modu temanın kendisi belirler
        final customNote = app.activeCustomTheme != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: p.pillBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.glassBorder),
          ),
          child: Row(
            children: [
              for (final it in items)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: app.themeSelectionMode == it.$1,
                    label: it.$3,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        app.setThemeSelectionMode(it.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: app.themeSelectionMode == it.$1 ? p.coolButtonBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: app.themeSelectionMode == it.$1
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))]
                              : const [],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedScale(
                              scale: app.themeSelectionMode == it.$1 ? 1.12 : 1.0,
                              duration: const Duration(milliseconds: 260),
                              child: Icon(it.$2,
                                  size: 22, color: app.themeSelectionMode == it.$1 ? p.coolButtonFg : p.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              it.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: app.themeSelectionMode == it.$1 ? p.coolButtonFg : p.textSecondary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
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
        ),
            if (app.themeSelectionMode == 'scheduled')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => pickTime(true),
                      icon: const Icon(Icons.nightlight_round, size: 18),
                      label: Text('${_l3('Gece', 'Dark', 'Dunkel')} ${hm(app.darkStartMinutes)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => pickTime(false),
                      icon: const Icon(Icons.wb_sunny_rounded, size: 18),
                      label: Text('${_l3('Gündüz', 'Light', 'Hell')} ${hm(app.darkEndMinutes)}'),
                    ),
                  ),
                ]),
              ),
            if (customNote)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _l3('Özel tema etkin: açık/koyu görünümü temanın kendisi belirler.',
                      'A custom theme is active: it defines light/dark itself.', 'Eigenes Design aktiv.'),
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
