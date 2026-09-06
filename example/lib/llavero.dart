import 'dart:convert';
import 'package:http/http.dart' as http;

/// EL LLAVERO — de dónde saca esta aplicación la lista de comercios que puede probar
///
/// Escrito el 2026-09-06.
///
/// ══ QUÉ PROBLEMA RESUELVE ══
///
/// Hay una sola aplicación de prueba y varios comercios de ejemplo. Antes de esto,
/// cambiar de uno a otro era volver a compilar pegándole a mano tres cosas: su llave, la
/// dirección a la que reporta y la dirección de su núcleo. Con el llavero, la aplicación
/// **pregunta** y se cambia sola.
///
/// ══ 🔴 ESTO ES DE LA APLICACIÓN DE PRUEBA. NO ES EL MOLDE DE UNA APP DE COMERCIO. ══
///
/// La aplicación de un comercio de verdad lleva UNA llave, la suya, y no tiene por qué
/// conocer la existencia de los demás. Este archivo es lo contrario: pide una lista de
/// varios comercios con sus llaves adentro. Se puede hacer porque son de ejemplo, porque
/// las llaves que trae sólo registran aparatos, y porque el servicio del otro lado **no
/// existe** si no se lo habilita a propósito. Copiarlo a la app de un cliente sería
/// entregarle la lista de los demás.
///
/// ══ LOS DOS VALORES QUE HACEN FALTA, Y NINGUNO ES SECRETO ══
///
/// ```
/// flutter run --dart-define=LLAVERO_URL=http://10.0.2.2:3085/api/llavero \
///             --dart-define=LLAVERO_LLAVE=…
/// ```
///
/// Sin `LLAVERO_URL` la aplicación se comporta como siempre: un solo comercio, el de la
/// llave con la que se compiló. El selector no aparece — y no aparecer es mejor que
/// aparecer vacío con un error.
const llaveroUrl = String.fromEnvironment('LLAVERO_URL');
const llaveroLlave = String.fromEnvironment('LLAVERO_LLAVE');

bool get hayLlavero => llaveroUrl.isNotEmpty && llaveroLlave.isNotEmpty;

/// Un comercio de la lista, tal como lo devuelve Collection.
class ComercioDePrueba {
  const ComercioDePrueba({
    required this.slug,
    required this.nombre,
    required this.llave,
    required this.urlBase,
    required this.nucleoUrl,
    required this.paquete,
    required this.identidadExigida,
    required this.falta,
  });

  final String slug;
  final String nombre;

  /// La llave de `devices:write` de este comercio. Es lo único que la aplicación no puede
  /// deducir por su cuenta.
  final String llave;

  /// La dirección de Collection a la que hay que reportar. La pone el servicio con el host
  /// por el que se lo llamó, así que desde un emulador ya viene con `10.0.2.2`.
  final String urlBase;

  /// De dónde salen SUS personas. Vacío = todavía no tiene núcleo declarado.
  final String nucleoUrl;

  /// Con qué paquete hay que haber compilado para que este comercio acepte la
  /// configuración. Si no coincide con el de la app, el servicio contesta 404.
  final String paquete;

  /// Si su identidad está EXIGIDA, esta aplicación NO puede entrar: haría falta el HMAC
  /// firmado por el backend del comercio, y ese secreto no puede vivir en un APK.
  final bool identidadExigida;

  /// Lo que le falta a este comercio para ser usable, ya redactado por el servicio. Se
  /// muestra tal cual: el selector tiene que DECIR por qué uno no sirve, no esconderlo.
  final List<String> falta;

  bool get listo => falta.isEmpty;

  factory ComercioDePrueba.desde(Map<String, dynamic> j) => ComercioDePrueba(
        slug: (j['slug'] ?? '').toString(),
        nombre: (j['nombre'] ?? '').toString(),
        llave: (j['llave'] ?? '').toString(),
        urlBase: (j['url_base'] ?? '').toString(),
        nucleoUrl: (j['nucleo_url'] ?? '').toString(),
        paquete: (j['paquete'] ?? '').toString(),
        identidadExigida: j['identidad_exigida'] == true,
        falta: ((j['falta'] as List?) ?? const []).map((x) => x.toString()).toList(),
      );
}

class ErrorDelLlavero implements Exception {
  ErrorDelLlavero(this.mensaje, {this.detalle});
  final String mensaje;
  final String? detalle;
  @override
  String toString() => detalle == null ? mensaje : '$mensaje\n$detalle';
}

class Llavero {
  static const _tiempoLimite = Duration(seconds: 10);

  /// Pide la lista. Lanza `ErrorDelLlavero` con un mensaje que se puede mostrar tal cual:
  /// esta pantalla es lo primero que se ve, y «algo falló» ahí no deja seguir a nadie.
  static Future<List<ComercioDePrueba>> comercios() async {
    if (!hayLlavero) {
      throw ErrorDelLlavero(
        'Esta aplicación se compiló sin llavero.',
        detalle: 'Pasá LLAVERO_URL y LLAVERO_LLAVE al compilar para poder elegir comercio.',
      );
    }

    final http.Response r;
    try {
      r = await http
          .get(Uri.parse(llaveroUrl), headers: {'x-llavero-key': llaveroLlave})
          .timeout(_tiempoLimite);
    } catch (e) {
      throw ErrorDelLlavero(
        'No se pudo alcanzar el llavero.',
        // La dirección va en el mensaje a propósito: el error de esta pantalla es, nueve
        // de diez veces, que se apuntó a `localhost` desde un emulador —donde no existe—
        // o que el back no está levantado. Verla ahorra el diagnóstico entero.
        detalle: '$llaveroUrl\n$e',
      );
    }

    if (r.statusCode == 401) {
      throw ErrorDelLlavero(
        'El llavero rechazó la credencial.',
        detalle: 'La llave con la que se compiló no es la que espera el servicio.',
      );
    }
    if (r.statusCode == 404) {
      throw ErrorDelLlavero(
        'El llavero no está habilitado en ese servicio.',
        detalle: 'La ruta no existe: se monta sólo con LLAVERO_DE_DEMOSTRACION=on.\n$llaveroUrl',
      );
    }
    if (r.statusCode != 200) {
      throw ErrorDelLlavero('El llavero contestó ${r.statusCode}.', detalle: r.body);
    }

    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    final lista = (cuerpo['comercios'] as List?) ?? const [];
    return lista
        .map((x) => ComercioDePrueba.desde(x as Map<String, dynamic>))
        .toList();
  }
}
