import Flutter
import UIKit
import CoreMotion
import Network

/**
 * LAS SEÑALES DE NIVEL 0 EN iOS.
 *
 * Contesta el mismo canal que Android —`hz_collection_sdk/senales`— y devuelve los campos
 * con LOS MISMOS NOMBRES, para que ni el catálogo, ni el servicio, ni la consola tengan que
 * saber de qué plataforma vino cada medición.
 *
 * ══ NO SON 95, Y ESO NO SE DISIMULA ══
 *
 * De los 95 campos de Android, en iOS se alcanzan alrededor de 35. Los que faltan no faltan
 * por falta de trabajo: no existen en iOS, y conviene tener escrito por qué, porque la
 * pregunta va a volver:
 *
 *   · los 27 de `cfg_`  — son `Settings.Global` y `Settings.Secure` de Android. iOS no
 *     expone su configuración interna a una aplicación. No hay equivalente.
 *   · los 7 de `acc_`   — Android permite ENUMERAR los servicios de accesibilidad activos.
 *     iOS sólo dice si VoiceOver está encendido, y nada sobre quién puede tocar la pantalla.
 *     🔴 Ésta es la pérdida que más importa: son los campos que detectan una estafa asistida
 *     en el momento. En iPhone esa señal no se puede tener.
 *   · los 3 de `usr_`   — iOS no tiene multiusuario. El concepto no aplica.
 *   · voltaje, temperatura, salud y tecnología de la batería — Android los publica, iOS no.
 *   · velocidad de bajada y subida, roaming, operadora, país de la SIM — CoreTelephony quedó
 *     restringido y buena parte deprecado desde iOS 16.
 *
 * ══ LO QUE SE DEJÓ AFUERA A PROPÓSITO, aunque se podría ══
 *
 * `hd_teclados` y `hd_horas_desde_el_arranque` son *Required Reason APIs* de Apple. La única
 * razón aprobada para leer los teclados activos exige que el dato NO SALGA DEL APARATO — y
 * este SDK justamente lo manda. Incluirlos es arriesgar el rechazo del build por un campo.
 * Si algún día hacen falta, se agregan en el aparato y viaja el agregado, no el dato.
 *
 * ══ Y NUNCA SE DEVUELVE CERO POR "NO SE PUDO MEDIR" ══
 *
 * Un campo que no se alcanza simplemente NO VIAJA. Es la misma regla que en Android y no es
 * un detalle: del otro lado, un `?? 0` convertiría "no medido" en "señal ausente", que son
 * cosas opuestas. Nulo no es cero.
 */
public class SenalesPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let canal = FlutterMethodChannel(name: "hz_collection_sdk/senales",
                                     binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SenalesPlugin(), channel: canal)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "medir":
      result(medir())
    case "puedeSegundoPlano":
      result(puedeSegundoPlano())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════════════

  /// ¿LA APLICACIÓN ANFITRIONA DECLARÓ LO QUE HACE FALTA PARA LEER LA UBICACIÓN CON LA
  /// APLICACIÓN EN EL FONDO?
  ///
  /// 🔴 En iOS no hay un permiso en un manifiesto: hay dos renglones en el `Info.plist`, y
  /// si falta cualquiera de los dos, CoreLocation **no entrega nada en el fondo y no tira
  /// ningún error**. Ése es el fallo silencioso que esto existe para no tener.
  ///
  ///  · `NSLocationAlwaysAndWhenInUseUsageDescription` — el texto que Apple le muestra a la
  ///    persona al pedir el «Siempre». Sin él, `requestAlwaysAuthorization` no hace nada.
  ///  · `UIBackgroundModes` con `location` — sin esto, iOS suspende la app y las
  ///    actualizaciones se cortan al salir de la pantalla.
  ///
  /// Sólo lee el propio `Info.plist` de la aplicación. No pide nada y no toca datos de nadie.
  private func puedeSegundoPlano() -> [String: Any] {
    let info = Bundle.main.infoDictionary ?? [:]
    var faltan: [String] = []

    let texto = info["NSLocationAlwaysAndWhenInUseUsageDescription"] as? String
    if (texto ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      faltan.append("Info.plist → NSLocationAlwaysAndWhenInUseUsageDescription")
    }

    let modos = info["UIBackgroundModes"] as? [String] ?? []
    if !modos.contains("location") {
      faltan.append("Info.plist → UIBackgroundModes con «location»")
    }

    return ["sePuede": faltan.isEmpty, "faltan": faltan]
  }

  private func medir() -> [String: Any] {
    var m: [String: Any] = [:]

    huellaDelAparato(&m)
    fechasDeLaInstalacion(&m)
    tiempoYIdioma(&m)
    pantalla(&m)
    sensores(&m)
    bateria(&m)
    red(&m)
    procedencia(&m)

    return m
  }

  // ── El aparato ──────────────────────────────────────────────────────────────────────

  private func huellaDelAparato(_ m: inout [String: Any]) {
    m["hd_marca"] = "Apple"
    m["hd_modelo"] = identificadorDeMaquina()
    m["hd_version_del_sistema"] = UIDevice.current.systemVersion
    m["hd_nucleos"] = ProcessInfo.processInfo.processorCount

    #if arch(arm64)
      m["hd_arquitectura"] = "arm64"
    #elseif arch(x86_64)
      m["hd_arquitectura"] = "x86_64"
    #endif

    // En tramos de 512 MB, igual que Android: el valor exacto identifica más de lo que
    // aporta, y para saber si el aparato es de gama baja el tramo alcanza.
    let bytes = ProcessInfo.processInfo.physicalMemory
    let mb = Int(bytes / 1_048_576)
    m["hd_ram_total_mb"] = (mb / 512) * 512
    m["hd_ram_poca"] = mb < 3072
  }

  /// El modelo REAL (`iPhone15,2`), no el genérico que devuelve `UIDevice.model` —
  /// que en todos los iPhone dice literalmente "iPhone" y no sirve para nada.
  private func identificadorDeMaquina() -> String {
    var sistema = utsname()
    uname(&sistema)
    return withUnsafePointer(to: &sistema.machine) { puntero in
      puntero.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
  }

  // ── Cuándo se instaló y cuándo se actualizó ─────────────────────────────────────────
  //
  // iOS no tiene `PackageManager.firstInstallTime`. Se deduce de la fecha de creación de la
  // carpeta de documentos —que nace con la instalación y muere al desinstalar— y de la del
  // propio bundle, que cambia con cada actualización. Es la técnica estándar y no pide
  // ningún permiso ni entra en las Required Reason APIs.

  private func fechasDeLaInstalacion(_ m: inout [String: Any]) {
    let fm = FileManager.default

    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
       let creada = (try? fm.attributesOfItem(atPath: docs.path))?[.creationDate] as? Date {
      m["hd_dias_desde_la_instalacion"] = enTramosDeSiete(dias(desde: creada))
    }

    if let bundle = Bundle.main.executableURL,
       let modificado = (try? fm.attributesOfItem(atPath: bundle.path))?[.modificationDate] as? Date {
      m["hd_dias_desde_la_actualizacion"] = dias(desde: modificado)
    }
  }

  private func dias(desde: Date) -> Int {
    max(0, Int(Date().timeIntervalSince(desde) / 86_400))
  }

  /// Tramos de siete días, como en Android: la fecha exacta de instalación es un
  /// identificador casi único cuando se cruza con otras señales.
  private func enTramosDeSiete(_ d: Int) -> Int { (d / 7) * 7 }

  // ── Tiempo e idioma ─────────────────────────────────────────────────────────────────

  private func tiempoYIdioma(_ m: inout [String: Any]) {
    let ahora = Date()
    let cal = Calendar.current

    m["hd_hora_local"] = cal.component(.hour, from: ahora)
    m["hd_dia_de_semana"] = cal.component(.weekday, from: ahora)
    m["hd_zona_horaria"] = TimeZone.current.identifier
    m["hd_minutos_de_desfase_utc"] = TimeZone.current.secondsFromGMT() / 60

    if let idioma = Locale.preferredLanguages.first {
      m["hd_idioma"] = idioma
    }
    m["hd_idiomas_configurados"] = Locale.preferredLanguages.count

    if #available(iOS 16.0, *) {
      m["hd_pais_del_sistema"] = Locale.current.region?.identifier
    } else {
      m["hd_pais_del_sistema"] = Locale.current.regionCode
    }
  }

  // ── Pantalla ────────────────────────────────────────────────────────────────────────

  private func pantalla(_ m: inout [String: Any]) {
    let p = UIScreen.main
    // Android reporta dpi; iOS habla de factor de escala. Se traduce contra los 160 dpi
    // que Android toma como densidad base, así que el número queda comparable entre las
    // dos plataformas — que es todo el punto de compartir el nombre del campo.
    m["hd_densidad_dpi"] = Int(p.scale * 160)

    let puntos = p.bounds.size
    let pulgadasDeDiagonal = sqrt(pow(puntos.width * p.scale, 2) + pow(puntos.height * p.scale, 2)) / (p.scale * 160)
    m["hd_pulgadas_x10"] = Int((pulgadasDeDiagonal * 10).rounded())
  }

  // ── Sensores ────────────────────────────────────────────────────────────────────────
  //
  // Sólo se pregunta si EXISTEN, nunca se leen. Preguntar por su existencia no pide
  // permiso y no enciende nada: es exactamente lo que hace el lado de Android.

  private func sensores(_ m: inout [String: Any]) {
    let motion = CMMotionManager()

    let acelerometro = motion.isAccelerometerAvailable
    let giroscopio = motion.isGyroAvailable
    let magnetometro = motion.isMagnetometerAvailable
    let barometro = CMAltimeter.isRelativeAltitudeAvailable()
    let paso = CMPedometer.isStepCountingAvailable()

    // La proximidad se comprueba encendiendo el monitor y leyendo si quedó encendido —
    // en los aparatos que no lo tienen, la propiedad no toma el valor. Se apaga enseguida.
    let dispositivo = UIDevice.current
    dispositivo.isProximityMonitoringEnabled = true
    let proximidad = dispositivo.isProximityMonitoringEnabled
    dispositivo.isProximityMonitoringEnabled = false

    m["sen_hay_acelerometro"] = acelerometro
    m["sen_hay_giroscopio"] = giroscopio
    m["sen_hay_magnetometro"] = magnetometro
    m["sen_hay_barometro"] = barometro
    m["sen_hay_paso"] = paso
    m["sen_hay_proximidad"] = proximidad

    // `sen_hay_luz` NO va: iOS no publica el sensor de luz ambiente.
    // `sen_genericos` tampoco: es un concepto de emulador de Android.
    m["sen_cantidad"] = [acelerometro, giroscopio, magnetometro, barometro, paso, proximidad]
      .filter { $0 }.count
  }

  // ── Batería ─────────────────────────────────────────────────────────────────────────

  private func bateria(_ m: inout [String: Any]) {
    let d = UIDevice.current
    let estabaEncendido = d.isBatteryMonitoringEnabled
    d.isBatteryMonitoringEnabled = true

    m["bat_presente"] = true
    m["bat_escala"] = 100

    switch d.batteryState {
    case .charging:  m["bat_enchufado_a"] = "cargando"
    case .full:      m["bat_enchufado_a"] = "completa"
    case .unplugged: m["bat_enchufado_a"] = "nada"
    default:         break   // `.unknown` no viaja: nulo no es cero
    }

    // Voltaje, temperatura, salud y tecnología NO van: iOS no los publica. Devolver 0
    // sería afirmar que la batería está a cero volts.

    if !estabaEncendido { d.isBatteryMonitoringEnabled = false }
  }

  // ── Red ─────────────────────────────────────────────────────────────────────────────
  //
  // `NWPathMonitor` es asincrónico y esto tiene que contestar sincrónico. Se espera con un
  // semáforo y un tope corto: si la red no contesta en 400 ms, los campos NO VIAJAN. Una
  // medición ausente es correcta; una inventada, no.

  private func red(_ m: inout [String: Any]) {
    let monitor = NWPathMonitor()
    let cola = DispatchQueue(label: "hz.collection.red")
    let espera = DispatchSemaphore(value: 0)
    var camino: NWPath?

    monitor.pathUpdateHandler = { p in
      camino = p
      espera.signal()
    }
    monitor.start(queue: cola)
    _ = espera.wait(timeout: .now() + 0.4)
    monitor.cancel()

    guard let c = camino else { return }

    m["red_es_wifi"] = c.usesInterfaceType(.wifi)
    m["red_es_celular"] = c.usesInterfaceType(.cellular)
    // Modo de datos bajos encendido = el sistema pide ahorrar. Es el equivalente honesto
    // de la restricción de datos en segundo plano de Android.
    m["red_sin_limite_de_datos"] = !c.isConstrained
    // Una VPN aparece como una interfaz que no es wifi ni celular ni cableada.
    m["red_hay_vpn"] = c.usesInterfaceType(.other)
      && !c.usesInterfaceType(.wifi) && !c.usesInterfaceType(.cellular)

    // Bajada, subida y roaming NO van: iOS no los expone.
  }

  // ── De dónde vino la aplicación ─────────────────────────────────────────────────────
  //
  // En Android es `getInstallerPackageName`. En iOS se deduce de dos rastros del bundle:
  // el perfil de aprovisionamiento —que existe en desarrollo y en Ad Hoc, y NO existe en
  // una app bajada de la tienda— y el nombre del recibo, que en TestFlight es `sandboxReceipt`.

  private func procedencia(_ m: inout [String: Any]) {
    let tienePerfil = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
    let esTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    m["hd_instalada_de_lado"] = tienePerfil
    m["hd_vino_de_la_tienda"] = !tienePerfil && !esTestFlight
    // `hd_reinstalada` se deduce del lado del servicio comparando la instalación nueva
    // contra las anteriores del mismo teléfono: acá no hay con qué saberlo.
  }
}
