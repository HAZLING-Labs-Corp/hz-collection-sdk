/// EL MAPA DE «YO» — sólo de la app de ejemplo. Dibuja todo lo recorrido (el historial local)
/// con la línea coloreada por velocidad, el punto actual con su precisión y su antigüedad.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/generado/textos_de_rastreo.dart';
import 'historial_de_recorrido.dart';

class PantallaDelMapa extends StatefulWidget {
  const PantallaDelMapa({super.key, required this.historial, required this.rastreo});
  final HistorialDeRecorrido historial;
  final Rastreo? rastreo;

  @override
  State<PantallaDelMapa> createState() => _PantallaDelMapaState();
}

class _PantallaDelMapaState extends State<PantallaDelMapa> {
  final _mapa = MapController();
  StreamSubscription<void>? _sub;
  StreamSubscription<Position>? _yo;
  Position? _posicion;
  Timer? _reloj;
  bool _seguir = true;
  bool _mapaListo = false;

  /// Con miles de puntos la línea se simplifica: nunca más de esto en pantalla.
  static const _maxPuntosDibujados = 1500;

  // quieto · a pie · rápido — mismo corte que el visor de escritorio (0,5 y 3 m/s).
  static const _colorRuta = Color(0xFF3B6FD4);

  /// Saturación al 10 % y un poco más claro: un mapa de navegación sobrio, no un mapa de colores.
  static const _desaturar = ColorFilter.matrix(<double>[
    0.2126 * 0.9 + 0.1, 0.7152 * 0.9, 0.0722 * 0.9, 0, 18,
    0.2126 * 0.9, 0.7152 * 0.9 + 0.1, 0.0722 * 0.9, 0, 18,
    0.2126 * 0.9, 0.7152 * 0.9, 0.0722 * 0.9 + 0.1, 0, 18,
    0, 0, 0, 1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    _sub = widget.historial.cambios.listen((_) {
      if (!mounted) return;
      setState(() {});
      _centrarSiSigue();
    });
    unawaited(_seguirMiPosicion());
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _yo?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  /// El punto «aquí estoy» no depende de que el rastreo haya grabado algo: mientras el mapa está
  /// abierto, se escucha la posición del teléfono (en primer plano, sin costo de fondo).
  Future<void> _seguirMiPosicion() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return;
      final ultima = await Geolocator.getLastKnownPosition();
      if (mounted && ultima != null) {
        setState(() => _posicion = ultima);
        _centrarSiSigue();
      }
      _yo = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _posicion = pos);
        _centrarSiSigue();
      }, onError: (Object _) {});
    } catch (_) {}
  }

  void _centrarSiSigue() {
    final p = widget.historial.puntos;
    final pos = _posicion;
    if (!_seguir || !_mapaListo) return;
    if (pos != null) {
      _mapa.move(LatLng(pos.latitude, pos.longitude), _mapa.camera.zoom);
    } else if (p.isNotEmpty) {
      _mapa.move(LatLng(p.last.lat, p.last.lon), _mapa.camera.zoom);
    }
  }

  /// Una sola línea, como una ruta de navegación: el mapa no se llena de colores.
  Color _color(double v) => _colorRuta;

  /// Segmentos del mismo color, sobre una lista ya simplificada.
  List<Polyline> _lineas(List<PuntoDelMapa> pts) {
    if (pts.length < 2) return const [];
    final paso = pts.length <= _maxPuntosDibujados ? 1 : (pts.length / _maxPuntosDibujados).ceil();
    final sel = <PuntoDelMapa>[
      for (var i = 0; i < pts.length; i += paso) pts[i],
      if ((pts.length - 1) % paso != 0) pts.last,
    ];
    final out = <Polyline>[];
    var tramo = <LatLng>[LatLng(sel.first.lat, sel.first.lon)];
    var color = _color(sel.first.v);
    for (var i = 1; i < sel.length; i++) {
      final a = sel[i - 1], b = sel[i];
      final corteDeTramo = a.tramo != b.tramo || b.t - a.t > 20 * 60 * 1000;
      final c = _color(b.v);
      if (corteDeTramo || c != color) {
        if (tramo.length > 1) {
          out.add(Polyline(points: tramo, color: color, strokeWidth: 5, borderColor: Colors.white, borderStrokeWidth: 1.5, pattern: StrokePattern.solid()));
        }
        tramo = corteDeTramo ? <LatLng>[] : <LatLng>[LatLng(a.lat, a.lon)];
        color = c;
      }
      tramo.add(LatLng(b.lat, b.lon));
    }
    if (tramo.length > 1) {
      out.add(Polyline(points: tramo, color: color, strokeWidth: 5, borderColor: Colors.white, borderStrokeWidth: 1.5, pattern: StrokePattern.solid()));
    }
    return out;
  }

  String _antiguedad(TextosDeRastreo t, int ms) {
    final s = math.max(0, (DateTime.now().millisecondsSinceEpoch - ms) ~/ 1000);
    if (s < 60) return t.mapaHaceSeg(s);
    if (s < 3600) return t.mapaHaceMin(s ~/ 60);
    return t.mapaHaceHoras(s ~/ 3600);
  }

  @override
  Widget build(BuildContext context) {
    final t = TextosDeRastreo.of(context);
    final pts = widget.historial.puntos;
    final ultimo = pts.isEmpty ? null : pts.last;
    var metros = 0.0;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].tramo == pts[i - 1].tramo) metros += HistorialDeRecorrido.metros(pts[i - 1], pts[i]);
    }
    final dur = pts.length < 2 ? Duration.zero : Duration(milliseconds: pts.last.t - pts.first.t);
    final centro = ultimo == null ? const LatLng(10.4969, -66.8480) : LatLng(ultimo.lat, ultimo.lon);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.mapaTitulo),
        actions: [
          IconButton(
            tooltip: t.mapaBorrar,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.historial.borrar(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 17,
                    onMapReady: () {
                      _mapaListo = true;
                      _centrarSiSigue();
                    },
                    onPositionChanged: (_, porGesto) {
                      if (porGesto && _seguir) setState(() => _seguir = false);
                    },
                  ),
                  children: [
                    // Estilo de navegación: el mapa base se desatura (casi gris) para que no invada;
                    // las calles conservan sus nombres. (CARTO ya pide llave: se usa el mosaico de OSM.)
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.juanpush.android1',
                      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _desaturar, child: tile),
                    ),
                    PolylineLayer(polylines: _lineas(pts)),
                    if (_posicion != null || ultimo != null)
                      CircleLayer(circles: [
                        CircleMarker(
                          point: _posicion != null
                              ? LatLng(_posicion!.latitude, _posicion!.longitude)
                              : LatLng(ultimo!.lat, ultimo.lon),
                          radius: math.max(_posicion?.accuracy ?? ultimo!.acc, 3),
                          useRadiusInMeter: true,
                          color: const Color(0x332D5F8A),
                          borderColor: const Color(0xFF2D5F8A),
                          borderStrokeWidth: 1,
                        ),
                      ]),
                    MarkerLayer(markers: [
                      if (pts.isNotEmpty)
                        Marker(
                          point: LatLng(pts.first.lat, pts.first.lon),
                          width: 22,
                          height: 22,
                          child: const Icon(Icons.flag, color: Color(0xFF444B55), size: 22),
                        ),
                      if (_posicion != null || ultimo != null)
                        Marker(
                          point: _posicion != null
                              ? LatLng(_posicion!.latitude, _posicion!.longitude)
                              : LatLng(ultimo!.lat, ultimo.lon),
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B6FD4),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                    ]),
                    const RichAttributionWidget(
                      attributions: [TextSourceAttribution('© OpenStreetMap')],
                    ),
                  ],
                ),
                if (ultimo == null && _posicion == null)
                  Center(
                    child: Card(
                      child: Padding(padding: const EdgeInsets.all(16), child: Text(t.mapaSinPuntos)),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    tooltip: t.mapaSeguir,
                    backgroundColor: _seguir ? Theme.of(context).colorScheme.primary : null,
                    foregroundColor: _seguir ? Theme.of(context).colorScheme.onPrimary : null,
                    onPressed: () {
                      setState(() => _seguir = true);
                      _centrarSiSigue();
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 18, runSpacing: 4, children: [
                    Text(t.mapaDistancia(metros >= 1000 ? (metros / 1000).toStringAsFixed(2) : metros.toStringAsFixed(0), metros >= 1000 ? 'km' : 'm')),
                    Text(t.mapaDuracion(dur.inMinutes, dur.inSeconds % 60)),
                    Text(t.mapaPuntos(pts.length)),
                    if (ultimo != null) Text(t.mapaUltimo(_antiguedad(t, ultimo.t))),
                    if (ultimo != null && ultimo.mock) Text(t.mapaSimulado),
                  ]),
                  const SizedBox(height: 4),
                  FutureBuilder<DiagnosticoDeRastreo>(
                    future: widget.rastreo?.diagnostico(),
                    builder: (c, s) => s.hasData
                        ? Text(t.mapaLotes(s.data!.lotesAceptados, s.data!.lotesRechazados), style: Theme.of(context).textTheme.bodySmall)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
