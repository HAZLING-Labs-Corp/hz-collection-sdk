/// EL HISTORIAL LOCAL DEL RECORRIDO — sólo de la app de ejemplo, no del SDK.
///
/// La cola del SDK borra lo que ya se envió, así que no sirve para dibujar «todo lo recorrido».
/// Esta clase escucha los puntos que la captura entrega y los guarda aparte (un archivo en el
/// caché de la app, con techo), de modo que el mapa se ve aunque no haya red hacia la ingesta
/// y sobrevive a que la app se cierre. Es una ayuda de diagnóstico: el dato de verdad es el de
/// la ingesta.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hz_collection_sdk/hz_collection_sdk.dart';

class PuntoDelMapa {
  const PuntoDelMapa(this.t, this.lat, this.lon, this.acc, this.v, this.mock, this.tramo);
  final int t;
  final double lat;
  final double lon;
  final double acc;

  /// m/s
  final double v;
  final bool mock;
  final int tramo;
}

class HistorialDeRecorrido {
  HistorialDeRecorrido._(this._archivo);

  /// Techo de puntos guardados: a un punto cada 10 s son ~55 horas.
  static const techo = 20000;

  final File _archivo;
  final List<PuntoDelMapa> puntos = [];
  final _cambios = StreamController<void>.broadcast();
  StreamSubscription<EventoDeCaptura>? _sub;
  IOSink? _sink;
  int _escritos = 0;

  Stream<void> get cambios => _cambios.stream;

  static Future<HistorialDeRecorrido> abrir() async {
    final h = HistorialDeRecorrido._(File('${Directory.systemTemp.path}/recorrido_de_ejemplo.jsonl'));
    await h._cargar();
    return h;
  }

  Future<void> _cargar() async {
    if (await _archivo.exists()) {
      final lineas = await _archivo.readAsLines();
      for (final l in lineas.skip(math.max(0, lineas.length - techo))) {
        try {
          final j = jsonDecode(l) as List;
          puntos.add(PuntoDelMapa(j[0] as int, (j[1] as num).toDouble(), (j[2] as num).toDouble(),
              (j[3] as num).toDouble(), (j[4] as num).toDouble(), j[5] == 1, j[6] as int));
        } catch (_) {}
      }
    }
    _escritos = puntos.length;
    _sink = _archivo.openWrite(mode: FileMode.append);
  }

  /// Escucha los puntos de la captura. Se llama de nuevo si se cambia de captura.
  void escuchar(CapturaDeRastreo captura) {
    _sub?.cancel();
    _sub = captura.eventos.listen((e) {
      if (e is! PuntoCapturado) return;
      final p = e.punto;
      if (puntos.isNotEmpty && puntos.last.t == p.t) return;
      final n = PuntoDelMapa(p.t, p.lat, p.lon, p.acc, p.v, p.mock, e.tramo);
      puntos.add(n);
      _sink?.writeln(jsonEncode([n.t, n.lat, n.lon, n.acc, n.v, n.mock ? 1 : 0, n.tramo]));
      _escritos++;
      if (puntos.length > techo) puntos.removeRange(0, puntos.length - techo);
      if (_escritos > techo * 2) unawaited(_compactar());
      _cambios.add(null);
    });
  }

  Future<void> _compactar() async {
    await _sink?.flush();
    await _sink?.close();
    final s = StringBuffer();
    for (final n in puntos) {
      s.writeln(jsonEncode([n.t, n.lat, n.lon, n.acc, n.v, n.mock ? 1 : 0, n.tramo]));
    }
    await _archivo.writeAsString(s.toString());
    _sink = _archivo.openWrite(mode: FileMode.append);
    _escritos = puntos.length;
  }

  Future<void> borrar() async {
    puntos.clear();
    await _sink?.close();
    if (await _archivo.exists()) await _archivo.delete();
    _sink = _archivo.openWrite(mode: FileMode.append);
    _escritos = 0;
    _cambios.add(null);
  }

  Future<void> cerrar() async {
    await _sub?.cancel();
    await _sink?.close();
    await _cambios.close();
  }

  /// Metros entre dos puntos (haversine).
  static double metros(PuntoDelMapa a, PuntoDelMapa b) {
    const r = 6371000.0;
    double rad(double g) => g * math.pi / 180;
    final dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }
}
