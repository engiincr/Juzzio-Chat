// =============================================================================
// Juzzio v0.5 — Hikâye emoji çıkartmaları
// Stüdyoda sürükle/büyüt (iki parmak), uzun bas = kaldır; görüntüleyicide aynı
// oransal konumda (x/y 0..1) çizilir. Veri: stories.stickers_json
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';
import 'juzzio_emoji_picker.dart';

const double kJuzzioStickerBaseSize = 56;

/// Tuval üzerine çıkartmaları yerleştirir. [onChanged] verilirse düzenlenebilir.
class JuzzioStickerLayer extends StatefulWidget {
  final List<JuzzioStorySticker> stickers;
  final ValueChanged<List<JuzzioStorySticker>>? onChanged;

  const JuzzioStickerLayer({super.key, required this.stickers, this.onChanged});

  bool get editable => onChanged != null;

  @override
  State<JuzzioStickerLayer> createState() => _JuzzioStickerLayerState();
}

class _JuzzioStickerLayerState extends State<JuzzioStickerLayer> {
  int? _active;
  double _startScale = 1;

  void _update(int index, JuzzioStorySticker next) {
    final list = List<JuzzioStorySticker>.of(widget.stickers);
    if (index < 0 || index >= list.length) return;
    list[index] = next;
    widget.onChanged?.call(list);
  }

  void _remove(int index) {
    final list = List<JuzzioStorySticker>.of(widget.stickers);
    if (index < 0 || index >= list.length) return;
    HapticFeedback.mediumImpact();
    list.removeAt(index);
    widget.onChanged?.call(list);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stickers.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final children = <Widget>[];
        for (var i = 0; i < widget.stickers.length; i++) {
          final st = widget.stickers[i];
          final size = kJuzzioStickerBaseSize * st.scale;
          Widget emoji = SizedBox(
            width: size * 1.35,
            height: size * 1.35,
            child: Center(
              child: Text(
                st.emoji,
                textAlign: TextAlign.center,
                style: juzzioEmojiStyle(size).copyWith(
                  shadows: const [Shadow(color: Color(0x66000000), blurRadius: 10)],
                ),
              ),
            ),
          );
          if (widget.editable) {
            emoji = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _remove(i),
              onScaleStart: (_) {
                _active = i;
                _startScale = st.scale;
              },
              onScaleUpdate: (d) {
                if (_active != i || w <= 0 || h <= 0) return;
                final cur = widget.stickers[i];
                _update(
                  i,
                  cur.copyWith(
                    x: (cur.x + d.focalPointDelta.dx / w).clamp(0.0, 1.0),
                    y: (cur.y + d.focalPointDelta.dy / h).clamp(0.0, 1.0),
                    scale: (d.pointerCount > 1 ? _startScale * d.scale : cur.scale).clamp(0.4, 4.0),
                  ),
                );
              },
              onScaleEnd: (_) => _active = null,
              child: emoji,
            );
          }
          children.add(
            Positioned(
              left: st.x * w - size * 0.675,
              top: st.y * h - size * 0.675,
              child: emoji,
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}

/// Cam alt sayfada emoji seçtirir; seçilen tek emojiyi döndürür.
Future<String?> pickJuzzioStickerEmoji(BuildContext context) async {
  final ctrl = TextEditingController();
  String? picked;
  await showJuzzioGlassSheet<void>(
    context: context,
    builder: (ctx) {
      void onChange() {
        final v = ctrl.text.trim();
        if (v.isNotEmpty && picked == null) {
          picked = v;
          Navigator.of(ctx).pop();
        }
      }

      ctrl.addListener(onChange);
      return JuzzioEmojiPicker(controller: ctrl, height: 360, isDark: true);
    },
  );
  ctrl.dispose();
  return picked;
}
