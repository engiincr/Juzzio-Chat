// =============================================================================
// JUZZIO v0.7.0 — Hata bildir / geri bildirim (ekran görüntüsüyle)
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import '../core/theme/juzzio_glass.dart';
import '../services/supabase_service.dart';

class JuzzioFeedbackPage extends StatefulWidget {
  const JuzzioFeedbackPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JuzzioFeedbackPage()));

  @override
  State<JuzzioFeedbackPage> createState() => _JuzzioFeedbackPageState();
}

class _JuzzioFeedbackPageState extends State<JuzzioFeedbackPage> {
  final _app = JuzzioAppController.instance;
  final _msg = TextEditingController();
  String _kind = 'bug';
  File? _image;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2200);
      if (x == null) return;
      setState(() => _image = File(x.path));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _msg.text.trim();
    if (text.length < 5) {
      setState(() => _error = _app.trEn('Lütfen sorunu en az birkaç kelimeyle anlat.', 'Please describe the issue in a few words.',
          'Bitte beschreibe das Problem in ein paar Worten.'));
      return;
    }
    final svc = SupabaseService.instance;
    final uid = svc.currentUserId;
    if (uid == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      var url = '';
      if (_image != null) url = await svc.uploadPublicImage(_image!, prefix: 'feedback');
      await svc.client.from('app_feedback').insert({
        'user_id': uid,
        'kind': _kind,
        'message': text,
        'image_url': url,
        'app_version': '${JuzzioConfig.appVersion}+${JuzzioConfig.appVersionCode}',
        'device_info': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_app.trEn('Teşekkürler! Bildirimin geliştiriciye ulaştı.', 'Thanks! Your report reached the developer.',
            'Danke! Deine Meldung ist angekommen.')),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      final raw = e.toString();
      setState(() => _error = raw.contains('feedback_rate_limited')
          ? _app.trEn('Çok sık bildirim gönderdin. Lütfen biraz sonra tekrar dene.', 'Too many reports. Please try again later.',
              'Zu viele Meldungen. Bitte später erneut.')
          : svc.friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(_app.isDark);
    Widget kindChip(String id, IconData icon, String label) {
      final sel = _kind == id;
      return ChoiceChip(
        avatar: Icon(icon, size: 16, color: sel ? p.coolButtonFg : p.textPrimary),
        label: Text(label),
        selected: sel,
        showCheckmark: false,
        labelStyle: TextStyle(color: sel ? p.coolButtonFg : p.textPrimary, fontWeight: FontWeight.w800),
        selectedColor: p.coolButtonBg,
        backgroundColor: p.pillBg,
        side: BorderSide(color: p.glassBorder),
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => _kind = id),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        title: Text(_app.trEn('Hata bildir / Geri bildirim', 'Report a bug / Feedback', 'Fehler melden / Feedback'),
            style: const TextStyle(fontFamily: JuzzioConfig.fontRegularBold, fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              kindChip('bug', Icons.bug_report_rounded, _app.trEn('Hata', 'Bug', 'Fehler')),
              kindChip('feedback', Icons.chat_rounded, _app.trEn('Geri bildirim', 'Feedback', 'Feedback')),
              kindChip('idea', Icons.lightbulb_rounded, _app.trEn('Öneri', 'Idea', 'Idee')),
            ],
          ),
          const SizedBox(height: 12),
          JuzzioGlass(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              controller: _msg,
              minLines: 5,
              maxLines: 12,
              maxLength: 4000,
              style: TextStyle(color: p.textPrimary, height: 1.4),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: _app.trEn(
                    'Ne oldu? Hangi ekranda, ne yaptığında? (Kişisel bilgi, şifre veya kart bilgisi yazma.)',
                    'What happened? On which screen? (Do not include passwords or personal data.)',
                    'Was ist passiert? Auf welchem Bildschirm? (Keine Passwörter oder persönlichen Daten.)'),
                hintStyle: TextStyle(color: p.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _pick,
            child: Container(
              height: _image == null ? 110 : 260,
              decoration: BoxDecoration(
                color: p.pillBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.glassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: _image == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, color: p.textPrimary, size: 30),
                        const SizedBox(height: 6),
                        Text(_app.trEn('Ekran görüntüsü ekle (isteğe bağlı)', 'Add a screenshot (optional)', 'Screenshot hinzufügen (optional)'),
                            style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w700)),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_image!, fit: BoxFit.contain),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filledTonal(
                            onPressed: () => setState(() => _image = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: p.dangerRed, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.coolButtonBg,
              foregroundColor: p.coolButtonFg,
              minimumSize: const Size.fromHeight(50),
              shape: const StadiumBorder(),
            ),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.coolButtonFg))
                : const Icon(Icons.send_rounded),
            label: Text(_app.trEn('Gönder', 'Send', 'Senden'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          Text(
            _app.trEn(
              'Gönderdiğin metin, ekran görüntüsü, uygulama sürümü ve cihaz işletim sistemi bilgisi yalnızca hatayı çözmek için geliştiriciye iletilir.',
              'Your text, screenshot, app version and OS version are sent to the developer only to fix the issue.',
              'Text, Screenshot, App- und OS-Version gehen nur zur Fehlerbehebung an den Entwickler.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
