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
 * Kamera iş parçacığında çalışır.
 * v0.9.3: yoğunluk 0..100 (0 = kapalı); parametre eşlemesi lib/services/juzzio_beauty.dart ile birebir aynı.
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
        level = newLevel.coerceIn(0, 100)
        if (trackId.isNullOrBlank()) return false
        if (attachedTrackId != trackId) {
            detach()
            val plugin = FlutterWebRTCPlugin.sharedSingleton ?: return false
            val track = plugin.getLocalTrack(trackId) as? LocalVideoTrack ?: return false
            track.addProcessor(this)
            attachedTrack = track
            attachedTrackId = trackId
            resetLoadGuard()
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
        val lift = (lv * 12) / 100
        for (i in 0..255) {
            // Gölgeleri biraz aydınlat, parlak alanları patlatma
            val boost = lift * (255 - i) / 255
            lut[i] = min(255, i + boost)
        }
        lutLevel = lv
    }

    // v1.2.9 başarım: görüntülü aramada GİDEN görüntünün donması düzeltildi.
    // Önceden her kare tam çözünürlükte (720p) GPU'dan okunup 3 geçişte işleniyor ve her kare için
    // yeni 1,4 MB'lık bellek ayrılıyordu; orta seviye telefonlarda kare başına 40–90 ms sürüyor,
    // kamera iş parçacığı tıkanıyor, karşı tarafa giden görüntü sürekli donuyordu.
    // Şimdi: (1) işleme en fazla [maxWidth] genişlikte yapılır (ölçekleme GPU'da, ucuz),
    // (2) çıkış tamponları havuzdan yeniden kullanılır, (3) iç döngülerde sınır kontrolü yok,
    // (4) süre bütçesi aşılırsa önce çözünürlük düşer, yine aşılırsa güzelleştirme bu arama için
    // kendiliğinden devre dışı kalır — görüntü akıcılığı her zaman önceliklidir.
    // v2.1: 60 fps için kare bütçesi 16,6 ms; işleme 9 ms'yi aşarsa önce çözünürlük düşer, sonra filtre kapanır
    private const val BUDGET_NS = 9_000_000L
    @Volatile private var maxWidth = 960
    @Volatile var overloaded = false
        private set
    private var avgNs = 0L
    private var frames = 0

    @Synchronized
    fun resetLoadGuard() {
        maxWidth = 960; overloaded = false; avgNs = 0L; frames = 0
    }

    private class Slot(val y: java.nio.ByteBuffer, val u: java.nio.ByteBuffer, val v: java.nio.ByteBuffer, val w: Int, val h: Int) {
        @Volatile var busy = false
    }
    private val pool = ArrayList<Slot>()

    private fun obtain(w: Int, h: Int): Slot {
        synchronized(pool) {
            for (sl in pool) if (!sl.busy && sl.w == w && sl.h == h) { sl.busy = true; return sl }
            if (pool.size >= 4) pool.removeAll { !it.busy }
            val cw = (w + 1) / 2
            val ch = (h + 1) / 2
            val sl = Slot(
                java.nio.ByteBuffer.allocateDirect(w * h),
                java.nio.ByteBuffer.allocateDirect(cw * ch),
                java.nio.ByteBuffer.allocateDirect(cw * ch), w, h,
            )
            sl.busy = true
            pool.add(sl)
            return sl
        }
    }

    override fun onFrame(frame: VideoFrame): VideoFrame {
        val lv = level
        if (lv <= 0 || overloaded) return frame
        val t0 = System.nanoTime()
        val srcW = frame.buffer.width
        val srcH = frame.buffer.height
        if (srcW < 16 || srcH < 16) return frame
        var tw = srcW
        var th = srcH
        if (srcW > maxWidth) {
            tw = maxWidth and 1.inv()
            th = ((srcH.toLong() * tw / srcW).toInt()) and 1.inv()
        }
        var scaled: VideoFrame.Buffer? = null
        var converted: VideoFrame.I420Buffer? = null
        try {
            val src = if (tw != srcW) frame.buffer.cropAndScale(0, 0, srcW, srcH, tw, th).also { scaled = it } else frame.buffer
            converted = src.toI420()
        } catch (_: Exception) {
        }
        scaled?.release()
        val i420 = converted ?: return frame
        var slotUsed: Slot? = null
        try {
            val w = i420.width
            val h = i420.height
            val radius = if (lv > 65) 3 else 2
            val alpha = min(240, 40 + lv * 2)
            val threshold = 6 + (lv * 16) / 100
            buildLut(lv)

            val size = w * h
            if (yIn.size < size) {
                yIn = ByteArray(size)
                tmp = IntArray(size)
                blur = IntArray(size)
            }
            val srcY = i420.dataY.duplicate()
            val strideY = i420.strideY
            for (row in 0 until h) {
                srcY.position(row * strideY)
                srcY.get(yIn, row * w, w)
            }

            // Yatay kutu bulanıklığı — kenarlarda sınır, içte düz döngü
            val win = radius * 2 + 1
            val wLast = w - 1
            for (row in 0 until h) {
                val base = row * w
                var sum = 0
                for (k in -radius..radius) sum += yIn[base + min(wLast, max(0, k))].toInt() and 0xFF
                var x = 0
                while (x < w) {
                    tmp[base + x] = sum
                    val outIdx = if (x >= radius) x - radius else 0
                    val inIdx = if (x + radius + 1 <= wLast) x + radius + 1 else wLast
                    sum += (yIn[base + inIdx].toInt() and 0xFF) - (yIn[base + outIdx].toInt() and 0xFF)
                    x++
                }
            }
            // Dikey kutu bulanıklığı — satır sırasıyla (önbellek dostu)
            val area = win * win
            val hLast = h - 1
            val colSum = IntArray(w)
            for (k in -radius..radius) {
                val r = min(hLast, max(0, k)) * w
                for (x in 0 until w) colSum[x] += tmp[r + x]
            }
            for (row in 0 until h) {
                val base = row * w
                val outRow = (if (row >= radius) row - radius else 0) * w
                val inRow = (if (row + radius + 1 <= hLast) row + radius + 1 else hLast) * w
                for (x in 0 until w) {
                    blur[base + x] = colSum[x] / area
                    colSum[x] += tmp[inRow + x] - tmp[outRow + x]
                }
            }

            val slot = obtain(w, h)
            slotUsed = slot
            val cw = (w + 1) / 2
            val ch = (h + 1) / 2
            val dstY = slot.y
            dstY.clear()
            val rowBuf = ByteArray(w)
            for (row in 0 until h) {
                val base = row * w
                for (x in 0 until w) {
                    val y = yIn[base + x].toInt() and 0xFF
                    val d = blur[base + x] - y
                    val ad = if (d < 0) -d else d
                    val smoothed = if (ad < threshold) y + (d * (alpha * (threshold - ad) / threshold) shr 8) else y
                    rowBuf[x] = lut[if (smoothed < 0) 0 else if (smoothed > 255) 255 else smoothed].toByte()
                }
                dstY.position(base)
                dstY.put(rowBuf, 0, w)
            }
            val warmU = if (lv >= 30) -1 else 0
            val warmV = if (lv >= 30) 1 else 0
            slot.u.clear(); slot.v.clear()
            copyPlane(i420.dataU.duplicate(), i420.strideU, slot.u, cw, cw, ch, warmU)
            copyPlane(i420.dataV.duplicate(), i420.strideV, slot.v, cw, cw, ch, warmV)
            dstY.rewind(); slot.u.rewind(); slot.v.rewind()

            val out = JavaI420Buffer.wrap(w, h, dstY, w, slot.u, cw, slot.v, cw) { slot.busy = false }
            slotUsed = null
            guard(System.nanoTime() - t0)
            return VideoFrame(out, frame.rotation, frame.timestampNs)
        } catch (_: Exception) {
            slotUsed?.busy = false
            return frame
        } finally {
            i420.release()
        }
    }

    /** Süre bütçesi: ortalama kare süresi bütçeyi aşarsa önce 640 genişliğe, sonra kapat. */
    private fun guard(ns: Long) {
        avgNs = if (frames == 0) ns else (avgNs * 7 + ns) / 8
        frames++
        if (frames < 20 || avgNs <= BUDGET_NS) return
        if (maxWidth > 640) {
            maxWidth = 640; frames = 0
        } else {
            overloaded = true
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
