// =============================================================================
// JUZZIO v1.2.0 — Paylaşılan vardiya planı kartı + ayrıntılı görüntüleyici
//  Grup sohbetine düşen "📅 Vardiya planı: 10.11–16.11 · Sabah 08-16 · 08:00–16:00 (5 gün)"
//  mesajı artık dokunulabilir bir karttır. Dokununca planın sahibine ait o aralıktaki
//  kayıtlar (user_shifts; RLS: yalnız bu grubun üyeleri görür) gün gün listelenir:
//  hangi gün, hangi saatler, hangi günler izin. Eski mesajlar da metinden çözülür.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_glass.dart';
import '../screens/shift_planner_screen.dart';
import '../services/supabase_service.dart';
import 'juzzio_message_cards.dart';
import 'juzzio_motion.dart';

class JuzzioSharedShift {
  const JuzzioSharedShift({required this.from, required this.to, required this.label, required this.hours, required this.days, this.note = ''});
  final DateTime from;
  final DateTime to;
  final String label;
  final String hours;
  final int days;
  final String note;
}

final RegExp _kShiftRe = RegExp(
  r'^📅\s*(?:Vardiya planı|Shift plan|Schichtplan):\s*(\d{1,2})\.(\d{1,2})\s*[–-]\s*(\d{1,2})\.(\d{1,2})\s*·\s*(.+?)\s*\((\d+)\s*[^)]*\)\s*$',
);

/// Vardiya planı mesajını çözer (saf; test edilir). Yıl, mesajın gönderildiği tarihten çıkarılır.
JuzzioSharedShift? juzzioParseSharedShift(String text, DateTime sentAt) {
  final lines = text.trim().split('\n');
  if (lines.isEmpty) return null;
  final m = _kShiftRe.firstMatch(lines.first.trim());
  if (m == null) return null;
  final d1 = int.parse(m.group(1)!), m1 = int.parse(m.group(2)!);
  final d2 = int.parse(m.group(3)!), m2 = int.parse(m.group(4)!);
  if (m1 < 1 || m1 > 12 || m2 < 1 || m2 > 12 || d1 < 1 || d1 > 31 || d2 < 1 || d2 > 31) return null;
  final local = sentAt.toLocal();
  var from = DateTime(local.year, m1, d1);
  // Aralık geçmişte kalmış bir yıl başı/sonu olabilir: gönderimden 200+ gün sonrası → önceki yıl
  if (from.difference(local).inDays > 200) from = DateTime(local.year - 1, m1, d1);
  if (local.difference(from).inDays > 200) from = DateTime(local.year + 1, m1, d1);
  var to = DateTime(from.year, m2, d2);
  if (to.isBefore(from)) to = DateTime(from.year + 1, m2, d2);
  final parts = m.group(5)!.split(' · ');
  final label = parts.first.trim();
  final hours = parts.length > 1 ? parts.sublist(1).join(' · ').trim() : '';
  return JuzzioSharedShift(
    from: from,
    to: to,
    label: label,
    hours: hours,
    days: int.parse(m.group(6)!),
    note: lines.length > 1 ? lines.sublist(1).join('\n').trim() : '',
  );
}

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _weekdayShort(JuzzioAppController app) => app.uiLang.startsWith('tr')
    ? const ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
    : app.uiLang.startsWith('de')
        ? const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class JuzzioShiftPlanCard extends StatelessWidget {
  const JuzzioShiftPlanCard({super.key, required this.isMe, required this.plan, required this.ownerId, required this.roomId, this.ownerName});
  final bool isMe;
  final JuzzioSharedShift plan;
  final String ownerId;
  final String roomId;
  final String? ownerName;

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final ink = JuzzioCardInk(isMe);
    final wd = _weekdayShort(app);
    void open() => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => JuzzioShiftPlanViewer(plan: plan, ownerId: ownerId, roomId: roomId, ownerName: ownerName),
        ));
    return JuzzioCardShell(
      isMe: isMe,
      onTap: open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isMe ? const Color(0x33FFFFFF) : JuzzioGlassTokens.glow.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(wd[plan.from.weekday - 1], style: TextStyle(color: ink.secondary, fontSize: 9.5, fontWeight: FontWeight.w800)),
              Text('${plan.from.day}', style: TextStyle(color: ink.primary, fontSize: 17, fontWeight: FontWeight.w900, height: 1.05)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.trEn('Vardiya planı', 'Shift plan', 'Schichtplan'),
                  style: TextStyle(color: ink.secondary, fontSize: 11.5, fontWeight: FontWeight.w700)),
              Text('${_dm(plan.from)} – ${_dm(plan.to)}', style: TextStyle(color: ink.primary, fontSize: 16, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _pill(ink, Icons.work_history_rounded, plan.label),
          if (plan.hours.isNotEmpty) _pill(ink, Icons.schedule_rounded, plan.hours),
          _pill(ink, Icons.calendar_month_rounded, app.trEn('${plan.days} gün', '${plan.days} days', '${plan.days} Tage')),
        ]),
        if (plan.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(plan.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: ink.primary, fontSize: 13)),
        ],
        const SizedBox(height: 10),
        JuzzioCardButton(isMe: isMe, label: app.trEn('Planı gün gün gör', 'View day by day', 'Tagesansicht'), icon: Icons.open_in_full_rounded, onTap: open),
      ]),
    );
  }

  Widget _pill(JuzzioCardInk ink, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: ink.buttonBg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: ink.accent),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: ink.primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Ayrıntılı görüntüleyici: aralıktaki her gün (çalışma saatleri / izin / kayıt yok)
class JuzzioShiftPlanViewer extends StatefulWidget {
  const JuzzioShiftPlanViewer({super.key, required this.plan, required this.ownerId, required this.roomId, this.ownerName});
  final JuzzioSharedShift plan;
  final String ownerId;
  final String roomId;
  final String? ownerName;

  @override
  State<JuzzioShiftPlanViewer> createState() => _JuzzioShiftPlanViewerState();
}

class _JuzzioShiftPlanViewerState extends State<JuzzioShiftPlanViewer> {
  final _app = JuzzioAppController.instance;
  Map<String, JuzzioShift> _byDay = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = SupabaseService.instance.currentUserId;
      var q = SupabaseService.instance.client
          .from('user_shifts')
          .select()
          .eq('user_id', widget.ownerId)
          .gte('shift_date', _ymd(widget.plan.from))
          .lte('shift_date', _ymd(widget.plan.to));
      // kendi planım değilse yalnız bu grupla paylaşılan kayıtlar (RLS de bunu zorunlu kılar)
      if (me != widget.ownerId) q = q.eq('room_id', widget.roomId);
      final rows = await q;
      final map = <String, JuzzioShift>{};
      for (final r in rows as List) {
        final s = JuzzioShift.fromMap(Map<String, dynamic>.from(r as Map));
        map[_ymd(s.date)] = s;
      }
      if (!mounted) return;
      setState(() {
        _byDay = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupabaseService.instance.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final plan = widget.plan;
    final days = <DateTime>[
      for (var d = plan.from; !d.isAfter(plan.to); d = DateTime(d.year, d.month, d.day + 1)) d,
    ];
    final work = _byDay.values.where((s) => s.code != 'off_day' && s.code != 'annual_leave').length;
    final off = _byDay.values.where((s) => s.code == 'off_day' || s.code == 'annual_leave').length;
    var minutes = 0;
    for (final s in _byDay.values) {
      if (s.startsAt != null && s.endsAt != null) minutes += s.endsAt!.difference(s.startsAt!).inMinutes.abs();
    }
    final wd = _weekdayShort(_app);
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_app.trEn('Vardiya planı', 'Shift plan', 'Schichtplan'), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 17)),
          if ((widget.ownerName ?? '').isNotEmpty)
            Text(widget.ownerName!, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
        ]),
      ),
      body: _loading
          ? const Center(child: JuzzioOrbitLoader())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [JuzzioGlassTokens.glow.withValues(alpha: 0.32), JuzzioGlassTokens.glow.withValues(alpha: 0.06)],
                    ),
                    border: Border.all(color: JuzzioGlassTokens.glow.withValues(alpha: 0.35)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_dm(plan.from)} – ${_dm(plan.to)}', style: TextStyle(color: p.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text([plan.label, if (plan.hours.isNotEmpty) plan.hours].join(' · '), style: TextStyle(color: p.textSecondary, fontSize: 13.5)),
                    const SizedBox(height: 14),
                    Row(children: [
                      _stat(p, '$work', _app.trEn('çalışma', 'work', 'Arbeit')),
                      _stat(p, '$off', _app.trEn('izin', 'off', 'frei')),
                      _stat(p, minutes == 0 ? '—' : '${(minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1)} ${_app.trEn('sa', 'h', 'Std')}',
                          _app.trEn('toplam', 'total', 'gesamt')),
                    ]),
                    if (plan.note.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(plan.note, style: TextStyle(color: p.textPrimary, fontSize: 13.5, height: 1.4)),
                    ],
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                if (_byDay.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _app.trEn('Bu aralık için kayıt bulunamadı (plan silinmiş ya da güncellenmiş olabilir). Özet yukarıda.',
                          'No entries found for this range (the plan may have been changed). Summary above.', 'Keine Einträge gefunden.'),
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 14),
                for (final d in days) _dayRow(p, d, _byDay[_ymd(d)], wd),
              ],
            ),
    );
  }

  Widget _stat(JuzzioPalette p, String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: p.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: p.textSecondary, fontSize: 12)),
        ]),
      );

  Widget _dayRow(JuzzioPalette p, DateTime d, JuzzioShift? s, List<String> wd) {
    final today = DateUtils.isSameDay(d, DateTime.now());
    final off = s != null && (s.code == 'off_day' || s.code == 'annual_leave');
    final color = s == null ? p.textSecondary.withValues(alpha: 0.4) : juzzioShiftColor(s.code);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: JuzzioGlassTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: today ? JuzzioGlassTokens.glow : JuzzioGlassTokens.border, width: today ? 1.6 : 1),
      ),
      child: Row(children: [
        SizedBox(
          width: 46,
          child: Column(children: [
            Text(wd[d.weekday - 1], style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
            Text('${d.day}', style: TextStyle(color: p.textPrimary, fontSize: 19, fontWeight: FontWeight.w900)),
          ]),
        ),
        Container(width: 4, height: 34, margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s == null ? _app.trEn('Kayıt yok', 'No entry', 'Kein Eintrag') : juzzioShiftLabel(s.code, _app),
              style: TextStyle(color: s == null ? p.textSecondary : p.textPrimary, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            if (s != null && s.hoursLabel.isNotEmpty)
              Text(s.hoursLabel, style: TextStyle(color: p.textSecondary, fontSize: 12.5)),
            if (s != null && s.note.isNotEmpty)
              Text(s.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textSecondary, fontSize: 12)),
          ]),
        ),
        if (off)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
            child: Text(_app.trEn('İzin', 'Off', 'Frei'), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
      ]),
    );
  }
}
