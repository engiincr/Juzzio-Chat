// =============================================================================
// JUZZIO v1.2.4 — Şifre gücü ölçer (kayıt ekranı)
//  Kullanıcının paylaştığı "Full Auth Flow" videosundaki gibi: yazdıkça dolan 4 parçalı
//  çubuk ve Zayıf / Orta / İyi / Güçlü etiketi. Puanlama saf fonksiyondur (test edilir).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';

/// 0 (boş) … 4 (güçlü). Uzunluk + karakter çeşitliliği; yaygın/tekrarlı şifreler cezalandırılır.
int juzzioPasswordScore(String pw) {
  if (pw.isEmpty) return 0;
  var score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 12) score++;
  final classes = [RegExp(r'[a-zçğıöşü]'), RegExp(r'[A-ZÇĞİÖŞÜ]'), RegExp(r'[0-9]'), RegExp(r'[^A-Za-z0-9çğıöşüÇĞİÖŞÜ]')]
      .where((r) => r.hasMatch(pw))
      .length;
  if (classes >= 2) score++;
  if (classes >= 3) score++;
  const common = ['123456', 'password', 'qwerty', 'sifre', 'şifre', '111111', 'juzzio', 'abc123'];
  final low = pw.toLowerCase();
  if (common.any(low.contains) || RegExp(r'^(.)\1+$').hasMatch(pw)) score = score > 1 ? 1 : score;
  if (pw.length < 6) score = score > 1 ? 1 : score;
  return score.clamp(1, 4);
}

class JuzzioPasswordStrengthBar extends StatelessWidget {
  const JuzzioPasswordStrengthBar({super.key, required this.password});
  final String password;

  static const _colors = [Color(0xFFFF5A6A), Color(0xFFFFA63D), Color(0xFF7BD1FF), Color(0xFF34C759)];

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final score = juzzioPasswordScore(password);
    final labels = [
      app.trEn('Zayıf', 'Weak', 'Schwach'),
      app.trEn('Orta', 'Fair', 'Mittel'),
      app.trEn('İyi', 'Good', 'Gut'),
      app.trEn('Güçlü', 'Strong', 'Stark'),
    ];
    final color = score == 0 ? Colors.transparent : _colors[score - 1];
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: password.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(children: [
                for (var i = 0; i < 4; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 180 + i * 60),
                      curve: Curves.easeOutCubic,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < score ? color : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: i < score ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8)] : null,
                      ),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 6),
                ],
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(labels[(score - 1).clamp(0, 3)], key: ValueKey(score), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ]),
            ),
    );
  }
}
