/// AJUSTAR EL RECORRIDO A LAS CALLES (map-matching) — sólo de la app de ejemplo.
///
/// Los puntos del GPS en una ladera con casas cercanas se desvían 10-50 m, y unidos con rectas
/// «pasan entre las casas». Aquí se le pide a un servicio de map-matching (Valhalla, perfil a pie)
/// que pegue el recorrido a las calles reales y devuelva la geometría de la calle. Es una ayuda de
/// visualización: el dato guardado y firmado sigue siendo el crudo, nunca se reescribe.
///
/// ⚠️ El servidor público de Valhalla es para DESARROLLO (uso liviano). Producción lleva el suyo;
/// por eso la dirección sale de un define (`RASTREO_MAP_MATCHING_URL`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'historial_de_recorrido.dart';

const _urlDelServicio =
    String.fromEnvironment('RASTREO_MAP_MATCHING_URL', defaultValue: 'https://valhalla1.openstreetmap.de/trace_route');

/// Hasta cuántos puntos se mandan: más no mejora la calle y encarece el pedido.
const _maxPuntos = 250;

List<LatLng> decodificarPolyline6(String s) {
  final out = <LatLng>[];
  var i = 0, lat = 0, lon = 0;
  while (i < s.length) {
    for (var k = 0; k < 2; k++) {
      var desp = 0, res = 0, b = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        res |= (b & 0x1f) << desp;
        desp += 5;
      } while (b >= 0x20);
      final d = (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      if (k == 0) {
        lat += d;
      } else {
        lon += d;
      }
    }
    out.add(LatLng(lat / 1e6, lon / 1e6));
  }
  return out;
}

class RecorridoAjustado {
  RecorridoAjustado(this.calles, this.hastaT);
  final List<LatLng> calles;

  /// El `t` del último punto que entró en este ajuste.
  final int hastaT;
}

/// `null` si el servicio no contesta o no encuentra calle (se dibuja el recorrido crudo).
Future<RecorridoAjustado?> ajustarACalles(List<PuntoDelMapa> puntos, {http.Client? cliente}) async {
  // un solo tramo por pedido: se parte donde hay un hueco de más de 5 min (otra caminata)
  var ini = puntos.length - 1;
  while (ini > 0 && puntos[ini].t - puntos[ini - 1].t < 5 * 60 * 1000) {
    ini--;
  }
  final tramo = puntos.sublist(ini);
  if (tramo.length < 3) return null;
  final unicos = <PuntoDelMapa>[];
  for (final p in tramo) {
    if (unicos.isEmpty || unicos.last.t != p.t) unicos.add(p);
  }
  final paso = unicos.length <= _maxPuntos ? 1 : (unicos.length / _maxPuntos).ceil();
  final sel = <PuntoDelMapa>[
    for (var i = 0; i < unicos.length; i += paso) unicos[i],
    if ((unicos.length - 1) % paso != 0) unicos.last,
  ];
  final c = cliente ?? http.Client();
  try {
    final r = await c
        .post(
          Uri.parse(_urlDelServicio),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'shape': [for (final p in sel) {'lat': p.lat, 'lon': p.lon}],
            'costing': 'pedestrian',
            'shape_match': 'map_snap',
            'trace_options': {'search_radius': 40, 'gps_accuracy': 20},
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final legs = (j['trip']?['legs'] as List?) ?? const [];
    final calles = <LatLng>[];
    for (final l in legs) {
      calles.addAll(decodificarPolyline6((l as Map)['shape'] as String));
    }
    return calles.length < 2 ? null : RecorridoAjustado(calles, sel.last.t);
  } catch (_) {
    return null;
  } finally {
    if (cliente == null) c.close();
  }
}
