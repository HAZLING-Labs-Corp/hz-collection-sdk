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

import 'cadencia.dart';

class ConfiguracionDeRastreo {
  const ConfiguracionDeRastreo({
    this.activo = false,
    this.perfil,
    this.quietoMin = 5,
    this.arranqueKmh = 10,
    this.lotePuntos = 40,
    this.estadoForzado,
    this.cadencia = const [],
  });

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
