// =============================================================================
// JUZZIO v0.9.5 — Yönetici: Güven puanı (moderasyon önceliği)
//  Puan sunucuda şeffaf kurallarla hesaplanır (bkz. juzzio_trust_score). 30'un altındaki
//  hesaplar günde en fazla 3 gönderi paylaşabilir.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/supabase_service.dart';
import '../widgets/juzzio_cloth_refresh.dart';

class JuzzioAdminTrustTab extends StatefulWidget {
  const JuzzioAdminTrustTab({super.key, required this.token});
  final String token;

  @override
  State<JuzzioAdminTrustTab> createState() => _JuzzioAdminTrustTabState();
}

class _JuzzioAdminTrustTabState extends State<JuzzioAdminTrustTab> {
  final _app = JuzzioAppController.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await SupabaseService.instance.client.rpc('admin_trust_list', params: {'p_token': widget.token, 'p_limit': 100});
      if (!mounted) return;
      setState(() {
        _rows = [for (final x in (r is List ? r : const [])) Map<String, dynamic>.from(x as Map)];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = SupabaseService.instance.friendlyError(e);
        });
      }
    }
  }

  Color _color(int s) => s < 30 ? const Color(0xFFE53935) : (s < 60 ? const Color(0xFFFFA000) : const Color(0xFF43A047));

  @override
  Widget build(BuildContext context) {
    return JuzzioClothRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          _app.trEn('Son 30 günde şikâyet edilen veya ihlal alan hesaplar, en düşük güven puanı en üstte. 30 altı: günde en fazla 3 gönderi.',
              'Accounts reported or with strikes in the last 30 days, lowest trust first. Below 30: max 3 posts per day.', 'Gemeldete Konten, niedrigstes Vertrauen zuerst.'),
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        if (!_loading && _rows.isEmpty && _error == null) Text(_app.trEn('Şikâyet edilen hesap yok.', 'No reported accounts.', 'Keine gemeldeten Konten.')),
        for (final r in _rows)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _color(int.tryParse('${r['score']}') ?? 0),
                child: Text('${r['score']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              title: Text('${r['display_name'] ?? ''}'),
              subtitle: Text('@${r['username'] ?? ''}'),
            ),
          ),
      ]),
    );
  }
}
