// =============================================================================
// JUZZIO v0.7.0 — Arama ayrıntısı
//  Arama geçmişindeki bir kayda dokunulunca: başlangıç saati, cevaplanma saati,
//  bitiş saati, toplam süre, aramayı ilk kimin kapattığı, yön ve durum.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';

class JuzzioCallDetailPage extends StatelessWidget {
  final JuzzioCallLog log;
  final VoidCallback? onCallBack;

  const JuzzioCallDetailPage({super.key, required this.log, this.onCallBack});

  static Future<void> open(BuildContext context, JuzzioCallLog log, {VoidCallback? onCallBack}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JuzzioCallDetailPage(log: log, onCallBack: onCallBack)),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _clock(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.day)}.${_two(l.month)}.${l.year}';
  }

  String _duration(int sec) {
    if (sec <= 0) return '00:00';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return h > 0 ? '${_two(h)}:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final p = JuzzioPalette(app.isDark);
    final myUid = SupabaseService.instance.currentUserId;
    final isOutgoing = log.callerId == myUid;
    final partnerName = log.isGroup && log.groupTitle.isNotEmpty
        ? log.groupTitle
        : (isOutgoing ? log.receiverName : log.callerName);
    final partnerAvatar = isOutgoing ? log.receiverAvatar : log.callerAvatar;

    // Süre: kayıttaki süre yoksa cevaplanma–bitiş farkından hesaplanır
    int sec = log.durationSec;
    if (sec <= 0 && log.answeredAt != null && log.endedAt != null) {
      sec = log.endedAt!.difference(log.answeredAt!).inSeconds.clamp(0, 1 << 31);
    }

    final String status;
    final Color statusColor;
    switch (log.status) {
      case 'rejected':
        status = app.trEn('Reddedildi', 'Declined', 'Abgelehnt');
        statusColor = p.dangerRed;
        break;
      case 'missed':
      case 'cancelled':
        status = isOutgoing
            ? app.trEn('Cevap yok', 'No answer', 'Keine Antwort')
            : app.trEn('Cevapsız arama', 'Missed call', 'Verpasster Anruf');
        statusColor = p.dangerRed;
        break;
      case 'busy_silent':
        status = app.trEn('Meşgul', 'Busy', 'Besetzt');
        statusColor = p.dangerRed;
        break;
      case 'ringing':
        status = app.trEn('Çalıyor', 'Ringing', 'Klingelt');
        statusColor = p.amberGlow;
        break;
      default:
        status = app.trEn('Görüşüldü', 'Answered', 'Angenommen');
        statusColor = p.onlineGreen;
    }

    String endedByText;
    if (log.endedAt == null) {
      endedByText = '—';
    } else if (log.endedBy == null) {
      endedByText = app.trEn('Bağlantı kesildi / sistem', 'Connection lost / system', 'Verbindung getrennt / System');
    } else if (log.endedBy == myUid) {
      endedByText = app.trEn('Siz kapattınız', 'You hung up', 'Du hast aufgelegt');
    } else if (log.endedBy == log.callerId) {
      endedByText = app.trEn('${log.callerName} kapattı', '${log.callerName} hung up', '${log.callerName} hat aufgelegt');
    } else if (log.endedBy == log.receiverId) {
      endedByText = app.trEn('${log.receiverName} kapattı', '${log.receiverName} hung up', '${log.receiverName} hat aufgelegt');
    } else {
      endedByText = app.trEn('Bir katılımcı kapattı', 'A participant hung up', 'Ein Teilnehmer hat aufgelegt');
    }

    Widget row(IconData icon, String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.pillBg, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: p.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(app.trEn('Arama ayrıntısı', 'Call details', 'Anrufdetails'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          JuzzioGlass(
            radius: 28,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                JuzzioGlassAvatar(imageUrl: partnerAvatar, name: partnerName, radius: 40),
                const SizedBox(height: 12),
                Text(partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(p, log.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        log.isVideo ? app.trEn('Görüntülü', 'Video', 'Video') : app.trEn('Sesli', 'Voice', 'Sprache')),
                    _chip(p, isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
                        isOutgoing ? app.trEn('Giden', 'Outgoing', 'Ausgehend') : app.trEn('Gelen', 'Incoming', 'Eingehend')),
                    _chip(p, Icons.circle, status, color: statusColor),
                  ],
                ),
                if (onCallBack != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.coolButtonBg,
                        foregroundColor: p.coolButtonFg,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCallBack!();
                      },
                      icon: Icon(log.isVideo ? Icons.videocam_rounded : Icons.call_rounded),
                      label: Text(app.trEn('Tekrar ara', 'Call again', 'Erneut anrufen'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          JuzzioGlass(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                row(Icons.calendar_today_rounded, app.trEn('Tarih', 'Date', 'Datum'), _date(log.createdAt)),
                row(Icons.ring_volume_rounded, app.trEn('Arama başladı', 'Call started', 'Anruf begonnen'), _clock(log.createdAt)),
                row(Icons.call_rounded, app.trEn('Cevaplandı', 'Answered', 'Angenommen'), _clock(log.answeredAt)),
                row(Icons.call_end_rounded, app.trEn('Sonlandı', 'Ended', 'Beendet'), _clock(log.endedAt)),
                row(Icons.timer_rounded, app.trEn('Görüşme süresi', 'Talk time', 'Gesprächsdauer'), _duration(sec)),
                row(Icons.back_hand_rounded, app.trEn('İlk kim kapattı', 'Who hung up first', 'Wer zuerst auflegte'), endedByText),
                if (log.dataKb > 0)
                  row(Icons.data_usage_rounded, app.trEn('Veri kullanımı', 'Data used', 'Datennutzung'),
                      log.dataKb >= 1024 ? '${(log.dataKb / 1024).toStringAsFixed(1)} MB' : '${log.dataKb} KB'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(JuzzioPalette p, IconData icon, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.pillBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 9 : 14, color: color ?? p.textPrimary),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
