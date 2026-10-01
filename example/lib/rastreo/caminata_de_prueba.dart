/// RECORRIDOS DE PRUEBA POR LAS CALLES REALES — a pie o en moto, desde donde está el teléfono.
///
/// Pedido de Juan (2026-09-30): «emular una moto, una vuelta hasta El Silencio y volver, que parezca
/// real». Se le pide a un enrutador (Valhalla; en producción el propio, `RASTREO_ENRUTADOR_URL`) la
/// ruta por calles y se remuestrea a UN PUNTO POR SEGUNDO con un modelo de velocidad creíble:
///   · a pie: 1,3 m/s parejo;
///   · en moto: 20-60 km/h según lo largo del tramo recto, acelerando y frenando (±1,5 m/s por s),
///     con una parada de semáforo de 25 s cada ~1,2 km y 60 s parado en el destino;
/// más un temblor de ~2 m como el GPS. 20 s parado al salir y `quietoMin` + 1 min al volver.
/// Herramienta de desarrollo: nada de esto va en el SDK.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'ajustar_a_calles.dart';

const _enrutador = String.fromEnvironment('RASTREO_ENRUTADOR_URL', defaultValue: 'https://valhalla1.openstreetmap.de/route');

/// El Silencio (Caracas): Plaza O'Leary. Un destino de prueba, nada más.
const elSilencio = LatLng(10.5037, -66.9172);

enum MedioDePrueba { aPie, moto }

/// `null` si el enrutador no contesta. Devuelve [lat, lon, v m/s, rumbo] por segundo.
Future<List<List<double>>?> recorridoDePrueba({
  required double lat,
  required double lon,
  required int quietoMin,
  required MedioDePrueba medio,
  LatLng? destino,
}) async {
  final origen = LatLng(lat, lon);
  final List<Map<String, double>> paradas;
  if (destino != null) {
    paradas = [
      {'lat': lat, 'lon': lon},
      {'lat': destino.latitude, 'lon': destino.longitude},
      {'lat': lat, 'lon': lon},
    ];
  } else {
    // a pie: una vuelta de ~1,5 km por dos puntos a ~300 m
    const dLat = 0.0027, dLon = 0.00275;
    paradas = [
      {'lat': lat, 'lon': lon},
      {'lat': lat - dLat, 'lon': lon + dLon},
      {'lat': lat - dLat * 1.3, 'lon': lon - dLon},
      {'lat': lat, 'lon': lon},
    ];
  }
  final c = http.Client();
  final tramos = <List<LatLng>>[]; // una lista de vértices por pata del viaje
  try {
    final r = await c
        .post(Uri.parse(_enrutador),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'locations': paradas,
              'costing': medio == MedioDePrueba.moto ? 'motorcycle' : 'pedestrian',
              'units': 'kilometers',
            }))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    for (final l in (j['trip']?['legs'] as List? ?? const [])) {
      tramos.add(decodificarPolyline6((l as Map)['shape'] as String));
    }
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
  if (tramos.isEmpty || tramos.every((t) => t.length < 2)) return null;

  final azar = math.Random(11);
  final temblorM = medio == MedioDePrueba.moto ? 2.5 : 1.5;
  double temblor() => (azar.nextDouble() * 2 - 1) * temblorM / 111320;
  const d = Distance();
  final pts = <List<double>>[];
  void parado(LatLng p, int seg) {
    for (var i = 0; i < seg; i++) {
      pts.add([p.latitude, p.longitude, 0, 0]);
    }
  }

  parado(origen, 20);
  var vActual = 0.0; // m/s
  var desdeSemaforo = 0.0;
  for (var k = 0; k < tramos.length; k++) {
    final calles = tramos[k];
    var sobrante = 0.0;
    for (var i = 1; i < calles.length; i++) {
      final a = calles[i - 1], b = calles[i];
      final largo = d.as(LengthUnit.Meter, a, b);
      if (largo <= 0) continue;
      final rumbo = (d.bearing(a, b) + 360) % 360;
      // la velocidad que «pide» este tramo: a pie siempre 1,3; en moto, más rápido cuanto más recto y largo
      final vMeta = medio == MedioDePrueba.aPie ? 1.3 : (15 + largo * 0.6).clamp(20, 60) / 3.6;
      var pos = sobrante;
      while (pos < largo) {
        // acelera o frena de a 1,5 m/s por segundo hacia la meta del tramo
        vActual += (vMeta - vActual).clamp(-1.5, 1.5);
        if (vActual < 0.5) vActual = 0.5;
        final f = pos / largo;
        final p = LatLng(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f);
        pts.add([p.latitude + temblor(), p.longitude + temblor(), vActual, rumbo]);
        pos += vActual;
        desdeSemaforo += vActual;
        if (medio == MedioDePrueba.moto && desdeSemaforo > 1200) {
          parado(p, 25); // semáforo
          vActual = 0.5;
          desdeSemaforo = 0;
        }
      }
      sobrante = pos - largo;
    }
    // al final de cada pata (el destino) se queda un minuto parado
    if (k < tramos.length - 1) {
      parado(calles.last, 60);
      vActual = 0.5;
    }
  }
  parado(origen, (quietoMin + 1) * 60);
  return pts;
}

/// Compatibilidad: la caminata de antes.
Future<List<List<double>>?> caminataDePrueba({required double lat, required double lon, required int quietoMin}) =>
    recorridoDePrueba(lat: lat, lon: lon, quietoMin: quietoMin, medio: MedioDePrueba.aPie);
