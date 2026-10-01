package com.hazling.collection

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * EL LADO NATIVO DEL RASTREO EN ANDROID — canal `hz_collection_sdk/rastreo`.
 *
 * Cuatro cosas y nada más: la clave ES256 del aparato, los relojes, la energía y el
 * reconocimiento de actividad.
 *
 * 🔴 SIGUE SIN DECLARAR NINGÚN PERMISO. `ACTIVITY_RECOGNITION` (Android 10+) lo declara la
 * APLICACIÓN si quiere la actividad; si no lo declara, la actividad no arranca y el detector
 * sigue con la salida de zona y la velocidad. El manifiesto del paquete sigue vacío.
 *
 * 🔴 PLAY SERVICES VA COMO `compileOnly`. El reconocimiento de actividad es de
 * `play-services-location`, que YA viene en el APK por `geolocator_android` (una dependencia
 * firme del SDK). Declararla `implementation` acá no agregaría un byte, pero sería una
 * dependencia más que auditar; `compileOnly` usa la que ya está. Si algún día no estuviera,
 * se atrapa el `NoClassDefFoundError` y la actividad se da por no disponible.
 */
private const val ETIQUETA = "HzRastreoHilo"

class RastreoNativo(
    private val contexto: Context,
    mensajero: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private val canal = MethodChannel(mensajero, "hz_collection_sdk/rastreo")
    private val eventos = EventChannel(mensajero, "hz_collection_sdk/rastreo/actividad")

    var actividad: Activity? = null
    private var permisoPendiente: MethodChannel.Result? = null
    private var sumidero: EventChannel.EventSink? = null
    private var receptor: BroadcastReceiver? = null
    private var intencion: PendingIntent? = null

    /**
     * 🔴 LA CLAVE NO SE TOCA EN EL HILO PRINCIPAL. `MethodChannel` entrega en el hilo
     * principal de Android, que desde Flutter 3.29 es TAMBIÉN el hilo del isolate de Dart
     * (hilos fusionados). El AndroidKeyStore es IPC con `keystore2` —y con StrongBox, con un
     * chip aparte—: generar una clave puede tardar segundos y firmar decenas o cientos de ms
     * en un teléfono barato o con el sistema cargado. En el hilo principal eso es un ANR
     * («Input dispatching timed out») y además congela a Dart. Se hace en un hilo propio, de
     * a una operación por vez (el Keystore no gana nada con paralelo), y la respuesta vuelve
     * al hilo principal, que es donde `Result` tiene que responderse.
     */
    private val hiloDeLaClave: ExecutorService =
        Executors.newSingleThreadExecutor { r -> Thread(r, "hz-rastreo-clave") }
    private val principal = Handler(Looper.getMainLooper())

    init {
        canal.setMethodCallHandler(this)
        eventos.setStreamHandler(this)
    }

    fun soltar() {
        canal.setMethodCallHandler(null)
        eventos.setStreamHandler(null)
        onCancel(null)
        hiloDeLaClave.shutdown()
    }

    /** Corre [trabajo] en el hilo de la clave, mide cuánto tardó y en qué hilo, y responde en el principal. */
    private fun enSegundoPlano(que: String, resultado: MethodChannel.Result, trabajo: () -> Any?) {
        val encolado = SystemClock.elapsedRealtimeNanos()
        hiloDeLaClave.execute {
            val inicio = SystemClock.elapsedRealtimeNanos()
            val salida = runCatching(trabajo)
            val fin = SystemClock.elapsedRealtimeNanos()
            Log.i(
                ETIQUETA,
                "$que hilo=${Thread.currentThread().name} principal=${Looper.myLooper() == Looper.getMainLooper()} " +
                    "trabajo=${(fin - inicio) / 1_000_000.0}ms espera=${(inicio - encolado) / 1_000_000.0}ms",
            )
            principal.post {
                salida.fold(
                    onSuccess = { resultado.success(it) },
                    onFailure = { resultado.error("rastreo", it.message ?: it.javaClass.simpleName, null) },
                )
            }
        }
    }

    override fun onMethodCall(call: MethodCall, resultado: MethodChannel.Result) {
        try {
            when (call.method) {
                "clave.asegurar" -> {
                    val alias = call.argument<String>("alias")!!
                    enSegundoPlano("clave.asegurar", resultado) { asegurarClave(alias) }
                }
                "clave.firmar" -> {
                    val alias = call.argument<String>("alias")!!
                    val datos = call.argument<ByteArray>("datos")!!
                    enSegundoPlano("clave.firmar(${datos.size}B)", resultado) { firmar(alias, datos) }
                }
                "clave.borrar" -> {
                    val alias = call.argument<String>("alias")!!
                    enSegundoPlano("clave.borrar", resultado) { almacen().deleteEntry(alias); null }
                }
                "reloj" -> resultado.success(reloj())
                "energia" -> resultado.success(energia())
                "energia.abrirAjustes" -> {
                    abrirAjustesDeBateria()
                    resultado.success(null)
                }
                "actividad.permiso" -> resultado.success(tienePermisoDeActividad())
                "actividad.pedirPermiso" -> pedirPermisoDeActividad(resultado)
                else -> resultado.notImplemented()
            }
        } catch (e: Exception) {
            resultado.error("rastreo", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ── La clave ─────────────────────────────────────────────────────────────────────

    private fun almacen(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    /**
     * Crea la clave si no existe. P-256, sólo firma, SHA-256, **no exportable** (ninguna
     * clave del AndroidKeyStore lo es). Con StrongBox si el teléfono lo tiene; si no, en el
     * TEE; y en el emulador, en software — y se dice cuál con `hardware`.
     */
    private fun asegurarClave(alias: String): Map<String, Any?> {
        val ks = almacen()
        if (!ks.containsAlias(alias)) {
            fun generar(strongBox: Boolean) {
                val g = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                if (strongBox && Build.VERSION.SDK_INT >= 28) spec.setIsStrongBoxBacked(true)
                g.initialize(spec.build())
                g.generateKeyPair()
            }
            try {
                generar(strongBox = true)
            } catch (e: Exception) {
                // StrongBoxUnavailableException y parientes: casi todos los teléfonos baratos.
                generar(strongBox = false)
            }
        }
        val cert = ks.getCertificate(alias)
        val privada = ks.getKey(alias, null) as PrivateKey
        return mapOf(
            // `encoded` de una pública EC en Java es el SPKI DER (X.509 SubjectPublicKeyInfo).
            "publica" to Base64.encodeToString(cert.publicKey.encoded, Base64.NO_WRAP),
            "hardware" to enHardware(privada),
        )
    }

    @Suppress("DEPRECATION")
    private fun enHardware(k: PrivateKey): Boolean = try {
        val info = KeyFactory.getInstance(k.algorithm, "AndroidKeyStore")
            .getKeySpec(k, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= 31) {
            info.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        } else {
            info.isInsideSecureHardware
        }
    } catch (e: Exception) {
        false
    }

    /** ES256 de los bytes: `SHA256withECDSA` hashea adentro y devuelve la firma DER. */
    private fun firmar(alias: String, datos: ByteArray): String {
        val privada = almacen().getKey(alias, null) as? PrivateKey
            ?: throw IllegalStateException("No hay clave del aparato: hay que enrolar")
        val s = Signature.getInstance("SHA256withECDSA")
        s.initSign(privada)
        s.update(datos)
        return Base64.encodeToString(s.sign(), Base64.NO_WRAP)
    }

    // ── Los relojes ──────────────────────────────────────────────────────────────────

    private fun reloj(): Map<String, Any?> = mapOf(
        // Cuenta el tiempo dormido y no lo mueve nadie cambiando la hora.
        "mono" to SystemClock.elapsedRealtime(),
        "arranques" to try {
            Settings.Global.getInt(contexto.contentResolver, Settings.Global.BOOT_COUNT)
        } catch (e: Exception) {
            -1
        },
    )

    // ── La energía ───────────────────────────────────────────────────────────────────

    private fun energia(): Map<String, Any?> {
        val pm = contexto.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "sinOptimizacion" to pm.isIgnoringBatteryOptimizations(contexto.packageName),
            "ahorro" to pm.isPowerSaveMode,
            "fabricante" to Build.MANUFACTURER,
            "modelo" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /**
     * La lista de optimización de batería, para que la persona elija «Sin restricciones».
     * No se usa `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` porque exige declarar
     * `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, que Play restringe — y este paquete no declara.
     */
    private fun abrirAjustesDeBateria() {
        val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        contexto.startActivity(i)
    }

    // ── La actividad ─────────────────────────────────────────────────────────────────

    private fun tienePermisoDeActividad(): Boolean =
        Build.VERSION.SDK_INT < 29 ||
            contexto.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    private fun declaroPermisoDeActividad(): Boolean = try {
        val info = contexto.packageManager.getPackageInfo(
            contexto.packageName, PackageManager.GET_PERMISSIONS
        )
        info.requestedPermissions?.contains(Manifest.permission.ACTIVITY_RECOGNITION) == true
    } catch (e: Exception) {
        false
    }

    private fun pedirPermisoDeActividad(resultado: MethodChannel.Result) {
        if (tienePermisoDeActividad()) return resultado.success(true)
        val a = actividad
        if (a == null || !declaroPermisoDeActividad()) return resultado.success(false)
        permisoPendiente = resultado
        a.requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), CODIGO_PERMISO)
    }

    override fun onRequestPermissionsResult(
        codigo: Int, permisos: Array<out String>, concedidos: IntArray
    ): Boolean {
        if (codigo != CODIGO_PERMISO) return false
        permisoPendiente?.success(concedidos.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permisoPendiente = null
        return true
    }

    /**
     * Las TRANSICIONES de actividad (entra/sale de vehículo, bici, a pie, corriendo, quieto),
     * no la actividad cada N segundos: las transiciones las calcula Play Services con el
     * acelerómetro en su proceso, y a nosotros sólo nos despierta el cambio.
     *
     * 🔴 El receptor es DINÁMICO (no hay `<receiver>` en el manifiesto vacío): vive mientras
     * viva el proceso. Con la captura propia el proceso vive por el servicio en primer plano
     * de geolocator; si lo matan, no hay actividad — es el límite conocido de la captura
     * propia que mide D-04.
     */
    @SuppressLint("MissingPermission", "UnspecifiedRegisterReceiverFlag")
    override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
        sumidero = sink
        if (!tienePermisoDeActividad()) {
            sink?.error("sin_permiso", "Falta ACTIVITY_RECOGNITION", null)
            return
        }
        try {
            val accion = "${contexto.packageName}.hz_collection.ACTIVIDAD"
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) = entregar(i)
            }
            val filtro = IntentFilter(accion)
            if (Build.VERSION.SDK_INT >= 33) {
                contexto.registerReceiver(r, filtro, Context.RECEIVER_NOT_EXPORTED)
            } else {
                contexto.registerReceiver(r, filtro)
            }
            receptor = r
            val bandera = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val pi = PendingIntent.getBroadcast(
                contexto, 7301, Intent(accion).setPackage(contexto.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or bandera
            )
            intencion = pi
            val tipos = listOf(
                com.google.android.gms.location.DetectedActivity.IN_VEHICLE,
                com.google.android.gms.location.DetectedActivity.ON_BICYCLE,
                com.google.android.gms.location.DetectedActivity.WALKING,
                com.google.android.gms.location.DetectedActivity.RUNNING,
                com.google.android.gms.location.DetectedActivity.STILL,
            )
            val transiciones = tipos.map {
                com.google.android.gms.location.ActivityTransition.Builder()
                    .setActivityType(it)
                    .setActivityTransition(
                        com.google.android.gms.location.ActivityTransition.ACTIVITY_TRANSITION_ENTER
                    )
                    .build()
            }
            com.google.android.gms.location.ActivityRecognition.getClient(contexto)
                .requestActivityTransitionUpdates(
                    com.google.android.gms.location.ActivityTransitionRequest(transiciones), pi
                )
                .addOnFailureListener { e -> sumidero?.error("actividad", e.message, null) }
        } catch (e: Throwable) {
            // NoClassDefFoundError si no hay Play Services en el APK; SecurityException si
            // el permiso no quedó. Ninguno es fatal.
            sink?.error("actividad", "${e.javaClass.simpleName}: ${e.message}", null)
        }
    }

    private fun entregar(i: Intent) {
        try {
            if (!com.google.android.gms.location.ActivityTransitionResult.hasResult(i)) return
            val r = com.google.android.gms.location.ActivityTransitionResult.extractResult(i) ?: return
            for (e in r.transitionEvents) {
                val tipo = when (e.activityType) {
                    com.google.android.gms.location.DetectedActivity.IN_VEHICLE -> "vehiculo"
                    com.google.android.gms.location.DetectedActivity.ON_BICYCLE -> "bici"
                    com.google.android.gms.location.DetectedActivity.WALKING -> "aPie"
                    com.google.android.gms.location.DetectedActivity.RUNNING -> "corriendo"
                    com.google.android.gms.location.DetectedActivity.STILL -> "quieto"
                    else -> "desconocida"
                }
                sumidero?.success(tipo)
            }
        } catch (e: Throwable) {
            sumidero?.error("actividad", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    override fun onCancel(args: Any?) {
        try {
            intencion?.let {
                com.google.android.gms.location.ActivityRecognition.getClient(contexto)
                    .removeActivityTransitionUpdates(it)
            }
        } catch (e: Throwable) {
        }
        try {
            receptor?.let { contexto.unregisterReceiver(it) }
        } catch (e: Exception) {
        }
        receptor = null
        intencion = null
        sumidero = null
    }

    companion object {
        private const val CODIGO_PERMISO = 7302
    }
}
