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
import java.util.Locale
import java.util.UUID

/**
 * v0.8.3 — Bildirimden hızlı yanıt.
 * Uygulama arka planda çalışıyorsa yanıt mevcut Flutter motoruna ("onQuickReply"),
 * tamamen kapalıysa ekransız bir Flutter motoruna (juzzioQuickReplyMain) iletilir.
 * Gönderim Dart'taki normal mesaj yolundan yapılır: uçtan uca şifreleme korunur,
 * metin Kotlin tarafında saklanmaz/loglanmaz.
 *
 * v0.9.0 (N-E): her yanıta TEK bir client_msg_id üretilir ve çalışan motordan ekransız motora
 * düşüşte de aynı kimlik gönderilir → sunucudaki benzersiz indeks çift mesajı engeller.
 * Dart sonucu {ok, status} döner; şifreleme yapılamazsa mesaj gönderilmez (fail-closed) ve
 * kullanıcıya ayrı bir durum metni gösterilir. Zaman aşımı "gönderilemedi" değil "doğrulanamadı"
 * olarak bildirilir (mesaj sunucuya ulaşmış olabilir). Kilit ekranında yanıt metni gizlenir.
 */
class JuzzioReplyReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_REPLY = "com.juzzio.app.QUICK_REPLY"
        const val ACTION_MARK_READ = "com.juzzio.app.MARK_READ"
        const val KEY_TEXT = "juzzio_reply_text"
        const val EXTRA_ROOM = "juzzio_reply_room"
        const val EXTRA_NOTIF_ID = "juzzio_reply_notif_id"
        const val EXTRA_TITLE = "juzzio_reply_title"
        const val EXTRA_CHANNEL = "juzzio_reply_channel"
        private const val TIMEOUT_MS = 25_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MARK_READ) {
            markRead(context, intent)
            return
        }
        if (intent.action != ACTION_REPLY) return
        val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_TEXT)?.toString()?.trim().orEmpty()
        val roomId = intent.getStringExtra(EXTRA_ROOM).orEmpty()
        val notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Juzzio"
        val channelId = intent.getStringExtra(EXTRA_CHANNEL) ?: MainActivity.NOTIF_CHANNEL_ID
        if (text.isEmpty() || roomId.isEmpty()) return
        val clientMsgId = "qr_" + UUID.randomUUID().toString().replace("-", "")
        val args = mapOf("room_id" to roomId, "text" to text, "client_msg_id" to clientMsgId)

        val pending = goAsync()
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        var finished = false
        fun finish(status: String) {
            if (finished) return
            finished = true
            updateNotification(app, notifId, title, channelId, text, status)
            try { pending.finish() } catch (_: Exception) {}
        }
        main.postDelayed({ finish("timeout") }, TIMEOUT_MS)

        // 1) Uygulama süreci ve motoru hâlâ çalışıyorsa onu kullan
        val live = MainActivity.activeMethodChannel
        if (live != null) {
            main.post {
                try {
                    live.invokeMethod("onQuickReply", args, object : MethodChannel.Result {
                        override fun success(result: Any?) { finish(statusOf(result)) }
                        override fun error(code: String, msg: String?, details: Any?) { finish("failed") }
                        override fun notImplemented() { startHeadless(app, args, ::finish) }
                    })
                } catch (_: Exception) {
                    startHeadless(app, args, ::finish)
                }
            }
            return
        }
        // 2) Uygulama kapalı: ekransız motor
        main.post { startHeadless(app, args, ::finish) }
    }

    /** v1.2.4: "Okundu olarak işaretle" — bildirim hemen kalkar, sunucuda sohbet okundu yapılır. */
    private fun markRead(context: Context, intent: Intent) {
        val roomId = intent.getStringExtra(EXTRA_ROOM).orEmpty()
        val notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0)
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId)
        } catch (_: Exception) {}
        if (roomId.isEmpty()) return
        val args = mapOf("op" to "mark_read", "room_id" to roomId)
        val pending = goAsync()
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        var finished = false
        fun finish(@Suppress("UNUSED_PARAMETER") status: String) {
            if (finished) return
            finished = true
            try { pending.finish() } catch (_: Exception) {}
        }
        main.postDelayed({ finish("timeout") }, TIMEOUT_MS)
        val live = MainActivity.activeMethodChannel
        main.post {
            if (live != null) {
                try {
                    live.invokeMethod("onQuickReply", args, object : MethodChannel.Result {
                        override fun success(result: Any?) { finish("ok") }
                        override fun error(code: String, msg: String?, details: Any?) { finish("failed") }
                        override fun notImplemented() { startHeadless(app, args, ::finish) }
                    })
                } catch (_: Exception) {
                    startHeadless(app, args, ::finish)
                }
            } else {
                startHeadless(app, args, ::finish)
            }
        }
    }

    /** Dart sonucu: eski sürüm Boolean, v0.9.0 {ok, status}. */
    private fun statusOf(result: Any?): String = when (result) {
        true -> "ok"
        is Map<*, *> -> {
            val st = result["status"]?.toString().orEmpty()
            if (result["ok"] == true) "ok" else if (st.isNotEmpty()) st else "failed"
        }
        else -> "failed"
    }

    private fun startHeadless(ctx: Context, args: Map<String, String>, done: (String) -> Unit) {
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
                            result.success(args)
                        }
                    }
                    "result" -> {
                        result.success(null)
                        done(statusOf(call.arguments))
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
            done("failed")
        }
    }

    private fun statusText(status: String): String {
        val tr = Locale.getDefault().language == "tr"
        return when (status) {
            "ok" -> if (tr) "✓ Gönderildi" else "✓ Sent"
            "e2eeUnavailable" ->
                if (tr) "🔒 Şifreleme hazır değil — mesaj gönderilmedi. Uygulamayı açıp tekrar deneyin."
                else "🔒 Encryption unavailable — not sent. Open the app and try again."
            "signedOut" -> if (tr) "⚠ Oturum kapalı — uygulamayı açın" else "⚠ Signed out — open the app"
            "invalid" -> if (tr) "⚠ Geçersiz yanıt — gönderilmedi" else "⚠ Invalid reply — not sent"
            "timeout" ->
                if (tr) "⏳ Gönderim doğrulanamadı — tekrar göndermeden önce sohbeti kontrol edin"
                else "⏳ Couldn't confirm delivery — check the chat before resending"
            else -> if (tr) "⚠ Gönderilemedi — uygulamayı açıp tekrar deneyin" else "⚠ Not sent — open the app and try again"
        }
    }

    private fun updateNotification(ctx: Context, id: Int, title: String, channelId: String, text: String, statusCode: String) {
        try {
            val ok = statusCode == "ok"
            val icon = if (ctx.applicationInfo.icon != 0) ctx.applicationInfo.icon else R.mipmap.ic_launcher
            val status = statusText(statusCode)
            // Kilit ekranında yanıt metni görünmez; yalnızca durum
            val publicVersion = NotificationCompat.Builder(ctx, channelId)
                .setSmallIcon(icon)
                .setContentTitle("Juzzio")
                .setContentText(status)
                .build()
            // v1.2.4: sohbet tarzı bildirim varsa yanıt aynı konuşmanın altına eklenir
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val previous = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                try { nm.activeNotifications.firstOrNull { it.id == id }?.notification } catch (_: Exception) { null }
            } else null
            val conv = if (ok && previous != null) {
                try { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(previous) } catch (_: Exception) { null }
            } else null
            conv?.addMessage(NotificationCompat.MessagingStyle.Message(text, System.currentTimeMillis(), null as androidx.core.app.Person?))
            val b = NotificationCompat.Builder(ctx, channelId)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText("Sen: $text")
                .setStyle(conv ?: NotificationCompat.BigTextStyle().bigText("Sen: $text\n$status"))
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setAutoCancel(true)
            if (ok) b.setTimeoutAfter(4_000L)
            val n = b.build()
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, n)
        } catch (_: Exception) {}
    }
}
