package com.juzzio.app

import com.juzzio.app.R

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.util.Rational
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "juzzio/notifications"
        const val NOTIF_CHANNEL_ID = "juzzio_high_priority_v2"
        const val CALL_CHANNEL_ID = "juzzio_calls_priority_v2"
        const val SOCIAL_CHANNEL_ID = "juzzio_social_priority_v2"
        const val UPDATE_CHANNEL_ID = "juzzio_ota_update_v2"
        const val PREFS_NAME = "juzzio_fcm_push_prefs"
        const val PREF_NOTIF_PREVIEW = "notif_preview_mode"
        const val PREF_UI_LANG = "ui_lang"
        // v0.9.7: bildirim yığını (grup) anahtarı ve özet bildirim kimliği
        const val JUZZIO_NOTIF_GROUP = "com.juzzio.app.STACK"
        const val JUZZIO_NOTIF_SUMMARY_ID = 990001

        // v0.7.0: Uygulamaya özel bildirim tonları ve zil sesleri (res/raw). Android 8+
        // kanal sesi kanal oluşturulurken sabitlendiği için her ses ayrı bir kanaldır:
        // juzzio_msg_<ses> ve juzzio_call_<ses>. Sunucu (push-webhook) alıcının seçimine
        // (kişiye özel dahil) göre kanalı seçer.
        val MESSAGE_TONES = listOf("juzzio_tone_glass", "juzzio_tone_drop", "juzzio_tone_pop", "juzzio_tone_chime")
        val RINGTONES = listOf("juzzio_ring_aurora", "juzzio_ring_crystal", "juzzio_ring_pulse", "juzzio_ring_breeze")
        private var ringPlayer: android.media.MediaPlayer? = null
        private var previewPlayer: android.media.MediaPlayer? = null

        fun rawSoundUri(context: Context, id: String): Uri? {
            if (id.isBlank() || id == "default") return null
            val res = context.resources.getIdentifier(id, "raw", context.packageName)
            if (res == 0) return null
            return Uri.parse("android.resource://${context.packageName}/$res")
        }

        fun soundForChannel(context: Context, channelId: String?, isCall: Boolean): Uri? {
            val c = channelId ?: return null
            val id = when {
                c.startsWith("juzzio_msg_") -> c.removePrefix("juzzio_msg_")
                c.startsWith("juzzio_call_") -> c.removePrefix("juzzio_call_")
                else -> return null
            }
            return rawSoundUri(context, id)
        }

        fun stopRinging() {
            try {
                ringPlayer?.stop()
                ringPlayer?.release()
            } catch (_: Exception) {}
            ringPlayer = null
        }

        fun startRinging(context: Context, id: String) {
            stopRinging()
            try {
                val uri = rawSoundUri(context, id)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE) ?: return
                val mp = android.media.MediaPlayer()
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.setDataSource(context, uri)
                mp.isLooping = true
                mp.prepare()
                mp.start()
                ringPlayer = mp
            } catch (_: Exception) {
                stopRinging()
            }
        }

        fun previewSound(context: Context, id: String, isRing: Boolean) {
            try {
                previewPlayer?.stop()
                previewPlayer?.release()
            } catch (_: Exception) {}
            previewPlayer = null
            try {
                val uri = rawSoundUri(context, id) ?: RingtoneManager.getDefaultUri(
                    if (isRing) RingtoneManager.TYPE_RINGTONE else RingtoneManager.TYPE_NOTIFICATION
                ) ?: return
                val mp = android.media.MediaPlayer()
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                mp.setDataSource(context, uri)
                mp.prepare()
                mp.setOnCompletionListener { it.release(); if (previewPlayer === it) previewPlayer = null }
                mp.start()
                previewPlayer = mp
                // Uzun sistem zil seslerinde önizleme 4 sn ile sınırlı
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        if (previewPlayer === mp && mp.isPlaying) { mp.stop(); mp.release(); previewPlayer = null }
                    } catch (_: Exception) {}
                }, 4000)
            } catch (_: Exception) {}
        }

        @Volatile
        var isAppInForeground: Boolean = false

        @Volatile
        var activeMethodChannel: MethodChannel? = null

        fun notifyTokenRefreshToFlutter(token: String) {
            val ch = activeMethodChannel ?: return
            Handler(Looper.getMainLooper()).post {
                try {
                    ch.invokeMethod("onFcmTokenRefresh", mapOf("token" to token))
                } catch (_: Exception) {}
            }
        }

        fun ensureChannelsCreated(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val callSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE) ?: defaultSoundUri

                val audioAttr = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val msgChannel = NotificationChannel(
                    NOTIF_CHANNEL_ID,
                    "Juzzio Anlık Mesaj & Grup Bildirimleri",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Birebir ve grup sohbeti bildirimleri"
                    enableVibration(true)
                    enableLights(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    setSound(defaultSoundUri, audioAttr)
                }

                val callChannel = NotificationChannel(
                    CALL_CHANNEL_ID,
                    "Juzzio Gelen Sesli & Görüntülü Aramalar",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Sesli ve görüntülü konferans arama bildirimleri"
                    enableVibration(true)
                    enableLights(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    setSound(callSoundUri, audioAttr)
                }

                val socialChannel = NotificationChannel(
                    SOCIAL_CHANNEL_ID,
                    "Juzzio Sosyal Etkileşimler (Beğeni, Yorum, Takip)",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Beğeni, yorum, yanıt, hikâye yanıtı ve takip isteği bildirimleri"
                    enableVibration(true)
                    enableLights(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    setSound(defaultSoundUri, audioAttr)
                }

                val updateChannel = NotificationChannel(
                    UPDATE_CHANNEL_ID,
                    "Juzzio OTA Sürüm Güncellemeleri",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Yeni Juzzio sürümü güncelleme bildirimleri"
                    enableVibration(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    setSound(defaultSoundUri, audioAttr)
                }

                nm.createNotificationChannel(msgChannel)
                nm.createNotificationChannel(callChannel)
                nm.createNotificationChannel(socialChannel)
                nm.createNotificationChannel(updateChannel)

                // v0.7.0: sese özel kanallar
                val ringAttr = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                for (tone in MESSAGE_TONES) {
                    val uri = rawSoundUri(context, tone) ?: continue
                    nm.createNotificationChannel(NotificationChannel(
                        "juzzio_msg_$tone", "Juzzio mesaj tonu: ${tone.removePrefix("juzzio_tone_")}", NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Juzzio'ya özel mesaj bildirimi tonu"
                        enableVibration(true)
                        lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                        setSound(uri, audioAttr)
                    })
                }
                for (ring in RINGTONES) {
                    val uri = rawSoundUri(context, ring) ?: continue
                    nm.createNotificationChannel(NotificationChannel(
                        "juzzio_call_$ring", "Juzzio zil sesi: ${ring.removePrefix("juzzio_ring_")}", NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Juzzio'ya özel gelen arama zil sesi"
                        enableVibration(true)
                        lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                        setSound(uri, ringAttr)
                    })
                }
            }
        }

        /**
         * v0.9.0 N-D/§6.4: mesaj bildirimleri için kilit ekranında GİZLİ (VISIBILITY_PRIVATE) ve
         * isteğe bağlı titreşimsiz kanal varyantı. Android 8+ kanalın kilit ekranı/titreşim ayarını
         * bildirimin kendi ayarına tercih ettiği ve kanal oluşturulduktan sonra değiştirilemediği
         * için, mevcut kanalın (özel ton dahil) sesini koruyan ayrı bir kanal oluşturulur.
         */
        fun privateMessageChannel(context: Context, baseId: String, vibrate: Boolean): String {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return baseId
            return try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val base = nm.getNotificationChannel(baseId) ?: nm.getNotificationChannel(NOTIF_CHANNEL_ID) ?: return baseId
                val id = baseId + if (vibrate) "_p3" else "_p3nv"
                if (nm.getNotificationChannel(id) == null) {
                    nm.createNotificationChannel(NotificationChannel(id, "${base.name} 🔒", base.importance).apply {
                        description = base.description
                        enableVibration(vibrate)
                        if (!vibrate) vibrationPattern = longArrayOf(0L)
                        enableLights(true)
                        lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                        setSound(base.sound, base.audioAttributes)
                    })
                }
                id
            } catch (_: Exception) {
                baseId
            }
        }

        fun displaySystemNotification(
            context: Context,
            id: Int,
            title: String,
            body: String,
            isUpdate: Boolean,
            isCall: Boolean,
            channelOverride: String?,
            eventType: String,
            notificationId: String,
            targetId: String,
            targetSecondaryId: String,
            actorId: String,
            // v0.9.0 N-D: doluysa bildirim gizli (VISIBILITY_PRIVATE) olur; kilit ekranında bu metin görünür
            lockScreenBody: String? = null,
            vibrate: Boolean = true
        ) {
            try {
                ensureChannelsCreated(context)
                val baseChannelId = channelOverride ?: when {
                    isUpdate -> UPDATE_CHANNEL_ID
                    isCall -> CALL_CHANNEL_ID
                    eventType in listOf(
                        "like", "comment", "reply", "comment_like", "mention", "follow", "follow_request",
                        "follow_accepted", "friend_request", "friend_accepted",
                        "story_like", "story_reply"
                    ) -> SOCIAL_CHANNEL_ID
                    else -> NOTIF_CHANNEL_ID
                }
                val resolvedChannelId = if (lockScreenBody != null) {
                    privateMessageChannel(context, baseChannelId, vibrate)
                } else baseChannelId

                val intentEventId = if (notificationId.isNotBlank()) {
                    notificationId
                } else {
                    "${eventType}_${targetId}_${System.currentTimeMillis()}"
                }

                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    if (isUpdate) {
                        putExtra("juzzio_action", "open_ota_update")
                    }
                    putExtra("juzzio_intent_event_id", intentEventId)
                    putExtra("juzzio_notification_id", notificationId)
                    putExtra("juzzio_event_type", eventType)
                    putExtra("juzzio_title", title)
                    putExtra("juzzio_body", body)
                    putExtra("juzzio_target_id", targetId)
                    putExtra("juzzio_target_secondary_id", targetSecondaryId)
                    putExtra("juzzio_actor_id", actorId)
                    putExtra("juzzio_channel_id", resolvedChannelId)
                }

                val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getActivity(context, id, intent, pendingIntentFlags)

                val defaultSoundUri = soundForChannel(context, baseChannelId, isCall) ?: RingtoneManager.getDefaultUri(
                    if (isCall) RingtoneManager.TYPE_RINGTONE else RingtoneManager.TYPE_NOTIFICATION
                )

                val smallIconRes: Int = if (context.applicationInfo.icon != 0) {
                    context.applicationInfo.icon
                } else {
                    R.mipmap.ic_launcher
                }

                val builder = NotificationCompat.Builder(context, resolvedChannelId)
                builder.setSmallIcon(smallIconRes)
                builder.setContentTitle(title)
                builder.setContentText(body)
                builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
                builder.setPriority(NotificationCompat.PRIORITY_MAX)
                builder.setDefaults(
                    if (vibrate) NotificationCompat.DEFAULT_VIBRATE or NotificationCompat.DEFAULT_LIGHTS
                    else NotificationCompat.DEFAULT_LIGHTS
                )
                builder.setSound(defaultSoundUri)
                if (lockScreenBody != null) {
                    builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                    builder.setPublicVersion(
                        NotificationCompat.Builder(context, resolvedChannelId)
                            .setSmallIcon(smallIconRes)
                            .setContentTitle("Juzzio")
                            .setContentText(lockScreenBody)
                            .build()
                    )
                } else {
                    builder.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                }
                builder.setCategory(
                    when {
                        isUpdate -> NotificationCompat.CATEGORY_RECOMMENDATION
                        isCall -> NotificationCompat.CATEGORY_CALL
                        eventType in listOf("like", "comment", "reply", "comment_like", "mention", "follow", "follow_request") -> NotificationCompat.CATEGORY_SOCIAL
                        else -> NotificationCompat.CATEGORY_MESSAGE
                    }
                )
                builder.setAutoCancel(true)
                builder.setContentIntent(pendingIntent)

                // v0.8.3: mesaj bildiriminde satır içi yanıt (uygulamayı açmadan gönder)
                if ((eventType == "message" || eventType == "group_activity") && targetId.isNotBlank()) {
                    try {
                        // v0.9.3: eylem metinleri uygulama/cihaz diline göre
                        val lang = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            .getString(PREF_UI_LANG, null) ?: java.util.Locale.getDefault().language
                        val (hint, label) = when (lang.substringBefore('-')) {
                            "tr" -> "Yanıt yaz…" to "Yanıtla"
                            "de" -> "Antwort schreiben…" to "Antworten"
                            "es" -> "Escribe una respuesta…" to "Responder"
                            "fr" -> "Écrire une réponse…" to "Répondre"
                            "ar" -> "اكتب ردًا…" to "رد"
                            "ru" -> "Написать ответ…" to "Ответить"
                            else -> "Write a reply…" to "Reply"
                        }
                        val remoteInput = androidx.core.app.RemoteInput.Builder(JuzzioReplyReceiver.KEY_TEXT)
                            .setLabel(hint)
                            .build()
                        val replyIntent = Intent(context, JuzzioReplyReceiver::class.java).apply {
                            action = JuzzioReplyReceiver.ACTION_REPLY
                            putExtra(JuzzioReplyReceiver.EXTRA_ROOM, targetId)
                            putExtra(JuzzioReplyReceiver.EXTRA_NOTIF_ID, id)
                            putExtra(JuzzioReplyReceiver.EXTRA_TITLE, title)
                            putExtra(JuzzioReplyReceiver.EXTRA_CHANNEL, resolvedChannelId)
                        }
                        // RemoteInput metni doldurabilsin diye MUTABLE (Android 12+ zorunlu)
                        val replyFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                        } else {
                            PendingIntent.FLAG_UPDATE_CURRENT
                        }
                        val replyPending = PendingIntent.getBroadcast(context, id, replyIntent, replyFlags)
                        val action = NotificationCompat.Action.Builder(
                            android.R.drawable.ic_menu_send, label, replyPending
                        )
                            .addRemoteInput(remoteInput)
                            .setAllowGeneratedReplies(true)
                            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                            .setShowsUserInterface(false)
                            .build()
                        builder.addAction(action)
                    } catch (_: Exception) {}
                }

                // v0.9.0 N-F: gelen aramada Kabul / Reddet (CallStyle). Kabul uygulamayı açar ve
                // aramayı o çağrı kimliğiyle cevaplar; Reddet uygulamayı açmadan sunucuda reddeder.
                if (eventType == "incoming_call" && targetSecondaryId.isNotBlank()) {
                    try {
                        val acceptIntent = Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra("juzzio_intent_event_id", "accept_" + targetSecondaryId)
                            putExtra("juzzio_notification_id", notificationId)
                            putExtra("juzzio_event_type", eventType)
                            putExtra("juzzio_title", title)
                            putExtra("juzzio_target_id", targetId)
                            putExtra("juzzio_target_secondary_id", targetSecondaryId)
                            putExtra("juzzio_actor_id", actorId)
                            putExtra("juzzio_call_action", "accept")
                            putExtra("juzzio_call_notif_id", id)
                        }
                        val acceptPending = PendingIntent.getActivity(context, id + 1, acceptIntent, pendingIntentFlags)
                        val declineIntent = Intent(context, JuzzioCallActionReceiver::class.java).apply {
                            action = JuzzioCallActionReceiver.ACTION_DECLINE
                            putExtra(JuzzioCallActionReceiver.EXTRA_CALL_ID, targetSecondaryId)
                            putExtra(JuzzioCallActionReceiver.EXTRA_NOTIF_ID, id)
                        }
                        val declinePending = PendingIntent.getBroadcast(context, id + 2, declineIntent, pendingIntentFlags)
                        val caller = androidx.core.app.Person.Builder().setName(title).setImportant(true).build()
                        builder.setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, declinePending, acceptPending))
                        builder.setOngoing(true)
                        builder.setAutoCancel(false)
                        builder.setTimeoutAfter(60_000L)
                    } catch (_: Exception) {}
                }

                if (isCall) {
                    builder.setFullScreenIntent(pendingIntent, true)
                }

                // v0.9.7: bildirim yığını — arama dışı bildirimler tek grupta üst üste toplanır
                val stackable = !isCall && eventType != "incoming_call"
                if (stackable) {
                    builder.setGroup(JUZZIO_NOTIF_GROUP)
                    builder.setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
                }

                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(id, builder.build())
                if (stackable && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        val summary = NotificationCompat.Builder(context, resolvedChannelId)
                            .setSmallIcon(smallIconRes)
                            .setContentTitle("Juzzio")
                            .setStyle(NotificationCompat.InboxStyle().setSummaryText("Juzzio"))
                            .setGroup(JUZZIO_NOTIF_GROUP)
                            .setGroupSummary(true)
                            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
                            .setAutoCancel(true)
                            .setContentIntent(pendingIntent)
                            .build()
                        nm.notify(JUZZIO_NOTIF_SUMMARY_ID, summary)
                    } catch (_: Exception) {}
                }
            } catch (_: Exception) {}
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var pendingPushTapPayload: Map<String, String>? = null
    private val consumedIntentEventIds = mutableSetOf<String>()
    // Ana ekran widget'ından gelen hızlı eylem (chats | new_message | camera | calls)
    private var pendingWidgetAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        isAppInForeground = true
        // v0.7.0: Uygulama açıkken (sohbet, arama) ekran kendiliğinden kararmaz/sönmez
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        ensureChannelsCreated(this)
        captureWidgetActionIfNeeded(intent, dispatchImmediatelyIfReady = false)
        capturePushIntentIfNeeded(intent, dispatchImmediatelyIfReady = false)
    }

    private fun captureWidgetActionIfNeeded(intent: Intent?, dispatchImmediatelyIfReady: Boolean) {
        if (intent == null) return
        val action = intent.getStringExtra(JuzzioHomeWidgetProvider.EXTRA_ACTION) ?: return
        intent.removeExtra(JuzzioHomeWidgetProvider.EXTRA_ACTION)
        val ch = activeMethodChannel
        if (dispatchImmediatelyIfReady && ch != null) {
            Handler(Looper.getMainLooper()).post {
                try {
                    ch.invokeMethod("onWidgetAction", mapOf("action" to action))
                } catch (_: Exception) {
                    pendingWidgetAction = action
                }
            }
        } else {
            pendingWidgetAction = action
        }
    }

    // v0.9.3: süren arama — ekran içinde ekran (PiP) ve ön plan servisi
    private var callActive = false
    private var callVideo = false

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder()
            .setAspectRatio(if (callVideo) Rational(9, 16) else Rational(3, 4))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(callActive)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    private fun applyPipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            pipParams()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {}
    }

    private fun enterCallPip(): Boolean {
        if (!callActive || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return try {
            enterPictureInPictureMode(pipParams()!!)
        } catch (_: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ otomatik girer (setAutoEnterEnabled); daha eskilerde elle
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterCallPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        try {
            activeMethodChannel?.invokeMethod("onPipChanged", mapOf("inPip" to isInPictureInPictureMode))
        } catch (_: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        acquireBackgroundRealtimeLocks()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // v0.9.3: "Arama sürüyor" bildirimine dokunuldu → arama ekranını büyüt
        if (intent.getStringExtra("juzzio_action") == "return_to_call") {
            intent.removeExtra("juzzio_action")
            Handler(Looper.getMainLooper()).post {
                try { activeMethodChannel?.invokeMethod("onReturnToCall", null) } catch (_: Exception) {}
            }
            return
        }
        captureWidgetActionIfNeeded(intent, dispatchImmediatelyIfReady = true)
        capturePushIntentIfNeeded(intent, dispatchImmediatelyIfReady = true)
    }

    private fun capturePushIntentIfNeeded(intent: Intent?, dispatchImmediatelyIfReady: Boolean) {
        if (intent == null) return
        val eventType = intent.getStringExtra("juzzio_event_type")
            ?: intent.getStringExtra("event_type")
            ?: intent.getStringExtra("type")
            ?: (if (intent.getStringExtra("juzzio_action") == "open_ota_update") "system" else null)

        if (eventType.isNullOrBlank()) return

        val targetId = intent.getStringExtra("juzzio_target_id")
            ?: intent.getStringExtra("target_id")
            ?: ""
        val notifId = intent.getStringExtra("juzzio_notification_id")
            ?: intent.getStringExtra("notification_id")
            ?: ""
        val rawEventId = intent.getStringExtra("juzzio_intent_event_id")
            ?: intent.getStringExtra("google.message_id")
            ?: "${eventType}_${notifId}_${targetId}"

        // Aynı intent'in hem onCreate hem onNewIntent ile iki kez işlenmesini engelle (Bölüm 9.6)
        if (consumedIntentEventIds.contains(rawEventId)) return
        consumedIntentEventIds.add(rawEventId)

        val payload = mapOf(
            "intent_event_id" to rawEventId,
            "notification_id" to notifId,
            "event_type" to eventType,
            "title" to (intent.getStringExtra("juzzio_title") ?: intent.getStringExtra("title") ?: "Juzzio"),
            "body" to (intent.getStringExtra("juzzio_body") ?: intent.getStringExtra("body") ?: ""),
            "target_id" to targetId,
            "target_secondary_id" to (intent.getStringExtra("juzzio_target_secondary_id") ?: intent.getStringExtra("target_secondary_id") ?: ""),
            "actor_id" to (intent.getStringExtra("juzzio_actor_id") ?: intent.getStringExtra("actor_id") ?: ""),
            "channel_id" to (intent.getStringExtra("juzzio_channel_id") ?: intent.getStringExtra("channel_id") ?: NOTIF_CHANNEL_ID),
            // v0.9.0 N-F: bildirimdeki "Kabul" düğmesi
            "call_action" to (intent.getStringExtra("juzzio_call_action") ?: "")
        )
        if (intent.getStringExtra("juzzio_call_action") == "accept") {
            try {
                val nid = intent.getIntExtra("juzzio_call_notif_id", 0)
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(nid)
            } catch (_: Exception) {}
        }

        if (dispatchImmediatelyIfReady && activeMethodChannel != null) {
            Handler(Looper.getMainLooper()).post {
                try {
                    activeMethodChannel?.invokeMethod("onPushNotificationTapped", payload)
                } catch (_: Exception) {
                    pendingPushTapPayload = payload
                }
            }
        } else {
            pendingPushTapPayload = payload
        }
    }

    private fun getOrCreateDeviceInstallationId(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        var deviceId = prefs.getString("device_id", null)
        if (deviceId.isNullOrBlank()) {
            val androidId = try {
                Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
            } catch (_: Exception) {
                ""
            }
            deviceId = if (androidId.isNotBlank()) "and_$androidId" else "and_${UUID.randomUUID()}"
            prefs.edit().putString("device_id", deviceId).apply()
        }
        return deviceId
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureChannelsCreated(this)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        activeMethodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // v0.9.0 N-D: bildirim önizleme kipi ('full' | 'sender' | 'hidden')
                "setNotificationPreviewMode" -> {
                    val mode = call.argument<String>("mode") ?: "full"
                    val safe = if (mode == "sender" || mode == "hidden") mode else "full"
                    val ui = call.argument<String>("uiLang")
                    val ed = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                        .putString(PREF_NOTIF_PREVIEW, safe)
                    // v0.9.3: bildirim eylem metinleri için uygulama dili
                    if (ui != null && Regex("^[a-z]{2,3}(-[A-Za-z0-9]{2,4})?$").matches(ui)) ed.putString(PREF_UI_LANG, ui)
                    ed.apply()
                    result.success(true)
                }
                // v0.9.3: arama başladı/bitti → ön plan servisi + PiP
                "setCallActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    callVideo = call.argument<Boolean>("video") ?: false
                    callActive = active
                    if (active) {
                        JuzzioCallService.start(this, call.argument<String>("title") ?: "Juzzio", callVideo)
                    } else {
                        JuzzioCallService.stop(this)
                    }
                    applyPipParams()
                    result.success(true)
                }
                "enterCallPip" -> result.success(enterCallPip())
                // v0.9.4: cihaz saati sunucudan saparsa Tarih ve Saat ayarları açılır
                // v0.9.5: tek seferlik medya görüntülenirken ekran görüntüsü/kayıt engellenir
                "setSecureScreen" -> {
                    val on = call.argument<Boolean>("secure") ?: false
                    if (on) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "openDateSettings" -> {
                    try {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_DATE_SETTINGS)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isAutoTimeEnabled" -> {
                    val auto = try {
                        android.provider.Settings.Global.getInt(contentResolver, android.provider.Settings.Global.AUTO_TIME, 1) == 1
                    } catch (_: Exception) { true }
                    result.success(auto)
                }
                "showSystemNotification" -> {
                    val title = call.argument<String>("title") ?: "Juzzio"
                    val body = call.argument<String>("body") ?: ""
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                    val isUpdate = call.argument<Boolean>("isUpdate") ?: false
                    val isCall = call.argument<Boolean>("isCall") ?: false
                    val channelArg = call.argument<String>("channelId")
                    displaySystemNotification(
                        context = this,
                        id = id,
                        title = title,
                        body = body,
                        isUpdate = isUpdate,
                        isCall = isCall,
                        channelOverride = channelArg,
                        // v0.9.3: uygulama açıkken gelen mesaj bildirimi de sohbete gider ve yanıtlanabilir
                        eventType = call.argument<String>("eventType")
                            ?: (if (isUpdate) "system" else (if (isCall) "missed_call" else "message")),
                        notificationId = call.argument<String>("notificationId") ?: "",
                        targetId = call.argument<String>("targetId") ?: "",
                        targetSecondaryId = call.argument<String>("targetSecondaryId") ?: "",
                        actorId = call.argument<String>("actorId") ?: "",
                        lockScreenBody = call.argument<String>("lockScreenBody")
                    )
                    result.success(true)
                }
                "showRichSocialNotification" -> {
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                    val title = call.argument<String>("title") ?: "Juzzio"
                    val body = call.argument<String>("body") ?: ""
                    val channelId = call.argument<String>("channelId")
                    val eventType = call.argument<String>("eventType") ?: "system"
                    val notificationId = call.argument<String>("notificationId") ?: ""
                    val targetId = call.argument<String>("targetId") ?: ""
                    val targetSecondaryId = call.argument<String>("targetSecondaryId") ?: ""
                    val actorId = call.argument<String>("actorId") ?: ""
                    val isCall = call.argument<Boolean>("isCall") ?: (eventType == "missed_call")
                    val isUpdate = call.argument<Boolean>("isUpdate") ?: (eventType == "system")

                    displaySystemNotification(
                        context = this,
                        id = id,
                        title = title,
                        body = body,
                        isUpdate = isUpdate,
                        isCall = isCall,
                        channelOverride = channelId,
                        eventType = eventType,
                        notificationId = notificationId,
                        targetId = targetId,
                        targetSecondaryId = targetSecondaryId,
                        actorId = actorId
                    )
                    result.success(true)
                }
                "previewSound" -> {
                    previewSound(this, call.argument<String>("id") ?: "default", call.argument<Boolean>("ring") ?: false)
                    result.success(true)
                }
                "startRingtone" -> {
                    startRinging(this, call.argument<String>("id") ?: "default")
                    result.success(true)
                }
                "stopRingtone" -> {
                    stopRinging()
                    result.success(true)
                }
                "getFirebaseConfigSummary" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val deviceId = getOrCreateDeviceInstallationId()
                    val notificationsAllowed = NotificationManagerCompat.from(this).areNotificationsEnabled()

                    try {
                        var apps = FirebaseApp.getApps(this)
                        if (apps.isEmpty()) {
                            FirebaseApp.initializeApp(this)
                            apps = FirebaseApp.getApps(this)
                        }
                        if (apps.isEmpty()) {
                            throw IllegalStateException("FirebaseApp is not initialized. Ensure android/app/google-services.json is present at build time.")
                        }
                        val fbApp = FirebaseApp.getInstance()
                        val opts = fbApp.options
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful && !task.result.isNullOrBlank()) {
                                val realToken = task.result!!
                                prefs.edit().putString("fcm_push_token", realToken).apply()
                                result.success(
                                    mapOf(
                                        "fcm_configured" to true,
                                        "fcm_status" to "ready",
                                        "project_id" to (opts.projectId ?: "juzzio"),
                                        "project_number" to (opts.gcmSenderId ?: "252976064150"),
                                        "mobilesdk_app_id" to opts.applicationId,
                                        "package_name" to packageName,
                                        "device_id" to deviceId,
                                        "push_token" to realToken,
                                        "notifications_enabled_os" to notificationsAllowed
                                    )
                                )
                            } else {
                                val cachedToken = prefs.getString("fcm_push_token", null)
                                result.success(
                                    mapOf(
                                        "fcm_configured" to true,
                                        "fcm_status" to "token_unavailable",
                                        "project_id" to (opts.projectId ?: "juzzio"),
                                        "project_number" to (opts.gcmSenderId ?: "252976064150"),
                                        "mobilesdk_app_id" to opts.applicationId,
                                        "package_name" to packageName,
                                        "device_id" to deviceId,
                                        "push_token" to (cachedToken ?: ""),
                                        "notifications_enabled_os" to notificationsAllowed,
                                        "error" to (task.exception?.localizedMessage ?: "FCM token could not be retrieved")
                                    )
                                )
                            }
                        }
                    } catch (e: Exception) {
                        result.success(
                            mapOf(
                                "fcm_configured" to false,
                                "fcm_status" to "missing_google_services_json",
                                "project_id" to "",
                                "project_number" to "",
                                "mobilesdk_app_id" to "",
                                "package_name" to packageName,
                                "device_id" to deviceId,
                                "push_token" to "",
                                "notifications_enabled_os" to notificationsAllowed,
                                "error" to (e.localizedMessage ?: "FirebaseApp is not initialized")
                            )
                        )
                    }
                }
                "getHardwareDeviceId" -> {
                    result.success(getOrCreateDeviceInstallationId())
                }
                "updateHomeWidget" -> {
                    try {
                        JuzzioWidgets.saveData(
                            this,
                            unread = (call.argument<Number>("unread") ?: 0).toInt(),
                            lastName = call.argument<String>("lastName") ?: "",
                            lastText = call.argument<String>("lastText") ?: "",
                            userName = call.argument<String>("userName") ?: "",
                            palette = call.argument<String>("palette") ?: "ocean",
                            lang = call.argument<String>("lang") ?: "tr",
                            dark = call.argument<Boolean>("dark") ?: true,
                            recentJson = call.argument<String>("recent") ?: "[]",
                            lastCallJson = call.argument<String>("lastCall") ?: ""
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "getWidgetAction" -> {
                    val action = pendingWidgetAction
                    pendingWidgetAction = null
                    result.success(action)
                }
                "getInitialPushPayload" -> {
                    val payload = pendingPushTapPayload
                    pendingPushTapPayload = null
                    result.success(payload)
                }
                "areNotificationsEnabledOnOs" -> {
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                }
                "requestNotificationPermission" -> {
                    requestPostNotificationsIfNeeded()
                    result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                }
                "openAppNotificationSettings" -> {
                    try {
                        val settingsIntent = Intent().apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.fromParts("package", packageName, null)
                            }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "ensureBackgroundLock" -> {
                    acquireBackgroundRealtimeLocks()
                    result.success(true)
                }
                "getNetworkConnectionType" -> {
                    result.success(resolveConnectionType())
                }
                "openUrlOrInstaller" -> {
                    val url = call.argument<String>("url") ?: "https://github.com/engiincr/Juzzio-Chat/releases/latest/download/Juzzio-latest.apk"
                    try {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(browserIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setBeautyFilter" -> {
                    val trackId = call.argument<String>("trackId")
                    val level = call.argument<Int>("level") ?: 0
                    val ok = try {
                        JuzzioBeautyProcessor.apply(trackId, level)
                    } catch (_: Throwable) {
                        false
                    }
                    result.success(ok)
                }
                "clearBeautyFilter" -> {
                    try {
                        JuzzioBeautyProcessor.detach()
                    } catch (_: Throwable) {
                    }
                    result.success(true)
                }
                "canInstallPackages" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "installApk" -> {
                    // İndirilen APK mevcut uygulamanın ÜZERİNE kurulur (aynı paket adı + aynı imza).
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success("missing_file")
                    } else {
                        try {
                            val file = java.io.File(path)
                            if (!file.exists() || file.length() < 1024L) {
                                result.success("missing_file")
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                result.success("needs_permission")
                            } else {
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    this, "$packageName.juzzio.otaprovider", file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success("started")
                            }
                        } catch (e: Exception) {
                            result.success("error:" + (e.localizedMessage ?: "install"))
                        }
                    }
                }
                "deviceProfile" -> {
                    // v0.8.2: düşük donanımlı cihazda cam bulanıklığı otomatik azaltılır
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        val mi = android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(mi)
                        result.success(mapOf(
                            "lowRam" to am.isLowRamDevice,
                            "totalMemMb" to (mi.totalMem / (1024L * 1024L)),
                            "sdk" to Build.VERSION.SDK_INT
                        ))
                    } catch (e: Exception) {
                        result.success(mapOf("lowRam" to false, "totalMemMb" to 0L, "sdk" to Build.VERSION.SDK_INT))
                    }
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val title = call.argument<String>("title") ?: "Juzzio"
                    try {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        val chooser = Intent.createChooser(send, title).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "videoFrames" -> {
                    // Video kırpıcı zaman çizelgesi ve kapak görseli için kareler (MediaMetadataRetriever)
                    val path = call.argument<String>("path") ?: ""
                    val times = call.argument<List<Number>>("timesMs") ?: emptyList()
                    val maxWidth = (call.argument<Number>("maxWidth") ?: 240).toInt().coerceIn(64, 1440)
                    val quality = (call.argument<Number>("quality") ?: 78).toInt().coerceIn(30, 95)
                    val mainHandler = Handler(Looper.getMainLooper())
                    Thread {
                        val out = ArrayList<String>()
                        var durationMs = 0L
                        val retriever = android.media.MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(path)
                            durationMs = retriever.extractMetadata(
                                android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                            )?.toLongOrNull() ?: 0L
                            val dir = java.io.File(cacheDir, "juzzio_frames")
                            if (!dir.exists()) dir.mkdirs()
                            for ((i, t) in times.withIndex()) {
                                val us = t.toLong().coerceAtLeast(0L) * 1000L
                                val frame = retriever.getFrameAtTime(
                                    us,
                                    android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                                ) ?: continue
                                val scaled = if (frame.width > maxWidth) {
                                    val h = (frame.height.toFloat() * maxWidth / frame.width).toInt().coerceAtLeast(1)
                                    android.graphics.Bitmap.createScaledBitmap(frame, maxWidth, h, true)
                                } else frame
                                val file = java.io.File(dir, "f_${System.nanoTime()}_$i.jpg")
                                java.io.FileOutputStream(file).use { os ->
                                    scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, os)
                                }
                                if (scaled !== frame) scaled.recycle()
                                frame.recycle()
                                out.add(file.absolutePath)
                            }
                        } catch (_: Exception) {
                        } finally {
                            try {
                                retriever.release()
                            } catch (_: Exception) {
                            }
                        }
                        val payload = mapOf("frames" to out, "durationMs" to durationMs)
                        mainHandler.post { result.success(payload) }
                    }.start()
                }
                "requestBatteryOptimizationExemption" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPostNotificationsIfNeeded() {
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        1001
                    )
                }
            }
        } catch (_: Exception) {}
    }

    private fun acquireBackgroundRealtimeLocks() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (wakeLock == null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "Juzzio::RealtimeBackgroundWakeLock"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                // v0.7.0: 24 saat yerine 10 dakika — arka planda pil tüketimini sınırlar
                wakeLock?.acquire(10 * 60 * 1000L)
            }

            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(lockMode, "Juzzio::RealtimeWifiLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        if (callActive) JuzzioCallService.stop(this)
        isAppInForeground = false
        if (activeMethodChannel != null) {
            activeMethodChannel = null
        }
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun resolveConnectionType(): String {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val net = cm.activeNetwork ?: return "none"
                val caps = cm.getNetworkCapabilities(net) ?: return "none"
                when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                    else -> "wifi"
                }
            } else {
                "wifi"
            }
        } catch (_: Exception) {
            "wifi"
        }
    }
}
