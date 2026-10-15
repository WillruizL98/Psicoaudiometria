package com.audiometria.audiometria

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Genera tonos puros estéreo con rampas de entrada/salida (sin "clics")
 * y los envía a un solo oído.
 */
class GeneradorTonos {
    private val frecuenciaMuestreo = 48_000
    private val duracionRampaS = 0.025
    private var pista: AudioTrack? = null
    private val manejador = Handler(Looper.getMainLooper())

    /** @param oido "D" (derecho), "I" (izquierdo) o "A" (ambos). */
    @Synchronized
    fun reproducir(frecuencia: Double, dbfs: Double, oido: String, duracionMs: Int) {
        detener()
        val muestras = frecuenciaMuestreo * duracionMs / 1000
        val rampa = (duracionRampaS * frecuenciaMuestreo).toInt().coerceAtMost(muestras / 2)
        val amplitud = 10.0.pow(dbfs / 20.0).coerceAtMost(1.0)
        val izquierdo = oido == "I" || oido == "A"
        val derecho = oido == "D" || oido == "A"

        val datos = FloatArray(muestras * 2)
        for (i in 0 until muestras) {
            val envolvente = when {
                i < rampa -> 0.5 * (1 - cos(PI * i / rampa))
                i >= muestras - rampa -> 0.5 * (1 - cos(PI * (muestras - 1 - i) / rampa))
                else -> 1.0
            }
            val valor = (amplitud * envolvente * sin(2 * PI * frecuencia * i / frecuenciaMuestreo)).toFloat()
            datos[2 * i] = if (izquierdo) valor else 0f
            datos[2 * i + 1] = if (derecho) valor else 0f
        }

        val nueva = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(frecuenciaMuestreo)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(datos.size * 4)
            .build()
        nueva.write(datos, 0, datos.size, AudioTrack.WRITE_BLOCKING)
        nueva.play()
        pista = nueva
        manejador.postDelayed({ liberar(nueva) }, duracionMs + 300L)
    }

    @Synchronized
    fun detener() {
        manejador.removeCallbacksAndMessages(null)
        pista?.let { liberar(it) }
    }

    @Synchronized
    private fun liberar(p: AudioTrack) {
        try {
            p.stop()
        } catch (_: IllegalStateException) {
        }
        p.release()
        if (pista === p) pista = null
    }
}
