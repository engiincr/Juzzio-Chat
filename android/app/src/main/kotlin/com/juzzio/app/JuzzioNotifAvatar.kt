package com.juzzio.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
import android.util.LruCache
import java.net.HttpURLConnection
import java.net.URL

/**
 * v1.2.4 — Bildirimde gönderen fotoğrafı (sohbet tarzı bildirim).
 * Yalnız herkese açık https adresinden, kısa zaman aşımıyla (3 sn) ve en fazla 2 MB indirilir;
 * yuvarlak kırpılıp bellekte (LRU, 24 adet) saklanır. Başarısızlıkta null → bildirim yine çıkar.
 * Ağ çağrısı yalnız FCM servisinin arka plan iş parçacığında yapılır.
 */
object JuzzioNotifAvatar {
    private const val MAX_BYTES = 2 * 1024 * 1024
    private const val SIZE = 192
    private val cache = LruCache<String, Bitmap>(24)

    fun load(url: String?): Bitmap? {
        if (url.isNullOrBlank() || !url.startsWith("https://") || url.length > 1500) return null
        cache.get(url)?.let { return it }
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 3000
                readTimeout = 3000
                instanceFollowRedirects = true
            }
            if (conn.responseCode != 200) return null
            val bytes = conn.inputStream.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    total += n
                    if (total > MAX_BYTES) return null
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            }
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            var sample = 1
            while (opts.outWidth / (sample * 2) >= SIZE && opts.outHeight / (sample * 2) >= SIZE) sample *= 2
            val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            val round = circle(raw)
            cache.put(url, round)
            round
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    private fun circle(src: Bitmap): Bitmap {
        val side = minOf(src.width, src.height)
        val x = (src.width - side) / 2
        val y = (src.height - side) / 2
        val square = Bitmap.createBitmap(src, x, y, side, side)
        val scaled = Bitmap.createScaledBitmap(square, SIZE, SIZE, true)
        val out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        Canvas(out).drawCircle(SIZE / 2f, SIZE / 2f, SIZE / 2f, paint)
        return out
    }
}
