import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, VoidCallback, debugPrint;
import 'package:flutter/material.dart'
    show BuildContext, Color, GlobalKey, NavigatorState, Widget;

import 'api_client.dart';
import 'campanita.dart';
import 'comportamiento/comportamiento.dart';
import 'decision_de_dibujo.dart';
import 'device_info.dart';
import 'diagnostico.dart';
import 'errors.dart';
import 'permiso.dart';
import 'consentimiento.dart';
import 'politica.dart';
import 'sesion.dart';
import 'modal_de_ubicacion.dart';
import 'ubicacion.dart';
import 'modulos/modulo.dart';
import 'modulos/modulo_aparato.dart';
import 'modulos/modulo_autenticidad.dart';
import 'modulos/modulo_senales.dart';
import 'modulos/registro.dart';
import 'presenter.dart';
import 'push_message.dart';
import 'remote_config.dart';
import 'ruta.dart';
import 'sujeto.dart';
import 'transmision/huella_local.dart';
import 'transmision/politica_de_transmision.dart';

/// Manejador de segundo plano.
///
/// Tiene que ser una función de nivel superior con `@pragma('vm:entry-point')`
/// para sobrevivir al recorte del árbol y poder correr en su propio aislado
/// cuando la aplicación está en segundo plano o cerrada.
///
/// Está vacío a propósito: el sistema operativo dibuja el aviso por su cuenta.
/// Medir la ENTREGA acá exigiría un cliente HTTP y una credencial propios
/// dentro del aislado, donde no hay acceso a nada de la aplicación. Queda
/// pendiente, y **mientras tanto la entrega en segundo plano no se cuenta** —
/// que es el caso más común. Es un límite conocido, no un descuido.
@pragma('vm:entry-point')
@pragma('vm:entry-point')
Future<void> manejadorDeSegundoPlano(RemoteMessage mensaje) async {
  // 🔴 Esto corre en OTRO ISOLATE. No hay `AkPush`, no hay `_api`, no hay nada
  // de lo que dejó `init()`: ese estado vive en el isolate principal y acá no
  // existe. Todo lo que haga falta hay que releerlo de `SharedPreferences`,
  // que es lo único compartido.
  //
  // Por qué vale la pena el rodeo: el caso NORMAL de una notificación es
  // llegar con la aplicación cerrada. Si sólo acusa recibo la que llega con la
  // app abierta, la consola muestra «aceptado» en la mayoría de los avisos que
  // sí llegaron, y eso se lee como una falla de entrega que no existe.
  final id = mensaje.data['pushLogId'] as String?;
  if (id == null) return;

  try {
    final credencial = await ConfigStore().leerCredencial();
    if (credencial == null) return;

    await AkPushApi(apiKey: credencial.llave, baseUrl: credencial.url)
        .reportarEvento(
      pushLogId: id,
      accion: AccionDePush.delivered.valor,
      estadoApp: 'BACKGROUND',
    );
  } catch (_) {
    // Igual que en el isolate principal: una medición nunca puede tumbar la
    // entrega del aviso. Un acuse perdido cuesta un dato.
  }
}

/// Recibir notificaciones push con una llave y una línea.
///
/// ```dart
/// await AkPush.init(apiKey: 'akp_...');
/// await AkPush.identify(userId: 'u_123');
/// ```
///
/// No se pega ningún archivo de configuración en el proyecto: la cuenta de
/// Google la sirve el servidor en cada arranque. Eso es lo que permite mover un
/// comercio de una cuenta a otra sin publicar una versión nueva.
///
/// ## Es dueño de la app de Firebase por defecto
///
/// `FirebaseMessaging` solo trabaja con la app **por defecto** de Firebase — no
/// hay API pública para usar una con nombre. Así que este paquete la
/// inicializa. Si la aplicación ya inicializó Firebase por su cuenta con otra
/// configuración, se avisa con un error claro en vez de trabajar con una cuenta
/// que no es la que el servidor asignó.
class AkPush {
  AkPush._();

  static final AkPush _yo = AkPush._();

  /// Lo que el comercio configuró. Hasta que el servicio sirva el campo, es la
  /// que reproduce el comportamiento de siempre.
  PoliticaDeNotificaciones _politica = PoliticaDeNotificaciones.comoEstabaAntes;
  PoliticaDeUbicacion _politicaDeUbicacion = const PoliticaDeUbicacion();
  final ValueNotifier<EstadoDeAvisos?> _avisos = ValueNotifier(null);

  EstadoDeAvisos _publicarAvisos(EstadoDeAvisos e) {
    _avisos.value = e;
    // El servidor tiene que enterarse de que esta persona apagó —o encendió— los
    // avisos. Si no, se le sigue enviando a un teléfono que no muestra nada y las
    // estadísticas dicen «entregado» sobre algo que nadie vio.
    unawaited(_reconciliar());
    return e;
  }


  /// La última vez que se registró, para no repetir una llamada que no cambia
  /// nada — y para que la huella venza y se revalide sola.
  HuellaDelRegistro? _huella;

  /// Qué se le preguntó y qué contestó. Se lee del disco al arrancar y
  /// sobrevive al cierre de sesión: el permiso es del teléfono, no de quien entra.
  Consentimiento _consentimiento = const Consentimiento();

  AkPushApi? _api;

  /// Se arma junto con el cliente, en `init()`. Antes de eso no hay a quién
  /// mandarle la posición.
  Ubicacion? _ubicacionInterna;
  Ubicacion get _ubicacion {
    final u = _ubicacionInterna;
    if (u == null) {
      throw StateError(
        'Hay que llamar a AkPush.init() antes de usar la ubicación: sin el '
        'cliente no hay a dónde mandarla.',
      );
    }
    return u;
  }
  AkPushConfig? _config;
  final ConfigStore _almacen = ConfigStore();

  /// Una sola instancia para todo el paquete: cachea el nivel de Android que
  /// hace falta para saber si un «no» todavía admite otro diálogo, y ese dato
  /// se consulta en cada vuelta del segundo plano.
  final GestorDePermiso _permiso = GestorDePermiso();

  /// El portero no depende de nada del arranque, así que se construye ya: el
  /// callback se puede registrar antes de `init()` sin que nada lo pise.
  final PorteroDeDibujo _portero = PorteroDeDibujo();

  /// LA POLÍTICA DE TRANSMISIÓN — qué se manda y cuándo. Ver
  /// `transmision/politica_de_transmision.dart`.
  ///
  /// Se construye acá y no en `init()` porque no depende de nada del arranque, y porque
  /// `AkPush.formulario(...)` tiene que poder llamarse desde el `initState` de una pantalla
  /// sin importar si el SDK ya terminó de arrancar: lo que se anote antes queda en la cola
  /// igual, y sale cuando haya con quién hablar.
  PoliticaDeTransmision _politicaDeTransmision = PoliticaDeTransmision.porOmision;
  PorteroDeEnvio _porteroDeEnvio = PorteroDeEnvio();
  Comportamiento _comportamiento = Comportamiento();

  /// Cambia la política antes de que nada la haya usado. Se llama sólo desde `init()`, y
  /// sólo si quien integra pasó una: sin eso, rige la de omisión y nadie ve un cambio.
  void _adoptarPolitica(PoliticaDeTransmision p) {
    if (identical(p, _politicaDeTransmision)) return;
    _politicaDeTransmision = p;
    _porteroDeEnvio = PorteroDeEnvio(politica: p);
    // El anterior suelta el gancho del ciclo de vida o quedarían dos escuchando, y cada
    // apertura de la aplicación anotaría dos `SESION_ABRE`.
    _comportamiento.soltar();
    _comportamiento = Comportamiento(politica: p);
  }

  String? _token;
  String? _userId;
  EstadoDelPermiso _estado = EstadoDelPermiso.sinPreguntar;

  // ── Lo que el diagnóstico necesita saber y nadie más guardaba ────────────
  //
  // Son cinco datos que sólo la fachada puede conocer —de dónde vino la
  // configuración de ESTE arranque, cuándo se consiguió el token, si el alta
  // LLEGÓ al servidor y qué error se tragó el SDK para no romperle el arranque
  // a nadie—. Sin ellos, `diagnostico()` puede decir qué falta pero no por qué.

  bool _configDelServidor = false;
  DateTime? _tokenObtenidoEl;
  bool _registrado = false;
  DateTime? _registradoEl;
  AkPushError? _ultimoError;

  /// POR QUÉ ESTE ARRANQUE NO TIENE AVISOS, cuando todo lo demás sí funciona.
  ///
  /// 🔴 Antes esto no existía porque no hacía falta: sin configuración de Firebase el
  /// arranque entero fallaba, así que no había un estado intermedio que describir. Desde el
  /// 2026-09-01 sí lo hay —el SDK recolecta aunque no pueda notificar— y ese estado tiene que
  /// ser legible, o sería peor que el fallo: una app que parece andar bien y no notifica.
  AkPushError? _sinAvisosPorque;

  final StreamController<PushMessage> _recibidos =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _tocados =
      StreamController<PushMessage>.broadcast();

  final Set<String> _toquesYaVistos = <String>{};
  final List<StreamSubscription<dynamic>> _suscripciones = [];

  // ── Lo que la aplicación consume ────────────────────────────────────────

  /// Avisos que llegaron con la aplicación abierta.
  static Stream<PushMessage> get onMessage => _yo._recibidos.stream;

  /// Avisos que la persona tocó, vengan de donde vengan.
  static Stream<PushMessage> get onNotificationTap => _yo._tocados.stream;

  /// Si hay permiso de notificaciones. `false` no es un fallo: es una respuesta.
  ///
  /// Sigue siendo un `bool` para no romper a quien ya lo consume, pero adentro
  /// ya no hay un `bool`: hay un [EstadoDelPermiso]. Quien tenga que decidir
  /// **qué ofrecerle a la persona** —volver a preguntar o mandarla a los
  /// Ajustes— necesita el estado entero, con [estadoDelPermiso].
  static bool get tienePermiso => _yo._estado.permiteRecibir;

  /// El token de este dispositivo, si ya se obtuvo.
  static String? get token => _yo._token;

  /// Deja que la aplicación decida si el aviso se dibuja. En `null` se dibuja
  /// todo, que es como venía siendo.
  ///
  /// Es asignable en cualquier momento, **incluso antes de [init]**: el portero
  /// no depende del arranque. Eso evita el error clásico de registrar el
  /// callback y que se pise al inicializar.
  ///
  /// La decisión afecta ÚNICAMENTE al dibujo: el evento `delivered` y
  /// [onMessage] ocurren igual, incluso con [DecisionDeDibujo.noMostrar].
  static DecidirDibujo? get alDecidirDibujo => _yo._portero.alDecidir;

  static set alDecidirDibujo(DecidirDibujo? decidir) =>
      _yo._portero.alDecidir = decidir;

  /// La ruta que dejó el último toque, para mirar sin consumirla. Observable:
  /// sirve con `ValueListenableBuilder` / `ListenableBuilder`.
  static ValueListenable<RutaDelAviso?> get rutaPendiente =>
      IntencionPendiente.instancia;

  /// Devuelve la ruta pendiente UNA vez y la limpia.
  static RutaDelAviso? consumirRuta() => IntencionPendiente.instancia.consumir();

  /// Lo que va a usar el 95% de las integraciones: entrega la ruta que ya
  /// estaba guardada (toque en frío, con la aplicación muerta) y todas las que
  /// lleguen después (toque caliente).
  ///
  /// Devuelve la función para cortar; llamarla en `dispose()` no es opcional:
  /// un consumidor muerto que siga suscrito se lleva la intención que le tocaba
  /// al que está vivo.
  ///
  /// ```dart
  /// late final VoidCallback _cortar;
  /// @override void initState() {
  ///   super.initState();
  ///   _cortar = AkPush.alRutear((r) => _navegador.go(r.destino));
  /// }
  /// @override void dispose() { _cortar(); super.dispose(); }
  /// ```
  static VoidCallback alRutear(void Function(RutaDelAviso ruta) navegar) =>
      IntencionPendiente.instancia.alLlegar(navegar);

  /// Por qué no llegan los push.
  ///
  /// No tiene efectos: no pide permiso, no registra, no envía nada. Se puede
  /// llamar desde un botón escondido de soporte, y **se puede llamar aunque
  /// [init] haya fallado** — que es justamente cuando más sirve. Por eso no
  /// pasa por `_asegurarIniciado()`: un diagnóstico que lanza `notInitialized`
  /// es inútil, porque el caso número uno es que `init()` no terminó.
  static Future<Diagnostico> diagnostico() => _yo._diagnostico();

  /// Lo que el comercio configuró sobre las notificaciones en su aplicación.
  ///
  /// Sirve para que la app sepa qué textos usar en su pregunta blanda y si el
  /// comercio considera el permiso indispensable.
  static PoliticaDeNotificaciones get politica => _yo._politica;

  /// Qué se le preguntó a esta persona y qué contestó.
  static Consentimiento get consentimiento => _yo._consentimiento;

  /// De qué comercio es esta aplicación, **según el servicio**.
  ///
  /// No hace falta configurarlo: el comercio sale de la llave, y la
  /// configuración lo devuelve. Sirve para diagnosticar y para mostrar en un
  /// registro contra cuál se está trabajando — que es la confusión real de quien
  /// administra tres comercios con tres llaves parecidas.
  ///
  /// 🔴 **No se usa como declaración.** Repetirle al servicio lo que él mismo
  /// acaba de contestar no comprueba nada: la guarda de `X-Comercio` sólo vale
  /// si la aplicación declara algo que sabe por su cuenta.
  static String? get comercio => _yo._config?.comercio;

  /// El catálogo de módulos que el servidor tiene para este comercio —
  /// `avisos`, `ubicacion`, y los que estén sólo `declarado`s—, con la clave
  /// siendo el nombre del módulo.
  ///
  /// Es sólo lectura: el paquete no construye nada a partir de esto. Sirve
  /// para que la aplicación pueda mostrar, por ejemplo, qué le falta activar a
  /// este comercio, sin tener que conocer el catálogo de memoria.
  static Map<String, InfoDeModulo> get modulos => _yo._config?.modulos ?? const {};

  /// POR QUÉ ESTE ARRANQUE NO TIENE AVISOS, aunque el resto del SDK funcione.
  ///
  /// `null` cuando los avisos están en pie. Con valor cuando el SDK arrancó, dio de alta la
  /// instalación y va a recolectar, pero **no puede notificar** — porque el paquete de esta
  /// aplicación no está en el inventario del comercio, o porque su configuración de Firebase
  /// está incompleta del lado del proveedor.
  ///
  /// 🔴 Se expone porque, desde que recolectar y notificar están separados, este estado
  /// intermedio es el más engañoso de todos: la app arranca, los datos llegan, la consola se
  /// ve viva, y los avisos no salen. Sin un lugar donde preguntarlo, la única forma de
  /// enterarse es que alguien note que hace días que no le llega nada.
  static AkPushError? get sinAvisosPorque => _yo._sinAvisosPorque;

  /// La aplicación avisa qué contestó la persona **en su propio modal**.
  ///
  /// Hay que llamarlo en los dos casos, no sólo cuando acepta: un «ahora no»
  /// también es un dato, y es el que distingue a quien se puede recuperar de
  /// quien ya dijo que no de verdad.
  ///
  /// Si aceptó, después se llama a [pedirPermiso] para el diálogo del sistema.
  static Future<void> reportarModal({required bool acepto}) =>
      _yo._reportarModal(acepto: acepto);

  /// ANOTA EN EL SERVICIO LO QUE LA PERSONA DECIDIÓ, CON EL TEXTO QUE LEYÓ.
  ///
  /// 🔴 Un solo lugar para las dos decisiones —avisos y ubicación— a propósito. Si cada
  /// una lo llamara por su cuenta, la que se agregue mañana se va a olvidar, y un
  /// consentimiento que a veces se anota y a veces no es peor que ninguno: hace creer
  /// que hay registro.
  ///
  /// Se traga cualquier fallo. Es telemetría de cumplimiento y **no puede romperle nada
  /// a la aplicación anfitriona**: si el servicio no contesta, la persona igual tiene que
  /// poder seguir usando la app. Lo que se pierde es el registro, no la decisión — que
  /// vive además en el almacén local.
  /// Corre los módulos que no piden ningún permiso.
  ///
  /// 🔴 `avisos` NO pasa por acá y es deliberado: es el único que hoy funciona en
  /// producción, y moverlo al registro es un cambio con riesgo propio que está anotado
  /// aparte. Mover la ubicación no podía romper un envío; mover los avisos sí.
  /// Espera a que no quede ningún diálogo de avisos en pantalla.
  ///
  /// No hay una señal del sistema que diga «el diálogo se cerró», así que se mira el estado
  /// del permiso hasta que deje de ser `sinPreguntar`, con un tope. El tope importa: si la
  /// persona deja el modal abierto y se va, la ubicación no se le ofrece en esta sesión —
  /// y eso es mejor que ofrecérsela encima de la pregunta anterior.
  Future<void> _esperarAQueSeCierreElDeAvisos() async {
    const paso = Duration(milliseconds: 400);
    const tope = Duration(seconds: 45);
    final hasta = DateTime.now().add(tope);
    while (DateTime.now().isBefore(hasta)) {
      final e = await _estadoDelPermiso();
      if (e != EstadoDelPermiso.sinPreguntar) return;
      await Future<void>.delayed(paso);
    }
  }

  Future<void> _correrModulos() async {
    final id = _userId;
    if (id == null || _api == null) return;
    try {
      final registro = RegistroDeModulos([
        ModuloDeAparato(),
        ModuloDeAutenticidad(),
        ModuloDeSenales(),
      ]);
      await registro.alEntrar(Contexto(
        api: _api!,
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        sujetoId: id,
        config: _config,
        // 🔴 ES LA ÚNICA LÍNEA QUE HACE QUE LA POLÍTICA EXISTA PARA LOS MÓDULOS. Sin ella
        // los tres se comportan como antes: miden y mandan, siempre. Con ella preguntan
        // primero, y una medición idéntica a la anterior no gasta una llamada.
        portero: _porteroDeEnvio,
      ));
    } catch (_) {
      // Ninguna señal vale romperle el inicio de sesión a nadie.
    }
  }

  Future<void> _anotarConsentimiento({
    required String categoria,
    required bool concedido,
    required String textoMostrado,
  }) async {
    final api = _api;
    if (api == null) return; // sin init() no hay a quién anotarle nada
    try {
      await api.anotarConsentimiento(
        categoria: categoria,
        concedido: concedido,
        // Si el comercio no cargó texto propio, se manda el del SDK: lo que hay que
        // guardar es lo que la persona TUVO DELANTE, no lo que el comercio escribió.
        textoMostrado: textoMostrado.trim().isEmpty
            ? '(el texto por omisión del paquete)'
            : textoMostrado,
        // La versión de la configuración del comercio. Es lo que permite saber después
        // si el texto cambió desde que esta persona lo leyó.
        versionDelTexto: int.tryParse(_config?.version ?? '') ?? 0,
        sujetoId: _userId,
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        versionDeLaApp: _config?.version,
        plataforma: Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : null),
      );
    } catch (_) {
      // A propósito: ver el comentario de arriba.
    }
  }

  Future<void> _reportarModal({required bool acepto}) async {
    _consentimiento =
        _consentimiento.conModal(acepto: acepto, cuando: DateTime.now());
    await _almacen.guardarConsentimiento(_consentimiento);
    await _almacen.anotarQueSePregunto();

    // Queda anotado en el servicio, con el texto que tuvo delante. Es la prueba, y sin
    // ella el registro dice que apretó un botón pero no a qué dijo que sí.
    await _anotarConsentimiento(
      categoria: 'avisos',
      concedido: acepto,
      textoMostrado: '${politica.textos.titulo}\n${politica.textos.cuerpo}',
    );

    // Un «ahora no» hay que reportarlo al servicio: el comercio necesita
    // distinguirlo de quien nunca vio la pregunta, y sin esto los dos se ven
    // igual. Si no hay con quién asociarlo todavía, viaja en el próximo alta.
    if (!acepto && _userId != null && _token != null) {
      try {
        await _registrarAhora(userId: _userId!, concedido: false);
      } catch (_) {
        // Es telemetría: no puede romperle nada a la aplicación.
      }
    }
  }

  // ── El comportamiento dentro de la propia aplicación ─────────────────────

  /// EMPIEZA A MIRAR UN FORMULARIO — cuánto tarda en llenarlo y cuántas veces lo deja.
  ///
  /// ```dart
  /// final f = AkPush.formulario('solicitud');      // en initState
  /// await f.abrir();
  /// TextField(controller: f.campo('cedula').controlador,
  ///           focusNode:  f.campo('cedula').foco)
  /// await f.enviar();                               // al apretar Enviar
  /// f.dispose();                                    // en dispose
  /// ```
  ///
  /// 🔴 **No se puede detectar solo y por eso se declara.** El SDK no tiene forma de saber
  /// qué pantalla es «la solicitud» ni cuál de los botones la envía; adivinarlo sería medir
  /// cualquier cosa y llamarla tiempo de llenado.
  ///
  /// 🔴 **Nunca viaja el contenido de un campo.** Ni el texto, ni su largo, ni un hash. Se
  /// mide *que* pegó la cédula, nunca *qué* cédula pegó. Ver `comportamiento/evento.dart`.
  ///
  /// Se puede llamar antes de que `init()` termine: lo que se anote queda en la cola del
  /// teléfono y sale cuando haya con quién hablar.
  static ObservadorDeFormulario formulario(String nombre) =>
      _yo._comportamiento.formulario(nombre);

  /// Cómo está el módulo de comportamiento: cuántos eventos esperan, cuándo salió el último
  /// lote, y por qué no salió si no salió.
  static Future<EstadoDelComportamiento> estadoDelComportamiento() =>
      _yo._comportamiento.estado();

  /// MANDA AHORA LO QUE HAY EN LA COLA. Devuelve cuántos eventos salieron.
  ///
  /// 🔴 ES LA EXCEPCIÓN, NO EL CAMINO. La política es que el lote sale **al abrir la
  /// aplicación** y nada más: una llamada de red por medición se nota en la batería, y el
  /// SDK ya la hace sola en `init()`. Esto existe para el caso en que el comercio necesita
  /// el dato en el momento —recién enviada una solicitud de crédito, con el analista
  /// esperando del otro lado— y no puede aguardar a la próxima apertura.
  ///
  /// Llamarla por cada evento devuelve el SDK a lo que hacía antes de que existiera la
  /// política, y con más pasos.
  static Future<int> transmitirComportamiento() => _yo._comportamiento.transmitir();

  /// La política de transmisión vigente: los cinco números y sus motivos.
  static PoliticaDeTransmision get politicaDeTransmision => _yo._politicaDeTransmision;

  /// Lo último que la política decidió de cada módulo, con el motivo en castellano.
  /// «no se transmitió: nada cambió» es una respuesta correcta, no una falla — y sin esto
  /// se vería igual que no haber medido.
  static Map<String, DecisionDeEnvio> get ultimasDecisiones =>
      Map.unmodifiable(_yo._porteroDeEnvio.ultimaDecision);

  // ── El ciclo de sesión ──────────────────────────────────────────────────

  /// Deja este teléfono en orden para esta persona: da de alta al SUJETO, da
  /// de baja a la anterior si era otra, resuelve el permiso según lo que
  /// configuró el comercio, y registra el módulo de avisos sólo si hace falta.
  ///
  /// Es lo que hay que llamar al iniciar sesión. Devuelve el resumen de cómo
  /// quedó, que es lo que la aplicación necesita para decidir qué mostrar.
  ///
  /// [tipo] si el sujeto es una persona natural o jurídica (empresa). Por
  /// omisión, natural.
  ///
  /// [documento] su documento de identidad —cédula, RIF, pasaporte—. Es lo que
  /// permite que un sistema de afuera pida un envío por cédula sin conocer el
  /// [userId] interno del comercio.
  ///
  /// [organizacion] la organización a la que PERTENECE, si tiene una —por
  /// ejemplo, un empleado de un proveedor—. No reemplaza al sujeto: cuelga de
  /// él.
  ///
  /// [datos] es lo que el comercio sabe de esta persona —nombre, sucursal, plan,
  /// segmento— y que nosotros no podemos inventar. Sin esto, la consola muestra
  /// un identificador opaco y no hay forma de buscar a nadie ni de segmentar un
  /// envío. Se manda en cada inicio de sesión, no una sola vez: la sucursal de
  /// una persona cambia, y el plan más todavía.
  ///
  /// [identityHash] es la firma que calcula el backend del comercio sobre el
  /// [userId]. El servicio la verifica cuando el comercio activó ese modo.
  ///
  /// 🔴 **Es el corazón del rediseño**: el sujeto se da de alta ANTES de tocar
  /// ningún permiso. Hasta acá, quien decía que no a los avisos no quedaba
  /// anotado en ningún lado —sin permiso no hay token, y sin token no había
  /// alta—. Después de esta llamada esa persona existe para el sistema con su
  /// aparato enlazado, aunque el permiso quede en «denegado».
  static Future<ResultadoDeSesion> alIniciarSesion({
    required String userId,
    TipoDeSujeto tipo = TipoDeSujeto.natural,
    Documento? documento,
    Organizacion? organizacion,
    Map<String, dynamic>? datos,
    String? identityHash,
    @Deprecated(
      'Usá `documento: Documento(clase: ClaseDeDocumento.cedula, numero: '
      '...)` en su lugar. Se sigue traduciendo sola —no se rompe nada— pero '
      'sólo alcanza para cédulas: con `documento` se declara la clase real '
      '(rif, pasaporte, otro) desde el arranque.',
    )
    String? identity,
  }) =>
      _yo._alIniciarSesion(
        userId: userId,
        tipo: tipo,
        documento: documento,
        organizacion: organizacion,
        identityHash: identityHash,
        // ignore: deprecated_member_use_from_same_package
        identity: identity,
        datos: datos,
      );

  // ── Dónde está la persona ────────────────────────────────────────────────

  /// ¿Se le puede pedir la ubicación, o ya contestó?
  ///
  /// `false` cuando ya la concedió o cuando la denegó para siempre — en ese
  /// último caso el diálogo del sistema ya no se muestra y sólo quedan los
  /// Ajustes del teléfono.
  static Future<bool> get sePuedePedirUbicacion => _yo._ubicacion.sePuedePreguntar;

  /// ¿Está concedida?
  static Future<bool> get tieneUbicacion => _yo._ubicacion.concedido;

  /// Pide el permiso de ubicación aproximada.
  ///
  /// 🔴 NO SE LLAMA EN EL ARRANQUE. Dos diálogos del sistema seguidos —el de
  /// notificaciones y éste— es la forma más rápida de que la persona diga que
  /// no a los dos. Se pide cuando la aplicación ya explicó para qué sirve.
  static Future<bool> pedirUbicacion() => _yo._ubicacion.pedir();

  /// La política que configuró el comercio para la ubicación.
  static PoliticaDeUbicacion get politicaDeUbicacion => _yo._politicaDeUbicacion;

  /// LE OFRECE A LA PERSONA COMPARTIR SU ZONA, CON EL MODAL DEL SDK.
  ///
  /// Explica primero —con los textos que escribió el comercio— y recién si dice que
  /// sí levanta el diálogo del sistema. Devuelve si quedó concedido.
  ///
  /// El SDK la llama solo al iniciar sesión cuando el comercio puso el momento en
  /// «despuesDeEntrar». Esta versión pública es para el otro momento, «laAppDecide»:
  /// ofrecerla recién cuando sirve para algo —al abrir el mapa de sucursales, por
  /// ejemplo— que es cuando más gente acepta.
  ///
  /// `context` es opcional: si la aplicación pasó [navegador] al `MaterialApp`, el
  /// SDK dibuja sin que le den ninguno.
  static Future<bool> ofrecerUbicacion([BuildContext? context]) =>
      _yo._ofrecerUbicacion(context: context, forzar: true);

  /// El motor. `forzar` distingue las dos entradas:
  ///
  ///  - **la automática** (al iniciar sesión) respeta la política: no ofrece nada si
  ///    el comercio la tiene apagada, si el momento es otro, o si se le ofreció hace
  ///    menos de `reintentarCadaDias`.
  ///  - **la que pide la aplicación** salta esas condiciones —ya decidió que es el
  ///    momento— pero NO salta las dos que no dependen de nadie: que el permiso no
  ///    esté ya concedido, y que el sistema todavía acepte mostrarlo.
  Future<bool> _ofrecerUbicacion({
    BuildContext? context,
    required bool forzar,
  }) async {
    try {
      // 🔴 Si ya está concedido no se pregunta de nuevo. Un modal que pide algo que
      // la persona ya dio es la clase de detalle que hace que se desconfíe del resto.
      if (await _ubicacion.concedido) {
        // Pero puede faltarle el otro interruptor. Ver [_avisarSiFaltaElServicio].
        await _avisarSiFaltaElServicio();
        return true;
      }

      // Y si el sistema ya no muestra el diálogo —dijo que no dos veces—, levantar el
      // modal sería mentirle: acepta, no pasa nada, y no hay forma de explicarle por
      // qué. Sólo le queda los Ajustes, y eso se ofrece en otro lado.
      if (!await _ubicacion.sePuedePreguntar) return false;

      if (!forzar) {
        if (!_politicaDeUbicacion.activa) return false;
        if (_politicaDeUbicacion.momento != MomentoDeUbicacion.despuesDeEntrar) {
          return false;
        }
        final desde = await _almacen.desdeLaUltimaOfertaDeUbicacion();
        if (desde != null &&
            desde.inDays < _politicaDeUbicacion.reintentarCadaDias) {
          return false;
        }
      }

      // 🔴 Se toma el contexto DESPUÉS de los `await` de arriba, no antes. Entre que
      // se consulta el permiso y se dibuja el modal la aplicación pudo cambiar de
      // pantalla, y un contexto capturado antes apuntaría a algo que ya no existe:
      // el modal no aparece, o aparece colgado de un árbol muerto.
      // Se anota ANTES de mostrarlo, no después. Si se anotara al cerrar y la persona
      // mata la aplicación con el modal abierto, en el próximo arranque lo ve otra
      // vez, y otra, y otra. Preferimos perder una oferta a hostigar a alguien.
      await _almacen.guardarOfertaDeUbicacion(DateTime.now());

      // 🔴 El contexto se busca ACÁ, después del último `await`, y no antes. Entre
      // consultar el permiso y dibujar, la aplicación pudo cambiar de pantalla: un
      // contexto tomado más arriba apuntaría a un árbol que ya no existe, y el modal
      // no aparecería nunca — sin ningún error que lo delate.
      final ctx = context ?? navegador.currentContext;
      if (ctx == null || !ctx.mounted) {
        // 🔴 SE AVISA, NO SE FALLA MUDO. Éste es el error de integración más probable
        // del SDK entero: el comercio prende la ubicación en la consola, abre la
        // aplicación, no pasa nada, y no hay ni un renglón que diga por qué. Medido
        // acá mismo el 2026-08-31: el modal no salió y sólo se supo mirando el código.
        //
        // Sale sólo en depuración: en producción no se le llena el registro a nadie
        // con esto, y para entonces la integración ya está hecha.
        assert(() {
          debugPrint(
            '[ak_push] La ubicación está activa para este comercio, pero el SDK no '
            'tiene dónde dibujar el modal. Agregá «navigatorKey: AkPush.navegador» '
            'a tu MaterialApp, o llamá a AkPush.ofrecerUbicacion(context) vos mismo.',
          );
          return true;
        }());
        return false;
      }

      final textos = _politicaDeUbicacion.textos;
      final quiere = await ModalDeUbicacion.mostrar(ctx, textos: textos);

      // 🔴 SE ANOTA EL «NO» IGUAL QUE EL «SÍ», y esa simetría importa: sin el rechazo
      // anotado, alguien que dijo que no y alguien a quien nunca se le preguntó se ven
      // idénticos —los dos sin registro— y son dos situaciones opuestas. A la primera hay
      // que dejarla en paz; a la segunda hay que preguntarle.
      final queLeyo = '${textos.titulo}\n${textos.cuerpo}';
      await _anotarConsentimiento(
        categoria: 'ubicacion',
        concedido: quiere,
        textoMostrado: queLeyo,
      );
      if (!quiere) return false;

      final concedido = await _ubicacion.pedir();
      if (!concedido) {
        // Aceptó en nuestro modal y después dijo que no en el del sistema. Es un «no» y
        // se anota como tal: el consentimiento vale por lo que terminó pasando, no por lo
        // que la persona contestó a mitad de camino.
        await _anotarConsentimiento(
          categoria: 'ubicacion',
          concedido: false,
          textoMostrado: queLeyo,
        );
        return false;
      }

      // 🔴 EL PERMISO NO ALCANZA: FALTA QUE EL TELÉFONO TENGA LA UBICACIÓN PRENDIDA.
      //
      // Son dos interruptores distintos y hasta hoy sólo se miraba uno. Medido en un
      // HONOR real el 2026-08-31: modal aceptado, diálogo del sistema aceptado, permiso
      // concedido — y cero posiciones, porque el interruptor general estaba apagado. No
      // hubo ni un error: `_leer()` devolvía null y el catch se lo tragaba. En la
      // consola se veía «con permiso, sin ubicaciones», que parece el sistema roto.
      //
      // Se le avisa en el momento, que es cuando la persona todavía está pensando en
      // esto y acaba de decir que sí. Un aviso media hora después no lo lee nadie.
      if (await _avisarSiFaltaElServicio()) {
        // Se devuelve `true` igual: el permiso QUEDÓ concedido, que es lo que preguntó
        // quien llamó. Lo que falta es del teléfono, no de esta persona, y en cuanto
        // prenda la ubicación las posiciones empiezan a llegar solas.
        return true;
      }

      // La primera posición se manda ya: sin esto la consola muestra a alguien «con
      // ubicación activa» y cero posiciones hasta el próximo arranque, que parece roto
      // aunque no lo esté.
      if (_userId != null) {
        await _ubicacion.reportarSiCorresponde(_userId!, forzar: true);
      }
      return true;
    } catch (_) {
      // Nunca tumba nada: perder una ubicación cuesta un dato de segmentación; que
      // falle el inicio de sesión cuesta que esa persona no reciba nada.
      return false;
    }
  }

  /// Lee y manda dónde está, si hay permiso y si pasó el tiempo mínimo.
  ///
  /// Devuelve si mandó algo. Nunca lanza: perder una posición cuesta un dato de
  /// segmentación; que falle el arranque cuesta que esa persona no reciba nada.
  static Future<bool> reportarUbicacion({bool forzar = false}) async {
    final u = _yo._userId;
    if (u == null) return false;
    return _yo._ubicacion.reportarSiCorresponde(u, forzar: forzar);
  }

  /// Cierra el ciclo: da de baja el teléfono y limpia la barra de estado.
  static Future<void> alCerrarSesion() => _yo._logout();

  // ── Arranque ────────────────────────────────────────────────────────────

  /// Pide la configuración, conecta con Firebase, pide permiso y consigue la
  /// dirección de este teléfono.
  ///
  /// No registra a nadie todavía: para eso está [identify], que se llama cuando
  /// la persona inicia sesión.
  ///
  /// [pedirPermisoAlIniciar] viene en `true` porque es lo que hacía este
  /// paquete desde la primera versión y no puede cambiar solo. Pero el arranque
  /// en frío es el **peor** momento para disparar el diálogo del sistema: la
  /// persona acaba de abrir la aplicación, todavía no sabe qué hace, y el «no»
  /// que se lleva ahí no se recupera nunca más. Poniéndolo en `false`, `init()`
  /// sólo **lee** el permiso y la aplicación decide cuándo pedirlo con
  /// [pedirPermiso], después de su propia pantalla que explica para qué sirve.
  /// Arranca el SDK. Dos valores, y ninguno más.
  ///
  /// [llave] es lo único que hay que cuidar, y es **lo que decide de qué
  /// comercio es cada llamada**: el comercio no se configura porque no hace
  /// falta — sale de la llave, del lado del servicio, y la configuración lo
  /// devuelve. Pedirlo aparte sería pedir un dato que el sistema ya sabe, con
  /// el riesgo de que alguien lo escriba distinto.
  ///
  /// [url] se configura en vez de quemarse, para poder apuntar a calidad o a
  /// producción sin publicar una versión nueva de la aplicación.
  /// La llave del navegador de la aplicación, para que el SDK pueda levantar sus
  /// propias pantallas.
  ///
  /// Se pasa una vez, en el `MaterialApp`:
  ///
  /// ```dart
  /// MaterialApp(navigatorKey: AkPush.navegador, home: ...)
  /// ```
  ///
  /// Con eso el SDK ya ofrece la ubicación solo, cuando el comercio lo activó desde
  /// la consola. Sin eso todo lo demás sigue andando igual — sólo que la ubicación
  /// hay que ofrecerla a mano con [ofrecerUbicacion].
  static final GlobalKey<NavigatorState> navegador = GlobalKey<NavigatorState>();

  static Future<void> init({
    required String llave,
    String? url,
    bool pedirPermisoAlIniciar = true,
    PoliticaDeNotificaciones? politicaPorDefecto,
    /// CUÁNDO SE TRANSMITE LO QUE SE MIDE. Si no se pasa, rige la de omisión: por lote al
    /// abrir, sólo si algo cambió, y todo igual cada siete días.
    ///
    /// El uso previsto es uno solo y es el de volver atrás:
    /// `politicaDeTransmision: PoliticaDeTransmision.comoEstabaAntes` deja el SDK midiendo
    /// y mandando siempre, como antes de que la política existiera.
    PoliticaDeTransmision? politicaDeTransmision,
  }) =>
      _yo._init(
        apiKey: llave,
        baseUrl: url,
        pedirPermisoAlIniciar: pedirPermisoAlIniciar,
        politicaPorDefecto: politicaPorDefecto,
        politicaDeTransmision: politicaDeTransmision,
      );

  Future<void> _init({
    required String apiKey,
    String? baseUrl,
    bool pedirPermisoAlIniciar = true,
    PoliticaDeNotificaciones? politicaPorDefecto,
    PoliticaDeTransmision? politicaDeTransmision,
  }) async {
    // Antes que nada: la política tiene que estar puesta antes de que se anote el primer
    // evento, o el primero se mediría con una y el resto con otra.
    if (politicaDeTransmision != null) _adoptarPolitica(politicaDeTransmision);
    // La que declara la aplicación rige mientras el servicio no mande la suya.
    // Cuando la mande, gana la del servidor: la decisión es del comercio, y el
    // sentido de servirla es que la cambie sin publicar una versión nueva.
    if (politicaPorDefecto != null) _politica = politicaPorDefecto;
    // Un reintento que funciona no puede seguir reportando el error de la vez
    // pasada: el diagnóstico diría que está roto algo que ya se arregló.
    _ultimoError = null;
    _sinAvisosPorque = null;

    try {
      final datos = await DatosDelDispositivo.recolectar();

      final urlNormalizada = AkPushApi.normalizarUrl(
          baseUrl ?? 'https://api-push.creditotal.online');

      _api = AkPushApi(apiKey: apiKey, baseUrl: urlNormalizada);
      _ubicacionInterna = Ubicacion(_api!);

      // Para el isolate de segundo plano, que no ve nada de esto. Ver H-09.
      await _almacen.guardarCredencial(apiKey, urlNormalizada);

      _consentimiento = await _almacen.leerConsentimiento();

      // ══ PRIMERO SE PREGUNTA, DESPUÉS SE MANDA ═════════════════════════════
      //
      // 🔴 EL ORDEN ESTABA AL REVÉS Y ERA UN AGUJERO DE VERDAD.
      //
      // `_registrarInstalacion` corría ACÁ ARRIBA, antes de resolver la
      // configuración: el primer envío de cada arranque salía con los datos del
      // aparato **sin haber preguntado nada al comercio**. Por más que la
      // perilla estuviera apagada, el aparato ya había viajado — y el descarte
      // del otro lado no devuelve la batería ni el tráfico que costó.
      //
      // Ahora la configuración se resuelve primero. Sigue sin esperar al
      // permiso ni a que alguien inicie sesión —el aparato existe antes que el
      // sujeto, eso no cambia—, pero ya sabe qué le permitieron antes de hablar.
      final cacheada = await _almacen.leer();

      // ══ RECOLECTAR Y NOTIFICAR SON COSAS SEPARADAS ════════════════════════
      //
      // 🔴 ANTES, LA FALTA DE FIREBASE APAGABA TODO EL SDK. `_resolverConfig`
      // propagaba el desacuerdo de paquete y `init()` moría ahí: no se daba de
      // alta la instalación, no corrían los módulos, no se medía ni una señal.
      // Un comercio que sólo quisiera recolectar datos quedaba obligado a tener
      // un proyecto de Firebase configurado, y una app iOS sin registrar perdía
      // también la ubicación y la autenticidad, que no tienen nada que ver.
      //
      // Medido el 2026-09-01: la app de Multivalores en iPhone no reportaba NADA
      // —cero campos de aparato, cero señales— y la única causa era que su
      // paquete de iOS no estaba en el inventario del comercio.
      //
      // Ahora el desacuerdo de paquete deja el SDK andando **sin avisos**, y se
      // anota por qué. Lo que sí sigue tumbando el arranque es una llave
      // rechazada: sin credencial válida no hay nada que hacer del otro lado, y
      // seguir sería fingir que se está recolectando.
      AkPushConfig? config;
      try {
        config = await _resolverConfig(datos.identificadorDePaquete, cacheada);
      } on AkPushError catch (e) {
        if (e.code != AkPushErrorCode.appMismatch) rethrow;
        _sinAvisosPorque = e;
        // También en `_ultimoError`, que es lo que ya lee el diagnóstico. Que el SDK
        // esté recolectando no vuelve esto un detalle: los avisos NO funcionan.
        _ultimoError = e;
      }

      // La instalación nace acá: sin token —todavía no se pidió permiso— y sin
      // sujeto —todavía no entró nadie—.
      await _registrarInstalacion(datos);

      // ══ EL COMPORTAMIENTO: SE ABRE LA SESIÓN Y SALE EL LOTE DE LA VEZ PASADA ═══════
      //
      // 🔴 ACÁ Y NO MÁS ABAJO, a propósito: abajo está el `return` de cuando no hay
      // configuración, y el comportamiento tiene que medirse igual. Un comercio al que le
      // falta el paquete registrado —o que todavía no tiene Firebase— pierde los avisos,
      // no la serie de comportamiento, que es lo único que no depende de nadie más.
      //
      // 🔴 Y NO SE ESPERA. Es lo único que se hace con la red en este punto del arranque,
      // y el arranque es la parte que la persona mira esperando. Si no hay señal, los
      // eventos se quedan en el teléfono y salen la próxima vez: la cola vive en el disco
      // justamente para eso. Que falle no puede costar un milisegundo de pantalla.
      await _comportamiento.arrancar(
        api: _api!,
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        config: config,
        // Quien haya quedado logueado sigue estándolo hasta que cierre sesión, así que el
        // `SESION_ABRE` de esta apertura es suyo. Ver la nota de `sujetoConocido`.
        sujetoConocido: await _almacen.leerUsuario(),
      );
      unawaited(_comportamiento.transmitir());

      // 🔴 La cuenta cambió. Un token de FCM solo vale dentro del proyecto que
      // lo emitió, así que el que tenemos guardado ya no sirve para nada — y si
      // no lo tiramos, este teléfono queda mudo para siempre sin ningún error
      // visible. Es el fallo más caro de todo el mecanismo de configuración
      // remota, y el único momento en que se puede atajar es acá.
      // El servidor manda. Si todavía no sirve el campo, `config.politica` es la
      // de siempre y no piso lo que declaró la aplicación.
      if (config == null) {
        // Sin configuración no hay avisos, y no hay nada más que preparar acá: la
        // instalación ya quedó dada de alta arriba y los módulos corren al iniciar
        // sesión, que es donde siempre corrieron.
        return;
      }

      if (config.trajoPolitica) _politica = config.politica;
      _politicaDeUbicacion = config.ubicacion;

      final cambio = cacheada != null && cacheada.version != config.version;
      if (cambio) {
        await _descartarCuentaAnterior();
      }

      await _iniciarFirebase(config);
      _config = config;
      await _almacen.guardar(config);

      _estado = pedirPermisoAlIniciar
          ? await _pedirAlSistemaYAnotar()
          : await _permiso.estadoActual();
      await _obtenerToken(descartarElViejo: cambio);

      // 🔴 LA DIRECCIÓN ES DE LA INSTALACIÓN, ASÍ QUE SE MANDA APENAS SE TIENE.
      //
      // La instalación se dio de alta más arriba, cuando todavía no había token: primero
      // se pide la configuración, después se inicia Firebase, y recién ahí hay dirección.
      // Sin esta línea el token se queda en el teléfono hasta que alguien inicie sesión —
      // y una aplicación donde nadie se loguea figura «sin token» para siempre.
      //
      // Medido el 2026-08-31 integrando el SDK en una aplicación de verdad: arrancó,
      // registró la instalación, obtuvo su token, y en la consola aparecía sin dirección.
      // No estaba roto: nadie se lo había contado al servidor.
      await _reportarLaDireccion();

      await Presentador.instancia.iniciar();
      _escuchar();
      await _procesarArranqueEnFrio();
    } on AkPushError catch (e) {
      // Se guarda ANTES de propagarlo. El error de `init()` se le tira a quien
      // integra y hasta acá no quedaba anotado en ningún lado, que es
      // exactamente el caso que más hay que diagnosticar.
      _ultimoError = e;
      rethrow;
    }
  }

  /// La configuración viene de la red; si no hay red, de lo último que se supo.
  ///
  /// Solo la primerísima instalación depende de tener señal. De ahí en adelante
  /// el teléfono arranca con lo que guardó, aunque esté sin conexión.
  Future<AkPushConfig> _resolverConfig(
    String identificadorDePaquete,
    AkPushConfig? cacheada,
  ) async {
    try {
      final delServidor = await _api!.obtenerConfig(identificadorDePaquete);
      _configDelServidor = true;
      return delServidor;
    } on AkPushError catch (e) {
      // Un desacuerdo entre la aplicación y lo registrado NO se resuelve con la
      // caché: seguiría con una configuración que el servidor ya dijo que no
      // corresponde. Se propaga.
      if (e.code == AkPushErrorCode.appMismatch ||
          e.code == AkPushErrorCode.unauthorized) {
        rethrow;
      }
      if (cacheada != null) {
        // Éste es el único lugar que sabe si la configuración de este arranque
        // vino de la red o del disco. Sin anotarlo, el diagnóstico no puede
        // avisar «este teléfono todavía no se enteró de que el comercio cambió
        // de cuenta».
        _configDelServidor = false;
        _ultimoError = e;
        return cacheada;
      }
      rethrow;
    }
  }

  /// Da de alta —o actualiza— el APARATO en el modelo nuevo.
  ///
  /// 🔴 NUNCA TUMBA EL ARRANQUE. Sin red en el primerísimo arranque, la
  /// instalación queda sin dar de alta y se reintenta sola en el próximo
  /// `init()` — es upsert por `instalacionId`, así que reintentar no duplica
  /// nada. Se anota el error para el diagnóstico y se sigue: éste es un dato
  /// de inventario del aparato, no el permiso ni el token, y perderlo un
  /// arranque no le cuesta un aviso a nadie.
  Future<void> _registrarInstalacion(DatosDelDispositivo datos) async {
    try {
      final instalacionId = await _almacen.leerOCrearInstalacionId();
      await _api!.registrarInstalacion(
        instalacionId: instalacionId,
        aparato: datos.toJson(),
      );
    } catch (e) {
      _ultimoError = e is AkPushError ? e : null;
    }
  }

  /// Le cuenta al servidor la dirección de ESTA instalación, sin necesidad de que haya
  /// nadie logueado. El token pertenece al aparato; el sujeto es otra cosa.
  ///
  /// No tumba nada si falla: quedará sin dirección hasta el próximo arranque o hasta que
  /// alguien inicie sesión, que es exactamente como estaba antes.
  Future<void> _reportarLaDireccion() async {
    if (_token == null || _api == null) return;
    try {
      await _api!.actualizarAvisosDeInstalacion(
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        token: _token!,
        plataforma: Platform.isIOS ? 'ios' : 'android',
        permiso: _estado.permiteRecibir,
        estadoDelPermiso: _estado.name,
      );
    } catch (e) {
      _ultimoError = e is AkPushError ? e : null;
    }
  }

  Future<void> _descartarCuentaAnterior() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Si no se puede borrar el token viejo, igual hay que seguir: el nuevo
      // proyecto va a emitir otro.
    }
    for (final app in List<FirebaseApp>.from(Firebase.apps)) {
      try {
        await app.delete();
      } catch (_) {
        // Una app que no se puede borrar no debe impedir el arranque.
      }
    }
    await _almacen.olvidarSesion();

    // Nada de lo que sabíamos sigue valiendo: el token es de otro proyecto y el
    // alta que el servidor tiene anotada es contra ese token. Dejarlos en pie
    // haría que el diagnóstico diga «registrado» sobre un registro muerto.
    _token = null;
    _tokenObtenidoEl = null;
    _registrado = false;
    _registradoEl = null;
  }

  Future<void> _iniciarFirebase(AkPushConfig config) async {
    final opciones = config.toFirebaseOptions();

    final existente = Firebase.apps
        .where((a) => a.name == defaultFirebaseAppName)
        .firstOrNull;

    if (existente != null) {
      if (existente.options.appId == opciones.appId) return;
      throw AkPushError(
        AkPushErrorCode.firebaseInit,
        'La aplicación ya inicializó Firebase con otra cuenta',
        details:
            'AkPush necesita ser quien inicialice Firebase, porque el transporte de '
            'notificaciones solo trabaja con la app por defecto. Quitá tu propia '
            'llamada a Firebase.initializeApp() y dejá que AkPush.init() la haga.',
      );
    }

    try {
      await Firebase.initializeApp(options: opciones);
    } catch (e) {
      throw AkPushError(
        AkPushErrorCode.firebaseInit,
        'No se pudo conectar con la cuenta de Google asignada',
        details: e.toString(),
      );
    }
  }

  Future<void> _obtenerToken({bool descartarElViejo = false}) async {
    try {
      FirebaseMessaging.onBackgroundMessage(manejadorDeSegundoPlano);
      if (descartarElViejo) {
        await FirebaseMessaging.instance.deleteToken();
      }
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) {
        _tokenObtenidoEl = DateTime.now();
        await _almacen.guardarToken(_token!);
      }
    } catch (e) {
      _token = null;
      _ultimoError = AkPushError(
        AkPushErrorCode.unknown,
        'No se pudo obtener el token',
        details: e.toString(),
      );
    }
  }

  // ── El permiso ──────────────────────────────────────────────────────────

  /// Qué contestó —o no contestó todavía— la persona. **No dispara ningún
  /// diálogo**, así que se puede llamar todas las veces que haga falta.
  ///
  /// Hay que llamarlo cada vez que la aplicación vuelve del segundo plano
  /// (`AppLifecycleState.resumed`): el permiso se cambia desde los Ajustes del
  /// teléfono y **nada le avisa a la aplicación** cuando eso pasa.
  static Future<EstadoDelPermiso> estadoDelPermiso() => _yo._estadoDelPermiso();

  Future<EstadoDelPermiso> _estadoDelPermiso() async {
    _estado = await _permiso.estadoActual();
    await _reconciliar();
    return _estado;
  }

  /// Dispara el diálogo del SISTEMA, que es lo que se gasta.
  ///
  /// En iPhone se muestra una sola vez en la vida de la instalación; en
  /// Android 13+ alcanzan dos descartes para que no se muestre más. Por eso se
  /// llama **después** de la pantalla propia de la aplicación —la que explica
  /// para qué sirven los avisos— y sólo si ahí la persona dijo que sí.
  ///
  /// Devuelve el estado que quedó, que no siempre es el que se esperaba: pedir
  /// cuando ya está [EstadoDelPermiso.denegadoParaSiempre] no muestra nada.
  static Future<EstadoDelPermiso> pedirPermiso() => _yo._pedirPermisoAhora();

  // ══ LOS AVISOS, PARA DIBUJARLOS ═══════════════════════════════════════════════
  //
  // Lo de arriba dice el estado crudo. Esto lo dice en castellano, y sobre todo
  // resuelve la distinción que si se erra rompe la confianza: cuándo el botón puede
  // activar los avisos de verdad y cuándo lo único que queda son los Ajustes.
  //
  // Pedido de Juan, 2026-08-31: *«el SDK debería proporcionar un link para aceptar
  // notificaciones... yo voy a hacer el front ahí, pero me voy a servir de los
  // servicios del SDK»*. Por eso van los servicios sueltos Y la campanita hecha:
  // quien quiera dibujar lo suyo tiene con qué, y quien no, la pone en una línea.

  /// 🔴 EL SEGUNDO INTERRUPTOR: LA UBICACIÓN DEL TELÉFONO.
  ///
  /// Tener el permiso no alcanza. Si el teléfono tiene la ubicación apagada no llega
  /// ninguna posición, y hasta el 2026-08-31 eso pasaba **sin un solo error**: se leía
  /// null y el catch se lo tragaba. En la consola la persona figuraba «con permiso, cero
  /// ubicaciones», que parece un sistema roto y no lo es.
  ///
  /// Se avisa en los dos caminos —al conceder el permiso, y al iniciar sesión de quien
  /// ya lo tenía—, porque alguien puede haber apagado el interruptor meses después de
  /// haber dado el permiso y nadie se enteraría nunca.
  ///
  /// Con su propio freno, y bien separado del de la oferta de ubicación: son dos avisos
  /// distintos, con dos causas distintas, y compartir la fecha haría que uno tapara al
  /// otro. Devuelve si faltaba el servicio.
  Future<bool> _avisarSiFaltaElServicio() async {
    if (await _ubicacion.servicioPrendido) return false;

    final desde = await _almacen.desdeElAvisoDeServicio();
    // Una semana. Es un interruptor que la gente apaga a propósito —para ahorrar
    // batería— y recordárselo todos los días sería hostigar; no recordárselo nunca
    // es perder a alguien que ya dijo que sí y sólo le falta un toque.
    if (desde != null && desde.inDays < 7) return true;

    // Se anota antes de buscar el contexto, para no dejar `await` alguno entre tomar
    // el contexto y dibujar: en ese hueco la aplicación puede haber cambiado de
    // pantalla, y el modal se colgaría de un árbol que ya no existe.
    await _almacen.guardarAvisoDeServicio(DateTime.now());

    final ctx = navegador.currentContext;
    if (ctx == null || !ctx.mounted) return true;

    final ir = await ModalDeUbicacion.mostrarServicioApagado(ctx);
    if (ir) await _ubicacion.abrirAjustesDeUbicacion();
    return true;
  }

  /// Cómo están los avisos, en lenguaje llano y con qué ofrecerle a la persona.
  static Future<EstadoDeAvisos> estadoDeAvisos() async =>
      _yo._avisos.value = EstadoDeAvisos.de(await _yo._estadoDelPermiso());

  /// LA CAMPANITA, ENCHUFADA. Una línea y no hace falta nada más:
  ///
  /// ```dart
  /// AppBar(actions: [AkPush.campanita()])
  /// ```
  ///
  /// Muestra un punto rojo cuando hay algo que resolver, abre una hoja que explica
  /// cómo están los avisos, y ofrece el único botón que puede arreglarlo en ese
  /// estado —pedir el permiso, o abrir los ajustes cuando el sistema ya no pregunta.
  /// Se actualiza sola cuando la persona vuelve de los Ajustes.
  static Widget campanita({
    Color? color,
    void Function(EstadoDeAvisos)? alResolver,
  }) =>
      CampanitaDeAvisos(
        color: color,
        alResolver: alResolver,
        estado: estadoDeAvisos,
        resolver: resolverAvisos,
      );

  /// Se actualiza sola cuando la aplicación vuelve del fondo.
  ///
  /// 🔴 Ése es el caso que importa: la persona va a los Ajustes del teléfono, activa
  /// los avisos y vuelve. Sin esto la pantalla sigue diciendo «apagados» hasta que
  /// alguien reinicie la aplicación, y la persona cree que ir no le sirvió de nada.
  static ValueListenable<EstadoDeAvisos?> get avisos => _yo._avisos;

  /// HACE LO QUE CORRESPONDA SEGÚN EL ESTADO, Y DEVUELVE CÓMO QUEDÓ.
  ///
  /// Si el sistema todavía pregunta, levanta su diálogo. Si ya no —dos negativas en
  /// Android, una en iPhone—, abre los ajustes del teléfono, que es la única salida
  /// que queda. Y si ya estaban activados no hace nada.
  ///
  /// La aplicación no tiene que saber en cuál de los tres casos está: llama a esto.
  static Future<EstadoDeAvisos> resolverAvisos() => _yo._resolverAvisos();

  Future<EstadoDeAvisos> _resolverAvisos() async {
    var e = EstadoDeAvisos.de(await _estadoDelPermiso());
    if (e.puedeRecibir && !e.hayQueIrAAjustes) return _publicarAvisos(e);

    if (e.hayQueIrAAjustes) {
      await _permiso.abrirAjustes();
      // 🔴 No se vuelve a leer el estado acá. Los ajustes se abren en OTRA pantalla y
      // esta línea corre un instante después, con la persona todavía mirando la lista
      // de permisos: lo que se leyera sería el estado viejo, y la campana se pintaría
      // en rojo justo cuando la persona acaba de activarlos. El estado bueno llega
      // solo cuando la aplicación vuelve del fondo — de eso se encarga [avisos].
      return e;
    }

    await _pedirPermisoAhora();
    e = EstadoDeAvisos.de(await _estadoDelPermiso());
    return _publicarAvisos(e);
  }

  /// Pide el permiso del sistema y **anota lo que la persona contestó**.
  ///
  /// 🔴 EL CONSENTIMIENTO SE ANOTA ACÁ Y NO SÓLO EN EL MODAL PROPIO, y ésa fue la
  /// corrección del 2026-09-01. Antes sólo se anotaba desde `reportarModal`, que es lo que
  /// llama la aplicación anfitriona cuando muestra su pantalla previa. Un comercio que NO
  /// usa la pregunta blanda —el camino más común— nunca registraba nada: con la compuerta
  /// encendida, sus avisos habrían quedado bloqueados y nadie habría entendido por qué.
  ///
  /// Se descubrió probando en el emulador, no leyendo el código: la llamada salía, el
  /// permiso se concedía, y la colección de consentimientos quedaba vacía.
  ///
  /// Éste es el único punto por donde pasa toda decisión del diálogo del sistema, así que
  /// anotarlo acá cubre todos los caminos —el directo y el que viene detrás de un modal—
  /// sin depender de que quien agregue el próximo se acuerde.
  /// 🔴 EL ÚNICO LUGAR QUE LE PIDE EL PERMISO AL SISTEMA, y por eso el único que anota.
  ///
  /// Había DOS caminos al diálogo —éste y el del arranque— y el registro estaba sólo en
  /// uno. Resultado: según por dónde entrara la persona, su decisión quedaba anotada o no,
  /// sin ninguna diferencia visible. Con la compuerta encendida eso significa que el mismo
  /// comercio funciona o no según un detalle que nadie puede ver.
  ///
  /// Se descubrió el 2026-09-01 probando el ciclo completo en el emulador: el permiso se
  /// concedía y la colección de consentimientos quedaba vacía.
  Future<EstadoDelPermiso> _pedirAlSistemaYAnotar() async {
    final estado = await _permiso.pedir();
    final concedido = estado == EstadoDelPermiso.concedido ||
        estado == EstadoDelPermiso.provisional;
    await _anotarConsentimiento(
      categoria: 'avisos',
      concedido: concedido,
      // Si el comercio no tiene pantalla previa, lo que la persona tuvo delante fue el
      // diálogo del sistema. Se dice así: inventar un texto que no vio sería peor.
      textoMostrado: politica.textos.cuerpo.trim().isNotEmpty
          ? '${politica.textos.titulo}\n${politica.textos.cuerpo}'
          : '(el diálogo del sistema operativo, sin pantalla previa del comercio)',
    );
    return estado;
  }

  Future<EstadoDelPermiso> _pedirPermisoAhora() async {
    _estado = await _pedirAlSistemaYAnotar();
    await _reconciliar();

    return _estado;
  }

  /// Abre la ficha de la aplicación en los Ajustes del teléfono.
  ///
  /// Es lo único que queda cuando el estado es
  /// [EstadoDelPermiso.denegadoParaSiempre]. Abre la ficha y no la pantalla
  /// exacta de notificaciones porque no hay una API que lleve directo a esa
  /// pantalla en las dos plataformas; desde la ficha están a un toque.
  ///
  /// Devuelve si se pudo abrir, **no** si la persona activó algo: eso no se
  /// puede saber desde acá. Hay que volver a llamar a [estadoDelPermiso] cuando
  /// la aplicación vuelve del segundo plano — que es exactamente lo que pasa
  /// cuando alguien sale a los Ajustes y vuelve.
  static Future<bool> abrirAjustesDeNotificaciones() =>
      _yo._permiso.abrirAjustes();

  /// Pone al día el alta cuando el permiso cambia DESPUÉS del arranque.
  ///
  /// 🔴 Es el punto que se pasa por alto y deja teléfonos mudos. En iOS
  /// `getToken()` necesita el token de APNS, que sólo existe después de que se
  /// concedió el permiso: con `pedirPermisoAlIniciar: false`, `init()` deja el
  /// token en `null` y `identify()` se va por la rama que sólo guarda el
  /// usuario. Eso está bien mientras nadie diga que sí — pero en cuanto dice
  /// que sí hay que conseguir el token y volver a registrar, o el servicio
  /// sigue viendo `permisoConcedido: false` (o directamente ningún alta) y
  /// filtra el envío antes de mandarlo.
  Future<void> _reconciliar() async {
    if (!_estado.permiteRecibir) return;
    if (_token == null) await _obtenerToken();

    final userId = _userId ?? await _almacen.leerUsuario();
    if (userId == null || _token == null) return;

    final datos = await DatosDelDispositivo.recolectar();
    try {
      await _api?.registrarDispositivo(
        // El mismo con el que se dio de alta la instalación: sin esto el servidor
        // la identifica por el `deviceId` del aparato y crea una segunda.
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        userId: userId,
        token: _token!,
        plataforma: datos.plataforma,
        deviceInfo: datos.toJson(),
        permisoConcedido: _estado.permiteRecibir,
      );
      _registrado = true;
      _registradoEl = DateTime.now();
    } catch (_) {
      // Se reintenta en el próximo identify(), o la próxima vez que la
      // aplicación vuelva del segundo plano y consulte el estado.
    }
  }

  // ── Quién es la persona ─────────────────────────────────────────────────

  /// Ata este teléfono a una persona. Se llama cuando inicia sesión.
  ///
  /// [identityHash] es la firma que calcula el backend del comercio sobre el
  /// [userId]. El servicio SÍ la verifica desde el 2026-08-30, y cada comercio
  /// elige en qué modo: apagada, avisando sin rechazar, o exigiéndola.
  ///
  /// [datos] es lo que el comercio sabe de esta persona —nombre, sucursal, plan,
  /// segmento— y que el servicio usa para poder buscarla y segmentar envíos. Sin
  /// esto, la consola sólo tiene un identificador opaco.
  static Future<void> identify({
    required String userId,
    String? identityHash,
    String? identity,
    Map<String, dynamic>? datos,
  }) =>
      _yo._identify(
        userId: userId,
        identityHash: identityHash,
        identity: identity,
        datos: datos,
      );

  /// El ciclo de sesión completo. La lógica de qué hacer vive en `sesion.dart`,
  /// separada de quien la ejecuta: acá sólo se cumple el plan.
  Future<ResultadoDeSesion> _alIniciarSesion({
    required String userId,
    TipoDeSujeto tipo = TipoDeSujeto.natural,
    Documento? documento,
    Organizacion? organizacion,
    String? identityHash,
    String? identity,
    Map<String, dynamic>? datos,
  }) async {
    _asegurarIniciado();

    // 🔴 `identity` queda en desuso: se traduce ACÁ, una sola vez, para que
    // todo lo de abajo trabaje siempre con `documento` sin importar por cuál
    // de las dos entró quien integra.
    final documentoResuelto = documento ??
        (identity != null && identity.isNotEmpty
            ? Documento(clase: ClaseDeDocumento.cedula, numero: identity)
            : null);

    // ══ EL SUJETO NACE ACÁ, ANTES DE TOCAR NINGÚN PERMISO ═══════════════════
    //
    // Es el corazón del rediseño: hasta ahora, sin permiso no había token, y
    // sin token no había alta — quien decía que no a los avisos no quedaba
    // anotado en ningún lado. Yendo primero acá, esta persona existe para el
    // sistema con su aparato enlazado, aunque más abajo el permiso quede en
    // «denegado».
    //
    // 🔴 SIN HUELLA A PROPÓSITO, a diferencia del alta del token de más abajo.
    // El alta del token se acota con `HuellaDelRegistro` porque repetirla no
    // cambia nada; ésta se llama en CADA inicio de sesión porque el servidor
    // tiene que actualizar `visto.ultima` siempre, y porque es la única forma
    // de que un cambio de documento o de organización llegue al servidor sin
    // depender de que ADEMÁS haya cambiado el token o el permiso — que es
    // justo el error que la huella del token ya causó una vez con `datos`
    // (ver la nota en `HuellaDelRegistro`). No acotar esta llamada es cómo se
    // evita caer en el mismo agujero por otra puerta.
    try {
      final instalacionId = await _almacen.leerOCrearInstalacionId();
      await _api!.registrarSujeto(
        sujetoId: userId,
        tipo: tipo,
        documento: documentoResuelto,
        organizacion: organizacion,
        datos: datos,
        instalacionId: instalacionId,
      );
    } catch (e) {
      // 🔴 SI ESTO FALLA, EL REGISTRO DEL TOKEN SE INTENTA IGUAL — ver más
      // abajo. Encadenar el alta del token detrás de la del sujeto sin esta
      // salvaguarda dejaría a la persona sin avisos por una falla de red que
      // no tiene nada que ver con el permiso: un servidor caído en el instante
      // del login no le puede costar los avisos a nadie. Se anota para el
      // diagnóstico y se sigue.
      _ultimoError = e is AkPushError ? e : null;
    }

    // 🔴 Se le PREGUNTA al sistema operativo, no se confía en lo guardado. La
    // persona pudo haber apagado las notificaciones desde los Ajustes del
    // teléfono seis meses atrás y nada le avisó a la aplicación: lo que está en
    // disco puede estar viejo, y el sistema siempre tiene la verdad.
    final anterior = _userId ?? await _almacen.leerUsuario();
    _huella ??= HuellaDelRegistro.fromJson(await _almacen.leerHuella());
    var estado = await _permiso.estadoActual();

    final plan = planearInicioDeSesion(
      politica: _politica,
      userId: userId,
      estado: estado,
      token: _token,
      userIdAnterior: anterior,
      ultimoRegistro: _huella,
      yaSePregunto: await _almacen.yaSePreguntoElPermiso(),
      desdeLaUltimaPregunta: await _almacen.desdeLaUltimaPregunta(),
      ahora: DateTime.now(),
      // 🔴 Si al comercio le cambió la sucursal o el plan de esta persona, hay que
      // registrar de nuevo aunque el usuario, el token y el permiso sean idénticos.
      // Sin esto el servidor se queda con el dato viejo para siempre y los envíos
      // segmentados le pegan al grupo equivocado, sin ningún error visible.
      huellaDeDatos: HuellaDelRegistro.resumirDatos(datos),
    );

    // Primero la baja de la anterior: si el registro nuevo falla a mitad, el
    // teléfono tiene que quedar sin dueño y no con el de antes, que seguiría
    // recibiendo lo suyo.
    if (plan.darDeBajaALaAnterior && anterior != null && _token != null) {
      try {
        await _api!.darDeBaja(userId: anterior, token: _token!);
      } catch (_) {
        // Si la baja no llega, igual hay que seguir: dejar a la persona nueva
        // sin registrar sería peor que dejar a la anterior de más.
      }
    }

    if (plan.pedirPermiso) {
      estado = await _pedirPermisoAhora();
    }

    // Con el permiso ya resuelto, para que el servidor guarde el estado de
    // verdad y no el de hace un segundo.
    final concedido = estado.permiteRecibir;

    // Si el sistema dice algo distinto de lo que teníamos anotado, gana el
    // sistema y queda registrado el cambio. Es el caso de quien lo apagó —o lo
    // encendió— desde los Ajustes: sin esto, el servicio le sigue enviando a un
    // teléfono que no muestra nada, o deja de enviarle a uno que sí.
    if (_consentimiento.acepto != null && _consentimiento.acepto != concedido) {
      _consentimiento = _consentimiento.conSistema(
        acepto: concedido,
        cuando: DateTime.now(),
      );
      await _almacen.guardarConsentimiento(_consentimiento);
    }

    var seRegistro = false;

    // 🔴 LA HUELLA ES LA CONSTANCIA DE QUE EL SERVIDOR YA LO TIENE.
    //
    // `_registrado` vive en memoria y arranca en `false` en cada apertura de la
    // aplicación; la huella vive en disco y sobrevive. Al segundo arranque el plan dice
    // «no hace falta registrar, no cambió nada» —que es correcto y ahorra una llamada—
    // pero nadie levantaba la bandera, y entonces:
    //
    //   · `puedeRecibir` daba `false` a alguien que sí puede recibir
    //   · el motivo decía «no llegó a registrarse en el servidor», que es MENTIRA
    //
    // Visto en pantalla el 2026-08-31: «No puede recibir» sobre un teléfono registrado
    // hacía tres minutos. Y cualquier comercio que use `puedeRecibir` para decidir qué
    // mostrar, mostraba lo equivocado en cada arranque salvo el primero.
    //
    // Que el plan diga «no registrar» significa exactamente que el registro vigente
    // sirve. Eso es estar registrado.
    if (!plan.registrar && _huella != null && _token != null) {
      _registrado = true;
      _registradoEl ??= _huella!.cuando;
    }

    if (plan.registrar || (plan.pedirPermiso && _token != null)) {
      try {
        await _registrarAhora(
          userId: userId,
          identity: identity,
          identityHash: identityHash,
          datosDeLaPersona: datos,
          concedido: concedido,
          estado: estado,
        );
        seRegistro = true;
      } catch (e) {
        _ultimoError = e is AkPushError ? e : null;
      }
    }

    _userId = userId;
    await _almacen.guardarUsuario(userId);
    // Desde acá, lo que se anote de comportamiento es de esta persona. Lo anotado ANTES no
    // se le atribuye hacia atrás: la aplicación se abre antes de que nadie entre, y esos
    // eventos son de la instalación. El servicio ya sabe a qué sujeto pertenece cada una.
    _comportamiento.entroElSujeto(userId);

    // ── LA UBICACIÓN, DESPUÉS DE TODO LO DEMÁS ────────────────────────────────────
    //
    // Acá y no antes, por tres razones que se pagan caro si se saltean:
    //
    //  1. El permiso de notificaciones ya está resuelto. Dos diálogos del sistema
    //     seguidos es la forma más rápida de que la persona diga que no a los dos, y
    //     el de notificaciones es el que el producto necesita.
    //  2. El registro ya se hizo. Si el modal tarda —o la persona lo deja abierto—,
    //     su teléfono ya quedó registrado y le pueden llegar avisos igual.
    //  3. `_userId` ya está puesto, así que si acepta se puede mandar la primera
    //     posición en el mismo acto.
    //
    // No se espera el resultado: el inicio de sesión de la aplicación no se queda
    // colgado detrás de un modal que la persona puede dejar abierto un minuto.
    // 🔴 LA UBICACIÓN ESPERA A QUE SE CONTESTE LO DE LOS AVISOS. Antes salía en paralelo
    // —`unawaited` sobre la llamada— y los dos modales aparecían encima del otro: el de
    // ubicación tapaba al de avisos, que quedaba contestándose a ciegas o sin contestar.
    // Medido en el emulador el 2026-09-01, con los dos módulos activos y política «login».
    //
    // Se encadena y NO se espera el conjunto: el inicio de sesión de la aplicación sigue
    // sin quedarse colgado detrás de un modal que la persona puede dejar abierto un minuto,
    // pero los dos diálogos van uno después del otro.
    unawaited(() async {
      await _esperarAQueSeCierreElDeAvisos();
      await _ofrecerUbicacion(forzar: false);
    }());

    // ── LOS MÓDULOS DE NIVEL 0 ──────────────────────────────────────────────
    //
    // 🔴 HASTA HOY EL REGISTRO DE MÓDULOS ERA CÓDIGO MUERTO. Existía, estaba probado, y
    // nadie lo armaba ni lo corría: `aparato` nunca midió nada en producción, y el módulo
    // de autenticidad habría sido el tercero en la lista de cosas que existen y no se
    // ejecutan. Medido el 2026-09-01.
    //
    // Se corren acá, después de que el sujeto quedó enlazado, porque necesitan saber a
    // quién pertenece lo que miden. Y sin esperar: son señales, y ninguna vale que el
    // inicio de sesión tarde un segundo más.
    //
    // El registro los corre en paralelo, con ocho segundos de tope cada uno y un try por
    // módulo. Uno que falle o que se cuelgue no arrastra a los otros ni al push.
    unawaited(_correrModulos());

    // 🔴 Y A QUIEN YA DIO EL PERMISO, SE LE LEE LA POSICIÓN.
    //
    // Sin esta línea la ubicación se mandaba UNA sola vez en la vida —en el mismo
    // instante de conceder el permiso— y nunca más. Si esa única vez fallaba, no había
    // segunda: la persona figuraba con ubicación activa y cero posiciones para siempre.
    // Fue exactamente lo que pasó el 2026-08-31 en un HONOR con el interruptor de
    // ubicación apagado.
    //
    // El freno de seis horas vive adentro de `reportarSiCorresponde`, así que llamarlo
    // en cada inicio de sesión no gasta batería ni multiplica lecturas: en la mayoría
    // de las llamadas devuelve `false` sin tocar el GPS.
    unawaited(_ubicacion.reportarSiCorresponde(userId));

    return ResultadoDeSesion(
      puedeRecibir: concedido && _token != null && _registrado,
      estadoDelPermiso: estado,
      accionSugerida: plan.accionSugerida,
      huboCambioDePersona: plan.darDeBajaALaAnterior,
      seRegistro: seRegistro,
      motivo: motivoDeSesion(
        estado: estado,
        hayToken: _token != null,
        registrado: _registrado,
      ),
    );
  }

  /// El alta contra el servicio, más la huella que evita repetirla.
  Future<void> _registrarAhora({
    required String userId,
    required bool concedido,
    EstadoDelPermiso? estado,
    String? identity,
    String? identityHash,
    Map<String, dynamic>? datosDeLaPersona,
  }) async {
    final datos = await DatosDelDispositivo.recolectar();
    final cuandoSePregunto = await _almacen.cuandoSePregunto();

    await _api!.registrarDispositivo(
        // El mismo con el que se dio de alta la instalación: sin esto el servidor
        // la identifica por el `deviceId` del aparato y crea una segunda.
        instalacionId: await _almacen.leerOCrearInstalacionId(),
      userId: userId,
      token: _token!,
      plataforma: datos.plataforma,
      identity: identity,
      identityHash: identityHash,
      datos: datosDeLaPersona,
      deviceInfo: datos.toJson(),
      permisoConcedido: concedido,
      estadoDelPermiso: (estado ?? _estado).name,
      sePreguntoEl: cuandoSePregunto,
      consentimiento: _consentimiento.toJson(),
    );

    _registrado = true;
    _registradoEl = DateTime.now();
    _huella = HuellaDelRegistro(
      userId: userId,
      token: _token!,
      permisoConcedido: concedido,
      cuando: _registradoEl!,
      huellaDeDatos: HuellaDelRegistro.resumirDatos(datosDeLaPersona),
    );
    await _almacen.guardarHuella(_huella!.toJson());
  }

  Future<void> _identify({
    required String userId,
    String? identityHash,
    String? identity,
    Map<String, dynamic>? datos,
  }) async {
    _asegurarIniciado();

    if (_token == null) {
      // Sin permiso no hay token, y sin token no hay nada que registrar. No es
      // un error: es el resultado de que la persona dijo que no. `_registrado`
      // queda en false a propósito, y eso es lo que hace que el diagnóstico
      // pueda decir «se llamó a identify() pero el alta no llegó».
      await _almacen.guardarUsuario(userId);
      _userId = userId;
      return;
    }

    final delAparato = await DatosDelDispositivo.recolectar();

    await _api!.registrarDispositivo(
        // El mismo con el que se dio de alta la instalación: sin esto el servidor
        // la identifica por el `deviceId` del aparato y crea una segunda.
        instalacionId: await _almacen.leerOCrearInstalacionId(),
      userId: userId,
      token: _token!,
      plataforma: delAparato.plataforma,
      identity: identity,
      identityHash: identityHash,
      datos: datos,
      deviceInfo: delAparato.toJson(),
      // El servicio filtra por esto antes de enviar. Reportar `true` cuando la
      // persona dijo que no significa pagar envíos a un teléfono que no va a
      // mostrar nada, e inflar la tasa de entrega con ellos.
      permisoConcedido: _estado.permiteRecibir,
    );

    _registrado = true;
    _registradoEl = DateTime.now();

    _userId = userId;
    await _almacen.guardarUsuario(userId);
  }

  /// Desata este teléfono de la persona que estaba usándolo.
  ///
  /// Llamarlo al cerrar sesión no es opcional: sin esto, un teléfono que cambia
  /// de manos —vendido, prestado, compartido en familia— sigue recibiendo los
  /// avisos de la persona anterior.
  static Future<void> logout() => _yo._logout();

  Future<void> _logout() async {
    final userId = _userId ?? await _almacen.leerUsuario();
    final token = _token ?? await _almacen.leerToken();

    if (userId != null && token != null && _api != null) {
      try {
        await _api!.darDeBaja(userId: userId, token: token);
      } catch (_) {
        // Si la baja no llega, se intenta de nuevo en el próximo cierre. No se
        // le muestra nada a nadie.
      }
    }

    _userId = null;
    _registrado = false;
    _registradoEl = null;
    // Lo que se anote desde ahora es de la instalación y de nadie más. Lo ya encolado
    // conserva el sujeto que tenía: pertenece a quien lo hizo, no a quien entre después.
    _comportamiento.salioElSujeto();
    await _almacen.olvidarSesion();
    await Presentador.instancia.retirarTodos();

    // Una ruta guardada apunta a los datos de quien estaba usando el teléfono:
    // entregarla después del cierre lo llevaría a la pantalla de otro.
    IntencionPendiente.instancia.limpiar();
  }

  /// Reporta una acción que sólo la aplicación puede saber.
  ///
  /// [AccionDePush.delivered] y [AccionDePush.opened] las reporta el paquete
  /// solo. Las otras tres —vista, descartada, caducada— dependen de cómo esté
  /// hecha la aplicación, así que las reporta quien la escribe.
  static Future<void> reportar(
    PushMessage mensaje,
    AccionDePush accion,
  ) async {
    final id = mensaje.pushLogId;
    if (id == null) return;
    await _yo._api?.reportarEvento(pushLogId: id, accion: accion.valor);
  }

  Future<Diagnostico> _diagnostico() async => (await Diagnostico.reunir(
        config: _config,
        configPedidaAlServidor: _configDelServidor,
        token: _token,
        tokenObtenidoEl: _tokenObtenidoEl,
        userId: _userId,
        registradoEnElServidor: _registrado,
        registradoEl: _registradoEl,
        ultimoError: _ultimoError,
        almacen: _almacen,
        // Se le pasa el gestor y NO el estado: `_estado` es el del último
        // momento en que alguien preguntó, y el permiso se apaga desde los
        // Ajustes sin avisarle a nadie. Diagnosticar con el valor viejo diría
        // «permiso concedido» justo en el caso que más se reporta. El gestor sí
        // se reutiliza, para no volver a pagar la lectura del nivel de Android.
        gestorDePermiso: _permiso,
      ))
          // La ubicación se agrega después de reunir el resto: `reunir` es de este
          // paquete pero no conoce el módulo de ubicación, y no tiene por qué —
          // diagnosticar la mensajería y diagnosticar la ubicación son dos cosas.
          //
          // Sólo se agrega si el comercio la tiene activada: mostrar «sin ubicaciones»
          // a quien nunca la pidió sería un problema inventado.
          .conUbicacion(_politicaDeUbicacion.activa
              ? EstadoDeUbicacion(
                  permitida: await _ubicacion.concedido,
                  servicioPrendido: await _ubicacion.servicioPrendido,
                  ultimoEnvio: _ubicacion.ultimoEnvio,
                  ultimoMotivo: _ubicacion.ultimoMotivo,
                )
              : null);

  // ── Lo que llega ────────────────────────────────────────────────────────

  void _escuchar() {
    _suscripciones.add(
      FirebaseMessaging.onMessage.listen(_alLlegarEnPrimerPlano),
    );
    _suscripciones.add(
      FirebaseMessaging.onMessageOpenedApp.listen(_alTocar),
    );
    // El toque sobre el aviso que dibujó ESTE paquete no pasa por FCM. Sin esta
    // línea, tocar una notificación con la aplicación abierta no hace nada.
    _suscripciones.add(
      Presentador.instancia.alTocar.listen(_alTocar),
    );
    _suscripciones.add(
      FirebaseMessaging.instance.onTokenRefresh.listen(_alRotarElToken),
    );
  }

  Future<void> _alLlegarEnPrimerPlano(RemoteMessage crudo) async {
    final mensaje = _traducir(crudo);
    _recibidos.add(mensaje);

    // FCM no dibuja nada con la aplicación abierta. Si esto no corre, el aviso
    // no se ve y nada lo reporta.
    final decision = await _portero.resolver(mensaje);
    if (decision.seDibuja) {
      await Presentador.instancia.mostrar(mensaje, silencioso: decision.sinRuido);
    }

    // El reporte queda FUERA del `if` a propósito: el aviso llegó al teléfono, y
    // que la aplicación haya decidido no dibujarlo es una decisión posterior a
    // la entrega. Contarlo adentro haría que el comercio que MÁS cuida a su
    // gente sea el que peor mide.
    final id = mensaje.pushLogId;
    if (id != null) {
      await _api?.reportarEvento(
        pushLogId: id,
        accion: AccionDePush.delivered.valor,
        estadoApp: 'FOREGROUND',
      );
    }
  }

  Future<void> _alTocar(dynamic entrada) async {
    final mensaje = entrada is RemoteMessage ? _traducir(entrada) : entrada as PushMessage;

    // El mismo toque llega dos veces con la aplicación cerrada: el sistema lo
    // reporta por getInitialMessage Y por onMessageOpenedApp, con el mismo id.
    // Sin esto se mide doble y se abre dos veces.
    final id = mensaje.messageId;
    if (id != null && !_toquesYaVistos.add(id)) return;

    // La intención se guarda ANTES de publicar el toque: quien escuche
    // onNotificationTap y mire la ruta pendiente en el mismo instante tiene que
    // encontrarla ya guardada, no medio cuadro después. Y va después del guard
    // de duplicados, o el toque doble del arranque en frío la guardaría dos
    // veces.
    IntencionPendiente.instancia.guardarDesde(mensaje);

    _tocados.add(mensaje);
    await Presentador.instancia.retirar(mensaje);

    final log = mensaje.pushLogId;
    if (log != null) {
      await _api?.reportarEvento(
        pushLogId: log,
        accion: AccionDePush.opened.valor,
        estadoApp: 'BACKGROUND',
      );
    }
  }

  Future<void> _alRotarElToken(String nuevo) async {
    _token = nuevo;
    _tokenObtenidoEl = DateTime.now();
    await _almacen.guardarToken(nuevo);

    // FCM rota el token solo, y el registro viejo deja de entregar en ese
    // momento. Si hay una persona atada a este teléfono, hay que volver a
    // registrarlo ya: esperar al próximo inicio de sesión deja al teléfono
    // silenciosamente inalcanzable mientras tanto.
    final userId = _userId ?? await _almacen.leerUsuario();
    if (userId == null) return;

    final datos = await DatosDelDispositivo.recolectar();
    try {
      await _api?.registrarDispositivo(
        // El mismo con el que se dio de alta la instalación: sin esto el servidor
        // la identifica por el `deviceId` del aparato y crea una segunda.
        instalacionId: await _almacen.leerOCrearInstalacionId(),
        userId: userId,
        token: nuevo,
        plataforma: datos.plataforma,
        deviceInfo: datos.toJson(),
        permisoConcedido: _estado.permiteRecibir,
      );
      _registrado = true;
      _registradoEl = DateTime.now();
    } catch (e) {
      // Ésta es la ventana muda: el token nuevo no lo tiene nadie anotado y el
      // viejo ya no entrega. Se anota para que el diagnóstico pueda decirlo, en
      // vez de que el teléfono quede inalcanzable sin ningún síntoma.
      _registrado = false;
      _ultimoError = e is AkPushError
          ? e
          : AkPushError(
              AkPushErrorCode.unknown,
              'No se pudo re-registrar el token rotado',
              details: e.toString(),
            );
    }
  }

  Future<void> _procesarArranqueEnFrio() async {
    try {
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (inicial != null) await _alTocar(inicial);
    } catch (_) {
      // Un arranque en frío sin mensaje inicial es lo normal.
    }
  }

  PushMessage _traducir(RemoteMessage m) => PushMessage(
        data: m.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
        title: m.notification?.title,
        body: m.notification?.body,
        messageId: m.messageId,
      );

  void _asegurarIniciado() {
    if (_api == null || _config == null) {
      throw AkPushError(
        AkPushErrorCode.notInitialized,
        'AkPush todavía no terminó de iniciarse',
        details:
            'AkPush.init() es asíncrono. Esperá a que termine antes de llamar a '
            'identify() o logout() — por ejemplo, deshabilitá el botón de inicio '
            'de sesión hasta que init() resuelva.',
      );
    }
  }
}

extension _Primero<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
