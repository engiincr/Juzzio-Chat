// =============================================================================
// JUZZIO v0.3.0 — Civciv Oyunu
//  • Yalnızca arkadaşlar arası; davet ile eşleşme; kişi başı en fazla 1 civciv
//  • Çok yavaş büyür (her besleme +1 xp, kişi başı 6 saatte bir)
//  • 12 saat beslenmezse acıkır, 3 gün beslenmezse "Ölüyorum!", 7 günde ölür
//  • Konuşma balonu kullanıcının (gizli) cinsiyetine göre: annecim / babacım / adı
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/juzzio_features_service.dart';
import '../services/supabase_service.dart';
import '../services/juzzio_time_sync.dart';
import '../services/juzzio_chick_wardrobe.dart';
import '../widgets/juzzio_chick_art.dart';
import 'chick_wardrobe_screen.dart';
import '../widgets/juzzio_nest_scene.dart';
import '../widgets/juzzio_cloth_refresh.dart';
import '../widgets/juzzio_motion.dart';

class JuzzioChickGameScreen extends StatefulWidget {
  final List<JuzzioUserProfile> friends;
  final String myDisplayName;

  /// Sohbetteki çatlak yumurtadan açıldıysa: bu arkadaş doğrudan davet edilir.
  final JuzzioUserProfile? inviteFriend;

  const JuzzioChickGameScreen({super.key, required this.friends, required this.myDisplayName, this.inviteFriend});

  @override
  State<JuzzioChickGameScreen> createState() => _JuzzioChickGameScreenState();
}

class _JuzzioChickGameScreenState extends State<JuzzioChickGameScreen> with TickerProviderStateMixin {
  final JuzzioFeaturesService _features = JuzzioFeaturesService.instance;
  JuzzioChickState? _state;
  String _gender = 'unspecified';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _refreshTimer;
  late final AnimationController _bounce;
  // v0.7.0: besleme anında yumurta/civciv titrer
  late final AnimationController _wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  /// v1.0.0: sevilince prenses gibi sağa dönüp cilve yapar
  late final AnimationController _twirl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  // v0.9.3: göz kırpma, kanat çırpma ve parçacık (kalp / yem) animasyonları
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  late final AnimationController _flap = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  bool _fxHearts = true;
  int _fxSeed = 1;
  int _pets = 0;
  Timer? _blinkTimer;
  final math.Random _rnd = math.Random();

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2400 + _rnd.nextInt(3200)), () async {
      if (!mounted) return;
      try {
        await _blink.forward(from: 0);
        if (mounted) await _blink.reverse();
      } catch (_) {}
      if (mounted) _scheduleBlink();
    });
  }

  void _burst({required bool hearts}) {
    setState(() {
      _fxHearts = hearts;
      _fxSeed = _rnd.nextInt(1 << 20);
    });
    _fx.forward(from: 0);
  }

  /// Sahneye dokunma: yumurtada titreme, civcivde sevme (kalp + kanat çırpma)
  void _pet(JuzzioChickState st) {
    HapticFeedback.selectionClick();
    if (st.stage < 1) _wobble.forward(from: 0); // yumurta titrer
    if (st.stage >= 1) {
      if (!JuzzioAppController.instance.reduceMotion) _twirl.forward(from: 0);
      _flap.forward(from: 0).then((_) {
        if (mounted) _flap.reverse();
      });
      _burst(hearts: true);
      setState(() => _pets++);
    }
  }

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _load();
    _features.fetchMyGender().then((g) {
      if (mounted) setState(() => _gender = g);
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load(silent: true));
    _scheduleBlink();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _bounce.dispose();
    _wobble.dispose();
    _twirl.dispose();
    _blinkTimer?.cancel();
    _blink.dispose();
    _flap.dispose();
    _fx.dispose();
    super.dispose();
  }

  Map<String, String> _style = const {};

  Future<void> _loadWardrobe() async {
    try {
      final w = await JuzzioChickWardrobeService.instance.fetch();
      if (mounted) setState(() => _style = w.style);
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    unawaited(_loadWardrobe());
    try {
      final st = await _features.fetchMyChick();
      if (!mounted) return;
      setState(() {
        _state = st;
        _error = null;
        _loading = false;
      });
      final friend = widget.inviteFriend;
      if (friend != null && !_autoInviteHandled) {
        _autoInviteHandled = true;
        final alreadyInvited = st.invites.any((i) => !i.incoming && i.otherName == friend.displayName);
        if (!st.hasChick && !alreadyInvited) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _inviteDirect(friend);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.instance.friendlyError(e);
        _loading = false;
      });
    }
  }

  bool _autoInviteHandled = false;

  Future<void> _inviteDirect(JuzzioUserProfile friend) async {
    final app = JuzzioAppController.instance;
    final nameCtrl = TextEditingController(text: app.t('chick_default_name'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Text('🥚', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Text(app.t('chick_invite_friend'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${friend.displayName} (@${friend.username})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: app.t('chick_name_label'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.t('chick_invite_friend'))),
        ],
      ),
    );
    final chickName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true) return;
    await _run(
      () => _features.inviteChickPartner(friendId: friend.id, chickName: chickName.isEmpty ? app.t('chick_default_name') : chickName),
      okText: app.t('chick_invite_sent').replaceAll('{name}', friend.displayName),
    );
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? JuzzioColors.red500 : JuzzioColors.emerald500),
    );
  }

  Future<void> _run(Future<void> Function() action, {String? okText}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (okText != null) _snack(okText);
      await _load(silent: true);
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _feed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await _features.feedChick();
      if (res.fed) {
        _wobble.forward(from: 0);
        HapticFeedback.mediumImpact();
        _burst(hearts: false);
        _flap.forward(from: 0).then((_) {
          if (mounted) _flap.reverse();
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) _burst(hearts: true);
        });
      }
      _snack(res.fed ? JuzzioAppController.instance.t('chick_fed') : JuzzioAppController.instance.t('chick_too_soon'),
          error: !res.fed);
      await _load(silent: true);
    } catch (e) {
      _snack(SupabaseService.instance.friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteFlow() async {
    final app = JuzzioAppController.instance;
    if (widget.friends.isEmpty) {
      _snack(app.t('chick_no_friends'), error: true);
      return;
    }
    final nameCtrl = TextEditingController(text: app.t('chick_default_name'));
    final picked = await showJuzzioSheet<JuzzioUserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuzzioGlassTokens.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    app.t('chick_pick_friend'),
                    style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                    child: TextField(
                      controller: nameCtrl,
                      maxLength: 24,
                      decoration: InputDecoration(
                        labelText: app.t('chick_name_label'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.friends.length,
                      itemBuilder: (_, i) {
                        final f = widget.friends[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: f.avatarUrl != null ? NetworkImage(f.avatarUrl!) : null,
                            child: f.avatarUrl == null ? Text(f.displayName.isNotEmpty ? f.displayName[0].toUpperCase() : '?') : null,
                          ),
                          title: Text(f.displayName),
                          subtitle: Text('@${f.username}'),
                          trailing: const Icon(Icons.egg_alt_rounded, color: JuzzioColors.amber500),
                          onTap: () => Navigator.of(ctx).pop(f),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final chickName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (picked == null) return;
    await _run(
      () => _features.inviteChickPartner(friendId: picked.id, chickName: chickName.isEmpty ? app.t('chick_default_name') : chickName),
      okText: app.t('chick_invite_sent').replaceAll('{name}', picked.displayName),
    );
  }

  Future<void> _confirmRelease() async {
    final app = JuzzioAppController.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('chick_release')),
        content: Text(app.t('chick_release_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('common_cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('chick_release'), style: const TextStyle(color: JuzzioColors.red500)),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _features.releaseChick());
  }

  String _stageEmoji(int stage) => const ['🥚', '🐣', '🐥', '🐔'][stage.clamp(0, 3)];

  String _speech(JuzzioChickState st) {
    final app = JuzzioAppController.instance;
    if (st.mood == 'dying') return app.t('chick_mood_dying');
    if (st.mood == 'hungry') {
      if (_gender == 'female') return app.t('chick_hungry_female');
      if (_gender == 'male') return app.t('chick_hungry_male');
      return app.t('chick_hungry_neutral').replaceAll('{name}', widget.myDisplayName);
    }
    return app.t('chick_mood_happy');
  }

  String _formatWait(DateTime at) {
    final app = JuzzioAppController.instance;
    final diff = at.difference(JuzzioClock.now());
    if (diff.isNegative) return app.t('chick_feed');
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return app.t('chick_next_feed_in').replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: p.headerDarkForest,
        foregroundColor: JuzzioGlassTokens.heading,
        title: Text(app.t('chick_title'), style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w800)),
        actions: [
          // v0.9.4: gardırop (yalnız civciv yumurtadan çıktıysa)
          if ((_state?.hasChick ?? false) && (_state?.stage ?? 0) >= 1)
            IconButton(
              tooltip: app.trEn('Gardırop', 'Wardrobe', 'Garderobe'),
              icon: const Icon(Icons.checkroom_rounded),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioChickWardrobeScreen(mood: _state?.mood ?? 'happy')));
                if (mounted) _loadWardrobe();
              },
            ),
          IconButton(
            tooltip: app.t('chick_rules_title'),
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(app.t('chick_rules_title')),
                content: Text(app.t('chick_rules')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(app.t('common_ok')))],
              ),
            ),
          ),
        ],
      ),
      body: JuzzioClothRefresh(
        onRefresh: () => _load(silent: true),
        child: _buildBody(p),
      ),
    );
  }

  Widget _buildBody(JuzzioPalette p) {
    final app = JuzzioAppController.instance;
    if (_loading && _state == null) return const Center(child: JuzzioOrbitLoader());
    if (_error != null && _state == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary))),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: _load, child: Text(app.t('common_retry')))),
        ],
      );
    }
    final st = _state ?? const JuzzioChickState();
    final textColor = p.textPrimary;

    if (!st.hasChick) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          JuzzioNestScene(stage: 0, crack: 0, wobble: _wobble, idle: _bounce, chickEmoji: '🥚', dark: p.isDark),
          const SizedBox(height: 12),
          Text(app.t('chick_intro'),
              textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 15.5, height: 1.45)),
          if (st.lastChickName != null) ...[
            const SizedBox(height: 14),
            Text(
              (st.lastChickStatus == 'dead' ? app.t('chick_died_info') : app.t('chick_released_info'))
                  .replaceAll('{name}', st.lastChickName!),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 22),
          JuzzioLiquidGlassButton(
            onTap: _busy ? null : _inviteFlow,
            icon: Icons.favorite_rounded,
            label: app.t('chick_invite_friend'),
            tint: const Color(0xFFFF6F91),
            loading: _busy,
          ),
          if (st.invites.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(app.t('chick_invites_title'),
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            for (final inv in st.invites)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: inv.otherAvatar != null && inv.otherAvatar!.isNotEmpty ? NetworkImage(inv.otherAvatar!) : null,
                    child: (inv.otherAvatar == null || inv.otherAvatar!.isEmpty)
                        ? Text(inv.otherName.isNotEmpty ? inv.otherName[0].toUpperCase() : '?')
                        : null,
                  ),
                  title: Text(inv.otherName),
                  subtitle: Text(
                    (inv.incoming ? app.t('chick_invite_incoming') : app.t('chick_invite_outgoing'))
                        .replaceAll('{chick}', inv.chickName),
                  ),
                  trailing: inv.incoming
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: app.t('chick_decline'),
                              icon: const Icon(Icons.close_rounded, color: JuzzioColors.red500),
                              onPressed: _busy
                                  ? null
                                  : () => _run(() => _features.respondChickInvite(inviteId: inv.id, accept: false)),
                            ),
                            IconButton(
                              tooltip: app.t('chick_accept'),
                              icon: const Icon(Icons.check_circle_rounded, color: JuzzioColors.emerald500),
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                        () => _features.respondChickInvite(inviteId: inv.id, accept: true),
                                        okText: app.t('chick_hatched'),
                                      ),
                            ),
                          ],
                        )
                      : TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => _features.respondChickInvite(inviteId: inv.id, accept: false)),
                          child: Text(app.t('common_cancel')),
                        ),
                ),
              ),
          ],
        ],
      );
    }

    final nextXp = st.nextStageXp;
    final progress = nextXp == null ? 1.0 : (st.xp / nextXp).clamp(0.0, 1.0);
    final moodColor = st.mood == 'dying'
        ? JuzzioColors.red500
        : st.mood == 'hungry'
            ? JuzzioColors.amber500
            : JuzzioColors.emerald500;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: AnimatedSwitcher(
           duration: const Duration(milliseconds: 380),
           transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
           child: Container(
            key: ValueKey(_speech(st)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: moodColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: moodColor.withValues(alpha: 0.6)),
            ),
            child: Text(_speech(st),
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
           ),
          ),
        ),
        const SizedBox(height: 8),
        // v0.7.0: beyaz zemin yerine gerçek saman kuş yuvası; yumurta beslendikçe titrer
        // ve deneyim puanı arttıkça kabuğu adım adım çatlar.
        GestureDetector(
          onTap: () => _pet(st),
          child: Stack(
            children: [
              JuzzioNestScene(
                style: _style,
                stage: st.stage,
                crack: st.stage <= 0 ? progress : 0,
                wobble: _wobble,
                idle: _bounce,
                chickEmoji: _stageEmoji(st.stage),
                dark: p.isDark,
                mood: st.mood,
                blink: _blink,
                flap: _flap,
                twirl: _twirl,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _fx,
                    builder: (_, __) => CustomPaint(
                      painter: JuzzioChickParticlesPainter(progress: _fx.value, hearts: _fxHearts, seed: _fxSeed),
                    ),
                  ),
                ),
              ),
              if (_pets > 0)
                Positioned(
                  right: 14,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Text('♥ $_pets', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
        Center(
          child: Text(st.name, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w900)),
        ),
        Center(
          child: Text(app.t('chick_stage_${st.stage.clamp(0, 3)}'),
              style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: JuzzioSparklerBar(
            value: progress,
            minHeight: 12,
            backgroundColor: JuzzioGlassTokens.surfaceStrong,
            color: JuzzioGlassTokens.custom?.button ?? JuzzioAppController.instance.glassPalette.swatchA,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          nextXp == null
              ? app.t('chick_max_stage')
              : app.t('chick_xp_progress').replaceAll('{xp}', '${st.xp}').replaceAll('{next}', '$nextXp'),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        // v0.9.3: cam bilgi kartları — tokluk ve büyüme
        Row(
          children: [
            Expanded(
              child: JuzzioGlassStatChip(
                icon: Icons.restaurant_rounded,
                label: app.t('chick_satiety'),
                value: '${((1 - juzzioChickHungerLevel(st.hoursSinceFed)) * 100).round()}%',
                color: moodColor,
                meter: 1 - juzzioChickHungerLevel(st.hoursSinceFed),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: JuzzioGlassStatChip(
                icon: Icons.trending_up_rounded,
                label: app.t('chick_growth'),
                value: '${(progress * 100).round()}%',
                color: const Color(0xFF7C4DFF),
                meter: progress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: CircleAvatar(
            backgroundImage: st.partnerAvatar != null && st.partnerAvatar!.isNotEmpty ? NetworkImage(st.partnerAvatar!) : null,
            child: (st.partnerAvatar == null || st.partnerAvatar!.isEmpty)
                ? Text(st.partnerName.isNotEmpty ? st.partnerName[0].toUpperCase() : '?')
                : null,
          ),
          title: Text(app.t('chick_partner'), style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
          subtitle: Text(st.partnerName, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
          trailing: Text(
            app.t('chick_last_fed').replaceAll('{h}', st.hoursSinceFed.toStringAsFixed(st.hoursSinceFed < 10 ? 1 : 0)),
            style: TextStyle(color: moodColor, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 12),
        JuzzioLiquidGlassButton(
          onTap: (_busy || !st.canFeedNow) ? null : _feed,
          icon: Icons.restaurant_rounded,
          label: st.canFeedNow || st.myNextFeedAt == null ? app.t('chick_feed') : _formatWait(st.myNextFeedAt!),
          tint: st.mood == 'happy' ? const Color(0xFFFFA000) : moodColor,
          loading: _busy,
        ),
        const SizedBox(height: 8),
        Text(app.t('chick_pet_hint'), textAlign: TextAlign.center, style: TextStyle(color: p.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : _confirmRelease,
          child: Text(app.t('chick_release'), style: const TextStyle(color: JuzzioColors.red500)),
        ),
      ],
    );
  }
}
