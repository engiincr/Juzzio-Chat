package com.juzzio.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.EventChannel

/**
 * v1.2.8 — Yedek canlı altyazı motoru (cihazın kendi konuşma tanıyıcısı).
 * Deepgram'a ulaşılamadığında (sunucu anahtarı yok, ağ sorunu) Dart tarafı bunu başlatır.
 * Sürekli dinler: her sonuçtan/hatadan sonra kısa bir beklemeyle yeniden başlar.
 * Olaylar EventChannel ile gider: {type: partial|final|error|state, text, code}
 */
class JuzzioSpeech(private val context: Context) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var lang = "tr-TR"

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun emit(map: Map<String, Any?>) {
        main.post { try { sink?.success(map) } catch (_: Exception) {} }
    }

    fun available(): Boolean = try { SpeechRecognizer.isRecognitionAvailable(context) } catch (_: Exception) { false }

    fun start(language: String) {
        lang = toTag(language)
        running = true
        main.post { listen() }
    }

    fun stop() {
        running = false
        main.post {
            try { recognizer?.cancel() } catch (_: Exception) {}
            try { recognizer?.destroy() } catch (_: Exception) {}
            recognizer = null
        }
    }

    private fun toTag(l: String): String {
        val b = l.lowercase().take(2)
        return when (b) {
            "tr" -> "tr-TR"; "en" -> "en-US"; "de" -> "de-DE"; "es" -> "es-ES"; "fr" -> "fr-FR"
            "it" -> "it-IT"; "pt" -> "pt-BR"; "ru" -> "ru-RU"; "ar" -> "ar-SA"; "ja" -> "ja-JP"
            "ko" -> "ko-KR"; "zh" -> "zh-CN"; "nl" -> "nl-NL"; "hi" -> "hi-IN"; "uk" -> "uk-UA"
            "pl" -> "pl-PL"; "az" -> "az-AZ"; "fa" -> "fa-IR"
            else -> l
        }
    }

    private fun restartSoon(delayMs: Long) {
        if (!running) return
        main.postDelayed({ if (running) listen() }, delayMs)
    }

    private fun listen() {
        if (!running) return
        if (!available()) {
            emit(mapOf("type" to "error", "code" to "unavailable"))
            running = false
            return
        }
        try {
            if (recognizer == null) {
                recognizer = SpeechRecognizer.createSpeechRecognizer(context)
                recognizer?.setRecognitionListener(listener)
            }
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 900L)
            }
            recognizer?.startListening(intent)
            emit(mapOf("type" to "state", "text" to "listening"))
        } catch (e: Exception) {
            emit(mapOf("type" to "error", "code" to "start_failed"))
            restartSoon(1500)
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onPartialResults(partialResults: Bundle?) {
            val t = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim() ?: ""
            if (t.isNotEmpty()) emit(mapOf("type" to "partial", "text" to t))
        }

        override fun onResults(results: Bundle?) {
            val t = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim() ?: ""
            if (t.isNotEmpty()) emit(mapOf("type" to "final", "text" to t))
            restartSoon(150)
        }

        override fun onError(error: Int) {
            // sessizlik / eşleşme yok normaldir → hemen yeniden dinle
            val quiet = error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            if (!quiet) emit(mapOf("type" to "error", "code" to "e$error"))
            if (error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY || error == SpeechRecognizer.ERROR_CLIENT) {
                try { recognizer?.destroy() } catch (_: Exception) {}
                recognizer = null
                restartSoon(900)
            } else if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                running = false
            } else {
                restartSoon(if (quiet) 100 else 1200)
            }
        }
    }
}
