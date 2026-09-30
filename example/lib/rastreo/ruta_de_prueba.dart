/// LA RUTA DE PRUEBA DEL BOTÓN «SIMULAR RECORRIDO» — y el canal que la inyecta.
///
/// Un recorrido de ~4 km en tres partes, un punto por segundo:
///   1. 40 s parado en el origen (para que la captura fije la zona de reposo);
///   2. ~1,6 km a 30 km/h (ritmo de ciudad: un punto cada 10 s);
///   3. ~2,4 km a 60 km/h (ritmo rápido: un punto cada 5 s);
///   4. parado [quietoMin] + 1 minutos al final (para ver apagarse el GPS y salir el lote).
///
/// Las coordenadas son de una ciudad cualquiera (Caracas, por estar a mano); no nombran a
/// nadie ni a nada: es una línea en un mapa.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _canal = MethodChannel('ejemplo/simulador');

/// Los vértices: [lat, lon, velocidad hasta el siguiente en m/s].
const _vertices = <List<double>>[
  [10.49610, -66.85300, 30 / 3.6],
  [10.49700, -66.84400, 30 / 3.6],
  [10.49780, -66.83850, 60 / 3.6],
  [10.49350, -66.82600, 60 / 3.6],
  [10.48800, -66.82000, 0],
];

/// La ruta a un punto por segundo: [lat, lon, velocidad m/s, rumbo].
List<List<double>> rutaDePrueba({required int quietoMin}) {
  final pts = <List<double>>[];
  final origen = _vertices.first;
  for (var i = 0; i < 40; i++) {
    pts.add([origen[0], origen[1], 0, 0]);
  }
  for (var i = 0; i < _vertices.length - 1; i++) {
    final a = _vertices[i], b = _vertices[i + 1];
    final d = _metros(a[0], a[1], b[0], b[1]);
    final v = a[2];
    final pasos = (d / v).ceil();
    final rumbo = _rumbo(a[0], a[1], b[0], b[1]);
    for (var k = 0; k < pasos; k++) {
      final f = k / pasos;
      pts.add([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, v, rumbo]);
    }
  }
  final fin = _vertices.last;
  for (var i = 0; i < (quietoMin + 1) * 60; i++) {
    pts.add([fin[0], fin[1], 0, 0]);
  }
  return pts;
}

double _metros(double la1, double lo1, double la2, double lo2) {
  const r = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final x = math.pow(math.sin(rad(la2 - la1) / 2), 2) +
      math.cos(rad(la1)) * math.cos(rad(la2)) * math.pow(math.sin(rad(lo2 - lo1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(x));
}

double _rumbo(double la1, double lo1, double la2, double lo2) {
  double rad(double g) => g * math.pi / 180;
  final y = math.sin(rad(lo2 - lo1)) * math.cos(rad(la2));
  final x = math.cos(rad(la1)) * math.sin(rad(la2)) -
      math.sin(rad(la1)) * math.cos(rad(la2)) * math.cos(rad(lo2 - lo1));
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

class Simulador {
  /// Arranca la ruta. `null` si arrancó; si no, por qué (en castellano, del nativo).
  static Future<String?> iniciar(List<List<double>> puntos) async {
    if (defaultTargetPlatform != TargetPlatform.android) return comandoDeIos(puntos);
    return _canal.invokeMethod<String>('iniciar', {'puntos': puntos, 'cadaMs': 1000});
  }

  static Future<void> detener() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _canal.invokeMethod('detener');
  }

  static Future<({bool corriendo, int indice, int total})> estado() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return (corriendo: false, indice: 0, total: 0);
    }
    final r = await _canal.invokeMapMethod<String, dynamic>('estado') ?? const {};
    return (
      corriendo: r['corriendo'] == true,
      indice: (r['indice'] as num?)?.toInt() ?? 0,
      total: (r['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// En el simulador de iOS la app no puede inyectar ubicaciones: se hace desde la Mac.
  /// Se devuelve el comando para copiarlo.
  static String comandoDeIos(List<List<double>> puntos) {
    final vertices = _vertices.map((v) => '${v[0]},${v[1]}').join(' ');
    return 'xcrun simctl location booted start --speed=12 $vertices';
  }
}
