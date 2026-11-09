// =============================================================================
// JUZZIO v0.9.5 — Güvenli takip (SOS / "eve vardım" modu)
//  • Bir sohbet seçilir (aile/arkadaş grubu ya da kişi), süre ve hareketsizlik sınırı belirlenir.
//  • Uygulama açıkken dakikada bir konum + pil gönderilir.
//  • Sunucu (her dakika): süre doldu ama "Vardım" denmediyse, belirtilen süre boyunca konum
//    gelmediyse/hareket yoksa ya da pil %5'e düştüyse sohbet üyelerine en yüksek öncelikli
//    🆘 bildirim + son konum bağlantısı gider. Uygulama kapansa bile bu denetim sunucuda sürer.
// =============================================================================

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_theme_and_locale.dart';
import '../services/supabase_service.dart';

/// İki konum arası mesafe (metre) — hareket algılama için (haversine).
double juzzioDistanceMeters(double lat1, double lng1, double lat2, double lng2) => Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

class JuzzioSafetyWalkScreen extends StatefulWidget {
  const JuzzioSafetyWalkScreen({super.key, required this.roomId, required this.roomTitle});
  final String roomId;
  final String roomTitle;

  static Future<void> open(BuildContext context, {required String roomId, required String roomTitle}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => JuzzioSafetyWalkScreen(roomId: roomId, roomTitle: roomTitle)));

  @override
  State<JuzzioSafetyWalkScreen> createState() => _JuzzioSafetyWalkScreenState();
}

class _JuzzioSafetyWalkScreenState extends State<JuzzioSafetyWalkScreen> {
  final _app = JuzzioAppController.instance;
  final _db = SupabaseService.instance.client;
  final _target = TextEditingController(text: '');
  int _minutes = 30;
  int _inactivity = 15;
  String? _sessionId;
  String _status = 'idle';
  DateTime? _endsAt;
  Timer? _pingTimer;
  Timer? _tick;
  Position? _last;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _tick?.cancel();
    _target.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      final row = await _db.from('safety_sessions').select().eq('user_id', uid).eq('status', 'active').maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _sessionId = row['id'].toString();
          _status = 'active';
          _endsAt = DateTime.tryParse('${row['expires_at']}')?.toLocal();
        });
        _startLoops();
      }
    } catch (_) {}
  }

  Future<bool> _ensureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = _app.trEn('Konum servisi kapalı.', 'Location services are off.', 'Standortdienste sind aus.'));
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => _error = _app.trEn('Konum izni gerekli.', 'Location permission required.', 'Standortberechtigung erforderlich.'));
      return false;
    }
    return true;
  }

  Future<void> _start() async {
    if (_busy || !await _ensureLocation()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await _db.rpc('start_safety_session', params: {
        'p_room': widget.roomId,
        'p_minutes': _minutes,
        'p_target': _target.text.trim(),
        'p_inactivity_min': _inactivity,
      });
      if (!mounted) return;
      setState(() {
        _sessionId = id.toString();
        _status = 'active';
        _endsAt = DateTime.now().add(Duration(minutes: _minutes));
      });
      _startLoops();
      await _ping();
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startLoops() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _ping() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      final moved = _last == null || juzzioDistanceMeters(_last!.latitude, _last!.longitude, pos.latitude, pos.longitude) > 25;
      _last = pos;
      int? battery;
      try {
        battery = await Battery().batteryLevel;
      } catch (_) {}
      final r = await _db.rpc('safety_ping', params: {
        'p_session': id,
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
        'p_battery': battery,
        'p_moved': moved,
      });
      if (!mounted) return;
      final st = r.toString();
      if (st != 'active') {
        _pingTimer?.cancel();
        setState(() => _status = st == 'sos_triggered' ? 'sos' : 'idle');
      }
    } catch (_) {}
  }

  Future<void> _finish(bool arrived) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await _db.rpc('safety_finish', params: {'p_session': id, 'p_arrived': arrived});
      HapticFeedback.mediumImpact();
      _pingTimer?.cancel();
      _tick?.cancel();
      if (mounted) {
        setState(() {
          _status = arrived ? 'arrived' : 'idle';
          _sessionId = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    }
  }

  Future<void> _sosNow() async {
    final id = _sessionId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('Acil yardım iste?', 'Ask for help now?', 'Jetzt Hilfe anfordern?')),
        content: Text(_app.trEn('${widget.roomTitle} sohbetindeki herkese son konumunla 🆘 bildirimi gider.', 'Everyone in ${widget.roomTitle} gets an 🆘 alert with your last location.', 'Alle in ${widget.roomTitle} erhalten einen Alarm.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('SOS')),
        ],
      ),
    );
    if (ok != true) return;
    await _ping();
    try {
      await _db.rpc('safety_sos_now', params: {'p_session': id});
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _status = 'sos');
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.instance.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    final left = _endsAt?.difference(DateTime.now());
    return Scaffold(
      backgroundColor: p.bgPrimary,
      appBar: AppBar(title: Text(_app.trEn('Güvenli takip', 'Safety check', 'Sicherheitscheck'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('${_app.trEn('Uyarı gidecek sohbet', 'Alerts go to', 'Warnungen an')}: ${widget.roomTitle}', style: TextStyle(color: p.textSecondary)),
        const SizedBox(height: 16),
        if (_status == 'active') ...[
          Center(
            child: Text(
              left == null || left.isNegative ? '00:00' : '${left.inMinutes.toString().padLeft(2, '0')}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900),
            ),
          ),
          Center(child: Text(_app.trEn('Konumun dakikada bir paylaşılıyor', 'Sharing location every minute', 'Standort jede Minute'), style: TextStyle(color: p.textSecondary))),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF34C759), minimumSize: const Size.fromHeight(56)),
            onPressed: () => _finish(true),
            icon: const Icon(Icons.home_rounded),
            label: Text(_app.trEn('Vardım, güvendeyim', 'I arrived safely', 'Sicher angekommen')),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(56)),
            onPressed: _sosNow,
            icon: const Icon(Icons.sos_rounded),
            label: Text(_app.trEn('ACİL YARDIM (SOS)', 'EMERGENCY (SOS)', 'NOTFALL (SOS)')),
          ),
          TextButton(onPressed: () => _finish(false), child: Text(_app.trEn('Takibi iptal et', 'Cancel tracking', 'Abbrechen'))),
        ] else ...[
          if (_status == 'arrived')
            Card(child: ListTile(leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759)), title: Text(_app.trEn('Güvende olduğun bildirildi.', 'Marked as safe.', 'Als sicher markiert.')))),
          if (_status == 'sos')
            Card(color: Colors.red.withValues(alpha: 0.15), child: ListTile(leading: const Icon(Icons.sos_rounded, color: Colors.red), title: Text(_app.trEn('SOS gönderildi. Yardım gelene kadar güvenli bir yerde kal.', 'SOS sent. Stay somewhere safe.', 'SOS gesendet.')))),
          TextField(controller: _target, maxLength: 120, decoration: InputDecoration(labelText: _app.trEn('Nereye gidiyorsun? (isteğe bağlı)', 'Where are you going? (optional)', 'Wohin? (optional)'))),
          Text(_app.trEn('Varış süresi', 'Expected arrival in', 'Ankunft in'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final m in const [15, 30, 60, 120])
              ChoiceChip(label: Text('$m ${_app.trEn('dk', 'min', 'Min')}'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
          ]),
          const SizedBox(height: 10),
          Text(_app.trEn('Hareketsiz kalırsam uyar', 'Alert if no movement for', 'Alarm ohne Bewegung nach'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 8, children: [
            for (final m in const [10, 15, 30])
              ChoiceChip(label: Text('$m ${_app.trEn('dk', 'min', 'Min')}'), selected: _inactivity == m, onSelected: (_) => setState(() => _inactivity = m)),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.shield_rounded),
            label: Text(_app.trEn('Takibi başlat', 'Start safety check', 'Starten')),
          ),
          const SizedBox(height: 12),
          Text(
            _app.trEn('Not: Telefonun kapanırsa veya internet giderse konum gelmez; sunucu bu durumda belirlediğin hareketsizlik süresi sonunda otomatik uyarır. Acil durumda 112\'yi arayın.',
                'If your phone dies or goes offline, no location arrives; the server then alerts automatically after the no-movement limit. In an emergency call your local emergency number.',
                'Im Notfall die Notrufnummer wählen.'),
            style: TextStyle(color: p.textSecondary, fontSize: 12),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      ]),
    );
  }
}
