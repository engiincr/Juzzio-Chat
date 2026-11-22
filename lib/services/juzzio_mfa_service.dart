// Juzzio 2.1 — İki adımlı doğrulama (TOTP, Supabase Auth MFA)
//
// * Kurulum: kimlik doğrulayıcı uygulamaya (Google Authenticator, Microsoft
//   Authenticator, 1Password…) karekod okutulur, 6 haneli kodla doğrulanır.
// * Giriş: şifre doğruysa ve hesapta doğrulanmış TOTP varsa oturum AAL1'de kalır;
//   kod girilip AAL2'ye yükselmeden uygulamaya girilmez (girişte ve açılışta).
// * Gizli anahtar yalnız kurulum ekranında, cihazda gösterilir; hiçbir yere
//   yazılmaz/loglanmaz. Kurtarma: destek + kimlik doğrulama (yönetici panelinde
//   MFA sıfırlama yalnız hesap sahibinin talebiyle).
//
// Not: gotrue sürümleri arasında bazı alanların null olabilirliği değiştiği için
// yanıtlar `dynamic` üzerinden okunur (derleme her iki sürümde de geçer).

import 'package:supabase_flutter/supabase_flutter.dart';

class JuzzioMfaEnrollment {
  const JuzzioMfaEnrollment({required this.factorId, required this.uri, required this.secret});
  final String factorId;
  final String uri;
  final String secret;
}

class JuzzioMfaFactor {
  const JuzzioMfaFactor({required this.id, required this.name, required this.verified});
  final String id;
  final String name;
  final bool verified;
}

/// "FactorStatus.verified" / "verified" → true; "unverified" → false (saf; test edilir)
bool juzzioMfaStatusVerified(Object? status) {
  final s = (status ?? '').toString().split('.').last.trim().toLowerCase();
  return s == 'verified';
}

/// "AuthenticatorAssuranceLevels.aal2" / "aal2" → "aal2" (saf; test edilir)
String juzzioAalName(Object? level) => (level ?? '').toString().split('.').last.trim().toLowerCase();

/// Kullanıcının girdiği kodu temizler: yalnız 6 rakam kabul edilir (saf; test edilir)
String? juzzioCleanTotpCode(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 6 ? digits : null;
}

class JuzzioMfaService {
  JuzzioMfaService._();
  static final JuzzioMfaService instance = JuzzioMfaService._();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Oturum AAL1'de ve hesapta doğrulanmış ikinci adım varsa true
  Future<bool> needsChallenge() async {
    try {
      final dynamic aal = await Future<dynamic>.value(_auth.mfa.getAuthenticatorAssuranceLevel());
      return juzzioAalName(aal.currentLevel) == 'aal1' && juzzioAalName(aal.nextLevel) == 'aal2';
    } catch (_) {
      return false;
    }
  }

  Future<List<JuzzioMfaFactor>> totpFactors() async {
    final dynamic res = await _auth.mfa.listFactors();
    final out = <JuzzioMfaFactor>[];
    for (final dynamic f in (res.totp as List? ?? const [])) {
      out.add(JuzzioMfaFactor(
        id: (f.id ?? '').toString(),
        name: (f.friendlyName ?? 'Authenticator').toString(),
        verified: juzzioMfaStatusVerified(f.status),
      ));
    }
    return out;
  }

  Future<bool> isEnabled() async {
    try {
      return (await totpFactors()).any((f) => f.verified);
    } catch (_) {
      return false;
    }
  }

  /// Yarım kalmış (doğrulanmamış) kurulumları temizleyip yeni TOTP kaydı başlatır
  Future<JuzzioMfaEnrollment> enroll() async {
    try {
      for (final f in await totpFactors()) {
        if (!f.verified) await _auth.mfa.unenroll(f.id);
      }
    } catch (_) {}
    final dynamic res = await _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Trawave',
      friendlyName: 'Trawave ${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    );
    final dynamic totp = res.totp;
    return JuzzioMfaEnrollment(
      factorId: (res.id ?? '').toString(),
      uri: (totp?.uri ?? '').toString(),
      secret: (totp?.secret ?? '').toString(),
    );
  }

  Future<void> verify(String factorId, String code) async {
    await _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  /// Girişte/açılışta istenen kodu ilk doğrulanmış faktörle doğrular
  Future<void> verifyLogin(String code) async {
    final factors = (await totpFactors()).where((f) => f.verified).toList();
    if (factors.isEmpty) throw AuthException('mfa_no_factor');
    await verify(factors.first.id, code);
  }

  Future<void> disable() async {
    for (final f in await totpFactors()) {
      await _auth.mfa.unenroll(f.id);
    }
  }
}
