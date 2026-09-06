import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consentimiento.dart';
import 'politica.dart';

/// Un módulo del catálogo, tal como lo describe el servidor.
///
/// El catálogo —`avisos`, `ubicacion`, `senales`, `rastreo`— vive en CÓDIGO del
/// lado del servicio, no en una base de datos: el comercio no lo edita, sólo
/// activa o desactiva lo que ya existe. Acá sólo se **lee** lo que el servidor
/// describe de cada uno.
///
/// 🔴 `estado` distingue lo que está construido de lo que sólo tiene lugar en
/// el modelo. Un módulo con `estado: 'declarado'` **no está implementado**: no
/// inventar su comportamiento a partir de este objeto es justamente lo que
/// evita construir sobre un módulo que todavía no existe del otro lado.
class InfoDeModulo {
  const InfoDeModulo({
    required this.nivel,
    required this.cadencia,
    required this.permisos,
    required this.estado,
  });

  /// 0 sin permiso · 1 permiso simple · 2 permiso caro (asusta en la ficha de
  /// Play) · 3 revisión manual de Google.
  final int nivel;

  /// `episodica` una vez · `periodica` al abrir con freno · `evento` cuando
  /// pasa algo · `continua` en segundo plano.
  final String cadencia;

  /// Los permisos NATIVOS que este módulo necesita, informativo nada más: el
  /// paquete no los pide ni los declara por su cuenta. Cualquier permiso nuevo
  /// va en el manifest de la aplicación anfitriona — este paquete no puede
  /// fusionar uno propio.
  final List<String> permisos;

  /// `activo` está construido · `declarado` tiene lugar en el modelo pero
  /// todavía no. Un valor que no se reconoce no se inventa: queda tal cual
  /// llegó, y [construido] lo trata como no construido.
  final String estado;

  bool get construido => estado == 'activo';

  factory InfoDeModulo.fromJson(Map<String, dynamic> j) => InfoDeModulo(
        nivel: (j['nivel'] as num?)?.toInt() ?? 0,
        cadencia: j['cadencia'] as String? ?? '',
        permisos: (j['permisos'] as List?)?.map((e) => '$e').toList() ??
            const <String>[],
        estado: j['estado'] as String? ?? 'declarado',
      );

  Map<String, dynamic> toJson() => {
        'nivel': nivel,
        'cadencia': cadencia,
        'permisos': permisos,
        'estado': estado,
      };
}

/// La configuración de Firebase que este comercio tiene asignada hoy.
///
/// No viene de un archivo pegado en el proyecto: la sirve el servidor en cada
/// arranque. Ése es el mecanismo que permite mover un comercio de una cuenta de
/// Google a otra **sin publicar una versión nueva** de la aplicación — que es la
/// operación que hoy obliga a recompilar, subir a las tiendas, esperar la
/// revisión de Apple y después esperar a que cada persona actualice.
class AkPushConfig {
  const AkPushConfig({
    required this.projectId,
    required this.appId,
    required this.apiKey,
    required this.messagingSenderId,
    required this.version,
    this.comercio,
    this.politica = PoliticaDeNotificaciones.comoEstabaAntes,
    this.ubicacion = const PoliticaDeUbicacion(),
    this.trajoPolitica = false,
    this.modulos = const {},
  });

  final String projectId;
  final String appId;
  final String apiKey;
  final String messagingSenderId;

  /// Huella de esta configuración.
  ///
  /// Es lo que deja detectar que el comercio cambió de cuenta. Sin ella no hay
  /// forma de saberlo, y un cambio de cuenta dejaría mudos a todos los
  /// teléfonos **sin ningún error visible**: los tokens viejos pertenecen al
  /// proyecto anterior y el nuevo no los reconoce.
  final String version;

  FirebaseOptions toFirebaseOptions() => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );

  /// El comercio al que pertenece esta configuración. Sirve para diagnosticar,
  /// no para decidir: quien manda es la llave.
  final String? comercio;

  /// Lo que el comercio configuró sobre cuándo y cómo pedir el permiso.
  ///
  /// Si el servicio todavía no manda el campo, es la política de siempre: pedir
  /// en el arranque, sin pregunta blanda. Nadie ve un cambio hasta que el
  /// comercio configure algo.
  final PoliticaDeNotificaciones politica;

  /// Si se le ofrece a la persona compartir su zona, y con qué palabras. Si el servidor
  /// no la manda —una versión vieja del servicio—, queda apagada: nunca se pide un
  /// permiso porque un campo faltó.
  final PoliticaDeUbicacion ubicacion;

  /// Si la política vino del servidor o es la de siempre porque el campo todavía
  /// no existe. Sirve para no pisar la que declaró la aplicación.
  final bool trajoPolitica;

  /// El catálogo de módulos que el servidor tiene para este comercio —
  /// `avisos`, `ubicacion`, y los que se declaren pero todavía no estén
  /// construidos—, con la clave siendo el nombre del módulo.
  ///
  /// Tolera que el servicio todavía no lo mande: queda vacío, y nadie ve un
  /// cambio hasta que el campo exista del otro lado.
  final Map<String, InfoDeModulo> modulos;

  factory AkPushConfig.fromJson(Map<String, dynamic> json) {
    final fb = (json['firebase'] as Map).cast<String, dynamic>();
    return AkPushConfig(
      projectId: fb['projectId'] as String,
      appId: fb['appId'] as String,
      apiKey: fb['apiKey'] as String,
      messagingSenderId: fb['messagingSenderId'] as String,
      // El servicio la manda como número; acá se guarda como texto porque lo
      // único que importa es comparar si cambió, no cuánto vale.
      version: '${json['version'] ?? ''}',
      comercio: json['comercio'] as String?,
      trajoPolitica: json['politica'] is Map,
      ubicacion: PoliticaDeUbicacion.fromJson(
        json['ubicacion'] is Map
            ? (json['ubicacion'] as Map).cast<String, dynamic>()
            : null,
      ),
      politica: PoliticaDeNotificaciones.fromJson(
        json['politica'] is Map
            ? (json['politica'] as Map).cast<String, dynamic>()
            : null,
      ),
      modulos: json['modulos'] is Map
          ? (json['modulos'] as Map).map((clave, valor) => MapEntry(
                '$clave',
                InfoDeModulo.fromJson(
                  valor is Map ? (valor).cast<String, dynamic>() : const {},
                ),
              ))
          : const {},
    );
  }

  /// Se guarda con la MISMA forma que devuelve el servicio, para que
  /// [fromJson] sirva igual para lo que llega por la red y para lo que se leyó
  /// del disco. Dos formas distintas serían dos maneras de romperse.
  Map<String, dynamic> toJson() => {
        'firebase': {
          'projectId': projectId,
          'appId': appId,
          'apiKey': apiKey,
          'messagingSenderId': messagingSenderId,
        },
        'version': version,
        if (comercio != null) 'comercio': comercio,
        'politica': politica.toJson(),
        if (modulos.isNotEmpty)
          'modulos': modulos.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// Guarda y recupera la última configuración conocida.
///
/// Sin esto, un primer arranque sin señal deja al teléfono sin registrar y sin
/// forma de recuperarse hasta la próxima vez que abra con conexión. Con esto,
/// **solo la primerísima instalación depende de tener red**.
class ConfigStore {
  static const _claveConfig = 'akpush.config';
  static const _claveToken = 'akpush.token';
  static const _claveUsuario = 'akpush.userId';
  static const _claveHuella = 'akpush.huella';
  static const _clavePregunta = 'akpush.ultimaPregunta';
  static const _claveConsentimiento = 'akpush.consentimiento';
  static const _claveCredencial = 'akpush.credencial';

  /// El identificador de ESTE APARATO en el modelo nuevo. Lo genera el SDK y
  /// vive acá, no en el sistema operativo.
  static const _claveInstalacionId = 'akpush.instalacionId';

  /// Cuándo se le OFRECIÓ la ubicación por última vez.
  ///
  /// 🔴 Es distinto de cuándo se le pidió el permiso del sistema, y por eso tiene su
  /// propia clave. La oferta es nuestra —el modal— y la controla la política del
  /// comercio; el permiso lo controla Android y su «no» es definitivo. Mezclarlas en
  /// una sola fecha haría que reinsistir con notificaciones apagara la ubicación, o
  /// al revés.
  static const _claveOfertaUbicacion = 'akpush.ofertaUbicacion';

  /// Cuándo se le avisó por última vez que el TELÉFONO tiene la ubicación apagada.
  /// Clave propia, separada de la oferta: son dos avisos con dos causas distintas, y
  /// compartir la fecha haría que uno tapara al otro durante semanas.
  static const _claveAvisoServicio = 'akpush.avisoServicioUbicacion';

  /// La SEGUNDA oferta —la de «siempre»— lleva su propia fecha, y no comparte la de arriba.
  ///
  /// 🔴 Compartirla haría que una tape a la otra: quien acaba de aceptar la zona tiene la
  /// fecha de hoy anotada, así que la oferta de «siempre» no saldría hasta dentro de dos
  /// semanas — justo cuando la persona ya se olvidó de qué es esta aplicación. Son dos
  /// preguntas distintas con dos relojes distintos.
  static const _claveOfertaSiempre = 'akpush.ofertaUbicacionSiempre';

  Future<AkPushConfig?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveConfig);
    if (crudo == null) return null;
    try {
      return AkPushConfig.fromJson(jsonDecode(crudo) as Map<String, dynamic>);
    } catch (_) {
      // Una configuración guardada que ya no se puede leer es peor que
      // ninguna: se descarta en silencio y se pide de nuevo.
      return null;
    }
  }

  Future<void> guardar(AkPushConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveConfig, jsonEncode(config.toJson()));
  }

  Future<String?> leerToken() async =>
      (await SharedPreferences.getInstance()).getString(_claveToken);

  Future<void> guardarToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(_claveToken, token);

  Future<String?> leerUsuario() async =>
      (await SharedPreferences.getInstance()).getString(_claveUsuario);

  Future<void> guardarUsuario(String userId) async =>
      (await SharedPreferences.getInstance()).setString(_claveUsuario, userId);

  /// La huella del último registro. Ver [HuellaDelRegistro] en `sesion.dart`.
  Future<Map<String, dynamic>?> leerHuella() async {
    final crudo = (await SharedPreferences.getInstance()).getString(_claveHuella);
    if (crudo == null) return null;
    try {
      return (jsonDecode(crudo) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarHuella(Map<String, dynamic> h) async =>
      (await SharedPreferences.getInstance())
          .setString(_claveHuella, jsonEncode(h));

  /// Cuándo se le preguntó por última vez. Es lo que hace que a quien dijo
  /// «ahora no» no se le vuelva a preguntar al día siguiente — que es cómo se
  /// consigue una desinstalación.
  Future<void> anotarQueSePregunto() async =>
      (await SharedPreferences.getInstance())
          .setString(_clavePregunta, DateTime.now().toIso8601String());

  Future<bool> yaSePreguntoElPermiso() async =>
      (await SharedPreferences.getInstance()).getString(_clavePregunta) != null;

  /// Cuándo se le mostró la pregunta por última vez. Es lo que le permite al
  /// comercio distinguir a quien dijo que no de quien nunca fue preguntado.
  Future<DateTime?> cuandoSePregunto() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_clavePregunta);
    return crudo == null ? null : DateTime.tryParse(crudo);
  }

  Future<void> guardarOfertaDeUbicacion(DateTime cuando) async =>
      (await SharedPreferences.getInstance())
          .setString(_claveOfertaUbicacion, cuando.toIso8601String());

  /// Cuánto pasó desde la última vez que se le ofreció. `null` = nunca se le ofreció.
  Future<Duration?> desdeLaUltimaOfertaDeUbicacion() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_claveOfertaUbicacion);
    final cuando = crudo == null ? null : DateTime.tryParse(crudo);
    return cuando == null ? null : DateTime.now().difference(cuando);
  }

  Future<void> guardarOfertaDeSiempre(DateTime cuando) async =>
      (await SharedPreferences.getInstance())
          .setString(_claveOfertaSiempre, cuando.toIso8601String());

  /// Cuánto pasó desde que se le ofreció el «siempre». `null` = nunca.
  Future<Duration?> desdeLaUltimaOfertaDeSiempre() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_claveOfertaSiempre);
    final cuando = crudo == null ? null : DateTime.tryParse(crudo);
    return cuando == null ? null : DateTime.now().difference(cuando);
  }

  Future<void> guardarAvisoDeServicio(DateTime cuando) async =>
      (await SharedPreferences.getInstance())
          .setString(_claveAvisoServicio, cuando.toIso8601String());

  Future<Duration?> desdeElAvisoDeServicio() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_claveAvisoServicio);
    final cuando = crudo == null ? null : DateTime.tryParse(crudo);
    return cuando == null ? null : DateTime.now().difference(cuando);
  }

  Future<Duration?> desdeLaUltimaPregunta() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_clavePregunta);
    final cuando = crudo == null ? null : DateTime.tryParse(crudo);
    return cuando == null ? null : DateTime.now().difference(cuando);
  }

  /// Qué se le preguntó a esta persona y qué contestó. Sobrevive al cierre de
  /// sesión: el permiso es del TELÉFONO, no de quien entra.
  Future<Consentimiento> leerConsentimiento() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_claveConsentimiento);
    if (crudo == null) return const Consentimiento();
    try {
      return Consentimiento.fromJson(
          (jsonDecode(crudo) as Map).cast<String, dynamic>());
    } catch (_) {
      return const Consentimiento();
    }
  }

  Future<void> guardarConsentimiento(Consentimiento c) async =>
      (await SharedPreferences.getInstance())
          .setString(_claveConsentimiento, jsonEncode(c.toJson()));

  /// La llave y la URL, para que el manejador de segundo plano las encuentre.
  ///
  /// 🔴 Esto existe por una razón concreta: **el manejador de segundo plano
  /// corre en otro isolate**. No ve los estáticos de `AkPush`, así que no tiene
  /// ni el cliente ni la llave. `SharedPreferences` sí cruza el isolate, y es
  /// el único camino para que un aviso recibido con la aplicación cerrada
  /// pueda acusar recibo.
  ///
  /// No agrega exposición: esta es la llave `devices:write`, la que viaja
  /// dentro del paquete publicado y es legible por construcción. Por eso no
  /// puede enviar — ver [AkPushErrorCode.unauthorized] y el README.
  Future<void> guardarCredencial(String llave, String url) async =>
      (await SharedPreferences.getInstance()).setString(
          _claveCredencial, jsonEncode({'llave': llave, 'url': url}));

  Future<({String llave, String url})?> leerCredencial() async {
    final crudo =
        (await SharedPreferences.getInstance()).getString(_claveCredencial);
    if (crudo == null) return null;
    try {
      final j = jsonDecode(crudo) as Map<String, dynamic>;
      final llave = j['llave'] as String?;
      final url = j['url'] as String?;
      if (llave == null || url == null) return null;
      return (llave: llave, url: url);
    } catch (_) {
      return null;
    }
  }

  /// El identificador de esta instalación, para el modelo nuevo — ver el
  /// contrato del rediseño: «Comercio → Sujeto → Instalación → módulos».
  ///
  /// Lo genera el SDK LA PRIMERA VEZ y lo persiste acá: tiene que sobrevivir
  /// cierres de la aplicación, así que no alcanza con guardarlo en memoria.
  ///
  /// 🔴 NO se usa el `deviceId` que entrega la plataforma. En Android puede
  /// cambiar —una restauración de fábrica, un cambio de cuenta de Google en
  /// versiones viejas— y un identificador que cambia solo deja de servir para
  /// reconocer «el mismo aparato» entre un arranque y el siguiente: el
  /// servidor vería una instalación nueva donde había una, y perdería el
  /// enlace con el sujeto que ya la tenía enlazada.
  Future<String> leerOCrearInstalacionId() async {
    final prefs = await SharedPreferences.getInstance();
    final existente = prefs.getString(_claveInstalacionId);
    if (existente != null && existente.isNotEmpty) return existente;

    final nuevo = _generarInstalacionId();
    await prefs.setString(_claveInstalacionId, nuevo);
    return nuevo;
  }

  /// Un identificador al azar, con la forma de un UUID v4.
  ///
  /// No se agrega el paquete `uuid` sólo para esto: `Random.secure()` alcanza
  /// para lo único que hace falta —que dos aparatos no elijan el mismo—, y
  /// sumar una dependencia nueva no estaba en el encargo.
  static String _generarInstalacionId() {
    final azar = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => azar.nextInt(256));
    // Versión 4 y variante RFC 4122, como cualquier UUID v4: no hace falta
    // que sea uno de verdad, alcanza con que tenga su forma y no choque.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int desde, int hasta) => bytes
        .sublist(desde, hasta)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// ══ OLVIDAR LA CONFIGURACIÓN DEL COMERCIO ═════════════════════════════════
  ///
  /// Para cambiar de comercio (`AkPush.cambiarDeComercio`). NO se usa al cerrar sesión:
  /// la ficha es del comercio, no de la persona, y borrarla en cada logout dejaría a la
  /// aplicación pidiéndola de nuevo en cada entrada — y sin ficha no hay avisos hasta que
  /// la red conteste.
  ///
  /// 🔴 Se borra la ficha Y la credencial, juntas. Son un par: una credencial de un
  /// comercio con la ficha de otro es el estado que hace que el SDK crea que está en un
  /// comercio y reporte al otro. El isolate de segundo plano lee la credencial de acá.
  Future<void> olvidarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveConfig);
    await prefs.remove(_claveCredencial);
    // El consentimiento también: lo que la persona aceptó lo aceptó CON UN COMERCIO. Que
    // valga para el siguiente sería darle por contestado algo que nunca le preguntaron.
    await prefs.remove(_claveConsentimiento);
  }

  Future<void> olvidarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);
    await prefs.remove(_claveUsuario);
    // La huella se va con la sesión: era de esa persona, no de este teléfono.
    await prefs.remove(_claveHuella);
  }
}
