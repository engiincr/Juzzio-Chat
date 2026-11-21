package com.juzzio.app

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * v2.1 — arama ses çıkışı yönlendirmesi.
 *
 * Kurallar (kullanıcı isteği):
 *  - Kulaklık (kablolu / USB / Bluetooth) bağlıysa ses otomatik ona gider.
 *  - Kulaklık arama sırasında çıkarılırsa ses HOPARLÖRE DEĞİL telefonun ahizesine (kulak) döner;
 *    kullanıcı isterse hoparlörü elle açar.
 *  - Kullanıcı seçici ile ahize / hoparlör / kablolu / Bluetooth arasında geçiş yapabilir.
 */
class JuzzioAudioRoute(context: Context) : EventChannel.StreamHandler {
    private val am = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: AudioDeviceCallback? = null
    private var active = false
    private var current = ROUTE_EARPIECE

    companion object {
        const val ROUTE_EARPIECE = "earpiece"
        const val ROUTE_SPEAKER = "speaker"
        const val ROUTE_WIRED = "wired"
        const val ROUTE_BLUETOOTH = "bluetooth"
    }

    private fun typeToRoute(t: Int): String? = when (t) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> ROUTE_EARPIECE
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> ROUTE_SPEAKER
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET -> ROUTE_WIRED
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> ROUTE_BLUETOOTH
        else -> if (Build.VERSION.SDK_INT >= 31 && t == AudioDeviceInfo.TYPE_BLE_HEADSET) ROUTE_BLUETOOTH else null
    }

    private fun outputs(): List<AudioDeviceInfo> = try {
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
    } catch (_: Exception) {
        emptyList()
    }

    /** Kullanılabilir çıkışlar: ahize + hoparlör her zaman; kulaklık/Bluetooth bağlıysa onlar da. */
    fun available(): List<String> {
        val set = linkedSetOf(ROUTE_EARPIECE, ROUTE_SPEAKER)
        for (d in outputs()) {
            val r = typeToRoute(d.type) ?: continue
            set.add(r)
        }
        // A2DP tek başına görüşme sesi taşımaz; ama SCO profili olan kulaklık A2DP ile birlikte görünür
        if (!set.contains(ROUTE_BLUETOOTH) && outputs().any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }) {
            set.add(ROUTE_BLUETOOTH)
        }
        return set.toList()
    }

    private fun bluetoothName(): String? = outputs().firstOrNull {
        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
    }?.productName?.toString()

    fun state(): Map<String, Any?> = mapOf(
        "current" to current,
        "available" to available(),
        "bluetoothName" to bluetoothName(),
    )

    /** Kulaklık varsa ona, yoksa tercih edilen (görüntülüde hoparlör, sesli aramada ahize). */
    private fun autoRoute(preferSpeaker: Boolean): String {
        val av = available()
        return when {
            av.contains(ROUTE_BLUETOOTH) -> ROUTE_BLUETOOTH
            av.contains(ROUTE_WIRED) -> ROUTE_WIRED
            preferSpeaker -> ROUTE_SPEAKER
            else -> ROUTE_EARPIECE
        }
    }

    fun start(preferSpeaker: Boolean): Map<String, Any?> {
        active = true
        if (callback == null) {
            val cb = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                    if (!active) return
                    val headset = addedDevices.mapNotNull { typeToRoute(it.type) }
                        .firstOrNull { it == ROUTE_WIRED || it == ROUTE_BLUETOOTH }
                    // Kulaklık takıldı → ses otomatik kulaklığa
                    if (headset != null) apply(headset) else emit()
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                    if (!active) return
                    val removed = removedDevices.mapNotNull { typeToRoute(it.type) }
                    if (removed.contains(current) || (current == ROUTE_BLUETOOTH && removedDevices.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP })) {
                        // Kulaklık çıkarıldı → hoparlör değil, AHİZE
                        val av = available()
                        apply(
                            when {
                                av.contains(ROUTE_BLUETOOTH) && current != ROUTE_BLUETOOTH -> ROUTE_BLUETOOTH
                                av.contains(ROUTE_WIRED) && current != ROUTE_WIRED -> ROUTE_WIRED
                                else -> ROUTE_EARPIECE
                            }
                        )
                    } else {
                        emit()
                    }
                }
            }
            callback = cb
            try { am.registerAudioDeviceCallback(cb, main) } catch (_: Exception) {}
        }
        apply(autoRoute(preferSpeaker))
        return state()
    }

    @Suppress("DEPRECATION")
    fun stop() {
        active = false
        callback?.let { try { am.unregisterAudioDeviceCallback(it) } catch (_: Exception) {} }
        callback = null
        try {
            if (Build.VERSION.SDK_INT >= 31) am.clearCommunicationDevice()
            if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }
            am.isSpeakerphoneOn = false
        } catch (_: Exception) {}
    }

    @Suppress("DEPRECATION")
    fun apply(route: String): Map<String, Any?> {
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val wantTypes = when (route) {
                    ROUTE_SPEAKER -> listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                    ROUTE_WIRED -> listOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET)
                    ROUTE_BLUETOOTH -> listOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET)
                    else -> listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
                }
                val dev = am.availableCommunicationDevices.firstOrNull { wantTypes.contains(it.type) }
                if (dev != null) {
                    am.setCommunicationDevice(dev)
                    current = route
                } else if (route == ROUTE_EARPIECE) {
                    am.clearCommunicationDevice()
                    current = ROUTE_EARPIECE
                }
            } else {
                    when (route) {
                    ROUTE_SPEAKER -> {
                        if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }
                        am.isSpeakerphoneOn = true
                    }
                    ROUTE_BLUETOOTH -> {
                        am.isSpeakerphoneOn = false
                        am.startBluetoothSco()
                        am.isBluetoothScoOn = true
                    }
                    else -> {
                        // Ahize ve kablolu kulaklık: hoparlör kapalıyken sistem takılı kulaklığı seçer
                        if (am.isBluetoothScoOn) { am.stopBluetoothSco(); am.isBluetoothScoOn = false }
                        am.isSpeakerphoneOn = false
                    }
                }
                current = route
            }
        } catch (_: Exception) {}
        emit()
        return state()
    }

    private fun emit() {
        val s = state()
        main.post { try { sink?.success(s) } catch (_: Exception) {} }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        emit()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
