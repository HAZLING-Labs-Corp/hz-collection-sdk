/// EL MAPA DE «YO» — sólo de la app de ejemplo. Calles en gris (el MISMO estilo vectorial de la
/// consola web), tu personita, la calle completa por la que fuiste (la cola que falta pegar, en el mismo azul).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../l10n/generado/textos_de_rastreo.dart';
import 'ajustar_a_calles.dart';
import 'estilo_de_calles.dart';
import 'historial_de_recorrido.dart';
import 'vehiculos.dart';

class PantallaDelMapa extends StatefulWidget {
  const PantallaDelMapa({super.key, required this.historial, required this.rastreo});
  final HistorialDeRecorrido historial;
  final Rastreo? rastreo;

  @override
  State<PantallaDelMapa> createState() => _PantallaDelMapaState();
}

class _PantallaDelMapaState extends State<PantallaDelMapa> {
  ml.MapController? _mapa;
  String? _estilo;
  StreamSubscription<void>? _sub;
  Position? _posicion;
  Timer? _reloj;
  bool _seguir = true;
  double _zoom = 16.5, _giroDelMapa = 0;

  /// PANTALLA COMPLETA (Juan, 2026-10-01): sin la barra de arriba, sin los datos de abajo y sin las
  /// barras del sistema; queda sólo el mapa con sus dos botones.
  bool _completa = false;
  void _alternarPantallaCompleta() {
    setState(() => _completa = !_completa);
    unawaited(SystemChrome.setEnabledSystemUIMode(_completa ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
  }
  RecorridoAjustado? _calles;
  bool _ajustando = false;
  int _ajustadoConPuntos = 0;

  /// el verde de la ruta, con borde blanco, como en las apps de viaje (Juan miró Yango, 2026-10-01);
  /// el mismo de la consola (`RUTA` en `capas-de-la-flota.ts`)
  static const _colorRuta = Color(0xFF1FB25A);

  /// La figura se DESLIZA del punto anterior al nuevo (el SDK graba cada 5-10 s rodando): sin esto
  /// saltaba de golpe y no se sentía en tiempo real (Juan, 2026-10-01).
  static const _deslizar = Duration(milliseconds: 1600);
  ml.Position? _animDesde, _animHasta;
  DateTime _animInicio = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _cuadros;

  void _moverFigura(ml.Position hasta) {
    final ahora = _dondeAnimado();
    if (_animHasta != null && _animHasta!.lng == hasta.lng && _animHasta!.lat == hasta.lat) return;
    _animDesde = ahora ?? hasta;
    _animHasta = hasta;
    _animInicio = DateTime.now();
    _cuadros?.cancel();
    _cuadros = Timer.periodic(const Duration(milliseconds: 33), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (DateTime.now().difference(_animInicio) >= _deslizar) t.cancel();
    });
  }

  ml.Position? _dondeAnimado() {
    final a = _animDesde, b = _animHasta;
    if (a == null || b == null) return b;
    final f = (DateTime.now().difference(_animInicio).inMilliseconds / _deslizar.inMilliseconds).clamp(0.0, 1.0);
    final e = Curves.easeInOut.transform(f);
    return ml.Position(a.lng + (b.lng - a.lng) * e, a.lat + (b.lat - a.lat) * e);
  }

  @override
  void initState() {
    super.initState();
    unawaited(archivoDelEstilo().then((e) {
      if (mounted) setState(() => _estilo = e);
    }));
    _sub = widget.historial.cambios.listen((_) {
      if (!mounted) return;
      setState(() {});
      _centrarSiSigue();
      unawaited(_ajustar());
    });
    unawaited(_ajustar());
    unawaited(_seguirMiPosicion());
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reloj?.cancel();
    _cuadros?.cancel();
    if (_completa) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  /// 🔴 EL MAPA NO ABRE SU PROPIO FLUJO DE GPS. En Android geolocator sólo sostiene UN flujo: abrir
  /// otro desde la pantalla CANCELA el del SDK, y el detector se queda sin lecturas precisas (medido
  /// el 2026-10-01 con la moto simulada: «detenido» a 25 km/h, lotes parados, línea recta en la
  /// consola). «Aquí estoy» sale de la última posición conocida al abrir y, después, del último punto
  /// que el SDK grabó (cada 5-10 s rodando).
  Future<void> _seguirMiPosicion() async {
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return;
      // la última conocida y, si el teléfono no tiene ninguna, UNA lectura suelta (no un flujo: el SDK
      // hace lo mismo para la presencia estando quieto). Sin esto el mapa abría sin la figura.
      final ultima = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)));
      if (mounted && widget.historial.puntos.isEmpty) {
        setState(() => _posicion = ultima);
        _centrarSiSigue();
      }
    } catch (_) {}
  }

  /// Pega el recorrido a las calles: al abrir y con CADA punto nuevo (un pedido a la vez). Antes era
  /// cada 6 y, mientras tanto, la cola cruda cortaba por dentro de las manzanas (Juan, 2026-10-01:
  /// «se salta las calles… después como que acomoda, pero no quiero que se vea dañado»).
  Future<void> _ajustar() async {
    final pts = widget.historial.puntos;
    if (_ajustando || pts.length < 3 || pts.length - _ajustadoConPuntos < 1) return;
    _ajustando = true;
    final n = pts.length;
    final r = await ajustarACalles(List.of(pts), medio: widget.rastreo?.configuracion.medio);
    _ajustando = false;
    if (!mounted) return;
    _ajustadoConPuntos = n;
    if (r != null) setState(() => _calles = r);
  }

  ml.Position? _donde() {
    final p = widget.historial.puntos;
    if (p.isNotEmpty) return ml.Position(p.last.lon, p.last.lat);
    final pos = _posicion;
    return pos == null ? null : ml.Position(pos.longitude, pos.latitude);
  }

  /// El rumbo para girar la figura: el del último punto grabado (si lo trae), si no el de la posición.
  double _rumbo() {
    final p = widget.historial.puntos;
    if (p.length >= 2) {
      final a = p[p.length - 2], b = p.last;
      final dy = b.lat - a.lat, dx = (b.lon - a.lon) * math.cos(a.lat * math.pi / 180);
      if (dx.abs() + dy.abs() > 1e-7) return (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
    }
    final h = _posicion?.heading ?? 0;
    return h < 0 ? 0 : h;
  }

  void _centrarSiSigue() {
    final d = _donde();
    if (!_seguir || d == null) return;
    _mapa?.animateCamera(center: d, nativeDuration: const Duration(milliseconds: 700));
  }

  /// La cola del GPS que todavía no se pegó a la calle, cortada por tramo (nunca une dos viajes con
  /// una recta). 🔴 La línea cruda NO se dibuja encima de la calle: con el teléfono quieto el GPS
  /// salta 10-25 m por lectura y, unida con rectas, se veía como una raya negra en zigzag (Juan,
  /// 2026-10-01). Lo que ya se pegó a la calle se ve sólo como la banda azul.
  /// Los puntos del último tramo que vienen DESPUÉS de la punta de la calle pegada.
  List<ml.Position> _despuesDeLaCalle(List<PuntoDelMapa> pts) {
    final calles = _calles?.calles;
    if (calles == null || calles.isEmpty || pts.isEmpty) return const [];
    final punta = calles.last;
    var ini = pts.length - 1;
    while (ini > 0 && pts[ini - 1].tramo == pts.last.tramo) {
      ini--;
    }
    var k = ini;
    var mejor = double.infinity;
    final cosLat = math.cos(punta.latitude * math.pi / 180);
    for (var i = ini; i < pts.length; i++) {
      final dy = pts[i].lat - punta.latitude, dx = (pts[i].lon - punta.longitude) * cosLat;
      final d = dx * dx + dy * dy;
      if (d <= mejor) {
        mejor = d;
        k = i;
      }
    }
    return [for (var i = k + 1; i < pts.length; i++) ml.Position(pts[i].lon, pts[i].lat)];
  }

  List<ml.LineString> _colaSinPegar(List<PuntoDelMapa> pts) {
    // con calle pegada no se dibuja nada crudo: la figura está en el último punto y la banda llega
    // hasta el penúltimo como mucho (un pedido por punto).
    if (_calles != null) return const [];
    const desde = 0;
    final out = <ml.LineString>[];
    var actual = <ml.Position>[];
    for (var i = desde; i < pts.length; i++) {
      if (actual.isNotEmpty && pts[i].tramo != pts[i - 1].tramo) {
        if (actual.length >= 2) out.add(ml.LineString(coordinates: actual));
        actual = <ml.Position>[];
      }
      actual.add(ml.Position(pts[i].lon, pts[i].lat));
    }
    if (actual.length >= 2) out.add(ml.LineString(coordinates: actual));
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
    final destino = _donde();
    if (destino != null) _moverFigura(destino);
    final donde = _dondeAnimado() ?? destino;
    final centro = destino ?? ml.Position(-66.8480, 10.4969);
    // 🔴 La banda SIEMPRE llega hasta la moto: lo pegado a la calle y, a continuación, lo medido que
    // todavía no se pegó (si el servicio de calles tarda o falla). Antes se quedaba atrás y «no
    // marcaba por dónde va» (Juan, 2026-10-01). Una sola línea, del mismo color.
    final banda = _calles == null
        ? const <ml.Position>[]
        : [for (final c in _calles!.calles) ml.Position(c.longitude, c.latitude), ..._despuesDeLaCalle(pts)];
    final capas = <ml.Layer>[
      if (_calles != null) ...[
        ml.PolylineLayer(
          polylines: [ml.LineString(coordinates: banda)],
          color: Colors.white,
          width: 10,
        ),
        ml.PolylineLayer(
          polylines: [ml.LineString(coordinates: banda)],
          color: _colorRuta,
          width: 6,
        ),
      ],
      // la cola que todavía no se pegó a la calle: mismo azul, sin raya oscura encima
      if (pts.length >= 2) ml.PolylineLayer(polylines: _colaSinPegar(pts), color: _colorRuta, width: 4),
    ];
    return Scaffold(
      appBar: _completa ? null : AppBar(
        title: Text(t.mapaTitulo),
        actions: [
          IconButton(tooltip: t.mapaPantallaCompleta, icon: const Icon(Icons.fullscreen), onPressed: _alternarPantallaCompleta),
          IconButton(tooltip: t.mapaBorrar, icon: const Icon(Icons.delete_outline), onPressed: () {
            setState(() => _calles = null);
            _ajustadoConPuntos = 0;
            widget.historial.borrar();
          }),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_estilo == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ml.MapLibreMap(
                    options: ml.MapOptions(initStyle: _estilo!, initCenter: centro, initZoom: 16.5, maxZoom: 19.5, minZoom: 9),
                    onMapCreated: (c) => _mapa = c,
                    onEvent: (e) {
                      // el vehículo crece con el zoom y su rumbo se corrige si el mapa está girado
                      if (e is ml.MapEventMoveCamera &&
                          ((e.camera.zoom - _zoom).abs() > 0.04 || (e.camera.bearing - _giroDelMapa).abs() > 0.5)) {
                        setState(() {
                          _zoom = e.camera.zoom;
                          _giroDelMapa = e.camera.bearing;
                        });
                      }
                      if (e is ml.MapEventStartMoveCamera && e.reason == ml.CameraChangeReason.apiGesture && _seguir) {
                        setState(() => _seguir = false);
                      }
                    },
                    layers: capas,
                    children: [
                      ml.WidgetLayer(markers: [
                        if (pts.isNotEmpty)
                          ml.Marker(
                            point: ml.Position(pts.first.lon, pts.first.lat),
                            size: const Size(26, 26),
                            child: const Icon(Icons.flag, color: Color(0xFF444B55), size: 26),
                          ),
                        if (donde != null && vehiculoDe(widget.rastreo?.configuracion.medio) != null)
                          // MOTO o CARRO: el vehículo visto desde arriba, del ancho de la calle, girando con el rumbo
                          ml.Marker(
                            point: donde,
                            size: Size.square(PintorDeVehiculo.lado * escalaPorZoom(_zoom)),
                            child: Transform.rotate(
                              angle: (_rumbo() - _giroDelMapa) * math.pi / 180,
                              child: CustomPaint(painter: PintorDeVehiculo(vehiculoDe(widget.rastreo?.configuracion.medio)!)),
                            ),
                          )
                        else if (donde != null)
                          // PERSONA: el muñequito en un círculo (con su foto, cuando el aparato sepa de quién es)
                          ml.Marker(
                            point: donde,
                            size: const Size(64, 64),
                            child: _FiguraDelMedio(
                              medio: widget.rastreo?.configuracion.medio,
                              rodando: widget.rastreo?.captura.estado != EstadoDeMovimiento.quieto && pts.isNotEmpty && pts.last.v > 0.5,
                              rumbo: _rumbo() - _giroDelMapa,
                            ),
                          ),
                      ]),
                    ],
                  ),
                if (ultimo == null && _posicion == null)
                  Center(child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(t.mapaSinPuntos)))),
                if (_completa)
                  Positioned(
                    right: 12,
                    top: MediaQuery.paddingOf(context).top + 12,
                    child: FloatingActionButton.small(
                      heroTag: 'pantalla-completa',
                      tooltip: t.mapaSalirPantallaCompleta,
                      onPressed: _alternarPantallaCompleta,
                      child: const Icon(Icons.fullscreen_exit),
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
          if (!_completa) SafeArea(
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

/// LA FIGURA DEL APARATO: un círculo con la imagen del medio (dato `rastreo.medio`: persona, bici,
/// dos ruedas, carro, bus), DERECHA para que se lea, y una flecha en el borde que gira con el
/// rumbo. Mirando hacia donde va: si va hacia el oeste, la imagen se voltea. Verde rodando, azul
/// quieto (Juan, 2026-10-01: «una motico en un círculo… igual que un carro o una personita»).
class _FiguraDelMedio extends StatelessWidget {
  const _FiguraDelMedio({required this.medio, required this.rodando, required this.rumbo});
  final String? medio;
  final bool rodando;
  final double rumbo;

  static IconData iconoDe(String? medio) => switch (medio) {
        'dosRuedas' => Icons.two_wheeler,
        'bici' => Icons.pedal_bike,
        'carro' => Icons.directions_car_filled,
        'bus' => Icons.directions_bus_filled,
        _ => Icons.directions_walk,
      };

  @override
  Widget build(BuildContext context) {
    final color = rodando ? const Color(0xFF2E9E5B) : const Color(0xFF3B6FD4);
    final haciaElOeste = rumbo > 180 && rumbo < 360;
    return Stack(alignment: Alignment.center, children: [
      if (rodando)
        Transform.rotate(
          angle: rumbo * math.pi / 180,
          child: CustomPaint(size: const Size(64, 64), painter: _PintorDeLaFlecha(color)),
        ),
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Transform.flip(flipX: rodando && haciaElOeste, child: Icon(iconoDe(medio), color: color, size: 28)),
      ),
    ]);
  }
}

class _PintorDeLaFlecha extends CustomPainter {
  const _PintorDeLaFlecha(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final punta = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx + 8, 10)
      ..lineTo(cx - 8, 10)
      ..close();
    canvas.drawPath(punta, Paint()..color = color);
    canvas.drawPath(punta, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _PintorDeLaFlecha old) => old.color != color;
}
