package com.juzzio.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import java.util.Calendar

/**
 * v2.1 (Faz 7.4) — Zamanlanmış sessiz saatler.
 * Aralık içinde gelen bildirimler (aramalar hariç) sessiz kanala düşer:
 * bildirim görünür ama ses/titreşim yapmaz. Ayar Flutter tarafından "setQuietHours" ile yazılır.
 */
object JuzzioQuietHours {
    const val CHANNEL_ID = "juzzio_quiet_v1"
    private const val KEY_ON = "quiet_enabled"
    private const val KEY_START = "quiet_start_min"
    private const val KEY_END = "quiet_end_min"

    /** Gece yarısını aşan aralıkları da destekler (23:00–07:00). */
    fun inRange(minute: Int, start: Int, end: Int): Boolean {
        if (start == end) return false
        return if (start < end) minute in start until end else (minute >= start || minute < end)
    }

    fun save(ctx: Context, on: Boolean, start: Int, end: Int) {
        ctx.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ON, on)
            .putInt(KEY_START, start.coerceIn(0, 1439))
            .putInt(KEY_END, end.coerceIn(0, 1439))
            .apply()
    }

    fun isActive(ctx: Context): Boolean {
        val p = ctx.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        if (!p.getBoolean(KEY_ON, false)) return false
        val c = Calendar.getInstance()
        val minute = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        return inRange(minute, p.getInt(KEY_START, 23 * 60), p.getInt(KEY_END, 7 * 60))
    }

    fun channel(ctx: Context): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(CHANNEL_ID, "Sessiz saatler", NotificationManager.IMPORTANCE_LOW).apply {
                            description = "Zamanlanmış sessiz saatlerde gelen bildirimler (ses ve titreşim yok)"
                            enableVibration(false)
                            vibrationPattern = longArrayOf(0L)
                            setSound(null, null)
                        }
                    )
                }
            } catch (_: Exception) {}
        }
        return CHANNEL_ID
    }
}
