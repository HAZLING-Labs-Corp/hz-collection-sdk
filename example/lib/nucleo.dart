import 'dart:convert';

import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:http/http.dart' as http;

/// ════════════════════════════════════════════════════════════════════════
/// EL NÚCLEO DEL COMERCIO — de dónde salen las personas
/// ════════════════════════════════════════════════════════════════════════
///
/// Hasta el 2026-09-05 esta aplicación llevaba las 104 personas **compiladas
/// adentro**, en `personas_de_prueba.dart`. Eso tenía un problema que no es de
/// orden: para corregir una cédula, agregar una empresa o arreglar un correo
/// había que **recompilar el APK y volver a repartirlo**. El juego de prueba se
/// volvía intocable.
///
/// Ahora las personas viven en `hz-mundototal-core`, que es el **sistema de
/// origen** del comercio: el que las posee. Esta aplicación es un consumidor,
/// igual que notificaciones. La app **no guarda copia**: si el núcleo no
/// contesta, lo dice nombrando la ruta que falta, en vez de fingir que tiene
/// gente.
///
/// El `10.0.2.2` es cómo un emulador de Android alcanza el localhost de la
/// máquina que lo hospeda. Desde un teléfono de verdad hay que pasar la IP de
/// la máquina en la red:
///
/// ```
/// flutter run --dart-define=NUCLEO_URL=http://192.168.10.103:3010
/// ```
const nucleoUrl =
    String.fromEnvironment('NUCLEO_URL', defaultValue: 'http://10.0.2.2:3010');

/// ═══════════════════════════════════════════════════════════════════════════════
/// 🔴 LA LLAVE DE CONSULTA — pedido de Juan, 2026-09-05
/// ═══════════════════════════════════════════════════════════════════════════════
///
/// > *«No quiero colocar mi clave y mi contraseña en la app para poder consultar hacia el
/// > core. En la app ya debería haber una consulta con un key de consulta de contacto.»*
///
/// Y tiene razón, porque lo que había mezclaba dos cosas:
///
/// · **quién entró** — una persona, con su usuario y su clave;
/// · **qué puede leer la aplicación** — la aplicación, no una persona.
///
/// Antes el directorio se leía con la sesión de la persona que había entrado. Eso obliga a
/// meter una credencial personal dentro de un APK que cualquiera descomprime, y le da a la
/// app **todo lo que puede esa persona** — mucho más de lo que necesita para listar.
///
/// Es la misma forma que ya usamos con Collection: la app lleva su llave y con eso alcanza.
/// El alcance de ésta es `contactos:leer` y nada más: no puede dar de alta, ni corregir,
/// ni borrar.
///
/// ```
/// flutter run --dart-define=NUCLEO_LLAVE=mtk_…
/// ```
const nucleoLlave = String.fromEnvironment('NUCLEO_LLAVE');

/// Una persona, tal como la devuelve el núcleo.
///
/// 🔴 El identificador principal es `uuid`. La cédula es un **alias**: sirve
/// para encontrarla, no para identificarla. El teléfono y el correo **nunca**
/// identifican.
class PersonaDelNucleo {
  const PersonaDelNucleo({
    required this.uuid,
    required this.cedula,
    required this.nombre,
    this.usuario = '',
    this.telefono = '',
    this.correo = '',
    this.pais = '',
    this.estado = '',
    this.ciudad = '',
    this.genero = '',
    this.tipo = TipoDeSujeto.natural,
    this.claseDeDocumento = ClaseDeDocumento.cedula,
    this.organizacion,
  });

  final String uuid;
  final String cedula;
  final String nombre;
  final String usuario;
  final String telefono;
  final String correo;
  final String pais;
  final String estado;
  final String ciudad;
  final String genero;
  final TipoDeSujeto tipo;
  final ClaseDeDocumento claseDeDocumento;
  final Organizacion? organizacion;

  /// Lo que el SDK espera: la CLASE del documento, no sólo el número.
  Documento get documento =>
      Documento(clase: claseDeDocumento, numero: cedula);

  factory PersonaDelNucleo.desdeJson(Map<String, dynamic> j) {
    final org = j['organizacion'] as String?;
    return PersonaDelNucleo(
      uuid: j['uuid'] as String? ?? '',
      cedula: j['cedula'] as String? ?? '',
      nombre: j['nombre'] as String? ?? '',
      usuario: j['usuario'] as String? ?? '',
      telefono: j['telefono'] as String? ?? '',
      correo: j['email'] as String? ?? '',
      pais: j['pais'] as String? ?? '',
      estado: j['estado'] as String? ?? '',
      ciudad: j['ciudad'] as String? ?? '',
      genero: j['genero'] as String? ?? '',
      tipo: TipoDeSujeto.desde(j['tipoDeSujeto'] as String?),
      claseDeDocumento: ClaseDeDocumento.desde(j['claseDeDocumento'] as String?),
      // El núcleo guarda el nombre de la organización; el SDK pide además un
      // código. Se deriva del nombre para no inventar uno que no existe.
      organizacion: (org == null || org.isEmpty)
          ? null
          : Organizacion(codigo: _codigoDe(org), nombre: org),
    );
  }

  static String _codigoDe(String nombre) => nombre
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Lo que puede salir mal hablando con el núcleo, con el nombre de la ruta.
class ErrorDelNucleo implements Exception {
  ErrorDelNucleo(this.mensaje, {this.ruta});
  final String mensaje;
  final String? ruta;

  @override
  String toString() => ruta == null ? mensaje : '$mensaje\n$ruta';
}

/// El cliente. Dos llamadas: entrar, y traer el directorio.
class Nucleo {
  static const _tiempoLimite = Duration(seconds: 12);

  /// La sesión firmada que devuelve el núcleo. Vive en memoria: si la app se
  /// cierra hay que volver a entrar, que es lo correcto para una demo.
  static String? token;

  static Uri _en(String ruta, [Map<String, String>? consulta]) {
    final base = nucleoUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$ruta').replace(queryParameters: consulta);
  }

  static Never _noContesta(Object e, String ruta) {
    throw ErrorDelNucleo(
      'El núcleo no contestó. ¿Está levantado?\n${e.runtimeType}',
      ruta: 'POST/GET $nucleoUrl$ruta',
    );
  }

  /// `POST /api/auth/login` — usuario y clave, como cualquier sistema de verdad.
  static Future<PersonaDelNucleo> entrar(String usuario, String clave) async {
    http.Response r;
    try {
      r = await http
          .post(
            _en('/api/auth/login'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'usuario': usuario, 'clave': clave}),
          )
          .timeout(_tiempoLimite);
    } catch (e) {
      _noContesta(e, '/api/auth/login');
    }

    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode == 401) {
      throw ErrorDelNucleo(cuerpo['error'] as String? ?? 'Usuario o clave incorrectos.');
    }
    if (r.statusCode != 200) {
      throw ErrorDelNucleo(
        'El núcleo respondió ${r.statusCode}: ${cuerpo['error'] ?? r.body}',
        ruta: 'POST $nucleoUrl/api/auth/login',
      );
    }

    final persona = cuerpo['persona'] as Map<String, dynamic>?;
    if (persona == null) {
      throw ErrorDelNucleo(
        'Ese usuario es de administración del núcleo, no una persona del elenco. '
        'Entrá con una persona: la semilla trae usuario1 … usuario100.',
      );
    }
    token = cuerpo['token'] as String?;
    return PersonaDelNucleo.desdeJson(persona);
  }

  /// `GET /api/contactos` — el directorio, paginado y buscable.
  ///
  /// Pide sesión: el elenco son personas con cédula, ciudad y correo, y un
  /// directorio abierto es una cartera publicada.
  static Future<List<PersonaDelNucleo>> directorio({String busqueda = ''}) async {
    if (token == null) {
      throw ErrorDelNucleo(
        'Todavía no hay sesión. Entrá con un usuario del núcleo y después se '
        'puede mirar el directorio.',
      );
    }

    http.Response r;
    try {
      r = await http.get(
        _en('/api/contactos', {
          'porPagina': '200',
          if (busqueda.isNotEmpty) 'q': busqueda,
        }),
        headers: {'authorization': 'Bearer $token'},
      ).timeout(_tiempoLimite);
    } catch (e) {
      _noContesta(e, '/api/contactos');
    }

    if (r.statusCode == 401) {
      if (nucleoLlave.isEmpty) {
        token = null;
        throw ErrorDelNucleo('La sesión venció. Volvé a entrar.');
      }
      /* Con llave, un 401 NO es «volvé a entrar»: la llave está mal o la revocaron, y
         decirle a la persona que vuelva a entrar la manda a hacer algo que no arregla
         nada. */
      throw ErrorDelNucleo(
        'El núcleo rechazó la llave de esta aplicación. Puede estar revocada o mal '
        'compilada.',
      );
    }
    if (r.statusCode != 200) {
      throw ErrorDelNucleo(
        'El núcleo respondió ${r.statusCode}.',
        ruta: 'GET $nucleoUrl/api/contactos',
      );
    }

    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    return (cuerpo['contactos'] as List)
        .cast<Map<String, dynamic>>()
        .map(PersonaDelNucleo.desdeJson)
        .toList();
  }
}
