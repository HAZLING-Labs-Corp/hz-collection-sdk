package com.hazling.collection

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.app.NotificationManager
import android.os.SystemClock
import android.os.UserManager
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.accessibility.AccessibilityManager
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.sqrt

/**
 * LAS SEÑALES DE NIVEL 0 — todo lo que se puede leer del teléfono SIN PEDIR UN PERMISO.
 *
 * 🔴 ESTE ARCHIVO NO PIDE NI DECLARA NINGÚN PERMISO, y el manifiesto de al lado está vacío
 * a propósito. Un permiso declarado en un paquete se le inyecta a TODA aplicación que lo
 * instale, la use o no — es el error que se le midió a CredoLab, cuyos paquetes le meten
 * READ_CONTACTS y READ_CALENDAR a cualquiera. `bin/muro.dart` lo comprueba en cada
 * compilación.
 *
 * ══ 🔴 DE DÓNDE SALE ESTE CÓDIGO, Y DE DÓNDE NO ══
 *
 * **De ningún SDK ajeno.** Ni una línea, ni una clase, ni un recurso, ni una biblioteca
 * compilada de otro colector entra en este repositorio: no se enlaza ninguno, no se declara
 * ninguno como dependencia, y no hay un solo `.jar`, `.aar`, `.dex` ni `.smali` de terceros
 * en el árbol. Todo lo de abajo está escrito en Kotlin contra la **API pública y documentada
 * de Android** —`Settings.Global`, `Settings.Secure`, `Settings.System`, `SensorManager`,
 * `BatteryManager`, `AccessibilityManager`, `ConnectivityManager`, `TelephonyManager`—, cada
 * una de ellas en developer.android.com y usable por cualquiera. Se puede auditar renglón
 * por renglón.
 *
 * Lo que aportaron las cuatro investigaciones del 2026-08-31 no fue código: fue **prioridad**
 * —cuáles de los cientos de campos posibles vale la pena mirar—, que es una decisión y no una
 * implementación. Y una de las cuatro aportó algo que ninguno de los colectores del mercado
 * tiene:
 *
 *   · El séptimo —`huellaDigital`— es el único grupo con respaldo independiente, y no lo
 *     tiene ningún colector del sector: sale del estudio de Berg, Burg, Gombovic y Puri para
 *     NBER sobre 270.000 compras, que midió que un modelo hecho *sólo* con huella digital
 *     —tipo de aparato, sistema, hora de la compra, canal— alcanza **AUC 69,6% contra 68,3%
 *     del FICO**. Y de la revisión del mercado antifraude (Socure, FingerprintJS, Seon), donde
 *     la coherencia entre idioma, zona horaria y país de la SIM es la señal más barata que
 *     existe. Ninguna cifra publicada por un proveedor de este sector está auditada por
 *     terceros; las de NBER sí, y por eso este grupo pesa distinto que los otros seis.
 *
 * 🔴 Y lo que enseñan los que perdieron: **Kreditech publicitaba 20.000 puntos de datos y
 * quebró.** Más campos no es mejor puntaje. Estos ~90 se eligieron por lo que aportan, no
 * por llenar una lista.
 *
 * 🔴 CADA LECTURA VA EN SU PROPIO try. Un teléfono donde una clave no existe o el fabricante
 * la bloqueó no puede hacer que se pierdan las otras noventa. Lo que no se pudo leer
 * sencillamente no aparece en el mapa, y eso es distinto de aparecer en cero — ver la regla
 * de «nulo no es cero» en transformar.dart.
 */
class SenalesPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var canal: MethodChannel
    private lateinit var contexto: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        contexto = binding.applicationContext
        canal = MethodChannel(binding.binaryMessenger, "hz_collection_sdk/senales")
        canal.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        canal.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, resultado: MethodChannel.Result) {
        when (call.method) {
            "medir" -> resultado.success(medir())
            "puedeSegundoPlano" -> resultado.success(puedeSegundoPlano())
            else -> resultado.notImplemented()
        }
    }

    private fun medir(): Map<String, Any?> = buildMap {
        putAll(configuracionDelSistema())
        putAll(accesibilidad())
        putAll(bateriaAFondo())
        putAll(sensores())
        putAll(perfilDeUsuario())
        putAll(redProfunda())
        putAll(huellaDigital())
        putAll(canalesAlcanzables())
        putAll(entregabilidad())
    }

    /**
     * ¿LA APLICACIÓN ANFITRIONA DECLARÓ LO QUE HACE FALTA PARA LEER LA UBICACIÓN EN SEGUNDO
     * PLANO?
     *
     * 🔴 NO PIDE NADA Y NO LEE NADA DE LA PERSONA. Lee el manifiesto FUSIONADO de la propia
     * aplicación —`PackageManager.GET_PERMISSIONS`, API pública, sin permiso— y contesta qué
     * falta. Es la única forma honesta de que el SDK sepa si puede usar un permiso que
     * **él no declara y no va a declarar**: declararlo acá se lo inyectaría a toda
     * aplicación que instale el paquete, y para una financiera eso es el camino corto a que
     * Google le saque la app de Play.
     *
     * Sin esto, un comercio prende «segundo plano» en su consola, ve el interruptor en
     * verde, espera quince días y no mide nada. Con esto, el modo se apaga solo y dice
     * exactamente qué renglón le falta al manifiesto.
     *
     * Los tres que se miran, y por qué:
     *
     *  · `ACCESS_BACKGROUND_LOCATION` — el permiso en sí. Desde Android 10.
     *  · `FOREGROUND_SERVICE` — `geolocator` levanta un servicio en primer plano para
     *    sostener las lecturas; su manifiesto declara el servicio, **no el permiso**.
     *  · `FOREGROUND_SERVICE_LOCATION` — desde Android 14 un servicio de tipo `location`
     *    exige además este permiso, y sin él el sistema **tira la aplicación abajo** al
     *    arrancar el servicio. Sólo se exige si la aplicación apunta a 34 o más: a una que
     *    apunte a 33 pedírselo sería marcar en rojo algo que anda.
     */
    private fun puedeSegundoPlano(): Map<String, Any?> {
        val declarados: Set<String> = intentar {
            @Suppress("DEPRECATION")
            contexto.packageManager
                .getPackageInfo(contexto.packageName, PackageManager.GET_PERMISSIONS)
                .requestedPermissions
                ?.toSet()
        } ?: emptySet()

        val faltan = mutableListOf<String>()
        if (!declarados.contains("android.permission.ACCESS_BACKGROUND_LOCATION")) {
            faltan.add("android.permission.ACCESS_BACKGROUND_LOCATION")
        }
        if (!declarados.contains("android.permission.FOREGROUND_SERVICE")) {
            faltan.add("android.permission.FOREGROUND_SERVICE")
        }
        val apuntaA34 = intentar { contexto.applicationInfo.targetSdkVersion } ?: 0
        if (Build.VERSION.SDK_INT >= 34 && apuntaA34 >= 34 &&
            !declarados.contains("android.permission.FOREGROUND_SERVICE_LOCATION")
        ) {
            faltan.add("android.permission.FOREGROUND_SERVICE_LOCATION")
        }

        return mapOf(
            "sePuede" to faltan.isEmpty(),
            "faltan" to faltan,
        )
    }

    /** Corre una lectura y se traga el fallo. Lo que no se pudo leer no aparece. */
    private inline fun <T> intentar(bloque: () -> T): T? = try { bloque() } catch (_: Throwable) { null }

    // ── 1 · La configuración del sistema ────────────────────────────────────────────────
    //
    // 28 claves de `android.provider.Settings`, todas públicas y documentadas. Las tres
    // primeras son señal antifraude directa:
    // depuración USB activa, modo desarrollador y una aplicación marcada como depurable no
    // son cosas que tenga el teléfono de alguien que sólo quiere pagar sus cuotas.
    //
    // 🔴 Y las tres escalas de animación en cero son la firma clásica de una granja: se
    // apagan para que el emulador corra más rápido. Por eso van, aunque parezcan triviales.

    private fun configuracionDelSistema(): Map<String, Any?> {
        val cr = contexto.contentResolver
        val seguras = listOf(
            "adb_enabled", "development_settings_enabled", "accessibility_enabled",
            "default_input_method", "install_non_market_apps", "device_provisioned"
        )
        val globales = listOf(
            "airplane_mode_on", "boot_count", "usb_mass_storage_enabled",
            "window_animation_scale", "transition_animation_scale", "animator_duration_scale",
            "wifi_watchdog_on", "wifi_num_open_networks_kept", "wifi_max_dhcp_retry_count",
            "development_settings_enabled", "adb_enabled", "stay_on_while_plugged_in"
        )
        val delSistema = listOf(
            "screen_off_timeout", "screen_brightness_mode", "font_scale",
            "sound_effects_enabled", "time_12_24", "end_button_behavior",
            "accelerometer_rotation", "haptic_feedback_enabled", "dtmf_tone"
        )

        return buildMap {
            for (k in seguras) intentar { Settings.Secure.getString(cr, k) }?.let { put("cfg_$k", it) }
            for (k in globales) intentar { Settings.Global.getString(cr, k) }?.let { put("cfg_$k", it) }
            for (k in delSistema) intentar { Settings.System.getString(cr, k) }?.let { put("cfg_$k", it) }

            // `debug_app` dice qué aplicación quedó marcada como depurable. Se manda SÓLO si
            // es la propia: el nombre de otra aplicación es un dato de terceros que no nos
            // corresponde, y no aporta al puntaje.
            intentar { Settings.Global.getString(cr, "debug_app") }?.let {
                put("cfg_debug_app_es_la_nuestra", it == contexto.packageName)
            }
        }
    }

    // ── 2 · Servicios de accesibilidad ──────────────────────────────────────────────────
    //
    // 🔴 LA SEÑAL MÁS VALIOSA DE TODA LA LISTA, y cuesta cero permisos. Un servicio de
    // accesibilidad activo que pueda leer la pantalla y tocar por vos es la firma del fraude
    // asistido: alguien guiando a la víctima por teléfono mientras le operan la cuenta.
    //
    // Se cuenta y se clasifica, NO se manda la lista de paquetes: qué aplicaciones tiene
    // instaladas una persona es un dato que no necesitamos para decir «hay una herramienta
    // de control remoto activa», que es lo único que importa acá.

    private fun accesibilidad(): Map<String, Any?> = buildMap {
        val am = intentar {
            contexto.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        } ?: return@buildMap

        intentar { am.isEnabled }?.let { put("acc_prendida", it) }
        intentar { am.isTouchExplorationEnabled }?.let { put("acc_exploracion_tactil", it) }

        val activos = intentar {
            am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        } ?: emptyList()
        val instalados = intentar { am.installedAccessibilityServiceList } ?: emptyList()

        put("acc_activos", activos.size)
        put("acc_instalados", instalados.size)

        // Los dos que de verdad importan: poder MIRAR la pantalla y poder TOCAR por vos.
        put("acc_puede_leer_la_pantalla", activos.any {
            intentar { it.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_RETRIEVE_WINDOW_CONTENT != 0 } == true
        })
        put("acc_puede_tocar_por_vos", activos.any {
            intentar {
                Build.VERSION.SDK_INT >= 24 &&
                    it.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_PERFORM_GESTURES != 0
            } == true
        })
        // Cuántos NO se declaran como herramienta de accesibilidad de verdad. Android 30+
        // obliga a declararlo, y quien no lo hace suele estar usando la API para otra cosa.
        put("acc_activos_sin_declararse_herramienta", activos.count {
            intentar {
                Build.VERSION.SDK_INT >= 30 && !it.isAccessibilityTool
            } == true
        })
    }

    // ── 3 · La batería, a fondo ─────────────────────────────────────────────────────────
    //
    // Voltaje, temperatura, tecnología y salud. Un emulador reporta valores imposibles
    // —temperatura constante, voltaje redondo— y una granja de teléfonos enchufados a la vez
    // reporta todos lo mismo. Es señal antifraude, no perfil de la persona.

    private fun bateriaAFondo(): Map<String, Any?> = buildMap {
        val i: Intent = intentar {
            contexto.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        } ?: return@buildMap

        intentar { i.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) }
            ?.takeIf { it >= 0 }?.let { put("bat_voltaje_mv", it) }
        intentar { i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) }
            ?.takeIf { it >= 0 }?.let { put("bat_temperatura_decimas_c", it) }
        intentar { i.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY) }?.let { put("bat_tecnologia", it) }
        intentar { i.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) }
            ?.takeIf { it >= 0 }?.let { put("bat_salud", it) }
        intentar { i.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) }
            ?.takeIf { it >= 0 }?.let { put("bat_enchufado_a", it) }
        intentar { i.getIntExtra(BatteryManager.EXTRA_SCALE, -1) }
            ?.takeIf { it >= 0 }?.let { put("bat_escala", it) }
        intentar { i.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true) }?.let { put("bat_presente", it) }
    }

    // ── 4 · Los sensores ────────────────────────────────────────────────────────────────
    //
    // Se manda CUÁNTOS hay y cuáles de los básicos existen, no la lista con vendedor y
    // resolución. La lista completa es una huella de dispositivo bastante única, y Apple
    // prohíbe la huella combinada tenga o no consentimiento — no vale la pena traerla en
    // Android para tener que sacarla después.
    //
    // Un teléfono real tiene entre quince y treinta sensores. Un emulador tiene tres.

    private fun sensores(): Map<String, Any?> = buildMap {
        val sm = intentar { contexto.getSystemService(Context.SENSOR_SERVICE) as SensorManager }
            ?: return@buildMap
        val todos = intentar { sm.getSensorList(Sensor.TYPE_ALL) } ?: return@buildMap

        /**
         * 🔴 NO ALCANZA CON `getSensorList(TYPE_ALL)` — corregido el 2026-09-05.
         *
         * Juan lo vio en su propio teléfono: un Honor con giroscopio, y la señal decía que
         * no lo tenía. Y no era un detalle cosmético — `sen_hay_giroscopio` en falso le sumó
         * **+10 puntos al portón de fraude**, sobre un teléfono real y sano.
         *
         * `getSensorList(TYPE_ALL)` NO devuelve todos los sensores: deja afuera los de
         * despertar y, sobre todo, **los fabricantes filtran esa lista**. Huawei y Honor son
         * los casos conocidos. La forma documentada de preguntar «¿este aparato tiene tal
         * sensor?» es `getDefaultSensor(tipo)`, que resuelve contra el HAL y no contra una
         * lista que el fabricante armó.
         *
         * Se consultan las dos y se toma el O lógico: si CUALQUIERA de los dos caminos lo
         * ve, el sensor existe. Un falso negativo acá le cuesta puntos a una persona real;
         * un falso positivo sólo le quita puntos a un emulador, que ya cae por otras diez
         * señales. La duda se resuelve para el lado de no castigar a nadie.
         */
        fun hay(tipo: Int): Boolean =
            (intentar { sm.getDefaultSensor(tipo) } != null) || todos.any { it.type == tipo }

        put("sen_cantidad", todos.size)
        put("sen_hay_acelerometro", hay(Sensor.TYPE_ACCELEROMETER))
        /**
         * El giroscopio además admite una variante SIN CALIBRAR (`TYPE_GYROSCOPE_UNCALIBRATED`),
         * y hay aparatos que exponen sólo ésa. Para la pregunta que importa —«¿este teléfono
         * puede saber que lo giraron?»— las dos sirven igual.
         */
        put("sen_hay_giroscopio", hay(Sensor.TYPE_GYROSCOPE) || hay(Sensor.TYPE_GYROSCOPE_UNCALIBRATED))
        put("sen_hay_magnetometro", hay(Sensor.TYPE_MAGNETIC_FIELD) || hay(Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED))
        put("sen_hay_proximidad", hay(Sensor.TYPE_PROXIMITY))
        put("sen_hay_luz", hay(Sensor.TYPE_LIGHT))
        put("sen_hay_barometro", hay(Sensor.TYPE_PRESSURE))
        put("sen_hay_paso", hay(Sensor.TYPE_STEP_COUNTER))
        // Cuántos dicen ser del fabricante genérico de Android: en un teléfono real casi
        // ninguno; en un emulador, todos.
        put("sen_genericos", todos.count {
            intentar { it.vendor?.contains("AOSP", true) == true || it.vendor?.contains("Google", true) == true } == true
        })
    }

    // ── 5 · El perfil de usuario ────────────────────────────────────────────────────────
    //
    // Si el teléfono tiene varios usuarios o un perfil de trabajo. No dice quién es la
    // persona; dice en qué tipo de aparato está la aplicación.

    private fun perfilDeUsuario(): Map<String, Any?> = buildMap {
        val um = intentar { contexto.getSystemService(Context.USER_SERVICE) as UserManager }
            ?: return@buildMap
        intentar { um.isSystemUser }?.let { put("usr_es_el_principal", it) }
        intentar { um.isUserAGoat }?.let { /* la broma de Android: no se manda */ }
        intentar {
            Build.VERSION.SDK_INT >= 23 && um.isDemoUser
        }?.let { put("usr_es_demo", it) }
        intentar {
            Build.VERSION.SDK_INT >= 34 && um.isUserForeground
        }?.let { put("usr_en_primer_plano", it) }
    }

    // ── 6 · La red, más a fondo que el tipo de conexión ─────────────────────────────────
    //
    // `ACCESS_NETWORK_STATE` ya está declarado por firebase_messaging y es nivel 0: no le
    // muestra un diálogo a nadie. No se lee el BSSID ni el nombre de la red: eso exige
    // permiso de ubicación desde Android 8 y además identifica el lugar donde está la persona.

    private fun redProfunda(): Map<String, Any?> = buildMap {
        val cm = intentar { contexto.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager }
            ?: return@buildMap
        val red = intentar { cm.activeNetwork } ?: return@buildMap
        val cap = intentar { cm.getNetworkCapabilities(red) } ?: return@buildMap

        intentar { cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) }?.let { put("red_es_wifi", it) }
        intentar { cap.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) }?.let { put("red_es_celular", it) }
        intentar { cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }?.let { put("red_hay_vpn", it) }
        intentar { cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) }
            ?.let { put("red_sin_limite_de_datos", it) }
        intentar { cap.linkDownstreamBandwidthKbps }?.takeIf { it > 0 }?.let { put("red_bajada_kbps", it) }
        intentar { cap.linkUpstreamBandwidthKbps }?.takeIf { it > 0 }?.let { put("red_subida_kbps", it) }
        intentar {
            Build.VERSION.SDK_INT >= 28 && cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
        }?.let { put("red_sin_roaming", it) }
    }

    /**
     * LA HUELLA DIGITAL — el grupo que no tiene ningún colector del mercado, y el único con
     * respaldo auditado por terceros.
     *
     * El estudio de NBER sobre 270.000 compras midió que **el tipo de aparato, el sistema, la
     * hora de la compra y el canal de llegada** solos le ganan al FICO. La diferencia de
     * morosidad entre gente de iPhone y gente de Android equivale a la distancia entre un
     * puntaje mediano y el percentil 80. Nada de eso pide un permiso.
     *
     * Y la mitad antifraude: **la coherencia**. Un teléfono cuyo idioma dice México, cuya zona
     * horaria dice Kiev y cuya SIM dice Nigeria no está mintiendo en ningún campo por
     * separado; miente en la combinación. Por eso se manda el país de cada fuente Y si
     * coinciden — el booleano calculado acá vale más que los tres campos sueltos, porque
     * quien arme el puntaje no tiene por qué saber comparar códigos ISO.
     *
     * 🔴 QUÉ NO ENTRA ACÁ, y por qué: la resolución exacta de pantalla junto con el modelo
     * exacto, los ABIs completos, las fuentes instaladas y la lista de teclados por nombre.
     * Cada uno agrega poquísimo al puntaje y muchísimo a la unicidad — que es la definición de
     * huella combinada, y Apple la prohíbe TENGA O NO consentimiento. Se manda el tamaño en
     * tramos y la CANTIDAD de teclados, no cuáles.
     */
    private fun huellaDigital(): Map<String, Any?> = buildMap {
        // ── Cuándo. El campo más citado del estudio de NBER y el más barato de todos: la
        // hora a la que alguien da de alta una cuenta dice bastante, y una granja trabaja de
        // madrugada porque nadie la está mirando.
        intentar {
            val c = Calendar.getInstance()
            put("hd_hora_local", c.get(Calendar.HOUR_OF_DAY))
            put("hd_dia_de_semana", c.get(Calendar.DAY_OF_WEEK))
        }
        intentar {
            val z = TimeZone.getDefault()
            put("hd_zona_horaria", z.id)
            put("hd_minutos_de_desfase_utc", z.rawOffset / 60000)
        }
        // Un teléfono con la hora puesta a mano es raro, y es lo primero que toca quien
        // quiere burlar una comprobación de fecha.
        intentar { Settings.Global.getInt(contexto.contentResolver, Settings.Global.AUTO_TIME) }
            ?.let { put("hd_hora_automatica", it) }
        intentar { Settings.Global.getInt(contexto.contentResolver, Settings.Global.AUTO_TIME_ZONE) }
            ?.let { put("hd_zona_automatica", it) }

        // ── Dónde dice ser. Tres fuentes independientes del mismo dato.
        val paisDelSistema = intentar { Locale.getDefault().country?.lowercase() }
        intentar { Locale.getDefault().language }?.let { put("hd_idioma", it) }
        paisDelSistema?.let { put("hd_pais_del_sistema", it) }
        intentar {
            if (Build.VERSION.SDK_INT >= 24) contexto.resources.configuration.locales.size() else 1
        }?.let { put("hd_idiomas_configurados", it) }

        val tm = intentar { contexto.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager }
        // 🔴 Ninguna de estas tres pide permiso — READ_PHONE_STATE es para el número y el
        // IMEI, que no se tocan acá ni en ningún otro lado del SDK.
        val paisDeLaSim = intentar { tm?.simCountryIso?.lowercase() }?.takeIf { it.isNotEmpty() }
        val paisDeLaRed = intentar { tm?.networkCountryIso?.lowercase() }?.takeIf { it.isNotEmpty() }
        paisDeLaSim?.let { put("hd_pais_de_la_sim", it) }
        paisDeLaRed?.let { put("hd_pais_de_la_red", it) }
        intentar { tm?.networkOperatorName }?.takeIf { it.isNotEmpty() }?.let { put("hd_operadora", it) }
        intentar { tm?.simState }?.let { put("hd_estado_de_la_sim", it) }

        // La coherencia, ya resuelta. Nulo si falta alguna de las dos: comparar contra un dato
        // que no se pudo leer daría «no coincide» para todo el que no tenga SIM puesta.
        if (paisDelSistema != null && paisDeLaSim != null) {
            put("hd_pais_coherente", paisDelSistema == paisDeLaSim)
        }
        if (paisDeLaRed != null && paisDeLaSim != null) {
            put("hd_sim_y_red_coinciden", paisDeLaRed == paisDeLaSim)
        }

        // ── Qué aparato es. La señal de NBER, sin adornos.
        intentar { Build.MANUFACTURER }?.let { put("hd_marca", it) }
        intentar { Build.MODEL }?.let { put("hd_modelo", it) }
        intentar { Build.VERSION.RELEASE }?.let { put("hd_version_del_sistema", it) }
        put("hd_api", Build.VERSION.SDK_INT)
        intentar { Build.SUPPORTED_ABIS.firstOrNull() }?.let { put("hd_arquitectura", it) }
        intentar { Runtime.getRuntime().availableProcessors() }?.let { put("hd_nucleos", it) }

        // Hace cuántos meses que este teléfono no recibe un parche de seguridad. Es de las
        // señales más honestas de todo el módulo: un aparato abandonado por su fabricante es
        // un aparato de gama baja o viejo, y eso se correlaciona sin necesidad de saber el
        // precio de nada.
        intentar {
            if (Build.VERSION.SDK_INT < 23) return@intentar null
            val p = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(Build.VERSION.SECURITY_PATCH)
                ?: return@intentar null
            ((System.currentTimeMillis() - p.time) / 2_592_000_000L).toInt()
        }?.takeIf { it >= 0 }?.let { put("hd_meses_sin_parche", it) }

        intentar {
            val am = contexto.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
            put("hd_ram_total_mb", (mem.totalMem / 1_048_576L).toInt())
            put("hd_ram_libre_mb", (mem.availMem / 1_048_576L).toInt())
            put("hd_ram_en_las_ultimas", mem.lowMemory)
            put("hd_ram_poca", am.isLowRamDevice)
        }

        intentar {
            val d = contexto.resources.displayMetrics
            put("hd_densidad_dpi", d.densityDpi)
            // El tamaño físico en décimas de pulgada. Separa un teléfono de una tableta y de
            // un emulador de escritorio sin mandar la resolución exacta, que es lo que
            // convierte a esto en huella.
            val pulgadas = sqrt(
                (d.widthPixels / d.xdpi) * (d.widthPixels / d.xdpi) +
                    (d.heightPixels / d.ydpi) * (d.heightPixels / d.ydpi)
            )
            put("hd_pulgadas_x10", (pulgadas * 10).toInt())
        }

        // ── Nuestra propia aplicación. Todo esto es sobre NOSOTROS: no se mira ninguna otra.
        intentar {
            val pm = contexto.packageManager
            val info = pm.getPackageInfo(contexto.packageName, 0)
            val dias = (System.currentTimeMillis() - info.firstInstallTime) / 86_400_000L
            put("hd_dias_desde_la_instalacion", dias.toInt())
            put("hd_dias_desde_la_actualizacion",
                ((System.currentTimeMillis() - info.lastUpdateTime) / 86_400_000L).toInt())
            put("hd_reinstalada", info.firstInstallTime != info.lastUpdateTime)
        }
        // De dónde vino la aplicación. Se manda SI vino de una tienda conocida, no el nombre
        // del instalador: una tienda alternativa concreta es un dato de terceros y no cambia
        // el puntaje más que el booleano.
        intentar {
            val pm = contexto.packageManager
            @Suppress("DEPRECATION")
            val quien = if (Build.VERSION.SDK_INT >= 30) {
                pm.getInstallSourceInfo(contexto.packageName).installingPackageName
            } else {
                pm.getInstallerPackageName(contexto.packageName)
            }
            put("hd_vino_de_la_tienda", quien == "com.android.vending")
            put("hd_instalada_de_lado", quien == null)
        }

        // Cuánto lleva encendido. Una granja reinicia sus aparatos todo el tiempo; un teléfono
        // de alguien lleva días o semanas prendido.
        intentar { (SystemClock.elapsedRealtime() / 3_600_000L).toInt() }
            ?.let { put("hd_horas_desde_el_arranque", it) }

        // Cuántos teclados tiene configurados. NO cuáles: el nombre de un teclado de terceros
        // es un dato de terceros, y además es de los campos que más unicidad aportan.
        intentar {
            val im = contexto.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            put("hd_teclados", im.enabledInputMethodList.size)
        }
    }

    /**
     * PRUEBA DE CONCEPTO — CANALES ALCANZABLES: qué apps de contacto tiene instaladas.
     *
     * Sólo PRESENCIA (instalada sí/no), no actividad. Se consultan los paquetes declarados en
     * <queries> del manifiesto — la forma Play-compliant de mirar apps PUNTUALES sin el permiso
     * `QUERY_ALL_PACKAGES` (que saca de la tienda). Cada consulta va en su try: un paquete que
     * no se puede consultar no tumba a los demás.
     */
    private fun canalesAlcanzables(): Map<String, Any?> = buildMap {
        val apps = mapOf(
            "canal_whatsapp" to "com.whatsapp",
            "canal_whatsapp_business" to "com.whatsapp.w4b",
            "canal_telegram" to "org.telegram.messenger",
            "canal_messenger" to "com.facebook.orca",
            "canal_facebook" to "com.facebook.katana",
            "canal_instagram" to "com.instagram.android",
            "canal_signal" to "org.thoughtcrime.securesms",
            "canal_sms_rcs" to "com.google.android.apps.messaging",
            "canal_gmail" to "com.google.android.gm",

            // ── Vida económica — agregadas el 2026-09-05 ────────────────────────────
            //
            // Las de arriba dicen POR DÓNDE mandarle un mensaje. Éstas dicen algo de la
            // persona, que es lo que un puntaje necesita.
            //
            // 🔴 Un nombre de paquete mal escrito NO falla: devuelve `false` para
            // siempre. La señal diría «no tiene Mercado Pago» de toda la cartera y nadie
            // se enteraría nunca. Antes de darle peso a cualquiera de éstas en un modelo,
            // hay que verla en `true` en al menos un teléfono real que sí la tenga.
            "app_mapas" to "com.google.android.apps.maps",
            "app_viajes" to "com.ubercab",
            "app_mercadolibre" to "com.mercadolibre",
            "app_mercadopago" to "com.mercadopago.wallet",
            "app_binance" to "com.binance.dev",
            "app_zelle" to "com.zellepay.zelle",
            "app_netflix" to "com.netflix.mediaclient",
            "app_spotify" to "com.spotify.music",

            // ── Banca y dinero de Venezuela — agregadas el 2026-09-11 ───────────────
            //
            // Pedido de Juan: la lista de aplicaciones financieras del pais, para que el
            // libro de elegibilidad pueda mirar con cuantas instituciones formales tiene
            // relacion operativa una persona.
            //
            // 🔴 LOS DIECIOCHO ESTAN VERIFICADOS CONTRA SU FICHA DE GOOGLE PLAY. Vale la
            // advertencia de arriba, y aca pesa el doble: un paquete mal escrito diria «no
            // tiene Banesco» de TODA la cartera venezolana, para siempre, sin dar sintoma.
            // Los que no se pudieron verificar quedaron afuera a proposito.
            //
            // ⚠️ Y ninguna de estas puntua todavia: la categoria «banca» del libro esta
            // declarada y VACIA hasta que estas señales viajen de verdad. Se prende cuando
            // se vean en `true` en un telefono real.
            "banco_bdv" to "com.bancodevenezuela.bdvdigital",
            "banco_banesco" to "com.banesco.samfbancamovilunificada",
            "banco_mercantil" to "com.mercantilbanco.mercantilmovil",
            "banco_bnc" to "bnc.bncnet.mobile2",
            "banco_provincial_dinero_rapido" to "com.dinerorapido.bancamovil",
            "banco_provinet_movil" to "com.totaltexto.bancamovil",
            "banco_provinet_empresas" to "com.bbva.empresas",
            "banco_bancaribe" to "bancaribe.miconexion",
            "banco_exterior" to "com.bancoexterior",
            "banco_tesoro" to "com.tesoro.tmovil",
            "banco_bancamiga" to "com.bancamiga",
            "banco_banplus" to "com.asociadosgerenciales.banpluspay",
            "banco_pago_movil_sms" to "net.comsolje.pagomovilsms",

            // Billeteras y dolares
            "app_zinli" to "com.zinli.app",
            "app_airtm" to "com.airtm.android",
            "app_wally" to "com.kinpos.wallytech",

            // Compras en cuotas — un competidor directo, y por eso importa
            "app_cashea" to "com.cashea.app",

            // Movilidad con señal economica
            "app_yummy" to "com.yummyrides"
        )
        val pm = contexto.packageManager
        for ((clave, paquete) in apps) {
            val instalada = intentar {
                pm.getPackageInfo(paquete, 0); true
            } ?: false
            put(clave, instalada)
        }
        // PoC: log para verificación inmediata, sin dar la vuelta por la consola.
        val presentes = filterValues { it == true }.keys.joinToString(", ")
        android.util.Log.i("Collection", "canales alcanzables (instaladas): $presentes")
    }

    /**
     * ENTREGABILIDAD — ¿este push va a LLEGAR y lo va a VER? Todo sin pedir un permiso.
     *
     * Son las señales que más predicen si un aviso llega de verdad, y que casi ningún colector
     * mide: el ahorro de batería y el Doze demoran o matan el push con la pantalla apagada; la
     * restricción en segundo plano lo corta; el No molestar lo silencia; y un canal en cero es
     * un "sí" al permiso general con un "no" a ESE aviso. El teléfono manda los hechos; el
     * proveedor arma con ellos su índice de entregabilidad en el servidor.
     */
    private fun entregabilidad(): Map<String, Any?> = buildMap {
        val pm = intentar { contexto.getSystemService(Context.POWER_SERVICE) as PowerManager }
        val nm = intentar { contexto.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager }

        // ¿Puede recibir avisos, a nivel del sistema? El permiso general.
        intentar { nm?.areNotificationsEnabled() }?.let { put("ent_avisos_permitidos", it) }

        // Cuántos de NUESTROS canales están silenciados (importancia en cero). Un "sí" general
        // con un canal apagado hace que ese aviso no suene aunque el permiso esté dado.
        intentar {
            if (Build.VERSION.SDK_INT >= 26 && nm != null) {
                nm.notificationChannels.count { it.importance == NotificationManager.IMPORTANCE_NONE }
            } else null
        }?.let { put("ent_canales_silenciados", it) }

        // Doze: ¿la app está exenta de la optimización de batería? Si NO, el push se demora.
        intentar { pm?.isIgnoringBatteryOptimizations(contexto.packageName) }
            ?.let { put("ent_exento_de_doze", it) }

        // ¿El sistema restringió la app en segundo plano? Ahí el push directamente no llega.
        intentar {
            if (Build.VERSION.SDK_INT >= 28) {
                val am = contexto.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                am.isBackgroundRestricted
            } else null
        }?.let { put("ent_restringida_en_segundo_plano", it) }

        // Ahorro de batería activo → entrega demorada.
        intentar { pm?.isPowerSaveMode }?.let { put("ent_ahorro_de_bateria", it) }

        // No molestar: 1 todo, 2 prioridad, 3 nada, 4 alarmas.
        intentar {
            if (Build.VERSION.SDK_INT >= 23) nm?.currentInterruptionFilter else null
        }?.let { put("ent_modo_no_molestar", it) }

        // ¿La pantalla está encendida ahora? Es la señal de actividad más directa, sin permiso.
        intentar { pm?.isInteractive }?.let { put("ent_pantalla_encendida", it) }

        // Nivel de señal de la antena, 0 a 4. Desde Android 9 se lee sin permiso.
        intentar {
            if (Build.VERSION.SDK_INT >= 28) {
                val tm = contexto.getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
                tm.signalStrength?.level
            } else null
        }?.let { put("ent_nivel_de_senal", it) }
    }
}
