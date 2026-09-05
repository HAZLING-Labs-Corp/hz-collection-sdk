/// LAS SEÑALES DE NIVEL 0 — todo lo que se lee del teléfono sin pedir un permiso.
///
/// Son ~90 campos, y **no salen todos del mismo lado**. Fueron cuatro investigaciones en
/// paralelo el 2026-08-31, no una:
///
///   · Los seis primeros grupos —configuración, accesibilidad, batería, sensores, perfil y
///     red— se leen de la **API pública y documentada de Android**: `Settings.Global`,
///     `Settings.Secure`, `Settings.System`, `SensorManager`, `BatteryManager`,
///     `AccessibilityManager` y `ConnectivityManager`. Cada clave de acá abajo está en
///     developer.android.com y cualquiera puede leerlas. Lo que aportó el análisis del
///     mercado fue **cuáles de las cientos que hay vale la pena mirar**, que es una decisión,
///     no un código.
///
///   · El séptimo —`hd_`, la huella digital— **no lo tiene ningún colector del mercado**, y es
///     el único grupo con respaldo independiente: del estudio de Berg, Burg, Gombovic y Puri
///     para **NBER sobre
///     270.000 compras**, donde un modelo hecho *sólo* con huella digital —tipo de aparato,
///     sistema, hora de la compra, canal— alcanzó **AUC 69,6% contra 68,3% del FICO**. Y de la
///     revisión del mercado antifraude, donde la coherencia entre idioma, zona horaria y país
///     de la SIM es la señal más barata que existe.
///
/// 🔴 Ninguna cifra publicada por un proveedor de este sector está auditada por terceros. Las
/// de NBER sí. Y **Kreditech publicitaba 20.000 puntos de datos y quebró**: más campos no es
/// mejor puntaje. Estos se eligieron por lo que aportan, no por llenar una lista.
///
/// 🔴 NINGUNO PIDE PERMISO Y NINGUNO DICE QUIÉN ES LA PERSONA. Dicen cómo está configurado
/// el aparato y si se comporta como un teléfono de verdad. Esa distinción es la que permite
/// que este módulo nazca prendido mientras ubicación y avisos nacen apagados.
///
/// 🔴 NADA DE ESTE ARCHIVO SALE DE CÓDIGO AJENO. Ni una línea, ni una clase, ni un recurso,
/// ni una biblioteca compilada de ningún otro colector entra en este repositorio — está
/// prohibido y se comprueba: `pubspec.yaml` no declara ninguna, y no hay un solo `.jar`,
/// `.aar` ni `.dex` de terceros en el árbol. Lo de abajo está escrito en Kotlin y en Dart
/// contra la API de Android, y se puede auditar línea por línea.
///
/// **Lo que deliberadamente NO se trae**, aunque el resto del sector sí:
///
///   · La lista de sensores con vendedor y resolución. Es una huella de dispositivo bastante
///     única, y Apple prohíbe la huella combinada tenga o no consentimiento. Se manda cuántos
///     hay y cuáles de los básicos existen, que es lo que separa un teléfono de un emulador.
///   · El nombre de la aplicación marcada como depurable si no es la nuestra. Es un dato de
///     terceros que no nos corresponde y no aporta al puntaje.
///   · El BSSID y el nombre de la red WiFi. Exigen permiso de ubicación desde Android 8 y
///     además dicen dónde está la persona.
///   · La lista de paquetes de accesibilidad. Se manda cuántos hay y qué pueden hacer, que es
///     lo único que importa para decir «hay una herramienta de control remoto activa».
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../permisologia/campos.dart';
import '../permisologia/transformar.dart';
import 'modulo.dart';

export '../permisologia/campos.dart' show camposDeSenales, gruposDeSenales, GrupoDeSenales, grupoDe;

class ModuloDeSenales extends Modulo {
  ModuloDeSenales();

  static const _canal = MethodChannel('hz_collection_sdk/senales');

  DateTime? _ultimaVez;
  String? _ultimoMotivo;

  /// Qué pasó con la última medición, aunque no haya sido un problema: «no se transmitió:
  /// nada cambió» es información, y sin este campo se veía igual que no haber medido.
  String? _ultimoDetalle;

  @override
  String get nombre => 'senales';

  @override
  int get nivel => Nivel.sinPermiso;

  /// Una foto al dar de alta. La configuración de un teléfono no cambia entre sesiones lo
  /// suficiente como para justificar medirla seguido.
  @override
  Cadencia get cadencia => Cadencia.episodica;

  @override
  List<String> get permisos => const [];

  @override
  Future<void> alEntrar(Contexto c) async {
    if (c.sujetoId == null) return;
    try {
      // 🔴 SE MIDE SIEMPRE Y SE TRANSMITE SI CAMBIÓ ALGO — las dos cosas son distintas.
      //
      // Medir es local y cuesta milisegundos; transmitir levanta la radio del teléfono. De
      // las 105 señales, diez cambian en cada medición —la hora local, el voltaje de la
      // batería— así que sin la política, «mandá lo que cambió» manda siempre todo. Quien
      // decide es `enviarMedicion`; acá sólo se mide y se anota qué contestó.
      final medido = await medir();
      final r = await enviarMedicion(c, nombre, medido);
      if (r.midio) _ultimaVez = DateTime.now();
      _ultimoDetalle = r.detalle;
      _ultimoMotivo = r.problema;
    } catch (e) {
      // Nunca tumba nada. Perder estas señales cuesta poder de un puntaje; que falle el
      // inicio de sesión cuesta que esa persona no reciba nada.
      _ultimoMotivo = 'falló al medir o al enviar: $e';
    }
  }

  @override
  Future<EstadoDeModulo> estado(Contexto c) async => EstadoDeModulo(
        andando: _ultimoMotivo == null,
        detalle: _ultimaVez == null
            ? 'todavía no midió'
            : 'midió hace ${DateTime.now().difference(_ultimaVez!).inMinutes} min'
                '${_ultimoDetalle != null ? " · $_ultimoDetalle" : ""}',
        ultimoMotivo: _ultimoMotivo,
        ultimaVez: _ultimaVez,
      );

  /// Mide. Público para poder probarlo sin montar toda la fachada.
  ///
  /// 🔴 ANDROID MIDE ~95 CAMPOS, iOS MIDE ~33, Y ESA DIFERENCIA NO SE DISIMULA.
  ///
  /// Hasta el 2026-09-01 esto devolvía un mapa vacío en iOS, porque el paquete declaraba
  /// sólo la plataforma `android` y nadie contestaba el canal. Ahora hay lado nativo de iOS
  /// —ver `ios/Classes/SenalesPlugin.swift`— y mide lo que la plataforma permite.
  ///
  /// Lo que NO se alcanza en iOS no se rellena con ceros: no viaja. En iOS no existen la
  /// configuración del sistema (`cfg_`), la enumeración de servicios de accesibilidad
  /// (`acc_`) ni el multiusuario (`usr_`). Devolver ceros haría que un puntaje tratara a
  /// todos los iPhone como el mismo teléfono raro — y peor: haría creer que la señal de
  /// control remoto se midió y salió negativa, cuando no se pudo medir.
  ///
  /// Quien consuma esto tiene que mirar CUÁNTOS campos llegaron antes de interpretarlos.
  Future<Map<String, Object?>> medir() async {
    if (!Platform.isAndroid && !Platform.isIOS) return const {};
    final crudo = await _canal.invokeMapMethod<String, Object?>('medir');
    if (crudo == null || crudo.isEmpty) return const {};

    // Todo pasa por la capa de transformación, igual que el resto. Acá casi todo es
    // `taICual` porque son propiedades del aparato y no texto que haya escrito nadie — pero
    // pasa por el mismo camino para que la regla no tenga excepciones.
    return armarPaquete(camposDeSenales, Map<String, Object?>.from(crudo));
  }
}
