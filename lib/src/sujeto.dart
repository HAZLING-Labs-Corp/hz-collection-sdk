/// El sujeto — quien se loguea.
///
/// Es la raíz del modelo nuevo: la instalación (el aparato) cuelga del
/// sujeto, y de la instalación cuelgan los módulos —avisos, entre otros—.
/// Antes de este rediseño la raíz era el token: quien decía que no a los
/// avisos no quedaba anotado en ningún lado. Con el sujeto naciendo en el
/// login —antes de tocar el permiso—, esa persona existe para el sistema
/// aunque conteste que no.
///
/// Ver `AkPush.alIniciarSesion` para el punto de entrada, y el contrato del
/// rediseño para la forma exacta de `POST /api/v1/sujetos`.
library;

/// Si el sujeto es una persona natural o una persona jurídica (empresa).
///
/// Por omisión `natural`, porque es lo que ya era todo el mundo antes de que
/// existiera esta distinción: un comercio que no declara nada no ve ningún
/// cambio.
enum TipoDeSujeto {
  natural,
  juridica;

  /// El texto que espera el servidor.
  String get valor => name;

  /// Un valor desconocido cae en `natural`, y no rompe: si el servicio agrega
  /// un tipo nuevo mañana, una versión vieja del paquete tiene que poder
  /// seguir leyendo la configuración en vez de fallar por una palabra que no
  /// conoce.
  static TipoDeSujeto desde(String? v) => switch (v) {
        'juridica' => TipoDeSujeto.juridica,
        _ => TipoDeSujeto.natural,
      };
}

/// La clase de documento con la que se identifica un sujeto.
enum ClaseDeDocumento {
  cedula,
  rif,
  pasaporte,
  otro;

  String get valor => name;

  static ClaseDeDocumento desde(String? v) => switch (v) {
        'rif' => ClaseDeDocumento.rif,
        'pasaporte' => ClaseDeDocumento.pasaporte,
        'otro' => ClaseDeDocumento.otro,
        // Incluye 'cedula' y cualquier valor que no se reconozca: es la
        // clase más común, y no inventar un rechazo por un valor nuevo del
        // servidor es más seguro que fallar.
        _ => ClaseDeDocumento.cedula,
      };
}

/// El documento de identidad del sujeto.
///
/// 🔴 Reemplaza a la vieja `identity` suelta —una cédula sin clase—. Ver el
/// `@Deprecated` en `AkPush.alIniciarSesion`: quien todavía mande `identity`
/// sigue andando, traducido acá mismo a `Documento(clase: cedula, numero:
/// identity)`, pero no puede declarar RIF ni pasaporte por esa vía.
class Documento {
  const Documento({required this.clase, required this.numero});

  final ClaseDeDocumento clase;

  /// Se guarda TAL CUAL llega, sin normalizar — igual que hace el servidor.
  /// Sacarle guiones o ceros de más acá sería inventarle al comercio un
  /// número que no es el que tiene anotado.
  final String numero;

  Map<String, dynamic> toJson() => {'clase': clase.valor, 'numero': numero};

  factory Documento.fromJson(Map<String, dynamic> j) => Documento(
        clase: ClaseDeDocumento.desde(j['clase'] as String?),
        numero: j['numero'] as String? ?? '',
      );

  @override
  String toString() => '${clase.valor}:$numero';
}

/// La organización a la que PERTENECE el sujeto.
///
/// No la reemplaza: un sujeto sigue siendo él mismo, con su propio
/// `sujetoId` y su propio `documento`, y además cuelga de una organización.
/// Es lo que permite distinguir, por ejemplo, a un empleado de un proveedor
/// de un cliente natural sin organización.
class Organizacion {
  const Organizacion({required this.codigo, this.nombre, this.rol});

  final String codigo;
  final String? nombre;
  final String? rol;

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        if (nombre != null) 'nombre': nombre,
        if (rol != null) 'rol': rol,
      };

  factory Organizacion.fromJson(Map<String, dynamic> j) => Organizacion(
        codigo: j['codigo'] as String? ?? '',
        nombre: j['nombre'] as String?,
        rol: j['rol'] as String?,
      );

  @override
  String toString() => rol != null ? '$codigo ($rol)' : codigo;
}
