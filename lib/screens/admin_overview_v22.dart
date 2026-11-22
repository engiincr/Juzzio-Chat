// =============================================================================
// JUZZIO v2.2.0 — GM-034: Yönetici Paneli "Genel Bakış" (Engin'in referans görseli)
//  Başlık: "J Juzzio | Admin Panel" + arama · bildirim · çıkış
//  Karşılama: fotoğraf (ışıklı halka), "Hoş geldin," ad + mavi tik, "Sistem Yöneticisi" rozeti;
//  özel gün teması açıksa sağda dekor (Halloween şatosu / Türk bayrağı)
//  Üst sekmeler: Genel Bakış · Kullanıcılar · Raporlar · Yasaklamalar · Güvenlik · Sistem Sağlığı · Ayarlar
//  Genel Bakış: "Son 30 Gün" seçici, 4 renkli sayaç kartı (% değişim), Aktivite Grafiği,
//  Son Aktiviteler, Dikkat Gerektirenler (şikâyet, yasaklı, güvenlik uyarısı, depolama çubuğu),
//  Sistem Sağlığı şeridi (Veritabanı · Gerçek Zamanlı · Depolama · Push FCM, % çevrimiçi süre)
//  ve Özel gün temaları (her yönetici iki temanın durumunu görür; açma/kapama ayar yetkisiyle).
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';

String _t(String tr, String en, String de) => JuzzioAppController.instance.trEn(tr, en, de);

/// Dönemsel % değişim (önceki dönem 0 ise null) (saf; test edilir)
double? juzzioPercentChange(num current, num previous) {
  if (previous <= 0) return null;
  return (current - previous) / previous * 100;
}

/// "%12,4" biçimi (Türkçede virgül) (saf; test edilir)
String juzzioFormatPercent(double v, {String lang = 'tr'}) {
  final s = v.abs().toStringAsFixed(1);
  final sign = v >= 0 ? '+' : '−';
  return lang == 'tr' ? '$sign${s.replaceAll('.', ',')}%' : '$sign$s%';
}

/// Binlik ayırıcılı sayı ("8.421") (saf; test edilir)
String juzzioGroupedNumber(num v, {String lang = 'tr'}) {
  final s = v.round().abs().toString();
  final sep = lang == 'en' ? ',' : '.';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

/// Seriyi (eskiden yeniye) şimdiki ve önceki döneme ayırır; [key] alanının toplamları (saf; test edilir)
(num, num) juzzioSeriesPeriodSums(List<Map<String, dynamic>> series, String key, int days) {
  num v(Map<String, dynamic> m) => (m[key] as num?) ?? 0;
  final cur = series.length <= days ? series : series.sublist(series.length - days);
  final prevEnd = series.length - cur.length;
  final prev = series.sublist(math.max(0, prevEnd - days), prevEnd);
  return (cur.fold<num>(0, (a, m) => a + v(m)), prev.fold<num>(0, (a, m) => a + v(m)));
}

/// Kısa ay adı ("Kas", "Nov") (saf; test edilir)
String juzzioShortMonth(int m, String lang) {
  const tr = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const de = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
  final list = lang == 'tr' ? tr : (lang == 'de' ? de : en);
  return list[(m - 1).clamp(0, 11)];
}

/// Üst sekme (mantıksal bölüm numarasıyla; null = Genel Bakış)
class JuzzioAdminTopTab {
  const JuzzioAdminTopTab(this.icon, this.label, this.section);
  final IconData icon;
  final String label;
  final int? section;
}

List<JuzzioAdminTopTab> juzzioAdminTopTabs() => [
      JuzzioAdminTopTab(Icons.grid_view_rounded, _t('Genel Bakış', 'Overview', 'Übersicht'), null),
      JuzzioAdminTopTab(Icons.people_alt_rounded, _t('Kullanıcılar', 'Users', 'Nutzer'), 1),
      JuzzioAdminTopTab(Icons.bar_chart_rounded, _t('Raporlar', 'Reports', 'Meldungen'), 2),
      JuzzioAdminTopTab(Icons.block_rounded, _t('Yasaklamalar', 'Bans', 'Sperren'), 3),
      JuzzioAdminTopTab(Icons.shield_rounded, _t('Güvenlik', 'Security', 'Sicherheit'), 4),
      JuzzioAdminTopTab(Icons.monitor_heart_rounded, _t('Sistem Sağlığı', 'System Health', 'Systemstatus'), 15),
      JuzzioAdminTopTab(Icons.settings_rounded, _t('Ayarlar', 'Settings', 'Einstellungen'), 10),
    ];

/// Yuvarlak cam başlık düğmesi (isteğe bağlı nokta)
class JuzzioAdminRoundButton extends StatelessWidget {
  const JuzzioAdminRoundButton({super.key, required this.icon, required this.onTap, this.tooltip, this.dot = false});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final b = Stack(clipBehavior: Clip.none, children: [
      JuzzioLiquidGlass(
        shape: BoxShape.circle,
        blur: 12,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 22, color: JuzzioGlassTokens.textPrimary)),
          ),
        ),
      ),
      if (dot)
        Positioned(
          right: 2,
          top: 2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: JuzzioGlassTokens.glow,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: JuzzioGlassTokens.glow.withValues(alpha: 0.6), blurRadius: 6)],
            ),
          ),
        ),
    ]);
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// Renkli sayaç kartı (Toplam Kullanıcı / Şu An Çevrimiçi / Toplam Mesaj / Toplam Arama)
class JuzzioAdminStatCard extends StatelessWidget {
  const JuzzioAdminStatCard({super.key, required this.color, required this.icon, required this.value, required this.label, this.change, this.note});
  final Color color;
  final IconData icon;
  final String value;
  final String label;
  final double? change;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final lang = JuzzioAppController.instance.uiLang;
    final up = (change ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 18, spreadRadius: -6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        ),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (change != null)
          Row(children: [
            Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: up ? color : const Color(0xFFFF6B6B)),
            const SizedBox(width: 4),
            Text(juzzioFormatPercent(change!, lang: lang),
                style: TextStyle(color: up ? color : const Color(0xFFFF6B6B), fontSize: 12.5, fontWeight: FontWeight.w800)),
          ])
        else
          Text(note ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Cam panel kartı
class JuzzioAdminPanelCard extends StatelessWidget {
  const JuzzioAdminPanelCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => JuzzioLiquidGlass(radius: 20, blur: 14, padding: padding, child: child);
}

class JuzzioAdminCardTitle extends StatelessWidget {
  const JuzzioAdminCardTitle({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.iconColor});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: iconColor ?? JuzzioGlassTokens.glowText, size: 26),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

/// Aktivite grafiği: neon alan çizgisi, ızgara, gün etiketleri, son noktada cam bilgi balonu
class JuzzioAdminActivityChart extends StatelessWidget {
  const JuzzioAdminActivityChart({super.key, required this.values, required this.labels, required this.tooltip});
  final List<double> values;
  final List<String> labels;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final g = JuzzioGlassTokens.glow;
    return SizedBox(
      height: 190,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AreaChartPainter(
                values: values,
                labels: labels,
                color: g,
                grid: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.08),
                text: JuzzioGlassTokens.textSecondary,
              ),
            ),
          ),
          if (values.isNotEmpty)
            Positioned(
              right: 4,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: JuzzioGlassTokens.space.depth.last.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: g.withValues(alpha: 0.8)),
                ),
                child: Text(tooltip,
                    style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.35)),
              ),
            ),
        ]);
      }),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  _AreaChartPainter({required this.values, required this.labels, required this.color, required this.grid, required this.text});
  final List<double> values;
  final List<String> labels;
  final Color color;
  final Color grid;
  final Color text;

  static String _axis(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K' : v.toStringAsFixed(0);

  void _label(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 10.5, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.center ? at.dx - tp.width / 2 : (align == TextAlign.right ? at.dx - tp.width : at.dx);
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 22.0, top = 46.0;
    final w = size.width - left - 8;
    final h = size.height - bottom - top;
    final maxV = values.isEmpty ? 1.0 : math.max(1.0, values.reduce(math.max));
    final niceMax = (maxV * 1.15);
    for (var i = 0; i <= 4; i++) {
      final y = top + h - h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), Paint()..color = grid);
      _label(canvas, _axis(niceMax * i / 4), Offset(left - 6, y), align: TextAlign.right);
    }
    if (values.length < 2) return;
    Offset pt(int i) => Offset(left + w * i / (values.length - 1), top + h - h * (values[i] / niceMax));
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = pt(i - 1), b = pt(i);
      final mx = (a.dx + b.dx) / 2;
      line.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(left + w, top + h)
      ..lineTo(left, top + h)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.02)],
          ).createShader(Rect.fromLTWH(left, top, w, h)));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = color);
    final last = pt(values.length - 1);
    canvas.drawCircle(last, 7, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawCircle(last, 4.5, Paint()..color = color);
    // gün etiketleri (en fazla 7)
    final n = labels.length;
    if (n > 0) {
      final step = math.max(1, (n / 6).ceil());
      for (var i = 0; i < n; i += step) {
        _label(canvas, labels[i], Offset(left + w * i / math.max(1, n - 1), size.height - 9), align: TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(_AreaChartPainter o) => o.values != values || o.color != color || o.labels != labels;
}

/// Son Aktiviteler satırı
class JuzzioAdminActivityRow extends StatelessWidget {
  const JuzzioAdminActivityRow({super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.when});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String when;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 13.5)),
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(when, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5)),
      ]),
    );
  }
}

/// Dikkat Gerektirenler satırı (dokununca ilgili sayfa)
class JuzzioAdminAttentionRow extends StatelessWidget {
  const JuzzioAdminAttentionRow({super.key, required this.icon, required this.color, required this.text, required this.onTap, this.progress});
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: 6,
                        color: progress! > 0.9 ? const Color(0xFFFF5A5A) : JuzzioGlassTokens.glow,
                        backgroundColor: JuzzioGlassTokens.textPrimary.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sistem Sağlığı servis hücresi
class JuzzioAdminServiceCell extends StatelessWidget {
  const JuzzioAdminServiceCell({super.key, required this.icon, required this.name, required this.ok, this.detail});
  final IconData icon;
  final String name;
  final bool? ok;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = ok == null ? const Color(0xFFFBBF24) : (ok! ? const Color(0xFF4ADE80) : const Color(0xFFFF5A5A));
    final label = detail ??
        (ok == null ? _t('Denetleniyor', 'Checking', 'Prüfe') : (ok! ? _t('Çevrimiçi', 'Online', 'Online') : _t('Sorunlu', 'Degraded', 'Gestört')));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: JuzzioGlassTokens.textPrimary, size: 28),
      const SizedBox(width: 10),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700))),
          ]),
        ]),
      ),
    ]);
  }
}
