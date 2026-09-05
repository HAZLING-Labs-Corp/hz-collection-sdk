import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'api_client.dart';

/// DÓNDE ESTÁ LA PERSONA, CUANDO ELLA LO PERMITE
///
/// Sirve para dos cosas concretas: segmentar un envío por zona sin que el
/// comercio tenga que mandar la ciudad de cada quien, y ver por dónde anduvo.
///
/// ══ SÓLO APROXIMADA, Y ES UNA DECISIÓN ══
///
/// Se pide `Permission.locationWhenInUse`, que en Android es la aproximada.
/// La precisa la acepta ~25% de la gente contra ~40% la aproximada, y la de
/// segundo plano ~10% **más un video justificando el uso ante Google**, con
/// revisión manual que se rechaza seguido.
///
/// Decisión de Juan, 2026-08-31: *«lo que sea muy difícil de aceptar en esta
/// versión no lo hagan»*. Para saber en qué ciudad está alguien, la aproximada
/// alcanza y sobra.
///
/// ══ 🔴 NO SE PIDE JUNTO CON EL DE NOTIFICACIONES ══
///
/// Dos diálogos del sistema seguidos, apenas se abre la aplicación, es la forma
/// más rápida de que la persona diga que no a los dos. El de notificaciones es
/// el que hace falta para el producto; el de ubicación es opcional y mejora la
/// segmentación. Por eso este se pide **después**, y sólo si el comercio lo
/// activó.
///
/// ══ CADA CUÁNTO SE ACTUALIZA ══
///
/// Al abrir la aplicación, con un freno de [minimoEntreLecturas]. Continuo
/// gasta batería y hace que Android muestre el ícono de ubicación activa — que
/// es exactamente lo que lleva a la gente a revocar el permiso.
class Ubicacion {
  Ubicacion(this._api);

  final AkPushApi _api;

  /// Cada cuánto se vuelve a leer.
  ///
  /// 🔴 **Eran seis horas y son dos, desde el 2026-09-05.** Seis alcanzaban para «en qué
  /// ciudad está», que era el objetivo original. Dejaron de alcanzar cuando la pregunta pasó
  /// a ser **cuánto se mueve**: con ese freno, alguien que abre la aplicación tres veces en
  /// una mañana deja **una sola** lectura, y una lectura no distingue a quien se quedó en su
  /// casa de quien cruzó la ciudad.
  ///
  /// No cuesta batería: se sigue leyendo **sólo cuando la persona abre la aplicación**, nunca
  /// en segundo plano. Lo que cambia es cuántas de esas aperturas dejan marca.
  static const minimoEntreLecturas = Duration(hours: 2);

  DateTime? _ultimaLectura;

  /// 🔴 POR QUÉ NO SE MANDÓ LA ÚLTIMA POSICIÓN.
  ///
  /// Existe porque el silencio de este módulo ya costó tres diagnósticos a mano en un
  /// solo día. `reportarSiCorresponde` no tumba nada —y está bien: perder una posición
  /// cuesta un dato de segmentación, que falle el arranque cuesta que esa persona no
  /// reciba nada— pero hasta hoy ese silencio era total: la consola mostraba «con
  /// permiso, cero ubicaciones» y no había forma de saber si faltaba el permiso, si el
  /// teléfono tenía la ubicación apagada, si el GPS no enganchó o si el servidor
  /// rechazó. Cuatro causas distintas, cuatro arreglos distintos, cero pistas.
  ///
  /// Ahora queda acá y sale en el diagnóstico.
  String? ultimoMotivo;

  /// Cuándo se mandó una posición por última vez. `null` = nunca.
  DateTime? ultimoEnvio;

  /// ¿Ya está concedido?
  ///
  /// 🔴 Se pregunta con `geolocator` y no con `permission_handler`, y no es indistinto:
  /// `permission_handler` declara `MANAGE_EXTERNAL_STORAGE` y
  /// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` en su propio manifest, y el fusionador de
  /// Android los inyecta en **cualquier aplicación que instale este SDK**, la use o no.
  /// El primero además obliga a llenar un formulario especial en Google Play.
  ///
  /// Es exactamente el error que le vimos a CredoLab en Credit CX: permisos declarados
  /// que la aplicación nunca pide, arruinando la ficha por datos que jamás va a obtener.
  /// `geolocator` hace lo mismo sin declarar nada.
  Future<bool> get concedido async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// 🔴 ¿EL TELÉFONO TIENE LA UBICACIÓN PRENDIDA?
  ///
  /// Es una pregunta DISTINTA de si la aplicación tiene permiso, y confundirlas cuesta
  /// caro. Medido el 2026-08-31 en un HONOR real: la persona aceptó el modal, aceptó el
  /// diálogo del sistema, el permiso quedó concedido — y no llegó ni una posición,
  /// porque el interruptor de ubicación del teléfono estaba apagado. En la consola eso
  /// se ve como «con permiso, cero posiciones», que parece un sistema roto.
  ///
  /// Y no se arregla pidiendo el permiso de nuevo: el permiso ya está. Lo que hay que
  /// hacer es ofrecerle prender la ubicación del teléfono, que es otro botón y otra
  /// pantalla de ajustes.
  Future<bool> get servicioPrendido => Geolocator.isLocationServiceEnabled();

  /// Abre los ajustes de UBICACIÓN del teléfono — no los de la aplicación.
  ///
  /// Son dos pantallas distintas: `openAppSettings` lleva a los permisos de esta
  /// aplicación, que en este caso ya están bien. Mandar ahí a alguien cuyo problema es
  /// el interruptor general es mandarlo a mirar algo que ya está en verde.
  Future<bool> abrirAjustesDeUbicacion() => Geolocator.openLocationSettings();

  /// ¿Se puede todavía preguntar, o la persona ya dijo que no para siempre?
  ///
  /// La diferencia importa: a quien nunca se le preguntó hay que preguntarle;
  /// a quien lo denegó permanentemente sólo le queda los Ajustes, e insistir
  /// con un diálogo que el sistema ya no muestra no hace nada salvo confundir
  /// a quien programa.
  Future<bool> get sePuedePreguntar async {
    final p = await Geolocator.checkPermission();
    // `deniedForever` es el «no» definitivo: el sistema ya no muestra el diálogo.
    return p != LocationPermission.deniedForever &&
        p != LocationPermission.always &&
        p != LocationPermission.whileInUse;
  }

  /// Pide el permiso. Devuelve si quedó concedido.
  ///
  /// Se llama cuando la aplicación lo decide —después de explicar para qué
  /// sirve— y nunca en el arranque en frío.
  Future<bool> pedir() async {
    final p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Lee la posición y la manda, si corresponde.
  ///
  /// No hace nada si no hay permiso o si se leyó hace poco. Devuelve si mandó
  /// algo, para que la aplicación pueda mostrarlo en su diagnóstico.
  ///
  /// 🔴 Nunca tumba nada: perder una posición cuesta un dato de segmentación;
  /// que falle el arranque de la aplicación cuesta que esa persona no reciba
  /// nada.
  Future<bool> reportarSiCorresponde(String userId, {bool forzar = false}) async {
    try {
      if (!await concedido) {
        ultimoMotivo = 'la aplicación no tiene permiso de ubicación';
        return false;
      }
      if (!await servicioPrendido) {
        ultimoMotivo = 'el teléfono tiene la ubicación apagada';
        return false;
      }

      final ahora = DateTime.now();
      if (!forzar &&
          _ultimaLectura != null &&
          ahora.difference(_ultimaLectura!) < minimoEntreLecturas) {
        ultimoMotivo = 'se leyó hace poco; la próxima lectura toca en '
            '${minimoEntreLecturas.inHours - ahora.difference(_ultimaLectura!).inHours} h';
        return false;
      }

      final p = await _leer();
      if (p == null) {
        // Pasa de verdad: en un lugar sin señal, con el GPS recién prendido, o cuando
        // el sistema todavía no tiene ninguna posición en caché. No es un error de
        // nadie y se resuelve solo en el próximo intento.
        ultimoMotivo = 'el sistema no devolvió ninguna posición en '
            '${_tiempoMaximo.inSeconds} s';
        return false;
      }

      await _api.reportarUbicacion(userId: userId, posicion: p);
      _ultimaLectura = ahora;
      ultimoEnvio = ahora;
      ultimoMotivo = null;
      return true;
    } catch (e) {
      // El motivo se guarda; el error no se propaga. Ver el comentario de arriba.
      ultimoMotivo = 'falló al leer o al enviar: $e';
      return false;
    }
  }

  /// Lee la posición del sistema.
  ///
  /// 🔴 CON PRECISIÓN BAJA A PROPÓSITO. `LocationAccuracy.low` le pide al
  /// sistema la posición por antenas y wifi en vez de encender el GPS: llega en
  /// un segundo, no gasta batería y da unos cientos de metros — que para saber
  /// en qué ciudad y qué zona está alguien sobra. Pedir alta precisión enciende
  /// el GPS, tarda, y muestra el ícono de ubicación activa que es lo que lleva
  /// a la gente a revocar el permiso.
  ///
  /// Y con un tiempo máximo: sin él, en un lugar sin señal esto queda esperando
  /// para siempre y el arranque de la aplicación se cuelga con él.
  static const _tiempoMaximo = Duration(seconds: 12);

  Future<Map<String, dynamic>?> _leer() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final p = await _posicion();
    if (p == null) return null;

    return {
      'lat': p.latitude,
      'lon': p.longitude,
      'precision': p.accuracy,
      // Se declara lo que se pidió, no lo que llegó: el sistema puede entregar
      // una posición más precisa si la persona ya se la había dado a la
      // aplicación por otro motivo, y decir «precisa» sobre algo que pedimos
      // aproximado sería afirmar de más.
      'exactitud': 'aproximada',
      'cuando': p.timestamp.toUtc().toIso8601String(),
    };
  }

  /// TRES INTENTOS, DE MÁS BARATO A MÁS CARO. Devuelve `null` si ninguno da.
  ///
  /// 🔴 SUBIR LA PRECISIÓN PEDIDA **NO** ROMPE LA PROMESA DE «SÓLO LA ZONA», y conviene
  /// entender por qué antes de tocar esto: con sólo `ACCESS_COARSE_LOCATION` concedido,
  /// Android **redondea la respuesta a unos 2 km pase lo que pase**. El permiso es el
  /// techo, no lo que pedimos. Sin `ACCESS_FINE_LOCATION` —que este SDK no declara ni
  /// pide— no hay forma de obtener la dirección de nadie, aunque se pida `best`.
  ///
  /// Por qué hacen falta los tres:
  ///
  ///  1. `low` usa sólo las antenas de telefonía. Es instantáneo y no gasta batería,
  ///     pero **hay teléfonos y lugares donde simplemente no devuelve nada** — medido
  ///     el 2026-08-31: `TimeoutException after 0:00:12` y ni una posición en toda la
  ///     sesión, con permiso concedido y ubicación prendida.
  ///  2. `medium` agrega el wifi. Es el que anda en la mayoría de los casos donde el
  ///     primero falla, y sigue sin encender el GPS.
  ///  3. La última conocida, que el sistema ya tiene guardada. Llega al instante, puede
  ///     ser de hace horas — y para saber en qué ciudad está alguien, eso alcanza. Vale
  ///     mucho más que no mandar nada.
  Future<Position?> _posicion() async {
    for (final precision in [LocationAccuracy.low, LocationAccuracy.medium]) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: precision,
            timeLimit: _tiempoMaximo,
          ),
        );
      } catch (_) {
        // Se prueba el siguiente. El motivo del fallo final lo anota quien llama.
      }
    }
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}
