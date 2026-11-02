package com.juzzio.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * v0.9.0 (ek paket N-F) — Gelen arama bildirimindeki "Reddet".
 * Uygulamayı açmadan sunucudaki `juzzio_decline_call` RPC'si çağrılır (yalnız aranan kişi,
 * yalnız çalan arama — sunucuda doğrulanır). Uygulama süreci canlıysa mevcut motor
 * ("onCallAction"), değilse ekransız motor (juzzioCallActionMain) kullanılır.
 * Bildirim, sonuç ne olursa olsun hemen kapatılır ve zil susar (kullanıcı reddetti);
 * sunucu çağrısı başarısızsa arama arayan tarafta zaman aşımıyla "cevapsız" olur.
 */
class JuzzioCallActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DECLINE = "com.juzzio.app.CALL_DECLINE"
        const val EXTRA_CALL_ID = "juzzio_call_id"
        const val EXTRA_NOTIF_ID = "juzzio_call_notif_id"
        private const val TIMEOUT_MS = 15_000L
        private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DECLINE) return
        val callId = intent.getStringExtra(EXTRA_CALL_ID).orEmpty()
        val notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0)
        val app = context.applicationContext
        try {
            (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId)
        } catch (_: Exception) {}
        if (!UUID_RE.matches(callId)) return

        val pending = goAsync()
        val main = Handler(Looper.getMainLooper())
        var finished = false
        fun finish() {
            if (finished) return
            finished = true
            try { pending.finish() } catch (_: Exception) {}
        }
        main.postDelayed({ finish() }, TIMEOUT_MS)
        val args = mapOf("call_id" to callId, "action" to "decline")

        val live = MainActivity.activeMethodChannel
        main.post {
            if (live != null) {
                try {
                    live.invokeMethod("onCallAction", args, object : MethodChannel.Result {
                        override fun success(result: Any?) = finish()
                        override fun error(code: String, msg: String?, details: Any?) = finish()
                        override fun notImplemented() = startHeadless(app, args) { finish() }
                    })
                } catch (_: Exception) {
                    startHeadless(app, args) { finish() }
                }
            } else {
                startHeadless(app, args) { finish() }
            }
        }
    }

    private fun startHeadless(ctx: Context, args: Map<String, String>, done: () -> Unit) {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(ctx)
            loader.ensureInitializationComplete(ctx, null)
            val engine = FlutterEngine(ctx)
            var delivered = false
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "juzzio/call_action")
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        if (delivered) result.success(null) else {
                            delivered = true
                            result.success(args)
                        }
                    }
                    "result" -> {
                        result.success(null)
                        done()
                        Handler(Looper.getMainLooper()).postDelayed({
                            try { engine.destroy() } catch (_: Exception) {}
                        }, 300)
                    }
                    else -> result.notImplemented()
                }
            }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "juzzioCallActionMain")
            )
        } catch (_: Exception) {
            done()
        }
    }
}
