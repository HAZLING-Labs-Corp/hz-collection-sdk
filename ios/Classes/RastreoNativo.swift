import Flutter
import UIKit
import CoreMotion
import Security

/**
 * EL LADO NATIVO DEL RASTREO EN iOS — el mismo canal y los mismos nombres que Android
 * (`hz_collection_sdk/rastreo`), para que Dart no sepa de qué plataforma vino nada.
 *
 * La clave vive en el SECURE ENCLAVE, no exportable. El simulador no tiene enclave: ahí se
 * crea en el llavero por software y `hardware` dice `false` — no se disimula.
 *
 * 🔴 NO SE DECLARA NADA ACÁ. La actividad (CoreMotion) necesita `NSMotionUsageDescription`
 * en el Info.plist de la APLICACIÓN; sin ese renglón iOS mata la app al pedirla, así que se
 * comprueba antes de arrancar y, si falta, se informa como error del flujo.
 */
final class RastreoNativo: NSObject, FlutterStreamHandler {

  private let canal: FlutterMethodChannel
  private let eventos: FlutterEventChannel
  private let movimiento = CMMotionActivityManager()
  private var sumidero: FlutterEventSink?
  private var ultimo: String?

  /// 🔴 La clave no se toca en el hilo principal: el Secure Enclave es otro procesador, y
  /// crear una clave o firmar puede tardar decenas de ms (más con el sistema cargado). En el
  /// hilo principal eso congela la interfaz y, con los hilos fusionados de Flutter, también
  /// a Dart. Una cola serie propia; la respuesta vuelve al principal.
  private let colaDeLaClave = DispatchQueue(label: "hz.rastreo.clave", qos: .utility)

  private func enSegundoPlano(_ que: String, _ result: @escaping FlutterResult,
                              _ trabajo: @escaping () throws -> Any?) {
    let encolado = DispatchTime.now().uptimeNanoseconds
    colaDeLaClave.async {
      let inicio = DispatchTime.now().uptimeNanoseconds
      let salida: Any?
      do { salida = try trabajo() } catch {
        salida = FlutterError(code: "rastreo", message: "\(error)", details: nil)
      }
      let fin = DispatchTime.now().uptimeNanoseconds
      NSLog("HzRastreoHilo %@ principal=%@ trabajo=%.1fms espera=%.1fms", que,
            Thread.isMainThread ? "true" : "false",
            Double(fin - inicio) / 1e6, Double(inicio - encolado) / 1e6)
      DispatchQueue.main.async { result(salida) }
    }
  }

  init(mensajero: FlutterBinaryMessenger) {
    canal = FlutterMethodChannel(name: "hz_collection_sdk/rastreo", binaryMessenger: mensajero)
    eventos = FlutterEventChannel(name: "hz_collection_sdk/rastreo/actividad",
                                  binaryMessenger: mensajero)
    super.init()
    canal.setMethodCallHandler { [weak self] llamada, resultado in
      self?.atender(llamada, resultado)
    }
    eventos.setStreamHandler(self)
  }

  private func atender(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "clave.asegurar":
        let alias = args["alias"] as? String ?? ""
        enSegundoPlano("clave.asegurar", result) { [unowned self] in
          try self.asegurarClave(alias: alias)
        }
      case "clave.firmar":
        let datos = (args["datos"] as? FlutterStandardTypedData)?.data ?? Data()
        let alias = args["alias"] as? String ?? ""
        enSegundoPlano("clave.firmar(\(datos.count)B)", result) { [unowned self] in
          try self.firmar(alias: alias, datos: datos)
        }
      case "clave.borrar":
        let alias = args["alias"] as? String ?? ""
        enSegundoPlano("clave.borrar", result) { [unowned self] in
          SecItemDelete(self.consulta(alias: alias) as CFDictionary)
          return nil
        }
      case "reloj":
        // CLOCK_MONOTONIC en Darwin cuenta el tiempo dormido. iOS no tiene contador de
        // arranques: se devuelve -1 y Dart lo cuenta.
        result(["mono": Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000), "arranques": -1])
      case "energia":
        result([
          "ahorro": ProcessInfo.processInfo.isLowPowerModeEnabled,
          "fabricante": "Apple",
          "modelo": UIDevice.current.model,
        ])
      case "energia.abrirAjustes":
        if let u = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(u)
        }
        result(nil)
      case "actividad.permiso":
        result(CMMotionActivityManager.authorizationStatus() == .authorized)
      case "actividad.pedirPermiso":
        // iOS pregunta solo la primera vez que se consulta. Se consulta una hora vieja
        // para disparar el diálogo sin arrancar el flujo.
        guard CMMotionActivityManager.isActivityAvailable(), declaroMovimiento() else {
          result(false); return
        }
        movimiento.queryActivityStarting(from: Date(timeIntervalSinceNow: -60), to: Date(),
                                         to: .main) { _, _ in
          result(CMMotionActivityManager.authorizationStatus() == .authorized)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "rastreo", message: "\(error)", details: nil))
    }
  }

  // ── La clave ─────────────────────────────────────────────────────────────────────

  private func consulta(alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    ]
  }

  private func privada(alias: String) -> SecKey? {
    var q = consulta(alias: alias)
    q[kSecReturnRef as String] = true
    var ref: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess, let r = ref else {
      return nil
    }
    return (r as! SecKey)
  }

  private func asegurarClave(alias: String) throws -> [String: Any] {
    var enHardware = false
    var clave = privada(alias: alias)
    if clave == nil {
      func crear(_ enclave: Bool) throws -> SecKey {
        var err: Unmanaged<CFError>?
        guard let acceso = SecAccessControlCreateWithFlags(
          nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
          enclave ? .privateKeyUsage : [], &err) else {
          throw err!.takeRetainedValue() as Error
        }
        var atributos: [String: Any] = [
          kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
          kSecAttrKeySizeInBits as String: 256,
          kSecPrivateKeyAttrs as String: [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: alias.data(using: .utf8)!,
            kSecAttrAccessControl as String: acceso,
          ],
        ]
        if enclave { atributos[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave }
        guard let k = SecKeyCreateRandomKey(atributos as CFDictionary, &err) else {
          throw err!.takeRetainedValue() as Error
        }
        return k
      }
      do {
        clave = try crear(true)
      } catch {
        clave = try crear(false) // simulador, o un aparato sin enclave
      }
    }
    guard let k = clave, let publica = SecKeyCopyPublicKey(k) else {
      throw NSError(domain: "rastreo", code: 1, userInfo: [NSLocalizedDescriptionKey: "sin clave"])
    }
    let atributos = SecKeyCopyAttributes(k) as? [String: Any] ?? [:]
    enHardware = (atributos[kSecAttrTokenID as String] as? String) == (kSecAttrTokenIDSecureEnclave as String)
    var err: Unmanaged<CFError>?
    guard let x963 = SecKeyCopyExternalRepresentation(publica, &err) as Data? else {
      throw err!.takeRetainedValue() as Error
    }
    // iOS da la pública en X9.63 (04 || X || Y, 65 bytes). Se le antepone la cabecera SPKI
    // fija de una P-256 para que quede igual que la de Android y la de la ingesta.
    let cabecera: [UInt8] = [
      0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
      0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
    let spki = Data(cabecera) + x963
    return ["publica": spki.base64EncodedString(), "hardware": enHardware]
  }

  /// ES256 de los bytes: `ecdsaSignatureMessageX962SHA256` hashea adentro y da la firma DER.
  private func firmar(alias: String, datos: Data) throws -> String {
    guard let k = privada(alias: alias) else {
      throw NSError(domain: "rastreo", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No hay clave del aparato: hay que enrolar"])
    }
    var err: Unmanaged<CFError>?
    guard let f = SecKeyCreateSignature(k, .ecdsaSignatureMessageX962SHA256, datos as CFData, &err)
      as Data? else {
      throw err!.takeRetainedValue() as Error
    }
    return f.base64EncodedString()
  }

  // ── La actividad ─────────────────────────────────────────────────────────────────

  private func declaroMovimiento() -> Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") != nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    guard CMMotionActivityManager.isActivityAvailable() else {
      return FlutterError(code: "actividad", message: "El aparato no tiene actividad", details: nil)
    }
    guard declaroMovimiento() else {
      return FlutterError(code: "sin_permiso",
                          message: "La aplicación no declaró NSMotionUsageDescription", details: nil)
    }
    sumidero = events
    movimiento.startActivityUpdates(to: .main) { [weak self] a in
      guard let self = self, let a = a, a.confidence != .low else { return }
      let tipo: String
      if a.automotive { tipo = "vehiculo" }
      else if a.cycling { tipo = "bici" }
      else if a.running { tipo = "corriendo" }
      else if a.walking { tipo = "aPie" }
      else if a.stationary { tipo = "quieto" }
      else { return }
      // Sólo las transiciones, igual que en Android.
      if tipo != self.ultimo {
        self.ultimo = tipo
        self.sumidero?(tipo)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    movimiento.stopActivityUpdates()
    sumidero = nil
    ultimo = nil
    return nil
  }
}
