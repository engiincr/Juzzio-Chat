// =============================================================================
// JUZZIO v0.8.0 — Şifreli sohbet yedeği (Google Drive)
//
//  • Yedek, kullanıcının KENDİ Google Drive hesabındaki gizli uygulama klasörüne
//    (appDataFolder) yazılır; Drive'da başka uygulamalar ve biz göremeyiz.
//  • İçerik, kullanıcının belirlediği en az 8 karakterlik yedek şifresinden
//    Argon2id (bellek-yoğun, GPU/ASIC saldırısına dayanıklı) ile türetilen 256 bit
//    anahtarla AES-256-GCM şifrelenir. Şifre hiçbir yere gönderilmez, saklanmaz.
//    256 bit simetrik şifreleme kuantum bilgisayarlara karşı da dayanıklıdır.
//  • Yedek dosyası hesap kimliğine (UUID) bağlıdır: hesap silinip yeniden açılırsa
//    eski yedek bu yeni hesaba yüklenmez ("Hesabınız için yedekleme bulunamadı").
//  • İçerik: uçtan uca şifreleme anahtarları (eski mesajlar yeni telefonda açılır),
//    tüm uygulama ayarları (tema, gizlilik, bildirim, sohbet tercihleri, yıldızlı
//    mesajlar, engellenen kullanıcı adları), zil sesi ve yakın arkadaş tercihleri.
//    Mesajlar, arama geçmişi, engellenenler ve profil zaten hesabınızda (sunucuda)
//    durur; giriş yapınca geri gelir, şifreli olanlar geri yüklenen anahtarla açılır.
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/app_theme_and_locale.dart';
import '../core/config.dart';
import 'juzzio_e2ee.dart';
import 'supabase_service.dart';

class JuzzioBackupException implements Exception {
  final String code;
  const JuzzioBackupException(this.code);
  @override
  String toString() => code;
}

class JuzzioBackupInfo {
  final String fileId;
  final DateTime? modified;
  final int size;
  const JuzzioBackupInfo(this.fileId, this.modified, this.size);
}

class JuzzioBackupService {
  JuzzioBackupService._();
  static final JuzzioBackupService instance = JuzzioBackupService._();

  static const String _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const String _magic = 'JUZZIO-BACKUP';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  final GoogleSignIn _google = GoogleSignIn(scopes: const [_scope]);
  final AesGcm _aes = AesGcm.with256bits();
  // OWASP 2024 önerisi: Argon2id, 19 MiB bellek, 2 tur, 1 iş parçacığı
  final Argon2id _kdf = Argon2id(parallelism: 1, memory: 19456, iterations: 2, hashLength: 32);

  String? get googleEmail => _google.currentUser?.email;

  String _fileName(String uid) => 'juzzio_backup_$uid.jzb';

  /// Drive hesabı seç (her seferinde seçim penceresi açılabilir).
  /// v0.9.3: Google oturum hataları anlamlı koda çevrilir; Drive izni (drive.appdata) verilmemişse
  /// izin yeniden İSTENİR (kullanıcı onay ekranında kutuyu boş bırakırsa Drive 403 döndürüyordu).
  Future<Map<String, String>> _auth({bool chooseAccount = true}) async {
    GoogleSignInAccount? acc;
    try {
      if (chooseAccount) {
        try {
          await _google.signOut();
        } catch (_) {}
        acc = await _google.signIn();
      } else {
        acc = _google.currentUser ?? await _google.signInSilently() ?? await _google.signIn();
      }
    } on PlatformException catch (e) {
      throw JuzzioBackupException(signInErrorCode(e.code, e.message));
    }
    if (acc == null) throw const JuzzioBackupException('cancelled');
    try {
      // İzin verilmemişse yeniden iste (Android'de onay ekranı açılır)
      final granted = await _google.requestScopes(const [_scope]);
      if (!granted) throw const JuzzioBackupException('drive_scope_denied');
    } on PlatformException catch (e) {
      throw JuzzioBackupException(signInErrorCode(e.code, e.message));
    }
    return acc.authHeaders;
  }

  /// Google Sign-In platform hatasından kullanıcıya anlamlı kod (saf, test edilebilir).
  static String signInErrorCode(String code, String? message) {
    final m = (message ?? '').toLowerCase();
    if (code == 'sign_in_canceled' || m.contains('12501')) return 'cancelled';
    // ApiException 10 = DEVELOPER_ERROR: uygulamanın imza (SHA-1) parmak izi Google Cloud'da kayıtlı değil
    if (m.contains('apiexception: 10') || m.contains(' 10:') || m.contains('developer_error')) return 'google_config';
    if (code == 'network_error' || m.contains('7:') || m.contains('network')) return 'network';
    if (m.contains('access_denied') || m.contains('12500')) return 'google_access_denied';
    return 'google_signin_failed';
  }

  /// Drive yanıtındaki hata nedeni (accessNotConfigured, insufficientPermissions...).
  static String driveErrorCode(int status, String body) {
    String reason = '';
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      if (err is Map) {
        final errs = err['errors'];
        if (errs is List && errs.isNotEmpty && errs.first is Map) reason = '${(errs.first as Map)['reason'] ?? ''}';
        if (reason.isEmpty) reason = '${err['status'] ?? ''}';
      }
    } catch (_) {}
    final r = reason.toLowerCase();
    if (r.contains('accessnotconfigured') || r.contains('service_disabled')) return 'drive_api_disabled';
    if (r.contains('insufficientpermissions') || r.contains('insufficient') || r.contains('permission_denied')) {
      return 'drive_scope_denied';
    }
    if (status == 401) return 'drive_auth_expired';
    if (r.contains('storagequotaexceeded')) return 'drive_full';
    if (r.contains('ratelimit') || status == 429) return 'drive_rate_limited';
    return 'drive_$status';
  }

  /// İstek; 401'de jeton yenilenip BİR kez tekrar denenir.
  Future<http.Response> _drive(Future<http.Response> Function(Map<String, String> h) send, Map<String, String> h) async {
    var res = await send(h);
    if (res.statusCode == 401) {
      try {
        final token = h['Authorization']?.replaceFirst('Bearer ', '') ?? '';
        if (token.isNotEmpty) await _google.currentUser?.clearAuthCache();
        final fresh = await _google.currentUser?.authHeaders;
        if (fresh != null) {
          h
            ..clear()
            ..addAll(fresh);
          res = await send(h);
        }
      } catch (_) {}
    }
    return res;
  }

  Future<JuzzioBackupInfo?> _find(Map<String, String> h, String uid) async {
    final q = Uri.encodeQueryComponent("name = '${_fileName(uid)}' and trashed = false");
    final res = await _drive(
      (hh) => http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&q=$q&fields=files(id,modifiedTime,size)'),
        headers: hh,
      ),
      h,
    );
    if (res.statusCode != 200) throw JuzzioBackupException(driveErrorCode(res.statusCode, res.body));
    final files = (jsonDecode(res.body) as Map)['files'];
    if (files is! List || files.isEmpty) return null;
    final f = files.first as Map;
    return JuzzioBackupInfo(
      f['id'].toString(),
      DateTime.tryParse('${f['modifiedTime']}'),
      int.tryParse('${f['size']}') ?? 0,
    );
  }

  Future<String> _encrypt(String uid, String password, Map<String, dynamic> payload) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final header = jsonEncode({
      'magic': _magic,
      'v': 1,
      'uid': uid,
      'kdf': 'argon2id',
      'm': 19456,
      't': 2,
      'p': 1,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'app': JuzzioConfig.appVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
    });
    final key = await _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final box = await _aes.encrypt(utf8.encode(jsonEncode(payload)),
        secretKey: key, nonce: _aes.newNonce(), aad: utf8.encode(header));
    return '$header\n${base64Encode(box.concatenation())}';
  }

  Future<Map<String, dynamic>> _decrypt(String uid, String password, String file) async {
    final nl = file.indexOf('\n');
    if (nl <= 0) throw const JuzzioBackupException('corrupt');
    final header = file.substring(0, nl);
    final h = jsonDecode(header);
    if (h is! Map || h['magic'] != _magic) throw const JuzzioBackupException('corrupt');
    if (h['uid'] != uid) throw const JuzzioBackupException('not_found');
    final kdf = Argon2id(
      parallelism: (h['p'] as num?)?.toInt() ?? 1,
      memory: (h['m'] as num?)?.toInt() ?? 19456,
      iterations: (h['t'] as num?)?.toInt() ?? 2,
      hashLength: 32,
    );
    final key = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: base64Decode('${h['salt']}'));
    try {
      final box = SecretBox.fromConcatenation(base64Decode(file.substring(nl + 1).trim()), nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box, secretKey: key, aad: utf8.encode(header));
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
    } on SecretBoxAuthenticationError {
      throw const JuzzioBackupException('wrong_password');
    }
  }

  /// Yedekle: Google hesabı seçilir, şifreli yedek Drive'a yazılır (varsa güncellenir).
  Future<DateTime> backup(String password) async {
    if (password.length < 8) throw const JuzzioBackupException('weak_password');
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) throw const JuzzioBackupException('no_session');
    await JuzzioE2ee.instance.ensureReady();
    final app = JuzzioAppController.instance;
    final payload = <String, dynamic>{
      'keyring': JuzzioE2ee.instance.exportKeyring(),
      'prefs': app.preferencesSnapshot(),
      'backup_at': DateTime.now().toUtc().toIso8601String(),
    };
    final body = await _encrypt(uid, password, payload);
    final h = await _auth();
    final existing = await _find(h, uid);
    http.Response res;
    if (existing == null) {
      const boundary = 'juzzio-backup-boundary';
      final meta = jsonEncode({'name': _fileName(uid), 'parents': ['appDataFolder']});
      final multipart = '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
          '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n$body\r\n--$boundary--';
      res = await _drive(
        (hh) => http.post(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
          headers: {...hh, 'Content-Type': 'multipart/related; boundary=$boundary'},
          body: utf8.encode(multipart),
        ),
        h,
      );
    } else {
      res = await _drive(
        (hh) => http.patch(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files/${existing.fileId}?uploadType=media'),
          headers: {...hh, 'Content-Type': 'application/octet-stream'},
          body: utf8.encode(body),
        ),
        h,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw JuzzioBackupException(driveErrorCode(res.statusCode, res.body));
    final now = DateTime.now();
    await _secure.write(key: 'juzzio_backup_last_$uid', value: now.toIso8601String());
    return now;
  }

  Future<DateTime?> lastBackupAt() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return null;
    return DateTime.tryParse(await _secure.read(key: 'juzzio_backup_last_$uid') ?? '');
  }

  /// Bu hesap için Drive'da yedek var mı? (hesap seçimi yapılır)
  Future<JuzzioBackupInfo?> findBackup() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) throw const JuzzioBackupException('no_session');
    return _find(await _auth(), uid);
  }

  /// Geri yükle: anahtarlar ve ayarlar içeri aktarılır.
  Future<void> restore(JuzzioBackupInfo info, String password) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) throw const JuzzioBackupException('no_session');
    final h = await _auth(chooseAccount: false);
    final res = await _drive(
      (hh) => http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/files/${info.fileId}?alt=media'),
        headers: hh,
      ),
      h,
    );
    if (res.statusCode != 200) throw JuzzioBackupException(driveErrorCode(res.statusCode, res.body));
    final payload = await _decrypt(uid, password, utf8.decode(res.bodyBytes));
    await JuzzioE2ee.instance.ensureReady();
    final ring = payload['keyring'];
    if (ring is String && ring.isNotEmpty) {
      JuzzioE2ee.instance.importKeyring(ring, adoptCurrent: true);
      await JuzzioE2ee.instance.afterRestore();
    }
    final prefs = payload['prefs'];
    if (prefs is Map) {
      await JuzzioAppController.instance.restorePreferencesSnapshot(Map<String, dynamic>.from(prefs));
    }
    await _secure.write(key: 'juzzio_restore_checked_$uid', value: '1');
  }

  /// Girişten sonra bir kez "yedeği geri yükle" önerisi gösterilsin mi?
  Future<bool> shouldOfferRestore() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return false;
    return (await _secure.read(key: 'juzzio_restore_checked_$uid')) == null;
  }

  Future<void> markRestoreChecked() async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    await _secure.write(key: 'juzzio_restore_checked_$uid', value: '1');
  }

  static String message(Object e) {
    final app = JuzzioAppController.instance;
    final code = e is JuzzioBackupException ? e.code : e.toString();
    switch (code) {
      case 'cancelled':
        return app.trEn('Google hesabı seçilmedi.', 'No Google account selected.', 'Kein Google-Konto gewählt.');
      case 'weak_password':
        return app.trEn('Yedek şifresi en az 8 karakter olmalı.', 'The backup password must be at least 8 characters.',
            'Das Backup-Passwort muss mindestens 8 Zeichen haben.');
      case 'wrong_password':
        return app.trEn('Yedek şifresi yanlış.', 'Wrong backup password.', 'Falsches Backup-Passwort.');
      case 'not_found':
        return app.trEn('Hesabınız için yedekleme bulunamadı.', 'No backup was found for your account.',
            'Für dein Konto wurde kein Backup gefunden.');
      case 'corrupt':
        return app.trEn('Yedek dosyası okunamadı.', 'The backup file could not be read.', 'Backup-Datei unlesbar.');
      // v0.9.3: "erişim reddedildi" türü hatalar ayrıştırıldı
      case 'drive_scope_denied':
        return app.trEn(
            'Google Drive izni verilmedi. Tekrar dene ve izin ekranında "Google Drive uygulama verileri" kutusunu işaretle.',
            'Google Drive permission was not granted. Try again and tick "Google Drive app data" on the consent screen.',
            'Google-Drive-Berechtigung nicht erteilt. Erneut versuchen und „Google Drive App-Daten“ erlauben.');
      case 'drive_api_disabled':
        return app.trEn('Google Drive hizmeti bu uygulama için henüz etkin değil (geliştirici ayarı). Lütfen daha sonra tekrar dene.',
            'Google Drive is not enabled for this app yet (developer setting). Please try again later.',
            'Google Drive ist für diese App noch nicht aktiviert (Entwicklereinstellung).');
      case 'google_config':
        return app.trEn('Google girişi bu uygulama sürümü için yapılandırılmamış (geliştirici ayarı: imza parmak izi).',
            'Google sign-in is not configured for this app build (developer setting: signing fingerprint).',
            'Google-Anmeldung ist für diesen App-Build nicht konfiguriert (Signatur-Fingerabdruck).');
      case 'google_access_denied':
        return app.trEn('Google erişimi reddetti. Uygulama Google tarafında doğrulama/test aşamasındaysa hesabının test kullanıcısı olarak eklenmesi gerekir.',
            'Google denied access. If the app is in Google verification/testing, your account must be added as a test user.',
            'Google hat den Zugriff verweigert. Im Testmodus muss dein Konto als Testnutzer hinzugefügt werden.');
      case 'drive_auth_expired':
        return app.trEn('Google oturumu süresi doldu. Tekrar dene.', 'Your Google session expired. Try again.', 'Google-Sitzung abgelaufen. Erneut versuchen.');
      case 'drive_full':
        return app.trEn('Google Drive depolama alanı dolu.', 'Your Google Drive storage is full.', 'Dein Google-Drive-Speicher ist voll.');
      case 'drive_rate_limited':
        return app.trEn('Google Drive şu an meşgul. Biraz sonra tekrar dene.', 'Google Drive is busy. Try again shortly.', 'Google Drive ist ausgelastet.');
      case 'network':
        return app.trEn('İnternet bağlantısı yok.', 'No internet connection.', 'Keine Internetverbindung.');
      default:
        return app.trEn('Google Drive işlemi başarısız ($code).', 'Google Drive operation failed ($code).',
            'Google-Drive-Vorgang fehlgeschlagen ($code).');
    }
  }
}
