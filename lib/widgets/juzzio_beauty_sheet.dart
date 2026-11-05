// =============================================================================
// JUZZIO v0.9.3 — Güzelleştirme yoğunluğu sayfası (görüntülü arama + hikâye stüdyosu)
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme_and_locale.dart';

/// Aç/kapat + 1..100 yoğunluk. Değişiklikler canlı bildirilir ([onChanged]: enabled, level).
Future<void> showJuzzioBeautySheet(
  BuildContext context, {
  required bool enabled,
  required int level,
  required void Function(bool enabled, int level) onChanged,
  String? note,
}) {
  final app = JuzzioAppController.instance;
  var on = enabled;
  var lv = level.clamp(1, 100).toDouble();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.25))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(9)))),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(app.loc('Güzelleştirme', 'Beauty', 'Verschönerung'),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    Switch(
                      value: on,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setS(() => on = v);
                        onChanged(on, lv.round());
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(app.loc('Yoğunluk', 'Intensity', 'Intensität'), style: const TextStyle(color: Colors.white70)),
                    const Spacer(),
                    Text('${lv.round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ]),
                  Slider(
                    value: lv,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    onChanged: on ? (v) => setS(() => lv = v) : null,
                    onChangeEnd: on ? (v) => onChanged(true, v.round()) : null,
                  ),
                  Wrap(spacing: 8, children: [
                    for (final preset in [(25, app.loc('Doğal', 'Natural', 'Natürlich')), (50, app.loc('Yumuşak', 'Soft', 'Weich')), (80, app.loc('Güçlü', 'Strong', 'Stark'))])
                      ChoiceChip(
                        label: Text(preset.$2),
                        selected: on && lv.round() == preset.$1,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setS(() {
                            on = true;
                            lv = preset.$1.toDouble();
                          });
                          onChanged(true, preset.$1);
                        },
                      ),
                  ]),
                  if (note != null) ...[
                    const SizedBox(height: 10),
                    Text(note, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
