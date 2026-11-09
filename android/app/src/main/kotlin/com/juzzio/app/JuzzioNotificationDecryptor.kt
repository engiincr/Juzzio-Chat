package com.juzzio.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * v0.9.0 (ek paket N-D) — Mesaj bildiriminin içeriğini CİHAZDA çözer.
 *
 * Sunucu FCM yüküne mesaj metni koymaz. Önizleme kipi 'full' ise bu sınıf, mesajı kullanıcının
 * kendi oturumuyla okuyan ve E2EE anahtarlarıyla cihazda çözen Dart kodunu çalıştırır:
 *  • Uygulama süreci canlıysa mevcut motor ("resolveNotificationPreview"),
 *  • değilse ekransız motor (juzzioNotificationPreviewMain).
 * Süre sınırı aşılırsa veya çözülemezse null döner → bildirim genel metinle gösterilir.
 * Çözülen metin saklanmaz/loglanmaz.
 *
 * ÖNEMLİ: Ana iş parçacığında ÇAĞRILMAMALI (FirebaseMessagingService.onMessageReceived arka
 * plan iş parçacığında çalışır; burada beklenir, motor işleri ana iş parçacığına gönderilir).
 */
object JuzzioNotificationDecryptor {
    // v0.9.3: çözme + uygulama diline çeviri için 9 sn (FCM işleyici sınırının altında)
    private const val TIMEOUT_MS = 9_000L
    private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    fun resolve(ctx: Context, roomId: String, messageId: String): String? {
        if (Looper.myLooper() == Looper.getMainLooper()) return null
        if (!UUID_RE.matches(roomId) || !UUID_RE.matches(messageId)) return null
        val args = mapOf("room_id" to roomId, "message_id" to messageId)
        val out = AtomicReference<String?>(null)
        val latch = CountDownLatch(1)
        val main = Handler(Looper.getMainLooper())
        var engineRef: FlutterEngine? = null

        fun done(v: Any?) {
            val text = (v as? Map<*, *>)?.get("text") as? String
            out.set(text?.takeIf { it.isNotBlank() })
            latch.countDown()
        }

        val live = MainActivity.activeMethodChannel
        main.post {
            if (live != null) {
                try {
                    live.invokeMethod("resolveNotificationPreview", args, object : MethodChannel.Result {
                        override fun success(result: Any?) = done(result)
                        override fun error(code: String, msg: String?, details: Any?) = done(null)
                        override fun notImplemented() = done(null)
                    })
                } catch (_: Exception) {
                    done(null)
                }
            } else {
                try {
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(ctx)
                    loader.ensureInitializationComplete(ctx, null)
                    val engine = FlutterEngine(ctx)
                    engineRef = engine
                    var delivered = false
                    val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "juzzio/notif_preview")
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
                                done(call.arguments)
                            }
                            else -> result.notImplemented()
                        }
                    }
                    engine.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "juzzioNotificationPreviewMain")
                    )
                } catch (_: Exception) {
                    done(null)
                }
            }
        }
        try {
            latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {}
        main.postDelayed({
            try { engineRef?.destroy() } catch (_: Exception) {}
        }, 300)
        return out.get()
    }
}
