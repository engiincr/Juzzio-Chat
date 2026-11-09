// =============================================================================
// JUZZIO v1.0.0 — Tıklanabilir bağlantılar ve konum kartı
//
//  • JuzzioLinkText    : metindeki web adreslerini, e-postaları ve telefon numaralarını
//                        algılar; dokununca cihazın VARSAYILAN uygulamasında açar
//                        (web → varsayılan tarayıcı, örn. Chrome; mailto → e-posta; tel → arama).
//                        Mesajlar, profil biyografisi, gönderi ve yorumlarda kullanılır.
//  • juzzioOpenLink    : güvenli açıcı (yalnız http/https/mailto/tel/geo; javascript: vb. reddedilir)
//  • juzzioParseLocation / JuzzioLocationCard :
//                        paylaşılan konum mesajını harita önizlemeli karta çevirir;
//                        "Haritada aç" Android'de Google Haritalar (geo:), iOS'ta Apple Haritalar,
//                        "Google Maps" her platformda Google Haritalar'da açar.
// =============================================================================

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

/// Metin içindeki bağlantı bölümü
class JuzzioLinkMatch {
  const JuzzioLinkMatch(this.start, this.end, this.text, this.uri);
  final int start;
  final int end;
  final String text;
  final Uri uri;
}

final RegExp _urlRe = RegExp(
  r'''((?:https?:\/\/|www\.)[^\s<>"'`]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|((?<![\w/])(?:\+|0)\d[\d\s().-]{7,}\d)''',
  caseSensitive: false,
);

/// Bağlantıları bulur (sondaki noktalama işaretleri bağlantıya dahil edilmez). Saf fonksiyon (test edilir).
List<JuzzioLinkMatch> juzzioFindLinks(String text) {
  final out = <JuzzioLinkMatch>[];
  for (final m in _urlRe.allMatches(text)) {
    var raw = m.group(0)!;
    var end = m.end;
    if (m.group(1) != null) {
      // ")" yalnız açılış parantezi varsa dahil; sondaki . , ! ? : ; ' " çıkarılır
      while (raw.isNotEmpty && '.,!?:;\'")]}»'.contains(raw[raw.length - 1])) {
        if (raw.endsWith(')') && '('.allMatches(raw).length > ')'.allMatches(raw).length - 1) break;
        raw = raw.substring(0, raw.length - 1);
        end--;
      }
      final withScheme = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
      final uri = Uri.tryParse(withScheme);
      if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) continue;
      out.add(JuzzioLinkMatch(m.start, end, raw, uri));
    } else if (m.group(2) != null) {
      out.add(JuzzioLinkMatch(m.start, end, raw, Uri(scheme: 'mailto', path: raw)));
    } else if (m.group(3) != null) {
      final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
      if (digits.replaceAll('+', '').length < 10 || digits.replaceAll('+', '').length > 15) continue;
      out.add(JuzzioLinkMatch(m.start, end, raw, Uri(scheme: 'tel', path: digits)));
    }
  }
  return out;
}

const Set<String> _allowedSchemes = {'http', 'https', 'mailto', 'tel', 'geo', 'maps'};

/// Bağlantıyı cihazın varsayılan uygulamasında açar. Başarısızsa false döner.
Future<bool> juzzioOpenLink(Uri uri) async {
  if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return false;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return true;
  } catch (_) {}
  // Harici uygulama bulunamazsa (ör. özel şema) sistem varsayılanı denenir
  try {
    return await launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {
    return false;
  }
}

/// Bağlantıları tıklanabilir gösteren metin (dokun → varsayılan uygulamada açılır).
class JuzzioLinkText extends StatefulWidget {
  const JuzzioLinkText(this.text, {super.key, required this.style, this.linkColor, this.maxLines, this.overflow, this.textAlign});
  final String text;
  final TextStyle style;
  final Color? linkColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  State<JuzzioLinkText> createState() => _JuzzioLinkTextState();
}

class _JuzzioLinkTextState extends State<JuzzioLinkText> {
  final List<GestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final links = juzzioFindLinks(widget.text);
    if (links.isEmpty) {
      return Text(widget.text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow, textAlign: widget.textAlign);
    }
    final linkStyle = widget.style.copyWith(
      color: widget.linkColor ?? JuzzioGlassTokens.glowText,
      decoration: TextDecoration.underline,
      decorationColor: (widget.linkColor ?? JuzzioGlassTokens.glowText).withValues(alpha: 0.6),
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    var i = 0;
    for (final l in links) {
      if (l.start > i) spans.add(TextSpan(text: widget.text.substring(i, l.start)));
      final rec = TapGestureRecognizer()
        ..onTap = () async {
          HapticFeedback.selectionClick();
          final ok = await juzzioOpenLink(l.uri);
          if (!ok && mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
              content: Text(JuzzioAppController.instance.trEn('Bağlantı açılamadı', 'Could not open the link', 'Link konnte nicht geöffnet werden')),
            ));
          }
        };
      _recognizers.add(rec);
      spans.add(TextSpan(text: l.text, style: linkStyle, recognizer: rec, semanticsLabel: l.text));
      i = l.end;
    }
    if (i < widget.text.length) spans.add(TextSpan(text: widget.text.substring(i)));
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}

// ---------------------------------------------------------------------------
// Konum
// ---------------------------------------------------------------------------
class JuzzioGeoPoint {
  const JuzzioGeoPoint(this.lat, this.lng, {this.label = ''});
  final double lat;
  final double lng;
  final String label;
}

final RegExp _geoRe = RegExp(
  r'(?:maps\.google\.[a-z.]+\/\?q=|google\.[a-z.]+\/maps(?:\/search\/\?api=1&query=|\?q=|\/@)|maps\.apple\.com\/\?(?:q=[^&]*&)?ll=|geo:)(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)',
  caseSensitive: false,
);

/// Konum paylaşımı metnini çözer (Juzzio'nun gönderdiği "📍 Konumum + harita bağlantısı" ve
/// harici Google/Apple Haritalar bağlantıları). Konum değilse null. Saf fonksiyon (test edilir).
JuzzioGeoPoint? juzzioParseLocation(String text) {
  final m = _geoRe.firstMatch(text);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1)!);
  final lng = double.tryParse(m.group(2)!);
  if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
  // Konum mesajı kısa olmalı (uzun metindeki bir bağlantı konum kartına dönüşmez)
  final rest = text.replaceAll(RegExp(r'(?:https?:\/\/|geo:)\S+'), '').trim();
  if (rest.length > 80) return null;
  final label = rest.replaceAll('📍', '').trim();
  return JuzzioGeoPoint(lat, lng, label: label);
}

/// Platformun harita uygulaması (Android: geo: → Google Haritalar/seçici, iOS: Apple Haritalar)
Uri juzzioNativeMapUri(JuzzioGeoPoint p) {
  final q = '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';
  final label = Uri.encodeComponent(p.label.isEmpty ? 'Juzzio' : p.label);
  if (!Platform.isIOS) return Uri.parse('geo:$q?q=$q($label)');
  return Uri.parse('https://maps.apple.com/?ll=$q&q=$label');
}

Uri juzzioGoogleMapUri(JuzzioGeoPoint p) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}');

class JuzzioLocationCard extends StatelessWidget {
  const JuzzioLocationCard({super.key, required this.point, required this.isMe});
  final JuzzioGeoPoint point;
  final bool isMe;

  Future<void> _open(BuildContext context, Uri primary, Uri fallback) async {
    HapticFeedback.selectionClick();
    if (await juzzioOpenLink(primary)) return;
    if (await juzzioOpenLink(fallback)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(JuzzioAppController.instance.trEn('Harita açılamadı', 'Could not open maps', 'Karte konnte nicht geöffnet werden')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final fg = isMe ? Colors.white : JuzzioGlassTokens.textPrimary;
    final sub = isMe ? Colors.white70 : JuzzioGlassTokens.textSecondary;
    final glow = JuzzioGlassTokens.glow;
    final coords = '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _open(context, juzzioNativeMapUri(point), juzzioGoogleMapUri(point)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 138,
                width: double.infinity,
                child: CustomPaint(
                  painter: _MiniMapPainter(seed: (point.lat * 1000 + point.lng * 1000).round(), dark: app.isDark, accent: glow),
                  child: Center(child: _Pin(color: glow)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.place_rounded, size: 18, color: isMe ? Colors.white : JuzzioGlassTokens.glowText),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.label.isEmpty ? app.trEn('Paylaşılan konum', 'Shared location', 'Geteilter Standort') : point.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    Text(coords, style: TextStyle(color: sub, fontSize: 11.5, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
              IconButton(
                tooltip: app.trEn('Koordinatları kopyala', 'Copy coordinates', 'Koordinaten kopieren'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_rounded, size: 17, color: sub),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: coords));
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _MapButton(
                  label: Platform.isIOS ? app.trEn('Haritalar', 'Maps', 'Karten') : app.trEn('Haritada aç', 'Open in maps', 'In Karten öffnen'),
                  icon: Icons.map_outlined,
                  filled: true,
                  onTap: () => _open(context, juzzioNativeMapUri(point), juzzioGoogleMapUri(point)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MapButton(
                  label: 'Google Maps',
                  icon: Icons.directions_rounded,
                  filled: false,
                  onTap: () => _open(context, juzzioGoogleMapUri(point), juzzioNativeMapUri(point)),
                  onDark: isMe,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.label, required this.icon, required this.filled, required this.onTap, this.onDark = false});
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? JuzzioGlassTokens.glow : Colors.white.withValues(alpha: onDark ? 0.14 : 0.06);
    final fg = filled ? JuzzioGlassTokens.onGlow : (onDark ? Colors.white : JuzzioGlassTokens.textPrimary);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 16)],
          ),
          child: Icon(Icons.person_pin_circle_rounded, size: 18, color: JuzzioGlassTokens.onGlow),
        ),
        Container(width: 3, height: 10, color: Colors.white),
        Container(
          width: 14,
          height: 5,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }
}

/// Ağ bağlantısı gerektirmeyen stilize harita önizlemesi (yol ağı + park + su), koordinata göre sabit
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({required this.seed, required this.dark, required this.accent});
  final int seed;
  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final land = dark ? const Color(0xFF1B2A26) : const Color(0xFFEDEFE6);
    final park = dark ? const Color(0xFF1F3B2B) : const Color(0xFFD5EBCF);
    final water = dark ? const Color(0xFF173246) : const Color(0xFFBFDDF2);
    final road = dark ? const Color(0xFF34443F) : Colors.white;
    final major = dark ? const Color(0xFF4C5E57) : const Color(0xFFFFE6A8);
    canvas.drawRect(Offset.zero & size, Paint()..color = land);
    // su ve park lekeleri
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * (0.55 + rnd.nextDouble() * 0.3))
        ..quadraticBezierTo(size.width * 0.3, size.height * (0.6 + rnd.nextDouble() * 0.3), size.width * 0.5, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = water,
    );
    for (var i = 0; i < 2; i++) {
      final r = Rect.fromLTWH(rnd.nextDouble() * size.width * 0.8, rnd.nextDouble() * size.height * 0.6, 40 + rnd.nextDouble() * 50, 26 + rnd.nextDouble() * 30);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = park);
    }
    final rp = Paint()
      ..color = road
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = rnd.nextDouble() * size.height;
      canvas.drawLine(Offset(-10, y), Offset(size.width + 10, y + (rnd.nextDouble() - 0.5) * 40), rp);
    }
    for (var i = 0; i < 6; i++) {
      final x = rnd.nextDouble() * size.width;
      canvas.drawLine(Offset(x, -10), Offset(x + (rnd.nextDouble() - 0.5) * 40, size.height + 10), rp);
    }
    canvas.drawLine(
      Offset(-10, size.height * 0.35),
      Offset(size.width + 10, size.height * 0.62),
      Paint()
        ..color = major
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    // konum çevresinde yumuşak vurgu ışıması
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      46,
      Paint()
        ..shader = RadialGradient(colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: 46)),
    );
  }

  @override
  bool shouldRepaint(_MiniMapPainter o) => o.seed != seed || o.dark != dark || o.accent != accent;
}
