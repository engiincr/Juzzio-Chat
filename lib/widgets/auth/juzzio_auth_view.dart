// =============================================================================
// JUZZIO GM-002 — Giriş / Kayıt ekranı görünümü (yalnız arayüz, K3)
//  İş mantığı (Supabase Auth, şifre sıfırlama, onaylar, OAuth, MFA, yönlendirme) main.dart'taki
//  _JuzzioRootFlowState'te kalır; bu widget yalnızca değerleri ve geri çağırmaları alır.
//  Giriş ve kayıt AYNI bileşenlerden üretilir (K1).
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/theme/juzzio_design_tokens.dart';
import 'juzzio_auth_kit.dart';

/// tr / en / de metin seçici (JuzzioAppController.trEn ile aynı imza)
typedef JuzzioTr = String Function(String tr, String en, String de);

class JuzzioAuthView extends StatelessWidget {
  const JuzzioAuthView({
    super.key,
    required this.registerMode,
    required this.t,
    required this.identifierController,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.rememberMe,
    required this.onRememberChanged,
    required this.loading,
    required this.errorText,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onToggleMode,
    required this.socialEnabled,
    required this.onSocial,
    required this.onSocialUnavailable,
    this.onBack,
    this.reduceMotion = false,
  });

  final bool registerMode;
  final JuzzioTr t;

  /// Girişte "e-posta veya kullanıcı adı", kayıtta "kullanıcı adı"
  final TextEditingController identifierController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;
  final bool loading;
  final String? errorText;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onToggleMode;

  /// provider → bu platformda gerçekten çalışıyor mu (K6)
  final Map<String, bool> socialEnabled;
  final ValueChanged<String> onSocial;
  final ValueChanged<String> onSocialUnavailable;

  /// null → geri düğmesi gösterilmez (sahte düğme yok)
  final VoidCallback? onBack;
  final bool reduceMotion;

  static const providers = ['google', 'apple', 'github'];
  static String providerName(String p) => switch (p) {
        'google' => 'Google',
        'apple' => 'Apple',
        _ => 'GitHub',
      };

  @override
  Widget build(BuildContext context) {
    final reg = registerMode;
    final hasError = errorText != null;

    final eye = JuzzioPasswordEye(
      obscured: obscurePassword,
      onToggle: onToggleObscure,
      showLabel: t('Şifreyi göster', 'Show password', 'Passwort anzeigen'),
      hideLabel: t('Şifreyi gizle', 'Hide password', 'Passwort verbergen'),
    );

    final fields = <Widget>[
      if (reg) ...[
        JuzzioAuthTextField(
          key: const ValueKey('auth_username'),
          controller: identifierController,
          hint: t('Kullanıcı adı', 'Username', 'Benutzername'),
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          hasError: hasError,
          enabled: !loading,
        ),
        const SizedBox(height: 10),
        JuzzioAuthTextField(
          key: const ValueKey('auth_email'),
          controller: emailController,
          hint: t('E-posta adresi', 'Email address', 'E-Mail-Adresse'),
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          hasError: hasError,
          enabled: !loading,
        ),
      ] else
        JuzzioAuthTextField(
          key: const ValueKey('auth_identifier'),
          controller: identifierController,
          hint: t(
            'E-posta adresi veya kullanıcı adı',
            'Email or username',
            'E-Mail oder Benutzername',
          ),
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          hasError: hasError,
          enabled: !loading,
        ),
      const SizedBox(height: 10),
      JuzzioAuthTextField(
        key: const ValueKey('auth_password'),
        controller: passwordController,
        hint: t('Şifre', 'Password', 'Passwort'),
        icon: Icons.lock_outline_rounded,
        obscure: obscurePassword,
        suffix: eye,
        textInputAction: TextInputAction.done,
        autofillHints: [
          reg ? AutofillHints.newPassword : AutofillHints.password,
        ],
        onSubmitted: (_) {
          if (!loading) onSubmit();
        },
        hasError: hasError,
        enabled: !loading,
      ),
    ];

    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: JuzzioAuthChip(
            label: reg
                ? t('Hesap Oluştur', 'Create Account', 'Konto erstellen')
                : t('Giriş Yap', 'Sign In', 'Anmelden'),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: reg
              ? JuzzioAuthTitle(
                  prefix: t('Juzzio’ya ', 'Join ', 'Willkommen bei '),
                  mark: t('Katıl', 'Juzzio', 'Juzzio'),
                )
              : JuzzioAuthTitle(
                  prefix: t('Tekrar Hoş ', 'Welcome ', 'Willkommen '),
                  mark: t('Geldin!', 'back!', 'zurück!'),
                  trailingEmoji: JuzzioAuthAssets.emojiWave,
                ),
        ),
        const SizedBox(height: 4),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 315),
            child: Text(
              reg
                  ? t(
                      'Arkadaşlarınla bağlan, dünyanın her yerinden insanlarla sohbet et.',
                      'Connect with friends and chat with people all over the world.',
                      'Verbinde dich mit Freunden und chatte weltweit.',
                    )
                  : t(
                      'Juzzio hesabına giriş yap, arkadaşlarınla kaldığın yerden devam et.',
                      'Sign in to Juzzio and pick up where you left off with your friends.',
                      'Melde dich bei Juzzio an und mach weiter, wo du aufgehört hast.',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: JuzzioType.family,
                color: JuzzioColorTokens.textSubtle,
                fontSize: JuzzioType.subtitle,
                height: 1.42,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: fields,
          ),
        ),
        if (!reg) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: JuzzioAuthCheckbox(
                    value: rememberMe,
                    onChanged: onRememberChanged,
                    label: t(
                      'Beni hatırla',
                      'Remember me',
                      'Angemeldet bleiben',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: JuzzioTextLink(
                      label: t(
                        'Şifremi unuttum?',
                        'Forgot password?',
                        'Passwort vergessen?',
                      ),
                      onTap: loading ? null : onForgotPassword,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        AnimatedSize(
          duration: JuzzioMotion.modal,
          curve: Curves.easeOutCubic,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      errorText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: JuzzioType.family,
                        color: JuzzioColorTokens.errorOnDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        SizedBox(height: reg ? 18 : 10),
        JuzzioPrimaryButton(
          key: const ValueKey('auth_submit'),
          label: reg
              ? t('Kayıt Ol', 'Sign Up', 'Registrieren')
              : t('Giriş Yap', 'Sign In', 'Anmelden'),
          loading: loading,
          onPressed: onSubmit,
        ),
        const SizedBox(height: 18),
        JuzzioOrDivider(label: t('veya', 'or', 'oder')),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in providers) ...[
              if (p != providers.first) const SizedBox(width: 18),
              JuzzioSocialButton(
                key: ValueKey('auth_social_$p'),
                provider: p,
                enabled: socialEnabled[p] == true,
                semanticLabel: socialEnabled[p] == true
                    ? t(
                        '${providerName(p)} ile giriş yap',
                        'Sign in with ${providerName(p)}',
                        'Mit ${providerName(p)} anmelden',
                      )
                    : t(
                        '${providerName(p)} ile giriş, kullanılamıyor',
                        'Sign in with ${providerName(p)}, unavailable',
                        'Mit ${providerName(p)} anmelden, nicht verfügbar',
                      ),
                onTap: loading
                    ? null
                    : () => socialEnabled[p] == true
                        ? onSocial(p)
                        : onSocialUnavailable(p),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        JuzzioAuthFooter(
          question: reg
              ? t(
                  'Zaten hesabın var mı?',
                  'Already have an account?',
                  'Schon ein Konto?',
                )
              : t(
                  'Hesabın yok mu?',
                  "Don't have an account?",
                  'Noch kein Konto?',
                ),
          action: reg
              ? t('Giriş Yap', 'Sign In', 'Anmelden')
              : t('Hesap Oluştur', 'Create Account', 'Konto erstellen'),
          onTap: onToggleMode,
        ),
      ],
    );

    return JuzzioAuthLayout(
      onBack: onBack,
      backLabel: t('Geri', 'Back', 'Zurück'),
      reduceMotion: reduceMotion,
      panel: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: panel,
      ),
    );
  }
}
