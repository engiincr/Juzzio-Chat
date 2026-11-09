// =============================================================================
// JUZZIO v0.9.7 — Ortak arayüz kiti
//  • JuzzioShimmer / JuzzioSkeleton…: boş gri ekran ve çember yerine parıldayan
//    iskelet yükleyiciler (tema renklerinden üretilir, "Hareketi azalt"a uyar)
//  • JuzzioUnreadPill: tema vurgu renkli, yaylanarak beliren hap şeklinde okunmamış rozeti
//  • kJuzzioPreviewPending: sohbet önizlemesi hazırlanıyor işareti (metin değil, iskelet)
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

/// Sohbet listesinde önizleme hazırlanırken alt satır yerine iskelet çizilir.
const String kJuzzioPreviewPending = '⁣';

/// Okunmamış sayısının rozet metni (99+ sınırı).
String juzzioUnreadLabel(int n) => n > 99 ? '99+' : '$n';

/// Parıltı efekti: alt ağaç bir maske olarak kullanılır, üzerinde ışık bandı kayar.
class JuzzioShimmer extends StatefulWidget {
  const JuzzioShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<JuzzioShimmer> createState() => _JuzzioShimmerState();
}

class _JuzzioShimmerState extends State<JuzzioShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = JuzzioAppController.instance.isDark;
    final base = dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06);
    final shine = Color.lerp(base, JuzzioGlassTokens.accentPair.first, 0.18)!.withValues(alpha: dark ? 0.22 : 0.16);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return ColorFiltered(colorFilter: ColorFilter.mode(base, BlendMode.srcIn), child: widget.child);
    }
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2.6 - 0.8;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(-1 + t, -0.3),
            end: Alignment(0 + t, 0.3),
            colors: [base, shine, base],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}

/// İskelet blok (shimmer maskesi içinde dolu şekil).
class JuzzioSkeletonBox extends StatelessWidget {
  const JuzzioSkeletonBox({super.key, this.width, required this.height, this.radius = 10, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// Tek satırlık önizleme iskeleti (sohbet kartında alt satır).
class JuzzioSkeletonLine extends StatelessWidget {
  const JuzzioSkeletonLine({super.key, this.widthFactor = 0.62, this.height = 11});
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => JuzzioShimmer(
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: JuzzioSkeletonBox(height: height, radius: 6),
        ),
      );
}

/// Sohbet listesi yüklenirken: avatar + iki satır, 8 kart.
class JuzzioConversationListSkeleton extends StatelessWidget {
  const JuzzioConversationListSkeleton({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) {
    return JuzzioShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: count,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
          child: Row(children: [
            const JuzzioSkeletonBox(height: 54, circle: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FractionallySizedBox(widthFactor: 0.42 + (i % 3) * 0.12, child: const JuzzioSkeletonBox(height: 14, radius: 7)),
                const SizedBox(height: 9),
                FractionallySizedBox(widthFactor: 0.7 - (i % 2) * 0.18, child: const JuzzioSkeletonBox(height: 11, radius: 6)),
              ]),
            ),
            const SizedBox(width: 12),
            const JuzzioSkeletonBox(width: 34, height: 10, radius: 5),
          ]),
        ),
      ),
    );
  }
}

/// Profil kartı yüklenirken: kapak, avatar, ad, biyografi, sayaçlar.
class JuzzioProfileSkeleton extends StatelessWidget {
  const JuzzioProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return JuzzioShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const JuzzioSkeletonBox(height: 140, radius: 24),
          const SizedBox(height: 16),
          const Center(child: JuzzioSkeletonBox(height: 96, circle: true)),
          const SizedBox(height: 14),
          const Center(child: JuzzioSkeletonBox(width: 160, height: 16, radius: 8)),
          const SizedBox(height: 8),
          const Center(child: JuzzioSkeletonBox(width: 110, height: 12, radius: 6)),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 3; i++) const JuzzioSkeletonBox(width: 70, height: 44, radius: 14),
          ]),
          const SizedBox(height: 18),
          for (var i = 0; i < 3; i++) ...[
            const JuzzioSkeletonBox(height: 12, radius: 6),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [for (var i = 0; i < 6; i++) const JuzzioSkeletonBox(height: 100, radius: 12)],
          ),
        ],
      ),
    );
  }
}

/// Genel liste iskeleti (bildirimler, ayar listeleri, yönetici tabloları).
class JuzzioListSkeleton extends StatelessWidget {
  const JuzzioListSkeleton({super.key, this.count = 6, this.leadingCircle = true});
  final int count;
  final bool leadingCircle;

  @override
  Widget build(BuildContext context) {
    return JuzzioShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: count,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            if (leadingCircle) ...[const JuzzioSkeletonBox(height: 42, circle: true), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FractionallySizedBox(widthFactor: 0.55 + (i % 3) * 0.1, child: const JuzzioSkeletonBox(height: 13, radius: 6)),
                const SizedBox(height: 7),
                const FractionallySizedBox(widthFactor: 0.85, child: JuzzioSkeletonBox(height: 10, radius: 5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Hap şeklinde okunmamış rozeti: sayı değişince yaylanarak büyür; sessize alınmış
/// sohbette sönük tonda gösterilir. Sayı 0 iken yer kaplamaz (hizalama bozulmaz).
class JuzzioUnreadPill extends StatelessWidget {
  const JuzzioUnreadPill({super.key, required this.count, this.muted = false});
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final accents = JuzzioGlassTokens.accentPair;
    final dark = JuzzioAppController.instance.isDark;
    final a = muted ? JuzzioGlassTokens.textMuted : accents.first;
    final b = muted ? JuzzioGlassTokens.textMuted.withValues(alpha: 0.8) : (accents.length > 1 ? accents[1] : accents.first);
    final fg = juzzioReadableOn(Color.lerp(a, b, 0.5)!);
    return SizedBox(
      height: 22,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.elasticOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
        child: count <= 0
            ? const SizedBox(key: ValueKey('none'), width: 22, height: 22)
            : Container(
                key: ValueKey('n$count'),
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
                  border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.28 : 0.55), width: 0.8),
                  boxShadow: muted ? null : [BoxShadow(color: a.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Text(
                  juzzioUnreadLabel(count),
                  style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.2, height: 1.0),
                ),
              ),
      ),
    );
  }
}
