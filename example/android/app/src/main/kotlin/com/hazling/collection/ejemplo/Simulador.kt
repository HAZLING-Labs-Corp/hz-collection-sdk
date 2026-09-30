package com.hazling.collection.ejemplo

import android.content.Context
import android.content.pm.ApplicationInfo
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * EL SIMULADOR DE RECORRIDOS — inyecta una ruta como si fuera el GPS del teléfono.
 *
 * Usa los PROVEEDORES DE PRUEBA de Android (`addTestProvider`) sobre GPS y red: el sistema
 * entrega esas ubicaciones a TODO el que escuche —el proveedor fusionado incluido—, así que
 * la captura del SDK las recibe por el camino real (geolocator → detector → cola → lote), y
 * con `isMock = true`, que es justo lo que el lote tiene que decir de ellas.
 *
 * Requisitos, y sin ellos el simulador lo dice en vez de fallar callado:
 *   · compilación de depuración (en release no hace nada);
 *   · la app elegida como «app de ubicación simulada»:
 *       adb shell appops set <paquete> android:mock_location allow
 */
class Simulador(private val contexto: Context, mensajero: BinaryMessenger) {
    private val canal = MethodChannel(mensajero, "ejemplo/simulador")
    private val lm = contexto.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val hilo = Handler(Looper.getMainLooper())
    private var corriendo = false
    private var indice = 0
    private var total = 0

    private val proveedores = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)

    init {
        canal.setMethodCallHandler { llamada, resultado ->
            when (llamada.method) {
                "iniciar" -> {
                    @Suppress("UNCHECKED_CAST")
                    val puntos = llamada.argument<List<List<Double>>>("puntos") ?: emptyList()
                    val cadaMs = llamada.argument<Int>("cadaMs") ?: 1000
                    resultado.success(iniciar(puntos, cadaMs.toLong()))
                }
                "detener" -> { detener(); resultado.success(null) }
                "estado" -> resultado.success(mapOf("corriendo" to corriendo, "indice" to indice, "total" to total))
                else -> resultado.notImplemented()
            }
        }
    }

    /** Devuelve `null` si arrancó, o por qué no. Cada punto: [lat, lon, velocidad m/s, rumbo]. */
    private fun iniciar(puntos: List<List<Double>>, cadaMs: Long): String? {
        if (contexto.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            return "el simulador sólo anda en una compilación de depuración"
        }
        detener()
        try {
            for (p in proveedores) {
                try { lm.removeTestProvider(p) } catch (_: Exception) {}
                if (Build.VERSION.SDK_INT >= 31) {
                    lm.addTestProvider(p, false, false, false, false, true, true, true,
                        ProviderProperties.POWER_USAGE_LOW, ProviderProperties.ACCURACY_FINE)
                } else {
                    @Suppress("DEPRECATION")
                    lm.addTestProvider(p, false, false, false, false, true, true, true, 1, 1)
                }
                lm.setTestProviderEnabled(p, true)
            }
        } catch (e: SecurityException) {
            return "falta elegir esta app como ubicación simulada: " +
                "adb shell appops set ${contexto.packageName} android:mock_location allow"
        }
        corriendo = true
        indice = 0
        total = puntos.size
        val paso = object : Runnable {
            override fun run() {
                if (!corriendo) return
                if (indice >= puntos.size) { detener(); return }
                val p = puntos[indice++]
                for (prov in proveedores) {
                    val l = Location(prov).apply {
                        latitude = p[0]; longitude = p[1]
                        speed = p[2].toFloat(); bearing = p[3].toFloat()
                        accuracy = if (prov == LocationManager.GPS_PROVIDER) 4f else 30f
                        altitude = 900.0
                        time = System.currentTimeMillis()
                        elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                    }
                    try { lm.setTestProviderLocation(prov, l) } catch (_: Exception) {}
                }
                hilo.postDelayed(this, cadaMs)
            }
        }
        hilo.post(paso)
        return null
    }

    fun detener() {
        corriendo = false
        hilo.removeCallbacksAndMessages(null)
        for (p in proveedores) {
            try { lm.removeTestProvider(p) } catch (_: Exception) {}
        }
    }
}
