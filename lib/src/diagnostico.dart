import 'package:firebase_core/firebase_core.dart';

import 'errors.dart';
import 'permiso.dart';
import 'remote_config.dart';

/// El eslabón de la cadena que está cortado.
///
/// Va aparte de la frase para que el soporte pueda AGRUPAR: cien tickets con
/// cien redacciones distintas no dicen nada; cien tickets que dicen `permiso`
/// dicen que hay que arreglar cuándo se pide el permiso.
enum Eslabon { configuracion, firebase, permiso, token, registro, ninguno }

/// Si la aplicación sabe qué cuenta de Google le tocó.
class EstadoDeLaConfiguracion {
  const EstadoDeLaConfiguracion({
    required this.hay,
    required this.vieneDelServidor,
    this.version,
    this.comercio,
  });

  /// Si hay configuración utilizable, venga de donde venga.
  final bool hay;

  /// `false` significa que se está trabajando con la que quedó guardada del
  /// arranque anterior. No es una falla —para eso está la caché— pero cambia el
  /// diagnóstico: si el comercio cambió de cuenta de Google hoy, este teléfono
  /// todavía no se enteró.
  final bool vieneDelServidor;

  /// Huella de la configuración. Es el dato que más rápido cierra un ticket:
  /// dos teléfonos con versiones distintas están hablando con cuentas distintas.
  final String? version;

  final String? comercio;

  bool get vieneDeLaCache => hay && !vieneDelServidor;

  bool get estaBien => hay;

  Map<String, dynamic> toJson() => {
        'hay': hay,
        'origen': !hay
            ? 'ninguno'
            : vieneDelServidor
                ? 'servidor'
                : 'cache',
        'version': version,
        'comercio': comercio,
      };
}

/// Si el transporte quedó conectado, y a qué cuenta.
class EstadoDeFirebase {
  const EstadoDeFirebase({
    required this.inicializado,
    this.projectId,
    this.appId,
    this.projectIdEsperado,
    this.appIdEsperado,
  });

  /// Si existe la app **por defecto** de Firebase, que es la única con la que
  /// trabaja el transporte de notificaciones.
  final bool inicializado;

  /// La cuenta con la que Firebase quedó inicializado DE VERDAD, leída del
  /// proceso y no de lo que el SDK cree haber hecho.
  final String? projectId;
  final String? appId;

  /// La cuenta que el servidor dijo que le toca a este comercio.
  final String? projectIdEsperado;
  final String? appIdEsperado;

  /// Que las dos cuentas no coincidan es el fallo más caro y más mudo de todos:
  /// la aplicación arranca, pide su token y lo consigue, pero ese token
  /// pertenece a otro proyecto y ningún envío del comercio va a alcanzarlo
  /// jamás. Sin comparar las dos, esto se ve exactamente igual que «todo bien».
  bool get coincideConLaConfiguracion =>
      appIdEsperado == null || appId == appIdEsperado;

  bool get estaBien => inicializado && coincideConLaConfiguracion;

  Map<String, dynamic> toJson() => {
        'inicializado': inicializado,
        'projectId': projectId,
        'appId': appId,
        'projectIdEsperado': projectIdEsperado,
        'appIdEsperado': appIdEsperado,
        'coincide': coincideConLaConfiguracion,
      };
}

/// Si el teléfono tiene una dirección a la cual enviarle.
class EstadoDelToken {
  const EstadoDelToken({required this.hay, this.obtenidoEl, this.huella});

  final bool hay;

  /// Cuándo se consiguió. Un token de hace semanas en un teléfono que se
  /// reinstaló no es el que el servidor tiene anotado.
  final DateTime? obtenidoEl;

  /// Principio y fin del token, nada más. El token entero pegado en un ticket
  /// queda en un chat, en un correo y en el historial de una herramienta de
  /// soporte para siempre; con el principio y el fin alcanza para comparar dos
  /// teléfonos, que es lo único para lo que se lo mira.
  final String? huella;

  bool get estaBien => hay;

  Map<String, dynamic> toJson() => {
        'hay': hay,
        'obtenidoEl': obtenidoEl?.toUtc().toIso8601String(),
        'huella': huella,
      };
}

/// Si el servidor sabe de quién es este teléfono.
class EstadoDelRegistro {
  const EstadoDelRegistro({
    required this.registrado,
    this.userId,
    this.registradoEl,
  });

  /// Si el alta llegó al servidor. No es lo mismo que tener [userId]: la
  /// fachada guarda el usuario aunque el alta no haya salido, justamente para
  /// poder reintentarla.
  final bool registrado;

  final String? userId;
  final DateTime? registradoEl;

  bool get estaBien => registrado;

  Map<String, dynamic> toJson() => {
        'registrado': registrado,
        'userId': userId,
        'registradoEl': registradoEl?.toUtc().toIso8601String(),
      };
}

/// Por qué no llegan los push.
///
/// «No me llegan los push» es la primera pregunta de toda integración y hasta
/// acá no tenía respuesta: la cadena tiene cinco eslabones —configuración,
/// Firebase, permiso, token, registro— y desde afuera los cinco fallos se ven
/// idénticos, que es no ver nada. [quePasa] elige el PRIMER eslabón cortado y
/// dice qué hacer, en castellano, para que el ticket llegue con la respuesta
/// adentro en vez de con una captura de una pantalla vacía.
///
/// ## Mira, no toca
///
/// Este objeto **no tiene efectos**: no pide permiso, no inicializa Firebase, no
/// pide token, no registra, no da de baja y no reporta nada al servidor. Sólo
/// lee estado que ya existe —los campos de la fachada, las apps de Firebase que
/// ya están en el proceso, lo que quedó guardado en el disco y el estado del
/// permiso vía [GestorDePermiso.estadoActual], que está documentado como que no
/// dispara ningún diálogo—.
///
/// Es a propósito, por dos razones:
///
///  - Un diagnóstico que arregla es un diagnóstico que miente: la próxima vez
///    que se lo corre el síntoma ya no está, y nadie sabe si se arregló solo o
///    lo arregló mirarlo.
///  - Sobre todo: llamar a `pedir()` desde un botón de «diagnosticar» le quema a
///    la aplicación su única oportunidad de pedirle el permiso a la persona. El
///    diálogo del sistema se gasta una sola vez, y gastarlo diagnosticando es
///    romper el eslabón que se estaba tratando de medir.
class Diagnostico {
  const Diagnostico({
    required this.configuracion,
    required this.firebase,
    required this.permiso,
    required this.token,
    required this.registro,
    this.ubicacion,
    this.ultimoError,
  });

  final EstadoDeLaConfiguracion configuracion;
  final EstadoDeFirebase firebase;

  /// Vocabulario de `permiso.dart`: quien diagnostica y quien pide el permiso
  /// tienen que llamar a las cosas igual, o el diagnóstico manda a arreglar algo
  /// que la aplicación llama de otra manera.
  final EstadoDelPermiso permiso;

  final EstadoDelToken token;
  final EstadoDelRegistro registro;

  /// Cómo va la ubicación, y **por qué no se mandó** la última vez.
  ///
  /// Es `null` cuando el comercio no tiene la ubicación activada, que es el estado por
  /// omisión: mostrar «sin ubicaciones» a quien nunca la pidió sería un error inventado.
  final EstadoDeUbicacion? ubicacion;

  /// El último [AkPushError] que el SDK se tragó para no romperle el arranque a
  /// la aplicación. Sin esto queda enterrado: la fachada silencia a propósito
  /// los fallos de permiso, de token y de alta, y ese silencio es justamente lo
  /// que deja al integrador sin ninguna pista.
  final AkPushError? ultimoError;

  /// Devuelve la misma foto con la ubicación puesta. Ver el comentario en `ak_push.dart`.
  Diagnostico conUbicacion(EstadoDeUbicacion? u) => Diagnostico(
        configuracion: configuracion,
        firebase: firebase,
        permiso: permiso,
        token: token,
        registro: registro,
        ubicacion: u,
        ultimoError: ultimoError,
      );

  /// Arma la foto. Es asíncrono sólo porque lee el disco y el estado del
  /// permiso.
  ///
  /// Tres cosas las lee por su cuenta en vez de recibirlas, y cada una por un
  /// motivo:
  ///
  ///  - **Las apps de Firebase del proceso**, porque es la única forma de ver
  ///    con qué cuenta quedó inicializado DE VERDAD.
  ///  - **Lo guardado en [ConfigStore]**, porque el caso que más importa
  ///    diagnosticar es justamente aquel en el que `init()` no terminó y la
  ///    fachada no tiene nada en memoria.
  ///  - **El permiso**, porque el que la fachada guardó es el del arranque, y el
  ///    permiso se apaga desde los Ajustes del teléfono sin que nada le avise a
  ///    la aplicación. Diagnosticar con el valor viejo diría «permiso concedido»
  ///    justo en el caso que más se reporta.
  ///
  /// [permiso] existe igual para poder pasar un estado ya leído y no pagar dos
  /// veces el salto al canal nativo.
  static Future<Diagnostico> reunir({
    AkPushConfig? config,
    bool configPedidaAlServidor = false,
    EstadoDelPermiso? permiso,
    String? token,
    DateTime? tokenObtenidoEl,
    String? userId,
    bool registradoEnElServidor = false,
    DateTime? registradoEl,
    AkPushError? ultimoError,
    ConfigStore? almacen,
    GestorDePermiso? gestorDePermiso,
  }) async {
    final store = almacen ?? ConfigStore();

    // Si la fachada no tiene nada en memoria, se cae a lo guardado. Un
    // diagnóstico que dice «no hay token» porque `init()` explotó antes de
    // leerlo manda a buscar el problema al lugar equivocado.
    final configEnUso = config ?? await _sinRomperse(store.leer());
    final tokenEnUso = token ?? await _sinRomperse(store.leerToken());
    final userIdEnUso = userId ?? await _sinRomperse(store.leerUsuario());

    final permisoLeido = permiso ??
        await _sinRomperse(
          (gestorDePermiso ?? GestorDePermiso()).estadoActual(),
        );

    // `sinPreguntar` es el estado que no cierra ningún camino, y por eso es el
    // que corresponde cuando no se pudo leer nada: decir «denegado para
    // siempre» sin saberlo manda a la persona a los Ajustes a arreglar un
    // problema que no es suyo.
    final permisoEnUso = permisoLeido ?? EstadoDelPermiso.sinPreguntar;

    return Diagnostico(
      configuracion: EstadoDeLaConfiguracion(
        hay: configEnUso != null,
        vieneDelServidor: configEnUso != null && configPedidaAlServidor,
        version: configEnUso?.version,
        comercio: configEnUso?.comercio,
      ),
      firebase: _observarFirebase(configEnUso),
      permiso: permisoEnUso,
      token: EstadoDelToken(
        hay: tokenEnUso != null && tokenEnUso.isNotEmpty,
        obtenidoEl: tokenObtenidoEl,
        huella: _huella(tokenEnUso),
      ),
      registro: EstadoDelRegistro(
        registrado: registradoEnElServidor,
        userId: userIdEnUso,
        registradoEl: registradoEl,
      ),
      ultimoError: ultimoError,
    );
  }

  // ── La respuesta ────────────────────────────────────────────────────────

  /// El primer eslabón cortado, o [Eslabon.ninguno].
  Eslabon get eslabonRoto => _veredicto.$1;

  /// Una frase en castellano con qué está roto y qué hacer.
  String get quePasa => _veredicto.$2;

  /// Si la cadena está entera de punta a punta.
  bool get todoBien => eslabonRoto == Eslabon.ninguno;

  /// El orden importa y es el de la cadena real, no el de la comodidad: sin
  /// configuración no hay Firebase, sin Firebase no hay permiso que sirva, sin
  /// permiso no hay token y sin token no hay a quién registrar. Reportar el
  /// último fallo en vez del primero manda a arreglar un síntoma.
  (Eslabon, String) get _veredicto {
    if (!configuracion.estaBien) {
      return (Eslabon.configuracion, _frasePorConfiguracion());
    }
    if (!firebase.estaBien) return (Eslabon.firebase, _frasePorFirebase());
    if (!permiso.permiteRecibir) return (Eslabon.permiso, _frasePorPermiso());
    if (!token.estaBien) return (Eslabon.token, _frasePorToken());
    if (!registro.estaBien) return (Eslabon.registro, _frasePorRegistro());
    return (Eslabon.ninguno, _fraseTodoBien());
  }

  String _frasePorConfiguracion() {
    switch (ultimoError?.code) {
      case AkPushErrorCode.unauthorized:
        return 'La llave con la que se llamó a init() no sirve: está mal '
            'escrita, o es la llave secreta del servidor donde va la pública '
            '(la que empieza con «akp_pub_»). Sin configuración el SDK no '
            'arranca: corregí la llave y volvé a llamar a init().';
      case AkPushErrorCode.appMismatch:
        return 'El servidor no reconoce a esta aplicación: el identificador de '
            'paquete con el que está compilada no es el que quedó registrado '
            'para esta llave. Hay que darlo de alta en el panel, o revisar que '
            'la app se esté compilando con el applicationId o el bundleId que '
            'corresponde.';
      case AkPushErrorCode.network:
      case AkPushErrorCode.serviceUnavailable:
        return 'No se pudo pedir la configuración al servidor y no había '
            'ninguna guardada de antes: la primerísima instalación necesita '
            'red una sola vez. Revisá la conexión del teléfono y volvé a '
            'llamar a init().';
      default:
        return 'El SDK no tiene configuración, así que no sabe con qué cuenta '
            'de Google trabajar: o init() nunca se llamó, o todavía no '
            'terminó. Acordate de que init() es asíncrono y hay que esperarlo.';
    }
  }

  String _frasePorFirebase() {
    if (firebase.inicializado && !firebase.coincideConLaConfiguracion) {
      return 'Firebase quedó inicializado con otra cuenta '
          '(${firebase.projectId ?? 'desconocida'}) y no con la que el '
          'servidor le asignó a este comercio '
          '(${firebase.projectIdEsperado ?? 'desconocida'}): el teléfono '
          'consigue token, pero es un token de otro proyecto y ningún envío '
          'del comercio lo va a alcanzar. Sacá tu propia llamada a '
          'Firebase.initializeApp() y dejá que la haga AkPush.init().';
    }
    return 'La configuración llegó pero Firebase no quedó inicializado, así '
        'que este teléfono no tiene por dónde recibir nada. Revisá el error de '
        'init() y que la cuenta que sirve el servidor esté completa.';
  }

  String _frasePorPermiso() => switch (permiso) {
        EstadoDelPermiso.denegadoParaSiempre =>
          'La persona denegó las notificaciones y no se puede volver a '
              'preguntar desde la app. Hay que mandarla a los Ajustes del '
              'teléfono, con GestorDePermiso.abrirAjustes().',
        EstadoDelPermiso.denegado =>
          'La persona dijo que no, pero en este teléfono todavía queda un '
              'diálogo del sistema —es Android 13 o superior—. Mostrale primero '
              'tu propia pantalla explicando para qué le sirven los avisos y '
              'sólo si dice que sí llamá a GestorDePermiso.pedir(): ésa es la '
              'última oportunidad que hay.',
        EstadoDelPermiso.sinPreguntar =>
          'Todavía no se le preguntó a la persona si acepta notificaciones, y '
              'hasta que diga que sí el sistema no emite ningún token. Pedile '
              'el permiso desde una pantalla donde ya se entienda para qué '
              'sirve: el diálogo del sistema se muestra una sola vez.',
        // Los dos que sí reciben nunca llegan acá: el veredicto los deja pasar.
        _ => 'El permiso está en ${permiso.name} y desde ese estado el '
            'teléfono sí recibe avisos.',
      };

  String _frasePorToken() =>
      'El permiso está dado pero el teléfono nunca consiguió su dirección —el '
      'token—, y sin dirección no hay adónde mandarle nada. Casi siempre es '
      'falta de red en el arranque o, en iOS, la llave de APNs sin cargar en la '
      'cuenta de Firebase. Volvé a llamar a init() con conexión.';

  String _frasePorRegistro() {
    if (registro.userId == null) {
      return 'El teléfono tiene token pero nunca se llamó a identify(): el '
          'servidor no sabe de quién es este teléfono, así que no lo incluye '
          'en ningún envío. Llamá a identify() cuando la persona inicia '
          'sesión.';
    }
    return 'Se llamó a identify() con «${registro.userId}» pero el alta nunca '
        'llegó al servidor: el teléfono tiene token y nadie lo tiene anotado. '
        'Casi siempre es que no había red en ese momento. Volvé a llamar a '
        'identify() con conexión.';
  }

  String _fraseTodoBien() {
    final buffer = StringBuffer(
      'La cadena está entera: configuración ${configuracion.version ?? '?'}, '
      'permiso ${permiso.name}, token obtenido y el teléfono registrado como '
      '«${registro.userId}». Si aun así no llegan los avisos, el problema no '
      'está en el teléfono sino en el envío: revisá en el panel si el envío '
      'salió y qué contestó el proveedor.',
    );

    if (configuracion.vieneDeLaCache) {
      buffer.write(
        ' Ojo: se está trabajando con la configuración guardada porque en este '
        'arranque no se pudo pedir la del servidor, así que si el comercio '
        'cambió de cuenta de Google hoy, este teléfono todavía no se enteró.',
      );
    }

    if (permiso == EstadoDelPermiso.provisional) {
      buffer.write(
        ' Ojo: el permiso es provisional, que en iOS significa que los avisos '
        'entran al centro de notificaciones en silencio, sin sonido y sin '
        'interrumpir — llegan, pero la persona puede no verlos nunca.',
      );
    }

    if (ultimoError != null) {
      buffer.write(
        ' Quedó dando vueltas un error que el SDK se tragó: $ultimoError.',
      );
    }

    return buffer.toString();
  }

  // ── Para pegar en un ticket ─────────────────────────────────────────────

  @override
  String toString() => [
        'AkPush — diagnóstico',
        'Qué pasa: $quePasa',
        'Eslabón roto: ${eslabonRoto.name}',
        '',
        _fila('configuración', configuracion.estaBien, _detalleConfiguracion()),
        _fila('firebase', firebase.estaBien, _detalleFirebase()),
        _fila('permiso', permiso.permiteRecibir, permiso.name),
        _fila('token', token.estaBien, _detalleToken()),
        _fila('registro', registro.estaBien, _detalleRegistro()),
        // La ubicación NO es un eslabón de la cadena de avisos: que no ande no impide
        // que lleguen los push. Va abajo, y sólo si el comercio la tiene activada.
        if (ubicacion != null)
          _fila(
              'ubicación',
              // 🔴 El modo pedido que no arrancó cuenta como ROTO. Un eslabón en verde que
              // hay que leer con lupa para descubrir que está en rojo es peor que no
              // tenerlo: el que diagnostica lo saltea.
              ubicacion!.puedeUbicar && !ubicacion!.elModoNoArranco,
              _detalleUbicacion()),
        // El último error no es un eslabón y por eso no se marca ok ni ROTO: un
        // error viejo con la cadena entera no es una falla, es un antecedente.
        '  ${'último error'.padRight(14)}      ${ultimoError ?? 'ninguno'}',
      ].join('\n');

  /// Ancho fijo para que los cinco eslabones se lean como una columna. Un
  /// diagnóstico desalineado en un ticket se lee como ruido, y lo que se lee
  /// como ruido no se lee.
  static String _fila(String nombre, bool bien, String detalle) =>
      '  ${nombre.padRight(14)}${bien ? 'ok  ' : 'ROTO'}  $detalle';

  String _detalleUbicacion() {
    final u = ubicacion!;
    // 🔴 El orden importa: primero LO QUE FALTA, que es lo accionable, y después el
    // antecedente. Un diagnóstico que abre con «última: hace 3 h» y esconde «el
    // teléfono tiene la ubicación apagada» al final hace perder el tiempo a quien lo lee.
    final falta = <String>[
      if (!u.permitida) 'sin permiso',
      if (!u.servicioPrendido) 'teléfono con la ubicación apagada',
      // 🔴 Y ÉSTE ES EL QUE NO ESTABA. Con los dos interruptores en verde y el segundo plano
      // apagado por un renglón que le falta al manifiesto, el diagnóstico decía «ok» sobre
      // un comercio que cree que mide todo el día y mide una vez por sesión.
      if (u.elModoNoArranco)
        'el modo «${u.modoPedido}» NO arrancó: corre «${u.modoActivo}»',
      if (u.faltaDeclarar.isNotEmpty)
        'a la aplicación le falta declarar ${u.faltaDeclarar.join(", ")}',
    ];
    final cuando = u.ultimoEnvio == null
        ? 'nunca se mandó una posición'
        : 'última hace ${DateTime.now().difference(u.ultimoEnvio!).inMinutes} min';
    return [
      if (falta.isNotEmpty) falta.join(' + '),
      cuando,
      if (u.modoActivo != 'alEntrar')
        'modo ${u.modoActivo} · ${u.lecturasDeLaSesion} leídas / '
            '${u.enviosDeLaSesion} enviadas en esta sesión',
      if (u.ultimoMotivo != null) 'motivo: ${u.ultimoMotivo}',
    ].join(' · ');
  }

  String _detalleConfiguracion() {
    if (!configuracion.hay) return 'no hay';
    final origen = configuracion.vieneDelServidor ? 'del servidor' : 'de caché';
    final comercio = configuracion.comercio;
    return 'versión ${configuracion.version ?? '?'} · $origen'
        '${comercio != null ? ' · comercio $comercio' : ''}';
  }

  String _detalleFirebase() {
    if (!firebase.inicializado) return 'sin inicializar';
    final cuenta = '${firebase.projectId ?? '?'} · ${firebase.appId ?? '?'}';
    if (firebase.coincideConLaConfiguracion) return cuenta;
    return '$cuenta (¡no es la asignada: '
        '${firebase.projectIdEsperado ?? '?'}!)';
  }

  String _detalleToken() {
    if (!token.hay) return 'no hay';
    final cuando = token.obtenidoEl;
    return '${token.huella}'
        '${cuando != null ? ' · ${cuando.toUtc().toIso8601String()}' : ''}';
  }

  String _detalleRegistro() {
    final userId = registro.userId;
    if (userId == null) return 'sin identify()';
    if (!registro.registrado) return '«$userId» · el alta no llegó';
    final cuando = registro.registradoEl;
    return '«$userId»'
        '${cuando != null ? ' · ${cuando.toUtc().toIso8601String()}' : ''}';
  }

  /// [quePasa] y [eslabonRoto] van adentro a propósito: quien reciba esto por
  /// telemetría necesita poder agrupar por eslabón y leer la frase sin volver a
  /// calcular nada de este archivo del lado del servidor.
  Map<String, dynamic> toJson() => {
        'todoBien': todoBien,
        'eslabonRoto': eslabonRoto.name,
        'quePasa': quePasa,
        'configuracion': configuracion.toJson(),
        'firebase': firebase.toJson(),
        'permiso': permiso.name,
        'token': token.toJson(),
        'registro': registro.toJson(),
        'ultimoError': ultimoError == null
            ? null
            : {
                'code': ultimoError!.code.name,
                'message': ultimoError!.message,
                'details': ultimoError!.details,
              },
      };

  // ── Lecturas sin efectos ────────────────────────────────────────────────

  /// Lee del proceso con qué cuenta quedó Firebase DE VERDAD, en vez de confiar
  /// en lo que el SDK cree haber inicializado. Es la única manera de detectar
  /// que la aplicación inicializó Firebase por su cuenta con otra cuenta.
  static EstadoDeFirebase _observarFirebase(AkPushConfig? config) {
    FirebaseApp? porDefecto;
    try {
      for (final app in Firebase.apps) {
        if (app.name == defaultFirebaseAppName) {
          porDefecto = app;
          break;
        }
      }
    } catch (_) {
      // Sin el canal nativo levantado no hay apps que mirar. Un diagnóstico que
      // explota al diagnosticar es peor que no tener diagnóstico.
    }

    return EstadoDeFirebase(
      inicializado: porDefecto != null,
      projectId: porDefecto?.options.projectId,
      appId: porDefecto?.options.appId,
      projectIdEsperado: config?.projectId,
      appIdEsperado: config?.appId,
    );
  }

  /// Cada lectura se hace a prueba de todo, porque la herramienta que existe
  /// para explicar una falla no puede caerse con ella.
  ///
  /// El límite de tiempo no es paranoia: estas lecturas cruzan canales nativos
  /// —el disco, la mensajería— y un canal que no contesta **no lanza ninguna
  /// excepción, se queda esperando**. Sin el límite, un botón de «diagnosticar»
  /// se queda girando para siempre justo en el teléfono que estaba roto, que es
  /// el único donde importaba. Es preferible una foto con un campo en blanco a
  /// ninguna foto.
  static Future<T?> _sinRomperse<T>(
    Future<T?> lectura, {
    Duration limite = const Duration(seconds: 3),
  }) async {
    try {
      return await lectura.timeout(limite);
    } catch (_) {
      return null;
    }
  }

  static String? _huella(String? token) {
    if (token == null || token.isEmpty) return null;
    if (token.length <= 12) return token;
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }
}


/// CÓMO VA LA UBICACIÓN — SOBRE TODO, POR QUÉ NO ANDA
///
/// Existe porque este módulo falla en silencio a propósito: perder una posición cuesta
/// un dato de segmentación, que falle el arranque cuesta que esa persona no reciba nada.
/// Pero el silencio dejaba al comercio sin ninguna pista: en la consola la persona
/// figuraba «con permiso, cero ubicaciones» y las causas posibles eran cuatro, con
/// cuatro arreglos distintos:
///
///   · la aplicación no tiene el permiso        → ofrecerle el modal
///   · el teléfono tiene la ubicación apagada   → mandarlo a los ajustes del teléfono
///   · el sistema no devolvió posición          → no es de nadie, se resuelve solo
///   · el envío al servidor falló               → mirar la red o el servicio
///
/// Medido el 2026-08-31: tres diagnósticos a mano en un día para distinguir entre las
/// dos primeras. Con esto se lee.
class EstadoDeUbicacion {
  const EstadoDeUbicacion({
    required this.permitida,
    required this.servicioPrendido,
    this.ultimoEnvio,
    this.ultimoMotivo,
    this.modoPedido = 'alEntrar',
    this.modoActivo = 'alEntrar',
    this.faltaDeclarar = const [],
    this.lecturasDeLaSesion = 0,
    this.enviosDeLaSesion = 0,
  });

  /// 🔴 EL MODO QUE PIDIÓ EL COMERCIO Y EL QUE DE VERDAD ESTÁ CORRIENDO, POR SEPARADO.
  ///
  /// Que sean dos campos es todo el punto: el caso que hay que poder ver de un vistazo es
  /// «pidió segundo plano y está corriendo alEntrar», que es un comercio convencido de que
  /// mide quince días y que no tiene ni una lectura. Con un solo campo, ese caso se ve
  /// idéntico a un comercio que nunca pidió nada.
  final String modoPedido;
  final String modoActivo;

  /// Qué renglones le faltan al manifiesto de la APLICACIÓN para el segundo plano. Vacío
  /// mientras no se haya consultado, o cuando está todo declarado.
  final List<String> faltaDeclarar;

  /// Cuántas posiciones dejó esta sesión, y cuántas salieron hacia el servicio. Sirve para
  /// medir el efecto de un modo en vez de creerlo.
  final int lecturasDeLaSesion;
  final int enviosDeLaSesion;

  /// La aplicación tiene el permiso.
  final bool permitida;

  /// El teléfono tiene el interruptor de ubicación prendido. **Es otra cosa**, y las
  /// dos tienen que estar para que llegue una sola posición.
  final bool servicioPrendido;

  /// Cuándo se mandó una posición por última vez. `null` = nunca se mandó ninguna.
  final DateTime? ultimoEnvio;

  /// Por qué no se mandó la última vez. `null` = la última salió bien.
  final String? ultimoMotivo;

  /// Si la ubicación está ANDANDO — no sólo si está permitida.
  ///
  /// 🔴 Los dos interruptores puestos y cero posiciones **no es «ok»**. Visto en
  /// pantalla el 2026-08-31: el diagnóstico decía `ubicación ok` sobre un aparato que
  /// nunca había mandado una sola posición, y sólo el detalle de al lado lo desmentía.
  /// Un eslabón en verde que hay que leer con lupa para descubrir que está en rojo es
  /// peor que no tenerlo: el que diagnostica lo saltea.
  bool get puedeUbicar =>
      permitida && servicioPrendido && (ultimoEnvio != null || ultimoMotivo == null);

  /// 🔴 El modo que se pidió no está corriendo. Es distinto de «no puede ubicar»: los dos
  /// interruptores pueden estar bien y el segundo plano estar apagado igual, porque a la
  /// aplicación le falta un renglón en el manifiesto.
  bool get elModoNoArranco => modoPedido != modoActivo;

  Map<String, dynamic> toJson() => {
        'permitida': permitida,
        'servicioPrendido': servicioPrendido,
        'ultimoEnvio': ultimoEnvio?.toIso8601String(),
        'ultimoMotivo': ultimoMotivo,
        'modoPedido': modoPedido,
        'modoActivo': modoActivo,
        if (faltaDeclarar.isNotEmpty) 'faltaDeclarar': faltaDeclarar,
        'lecturasDeLaSesion': lecturasDeLaSesion,
        'enviosDeLaSesion': enviosDeLaSesion,
      };
}
