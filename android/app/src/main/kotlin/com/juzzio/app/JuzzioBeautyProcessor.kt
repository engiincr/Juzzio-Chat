package com.juzzio.app

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Görüntülü aramada gerçek zamanlı güzelleştirme (karşı tarafa giden görüntüye uygulanır).
 * v0.5.0: Tek dokunuşla açılıp kapanan, BULANIKLAŞTIRMAYAN doğal mod.
 *  • Yalnızca küçük parlaklık farkları (cilt dokusu, gözenek) yumuşatılır; ağırlık
 *    fark büyüdükçe doğrusal olarak sıfıra iner (bilateral benzeri aralık ağırlığı).
 *    Böylece gözler, kaşlar, saç ve yüz hatları tamamen keskin kalır.
 *  • Yarıçap 2 piksel ile sınırlıdır; görüntü "flu" görünmez.
 *  • Gölgelerde çok hafif aydınlatma ve doğal sıcak ton.
 * Kamera iş parçacığında çalışır; 0 = kapalı, >0 = açık (eski 1-3 seviyeleri aynı doğal moda eşlenir).
 */
object JuzzioBeautyProcessor : LocalVideoTrack.ExternalVideoFrameProcessing {

    @Volatile
    private var level: Int = 0

    private var attachedTrackId: String? = null
    private var attachedTrack: LocalVideoTrack? = null

    private var yIn = ByteArray(0)
    private var tmp = IntArray(0)
    private var blur = IntArray(0)
    private val lut = IntArray(256)
    private var lutLevel = -1

    /** Seviyeyi ayarlar ve verilen yerel video izine bağlanır. Başarılıysa true. */
    @Synchronized
    fun apply(trackId: String?, newLevel: Int): Boolean {
        level = newLevel.coerceIn(0, 3)
        if (trackId.isNullOrBlank()) return false
        if (attachedTrackId != trackId) {
            detach()
            val plugin = FlutterWebRTCPlugin.sharedSingleton ?: return false
            val track = plugin.getLocalTrack(trackId) as? LocalVideoTrack ?: return false
            track.addProcessor(this)
            attachedTrack = track
            attachedTrackId = trackId
        }
        return true
    }

    @Synchronized
    fun detach() {
        try {
            attachedTrack?.removeProcessor(this)
        } catch (_: Exception) {
        }
        attachedTrack = null
        attachedTrackId = null
    }

    private fun buildLut(lv: Int) {
        if (lutLevel == lv) return
        val lift = 7
        for (i in 0..255) {
            // Gölgeleri biraz aydınlat, parlak alanları patlatma
            val boost = lift * (255 - i) / 255
            lut[i] = min(255, i + boost)
        }
        lutLevel = lv
    }

    override fun onFrame(frame: VideoFrame): VideoFrame {
        val lv = level
        if (lv <= 0) return frame
        var converted: VideoFrame.I420Buffer? = null
        try {
            converted = frame.buffer.toI420()
        } catch (_: Exception) {
        }
        val i420 = converted ?: return frame
        try {
            val w = i420.width
            val h = i420.height
            if (w < 16 || h < 16) return frame
            // Doğal mod: küçük yarıçap, orta güç, düşük eşik (bulanıklık yok)
            val radius = 2
            val alpha = 120 // en fazla ~%47 yumuşatma, yalnızca çok küçük farklarda
            val threshold = 12
            buildLut(1)

            val size = w * h
            if (yIn.size < size) {
                yIn = ByteArray(size)
                tmp = IntArray(size)
                blur = IntArray(size)
            }

            // Y düzlemini sıkı (stride'sız) diziye kopyala
            val srcY = i420.dataY.duplicate()
            val strideY = i420.strideY
            for (row in 0 until h) {
                srcY.position(row * strideY)
                srcY.get(yIn, row * w, w)
            }

            // Yatay kutu bulanıklığı (kayan pencere)
            val win = radius * 2 + 1
            for (row in 0 until h) {
                val base = row * w
                var sum = 0
                for (k in -radius..radius) {
                    sum += yIn[base + k.coerceIn(0, w - 1)].toInt() and 0xFF
                }
                for (x in 0 until w) {
                    tmp[base + x] = sum
                    val outIdx = (x - radius).coerceIn(0, w - 1)
                    val inIdx = (x + radius + 1).coerceIn(0, w - 1)
                    sum += (yIn[base + inIdx].toInt() and 0xFF) - (yIn[base + outIdx].toInt() and 0xFF)
                }
            }
            // Dikey kutu bulanıklığı
            val area = win * win
            for (x in 0 until w) {
                var sum = 0
                for (k in -radius..radius) {
                    sum += tmp[k.coerceIn(0, h - 1) * w + x]
                }
                for (row in 0 until h) {
                    blur[row * w + x] = sum / area
                    val outRow = (row - radius).coerceIn(0, h - 1)
                    val inRow = (row + radius + 1).coerceIn(0, h - 1)
                    sum += tmp[inRow * w + x] - tmp[outRow * w + x]
                }
            }

            val out = JavaI420Buffer.allocate(w, h)
            val dstY = out.dataY
            val dstStrideY = out.strideY
            val rowBuf = ByteArray(w)
            for (row in 0 until h) {
                val base = row * w
                for (x in 0 until w) {
                    val y = yIn[base + x].toInt() and 0xFF
                    val d = blur[base + x] - y
                    // Aralık ağırlığı: fark büyüdükçe yumuşatma doğrusal olarak sıfıra iner;
                    // eşik üstündeki farklar (kenar/detay) hiç değiştirilmez.
                    val ad = abs(d)
                    val smoothed = if (ad < threshold) {
                        val w8 = alpha * (threshold - ad) / threshold
                        y + (d * w8 shr 8)
                    } else {
                        y
                    }
                    rowBuf[x] = lut[max(0, min(255, smoothed))].toByte()
                }
                dstY.position(row * dstStrideY)
                dstY.put(rowBuf, 0, w)
            }

            // Renk düzlemleri: hafif sıcak ton (cilt rengini canlandırır)
            val cw = (w + 1) / 2
            val ch = (h + 1) / 2
            val warmU = -1
            val warmV = 1
            copyPlane(i420.dataU.duplicate(), i420.strideU, out.dataU, out.strideU, cw, ch, warmU)
            copyPlane(i420.dataV.duplicate(), i420.strideV, out.dataV, out.strideV, cw, ch, warmV)

            return VideoFrame(out, frame.rotation, frame.timestampNs)
        } catch (_: Exception) {
            return frame
        } finally {
            i420.release()
        }
    }

    private fun copyPlane(
        src: java.nio.ByteBuffer,
        srcStride: Int,
        dst: java.nio.ByteBuffer,
        dstStride: Int,
        width: Int,
        height: Int,
        shift: Int,
    ) {
        val row = ByteArray(width)
        for (r in 0 until height) {
            src.position(r * srcStride)
            src.get(row, 0, width)
            if (shift != 0) {
                for (i in 0 until width) {
                    row[i] = max(0, min(255, (row[i].toInt() and 0xFF) + shift)).toByte()
                }
            }
            dst.position(r * dstStride)
            dst.put(row, 0, width)
        }
    }
}
