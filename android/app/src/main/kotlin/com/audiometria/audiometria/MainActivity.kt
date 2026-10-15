package com.audiometria.audiometria

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val hiloPython = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())
    private val tonos = GeneradorTonos()
    private lateinit var audio: AudioManager
    private var observadorAudifonos: AudioDeviceCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val mensajero = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(mensajero, "audiometria/audio").setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "audifonos" -> resultado.success(audifonosConectados())
                "volumen" -> resultado.success(estadoVolumen())
                "fijarVolumen" -> {
                    val nivel = llamada.argument<Int>("nivel")!!
                    val mostrar = llamada.argument<Boolean>("mostrar") ?: false
                    if (audio.getStreamVolume(AudioManager.STREAM_MUSIC) != nivel) {
                        audio.setStreamVolume(
                            AudioManager.STREAM_MUSIC, nivel,
                            if (mostrar) AudioManager.FLAG_SHOW_UI else 0
                        )
                    }
                    resultado.success(estadoVolumen())
                }
                "tono" -> {
                    tonos.reproducir(
                        llamada.argument<Double>("frecuencia")!!,
                        llamada.argument<Double>("dbfs")!!,
                        llamada.argument<String>("oido")!!,
                        llamada.argument<Int>("duracionMs")!!
                    )
                    resultado.success(null)
                }
                "detener" -> {
                    tonos.detener()
                    resultado.success(null)
                }
                else -> resultado.notImplemented()
            }
        }

        EventChannel(mensajero, "audiometria/audifonos").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(argumentos: Any?, eventos: EventChannel.EventSink) {
                observadorAudifonos?.let { audio.unregisterAudioDeviceCallback(it) }
                val observador = object : AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(agregados: Array<out AudioDeviceInfo>) {
                        eventos.success(audifonosConectados())
                    }

                    override fun onAudioDevicesRemoved(quitados: Array<out AudioDeviceInfo>) {
                        eventos.success(audifonosConectados())
                    }
                }
                observadorAudifonos = observador
                audio.registerAudioDeviceCallback(observador, principal)
                eventos.success(audifonosConectados())
            }

            override fun onCancel(argumentos: Any?) {
                observadorAudifonos?.let { audio.unregisterAudioDeviceCallback(it) }
                observadorAudifonos = null
            }
        })

        MethodChannel(mensajero, "audiometria/python").setMethodCallHandler { llamada, resultado ->
            val modulo = llamada.argument<String>("modulo")!!
            val funcion = llamada.argument<String>("funcion")!!
            val datos = llamada.argument<String>("datos") ?: "null"
            // Python corre en un hilo aparte para no congelar la interfaz.
            hiloPython.execute {
                try {
                    if (!Python.isStarted()) Python.start(AndroidPlatform(applicationContext))
                    val respuesta = Python.getInstance().getModule("puente")
                        .callAttr("llamar", modulo, funcion, datos).toString()
                    principal.post { resultado.success(respuesta) }
                } catch (e: Exception) {
                    principal.post { resultado.error("PYTHON", e.message, null) }
                }
            }
        }

        MethodChannel(mensajero, "audiometria/sistema").setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "directorio" -> resultado.success(filesDir.absolutePath)
                "compartir", "abrir" -> {
                    val archivo = File(llamada.argument<String>("ruta")!!)
                    val tipo = llamada.argument<String>("tipo") ?: "application/octet-stream"
                    val uri = FileProvider.getUriForFile(this, "$packageName.archivos", archivo)
                    val intencion = if (llamada.method == "compartir") {
                        Intent.createChooser(
                            Intent(Intent.ACTION_SEND).apply {
                                type = tipo
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            },
                            "Compartir"
                        )
                    } else {
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, tipo)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    try {
                        startActivity(intencion)
                        resultado.success(true)
                    } catch (e: ActivityNotFoundException) {
                        resultado.error("SIN_APP", "No hay una aplicación para abrir este archivo", null)
                    }
                }
                else -> resultado.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tonos.detener()
        observadorAudifonos?.let { audio.unregisterAudioDeviceCallback(it) }
        super.onDestroy()
    }

    private fun estadoVolumen(): Map<String, Int> = mapOf(
        "actual" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
        "maximo" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
    )

    /** Solo cuentan como audífonos las salidas que van a los oídos. */
    private fun audifonosConectados(): List<Map<String, String>> {
        val tipos = mutableMapOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES to "cable",
            AudioDeviceInfo.TYPE_WIRED_HEADSET to "cable",
            AudioDeviceInfo.TYPE_USB_HEADSET to "usb",
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP to "bluetooth",
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            tipos[AudioDeviceInfo.TYPE_BLE_HEADSET] = "bluetooth"
        }
        return audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.type in tipos }
            .map {
                mapOf(
                    "nombre" to (it.productName?.toString()?.takeIf { n -> n.isNotBlank() } ?: "Audífonos"),
                    "tipo" to tipos.getValue(it.type),
                )
            }
            .distinct()
    }
}
