package com.juzzio.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * v0.9.3 — Süren arama için ön plan servisi (WhatsApp benzeri).
 *  Uygulama arka plana atıldığında Android, ön plan servisi olmayan uygulamanın mikrofon/kamera
 *  erişimini keser ve işlemi sonlandırabilir → arama kopuyordu. Bu servis arama süresince
 *  "Arama sürüyor" kalıcı bildirimini gösterir; mikrofon (görüntülüde kamera) erişimi korunur.
 *  Bildirime dokununca aramaya dönülür; "Kapat" aramayı uygulamadan sonlandırır.
 */
class JuzzioCallService : Service() {
    companion object {
        const val CHANNEL_ID = "juzzio_ongoing_call_v1"
        const val NOTIF_ID = 47_001
        const val EXTRA_TITLE = "title"
        const val EXTRA_VIDEO = "video"
        const val ACTION_HANGUP = "com.juzzio.app.CALL_HANGUP"

        fun start(ctx: Context, title: String, video: Boolean) {
            val i = Intent(ctx, JuzzioCallService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_VIDEO, video)
            try {
                ContextCompat.startForegroundService(ctx, i)
            } catch (_: Exception) {}
        }

        fun stop(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, JuzzioCallService::class.java))
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANGUP) {
            // Flutter tarafına "kapat" iletilir; servis arama gerçekten bitince durdurulur
            Handler(Looper.getMainLooper()).post {
                try {
                    MainActivity.activeMethodChannel?.invokeMethod("onCallHangupFromNotification", null)
                } catch (_: Exception) {}
            }
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Juzzio"
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) ?: false
        ensureChannel()
        val notification = buildNotification(title, video)
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            // Kamera türü yalnız izin verilmişse eklenir (aksi hâlde Android 14 servisi reddeder)
            if (video && ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
        }
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, notification, type)
        } catch (_: Exception) {
            // Mikrofon izni yoksa vb. — bildirimsiz devam etmek yerine servisi kapat
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(CHANNEL_ID, "Süren arama", NotificationManager.IMPORTANCE_LOW)
        ch.setShowBadge(false)
        ch.setSound(null, null)
        nm.createNotificationChannel(ch)
    }

    private fun label(tr: String, en: String, de: String): String {
        val lang = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
            .getString(MainActivity.PREF_UI_LANG, null) ?: java.util.Locale.getDefault().language
        return when (lang.substringBefore('-')) {
            "tr" -> tr
            "de" -> de
            else -> en
        }
    }

    private fun buildNotification(title: String, video: Boolean): Notification {
        val flagsImm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_UPDATE_CURRENT
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("juzzio_action", "return_to_call")
        }
        val openPi = PendingIntent.getActivity(this, NOTIF_ID, open, flagsImm)
        val hang = Intent(this, JuzzioCallService::class.java).setAction(ACTION_HANGUP)
        val hangPi = PendingIntent.getService(this, NOTIF_ID + 1, hang, flagsImm)
        val icon = if (applicationInfo.icon != 0) applicationInfo.icon else R.mipmap.ic_launcher
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(
                if (video) label("Görüntülü arama sürüyor · dönmek için dokun", "Video call in progress · tap to return", "Videoanruf läuft · zum Zurückkehren tippen")
                else label("Sesli arama sürüyor · dönmek için dokun", "Voice call in progress · tap to return", "Sprachanruf läuft · zum Zurückkehren tippen")
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis())
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, label("Kapat", "Hang up", "Auflegen"), hangPi)
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Uygulama son kullanılanlardan kaydırılırsa arama da biter (yetim servis kalmaz)
        Handler(Looper.getMainLooper()).post {
            try {
                MainActivity.activeMethodChannel?.invokeMethod("onCallHangupFromNotification", null)
            } catch (_: Exception) {}
        }
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
}
