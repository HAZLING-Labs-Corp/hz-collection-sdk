/// LA CADENCIA POR ESTADO — cada cuánto se muestrea y se manda, según lo que está pasando.
///
/// PM-025 §4.5, «Cambio del 30-09-2026» (Juan: *la cadencia es inteligencia configurable*).
/// El servidor manda una TABLA ordenada; el SDK evalúa cada pocos segundos la situación del
/// aparato y aplica **la primera fila cuya condición se cumpla**:
///
/// ```
/// { estado: "emergencia",  si: { forzado: true },            muestreoSeg: 2,  presenciaSeg: 5,  loteSeg: 15 }
/// { estado: "rapido",      si: { velKmhMayorA: 40 },         muestreoSeg: 5,  presenciaSeg: 15, loteSeg: 120 }
/// { estado: "rodando",     si: { enMovimiento: true },       muestreoSeg: 10, presenciaSeg: 20, loteSeg: 300 }
/// { estado: "nocheQuieto", si: { quietoMinMayorA: 30, horaEntre: ["22:00","06:00"] }, muestreoSeg: 0, latidoMin: 180 }
/// { estado: "detenido",    si: { quietoMinMayorA: 5 },       muestreoSeg: 0, presenciaSeg: 0, latidoMin: 30 }
/// ```
///
/// **El SDK no sabe qué significa «emergencia» ni «noche»**: sabe evaluar condiciones. Las
/// filas y sus nombres son del perfil de medición del comercio (PM-026 §1: capta, no decide).
///
/// ══ LOS BORDES, ESCRITOS PORQUE SON LOS QUE SE DISCUTEN ══
///
///  · `velKmhMayorA: 40` es **estrictamente mayor**: a 40 km/h justos no es «rápido».
///  · `quietoMinMayorA: 5` es **estrictamente mayor**: a los 5 min justos todavía no.
///  · `horaEntre: ["22:00","06:00"]` incluye el inicio y excluye el fin (22:00 sí, 06:00 no),
///    y cruza la medianoche si el inicio es mayor que el fin. Hora LOCAL del teléfono.
///  · Una fila sin condiciones (`si: {}`) se cumple siempre.
///  · Una condición que no se entiende hace que la fila NO se cumpla: nunca se prende un GPS
///    más caro por una palabra nueva que esta versión no conoce.
///
/// ══ EL RESPALDO ══
///
/// Tabla ausente o vacía → [FilaDeCadencia.respaldo]: la de «rodando», 10 s / 20 s / 300 s.
/// Tabla presente sin fila que se cumpla → el respaldo si rueda, o «quieto» sin GPS si no.
library;

/// Lo que el SDK sabe del aparato en este momento, para evaluar la tabla.
class SituacionDelAparato {
  const SituacionDelAparato({
    required this.forzado,
    required this.velKmh,
    required this.enMovimiento,
    required this.quietoMin,
    required this.hora,
  });

  /// El servidor puso `estadoForzado` para este aparato.
  final bool forzado;

  /// La última velocidad conocida, km/h.
  final double velKmh;

  /// El detector dice que rueda (GPS preciso prendido y grabando).
  final bool enMovimiento;

  /// Minutos desde el último movimiento (0 si se mueve).
  final double quietoMin;

  /// La hora local del teléfono.
  final DateTime hora;
}

class CondicionDeCadencia {
  const CondicionDeCadencia({
    this.forzado,
    this.velKmhMayorA,
    this.enMovimiento,
    this.quietoMinMayorA,
    this.horaEntre,
    this.desconocida = false,
  });

  final bool? forzado;
  final double? velKmhMayorA;
  final bool? enMovimiento;
  final double? quietoMinMayorA;

  /// Minutos desde medianoche: (inicio, fin).
  final (int, int)? horaEntre;

  /// Vino algo que esta versión no entiende: la fila no se cumple nunca.
  final bool desconocida;

  static const _conocidas = {
    'forzado', 'velKmhMayorA', 'enMovimiento', 'quietoMinMayorA', 'horaEntre'
  };

  factory CondicionDeCadencia.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CondicionDeCadencia();
    var desconocida = j.keys.any((k) => !_conocidas.contains(k));
    double? num_(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is num && v.isFinite) return v.toDouble();
      desconocida = true;
      return null;
    }

    bool? bool_(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is bool) return v;
      desconocida = true;
      return null;
    }

    (int, int)? hora;
    final h = j['horaEntre'];
    if (h != null) {
      final a = h is List && h.length == 2 ? minutosDe('${h[0]}') : null;
      final b = h is List && h.length == 2 ? minutosDe('${h[1]}') : null;
      if (a == null || b == null) {
        desconocida = true;
      } else {
        hora = (a, b);
      }
    }
    return CondicionDeCadencia(
      forzado: bool_('forzado'),
      velKmhMayorA: num_('velKmhMayorA'),
      enMovimiento: bool_('enMovimiento'),
      quietoMinMayorA: num_('quietoMinMayorA'),
      horaEntre: hora,
      desconocida: desconocida,
    );
  }

  /// "22:00" → 1320. Lo que no tenga esa forma, `null`.
  static int? minutosDe(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!), mi = int.parse(m[2]!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  bool seCumple(SituacionDelAparato s) {
    if (desconocida) return false;
    if (forzado != null && s.forzado != forzado) return false;
    if (velKmhMayorA != null && !(s.velKmh > velKmhMayorA!)) return false;
    if (enMovimiento != null && s.enMovimiento != enMovimiento) return false;
    if (quietoMinMayorA != null && !(s.quietoMin > quietoMinMayorA!)) return false;
    final h = horaEntre;
    if (h != null) {
      final ahora = s.hora.hour * 60 + s.hora.minute;
      final (ini, fin) = h;
      final dentro = ini <= fin ? (ahora >= ini && ahora < fin) : (ahora >= ini || ahora < fin);
      if (!dentro) return false;
    }
    return true;
  }
}

class FilaDeCadencia {
  const FilaDeCadencia({
    required this.estado,
    this.si = const CondicionDeCadencia(),
    required this.muestreoSeg,
    this.presenciaSeg = 0,
    this.loteSeg,
    this.latidoMin,
  });

  /// El nombre que le puso el perfil. Sólo para mostrar y anotar.
  final String estado;
  final CondicionDeCadencia si;

  /// Cada cuánto se graba un punto. **0 = GPS preciso apagado.**
  final int muestreoSeg;

  /// Para la presencia (rebanada 2). Se lee, no se usa todavía.
  final int presenciaSeg;

  /// Cada cuánto sale un lote en este estado. `null` si la fila no lo dice (las de quieto:
  /// lo que esperaba ya salió al detenerse).
  final int? loteSeg;

  /// Para el latido (otra rebanada). Se lee, no se usa todavía.
  final int? latidoMin;

  /// Pisos: el SDK no obedece un número que dañe la batería o martille la ingesta.
  /// 10 s de lote sólo es admisible para un aparato forzado (emergencia, a mano, uno por
  /// uno); a 1 M de aparatos el piso de verdad lo pone el perfil (300 s).
  static const pisoLoteSeg = 10;
  static const pisoMuestreoSeg = 1;

  /// Sin tabla, o sin fila que se cumpla: «rodando» con 10 / 20 / 300.
  static const respaldo = FilaDeCadencia(
    estado: 'rodando',
    si: CondicionDeCadencia(enMovimiento: true),
    muestreoSeg: 10,
    presenciaSeg: 20,
    loteSeg: 300,
  );

  /// Quieto, antes de que se cumpla ninguna fila de quieto: no se graba, el lote como el
  /// respaldo (lo que esperaba ya salió al detenerse).
  static const quietoSinFila = FilaDeCadencia(estado: 'quieto', muestreoSeg: 0, loteSeg: 300);

  factory FilaDeCadencia.fromJson(Map<String, dynamic> j) {
    int? entero(String k, {int? piso, bool ceroVale = false}) {
      final v = j[k];
      if (v is! num || !v.isFinite) return null;
      var n = v.round();
      if (n < 0) n = 0;
      if (n == 0 && ceroVale) return 0;
      if (piso != null && n < piso) n = piso;
      return n;
    }

    return FilaDeCadencia(
      estado: j['estado'] is String ? j['estado'] as String : '?',
      si: CondicionDeCadencia.fromJson(
          j['si'] is Map ? Map<String, dynamic>.from(j['si'] as Map) : null),
      // Sin `muestreoSeg` no se inventa un GPS prendido: 0.
      muestreoSeg: entero('muestreoSeg', piso: pisoMuestreoSeg, ceroVale: true) ?? 0,
      presenciaSeg: entero('presenciaSeg', ceroVale: true) ?? 0,
      loteSeg: entero('loteSeg', piso: pisoLoteSeg),
      latidoMin: entero('latidoMin', piso: 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'estado': estado,
        'muestreoSeg': muestreoSeg,
        'presenciaSeg': presenciaSeg,
        if (loteSeg != null) 'loteSeg': loteSeg,
        if (latidoMin != null) 'latidoMin': latidoMin,
      };
}

/// Elige la fila. Pura: la misma tabla y la misma situación dan siempre la misma fila.
///
/// Sin fila que se cumpla: si rueda, el [FilaDeCadencia.respaldo]; si no rueda (p. ej. quieto
/// hace 3 min, antes de «detenido»), [FilaDeCadencia.quietoSinFila] — el GPS ya está apagado
/// por el detector y decir «rodando» en el diagnóstico sería mentir.
FilaDeCadencia evaluarCadencia(List<FilaDeCadencia> tabla, SituacionDelAparato s) {
  for (final f in tabla) {
    if (f.si.seCumple(s)) return f;
  }
  return (tabla.isEmpty || s.enMovimiento) ? FilaDeCadencia.respaldo : FilaDeCadencia.quietoSinFila;
}
