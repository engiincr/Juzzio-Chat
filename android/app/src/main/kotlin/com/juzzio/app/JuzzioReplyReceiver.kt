package com.juzzio.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * v0.8.3 — Bildirimden hızlı yanıt.
 * Uygulama arka planda çalışıyorsa yanıt mevcut Flutter motoruna ("onQuickReply"),
 * tamamen kapalıysa ekransız bir Flutter motoruna (juzzioQuickReplyMain) iletilir.
 * Gönderim Dart'taki normal mesaj yolundan yapılır: uçtan uca şifreleme korunur,
 * metin Kotlin tarafında saklanmaz/loglanmaz.
 */
class JuzzioReplyReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_REPLY = "com.juzzio.app.QUICK_REPLY"
        const val KEY_TEXT = "juzzio_reply_text"
        const val EXTRA_ROOM = "juzzio_reply_room"
        const val EXTRA_NOTIF_ID = "juzzio_reply_notif_id"
        const val EXTRA_TITLE = "juzzio_reply_title"
        const val EXTRA_CHANNEL = "juzzio_reply_channel"
        private const val TIMEOUT_MS = 25_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_REPLY) return
        val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_TEXT)?.toString()?.trim().orEmpty()
        val roomId = intent.getStringExtra(EXTRA_ROOM).orEmpty()
        val notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Juzzio"
        val channelId = intent.getStringExtra(EXTRA_CHANNEL) ?: MainActivity.NOTIF_CHANNEL_ID
        if (text.isEmpty() || roomId.isEmpty()) return

        val pending = goAsync()
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        var finished = false
        fun finish(ok: Boolean) {
            if (finished) return
            finished = true
            updateNotification(app, notifId, title, channelId, text, ok)
            try { pending.finish() } catch (_: Exception) {}
        }
        main.postDelayed({ finish(false) }, TIMEOUT_MS)

        // 1) Uygulama süreci ve motoru hâlâ çalışıyorsa onu kullan
        val live = MainActivity.activeMethodChannel
        if (live != null) {
            main.post {
                try {
                    live.invokeMethod("onQuickReply", mapOf("room_id" to roomId, "text" to text), object : MethodChannel.Result {
                        override fun success(result: Any?) { finish(result == true) }
                        override fun error(code: String, msg: String?, details: Any?) { finish(false) }
                        override fun notImplemented() { startHeadless(app, roomId, text, ::finish) }
                    })
                } catch (_: Exception) {
                    startHeadless(app, roomId, text, ::finish)
                }
            }
            return
        }
        // 2) Uygulama kapalı: ekransız motor
        main.post { startHeadless(app, roomId, text, ::finish) }
    }

    private fun startHeadless(ctx: Context, roomId: String, text: String, done: (Boolean) -> Unit) {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(ctx)
            loader.ensureInitializationComplete(ctx, null)
            val engine = FlutterEngine(ctx)
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "juzzio/quick_reply")
            var delivered = false
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        if (delivered) {
                            result.success(null)
                        } else {
                            delivered = true
                            result.success(mapOf("room_id" to roomId, "text" to text))
                        }
                    }
                    "result" -> {
                        result.success(null)
                        done((call.argument<Boolean>("ok")) == true)
                        Handler(Looper.getMainLooper()).postDelayed({
                            try { engine.destroy() } catch (_: Exception) {}
                        }, 300)
                    }
                    else -> result.notImplemented()
                }
            }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "juzzioQuickReplyMain")
            )
        } catch (_: Exception) {
            done(false)
        }
    }

    private fun updateNotification(ctx: Context, id: Int, title: String, channelId: String, text: String, ok: Boolean) {
        try {
            val icon = if (ctx.applicationInfo.icon != 0) ctx.applicationInfo.icon else R.mipmap.ic_launcher
            val status = if (ok) "✓ Gönderildi" else "⚠ Gönderilemedi — uygulamayı açıp tekrar deneyin"
            val b = NotificationCompat.Builder(ctx, channelId)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText("Sen: $text")
                .setStyle(NotificationCompat.BigTextStyle().bigText("Sen: $text\n$status"))
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setAutoCancel(true)
            if (ok) b.setTimeoutAfter(4_000L)
            val n = b.build()
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, n)
        } catch (_: Exception) {}
    }
}
