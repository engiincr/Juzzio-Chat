// =============================================================================
// JUZZIO v0.9.0 — Sohbet kilidi arayüzü (§4.6): PIN girişi / PIN oluşturma, Sohbet Bilgileri >
// Gizlilik > "Sohbeti Kilitle" anahtarı. Kilitleme sohbetin bildirim önizlemesini sunucuda
// 'gizli' yapar; kilit kaldırılınca cihaz ayarına döner.
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_chat_lock.dart';
import '../services/supabase_service.dart';
import 'juzzio_motion.dart';

/// PIN ister; doğrulanırsa true.
/// v1.2.8: yazı alanı YOK — dokunmatik tuş takımı. PIN hiç belirlenmediyse varsayılan PIN
/// 0000'dır; 0000 girilince hemen yeni PIN (en az 4 rakam) belirletilir. [allowCreate]
/// geriye dönük uyumluluk için durur (varsayılan PIN her zaman kullanılabilir).
Future<bool> juzzioRequireChatPin(BuildContext context, {bool allowCreate = true}) async {
  final lock = JuzzioChatLock.instance;
  if (!lock.loaded) await lock.load();
  if (lock.isUnlocked) return true;
  final has = await lock.hasPin();
  final len = await lock.pinLength();
  if (!context.mounted) return false;
  final app = JuzzioAppController.instance;
  final ok = await showJuzzioPinPad(
    context,
    title: app.trEn('Kilitli sohbetler', 'Locked chats', 'Gesperrte Chats'),
    subtitle: has
        ? app.trEn('Uygulama PIN\'ini gir', 'Enter your app PIN', 'App-PIN eingeben')
        : app.trEn('Henüz PIN belirlemedin: varsayılan PIN 0000', 'No PIN set yet: the default PIN is 0000',
            'Noch keine PIN: Standard-PIN ist 0000'),
    autoLength: len,
    verify: lock.unlock,
  );
  if (ok == null || !context.mounted) return false;
  if (has) return true;
  // varsayılan PIN ile girildi → yeni PIN belirle (iki kez)
  final first = await showJuzzioPinPad(
    context,
    title: app.trEn('Yeni PIN belirle', 'Set a new PIN', 'Neue PIN festlegen'),
    step: 1,
    subtitle: app.trEn('En az 4 rakam. Bitince ✓\'ye dokun.', 'At least 4 digits. Tap ✓ when done.', 'Mindestens 4 Ziffern. Dann ✓.'),
    verify: (pin) async => JuzzioChatLockMath.validPin(pin) && pin != JuzzioChatLock.defaultPin,
    errorText: app.trEn('PIN 4–8 rakam olmalı ve 0000 olamaz', 'PIN must be 4–8 digits and not 0000', 'PIN 4–8 Ziffern, nicht 0000'),
  );
  if (first == null || !context.mounted) return false;
  final again = await showJuzzioPinPad(
    context,
    title: app.trEn('PIN\'i tekrar gir', 'Repeat the PIN', 'PIN wiederholen'),
    step: 1,
    autoLength: first.length,
    verify: (pin) async => pin == first,
    errorText: app.trEn('PIN\'ler eşleşmiyor', 'PINs do not match', 'PINs stimmen nicht überein'),
  );
  if (again == null) return false;
  await lock.setPin(first);
  await lock.unlock(first); // yeni PIN ile açık say
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(app.trEn('Yeni PIN kaydedildi.', 'New PIN saved.', 'Neue PIN gespeichert.')),
    ));
  }
  return true;
}

/// v1.2.8 — dokunmatik PIN tuş takımı. Doğrulanan PIN'i döndürür (vazgeçilirse null).
/// [autoLength] verilirse o hanede kendiliğinden dener; aksi hâlde ✓ ile onaylanır.
/// v1.2.9: "Tam doğrulama akışı" tasarımı — grafit zemin, limon yeşili/mercan ışık lekeleri,
/// cam kart, 3 adımlı ilerleme (Kimlik · Doğrula · Açıldı), kod kutuları, doğrulanıyor halkası ve
/// "Doğrulandı" onay ekranı. [step] 0 = giriş, 1 = yeni PIN, 2 = tekrar.
Future<String?> showJuzzioPinPad(
  BuildContext context, {
  required String title,
  String? subtitle,
  int? autoLength,
  required Future<bool> Function(String pin) verify,
  String? errorText,
  int step = 0,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // v1.2.9 düzeltme: TAM EKRAN — temadan gelen beyaz kenar çizgisi, yuvarlak köşe ve üstteki boşluk yok
      backgroundColor: JuzzioAuthPalette.graphite,
      barrierColor: JuzzioAuthPalette.graphite,
      elevation: 0,
      useSafeArea: false,
      enableDrag: false,
      clipBehavior: Clip.hardEdge,
      shape: const RoundedRectangleBorder(side: BorderSide.none, borderRadius: BorderRadius.zero),
      constraints: const BoxConstraints(minWidth: double.infinity, maxWidth: double.infinity),
      builder: (_) => _PinPad(title: title, subtitle: subtitle, autoLength: autoLength, verify: verify, errorText: errorText, step: step),
    );

/// Tasarım renkleri (videodaki "Trending palette": Graphite · Lime · Bone · Smoke · Coral)
class JuzzioAuthPalette {
  static const graphite = Color(0xFF0C0D0A);
  static const lime = Color(0xFFC6F432);
  static const bone = Color(0xFFF1EDE3);
  static const smoke = Color(0xFF8D8D86);
  static const coral = Color(0xFFFF6A45);
}

class _PinPad extends StatefulWidget {
  const _PinPad({required this.title, this.subtitle, this.autoLength, required this.verify, this.errorText, this.step = 0});
  final String title;
  final String? subtitle;
  final int? autoLength;
  final Future<bool> Function(String pin) verify;
  final String? errorText;
  final int step;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> with TickerProviderStateMixin {
  String _pin = '';
  String? _err;
  bool _busy = false;
  bool _done = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);

  @override
  void dispose() {
    _shake.dispose();
    _spin.dispose();
    _glow.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _done || _pin.length < 4) return;
    setState(() => _busy = true);
    _spin.repeat();
    final started = DateTime.now();
    final ok = await widget.verify(_pin);
    // "doğrulanıyor" halkası en az 450 ms görünür (göz algısı)
    final wait = 450 - DateTime.now().difference(started).inMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    _spin.stop();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _done = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (mounted) Navigator.pop(context, _pin);
      return;
    }
    final app = JuzzioAppController.instance;
    final until = JuzzioChatLock.instance.blockedUntil;
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _busy = false;
      _pin = '';
      _err = until != null && until.isAfter(DateTime.now())
          ? app.trEn('Çok fazla hatalı deneme. ${until.difference(DateTime.now()).inSeconds + 1} sn bekle.',
              'Too many attempts. Wait ${until.difference(DateTime.now()).inSeconds + 1}s.',
              'Zu viele Versuche. ${until.difference(DateTime.now()).inSeconds + 1} s warten.')
          : (widget.errorText ?? app.trEn('PIN hatalı', 'Wrong PIN', 'Falsche PIN'));
    });
  }

  void _tap(String d) {
    if (_busy || _done || _pin.length >= 8) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _err = null;
    });
    if (widget.autoLength != null && _pin.length == widget.autoLength) _submit();
  }

  void _back() {
    if (_busy || _done || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Widget _stepper(JuzzioAppController app) {
    final labels = [
      app.trEn('Kimlik', 'Account', 'Konto'),
      app.trEn('Doğrula', 'Verify', 'Prüfen'),
      app.trEn('Açıldı', 'Done', 'Fertig'),
    ];
    final current = _done ? 2 : (_busy ? 1 : (widget.step > 0 ? 1 : 0));
    Widget node(int i) {
      final passed = i < current || (_done && i == 2);
      final active = i == current;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: passed || active ? JuzzioAuthPalette.lime : Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: passed || active ? JuzzioAuthPalette.lime : Colors.white24),
          ),
          alignment: Alignment.center,
          child: passed
              ? const Icon(Icons.check_rounded, size: 13, color: JuzzioAuthPalette.graphite)
              : Text('${i + 1}', style: TextStyle(color: active ? JuzzioAuthPalette.graphite : Colors.white54, fontSize: 11, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 6),
        Text(labels[i], style: TextStyle(color: active || passed ? Colors.white : Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]);
    }

    Widget line(int i) => Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 1.6,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: i < current ? JuzzioAuthPalette.lime : Colors.white12,
          ),
        );
    return Row(children: [node(0), line(0), node(1), line(1), node(2)]);
  }

  Widget _boxes() {
    final count = widget.autoLength ?? (_pin.length < 4 ? 4 : (_pin.length < 8 ? _pin.length + 1 : 8));
    return AnimatedBuilder(
      animation: _shake,
      builder: (_, child) => Transform.translate(
          offset: Offset(12 * (1 - _shake.value) * (((_shake.value * 6).floor().isEven) ? 1 : -1) * (_shake.isAnimating ? 1 : 0), 0), child: child),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: count > 6 ? 32 : 40,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i < _pin.length ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _err != null
                      ? JuzzioAuthPalette.coral
                      : (i == _pin.length ? JuzzioAuthPalette.lime : Colors.white.withValues(alpha: 0.16)),
                  width: i == _pin.length ? 1.8 : 1.1,
                ),
                boxShadow: i == _pin.length && _err == null
                    ? [BoxShadow(color: JuzzioAuthPalette.lime.withValues(alpha: 0.35), blurRadius: 14)]
                    : null,
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: i < _pin.length
                    ? Container(
                        key: const ValueKey('f'),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: JuzzioAuthPalette.bone, shape: BoxShape.circle))
                    : const SizedBox(key: ValueKey('e')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(Widget child, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Material(
          color: Colors.white.withValues(alpha: onTap == null ? 0.0 : 0.07),
          shape: const CircleBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: JuzzioAuthPalette.lime.withValues(alpha: 0.25),
            onTap: onTap,
            child: SizedBox(width: 68, height: 68, child: Center(child: child)),
          ),
        ),
      );

  Widget _verified(JuzzioAppController app) {
    Widget chip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: JuzzioAuthPalette.lime.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: JuzzioAuthPalette.lime.withValues(alpha: 0.4))),
          child: Text('✓ $t', style: const TextStyle(color: JuzzioAuthPalette.lime, fontSize: 11, fontWeight: FontWeight.w800)),
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: JuzzioAuthPalette.lime, width: 2.4),
            boxShadow: [BoxShadow(color: JuzzioAuthPalette.lime.withValues(alpha: 0.4), blurRadius: 28)],
          ),
          child: const Icon(Icons.check_rounded, color: JuzzioAuthPalette.lime, size: 42),
        ),
        const SizedBox(height: 14),
        Text(app.trEn('Doğrulandı', "You're verified", 'Bestätigt'),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          chip(app.trEn('PIN korumalı', 'PIN protected', 'PIN-geschützt')),
          chip(app.trEn('Uçtan uca şifreli', 'End-to-end encrypted', 'E2E-verschlüsselt')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    Widget digit(String d) =>
        _key(Text(d, style: const TextStyle(color: JuzzioAuthPalette.bone, fontSize: 26, fontWeight: FontWeight.w600)), () => _tap(d));
    final h = MediaQuery.of(context).size.height;
    return ClipRect(
      child: Container(
        height: h,
        width: double.infinity,
        color: JuzzioAuthPalette.graphite,
        child: Stack(children: [
          // limon ve mercan ışık lekeleri (yavaşça nefes alır)
          AnimatedBuilder(
            animation: _glow,
            builder: (_, __) => Stack(children: [
              Positioned(
                top: -90 + 30 * _glow.value,
                left: -60,
                child: _blob(JuzzioAuthPalette.lime, 300, 0.28 + 0.08 * _glow.value),
              ),
              Positioned(
                bottom: 40 - 30 * _glow.value,
                right: -80,
                child: _blob(JuzzioAuthPalette.coral, 280, 0.20 + 0.06 * (1 - _glow.value)),
              ),
            ]),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          _stepper(app),
                          const SizedBox(height: 18),
                          if (_done)
                            Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: _verified(app)))
                          else ...[
                            Text(widget.title,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 6),
                              Text(widget.subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                            ],
                            const SizedBox(height: 18),
                            _boxes(),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 22,
                              child: Row(children: [
                                if (_busy) ...[
                                  RotationTransition(
                                    turns: _spin,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: JuzzioAuthPalette.lime, width: 2),
                                      ),
                                      child: const Align(alignment: Alignment.topCenter, child: SizedBox(width: 4, height: 4, child: ColoredBox(color: JuzzioAuthPalette.graphite))),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(app.trEn('Doğrulanıyor…', 'Verifying…', 'Wird geprüft…'),
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                                ] else if (_err != null)
                                  Expanded(
                                    child: Text(_err!,
                                        style: const TextStyle(color: JuzzioAuthPalette.coral, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  )
                                else
                                  Text(app.trEn('Uçtan uca şifreli · PIN cihazında tutulur', 'End-to-end encrypted · PIN stays on device',
                                      'E2E-verschlüsselt · PIN bleibt auf dem Gerät'),
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5)),
                              ]),
                            ),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                IgnorePointer(
                  ignoring: _done,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _done ? 0.25 : 1,
                    child: Column(children: [
                      for (final row in const [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                      ])
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) digit(d)]),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _key(const Icon(Icons.backspace_outlined, color: Colors.white70), _pin.isEmpty ? null : _back),
                        digit('0'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          child: Material(
                            color: _pin.length >= 4 ? JuzzioAuthPalette.lime : Colors.white.withValues(alpha: 0.05),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _pin.length >= 4 ? _submit : null,
                              child: SizedBox(
                                width: 68,
                                height: 68,
                                child: Icon(Icons.arrow_forward_rounded,
                                    color: _pin.length >= 4 ? JuzzioAuthPalette.graphite : Colors.white24, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(app.trEn('Vazgeç', 'Cancel', 'Abbrechen'), style: const TextStyle(color: Colors.white60)),
                ),
              ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _blob(Color c, double size, double alpha) => IgnorePointer(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(width: size, height: size, decoration: BoxDecoration(color: c.withValues(alpha: alpha), shape: BoxShape.circle)),
        ),
      );
}

/// Sohbet Bilgileri > Gizlilik > "Sohbeti Kilitle"
class JuzzioChatLockTile extends StatefulWidget {
  const JuzzioChatLockTile({super.key, required this.roomId});
  final String roomId;

  @override
  State<JuzzioChatLockTile> createState() => _JuzzioChatLockTileState();
}

class _JuzzioChatLockTileState extends State<JuzzioChatLockTile> {
  @override
  void initState() {
    super.initState();
    if (!JuzzioChatLock.instance.loaded) JuzzioChatLock.instance.load();
  }

  Future<void> _toggle(bool lock) async {
    final app = JuzzioAppController.instance;
    if (!await juzzioRequireChatPin(context)) return;
    await JuzzioChatLock.instance.setLocked(widget.roomId, lock);
    try {
      // Kilitli sohbetin bildirimi içerik/gönderen göstermez (sunucuda, tüm cihazlarda)
      await SupabaseService.instance.setRoomNotificationPrefs(widget.roomId, preview: lock ? 'hidden' : 'inherit');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(app.trEn('Sohbet kilitlendi, ancak bildirim önizlemesi güncellenemedi.',
              'Chat locked, but the notification preview could not be updated.', 'Chat gesperrt, Vorschau konnte nicht aktualisiert werden.')),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    return ListenableBuilder(
      listenable: JuzzioChatLock.instance,
      builder: (context, _) => JuzzioSwitchListTile(style: JuzzioToggleStyle.check,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        secondary: Icon(Icons.lock_person_rounded, color: p.textPrimary),
        title: Text(app.trEn('Sohbeti Kilitle', 'Lock chat', 'Chat sperren'),
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800)),
        subtitle: Text(
          app.trEn('Listede gizlenir, PIN ile açılır; bildirim içeriği gösterilmez.',
              'Hidden from the list, opened with PIN; notification content hidden.',
              'In der Liste verborgen, mit PIN geöffnet; Mitteilungsinhalt verborgen.'),
          style: TextStyle(color: p.textSecondary, fontSize: 12),
        ),
        value: JuzzioChatLock.instance.isLocked(widget.roomId),
        onChanged: _toggle,
      ),
    );
  }
}
