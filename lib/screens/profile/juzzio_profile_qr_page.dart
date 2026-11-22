// =============================================================================
// JUZZIO 2.1 — Profil Karekodum (tasarım: "PROFİL KAREKOD")
//  • Limon çerçeveli kart: avatar (mavi tik), ad, @kullanıcı adı, ortasında J logolu beyaz karekod
//  • Eylemler: Profil Bağlantısını Kopyala · Paylaş · İndir (galeriye PNG)
//  • "Karekod Tara": telefonun kamerasıyla okutulan bağlantı Juzzio'yu açar; burada bağlantı
//    ya da kullanıcı adı yapıştırılarak da profil açılabilir.
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/app_theme_and_locale.dart';
import '../../core/native_bridge.dart';
import '../../core/theme/juzzio_glass.dart';
import '../../core/theme/juzzio_aurora.dart';
import '../../services/supabase_service.dart';
import '../../widgets/juzzio_brand.dart';
import '../../widgets/juzzio_profile_qr.dart';
import '../../widgets/juzzio_neon_kit.dart';
import '../../widgets/social_common_widgets.dart';

/// Paylaşılan profil bağlantısından ya da yazılan metinden kullanıcı adını çıkarır (saf; test edilir).
String? juzzioUsernameFromScan(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t);
  if (uri != null && uri.hasScheme) {
    final u = uri.queryParameters['u'];
    if (u != null && RegExp(r'^[A-Za-z0-9_.]{2,32}$').hasMatch(u)) return u.toLowerCase();
    return null;
  }
  final name = t.startsWith('@') ? t.substring(1) : t;
  return RegExp(r'^[A-Za-z0-9_.]{2,32}$').hasMatch(name) ? name.toLowerCase() : null;
}

class JuzzioProfileQrPage extends StatefulWidget {
  const JuzzioProfileQrPage({super.key, required this.profile, this.onOpenUsername});
  final JuzzioUserProfile profile;
  final void Function(String username)? onOpenUsername;

  @override
  State<JuzzioProfileQrPage> createState() => _JuzzioProfileQrPageState();
}

class _JuzzioProfileQrPageState extends State<JuzzioProfileQrPage> {
  final _app = JuzzioAppController.instance;
  final _qrKey = GlobalKey();
  bool _saving = false;

  String get _link => JuzzioNative.profileLink(widget.profile.username);

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link));
    _snack(_app.trEn('Bağlantı kopyalandı.', 'Link copied.', 'Link kopiert.'));
  }

  Future<void> _share() async {
    final ok = await JuzzioNative.shareText(
      _app.trEn("Trawave'de beni ekle: $_link", 'Add me on Trawave: $_link', 'Füge mich auf Trawave hinzu: $_link'),
      title: _app.trEn('Profili paylaş', 'Share profile', 'Profil teilen'),
    );
    if (!ok) await _copy();
  }

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getApplicationSupportDirectory();
      final name = 'juzzio_qr_${widget.profile.username}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      final ok = await JuzzioNative.saveToGallery(path: file.path, mime: 'image/png', name: name, kind: 'image');
      _snack(ok
          ? _app.trEn('Karekod galeriye kaydedildi.', 'QR code saved to gallery.', 'QR-Code gespeichert.')
          : _app.trEn('Kaydedilemedi.', 'Could not save.', 'Speichern fehlgeschlagen.'));
    } catch (_) {
      _snack(_app.trEn('Kaydedilemedi.', 'Could not save.', 'Speichern fehlgeschlagen.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// v2.1: Android/iOS'ta kamera ile canlı tarama; desteklenmeyen
  /// platformda (masaüstü/web) veya kamera reddedilince yapıştırma.
  Future<void> _scan() async {
    final camera = Platform.isAndroid || Platform.isIOS;
    if (!camera) return _scanPaste();
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => JuzzioQrCameraScanPage(app: _app)),
    );
    if (res == null) return;
    if (res == JuzzioQrCameraScanPage.pasteSignal) return _scanPaste();
    _openScanned(res);
  }

  void _openScanned(String res) {
    final u = juzzioUsernameFromScan(res);
    if (u == null) {
      _snack(_app.trEn('Geçerli bir Trawave bağlantısı değil.', 'Not a valid Trawave link.', 'Kein gültiger Trawave-Link.'));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onOpenUsername?.call(u);
  }

  Future<void> _scanPaste() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_app.trEn('Karekod Tara', 'Scan QR Code', 'QR-Code scannen')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _app.trEn(
                'Telefonunun kamerasını karekoda tut: bağlantı Trawave\'i açar. Ya da bağlantıyı / kullanıcı adını buraya yapıştır.',
                'Point your phone camera at the code — the link opens Trawave. Or paste the link / username here.',
                'Richte die Kamera auf den Code oder füge den Link / Benutzernamen hier ein.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '@kullaniciadi', prefixIcon: Icon(Icons.qr_code_scanner_rounded)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_app.trEn('Vazgeç', 'Cancel', 'Abbrechen'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(_app.trEn('Profili aç', 'Open profile', 'Profil öffnen'))),
        ],
      ),
    );
    ctrl.dispose();
    if (res == null) return;
    _openScanned(res);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final glow = JuzzioGlassTokens.glow;
    final name = p.displayName.trim().isEmpty ? p.username : p.displayName.trim();
    return JuzzioAuroraPage(child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            JuzzioScreenHeader(
              title: _app.trEn('Profil Karekodum', 'My Profile QR', 'Mein Profil-QR'),
              subtitle: _app.trEn("Beni Trawave'de eklemek için karekodu tara.", 'Scan the code to add me on Trawave.',
                  'Scanne den Code, um mich auf Trawave hinzuzufügen.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: JuzzioNeonCard(
                highlighted: true,
                radius: 30,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: glow, width: 2)),
                          child: JuzzioUserAvatar(imageUrl: p.avatarUrl, displayName: name, radius: 40),
                        ),
                        if (p.isVerified)
                          Positioned(
                            right: -2,
                            bottom: 2,
                            child: Container(
                              decoration: BoxDecoration(color: JuzzioGlassTokens.space.depth.last, shape: BoxShape.circle),
                              child: Icon(Icons.verified_rounded, color: glow, size: 22),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(name, style: TextStyle(color: JuzzioGlassTokens.heading, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('@${p.username}', style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 13)),
                    const SizedBox(height: 16),
                    RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                        child: SizedBox(
                          width: 200,
                          height: 200,
                          // v2.2.0: profil fotoğrafındaki çevirmeli kartla birebir aynı karekod
                          // (aynı düzey, yuvarlak noktalar, kart renginde yuvarlak gözler)
                          child: JuzzioProfileQr(
                            data: _link,
                            color: juzzioProfileCardColor(p.cardBgColor, const Color(0xFF2563EB)),
                            size: 200,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circle(Icons.link_rounded, _app.trEn('Profil Bağlantısını\nKopyala', 'Copy Profile\nLink', 'Profil-Link\nkopieren'), _copy),
                  _circle(Icons.ios_share_rounded, _app.trEn('Paylaş', 'Share', 'Teilen'), _share),
                  _circle(Icons.download_rounded, _app.trEn('İndir', 'Download', 'Laden'), _saving ? null : _download),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: JuzzioNeonCard(
                onTap: _scan,
                radius: 26,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                highlighted: true,
                child: Row(children: [
                  Icon(Icons.qr_code_scanner_rounded, color: JuzzioGlassTokens.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_app.trEn('Karekod Tara', 'Scan QR Code', 'QR-Code scannen'),
                        style: TextStyle(color: JuzzioGlassTokens.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: JuzzioGlassTokens.textSecondary),
                ]),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _circle(IconData icon, String label, VoidCallback? onTap) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Material(
            color: JuzzioGlassTokens.spaceCard,
            shape: CircleBorder(side: BorderSide(color: JuzzioGlassTokens.spaceCardBorder)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 52, height: 52, child: Icon(icon, color: JuzzioGlassTokens.textPrimary)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(color: JuzzioGlassTokens.textSecondary, fontSize: 11.5)),
        ],
      ),
    );
  }
}


/// v2.1 — Kamera ile Juzzio karekodu tarama ekranı (tasarım: QR Kod Tara).
/// İlk geçerli kod bulunduğunda ham metni döndürür; "Bağlantı yapıştır"
/// [pasteSignal] döndürür. Görüntü cihazda işlenir, hiçbir yere yüklenmez.
class JuzzioQrCameraScanPage extends StatefulWidget {
  const JuzzioQrCameraScanPage({super.key, required this.app});
  final JuzzioAppController app;
  static const pasteSignal = '\u0000paste';

  @override
  State<JuzzioQrCameraScanPage> createState() => _JuzzioQrCameraScanPageState();
}

class _JuzzioQrCameraScanPageState extends State<JuzzioQrCameraScanPage> {
  final MobileScannerController _cam = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _torch = false;

  String _t(String tr, String en, String de) => widget.app.trEn(tr, en, de);

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty && juzzioUsernameFromScan(v) != null) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _cam,
            onDetect: _onDetect,
            errorBuilder: (ctx, err, [child]) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _t('Kameraya erişilemedi. İzin verip tekrar dene ya da bağlantıyı yapıştır.',
                        'Camera unavailable. Allow access and retry, or paste the link.',
                        'Kamera nicht verfügbar. Erlaube den Zugriff oder füge den Link ein.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ]),
              ),
            ),
          ),
          // Tarama çerçevesi
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: JuzzioGlassTokens.glowText, width: 3),
                  boxShadow: [BoxShadow(color: JuzzioGlassTokens.glowText.withValues(alpha: 0.35), blurRadius: 24)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(_t('QR Kod Tara', 'Scan QR Code', 'QR-Code scannen'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _cam.toggleTorch();
                        if (mounted) setState(() => _torch = !_torch);
                      },
                      icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                    ),
                  ]),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(children: [
                    Text(
                      _t('Karekodu çerçevenin içine hizala', 'Align the QR code inside the frame', 'Richte den QR-Code im Rahmen aus'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(JuzzioQrCameraScanPage.pasteSignal),
                      icon: Icon(Icons.link_rounded, color: JuzzioGlassTokens.glowText),
                      label: Text(_t('Bağlantı yapıştır', 'Paste link', 'Link einfügen'),
                          style: TextStyle(color: JuzzioGlassTokens.glowText, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
