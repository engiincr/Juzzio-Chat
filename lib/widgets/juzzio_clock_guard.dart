// =============================================================================
// JUZZIO v0.9.4 — Tarih/saat eşitleme uyarısı (tüm sayfaların üstünde)
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_time_sync.dart';

class JuzzioClockGuard extends StatefulWidget {
  const JuzzioClockGuard({super.key, required this.child});
  final Widget child;

  @override
  State<JuzzioClockGuard> createState() => _JuzzioClockGuardState();
}

class _JuzzioClockGuardState extends State<JuzzioClockGuard> with WidgetsBindingObserver {
  final _sync = JuzzioTimeSync.instance;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync.addListener(_onChange);
    // Oturum geri yüklensin diye kısa gecikme
    Future.delayed(const Duration(seconds: 3), () => unawaited(_sync.check(force: true)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {
      if (!_sync.drifted) _dismissed = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sync.check(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final show = _sync.drifted && !_dismissed;
    final app = JuzzioAppController.instance;
    final mins = _sync.offset.inMinutes.abs();
    return Stack(children: [
      widget.child,
      if (show)
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.of(context).padding.top + 8,
          child: Material(
            color: const Color(0xFFB3261E),
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(app.trEn('Tarih ve saatinizi eşitlemeniz gerekiyor', 'Please sync your date and time', 'Bitte Datum und Uhrzeit synchronisieren'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      app.trEn('Cihaz saatiniz ülke saatinden yaklaşık $mins dk farklı. "Otomatik tarih ve saat"i açın.',
                          'Your device clock is about $mins min off. Turn on "Automatic date & time".',
                          'Die Geräteuhr weicht um etwa $mins Min. ab. Aktiviere „Datum/Uhrzeit automatisch".'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ]),
                ),
                TextButton(
                  onPressed: _sync.openDateSettings,
                  child: Text(app.trEn('Ayarlar', 'Settings', 'Einstellungen'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  // Not: burada Overlay yok → tooltip kullanılmaz
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}
