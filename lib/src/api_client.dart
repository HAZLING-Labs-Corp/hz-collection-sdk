import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'remote_config.dart';
import 'sujeto.dart';

/// Cliente de las rutas del servicio.
///
/// Todo lo que sale de acá lleva la llave **pública** (`akp_pub_…`). Es pública
/// por construcción: va dentro de la aplicación, y lo que va dentro de una
/// aplicación lo puede leer cualquiera que la descomprima. Por eso solo permite
/// pedir la configuración, dar de alta el dispositivo que la presenta, y
/// reportar qué pasó con un aviso. **Enviar necesita la otra llave, que vive en
/// el servidor del comercio y nunca llega acá.**
class AkPushApi {
  AkPushApi({
    required this.apiKey,
    required this.baseUrl,
    http.Client? cliente,
    this.timeout = const Duration(seconds: 10),
  }) : _cliente = cliente ?? http.Client();

  /// Quita el `/api/v1` del final si vino, y las barras sueltas.
  ///
  /// La consola le muestra al comercio la dirección **con** el sufijo, así que
  /// quien la siga al pie de la letra la va a pegar completa — y el paquete lo
  /// agrega por su cuenta. Sin esto la petición sale a `/api/v1/api/v1/…`, el
  /// servidor contesta su 404 genérico, y el error que ve quien integra no se
  /// parece en nada a «el prefijo está dos veces».
  static String normalizarUrl(String url) => url
      .replaceAll(RegExp(r'/+$'), '')
      .replaceAll(RegExp(r'/api/v1$'), '');

  final String apiKey;

  /// La dirección del servicio, **sin** el `/api/v1` final: el paquete lo
  /// agrega.
  ///
  /// Se acepta igual con el sufijo, porque la consola se lo muestra así al
  /// comercio y quien la siga al pie de la letra lo va a pegar completo. Sin
  /// esta normalización la petición sale a `/api/v1/api/v1/…`, el servidor
  /// contesta su 404 genérico, y el error que ve quien integra no se parece en
  /// nada a «la dirección tiene el prefijo dos veces».
  final String baseUrl;

  final Duration timeout;
  final http.Client _cliente;

  Map<String, String> get _cabeceras => {
        'content-type': 'application/json',
        // El comercio NO se declara: sale de la llave, del lado del servicio.
        // Declararlo repitiendo lo que el servicio contestó no comprueba nada, y
        // pedirlo por configuración es pedir un dato que el sistema ya sabe.
        'authorization': 'Bearer $apiKey',
      };

  /// Pide la configuración que le toca a esta aplicación.
  ///
  /// [identificadorDePaquete] no es opcional y no es burocracia: es lo que
  /// permite al servidor verificar que la configuración que va a entregar
  /// corresponde a ESTA aplicación. Si no coincidieran, la aplicación
  /// inicializaría Firebase, pediría su token y no lo obtendría —o lo obtendría
  /// y no le llegaría nada— sin ninguna excepción ni registro. Un 409 explícito
  /// es infinitamente más barato de diagnosticar que una aplicación muda.
  Future<AkPushConfig> obtenerConfig(String identificadorDePaquete) async {
    final uri = Uri.parse('$baseUrl/api/v1/configuracion')
        .replace(queryParameters: {'paquete': identificadorDePaquete});

    final json = await _pedir(() => _cliente.get(uri, headers: _cabeceras));
    return AkPushConfig.fromJson(json);
  }

  /// Da de alta —o actualiza— EL APARATO. Nace apenas arranca la aplicación,
  /// **sin token y sin sujeto**: todavía no se pidió permiso y todavía no
  /// entró nadie. El sujeto lo enlaza después, al iniciar sesión — ver
  /// [registrarSujeto].
  ///
  /// Es upsert por [instalacionId], que genera y persiste el propio SDK — ver
  /// `ConfigStore.leerOCrearInstalacionId`. Llamarlo de nuevo en cada arranque
  /// no duplica nada: actualiza el mismo aparato.
  Future<void> registrarInstalacion({
    required String instalacionId,
    required Map<String, dynamic> aparato,
    String? sujetoId,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/instalaciones'),
          headers: _cabeceras,
          body: jsonEncode({
            'instalacionId': instalacionId,
            'aparato': aparato,
            if (sujetoId != null) 'sujetoId': sujetoId,
          }),
        ));
  }

  /// Da de alta —o actualiza— EL SUJETO: quien se loguea.
  ///
  /// Es la raíz del modelo nuevo, y por eso se llama al iniciar sesión, ANTES
  /// de tocar ningún permiso — ver la nota grande en `AkPush.alIniciarSesion`.
  /// Es lo que hace que una persona exista para el sistema aunque conteste que
  /// no a los avisos: antes de esto, un «no» temprano la dejaba invisible.
  ///
  /// Si viene [instalacionId], el servidor enlaza esa instalación a este
  /// sujeto — y desenlaza la que tenía antes, si era otra.
  Future<void> registrarSujeto({
    required String sujetoId,
    required TipoDeSujeto tipo,
    Documento? documento,
    Organizacion? organizacion,
    Map<String, dynamic>? datos,
    String? instalacionId,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/sujetos'),
          headers: _cabeceras,
          body: jsonEncode({
            'sujetoId': sujetoId,
            'tipo': tipo.valor,
            if (documento != null) 'documento': documento.toJson(),
            if (organizacion != null) 'organizacion': organizacion.toJson(),
            if (datos != null && datos.isNotEmpty) 'datos': datos,
            if (instalacionId != null) 'instalacionId': instalacionId,
          }),
        ));
  }

  /// Actualiza el MÓDULO DE AVISOS de esta instalación: el token de FCM, si
  /// hay permiso, y qué se le preguntó.
  ///
  /// 🔴 Hasta el rediseño, esto ERA el alta de la persona — el token era la
  /// raíz. Ahora la raíz es el sujeto ([registrarSujeto]) y esto sólo carga
  /// el módulo `avisos` de la instalación que ya existe. La URL no cambió —
  /// sigue siendo `/api/v1/dispositivos`— porque del lado del servidor quedó
  /// como un alias en desuso que traduce al formato nuevo, para que una
  /// aplicación ya instalada no se rompa entre despliegues.
  Future<void> registrarDispositivo({
    required String userId,
    required String token,
    required String plataforma,
    /// 🔴 EL MISMO QUE SE USÓ AL DAR DE ALTA LA INSTALACIÓN.
    ///
    /// Sin esto el servidor no puede saber que este token es del aparato que ya
    /// registró, y cae al camino viejo: identifica la instalación por el `deviceId`
    /// del aparato y **crea una segunda**. Medido el 2026-08-31 contra una base
    /// limpia: una persona, un teléfono, dos instalaciones.
    ///
    /// Es opcional sólo para no romper a quien llame este método sin él; el SDK
    /// siempre lo manda.
    String? instalacionId,
    String? identity,
    String? identityHash,
    /// Lo que el comercio sabe de esta persona: nombre, sucursal, plan, lo que sea.
    Map<String, dynamic>? datos,
    Map<String, dynamic>? deviceInfo,
    bool permisoConcedido = true,
    String? estadoDelPermiso,
    DateTime? sePreguntoEl,
    Map<String, dynamic>? consentimiento,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/dispositivos'),
          headers: _cabeceras,
          body: jsonEncode({
            if (instalacionId != null) 'instalacionId': instalacionId,
            'userId': userId,
            'token': token,
            'platform': plataforma,
            // El servicio filtra por esto antes de enviar: un dispositivo sin
            // permiso concedido no recibe intentos, y por lo tanto no se cobra.
            'permissionsGranted': permisoConcedido,
            // 🔴 El booleano no alcanza, y ésta es la diferencia que el comercio
            // necesita ver: «nunca se le preguntó» y «se le preguntó y dijo que
            // no» son dos cosas distintas y piden acciones opuestas. A la
            // primera hay que preguntarle; a la segunda, dejarla en paz o
            // mandarla a los Ajustes.
            //
            // Y no se puede saber QUÉ contestó alguien a quien nunca se le
            // mostró la pregunta — pero sí se puede saber **que se le mostró**,
            // que es lo único que convierte el «no» en un número medible.
            if (estadoDelPermiso != null) 'estadoDelPermiso': estadoDelPermiso,
            if (sePreguntoEl != null)
              'sePreguntoEl': sePreguntoEl.toUtc().toIso8601String(),
            // El rastro de las DOS preguntas. `punto` es el resumen que la
            // consola puede mostrar sin interpretar fechas: sin_preguntar,
            // dijo_ahora_no, esperando_al_sistema, acepto,
            // denego_en_el_sistema.
            if (consentimiento != null) 'consentimiento': consentimiento,
            if (identity != null) 'identity': identity,
            if (identityHash != null) 'identityHash': identityHash,
            // 🔴 LO QUE EL COMERCIO SABE DE ESTA PERSONA, y que nosotros no podemos
            // inventar: su nombre, su sucursal, su plan, su segmento.
            //
            // Sin esto, la consola muestra un identificador opaco —`u_9000`— y no hay
            // forma de buscar a nadie ni de segmentar un envío. El servicio ya sabe
            // filtrar por estos campos y los DESCUBRE solo: no hay que declararlos en
            // ningún lado, basta con mandarlos.
            //
            // Se manda en cada registro, no una sola vez: la sucursal de una persona
            // cambia, y el plan más todavía.
            if (datos != null && datos.isNotEmpty) 'metadata': datos,
            if (deviceInfo != null) 'deviceInfo': deviceInfo,
          }),
        ));
  }

  /// Dónde está esta persona.
  ///
  /// Va aparte del registro del dispositivo y no dentro: la posición cambia
  /// mucho más seguido que el teléfono, y meterla en el alta obligaría a
  /// re-registrar el dispositivo entero cada vez que alguien se mueve.
  Future<void> reportarUbicacion({
    required String userId,
    required Map<String, dynamic> posicion,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/ubicacion'),
          headers: _cabeceras,
          body: jsonEncode({'userId': userId, 'posiciones': [posicion]}),
        ));
  }

  /// Da de baja este dispositivo.
  ///
  /// Es lo que evita que un teléfono que cambia de manos —vendido, prestado,
  /// compartido en familia— siga recibiendo los avisos de la persona anterior.
  Future<void> darDeBaja({required String userId, required String token}) async {
    // Los dos identificadores van en la ruta, así que hay que escaparlos: un
    // token de FCM trae `:` y otros caracteres que sin escapar parten la ruta
    // en pedazos y producen un 404 que no tiene nada que ver con la baja.
    final uri = Uri.parse(
      '$baseUrl/api/v1/dispositivos/'
      '${Uri.encodeComponent(userId)}/${Uri.encodeComponent(token)}',
    );
    await _pedir(() => _cliente.delete(uri, headers: _cabeceras));
  }

  /// Reporta qué pasó con un aviso. Es «lo mejor que se pueda»: un fallo acá
  /// nunca debe llegar a la persona que usa la aplicación.
  Future<void> reportarEvento({
    required String pushLogId,
    required String accion,
    String? estadoApp,
  }) async {
    try {
      await _pedir(() => _cliente.post(
            Uri.parse('$baseUrl/api/v1/interacciones'),
            headers: _cabeceras,
            body: jsonEncode({
              'pushLogId': pushLogId,
              'accion': accion,
              if (estadoApp != null) 'appState': estadoApp,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            }),
          ));
    } catch (_) {
      // Silencio a propósito: la medición no puede cambiar el comportamiento
      // de la aplicación. Un evento perdido cuesta un dato; un error mostrado
      // por una medición cuesta la confianza en la aplicación.
    }
  }

  Future<Map<String, dynamic>> _pedir(
    Future<http.Response> Function() peticion,
  ) async {
    http.Response respuesta;
    try {
      respuesta = await peticion().timeout(timeout);
    } catch (e) {
      throw AkPushError(
        AkPushErrorCode.network,
        'No se pudo contactar el servicio',
        details: e.toString(),
      );
    }

    Map<String, dynamic> json;
    try {
      json = respuesta.body.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(respuesta.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw AkPushError(
        AkPushErrorCode.unknown,
        'El servicio devolvió una respuesta que no se pudo leer',
      );
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 &&
        json['ok'] != false) {
      return json;
    }

    // El servicio contesta `{ ok:false, error?, message }`: `error` sólo viene
    // en los rechazos de credencial, y `message` siempre.
    final mensaje = json['message'] as String? ??
        json['error'] as String? ??
        'Error ${respuesta.statusCode}';
    final detalle = json['error'] as String?;

    final codigo = switch (respuesta.statusCode) {
      // El comercio encendió la verificación de identidad y esta llamada no
      // trae una firma válida. No es un problema de la llave.
      403 when json['error'] == 'identidad_no_verificada' =>
        AkPushErrorCode.firmaDeIdentidad,
      401 || 403 => AkPushErrorCode.unauthorized,
      // 🔴 Hay DOS clases de 404 y confundirlas manda a buscar en el lugar
      // equivocado.
      //
      // El del servicio —«este paquete no está registrado en tu comercio»—
      // trae `ok:false` y un `message` que lo explica: ése sí es appMismatch.
      //
      // El OTRO es el 404 genérico del servidor cuando la ruta no existe, y
      // casi siempre significa que la dirección está mal configurada. Decirle a
      // quien integra que «la app no coincide con la registrada» cuando lo que
      // pasa es que la URL tiene el prefijo dos veces le hace revisar el
      // registro del paquete durante una hora.
      404 => json['ok'] == false
          ? AkPushErrorCode.appMismatch
          : AkPushErrorCode.rutaNoEncontrada,
      502 || 503 => AkPushErrorCode.serviceUnavailable,
      _ => AkPushErrorCode.unknown,
    };

    throw AkPushError(codigo, mensaje, details: detalle);
  }

  /// LO QUE SE MIDIÓ DEL APARATO — el módulo `aparato`.
  ///
  /// Va a la instalación, no al sujeto: lo que se midió lo midió un teléfono, y una persona
  /// puede tener dos. Y es un mapa abierto a propósito: cada módulo manda lo suyo sin que
  /// esta firma tenga que cambiar cada vez.
  /// Devuelve `null` si se guardó, o el MOTIVO si el servicio lo descartó.
  Future<String?> reportarSenales({
    required String sujetoId,
    required String instalacionId,
    required Map<String, dynamic> senales,
    /// 🔴 A qué módulo pertenece la medición. Sin esto, el servicio guardaba TODO en el
    /// mismo lugar y el segundo módulo que midiera pisaba al primero, sin ningún error.
    /// Por omisión `aparato`, que es donde caía antes: así el APK viejo no cambia.
    String modulo = 'aparato',
  }) async {
    final r = await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/senales'),
          headers: _cabeceras,
          body: jsonEncode({
            'sujetoId': sujetoId,
            'instalacionId': instalacionId,
            'modulo': modulo,
            'senales': senales,
          }),
        ));

    /**
     * 🔴 SE LEE LO QUE CONTESTÓ, Y ANTES SE TIRABA.
     *
     * El servicio acepta con 200 y a veces DESCARTA: cuando el comercio tiene el módulo
     * apagado devuelve `{ok: true, noSeGuardo: {modulo, porQue}}`. Como el cuerpo se
     * ignoraba, un descarte era indistinguible de un guardado.
     *
     * Medido el 2026-09-01: las señales de un comercio se tiraron durante toda una tarde
     * mientras el teléfono y la consola decían que todo andaba. Se descubrió por el TAMAÑO
     * de la respuesta en los registros del servidor —22 bytes contra 106—, que es una forma
     * absurda de enterarse de algo que el servicio estaba diciendo con palabras.
     *
     * Devolver el motivo permite que el módulo lo ponga en su diagnóstico. No se lanza una
     * excepción: no es un error del que llama, es la configuración del comercio funcionando.
     */
    final descarte = r['noSeGuardo'];
    if (descarte is Map) {
      final porQue = descarte['porQue'];
      return porQue is String && porQue.isNotEmpty
          ? porQue
          : 'el servicio descartó la medición y no dijo por qué';
    }
    return null;
  }

  /// EL COMPORTAMIENTO DENTRO DE LA PROPIA APLICACIÓN, POR LOTE.
  ///
  /// 🔴 **POR LOTE Y NO POR EVENTO, y eso es la mitad del valor de esta ruta.** Un
  /// formulario de ocho campos genera unos veinte eventos; mandarlos de a uno serían veinte
  /// peticiones mientras la persona escribe, cada una levantando la radio del teléfono. Los
  /// eventos se guardan en el teléfono y salen todos juntos en la próxima apertura — ver
  /// `Comportamiento.transmitir`.
  ///
  /// ══ EL CONTRATO, Y LO QUE ESTE LADO LE AGREGA ══
  ///
  /// El contrato del 2026-09-04 fija el arreglo: `{ eventos: [ { tipo, cuando, ms, datos } ] }`.
  /// Eso viaja tal cual y no se toca.
  ///
  /// 🔴 Al lado van **`sujetoId` e `instalacionId`**, que el contrato no nombra. No es una
  /// libertad: sin ellos el lote no se puede atribuir a nadie. La llave pública dice de qué
  /// COMERCIO es la petición, no de qué persona, así que un lote sin sujeto es un lote que
  /// del otro lado no se puede guardar en ninguna serie. Van en el sobre y no adentro de
  /// cada evento para no repetir el mismo identificador doscientas veces en un cuerpo.
  /// **Está anotado para avisarle al frente que construye el back**: si allá se decidió
  /// leerlo de otro lado, se cambia acá y no al revés.
  ///
  /// `sujetoId` puede ser nulo con toda legitimidad: la aplicación se abre antes de que
  /// nadie inicie sesión, y esos eventos son de la instalación. El servicio ya sabe a qué
  /// sujeto pertenece una instalación.
  Future<void> reportarComportamiento({
    required String instalacionId,
    required List<Map<String, Object?>> eventos,
    String? sujetoId,
  }) async {
    if (eventos.isEmpty) return;
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/comportamiento'),
          headers: _cabeceras,
          body: jsonEncode({
            'instalacionId': instalacionId,
            if (sujetoId != null) 'sujetoId': sujetoId,
            'eventos': eventos,
          }),
        ));
  }

  /// ANOTA LO QUE LA PERSONA DECIDIÓ, CON EL TEXTO QUE TENÍA DELANTE.
  ///
  /// 🔴 MANDA EL TEXTO MOSTRADO, y el servicio rechaza si falta. No es burocracia: el
  /// texto del comercio cambia, y dentro de un año «aceptó» sin el texto es anotar que
  /// alguien apretó un botón. Lo que hay que poder demostrar es a QUÉ dijo que sí.
  ///
  /// Es telemetría de cumplimiento: nunca puede romperle nada a la aplicación anfitriona,
  /// así que quien la llama envuelve la llamada y se traga el fallo.
  Future<void> anotarConsentimiento({
    required String categoria,
    required bool concedido,
    required String textoMostrado,
    required int versionDelTexto,
    String? sujetoId,
    String? instalacionId,
    String? versionDeLaApp,
    String? plataforma,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/consentimiento'),
          headers: _cabeceras,
          body: jsonEncode({
            'categoria': categoria,
            'decision': concedido ? 'concedido' : 'revocado',
            'textoMostrado': textoMostrado,
            'versionDelTexto': versionDelTexto,
            if (sujetoId != null) 'sujetoId': sujetoId,
            if (instalacionId != null) 'instalacionId': instalacionId,
            if (versionDeLaApp != null) 'versionDeLaApp': versionDeLaApp,
            if (plataforma != null) 'plataforma': plataforma,
          }),
        ));
  }

  /// LA DIRECCIÓN DE ESTA INSTALACIÓN, SIN NECESIDAD DE QUE HAYA NADIE LOGUEADO.
  ///
  /// El token pertenece al APARATO. Antes sólo llegaba al servidor dentro del alta de un
  /// dispositivo, que ocurre al iniciar sesión — así que una aplicación donde nadie se
  /// loguea figuraba sin dirección para siempre, aunque la tuviera.
  Future<void> actualizarAvisosDeInstalacion({
    required String instalacionId,
    required String token,
    required String plataforma,
    required bool permiso,
    String? estadoDelPermiso,
  }) async {
    await _pedir(() => _cliente.post(
          Uri.parse('$baseUrl/api/v1/instalaciones'),
          headers: _cabeceras,
          body: jsonEncode({
            'instalacionId': instalacionId,
            'avisos': {
              'token': token,
              'plataforma': plataforma,
              'permiso': permiso,
              if (estadoDelPermiso != null) 'estado': estadoDelPermiso,
            },
          }),
        ));
  }
}
