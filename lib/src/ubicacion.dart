import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'politica.dart';

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
/// ══ CADA CUÁNTO SE ACTUALIZA — TRES MODOS, Y LOS TRES CUESTAN DISTINTO ══
///
/// Por omisión: al abrir la aplicación, con un freno de [minimoEntreLecturas]. Ése es el
/// comportamiento de siempre y el que rige si el comercio no configura nada.
///
/// Los otros dos —[ModoDeLectura.enPrimerPlano] y [ModoDeLectura.enSegundoPlano]— los
/// prende el comercio desde su consola y los arranca [arrancarContinuo]. Leé el enum antes
/// de tocar nada: el segundo exige permisos que **este paquete no declara ni puede
/// declarar**, y si faltan, el modo se apaga solo y lo dice en [ultimoMotivo].
class Ubicacion with WidgetsBindingObserver {
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
    return _comoSeManda(p);
  }

  /// Cómo viaja una posición. Está aparte porque hay **dos** caminos que mandan —la lectura
  /// de `alEntrar` y el flujo continuo— y dos formatos distintos serían dos maneras de que
  /// el servicio reciba algo que no espera.
  Map<String, dynamic> _comoSeManda(Position p) => {
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

  // ═══════════════════════════════════════════════════════════════════════════════════
  // LECTURA CONTINUA — los otros dos modos
  // ═══════════════════════════════════════════════════════════════════════════════════
  //
  // Pedido de Juan, 2026-09-05: *«para un vendedor de motos: yo quiero saber qué tanto se
  // mueve en el día, y no necesariamente con la aplicación abierta»*.
  //
  // 🔴 SON DOS COSAS DISTINTAS Y ACÁ ESTÁN SEPARADAS A PROPÓSITO. El primer plano no pide
  // ningún permiso nuevo y aporta poco al movimiento; el segundo plano es el que contesta
  // la pregunta y es el que puede sacar una aplicación de Play si se declara donde no va.

  /// EL CANAL DEL PLUGIN. Es el mismo que usan las señales de nivel 0 — un plugin, un
  /// canal — y se usa para UNA sola pregunta: qué permisos declaró la aplicación
  /// anfitriona en su manifiesto. No pide nada ni lee nada de la persona.
  static const _canal = MethodChannel('hz_collection_sdk/senales');

  /// Lo que está corriendo AHORA. No es lo que el comercio pidió: si pidió segundo plano y
  /// la aplicación no declaró el permiso, acá dice [ModoDeLectura.alEntrar] y [ultimoMotivo]
  /// dice por qué.
  ModoDeLectura modoActivo = ModoDeLectura.alEntrar;

  /// Lo que el comercio pidió, aunque no se haya podido.
  ModoDeLectura modoPedido = ModoDeLectura.alEntrar;

  /// 🔴 CUÁNTAS LECTURAS DEJÓ ESTA SESIÓN. Existe para poder MEDIR el cambio en vez de
  /// creerlo: sin este número, «ahora lee más seguido» es una afirmación sin respaldo.
  int lecturasDeLaSesion = 0;

  /// De ésas, cuántas salieron de verdad hacia el servicio. Es otro número: una lectura que
  /// llega antes de que pase el intervalo se descarta acá y nunca toca la red.
  int enviosDeLaSesion = 0;

  StreamSubscription<Position>? _flujo;
  bool _observando = false;
  String? _userIdDelFlujo;
  Duration _cadaDelFlujo = Duration.zero;
  DateTime? _ultimaDelFlujo;
  TextosDeSiempre _textosDelFlujo = const TextosDeSiempre();

  /// Lo que la aplicación anfitriona **no declaró** y hace falta para el segundo plano.
  /// Vacío no significa que se pueda: significa que todavía no se preguntó. Ver
  /// [sePuedeEnSegundoPlano].
  List<String> faltaDeclarar = const [];

  bool? _sePuedeEnSegundoPlano;

  /// 🔴 ¿LA APLICACIÓN ANFITRIONA DECLARÓ LO QUE HACE FALTA PARA EL SEGUNDO PLANO?
  ///
  /// ══ POR QUÉ ESTA PREGUNTA EXISTE ══
  ///
  /// Porque **este paquete no declara `ACCESS_BACKGROUND_LOCATION` y no lo va a declarar**.
  /// Un permiso escrito en el manifiesto de un paquete se le inyecta a TODA aplicación que
  /// lo instale, la use o no — y la política de préstamos personales de Google Play es de
  /// las que sacan la app de la tienda. Una financiera que instale este SDK no puede
  /// heredar ese permiso por haberlo instalado.
  ///
  /// Entonces lo declara la aplicación, y el SDK lo **usa sólo si está**. Sin esta
  /// comprobación, un comercio prende «segundo plano» en su consola, ve el interruptor en
  /// verde, espera quince días y no mide **nada** — sin un solo error. Ése es exactamente
  /// el fallo silencioso que este método existe para no tener.
  ///
  /// Se le pregunta al sistema por el manifiesto FUSIONADO, que es el que de verdad llevó
  /// el APK. Si el canal no contesta —una prueba sin plugin, una plataforma sin implementar—
  /// la respuesta es **que no se puede**: fallar hacia el modo caro por no poder preguntar
  /// sería prender un servicio en el fondo a ciegas.
  Future<bool> get sePuedeEnSegundoPlano async {
    final ya = _sePuedeEnSegundoPlano;
    if (ya != null) return ya;
    try {
      final r = await _canal
          .invokeMapMethod<String, Object?>('puedeSegundoPlano')
          .timeout(const Duration(seconds: 3));
      faltaDeclarar =
          (r?['faltan'] as List?)?.map((e) => '$e').toList() ?? const [];
      _sePuedeEnSegundoPlano = r?['sePuede'] == true;
    } catch (e) {
      // 🔴 UN FALLO NO SE CACHEA, LA RESPUESTA SÍ. El manifiesto no cambia mientras la
      // aplicación corre, así que un «sí» o un «no» del sistema valen para siempre. Pero
      // esto se puede llamar antes de que el plugin se enganche al motor, y cachear ese
      // tropiezo dejaría el segundo plano apagado por el resto de la vida del proceso —
      // por un problema de arranque, no por lo que dice el manifiesto.
      faltaDeclarar = ['no se le pudo preguntar al sistema qué declaró el manifiesto: $e'];
      return false;
    }
    return _sePuedeEnSegundoPlano!;
  }

  /// ¿Está concedido el «Permitir siempre»?
  ///
  /// 🔴 `LocationPermission.always` sólo aparece si la aplicación declaró
  /// `ACCESS_BACKGROUND_LOCATION` **y** la persona lo aceptó. Sin la declaración, geolocator
  /// devuelve `whileInUse` como techo, pase lo que pase.
  Future<bool> get tieneSiempre async =>
      (await Geolocator.checkPermission()) == LocationPermission.always;

  /// PIDE EL «SIEMPRE» — la SEGUNDA pregunta, que es otra pregunta.
  ///
  /// 🔴 NO SE PUEDE PEDIR DE ENTRADA, y no es una preferencia nuestra: desde Android 11 el
  /// sistema **no muestra** el diálogo de «permitir siempre» si la aplicación no tiene ya el
  /// de «mientras se usa», y aun teniéndolo abre la pantalla de Ajustes en vez de un
  /// diálogo, para que la persona lo elija a mano. iOS 13+ hace lo mismo con otro nombre.
  ///
  /// Por eso esto se llama **después** de [pedir], y por eso el modal que lo precede es otro
  /// —[ModalDeUbicacion.mostrarSiempre]— y no el de la zona: la persona tiene que saber que
  /// la mandan a Ajustes y qué botón buscar ahí.
  ///
  /// Devuelve si quedó en «siempre». Un `false` acá es de lo más normal: la persona salió de
  /// Ajustes sin tocar nada.
  Future<bool> pedirSiempre() async {
    if (await tieneSiempre) return true;
    // El primero tiene que estar. Pedir el de fondo sin el de uso no muestra nada.
    if (!await concedido) return false;
    final p = await Geolocator.requestPermission();
    return p == LocationPermission.always;
  }

  /// ARRANCA LA LECTURA CONTINUA. Devuelve `null` si arrancó, o **por qué no** si no.
  ///
  /// 🔴 NUNCA FALLA EN SILENCIO. Ese motivo se guarda además en [ultimoMotivo] y sale en el
  /// diagnóstico, porque el caso que hay que evitar es el comercio que cree que está
  /// midiendo quince días y no tiene ni una lectura.
  ///
  /// Es idempotente: llamarlo dos veces con el mismo modo no abre dos flujos.
  Future<String?> arrancarContinuo({
    required String userId,
    required ModoDeLectura modo,
    required Duration cada,
    TextosDeSiempre textos = const TextosDeSiempre(),
  }) async {
    modoPedido = modo;
    _textosDelFlujo = textos;

    if (modo == ModoDeLectura.alEntrar) {
      await detenerContinuo();
      return null;
    }

    // Los dos interruptores de siempre. Sin ellos no hay nada que arrancar, y el motivo es
    // distinto en cada caso: uno se arregla con un diálogo, el otro con los ajustes del
    // teléfono. Ver la nota de `servicioPrendido`.
    if (!await concedido) return _noArranco('la aplicación no tiene permiso de ubicación');
    if (!await servicioPrendido) {
      return _noArranco('el teléfono tiene la ubicación apagada');
    }

    if (modo == ModoDeLectura.enSegundoPlano) {
      // 🔴 ACÁ ES DONDE EL MODO SE APAGA SOLO. Ver `sePuedeEnSegundoPlano`.
      if (!await sePuedeEnSegundoPlano) {
        return _noArranco(
          'el segundo plano está apagado: la aplicación no declaró '
          '${faltaDeclarar.join(", ")}. Se declara en el manifiesto de la APLICACIÓN, '
          'nunca en el del SDK — ver el README, «Ubicación continua».',
        );
      }
      if (!await tieneSiempre) {
        return _noArranco(
          'la persona no dio el permiso «Permitir siempre»; sin él sólo se lee con la '
          'aplicación abierta',
        );
      }
    }

    // Idempotencia: mismo modo y mismo intervalo, no se toca nada.
    if (_flujo != null && modoActivo == modo && _cadaDelFlujo == cada) return null;
    await _cortarElFlujo();

    _userIdDelFlujo = userId;
    _cadaDelFlujo = cada;
    _ultimaDelFlujo = null;

    try {
      _flujo = Geolocator.getPositionStream(
        locationSettings: _ajustes(modo, cada, textos),
      ).listen(
        (p) => unawaited(_llegoUna(p)),
        onError: (Object e) {
          // Pasa de verdad: la persona apaga la ubicación del teléfono con la aplicación
          // en el fondo, o revoca el permiso desde Ajustes. El flujo muere y nada avisaría.
          ultimoMotivo = 'la lectura continua se cortó: $e';
          unawaited(detenerContinuo());
        },
        cancelOnError: true,
      );
    } catch (e) {
      return _noArranco('no se pudo abrir la lectura continua: $e');
    }

    modoActivo = modo;
    ultimoMotivo = null;

    // 🔴 EL PRIMER PLANO SE CORTA SOLO CUANDO LA APLICACIÓN SE VA AL FONDO — y ésa es toda
    // la diferencia con el otro modo. Sin esto, «primer plano» seguiría leyendo con la
    // aplicación cerrada usando un permiso que la persona dio para otra cosa.
    if (modo == ModoDeLectura.enPrimerPlano) _observar();
    return null;
  }

  /// Corta la lectura continua y vuelve al modo de siempre.
  ///
  /// 🔴 BAJA LOS DOS MODOS, EL ACTIVO Y EL PEDIDO. Bajar sólo el activo dejaría el
  /// diagnóstico diciendo «pidió enSegundoPlano y corre alEntrar» —o sea, ROTO— después de
  /// un corte que alguien pidió a propósito: al cerrar sesión, o desde una pantalla de
  /// «pausar el seguimiento». Un rojo por algo que se hizo bien enseña a ignorar los rojos.
  ///
  /// El corte automático al irse al fondo NO pasa por acá: ése toca `_cortarElFlujo` directo
  /// y conserva el pedido, que es lo que le permite volver a arrancar al volver al frente.
  Future<void> detenerContinuo() async {
    await _cortarElFlujo();
    modoActivo = ModoDeLectura.alEntrar;
    modoPedido = ModoDeLectura.alEntrar;
    _dejarDeObservar();
  }

  Future<void> _cortarElFlujo() async {
    final f = _flujo;
    _flujo = null;
    if (f != null) {
      try {
        await f.cancel();
      } catch (_) {
        // Cancelar un flujo ya muerto no es un problema de nadie.
      }
    }
  }

  String _noArranco(String porQue) {
    modoActivo = ModoDeLectura.alEntrar;
    ultimoMotivo = porQue;
    assert(() {
      debugPrint('[collection] ubicación continua: $porQue');
      return true;
    }());
    return porQue;
  }

  /// LLEGÓ UNA POSICIÓN DEL FLUJO.
  ///
  /// 🔴 EL RELOJ SE APLICA ACÁ, EN DART, Y NO SÓLO EN EL NATIVO. En Android `intervalDuration`
  /// pone el ritmo; en iPhone **no existe** ese parámetro —CoreLocation entrega por distancia
  /// recorrida— así que sin esta compuerta el mismo comercio con la misma configuración
  /// mandaría un puñado de posiciones por hora en Android y un chorro en iPhone. Y es además
  /// lo que protege los 60 huecos que el servicio guarda por aparato: una lectura de más no
  /// agrega información, tira la más vieja.
  Future<void> _llegoUna(Position p) async {
    lecturasDeLaSesion++;
    final ahora = DateTime.now();
    final desde = _ultimaDelFlujo;
    if (desde != null && ahora.difference(desde) < _cadaDelFlujo) return;
    _ultimaDelFlujo = ahora;

    final id = _userIdDelFlujo;
    if (id == null) return;
    try {
      await _api.reportarUbicacion(userId: id, posicion: _comoSeManda(p));
      // El freno de las dos horas comparte reloj a propósito: mientras el flujo esté
      // andando, la lectura de `alEntrar` no tiene nada que agregar.
      _ultimaLectura = ahora;
      ultimoEnvio = ahora;
      ultimoMotivo = null;
      enviosDeLaSesion++;
    } catch (e) {
      ultimoMotivo = 'falló al enviar una posición del flujo: $e';
    }
  }

  /// Los ajustes de cada plataforma. Es lo único que cambia entre los dos modos continuos.
  LocationSettings _ajustes(
    ModoDeLectura modo,
    Duration cada,
    TextosDeSiempre textos,
  ) {
    final enFondo = modo == ModoDeLectura.enSegundoPlano;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        // La misma precisión baja de siempre: antenas y wifi, sin GPS. Ver `_posicion`.
        accuracy: LocationAccuracy.low,
        // Cero a propósito: **quedarse quieto también es un dato**. Con un filtro por
        // distancia, alguien que no se mueve en todo el día no deja ni una lectura y se ve
        // igual que alguien que desinstaló la aplicación. Son cosas opuestas.
        distanceFilter: 0,
        intervalDuration: cada,
        // 🔴 EL AVISO FIJO NO ES DECORACIÓN: sin él Android no deja leer la ubicación con la
        // aplicación en el fondo. Y con él la persona ve, todo el día, que la están
        // midiendo — que es como tiene que ser.
        foregroundNotificationConfig: enFondo
            ? ForegroundNotificationConfig(
                notificationTitle: textos.avisoTitulo,
                notificationText: textos.avisoCuerpo,
                notificationChannelName: 'Ubicación en segundo plano',
                // 🔴 LOS DOS EN FALSO, Y ES LA DECISIÓN DE BATERÍA MÁS GRANDE DE ACÁ. Con
                // el wake lock puesto, el teléfono no se duerme nunca y la lectura cada
                // media hora pasa a costar como tener la pantalla apagada pero el
                // procesador despierto todo el día. Sin él, el sistema duerme y entrega las
                // lecturas juntas cuando despierta — que para «cuánto se movió» da lo
                // mismo, porque cada posición trae su propia hora.
                enableWakeLock: false,
                enableWifiLock: false,
                setOngoing: true,
              )
            : null,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.low,
        // iOS no tiene intervalo: entrega por distancia. Cien metros es lo más chico que
        // tiene sentido con precisión reducida; el ritmo de verdad lo pone la compuerta de
        // `_llegoUna`, que es la que hace que las dos plataformas se comporten igual.
        distanceFilter: 100,
        allowBackgroundLocationUpdates: enFondo,
        // La flecha azul de la barra. Se muestra a propósito, por lo mismo que el aviso fijo
        // de Android: la persona tiene que poder ver que la están midiendo.
        showBackgroundLocationIndicator: enFondo,
        // Que iOS pause solo cuando la persona lleva rato quieta. Es batería gratis: si no
        // se mueve, no hay nada nuevo que contar.
        pauseLocationUpdatesAutomatically: true,
      );
    }

    return LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 0);
  }

  // ── El ciclo de vida, sólo para el primer plano ────────────────────────────────────

  void _observar() {
    if (_observando) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observando = true;
    } catch (_) {
      // Sin binding —una prueba sin widgets— no hay ciclo de vida que escuchar. El flujo
      // sigue andando; lo único que se pierde es cortarlo al irse al fondo.
    }
  }

  void _dejarDeObservar() {
    if (!_observando) return;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _observando = false;
  }

  // El nombre va en castellano como todo el resto del paquete. El aviso del analizador es
  // sobre el nombre del parámetro de Flutter (`state`), que nadie nombra al llamar: este
  // método lo invoca el framework por posición.
  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (modoPedido != ModoDeLectura.enPrimerPlano) return;
    // Nada de esto puede lanzar hacia el framework: el ciclo de vida lo llama Flutter y una
    // excepción acá se le ve a la persona como una pantalla roja.
    unawaited(() async {
      try {
        switch (estado) {
          case AppLifecycleState.paused:
          case AppLifecycleState.detached:
            await _cortarElFlujo();
            modoActivo = ModoDeLectura.alEntrar;
          case AppLifecycleState.resumed:
            final id = _userIdDelFlujo;
            if (id != null && _flujo == null) {
              await arrancarContinuo(
                userId: id,
                modo: ModoDeLectura.enPrimerPlano,
                cada: _cadaDelFlujo,
                textos: _textosDelFlujo,
              );
            }
          default:
            // `inactive` y `hidden` pasan cada vez que baja la persiana de avisos o entra
            // una llamada. No es irse de la aplicación y no corta nada.
            break;
        }
      } catch (_) {}
    }());
  }
}
