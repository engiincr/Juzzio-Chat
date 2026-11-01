// =============================================================================
// JUZZIO v0.8.2 — HEX / RGB / HSL renk seçici (paket gerektirmez)
// Üç gösterim de aynı rengi düzenler ve birbirleriyle anında eşitlenir.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/theme/juzzio_custom_theme.dart';
import '../../core/theme/juzzio_glass.dart';

/// Renk seçici alt penceresini açar. İptal → null.
Future<Color?> showJuzzioColorPicker(
  BuildContext context, {
  required Color initial,
  required String title,
  bool allowAlpha = false,
  Color? contrastAgainst,
}) {
  return showJuzzioGlassSheet<Color>(
    context: context,
    builder: (_) => _JuzzioColorPickerBody(
      initial: initial,
      title: title,
      allowAlpha: allowAlpha,
      contrastAgainst: contrastAgainst,
    ),
  );
}

class _JuzzioColorPickerBody extends StatefulWidget {
  final Color initial;
  final String title;
  final bool allowAlpha;
  final Color? contrastAgainst;
  const _JuzzioColorPickerBody({required this.initial, required this.title, required this.allowAlpha, this.contrastAgainst});

  @override
  State<_JuzzioColorPickerBody> createState() => _JuzzioColorPickerBodyState();
}

enum _Mode { hex, rgb, hsl }

class _JuzzioColorPickerBodyState extends State<_JuzzioColorPickerBody> {
  late Color _c = widget.allowAlpha ? widget.initial : widget.initial.withValues(alpha: 1);
  _Mode _mode = _Mode.hex;
  late final TextEditingController _hex = TextEditingController(text: JuzzioCustomTheme.toHex(_c));
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int _ch(double v) => (v * 255).round().clamp(0, 255);

  void _set(Color c, {bool fromHex = false}) {
    setState(() {
      _c = widget.allowAlpha ? c : c.withValues(alpha: 1);
      if (!fromHex) {
        _hex.text = JuzzioCustomTheme.toHex(_c);
        _hexError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final t = JuzzioGlassTokens.textPrimary;
    final t2 = JuzzioGlassTokens.textSecondary;
    final hsl = HSLColor.fromColor(_c);
    final ratio = widget.contrastAgainst == null
        ? null
        : JuzzioCustomTheme.contrastRatio(_c.withValues(alpha: 1), widget.contrastAgainst!.withValues(alpha: 1));

    Widget slider(String label, double value, double max, ValueChanged<double> onChanged, {String? suffix}) => Row(
          children: [
            SizedBox(width: 34, child: Text(label, style: TextStyle(color: t2, fontWeight: FontWeight.w800))),
            Expanded(
              child: Slider(
                value: value.clamp(0, max).toDouble(),
                min: 0,
                max: max,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text('${value.round()}${suffix ?? ''}',
                  textAlign: TextAlign.end, style: TextStyle(color: t, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ],
        );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: TextStyle(color: t, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _c,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: JuzzioGlassTokens.borderStrong),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(JuzzioCustomTheme.toHex(_c), style: TextStyle(color: t, fontWeight: FontWeight.w900, fontSize: 16)),
                Text('RGB ${_ch(_c.r)}, ${_ch(_c.g)}, ${_ch(_c.b)}', style: TextStyle(color: t2, fontSize: 12)),
                Text('HSL ${hsl.hue.round()}°, ${(hsl.saturation * 100).round()}%, ${(hsl.lightness * 100).round()}%',
                    style: TextStyle(color: t2, fontSize: 12)),
                if (ratio != null)
                  Text(
                    '${app.trEn('Kontrast', 'Contrast', 'Kontrast')} ${ratio.toStringAsFixed(1)}:1 '
                    '${ratio >= 4.5 ? '✓ AA' : (ratio >= 3 ? '• ${app.trEn('büyük metin', 'large text', 'großer Text')}' : '⚠ ${app.trEn('düşük', 'low', 'niedrig')}')}',
                    style: TextStyle(
                      color: ratio >= 4.5 ? const Color(0xFF34C759) : (ratio >= 3 ? t2 : const Color(0xFFFF647B)),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.hex, label: Text('HEX')),
              ButtonSegment(value: _Mode.rgb, label: Text('RGB')),
              ButtonSegment(value: _Mode.hsl, label: Text('HSL')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          const SizedBox(height: 12),
          if (_mode == _Mode.hex)
            TextField(
              controller: _hex,
              style: TextStyle(color: t, fontWeight: FontWeight.w700, letterSpacing: 1),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                labelText: widget.allowAlpha ? '#RRGGBB / #AARRGGBB' : '#RRGGBB',
                errorText: _hexError,
              ),
              onChanged: (v) {
                final parsed = JuzzioCustomTheme.parseHex(v);
                if (parsed == null) {
                  setState(() => _hexError = app.trEn('Geçersiz HEX', 'Invalid HEX', 'Ungültiger HEX'));
                } else {
                  _hexError = null;
                  _set(parsed, fromHex: true);
                }
              },
            ),
          if (_mode == _Mode.rgb) ...[
            slider('R', _ch(_c.r).toDouble(), 255, (v) => _set(Color.fromARGB(_ch(_c.a), v.round(), _ch(_c.g), _ch(_c.b)))),
            slider('G', _ch(_c.g).toDouble(), 255, (v) => _set(Color.fromARGB(_ch(_c.a), _ch(_c.r), v.round(), _ch(_c.b)))),
            slider('B', _ch(_c.b).toDouble(), 255, (v) => _set(Color.fromARGB(_ch(_c.a), _ch(_c.r), _ch(_c.g), v.round()))),
          ],
          if (_mode == _Mode.hsl) ...[
            slider('H', hsl.hue, 360, (v) => _set(hsl.withHue(v.clamp(0.0, 359.9)).toColor()), suffix: '°'),
            slider('S', hsl.saturation * 100, 100, (v) => _set(hsl.withSaturation(v / 100).toColor()), suffix: '%'),
            slider('L', hsl.lightness * 100, 100, (v) => _set(hsl.withLightness(v / 100).toColor()), suffix: '%'),
          ],
          if (widget.allowAlpha)
            slider('A', _c.a * 100, 100, (v) => _set(_c.withValues(alpha: v / 100)), suffix: '%'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(app.trEn('İptal', 'Cancel', 'Abbrechen')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _hexError != null ? null : () => Navigator.of(context).pop(_c),
                child: Text(app.trEn('Seç', 'Select', 'Wählen')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
