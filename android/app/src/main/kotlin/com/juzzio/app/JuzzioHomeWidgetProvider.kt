package com.juzzio.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * v0.7.0 — Juzzio ana ekran widget'ları (6 farklı boyut ve amaç).
 *  1) Sohbet (4x1, WhatsApp tarzı sade)   → JuzzioHomeWidgetProvider
 *  2) Hızlı eylemler (4x1)                → JuzzioActionsWidget
 *  3) Okunmamış sayacı (1x1)              → JuzzioUnreadWidget
 *  4) Hikâye kamerası (1x1)               → JuzzioCameraWidget
 *  5) Son arama (3x1)                     → JuzzioCallsWidget
 *  6) Son sohbetler (4x2)                 → JuzzioRecentWidget
 * Hepsi uygulamanın o anki temasına (aydınlık/karanlık) ve arayüz diline uyar.
 * Veriler uygulama tarafından "updateHomeWidget" kanal çağrısıyla yazılır.
 */
object JuzzioWidgets {
    const val EXTRA_ACTION = "juzzio_widget_action"
    private const val PREFS = "juzzio_home_widget"

    private val ALL = listOf(
        JuzzioHomeWidgetProvider::class.java,
        JuzzioActionsWidget::class.java,
        JuzzioUnreadWidget::class.java,
        JuzzioCameraWidget::class.java,
        JuzzioCallsWidget::class.java,
        JuzzioRecentWidget::class.java,
    )

    fun saveData(
        context: Context,
        unread: Int,
        lastName: String,
        lastText: String,
        userName: String,
        palette: String,
        lang: String,
        dark: Boolean,
        recentJson: String,
        lastCallJson: String,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt("unread", unread.coerceAtLeast(0))
            .putString("last_name", lastName.take(60))
            .putString("last_text", lastText.take(140))
            .putString("user_name", userName.take(40))
            .putString("palette", palette)
            .putString("lang", lang)
            .putBoolean("dark", dark)
            .putString("recent", recentJson.take(4000))
            .putString("last_call", lastCallJson.take(1000))
            .apply()
        refreshAll(context)
    }

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (cls in ALL) {
            try {
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) continue
                val views = build(context, cls)
                for (id in ids) manager.updateAppWidget(id, views)
            } catch (_: Exception) {
            }
        }
    }

    class Data(val p: android.content.SharedPreferences) {
        val lang: String = p.getString("lang", "tr") ?: "tr"
        val dark: Boolean = p.getBoolean("dark", true)
        val unread: Int = p.getInt("unread", 0)
        val lastName: String = p.getString("last_name", "") ?: ""
        val lastText: String = p.getString("last_text", "") ?: ""
        val fg: Int = if (dark) 0xFFFFFFFF.toInt() else 0xFF111113.toInt()
        val sub: Int = if (dark) 0xB3FFFFFF.toInt() else 0xFF5A5A62.toInt()
        val bg: Int = if (dark) R.drawable.juzzio_wbg_dark else R.drawable.juzzio_wbg_light
        val btn: Int = if (dark) R.drawable.juzzio_wbtn_dark else R.drawable.juzzio_wbtn_light
        val rowBg: Int = if (dark) R.drawable.juzzio_wrow_dark else R.drawable.juzzio_wrow_light
        fun t(tr: String, en: String, de: String): String = when (lang.lowercase()) {
            "tr" -> tr
            "de" -> de
            else -> en
        }
    }

    private fun intent(context: Context, action: String, code: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ACTION, action)
        }
        return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun badge(v: RemoteViews, id: Int, count: Int) {
        if (count > 0) {
            v.setViewVisibility(id, View.VISIBLE)
            v.setTextViewText(id, if (count > 99) "99+" else count.toString())
        } else {
            v.setViewVisibility(id, View.GONE)
        }
    }

    fun build(context: Context, cls: Class<*>): RemoteViews {
        val d = Data(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE))
        return when (cls) {
            JuzzioActionsWidget::class.java -> actions(context, d)
            JuzzioUnreadWidget::class.java -> unread(context, d)
            JuzzioCameraWidget::class.java -> camera(context, d)
            JuzzioCallsWidget::class.java -> calls(context, d)
            JuzzioRecentWidget::class.java -> recent(context, d)
            else -> chat(context, d)
        }
    }

    private fun chat(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        v.setTextColor(R.id.w_title, d.fg)
        v.setTextColor(R.id.w_sub, d.sub)
        if (d.lastName.isNotBlank()) {
            v.setTextViewText(R.id.w_title, d.lastName)
            v.setTextViewText(R.id.w_sub, d.lastText.ifBlank { d.t("Yeni mesaj", "New message", "Neue Nachricht") })
        } else {
            v.setTextViewText(R.id.w_title, "Juzzio")
            v.setTextViewText(R.id.w_sub, d.t("Her şey güncel", "All caught up", "Alles erledigt"))
        }
        badge(v, R.id.w_badge, d.unread)
        v.setOnClickPendingIntent(R.id.w_root, intent(context, "chats", 7200))
        return v
    }

    private fun actions(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget_actions)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        val items = listOf(
            Triple(R.id.w_a1, "chats", d.t("Sohbet", "Chats", "Chats")),
            Triple(R.id.w_a2, "new_message", d.t("Yeni", "New", "Neu")),
            Triple(R.id.w_a3, "camera", d.t("Kamera", "Camera", "Kamera")),
            Triple(R.id.w_a4, "calls", d.t("Arama", "Calls", "Anrufe")),
        )
        val icons = listOf(R.id.w_a1_icon, R.id.w_a2_icon, R.id.w_a3_icon, R.id.w_a4_icon)
        val labels = listOf(R.id.w_a1_label, R.id.w_a2_label, R.id.w_a3_label, R.id.w_a4_label)
        items.forEachIndexed { i, (id, action, label) ->
            v.setInt(icons[i], "setBackgroundResource", d.btn)
            v.setInt(icons[i], "setColorFilter", d.fg)
            v.setTextViewText(labels[i], label)
            v.setTextColor(labels[i], d.sub)
            v.setOnClickPendingIntent(id, intent(context, action, 7210 + i))
        }
        return v
    }

    private fun unread(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget_unread)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        v.setInt(R.id.w_icon, "setColorFilter", if (d.unread > 0) 0xFF25D366.toInt() else d.fg)
        v.setTextViewText(R.id.w_count, if (d.unread > 99) "99+" else d.unread.toString())
        v.setTextColor(R.id.w_count, d.fg)
        v.setTextViewText(R.id.w_label, d.t("okunmamış", "unread", "ungelesen"))
        v.setTextColor(R.id.w_label, d.sub)
        v.setOnClickPendingIntent(R.id.w_root, intent(context, "chats", 7220))
        return v
    }

    private fun camera(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget_camera)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        v.setInt(R.id.w_icon, "setBackgroundResource", d.btn)
        v.setInt(R.id.w_icon, "setColorFilter", d.fg)
        v.setTextViewText(R.id.w_label, d.t("Hikâye", "Story", "Story"))
        v.setTextColor(R.id.w_label, d.sub)
        v.setOnClickPendingIntent(R.id.w_root, intent(context, "camera", 7230))
        return v
    }

    private fun calls(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget_calls)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        v.setInt(R.id.w_icon, "setBackgroundResource", d.btn)
        v.setTextColor(R.id.w_title, d.fg)
        v.setTextColor(R.id.w_sub, d.sub)
        var title = d.t("Aramalar", "Calls", "Anrufe")
        var sub = d.t("Henüz arama yok", "No calls yet", "Noch keine Anrufe")
        var missed = false
        try {
            val raw = d.p.getString("last_call", "") ?: ""
            if (raw.isNotBlank()) {
                val o = JSONObject(raw)
                title = o.optString("name", title).ifBlank { title }
                missed = o.optBoolean("missed", false)
                sub = listOf(o.optString("status", ""), o.optString("time", "")).filter { it.isNotBlank() }.joinToString(" · ")
                    .ifBlank { sub }
            }
        } catch (_: Exception) {
        }
        v.setImageViewResource(R.id.w_icon, if (missed) R.drawable.ic_juzzio_widget_missed else R.drawable.ic_juzzio_widget_call)
        v.setInt(R.id.w_icon, "setColorFilter", if (missed) 0xFFEF4444.toInt() else d.fg)
        v.setTextViewText(R.id.w_title, title)
        v.setTextViewText(R.id.w_sub, sub)
        v.setOnClickPendingIntent(R.id.w_root, intent(context, "calls", 7240))
        return v
    }

    private fun recent(context: Context, d: Data): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.juzzio_widget_recent)
        v.setInt(R.id.w_root, "setBackgroundResource", d.bg)
        v.setTextViewText(R.id.w_title, d.t("Son sohbetler", "Recent chats", "Letzte Chats"))
        v.setTextColor(R.id.w_title, d.fg)
        badge(v, R.id.w_badge, d.unread)
        val rows = listOf(
            arrayOf(R.id.w_r1, R.id.w_r1_name, R.id.w_r1_text, R.id.w_r1_badge),
            arrayOf(R.id.w_r2, R.id.w_r2_name, R.id.w_r2_text, R.id.w_r2_badge),
            arrayOf(R.id.w_r3, R.id.w_r3_name, R.id.w_r3_text, R.id.w_r3_badge),
        )
        var arr = JSONArray()
        try {
            arr = JSONArray(d.p.getString("recent", "[]") ?: "[]")
        } catch (_: Exception) {
        }
        rows.forEachIndexed { i, r ->
            v.setInt(r[0], "setBackgroundResource", d.rowBg)
            v.setTextColor(r[1], d.fg)
            v.setTextColor(r[2], d.sub)
            if (i < arr.length()) {
                val o = arr.optJSONObject(i) ?: JSONObject()
                v.setViewVisibility(r[0], View.VISIBLE)
                v.setTextViewText(r[1], o.optString("name", ""))
                v.setTextViewText(r[2], o.optString("text", ""))
                badge(v, r[3], o.optInt("unread", 0))
            } else if (i == 0) {
                v.setViewVisibility(r[0], View.VISIBLE)
                v.setTextViewText(r[1], d.t("Her şey güncel", "All caught up", "Alles erledigt"))
                v.setTextViewText(r[2], d.t("Yeni mesajlar burada görünür", "New messages appear here", "Neue Nachrichten erscheinen hier"))
                badge(v, r[3], 0)
            } else {
                v.setViewVisibility(r[0], View.INVISIBLE)
            }
            v.setOnClickPendingIntent(r[0], intent(context, "chats", 7250 + i))
        }
        v.setOnClickPendingIntent(R.id.w_header, intent(context, "chats", 7260))
        return v
    }
}

abstract class JuzzioBaseWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val views = JuzzioWidgets.build(context, this::class.java)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }
}

/** 1) Sohbet (4x1) — eski widget'ın sınıf adı korunur, böylece ekli widget'lar bozulmaz */
class JuzzioHomeWidgetProvider : JuzzioBaseWidget() {
    companion object {
        const val EXTRA_ACTION = JuzzioWidgets.EXTRA_ACTION
    }
}
class JuzzioActionsWidget : JuzzioBaseWidget()
class JuzzioUnreadWidget : JuzzioBaseWidget()
class JuzzioCameraWidget : JuzzioBaseWidget()
class JuzzioCallsWidget : JuzzioBaseWidget()
class JuzzioRecentWidget : JuzzioBaseWidget()
