/// UN PUNTO DEL RECORRIDO, con la forma exacta de PM-025 §4.1.
///
/// `{ t, lat, lon, acc, v, h, alt, mock, bat }` — tiempo en ms desde época, grados, metros,
/// m/s, grados, metros, si el sistema dice que es simulado, y la batería 0-100.
/// Lo que el sistema no da va con su centinela: `bat -1`, `h -1`, `alt -9999` (§4.12).
///
/// ══ POR QUÉ SE REDONDEA ANTES DE GUARDAR ══
///
/// Un GPS de teléfono no sabe la posición a la décima de milímetro, y escribir
/// `10.491283746152837` en vez de `10.4912837` sólo agrega bytes que se multiplican por un
/// millón de aparatos. Siete decimales en la coordenada son ~1 cm; una décima en metros y
/// en grados es más fino que cualquier GPS de consumo. Y redondear ANTES de guardar —no al
/// armar el lote— hace que lo que se guardó, lo que se hasheó y lo que se mandó sean
/// exactamente el mismo número.
library;

class PuntoDeRastreo {
  PuntoDeRastreo({
    required this.t,
    required double lat,
    required double lon,
    required double acc,
    required double v,
    required double h,
    required double alt,
    required this.mock,
    required int bat,
  })  : lat = _redondear(lat, 7),
        lon = _redondear(lon, 7),
        acc = _redondear(acc < 0 ? 0 : acc, 1),
        v = _redondear(v < 0 ? 0 : v, 2),
        h = (!h.isFinite || h < 0) ? rumboDesconocido : _rumbo(h),
        alt = (!alt.isFinite || alt < -500 || alt > 10000)
            ? altitudDesconocida
            : _redondear(alt, 1),
        bat = (bat < 0 || bat > 100) ? bateriaDesconocida : bat;

  /// Rumbo en [0, 360): el redondeo a 1 decimal no puede llegar a 360 (el servidor lo rechaza).
  static double _rumbo(double h) {
    final r = _redondear(h % 360, 1);
    return r >= 360 ? 0 : r;
  }

  /// ══ VALORES DESCONOCIDOS (contrato §4.12) ══
  ///
  /// El punto sigue teniendo 9 campos numéricos (`null` no pasa), pero cuando el sistema
  /// no da el dato se manda un centinela fuera del rango físico, nunca 0: `bat: 0` es
  /// batería muerta y `h: 0` es el norte. Collection los guarda tal cual y la constancia
  /// los trata como «no se sabe».
  static const int bateriaDesconocida = -1;
  static const double rumboDesconocido = -1;
  static const double altitudDesconocida = -9999;

  /// Hora de la fijación, ms desde época.
  final int t;
  final double lat;
  final double lon;

  /// Precisión horizontal, metros.
  final double acc;

  /// Velocidad, m/s. Si el sistema no la da, 0 (no se inventa: ver `v` en el detector).
  final double v;

  /// Rumbo, grados [0, 360), o [rumboDesconocido] (-1).
  final double h;

  /// Altitud, metros, o [altitudDesconocida] (-9999).
  final double alt;

  /// El sistema dice que la ubicación viene de un proveedor simulado. Se manda tal cual:
  /// el SDK no decide si eso invalida el punto; lo decide quien lo lea (PM-026 §1).
  final bool mock;

  /// Batería 0-100 al tomar el punto, o [bateriaDesconocida] (-1).
  final int bat;

  Map<String, dynamic> toJson() => {
        't': t,
        'lat': lat,
        'lon': lon,
        'acc': acc,
        'v': v,
        'h': h,
        'alt': alt,
        'mock': mock,
        'bat': bat,
      };

  factory PuntoDeRastreo.fromJson(Map<String, dynamic> j) => PuntoDeRastreo(
        t: (j['t'] as num).toInt(),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        acc: (j['acc'] as num).toDouble(),
        v: (j['v'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        alt: (j['alt'] as num).toDouble(),
        mock: j['mock'] == true,
        bat: (j['bat'] as num).toInt(),
      );

  static double _redondear(double x, int decimales) {
    if (!x.isFinite) return 0;
    var f = 1.0;
    for (var i = 0; i < decimales; i++) {
      f *= 10;
    }
    final r = (x * f).roundToDouble() / f;
    return r == 0 ? 0.0 : r; // sin cero negativo
  }
}
