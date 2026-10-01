/// LA CAMINATA DE PRUEBA — una vuelta a pie POR LAS CALLES REALES desde donde está el teléfono.
///
/// Pedido de Juan (2026-09-30): «haz una emulación desde mi punto con mi teléfono». Se le pide a un
/// enrutador (Valhalla, perfil a pie) una vuelta de ~1,5 km que sale de la posición actual, pasa por
/// dos puntos a ~300 m y vuelve; la geometría de las calles se remuestrea a un punto por segundo a
/// paso humano (1,3 m/s) con un temblor chico, como el GPS real. 20 s parado al salir y
/// `quietoMin` + 1 min parado al volver, para ver despertar y apagarse el GPS.
///
/// Es una herramienta de desarrollo (red externa, servidor público): nada de esto va en el SDK.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'ajustar_a_calles.dart';

const _enrutador = String.fromEnvironment('RASTREO_ENRUTADOR_URL', defaultValue: 'https://valhalla1.openstreetmap.de/route');
const _pasoMs = 1.3; // m/s, paso humano
const _temblorM = 1.5;

/// `null` si el enrutador no contesta. Devuelve [lat, lon, v m/s, rumbo] por segundo.
Future<List<List<double>>?> caminataDePrueba({required double lat, required double lon, required int quietoMin}) async {
  // ~300 m al sureste y ~300 m al suroeste (en grados, a esta latitud)
  const dLat = 0.0027, dLon = 0.00275;
  final paradas = [
    {'lat': lat, 'lon': lon},
    {'lat': lat - dLat, 'lon': lon + dLon},
    {'lat': lat - dLat * 1.3, 'lon': lon - dLon},
    {'lat': lat, 'lon': lon},
  ];
  final c = http.Client();
  List<LatLng> calles;
  try {
    final r = await c
        .post(Uri.parse(_enrutador),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'locations': paradas, 'costing': 'pedestrian', 'units': 'kilometers'}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    calles = <LatLng>[];
    for (final l in (j['trip']?['legs'] as List? ?? const [])) {
      calles.addAll(decodificarPolyline6((l as Map)['shape'] as String));
    }
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
  if (calles.length < 2) return null;

  final azar = math.Random(7);
  double temblor() => (azar.nextDouble() * 2 - 1) * _temblorM / 111320; // grados ~ metros
  final pts = <List<double>>[];
  for (var i = 0; i < 20; i++) {
    pts.add([lat, lon, 0, 0]);
  }
  const d = Distance();
  var sobrante = 0.0;
  for (var i = 1; i < calles.length; i++) {
    final a = calles[i - 1], b = calles[i];
    final largo = d.as(LengthUnit.Meter, a, b);
    if (largo <= 0) continue;
    final rumbo = (d.bearing(a, b) + 360) % 360;
    var pos = sobrante;
    while (pos < largo) {
      final f = pos / largo;
      pts.add([
        a.latitude + (b.latitude - a.latitude) * f + temblor(),
        a.longitude + (b.longitude - a.longitude) * f + temblor(),
        _pasoMs,
        rumbo,
      ]);
      pos += _pasoMs;
    }
    sobrante = pos - largo;
  }
  for (var i = 0; i < (quietoMin + 1) * 60; i++) {
    pts.add([lat, lon, 0, 0]);
  }
  return pts;
}
