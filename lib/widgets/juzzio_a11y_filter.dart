// Juzzio 2.1 (Faz 8.5) — Erişilebilirlik katmanı
//  • Kalın yazı: tüm uygulamada MediaQuery.boldText
//  • Renk düzeltme (renk körlüğü): protanopi / döteranopi / tritanopi için yaklaşık
//    "daltonizasyon" matrisi, gri tonlama. Kapalıyken hiçbir katman eklenmez (başarım).

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';

/// Renk düzeltme matrisleri (RGB, satır toplamı 1 → beyaz beyaz kalır) (saf; test edilir)
List<double>? juzzioColorVisionMatrix(String mode) {
  switch (mode) {
    case 'protanopia':
      return const [1, 0, 0, 0, 0, -0.2549, 1.2549, 0, 0, 0, 0.3031, -0.5451, 1.242, 0, 0, 0, 0, 0, 1, 0];
    case 'deuteranopia':
      return const [1, 0, 0, 0, 0, -0.4375, 1.4375, 0, 0, 0, 0.2625, -0.5625, 1.3, 0, 0, 0, 0, 0, 1, 0];
    case 'tritanopia':
      return const [1.05, -0.3825, 0.3325, 0, 0, 0, 1.2345, -0.2345, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    case 'grayscale':
      return const [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
  }
  return null;
}

class JuzzioA11yFilter extends StatelessWidget {
  const JuzzioA11yFilter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    Widget out = child;
    if (app.boldTextEnabled) {
      final mq = MediaQuery.of(context);
      out = MediaQuery(data: mq.copyWith(boldText: true), child: out);
    }
    final m = juzzioColorVisionMatrix(app.colorVisionMode);
    if (m != null) out = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: out);
    return out;
  }
}
