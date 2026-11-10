package com.juzzio.app

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * v1.2.4 — Sohbet medyasını galeriye kaydet (WhatsApp gibi).
 *  • Android 10+: MediaStore ile Pictures/Juzzio, Movies/Juzzio, Download/Juzzio — izin GEREKMEZ.
 *  • Android 9 ve altı: genel klasöre yazılır (WRITE_EXTERNAL_STORAGE verilmişse) ve taranır.
 *  • Dosya adı temizlenir; yol yalnız uygulamanın kendi önbellek/geçici klasöründen kabul edilir.
 */
object JuzzioGallery {
    fun save(ctx: Context, path: String, mime: String, name: String, kind: String): Boolean {
        return try {
            val src = File(path)
            val canon = src.canonicalPath
            val dataDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) ctx.dataDir else null
            val allowed = listOfNotNull(ctx.cacheDir, ctx.filesDir, ctx.codeCacheDir, dataDir)
                .any { canon.startsWith(it.canonicalPath) }
            if (!allowed || !src.isFile || src.length() <= 0) return false
            val safeName = name.replace(Regex("[^A-Za-z0-9._ -]"), "_").take(80).ifBlank { "juzzio_${System.currentTimeMillis()}" }
            val safeMime = if (Regex("^[a-z]+/[a-z0-9.+-]+$").matches(mime)) mime else "application/octet-stream"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val (collection, rel) = when (kind) {
                    "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_PICTURES}/Juzzio"
                    "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_MOVIES}/Juzzio"
                    else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_DOWNLOADS}/Juzzio"
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, safeMime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, rel)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = ctx.contentResolver
                val uri = resolver.insert(collection, values) ?: return false
                try {
                    resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } } ?: run {
                        resolver.delete(uri, null, null)
                        return false
                    }
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                    true
                } catch (e: Exception) {
                    try { resolver.delete(uri, null, null) } catch (_: Exception) {}
                    false
                }
            } else {
                @Suppress("DEPRECATION")
                val base = Environment.getExternalStoragePublicDirectory(
                    when (kind) {
                        "image" -> Environment.DIRECTORY_PICTURES
                        "video" -> Environment.DIRECTORY_MOVIES
                        else -> Environment.DIRECTORY_DOWNLOADS
                    }
                )
                val dir = File(base, "Juzzio")
                if (!dir.exists() && !dir.mkdirs()) return false
                val dst = File(dir, safeName)
                src.inputStream().use { input -> dst.outputStream().use { input.copyTo(it) } }
                MediaScannerConnection.scanFile(ctx, arrayOf(dst.absolutePath), arrayOf(safeMime), null)
                true
            }
        } catch (_: Exception) {
            false
        }
    }
}
