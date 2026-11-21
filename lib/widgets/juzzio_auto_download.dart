// Juzzio 2.1 (Faz 8.2) — Medya otomatik indirme kuralı
//  'always' → her ağda otomatik (varsayılan) · 'wifi' → yalnız Wi-Fi/Ethernet · 'never' → dokununca
//  Kendi gönderdiğim medya her zaman görünür. Bir kez dokunulan medya bu oturumda açık kalır.

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../services/juzzio_net.dart';

/// Bu medya şimdi otomatik yüklenmeli mi? (saf; test edilir)
bool juzzioShouldAutoDownload(String mode, {required bool unmetered, required bool isMine}) {
  if (isMine) return true;
  switch (mode) {
    case 'never':
      return false;
    case 'wifi':
      return unmetered;
    default:
      return true;
  }
}

class JuzzioAutoDownloadGate extends StatefulWidget {
  const JuzzioAutoDownloadGate({super.key, required this.id, required this.isMine, required this.child, this.isVideo = false});
  final String id;
  final bool isMine;
  final bool isVideo;
  final Widget child;

  /// Bu oturumda elle açılan medya kimlikleri
  static final Set<String> opened = <String>{};

  @override
  State<JuzzioAutoDownloadGate> createState() => _JuzzioAutoDownloadGateState();
}

class _JuzzioAutoDownloadGateState extends State<JuzzioAutoDownloadGate> {
  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([app, JuzzioNet.instance]),
      builder: (context, _) {
        final allowed = JuzzioAutoDownloadGate.opened.contains(widget.id) ||
            juzzioShouldAutoDownload(app.autoDownloadMode, unmetered: JuzzioNet.instance.unmetered, isMine: widget.isMine);
        if (allowed) return widget.child;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => JuzzioAutoDownloadGate.opened.add(widget.id)),
          child: Container(
            height: 150,
            width: 220,
            alignment: Alignment.center,
            color: Colors.black.withValues(alpha: 0.25),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.isVideo ? Icons.play_circle_outline_rounded : Icons.download_rounded, color: Colors.white, size: 36),
              const SizedBox(height: 6),
              Text(
                widget.isVideo
                    ? app.trEn('Videoyu indirmek için dokun', 'Tap to download video', 'Tippen zum Laden')
                    : app.trEn('Fotoğrafı indirmek için dokun', 'Tap to download photo', 'Tippen zum Laden'),
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        );
      },
    );
  }
}
