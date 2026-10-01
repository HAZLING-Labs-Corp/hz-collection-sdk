/// EL BLOQUE `rastreo` DE `GET /api/v1/configuracion` — qué se mide de esta instalación.
///
/// PM-025 §4.5 con el «Cambio del 30-09-2026»:
///
/// ```
/// rastreo: { activo, perfil, arranqueKmh: 10, quietoMin: 5, golpe: { g: 4, quietoSeg: 60 },
///            estadoForzado: null, lotePuntos: 40, cadencia: [ …filas… ] }
/// ```
///
/// Los números de muestreo, presencia, lote y latido YA NO son fijos: viven en la tabla
/// `cadencia` (ver `cadencia.dart`), que el SDK evalúa cada pocos segundos. Acá quedan los
/// que no dependen del estado: la velocidad de arranque, los minutos para darse por quieto,
/// el techo de puntos por lote, y lo que el servidor fuerce.
///
/// ══ 🔴 LA MISMA REGLA DE `politica.dart`: LO QUE FALTA O NO SE ENTIENDE CAE HACIA ABAJO ══
///
/// Si el servicio no manda el bloque —una versión vieja, un comercio sin el módulo, un 404—
/// el rastreo queda **apagado**. Nunca se prende un GPS en el fondo porque un campo faltó.
/// Un número fuera de rango se acota a un piso y un techo: un `loteSeg: 0` escrito por
/// error en una consola dejaría un teléfono mandando sin parar, y eso por un millón de
/// aparatos es un ataque contra nuestra propia ingesta.
library;

import '../politica.dart';
import 'cadencia.dart';
import 'etiquetas/etiquetas_ble.dart';
import 'golpe/detector_de_golpe.dart';

class ConfiguracionDeRastreo {
  const ConfiguracionDeRastreo({
    this.activo = false,
    this.perfil,
    this.quietoMin = 5,
    this.arranqueKmh = 10,
    this.lotePuntos = 40,
    this.estadoForzado,
    this.cadencia = const [],
    this.permiso = permisoPorOmision,
    this.despertarSeg = 3,
    this.despertarAceleracion = 1.0,
    this.presenciaQuietoSeg = 30,
    this.medio,
    this.golpe = UmbralesDeGolpe.porOmision,
    this.etiquetas = ConfiguracionDeEtiquetas.ninguna,
  });

  /// Etiquetas BLE (01-10-2026): las de la persona y cómo escucharlas. Sin bloque: no se escanea.
  final ConfiguracionDeEtiquetas etiquetas;

  /// Si hay algo que medir. Sin perfil vigente, el servicio manda `false`.
  final bool activo;

  /// El nombre del perfil que manda. Sólo para mostrar: el SDK decide por los números.
  final String? perfil;

  /// A los cuántos minutos quieto se apaga el GPS preciso.
  final int quietoMin;

  /// La velocidad que confirma que la persona arrancó de verdad (y no que el GPS saltó).
  final int arranqueKmh;

  /// El TECHO de puntos de un lote, en cualquier estado: un lote sale al llegar a este
  /// número aunque no haya pasado el `loteSeg` de la fila, y un atraso sin señal sale en
  /// varios lotes de este tamaño, no en uno enorme.
  final int lotePuntos;

  /// Lo pone el servidor para un aparato concreto (rebanada 4). En la rebanada 1 sólo se
  /// lee: si viene, la condición `forzado: true` de la tabla se cumple.
  final String? estadoForzado;

  /// La tabla de cadencia, en orden. Vacía → [FilaDeCadencia.respaldo].
  final List<FilaDeCadencia> cadencia;

  /// CL-36 · cuándo y cómo se pide el permiso de ubicación: la MISMA política que Collection ya
  /// usa para las notificaciones (`politica.dart`): la decide el comercio desde su consola, viaja
  /// con la configuración y la app la lee sin código propio. Si el servidor no la manda: al abrir,
  /// con pregunta blanda.
  final PoliticaDeNotificaciones permiso;

  /// CL-37 · despertar por movimiento del teléfono: quieto, con el acelerómetro (sin gravedad)
  /// por encima de [despertarAceleracion] m/s² durante [despertarSeg] segundos seguidos, el SDK
  /// enciende el GPS preciso. Dato del perfil, no constante: mientras se desarrolla, 3 s.
  final int despertarSeg;
  final double despertarAceleracion;

  /// CL-38 · cada cuántos segundos repite su última posición estando quieto (0 = no repite).
  final int presenciaQuietoSeg;

  /// CL-41 · el medio que mide el perfil (`pie`, `bici`, `dosRuedas`, `carro`, `bus`), para dibujar al aparato.
  final String? medio;

  /// Tramo 3.3 · los umbrales del detector de golpe (`golpe: { g, quietoSeg }`). Si el bloque
  /// no los trae, 4 g y 60 s, con piso y techo (ver [UmbralesDeGolpe]).
  final UmbralesDeGolpe golpe;

  static const pisoDespertarSeg = 1;
  static const techoDespertarSeg = 60;

  /// Los textos de la pregunta blanda cuando el comercio no manda los suyos (los de
  /// `TextosDeLaPregunta.predeterminados` hablan de avisos, no de ubicación).
  static const textosDeUbicacion = TextosDeLaPregunta(
    titulo: '¿Registramos tu recorrido?',
    cuerpo: 'Usamos tu ubicación, también con la app cerrada, para registrar por dónde vas. '
        'Se apaga sola cuando te detienes.',
    aceptar: 'Sí, registrar',
    ahoraNo: 'Ahora no',
  );

  static const permisoPorOmision = PoliticaDeNotificaciones(
    momento: MomentoDelPermiso.arranque,
    preguntaBlanda: true,
    textos: textosDeUbicacion,
  );

  static PoliticaDeNotificaciones _permisoDesde(Object? crudo) {
    if (crudo is! Map) return permisoPorOmision;
    final j = Map<String, dynamic>.from(crudo);
    final p = PoliticaDeNotificaciones.fromJson(j);
    final traeTextos = j['textos'] is Map && (j['textos'] as Map).isNotEmpty;
    return PoliticaDeNotificaciones(
      momento: p.momento,
      obligatorio: p.obligatorio,
      preguntaBlanda: j.containsKey('preguntaBlanda') ? p.preguntaBlanda : true,
      reintentarCadaDias: p.reintentarCadaDias,
      textos: traeTextos
          ? TextosDeLaPregunta(
              titulo: (j['textos']['titulo'] as String?) ?? textosDeUbicacion.titulo,
              cuerpo: (j['textos']['cuerpo'] as String?) ?? textosDeUbicacion.cuerpo,
              aceptar: (j['textos']['aceptar'] as String?) ?? textosDeUbicacion.aceptar,
              ahoraNo: (j['textos']['ahoraNo'] as String?) ?? textosDeUbicacion.ahoraNo,
            )
          : textosDeUbicacion,
    );
  }

  static const apagada = ConfiguracionDeRastreo();

  /// Menos de un minuto quieto no es «quieto»: es un semáforo.
  static const pisoQuietoMin = 1;

  /// Por debajo de 3 km/h el GPS de un teléfono barato «camina» solo, parado en la mesa.
  static const pisoArranqueKmh = 3;

  /// Un lote de más de 200 puntos pesa más de 30 KB sin comprimir: una red 2G lo corta.
  /// Es además el techo de la ingesta (`TECHO_PUNTOS_POR_LOTE`).
  static const techoLotePuntos = 200;

  factory ConfiguracionDeRastreo.fromJson(Map<String, dynamic>? j) {
    if (j == null) return apagada;
    int entero(String k, int siNo, {int? piso, int? techo}) {
      final v = j[k];
      var n = v is num && v.isFinite ? v.round() : siNo;
      if (piso != null && n < piso) n = piso;
      if (techo != null && n > techo) n = techo;
      return n;
    }

    final perfil = j['perfil'];
    final forzado = j['estadoForzado'];
    final tabla = j['cadencia'];
    return ConfiguracionDeRastreo(
      activo: j['activo'] == true,
      perfil: perfil is String && perfil.isNotEmpty ? perfil : null,
      quietoMin: entero('quietoMin', 5, piso: pisoQuietoMin),
      arranqueKmh: entero('arranqueKmh', 10, piso: pisoArranqueKmh),
      lotePuntos: entero('lotePuntos', 40, piso: 1, techo: techoLotePuntos),
      estadoForzado: forzado is String && forzado.isNotEmpty ? forzado : null,
      cadencia: tabla is List
          ? [
              for (final f in tabla)
                if (f is Map) FilaDeCadencia.fromJson(Map<String, dynamic>.from(f)),
            ]
          : const [],
      permiso: _permisoDesde(j['permiso']),
      despertarSeg: j['despertar'] is Map
          ? ((((j['despertar'] as Map)['seg']) is num ? ((j['despertar'] as Map)['seg'] as num).round() : 3)
              .clamp(pisoDespertarSeg, techoDespertarSeg))
          : 3,
      medio: j['medio'] is String && (j['medio'] as String).isNotEmpty ? j['medio'] as String : null,
      presenciaQuietoSeg: (j['presenciaQuietoSeg'] is num ? (j['presenciaQuietoSeg'] as num).round() : 30).clamp(0, 86400),
      despertarAceleracion: j['despertar'] is Map && (j['despertar'] as Map)['aceleracion'] is num
          ? (((j['despertar'] as Map)['aceleracion'] as num).toDouble()).clamp(0.3, 10.0)
          : 1.0,
      golpe: UmbralesDeGolpe.fromJson(j['golpe']),
      etiquetas: ConfiguracionDeEtiquetas.fromJson(j['etiquetas']),
    );
  }

  /// Para guardarla en disco y leerla con [fromJson]. Las condiciones se guardan crudas.
  Map<String, dynamic> toJson() => {
        'activo': activo,
        'perfil': perfil,
        'quietoMin': quietoMin,
        'arranqueKmh': arranqueKmh,
        'lotePuntos': lotePuntos,
        'estadoForzado': estadoForzado,
        'permiso': permiso.toJson(),
        'despertar': {'seg': despertarSeg, 'aceleracion': despertarAceleracion},
        'presenciaQuietoSeg': presenciaQuietoSeg,
        'medio': medio,
        'golpe': golpe.toJson(),
        if (etiquetas.hayQueEscuchar) 'etiquetas': etiquetas.toJson(),
        'cadencia': [for (final f in cadencia) {...f.toJson(), 'si': _siCrudo(f.si)}],
      };

  static Map<String, dynamic> _siCrudo(CondicionDeCadencia c) {
    String hhmm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return {
      if (c.desconocida) '?': true,
      if (c.forzado != null) 'forzado': c.forzado,
      if (c.velKmhMayorA != null) 'velKmhMayorA': c.velKmhMayorA,
      if (c.enMovimiento != null) 'enMovimiento': c.enMovimiento,
      if (c.quietoMinMayorA != null) 'quietoMinMayorA': c.quietoMinMayorA,
      if (c.horaEntre != null) 'horaEntre': [hhmm(c.horaEntre!.$1), hhmm(c.horaEntre!.$2)],
    };
  }

  /// La velocidad de arranque en m/s, que es la unidad de todo lo demás.
  double get arranqueMs => arranqueKmh / 3.6;

  Duration get quieto => Duration(minutes: quietoMin);

  /// La fila que manda ahora.
  FilaDeCadencia filaPara(SituacionDelAparato s) => evaluarCadencia(cadencia, s);

  /// El intervalo al que se abre el GPS preciso: el muestreo más corto de la tabla entre
  /// las filas que no piden `forzado` (o 2 s si el aparato está forzado y la tabla lo dice).
  /// Así el flujo no se reabre cada vez que se cruza de «rodando» a «rápido»: el ritmo de
  /// cada fila lo aplica el detector descartando lecturas.
  int get muestreoDelGpsSeg {
    int? minimo;
    for (final f in cadencia) {
      if (f.muestreoSeg <= 0) continue;
      if (f.si.forzado == true && estadoForzado == null) continue;
      if (minimo == null || f.muestreoSeg < minimo) minimo = f.muestreoSeg;
    }
    return minimo ?? FilaDeCadencia.respaldo.muestreoSeg;
  }
}
