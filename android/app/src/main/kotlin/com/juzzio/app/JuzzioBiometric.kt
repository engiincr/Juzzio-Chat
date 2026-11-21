package com.juzzio.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

/**
 * v2.1 (Faz 10.1) — Yönetici paneli için biyometrik / ekran kilidi doğrulaması.
 * Çerçeve (framework) BiometricPrompt kullanılır → FragmentActivity gerekmez.
 * Sonuç: "ok" | "cancel" | "unavailable" (Android 10 öncesi ya da cihazda ekran kilidi yok).
 * Parmak izi/yüz verisi uygulamaya hiç gelmez; yalnız sistemin "doğrulandı" cevabı alınır.
 */
object JuzzioBiometric {
    fun prompt(activity: Activity, title: String, subtitle: String, done: (String) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) { done("unavailable"); return }
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km == null || !km.isDeviceSecure) { done("unavailable"); return }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bm = activity.getSystemService(BiometricManager::class.java)
            val can = bm?.canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
            ) ?: BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE
            if (can != BiometricManager.BIOMETRIC_SUCCESS) { done("unavailable"); return }
        }
        var finished = false
        fun finish(r: String) { if (!finished) { finished = true; done(r) } }
        try {
            val builder = BiometricPrompt.Builder(activity).setTitle(title).setSubtitle(subtitle)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
            } else {
                @Suppress("DEPRECATION")
                builder.setDeviceCredentialAllowed(true)
            }
            builder.build().authenticate(
                CancellationSignal(),
                activity.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) = finish("ok")
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) = finish("cancel")
                }
            )
        } catch (_: Exception) {
            finish("unavailable")
        }
    }
}
