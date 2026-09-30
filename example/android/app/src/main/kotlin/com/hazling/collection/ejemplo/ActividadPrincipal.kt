package com.hazling.collection.ejemplo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * La actividad de la app de EJEMPLO. Es FlutterActivity más un canal: el del simulador de
 * recorridos (`ejemplo/simulador`), que sólo existe para probar el rastreo en el emulador
 * sin salir a la calle.
 *
 * Va en un paquete fijo (`com.hazling.collection.ejemplo`) y se nombra completo en el
 * manifiesto: así el identificador de la aplicación se sigue pudiendo cambiar al compilar
 * (`-Ppaquete=…`) sin tocar este archivo.
 */
class ActividadPrincipal : FlutterActivity() {
    private var simulador: Simulador? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        simulador = Simulador(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        simulador?.detener()
        simulador = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
