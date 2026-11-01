package com.juzzio.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Gerçek Firebase Cloud Messaging (FCM) Servisi (Bölüm 9 & 15.2)
 * - onNewToken: Yeni veya yenilenen FCM registration token'ı kaydeder ve Flutter'a iletir.
 * - onMessageReceived: Gelen FCM mesajlarını ön plan / arka plan durumuna göre işler;
 *   çift bildirim üretmeden doğru Android kanalında gösterir.
 */
class JuzzioFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        if (token.isBlank()) return
        try {
            val prefs = getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString("fcm_push_token", token).apply()
            MainActivity.notifyTokenRefreshToFlutter(token)
        } catch (_: Exception) {}
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        try {
            val data = remoteMessage.data
            val notif = remoteMessage.notification

            val eventType = data["event_type"] ?: data["type"] ?: "message"
            val notificationId = data["notification_id"] ?: remoteMessage.messageId ?: ""
            val targetId = data["target_id"] ?: ""
            val targetSecondaryId = data["target_secondary_id"] ?: ""
            val actorId = data["actor_id"] ?: ""
            val channelId = data["channel_id"] ?: MainActivity.NOTIF_CHANNEL_ID
            val title = data["title"] ?: notif?.title ?: "Juzzio"
            val body = data["body"] ?: notif?.body ?: ""

            if (body.isBlank() && title.isBlank()) return

            // Uygulama ön plandaysa (foreground) Flutter katmanına haber ver;
            // yalnızca data-only mesajlarda veya açıkça isteniyorsa tek bir bildirim göster.
            if (MainActivity.isAppInForeground && MainActivity.activeMethodChannel != null) {
                val payload = mapOf(
                    "notification_id" to notificationId,
                    "event_type" to eventType,
                    "title" to title,
                    "body" to body,
                    "target_id" to targetId,
                    "target_secondary_id" to targetSecondaryId,
                    "actor_id" to actorId,
                    "channel_id" to channelId
                )
                Handler(Looper.getMainLooper()).post {
                    try {
                        MainActivity.activeMethodChannel?.invokeMethod("onForegroundFcmMessage", payload)
                    } catch (_: Exception) {}
                }
                return
            }

            val notifIntId = if (notificationId.isNotBlank()) {
                notificationId.hashCode() and 0x7FFFFFFF
            } else {
                (System.currentTimeMillis() % 100000).toInt()
            }

            MainActivity.displaySystemNotification(
                context = applicationContext,
                id = notifIntId,
                title = title,
                body = body,
                isUpdate = eventType == "system",
                isCall = eventType == "missed_call" || eventType == "incoming_call",
                channelOverride = channelId,
                eventType = eventType,
                notificationId = notificationId,
                targetId = targetId,
                targetSecondaryId = targetSecondaryId,
                actorId = actorId
            )
        } catch (_: Exception) {}
    }
}
