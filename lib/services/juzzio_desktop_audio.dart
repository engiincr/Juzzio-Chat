// =============================================================================
// JUZZIO GM-003 — Masaüstü (Windows/macOS/Linux) arama ses aygıtları
//  Sorun: Windows'ta WebRTC karşı tarafın sesini "Varsayılan İLETİŞİM aygıtı"na gönderir.
//  Bu aygıt kapalı bir kulaklık, monitör ya da sanal bir aygıt (ör. FxSound) olunca karşı tarafın
//  sesi hiç duyulmaz; çeviri veri kanalından geldiği için çalışmaya devam eder.
//  Çözüm: arama bağlanınca çıkış aygıtı AÇIKÇA seçilir (kullanıcının kayıtlı seçimi, yoksa
//  Windows'un normal varsayılan aygıtı). Kullanıcı arama ekranından çıkış ve mikrofon seçebilir;
//  seçim cihazda saklanır ve sonraki aramalarda uygulanır. Aygıt takılıp çıkarılınca yeniden uygulanır.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:path_provider/path_provider.dart';

/// Saf kural (testlerde de kullanılır): kayıtlı seçim varsa o (önce kimlik, sonra ad ile);
/// yoksa sistemin normal varsayılanı ("Default"/"Varsayılan" etiketli), o da yoksa ilk aygıt.
/// "Communication/İletişim" etiketli sanal girişler varsayılan olarak seçilmez.
MediaDevice? juzzioPickDevice(List<MediaDevice> devices,
    {String? savedId, String? savedLabel}) {
  if (devices.isEmpty) return null;
  if (savedId != null && savedId.isNotEmpty) {
    for (final d in devices) {
      if (d.deviceId == savedId) return d;
    }
  }
  if (savedLabel != null && savedLabel.isNotEmpty) {
    for (final d in devices) {
      if (d.label == savedLabel) return d;
    }
  }
  bool isDefault(MediaDevice d) {
    final l = d.label.toLowerCase();
    return d.deviceId == 'default' ||
        l.startsWith('default') ||
        l.startsWith('varsayılan');
  }

  bool isComm(MediaDevice d) {
    final l = d.label.toLowerCase();
    return d.deviceId == 'communications' ||
        l.startsWith('communication') ||
        l.startsWith('iletişim');
  }

  for (final d in devices) {
    if (isDefault(d)) return d;
  }
  for (final d in devices) {
    if (!isComm(d)) return d;
  }
  return devices.first;
}

class JuzzioDesktopAudio extends ChangeNotifier {
  JuzzioDesktopAudio._();
  static final JuzzioDesktopAudio instance = JuzzioDesktopAudio._();

  bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  List<MediaDevice> outputs = const [];
  List<MediaDevice> inputs = const [];
  MediaDevice? selectedOutput;
  MediaDevice? selectedInput;

  /// Son hata (arayüzde kısa bilgi olarak gösterilir; boşsa sorun yok)
  String? lastError;

  Room? _room;
  StreamSubscription<List<MediaDevice>>? _deviceSub;
  Map<String, String> _saved = const {};
  bool _loaded = false;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/juzzio_desktop_audio.json');
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (f.existsSync()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map)
          _saved = raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_saved));
    } catch (_) {}
  }

  Future<void> refresh() async {
    if (!supported) return;
    try {
      final all = await Hardware.instance.enumerateDevices();
      outputs = all.where((d) => d.kind == 'audiooutput').toList();
      inputs = all.where((d) => d.kind == 'audioinput').toList();
    } catch (e) {
      lastError = 'Ses aygıtları listelenemedi: $e';
    }
    notifyListeners();
  }

  /// Arama bağlandıktan sonra çağrılır: kayıtlı/varsayılan çıkış ve (kayıtlıysa) mikrofon uygulanır.
  Future<void> attach(Room room) async {
    if (!supported) return;
    _room = room;
    await _load();
    await refresh();
    _deviceSub ??= Hardware.instance.onDeviceChange.stream
        .listen((_) => unawaited(_onDevicesChanged()));
    await _applyOutput(juzzioPickDevice(outputs,
        savedId: _saved['outId'], savedLabel: _saved['outLabel']));
    final savedIn = _saved['inId'] ?? _saved['inLabel'];
    if (savedIn != null && savedIn.isNotEmpty) {
      await _applyInput(juzzioPickDevice(inputs,
          savedId: _saved['inId'], savedLabel: _saved['inLabel']));
    }
  }

  /// Karşı tarafın ses izi geldiğinde yeniden uygulanır (bazı sürücülerde ilk izle oynatıcı sıfırlanır).
  Future<void> reapply() async {
    if (!supported || _room == null) return;
    await _applyOutput(selectedOutput ??
        juzzioPickDevice(outputs,
            savedId: _saved['outId'], savedLabel: _saved['outLabel']));
  }

  Future<void> detach() async {
    _room = null;
    await _deviceSub?.cancel();
    _deviceSub = null;
  }

  Future<void> selectOutput(MediaDevice d) async {
    _saved = {..._saved, 'outId': d.deviceId, 'outLabel': d.label};
    unawaited(_save());
    await _applyOutput(d);
  }

  Future<void> selectInput(MediaDevice d) async {
    _saved = {..._saved, 'inId': d.deviceId, 'inLabel': d.label};
    unawaited(_save());
    await _applyInput(d);
  }

  Future<void> _onDevicesChanged() async {
    final before = selectedOutput?.deviceId;
    await refresh();
    final stillThere = outputs.any((d) => d.deviceId == before);
    if (!stillThere || _room != null) {
      await _applyOutput(juzzioPickDevice(outputs,
          savedId: _saved['outId'], savedLabel: _saved['outLabel']));
    }
  }

  Future<void> _applyOutput(MediaDevice? d) async {
    if (d == null) {
      lastError = 'Ses çıkış aygıtı bulunamadı.';
      notifyListeners();
      return;
    }
    try {
      final room = _room;
      if (room != null) {
        await room.setAudioOutputDevice(d);
      } else {
        await Hardware.instance.selectAudioOutput(d);
      }
      selectedOutput = d;
      lastError = null;
    } catch (e) {
      lastError = 'Çıkış aygıtı seçilemedi (${d.label}): $e';
    }
    notifyListeners();
  }

  Future<void> _applyInput(MediaDevice? d) async {
    if (d == null) return;
    try {
      final room = _room;
      if (room != null) {
        await room.setAudioInputDevice(d);
      } else {
        await Hardware.instance.selectAudioInput(d);
      }
      selectedInput = d;
      lastError = null;
    } catch (e) {
      lastError = 'Mikrofon seçilemedi (${d.label}): $e';
    }
    notifyListeners();
  }
}
