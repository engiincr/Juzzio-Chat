// =============================================================================
// JUZZIO v1.2.9 — Hareketli "GIF" çıkartmalar (yazısız, komik, %100 özgün)
//  • Telif riski yok: hiçbir dış GIF/çizim kullanılmaz; her çıkartma Juzzio'nun kendi
//    animasyon motoruyla (emoji yazı tipi + kod ile çizilen efektler) oynatılır.
//    Emoji yazı tipi Noto Color Emoji (SIL OFL 1.1) — bkz. docs/ASSET_LICENSES.md
//  • Sözcük yok: yalnız ifade + hareket (uykulu, kahkaha, dans, utanç…)
//  • Aranabilir: etiketler trEn ile yazılır → l10n aracı tüm uygulama dillerine çevirir,
//    böylece her ülke kendi dilinde arayabilir.
//  • Mesaj biçimi: "[[jgif:<kimlik>]]" — uçtan uca şifreli metin olarak gider; alıcı cihazda
//    balonsuz, büyük ve döngüde oynatılır. Bilinmeyen kimlik → düz metin (geriye uyumlu).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

/// Çıkartma hareket türleri (her biri kodla çizilir)
enum JuzzioGifFx {
  sleepy, // yavaş sallanma + yükselen Z'ler
  laugh, // hızlı titreme + gözyaşı damlaları
  love, // nabız + yükselen kalpler
  cry, // aşağı akan gözyaşları
  party, // zıplama + konfeti
  dance, // sağa sola dans
  shock, // büyüyüp sarsılma + şimşek
  angry, // kırmızı titreşim + buhar
  cool, // yavaş kayma + parıltı
  shy, // küçülüp saklanma + pembe yanak halkası
  spin, // dönme
  bounce, // top gibi zıplama
  wave, // el sallama (döndürerek)
  hungry, // çiğneme (dikey ezilme) + parçacıklar
  think, // eğilip baloncuk
  rain, // üstte yağmur bulutu damlaları
  fire, // titreşen alevler
  ghost, // yüzme + saydamlaşma
}

class JuzzioGifSpec {
  const JuzzioGifSpec(this.id, this.emoji, this.fx, this.tags);
  final String id;
  final String emoji;
  final JuzzioGifFx fx;

  /// Aranabilir etiketler (uygulama dilinde) — tembel üretilir
  final String Function(JuzzioAppController app) tags;
}

/// 42 çıkartma — kimlikler kalıcıdır (gönderilmiş mesajlar bunlara başvurur), DEĞİŞTİRMEYİN
final List<JuzzioGifSpec> kJuzzioGifs = <JuzzioGifSpec>[
  JuzzioGifSpec('sleepy', '😴', JuzzioGifFx.sleepy, (a) => a.trEn('uyku uykulu uyuyacağım iyi geceler yorgun', 'sleep sleepy going to bed good night tired')),
  JuzzioGifSpec('yawn', '🥱', JuzzioGifFx.sleepy, (a) => a.trEn('esneme uykum geldi sıkıldım', 'yawn sleepy bored')),
  JuzzioGifSpec('sleep_cat', '😽', JuzzioGifFx.sleepy, (a) => a.trEn('kedi uyku şekerleme', 'cat nap sleep')),
  JuzzioGifSpec('moon_night', '🌛', JuzzioGifFx.sleepy, (a) => a.trEn('gece ay iyi geceler', 'night moon good night')),
  JuzzioGifSpec('lol', '🤣', JuzzioGifFx.laugh, (a) => a.trEn('kahkaha gülmek komik çok komik', 'laugh lol funny hilarious')),
  JuzzioGifSpec('joy', '😂', JuzzioGifFx.laugh, (a) => a.trEn('gülmekten ağlamak komik', 'tears of joy funny')),
  JuzzioGifSpec('cat_laugh', '😹', JuzzioGifFx.laugh, (a) => a.trEn('kedi gülüyor komik', 'cat laughing funny')),
  JuzzioGifSpec('monkey', '🙈', JuzzioGifFx.shy, (a) => a.trEn('maymun utanmak görmedim', 'monkey shy did not see')),
  JuzzioGifSpec('blush', '😊', JuzzioGifFx.shy, (a) => a.trEn('utangaç kızarmak teşekkür', 'blush shy thanks')),
  JuzzioGifSpec('peek', '🫣', JuzzioGifFx.shy, (a) => a.trEn('gizlice bakmak utanç', 'peek shy hide')),
  JuzzioGifSpec('love', '🥰', JuzzioGifFx.love, (a) => a.trEn('aşk sevgi seni seviyorum kalp', 'love hearts adore')),
  JuzzioGifSpec('heart_eyes', '😍', JuzzioGifFx.love, (a) => a.trEn('aşık hayran harika', 'heart eyes crush')),
  JuzzioGifSpec('kiss', '😘', JuzzioGifFx.love, (a) => a.trEn('öpücük öpmek', 'kiss smooch')),
  JuzzioGifSpec('heart', '❤️', JuzzioGifFx.love, (a) => a.trEn('kalp sevgi', 'heart love')),
  JuzzioGifSpec('cry', '😭', JuzzioGifFx.cry, (a) => a.trEn('ağlamak hüzün üzgün', 'cry sob sad')),
  JuzzioGifSpec('pleading', '🥺', JuzzioGifFx.cry, (a) => a.trEn('lütfen rica yalvarmak', 'please pleading puppy eyes')),
  JuzzioGifSpec('sad_cat', '😿', JuzzioGifFx.cry, (a) => a.trEn('üzgün kedi', 'sad cat')),
  JuzzioGifSpec('party', '🥳', JuzzioGifFx.party, (a) => a.trEn('parti kutlama doğum günü tebrikler', 'party celebrate birthday congrats')),
  JuzzioGifSpec('tada', '🎉', JuzzioGifFx.party, (a) => a.trEn('tebrikler yaşasın', 'congrats hooray')),
  JuzzioGifSpec('cake', '🎂', JuzzioGifFx.party, (a) => a.trEn('pasta doğum günü', 'cake birthday')),
  JuzzioGifSpec('dance', '💃', JuzzioGifFx.dance, (a) => a.trEn('dans eğlence oyna', 'dance fun party')),
  JuzzioGifSpec('dance_man', '🕺', JuzzioGifFx.dance, (a) => a.trEn('dans disko', 'dance disco')),
  JuzzioGifSpec('penguin', '🐧', JuzzioGifFx.dance, (a) => a.trEn('penguen dans sevimli', 'penguin dance cute')),
  JuzzioGifSpec('shock', '😱', JuzzioGifFx.shock, (a) => a.trEn('şok korku çığlık inanamıyorum', 'shock scream omg')),
  JuzzioGifSpec('mind_blown', '🤯', JuzzioGifFx.shock, (a) => a.trEn('beyin yandı şaşkın inanılmaz', 'mind blown wow')),
  JuzzioGifSpec('wow', '😮', JuzzioGifFx.shock, (a) => a.trEn('vay şaşırmak', 'wow surprised')),
  JuzzioGifSpec('angry', '😡', JuzzioGifFx.angry, (a) => a.trEn('kızgın sinirli öfke', 'angry mad rage')),
  JuzzioGifSpec('huff', '😤', JuzzioGifFx.angry, (a) => a.trEn('hırs inat burnundan solumak', 'huff triumph stubborn')),
  JuzzioGifSpec('cool', '😎', JuzzioGifFx.cool, (a) => a.trEn('havalı karizma rahat', 'cool chill swag')),
  JuzzioGifSpec('star', '🤩', JuzzioGifFx.cool, (a) => a.trEn('harika muhteşem yıldız', 'amazing star struck')),
  JuzzioGifSpec('dizzy', '😵‍💫', JuzzioGifFx.spin, (a) => a.trEn('başım döndü sersem', 'dizzy confused')),
  JuzzioGifSpec('upside', '🙃', JuzzioGifFx.spin, (a) => a.trEn('ters şaka ironi', 'upside down silly')),
  JuzzioGifSpec('ball', '⚽', JuzzioGifFx.bounce, (a) => a.trEn('futbol top maç gol', 'football soccer goal')),
  JuzzioGifSpec('chick', '🐥', JuzzioGifFx.bounce, (a) => a.trEn('civciv sevimli zıpla', 'chick cute hop')),
  JuzzioGifSpec('bunny', '🐰', JuzzioGifFx.bounce, (a) => a.trEn('tavşan zıplamak sevimli', 'bunny hop cute')),
  JuzzioGifSpec('hello', '👋', JuzzioGifFx.wave, (a) => a.trEn('merhaba selam görüşürüz bay bay', 'hello hi bye wave')),
  JuzzioGifSpec('yum', '😋', JuzzioGifFx.hungry, (a) => a.trEn('lezzetli acıktım yemek', 'yummy hungry food')),
  JuzzioGifSpec('pizza', '🍕', JuzzioGifFx.hungry, (a) => a.trEn('pizza yemek acıktım', 'pizza food hungry')),
  JuzzioGifSpec('think', '🤔', JuzzioGifFx.think, (a) => a.trEn('düşünmek hmm emin değilim', 'think hmm not sure')),
  JuzzioGifSpec('rainy', '😔', JuzzioGifFx.rain, (a) => a.trEn('moral bozuk kasvetli yağmur', 'gloomy down rainy mood')),
  JuzzioGifSpec('fire', '🔥', JuzzioGifFx.fire, (a) => a.trEn('ateş harika süper sıcak', 'fire lit hot awesome')),
  JuzzioGifSpec('ghost', '👻', JuzzioGifFx.ghost, (a) => a.trEn('hayalet kayboldum boo', 'ghost boo ghosted')),
];

final Map<String, JuzzioGifSpec> _byId = {for (final g in kJuzzioGifs) g.id: g};

final RegExp _tokenRe = RegExp(r'^\[\[jgif:([a-z0-9_]{1,32})\]\]$');

/// Mesaj metni bir çıkartma mı? (saf; test edilir)
JuzzioGifSpec? juzzioGifFromText(String text) {
  final m = _tokenRe.firstMatch(text.trim());
  if (m == null) return null;
  return _byId[m.group(1)!];
}

String juzzioGifToken(String id) => '[[jgif:$id]]';

/// Sohbet listesi/bildirim önizlemesi: belirteç yerine "🎞️ GIF 😴"
String juzzioGifPreview(String text) {
  final g = juzzioGifFromText(text);
  return g == null ? text : '🎞️ GIF ${g.emoji}';
}

/// Aramayla eşleşen çıkartmalar (etiketler uygulama dilinde + emojinin kendisi)
List<JuzzioGifSpec> juzzioSearchGifs(String query, JuzzioAppController app) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kJuzzioGifs;
  return kJuzzioGifs.where((g) => g.tags(app).toLowerCase().contains(q) || g.id.contains(q) || g.emoji == q).toList();
}

/// Döngüde oynayan çıkartma. [play] false ise ilk karede durur (performans modu / arka plan).
class JuzzioGifSticker extends StatefulWidget {
  const JuzzioGifSticker({super.key, required this.spec, this.size = 120, this.play = true});
  final JuzzioGifSpec spec;
  final double size;
  final bool play;

  @override
  State<JuzzioGifSticker> createState() => _JuzzioGifStickerState();
}

class _JuzzioGifStickerState extends State<JuzzioGifSticker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _durFor(widget.spec.fx));

  static Duration _durFor(JuzzioGifFx fx) => switch (fx) {
        JuzzioGifFx.laugh || JuzzioGifFx.angry || JuzzioGifFx.fire => const Duration(milliseconds: 900),
        JuzzioGifFx.spin => const Duration(milliseconds: 1600),
        JuzzioGifFx.sleepy || JuzzioGifFx.ghost || JuzzioGifFx.rain => const Duration(milliseconds: 2600),
        _ => const Duration(milliseconds: 1400),
      };

  bool get _shouldPlay => widget.play && !JuzzioGlassTokens.reducedEffects && !JuzzioAppController.instance.reduceMotion;

  @override
  void initState() {
    super.initState();
    if (_shouldPlay) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant JuzzioGifSticker old) {
    super.didUpdateWidget(old);
    if (_shouldPlay && !_c.isAnimating) _c.repeat();
    if (!_shouldPlay && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final face = Text(widget.spec.emoji, style: juzzioEmojiStyle(s * 0.56));
            return CustomPaint(
              painter: _GifFxPainter(fx: widget.spec.fx, t: t, back: true),
              foregroundPainter: _GifFxPainter(fx: widget.spec.fx, t: t, back: false),
              child: Center(child: _motion(widget.spec.fx, t, s, face)),
            );
          },
        ),
      ),
    );
  }

  Widget _motion(JuzzioGifFx fx, double t, double s, Widget face) {
    final w = 2 * math.pi * t;
    switch (fx) {
      case JuzzioGifFx.sleepy:
        return Transform.rotate(angle: math.sin(w) * 0.12, child: Transform.translate(offset: Offset(0, math.sin(w) * s * 0.02), child: face));
      case JuzzioGifFx.laugh:
        return Transform.rotate(angle: math.sin(w * 4) * 0.14, child: Transform.translate(offset: Offset(0, -math.sin(w * 4).abs() * s * 0.04), child: face));
      case JuzzioGifFx.love:
        final k = 1 + 0.12 * math.pow(math.sin(w * 2).abs(), 3);
        return Transform.scale(scale: k.toDouble(), child: face);
      case JuzzioGifFx.cry:
        return Transform.translate(offset: Offset(math.sin(w * 3) * s * 0.015, 0), child: face);
      case JuzzioGifFx.party:
        final y = -math.sin(w).abs() * s * 0.12;
        return Transform.translate(offset: Offset(0, y), child: Transform.rotate(angle: math.sin(w) * 0.15, child: face));
      case JuzzioGifFx.dance:
        return Transform.translate(
          offset: Offset(math.sin(w) * s * 0.1, -math.sin(w * 2).abs() * s * 0.05),
          child: Transform.rotate(angle: math.sin(w) * 0.3, child: face),
        );
      case JuzzioGifFx.shock:
        final k = 1 + 0.18 * math.max(0.0, math.sin(w * 2));
        return Transform.translate(offset: Offset(math.sin(w * 18) * s * 0.012, 0), child: Transform.scale(scale: k, child: face));
      case JuzzioGifFx.angry:
        return Transform.translate(offset: Offset(math.sin(w * 6) * s * 0.03, 0), child: face);
      case JuzzioGifFx.cool:
        return Transform.translate(offset: Offset(math.sin(w) * s * 0.06, 0), child: Transform.rotate(angle: -0.06 + math.sin(w) * 0.05, child: face));
      case JuzzioGifFx.shy:
        final k = 0.86 + 0.14 * (0.5 + 0.5 * math.cos(w));
        return Transform.scale(scale: k, child: Transform.rotate(angle: math.sin(w) * 0.08, child: face));
      case JuzzioGifFx.spin:
        return Transform.rotate(angle: w, child: face);
      case JuzzioGifFx.bounce:
        final ph = (t * 2) % 1.0;
        final y = -4 * ph * (1 - ph) * s * 0.22; // parabol
        final squash = ph < 0.08 || ph > 0.92 ? 0.86 : 1.0;
        return Transform.translate(offset: Offset(0, y + s * 0.08), child: Transform.scale(scaleX: 2 - squash, scaleY: squash, alignment: Alignment.bottomCenter, child: face));
      case JuzzioGifFx.wave:
        return Transform.rotate(alignment: Alignment.bottomCenter, angle: math.sin(w * 2) * 0.45, child: face);
      case JuzzioGifFx.hungry:
        final k = 1 - 0.1 * math.sin(w * 3).abs();
        return Transform.scale(scaleX: 1 / k, scaleY: k, child: face);
      case JuzzioGifFx.think:
        return Transform.rotate(angle: -0.18 + math.sin(w) * 0.06, child: Transform.translate(offset: Offset(-s * 0.06, s * 0.05), child: face));
      case JuzzioGifFx.rain:
        return Transform.translate(offset: Offset(0, s * 0.1 + math.sin(w) * s * 0.01), child: face);
      case JuzzioGifFx.fire:
        final k = 1 + 0.05 * math.sin(w * 5);
        return Transform.scale(scaleY: k, alignment: Alignment.bottomCenter, child: face);
      case JuzzioGifFx.ghost:
        return Opacity(
          opacity: 0.55 + 0.45 * (0.5 + 0.5 * math.cos(w)),
          child: Transform.translate(offset: Offset(math.sin(w) * s * 0.12, math.cos(w * 2) * s * 0.05), child: face),
        );
    }
  }
}

class _GifFxPainter extends CustomPainter {
  _GifFxPainter({required this.fx, required this.t, required this.back});
  final JuzzioGifFx fx;
  final double t;
  final bool back;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = size.center(Offset.zero);
    switch (fx) {
      case JuzzioGifFx.sleepy:
        if (back) return;
        for (var i = 0; i < 3; i++) {
          final ph = (t + i / 3) % 1.0;
          final p = Offset(c.dx + s * (0.18 + ph * 0.18), c.dy - s * (0.12 + ph * 0.3));
          _z(canvas, p, s * (0.06 + ph * 0.06), Colors.white.withValues(alpha: (1 - ph) * 0.95));
        }
      case JuzzioGifFx.laugh:
      case JuzzioGifFx.cry:
        if (back) return;
        final paint = Paint()..color = const Color(0xFF6EC6FF);
        for (var i = 0; i < (fx == JuzzioGifFx.cry ? 4 : 2); i++) {
          final ph = (t * (fx == JuzzioGifFx.cry ? 1.5 : 2) + i / 4) % 1.0;
          final side = i.isEven ? -1 : 1;
          final p = fx == JuzzioGifFx.cry
              ? Offset(c.dx + side * s * 0.13, c.dy + s * (-0.02 + ph * 0.38))
              : Offset(c.dx + side * s * (0.24 + ph * 0.12), c.dy - s * 0.06 + ph * s * 0.08);
          paint.color = const Color(0xFF6EC6FF).withValues(alpha: 1 - ph);
          _drop(canvas, p, s * 0.035, paint);
        }
      case JuzzioGifFx.love:
        if (back) return;
        for (var i = 0; i < 4; i++) {
          final ph = (t + i / 4) % 1.0;
          final x = c.dx + math.sin((i * 1.7) + ph * 6) * s * 0.3;
          final y = c.dy + s * 0.25 - ph * s * 0.6;
          _heart(canvas, Offset(x, y), s * (0.05 + 0.03 * (1 - ph)), const Color(0xFFFF4D8D).withValues(alpha: 1 - ph));
        }
      case JuzzioGifFx.party:
        final rnd = math.Random(7);
        const colors = [Color(0xFFFF4D8D), Color(0xFFFFD23F), Color(0xFF3EC1F3), Color(0xFF8C6CFF), Color(0xFF4BE39A)];
        for (var i = 0; i < 14; i++) {
          if (back != i.isEven) continue;
          final ph = (t + rnd.nextDouble()) % 1.0;
          final x = rnd.nextDouble() * s;
          final y = -s * 0.1 + ph * s * 1.1;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(ph * 8 + i);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s * 0.04, height: s * 0.065),
              Paint()..color = colors[i % colors.length].withValues(alpha: 0.9));
          canvas.restore();
        }
      case JuzzioGifFx.shock:
        if (back) return;
        final a = math.max(0.0, math.sin(2 * math.pi * t * 2));
        final paint = Paint()
          ..color = const Color(0xFFFFD23F).withValues(alpha: a)
          ..strokeWidth = s * 0.025
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        for (var i = 0; i < 6; i++) {
          final ang = i * math.pi / 3 + 0.3;
          final r1 = s * 0.36, r2 = s * 0.46;
          canvas.drawLine(c + Offset(math.cos(ang) * r1, math.sin(ang) * r1), c + Offset(math.cos(ang) * r2, math.sin(ang) * r2), paint);
        }
      case JuzzioGifFx.angry:
        if (back) {
          final g = 0.25 + 0.2 * math.sin(2 * math.pi * t * 2);
          canvas.drawCircle(c, s * 0.36, Paint()..color = const Color(0xFFFF3B30).withValues(alpha: g)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
          return;
        }
        for (var i = 0; i < 2; i++) {
          final ph = (t + i / 2) % 1.0;
          final side = i == 0 ? -1 : 1;
          final p = Offset(c.dx + side * s * (0.28 + ph * 0.1), c.dy - s * (0.22 + ph * 0.12));
          canvas.drawCircle(p, s * (0.03 + ph * 0.05), Paint()..color = Colors.white.withValues(alpha: (1 - ph) * 0.8));
        }
      case JuzzioGifFx.cool:
      case JuzzioGifFx.fire:
        if (back) return;
        for (var i = 0; i < 3; i++) {
          final ph = (t * 1.3 + i / 3) % 1.0;
          final k = math.sin(math.pi * ph);
          final p = Offset(c.dx + s * (i - 1) * 0.3, c.dy - s * (0.32 - (i % 2) * 0.08));
          _sparkle(canvas, p, s * 0.06 * k, (fx == JuzzioGifFx.fire ? const Color(0xFFFF8A3D) : Colors.white).withValues(alpha: k));
        }
      case JuzzioGifFx.shy:
        if (!back) return;
        final a = 0.25 + 0.2 * math.cos(2 * math.pi * t);
        canvas.drawCircle(c, s * 0.34, Paint()..color = const Color(0xFFFF9EC7).withValues(alpha: a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
      case JuzzioGifFx.hungry:
        if (back) return;
        for (var i = 0; i < 5; i++) {
          final ph = (t * 1.5 + i / 5) % 1.0;
          final x = c.dx + (i - 2) * s * 0.06 + math.sin(ph * 9) * s * 0.03;
          final y = c.dy + s * 0.2 + ph * s * 0.2;
          canvas.drawCircle(Offset(x, y), s * 0.018, Paint()..color = const Color(0xFFFFC069).withValues(alpha: 1 - ph));
        }
      case JuzzioGifFx.think:
        if (back) return;
        final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t);
        final paint = Paint()..color = Colors.white.withValues(alpha: 0.9);
        canvas.drawCircle(Offset(c.dx + s * 0.2, c.dy - s * 0.18), s * 0.025, paint);
        canvas.drawCircle(Offset(c.dx + s * 0.27, c.dy - s * 0.28), s * 0.04, paint);
        canvas.drawCircle(Offset(c.dx + s * 0.32, c.dy - s * 0.41), s * (0.07 + 0.01 * pulse), paint);
      case JuzzioGifFx.rain:
        final cloud = Paint()..color = const Color(0xFF9AA4B2);
        if (back) return;
        final top = Offset(c.dx, c.dy - s * 0.34);
        canvas.drawCircle(top + Offset(-s * 0.12, 0), s * 0.1, cloud);
        canvas.drawCircle(top + Offset(s * 0.02, -s * 0.05), s * 0.13, cloud);
        canvas.drawCircle(top + Offset(s * 0.15, 0), s * 0.09, cloud);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: top + Offset(0, s * 0.04), width: s * 0.44, height: s * 0.1), Radius.circular(s * 0.05)), cloud);
        final drop = Paint()
          ..color = const Color(0xFF6EC6FF)
          ..strokeWidth = s * 0.015
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 6; i++) {
          final ph = (t * 2 + i / 6) % 1.0;
          final x = top.dx + (i - 2.5) * s * 0.07;
          final y = top.dy + s * 0.1 + ph * s * 0.25;
          drop.color = const Color(0xFF6EC6FF).withValues(alpha: 1 - ph);
          canvas.drawLine(Offset(x, y), Offset(x - s * 0.01, y + s * 0.05), drop);
        }
      case JuzzioGifFx.ghost:
        if (back) return;
        for (var i = 0; i < 3; i++) {
          final ph = (t + i / 3) % 1.0;
          canvas.drawCircle(Offset(c.dx - s * 0.3 + ph * s * 0.6, c.dy + s * 0.34), s * 0.02 * (1 - ph), Paint()..color = Colors.white.withValues(alpha: 0.5 * (1 - ph)));
        }
      case JuzzioGifFx.dance:
      case JuzzioGifFx.spin:
      case JuzzioGifFx.bounce:
      case JuzzioGifFx.wave:
        if (back || fx == JuzzioGifFx.bounce) {
          if (fx == JuzzioGifFx.bounce && back) {
            final ph = (t * 2) % 1.0;
            final k = 1 - 4 * ph * (1 - ph) * 0.6;
            canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, c.dy + s * 0.42), width: s * 0.4 * k, height: s * 0.06 * k),
                Paint()..color = Colors.black.withValues(alpha: 0.22));
          }
          return;
        }
        // müzik notası benzeri küçük daireler (yazısız)
        for (var i = 0; i < 2; i++) {
          final ph = (t + i / 2) % 1.0;
          final p = Offset(c.dx + (i == 0 ? -1 : 1) * s * (0.3 + ph * 0.05), c.dy - s * (0.1 + ph * 0.25));
          canvas.drawCircle(p, s * 0.03, Paint()..color = JuzzioGlassTokens.glow.withValues(alpha: 1 - ph));
          canvas.drawLine(p + Offset(s * 0.028, 0), p + Offset(s * 0.028, -s * 0.09),
              Paint()
                ..color = JuzzioGlassTokens.glow.withValues(alpha: 1 - ph)
                ..strokeWidth = s * 0.012);
        }
    }
  }

  void _z(Canvas canvas, Offset p, double h, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = h * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(p.dx - h / 2, p.dy - h / 2)
      ..lineTo(p.dx + h / 2, p.dy - h / 2)
      ..lineTo(p.dx - h / 2, p.dy + h / 2)
      ..lineTo(p.dx + h / 2, p.dy + h / 2);
    canvas.drawPath(path, paint);
  }

  void _drop(Canvas canvas, Offset p, double r, Paint paint) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r * 1.8)
      ..quadraticBezierTo(p.dx + r * 1.2, p.dy, p.dx, p.dy + r)
      ..quadraticBezierTo(p.dx - r * 1.2, p.dy, p.dx, p.dy - r * 1.8);
    canvas.drawPath(path, paint);
  }

  void _heart(Canvas canvas, Offset p, double r, Color color) {
    final path = Path()
      ..moveTo(p.dx, p.dy + r * 0.9)
      ..cubicTo(p.dx - r * 1.6, p.dy - r * 0.2, p.dx - r * 0.7, p.dy - r * 1.4, p.dx, p.dy - r * 0.5)
      ..cubicTo(p.dx + r * 0.7, p.dy - r * 1.4, p.dx + r * 1.6, p.dy - r * 0.2, p.dx, p.dy + r * 0.9);
    canvas.drawPath(path, Paint()..color = color);
  }

  void _sparkle(Canvas canvas, Offset p, double r, Color color) {
    if (r <= 0.2) return;
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GifFxPainter old) => old.t != t || old.fx != fx;
}

/// GIF sekmesi: arama + ızgara. Dokununca [onPick] çağrılır (sohbet belirteci gönderir).
class JuzzioGifGrid extends StatefulWidget {
  const JuzzioGifGrid({super.key, required this.onPick, required this.isDark});
  final ValueChanged<JuzzioGifSpec> onPick;
  final bool isDark;

  @override
  State<JuzzioGifGrid> createState() => _JuzzioGifGridState();
}

class _JuzzioGifGridState extends State<JuzzioGifGrid> {
  final TextEditingController _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final list = juzzioSearchGifs(_q.text, app);
    final fg = widget.isDark ? Colors.white : const Color(0xFF111114);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: fg, fontSize: 14),
              decoration: InputDecoration(
                hintText: app.trEn('GIF ara (uyku, kahkaha, dans…)', 'Search GIFs (sleep, laugh, dance…)'),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: widget.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(app.trEn('Sonuç bulunamadı', 'No results'), style: TextStyle(color: fg.withValues(alpha: 0.6))))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 96, mainAxisSpacing: 6, crossAxisSpacing: 6),
                  itemCount: list.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => widget.onPick(list[i]),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(child: JuzzioGifSticker(spec: list[i], size: 80)),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
